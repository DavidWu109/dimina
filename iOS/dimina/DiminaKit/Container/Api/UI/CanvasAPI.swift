//
//  CanvasAPI.swift
//  dimina
//

import Foundation

/**
 * UI - Canvas API
 *
 * Canvas drawing runs in the render WebView. The container persists the
 * exported image and returns a Dimina virtual path to the mini program.
 */
public final class CanvasAPI: DMPContainerApi {
    private static let maxImageBytes = 32 * 1024 * 1024
    private static let maxBase64Bytes = (maxImageBytes * 4 / 3) + 8
    private static let maxPendingExportsPerApp = 2

    private static let queueLock = NSLock()
    private static var queues: [String: DispatchQueue] = [:]
    private static var jobs: [String: [UUID: ExportJob]] = [:]
    private static var generations: [String: Int] = [:]

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("saveCanvasTempFile", handler: saveCanvasTempFile)
    }

    private func saveCanvasTempFile(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let map = param.getMap()
        guard let dataURL = map.getString(key: "dataURL"), !dataURL.isEmpty else {
            return failure(callback, message: "dataURL is empty")
        }
        guard let fileType = Self.normalizedFileType(map.getString(key: "fileType")) else {
            return failure(callback, message: "fileType is invalid")
        }
        guard Self.isValidAppId(env.appId) else {
            return failure(callback, message: "appId is invalid")
        }
        guard let base64 = Self.canvasBase64(from: dataURL, fileType: fileType),
              let base64ByteCount = Self.validatedBase64ByteCount(base64) else {
            return failure(callback, message: "dataURL is invalid or oversized")
        }
        guard let job = Self.reserveExport(
            appId: env.appId,
            byteCount: base64ByteCount,
            payload: base64
        ) else {
            return failure(callback, message: "too many pending exports")
        }

        let workItem = DispatchWorkItem {
            guard let payload = Self.beginExport(job) else { return }
            defer { Self.finishExport(job) }
            let outcome = Self.writeTempFile(
                base64: payload,
                fileType: fileType,
                appId: env.appId
            )
            DispatchQueue.main.async {
                Self.deliver(
                    outcome,
                    appId: env.appId,
                    generation: job.generation,
                    callback: callback
                )
            }
        }
        Self.attachExport(job, workItem: workItem)
        job.queue.async(execute: workItem)
        return DMPAsyncResult()
    }

    static func normalizedFileType(_ fileType: String?) -> String? {
        switch fileType?.lowercased() {
        case nil, "", "png":
            return "png"
        case "jpg", "jpeg":
            return "jpg"
        default:
            return nil
        }
    }

    static func canvasBase64(from value: String, fileType: String) -> String? {
        guard value.prefix(5).lowercased() == "data:" else { return value }
        guard let separator = value.firstIndex(of: ",") else { return nil }

        let header = value[..<separator].lowercased()
        let mime: String
        switch header {
        case "data:image/png;base64":
            mime = "png"
        case "data:image/jpg;base64", "data:image/jpeg;base64":
            mime = "jpg"
        default:
            return nil
        }
        guard mime == fileType else { return nil }
        return String(value[value.index(after: separator)...])
    }

    static func validatedBase64ByteCount(_ value: String) -> Int? {
        var count = 0
        var paddingCount = 0
        var sawPadding = false

        for byte in value.utf8 {
            count += 1
            guard count <= maxBase64Bytes else { return nil }
            switch byte {
            case 65...90, 97...122, 48...57, 43, 47:
                guard !sawPadding else { return nil }
            case 61:
                sawPadding = true
                paddingCount += 1
                guard paddingCount <= 2 else { return nil }
            default:
                return nil
            }
        }
        guard count > 0, count.isMultiple(of: 4) else { return nil }
        return count
    }

    static func matchesImageType(_ data: Data, fileType: String) -> Bool {
        let bytes = [UInt8](data.prefix(8))
        if fileType == "png" {
            return bytes == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        }
        return bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
    }

    static func isValidAppId(_ appId: String) -> Bool {
        guard !appId.isEmpty, appId != ".", appId != ".." else { return false }
        return appId.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    static func clearApp(_ appId: String) {
        queueLock.lock()
        generations[appId] = (generations[appId] ?? 0) + 1
        let queuedJobs = (jobs[appId] ?? [:]).values.filter { !$0.started }
        for job in queuedJobs {
            job.cancelled = true
            job.payload = nil
            job.workItem?.cancel()
            jobs[appId]?.removeValue(forKey: job.id)
        }
        if jobs[appId]?.isEmpty == true {
            jobs.removeValue(forKey: appId)
        }
        if jobs[appId] == nil {
            queues.removeValue(forKey: appId)
        }
        queueLock.unlock()
    }

    private final class ExportJob {
        let id = UUID()
        let appId: String
        let queue: DispatchQueue
        let generation: Int
        let byteCount: Int
        var payload: String?
        var started = false
        var cancelled = false
        var workItem: DispatchWorkItem?

        init(
            appId: String,
            queue: DispatchQueue,
            generation: Int,
            byteCount: Int,
            payload: String
        ) {
            self.appId = appId
            self.queue = queue
            self.generation = generation
            self.byteCount = byteCount
            self.payload = payload
        }
    }

    private enum WriteOutcome {
        case success(URL)
        case failure(String)
    }

    private static func reserveExport(
        appId: String,
        byteCount: Int,
        payload: String
    ) -> ExportJob? {
        queueLock.lock()
        defer { queueLock.unlock() }
        let appJobs = jobs[appId] ?? [:]
        let pendingBytes = appJobs.values.reduce(0) { $0 + $1.byteCount }
        guard appJobs.count < maxPendingExportsPerApp,
              pendingBytes + byteCount <= maxPendingExportsPerApp * maxBase64Bytes else {
            return nil
        }
        let queue = queues[appId] ?? DispatchQueue(
            label: "com.didi.dimina.canvas.export.\(appId)",
            qos: .userInitiated
        )
        queues[appId] = queue
        let job = ExportJob(
            appId: appId,
            queue: queue,
            generation: generations[appId] ?? 0,
            byteCount: byteCount,
            payload: payload
        )
        jobs[appId, default: [:]][job.id] = job
        return job
    }

    private static func attachExport(_ job: ExportJob, workItem: DispatchWorkItem) {
        queueLock.lock()
        let active = jobs[job.appId]?[job.id] === job && !job.cancelled
        if active {
            job.workItem = workItem
        }
        queueLock.unlock()
        if !active { workItem.cancel() }
    }

    private static func beginExport(_ job: ExportJob) -> String? {
        queueLock.lock()
        defer { queueLock.unlock() }
        guard jobs[job.appId]?[job.id] === job, !job.cancelled else { return nil }
        job.started = true
        defer { job.payload = nil }
        return job.payload
    }

    private static func finishExport(_ job: ExportJob) {
        queueLock.lock()
        defer { queueLock.unlock() }
        job.payload = nil
        jobs[job.appId]?.removeValue(forKey: job.id)
        if jobs[job.appId]?.isEmpty == true {
            jobs.removeValue(forKey: job.appId)
        }
    }

    private static func shouldDeliver(appId: String, generation: Int) -> Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        return generations[appId] ?? 0 == generation
    }

    private static func writeTempFile(
        base64: String,
        fileType: String,
        appId: String
    ) -> WriteOutcome {
        guard let imageData = Data(base64Encoded: base64),
              !imageData.isEmpty,
              imageData.count <= maxImageBytes,
              matchesImageType(imageData, fileType: fileType) else {
            return .failure("image data is invalid")
        }

        let sandboxURL = URL(
            fileURLWithPath: DMPSandboxManager.sandboxPath(),
            isDirectory: true
        ).standardizedFileURL.resolvingSymlinksInPath()
        let appURL = sandboxURL
            .appendingPathComponent(appId, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard !sandboxURL.path.isEmpty,
              appURL.path.hasPrefix(sandboxURL.path + "/") else {
            return .failure("sandbox path is invalid")
        }
        let directoryURL = appURL
            .appendingPathComponent("resources", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
        let fileName = "canvas_\(UUID().uuidString.lowercased()).\(fileType)"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try imageData.write(to: fileURL, options: .atomic)
            return .success(fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return .failure(error.localizedDescription)
        }
    }

    private static func deliver(
        _ outcome: WriteOutcome,
        appId: String,
        generation: Int,
        callback: DMPBridgeCallback?
    ) {
        guard shouldDeliver(appId: appId, generation: generation) else {
            if case .success(let fileURL) = outcome {
                try? FileManager.default.removeItem(at: fileURL)
            }
            return
        }

        switch outcome {
        case .success(let fileURL):
            let result = DMPMap()
            result.set(
                "tempFilePath",
                DMPFileUtil.vPathFromSandboxPath(sandboxPath: fileURL.path, appId: appId)
            )
            result.set("errMsg", "canvasToTempFilePath:ok")
            DMPContainerApi.invokeSuccess(callback: callback, param: result)
        case .failure(let message):
            invokeFailure(callback: callback, message: message)
        }
    }

    private func failure(
        _ callback: DMPBridgeCallback?,
        message: String
    ) -> DMPAPIResult {
        Self.invokeFailure(callback: callback, message: message)
        return DMPAsyncResult()
    }

    private static func invokeFailure(callback: DMPBridgeCallback?, message: String) {
        DMPContainerApi.invokeFailure(
            callback: callback,
            param: nil,
            errMsg: "canvasToTempFilePath:fail \(message)"
        )
    }
}
