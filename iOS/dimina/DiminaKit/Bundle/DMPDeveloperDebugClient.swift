//
//  DMPDeveloperDebugClient.swift
//  Dimina
//
//  Developer-tool WebSocket channel (`/__debug`).
//

import Foundation
import UIKit

public struct DMPDeveloperDebugSession {
    fileprivate let bundleURL: URL
    fileprivate let debugURL: URL
    fileprivate let targetAppId: String
    fileprivate let versionCode: Int
}

public final class DMPDeveloperDebugClient: NSObject {
    private weak var app: DMPApp?
    private let session: DMPDeveloperDebugSession
    private let lock = NSLock()
    private var socket: URLSessionWebSocketTask?
    private var runTask: Task<Void, Never>?
    private var isStarted = false
    private var isReloading = false
    private var hasPendingReload = false
    private var pendingLogs: [[String: Any]] = []

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private init(session: DMPDeveloperDebugSession, app: DMPApp) {
        self.session = session
        self.app = app
        super.init()
    }

    public static func prepare(
        bundleURL: URL,
        debugURL: URL,
        targetAppId: String,
        versionCode: Int
    ) async throws -> DMPDeveloperDebugSession {
        guard isValidDebugURL(debugURL, for: bundleURL) else {
            throw DMPDeveloperPreviewError.invalidURL
        }
        try await DMPDeveloperArchiveInstaller.install(
            bundleURL: bundleURL,
            targetAppId: targetAppId,
            versionCode: versionCode
        )
        return DMPDeveloperDebugSession(
            bundleURL: bundleURL,
            debugURL: debugURL,
            targetAppId: targetAppId,
            versionCode: versionCode
        )
    }

    public static func isValidDebugURL(_ debugURL: URL, for bundleURL: URL) -> Bool {
        guard DMPDeveloperArchiveInstaller.isAllowedBundleURL(bundleURL),
              debugURL.user == nil,
              debugURL.password == nil,
              let scheme = debugURL.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme),
              debugURL.path == "/__debug",
              debugURL.host?.lowercased() == bundleURL.host?.lowercased() else {
            return false
        }
        return true
    }

    static func attach(session: DMPDeveloperDebugSession, to app: DMPApp)
        -> DMPDeveloperDebugClient {
        return DMPDeveloperDebugClient(session: session, app: app)
    }

    func start() {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }
        isStarted = true
        lock.unlock()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        attachLogSources()
        beginConnectionLoop()
    }

    func attachLogSources() {
        DMPEngineLog.delegate = self
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.app?.render?.setLoggerDelegate(self)
        }
    }

    func stop() {
        lock.lock()
        isStarted = false
        let task = runTask
        runTask = nil
        let currentSocket = socket
        socket = nil
        pendingLogs.removeAll()
        lock.unlock()

        task?.cancel()
        currentSocket?.cancel(with: .goingAway, reason: nil)
        NotificationCenter.default.removeObserver(self)
        if DMPEngineLog.delegate === self {
            DMPEngineLog.delegate = nil
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.app?.render?.setLoggerDelegate(nil)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        runTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    @objc private func applicationDidEnterBackground() {
        pauseConnection()
    }

    @objc private func applicationDidBecomeActive() {
        lock.lock()
        let shouldResume = isStarted && runTask == nil
        lock.unlock()
        if shouldResume {
            beginConnectionLoop()
        }
    }

    private func beginConnectionLoop() {
        lock.lock()
        guard isStarted, runTask == nil else {
            lock.unlock()
            return
        }
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.connectionLoop()
        }
        runTask = task
        lock.unlock()
    }

    private func pauseConnection() {
        lock.lock()
        let task = runTask
        runTask = nil
        let currentSocket = socket
        socket = nil
        lock.unlock()
        task?.cancel()
        currentSocket?.cancel(with: .goingAway, reason: nil)
    }

    private func connectionLoop() async {
        var retryDelay: UInt64 = 500_000_000
        while !Task.isCancelled {
            let webSocket = urlSession.webSocketTask(with: session.debugURL)
            setSocket(webSocket)
            webSocket.resume()
            let heartbeat = Task { [weak self, weak webSocket] in
                guard let self, let webSocket else { return }
                await self.heartbeatLoop(webSocket)
            }
            do {
                try await sendDeviceConnected(using: webSocket)
                try await flushPendingLogs(using: webSocket)
                retryDelay = 500_000_000
                try await receiveLoop(webSocket)
            } catch is CancellationError {
                heartbeat.cancel()
                webSocket.cancel(with: .goingAway, reason: nil)
                clearSocket(webSocket)
                return
            } catch {
                DMPLog.bundle.warn("developer debug socket disconnected: \(error.localizedDescription)")
            }
            heartbeat.cancel()
            webSocket.cancel(with: .goingAway, reason: nil)
            clearSocket(webSocket)
            guard !Task.isCancelled else { return }
            let jitter = UInt64.random(in: 0...250_000_000)
            try? await Task.sleep(nanoseconds: retryDelay + jitter)
            retryDelay = min(retryDelay * 2, 8_000_000_000)
        }
    }

    private func heartbeatLoop(_ webSocket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await sendJSON([
                    "type": "ping",
                    "ts": timestamp(),
                ], using: webSocket)
            } catch {
                return
            }
        }
    }

    private func receiveLoop(_ webSocket: URLSessionWebSocketTask) async throws {
        while !Task.isCancelled {
            let message = try await receive(using: webSocket)
            let data: Data
            switch message {
            case .string(let text):
                guard let value = text.data(using: .utf8) else { continue }
                data = value
            case .data:
                // The developer protocol is JSON over UTF-8 text frames. Ignore
                // binary frames so arbitrary bytes never reach the JSON parser.
                continue
            @unknown default:
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            switch type {
            case "ping":
                try await sendJSON([
                    "type": "pong",
                    "ts": json["ts"] ?? timestamp(),
                ], using: webSocket)
            case "notify" where isReloadNotification(json["payload"]):
                scheduleReload()
            default:
                break
            }
        }
    }

    private func isReloadNotification(_ payload: Any?) -> Bool {
        if let value = payload as? String {
            return value == "reload"
        }
        guard let map = payload as? [String: Any] else { return false }
        return (map["type"] as? String) == "reload"
            || (map["event"] as? String) == "reload"
            || (map["name"] as? String) == "reload"
    }

    private func scheduleReload() {
        lock.lock()
        if isReloading {
            hasPendingReload = true
            lock.unlock()
            return
        }
        isReloading = true
        lock.unlock()

        Task { [weak self] in
            guard let self else { return }
            while true {
                do {
                    try await DMPDeveloperArchiveInstaller.install(
                        bundleURL: self.session.bundleURL,
                        targetAppId: self.session.targetAppId,
                        versionCode: self.session.versionCode
                    )
                    await self.app?.applyUpdate()
                    if let currentSocket = self.currentSocket() {
                        try? await self.sendDeviceConnected(using: currentSocket)
                    }
                } catch {
                    self.enqueueLog(
                        level: "error",
                        module: "native",
                        message: "reload failed: \(error.localizedDescription)"
                    )
                }

                if self.finishReloadIteration() {
                    continue
                }
                return
            }
        }
    }

    private func sendDeviceConnected(using webSocket: URLSessionWebSocketTask) async throws {
        let info = Bundle.main.infoDictionary
        try await sendJSON([
            "type": "notify",
            "payload": [
                "type": "deviceConnected",
                "event": "deviceConnected",
                "deviceName": UIDevice.current.name,
                "os": "iOS \(UIDevice.current.systemVersion)",
                "appVersion": info?["CFBundleShortVersionString"] as? String ?? "unknown",
                "sdkVersion": DiminaVersion.sdkVersion,
            ],
            "ts": timestamp(),
        ], using: webSocket)
    }

    private func enqueueLog(level: String, module: String, message: String) {
        let trimmed = String(message.prefix(8_192))
        let payload: [String: Any] = [
            "type": "log",
            "payload": [
                "level": level,
                "module": module,
                "message": trimmed,
            ],
            "ts": timestamp(),
        ]
        lock.lock()
        guard let currentSocket = socket else {
            pendingLogs.append(payload)
            if pendingLogs.count > 200 {
                pendingLogs.removeFirst(pendingLogs.count - 200)
            }
            lock.unlock()
            return
        }
        lock.unlock()
        Task { [weak self, weak currentSocket] in
            guard let self, let currentSocket else { return }
            try? await self.sendJSON(payload, using: currentSocket)
        }
    }

    private func flushPendingLogs(using webSocket: URLSessionWebSocketTask) async throws {
        let logs = takePendingLogs()
        for log in logs {
            try await sendJSON(log, using: webSocket)
        }
    }

    private func finishReloadIteration() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasPendingReload {
            hasPendingReload = false
            return true
        }
        isReloading = false
        return false
    }

    private func takePendingLogs() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        let logs = pendingLogs
        pendingLogs.removeAll()
        return logs
    }

    private func setSocket(_ newSocket: URLSessionWebSocketTask) {
        lock.lock()
        socket = newSocket
        lock.unlock()
    }

    private func clearSocket(_ oldSocket: URLSessionWebSocketTask) {
        lock.lock()
        if socket === oldSocket {
            socket = nil
        }
        lock.unlock()
    }

    private func currentSocket() -> URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        return socket
    }

    private func timestamp() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private func sendJSON(
        _ json: [String: Any],
        using webSocket: URLSessionWebSocketTask
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        if #available(iOS 15.0, *) {
            try await webSocket.send(.string(text))
        } else {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                webSocket.send(.string(text)) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    private func receive(using webSocket: URLSessionWebSocketTask) async throws
        -> URLSessionWebSocketTask.Message {
        if #available(iOS 15.0, *) {
            return try await webSocket.receive()
        }
        return try await withCheckedThrowingContinuation { continuation in
            webSocket.receive { result in
                continuation.resume(with: result)
            }
        }
    }
}

extension DMPDeveloperDebugClient: DMPWebViewLoggerDelegate {
    public func webViewDidLog(webViewId: Int, level: DMPLogLevel, message: String) {
        let mappedLevel: String
        switch level {
        case .error:
            mappedLevel = "error"
        case .warn, .network, .resource:
            mappedLevel = "warn"
        case .info:
            mappedLevel = "info"
        case .log:
            mappedLevel = "log"
        }
        enqueueLog(level: mappedLevel, module: "render", message: message)
    }
}

extension DMPDeveloperDebugClient: DMPEngineLogDelegate {
    func engineDidLog(level: LogLevel, message: String) {
        let mappedLevel: String
        switch level {
        case .log: mappedLevel = "log"
        case .info: mappedLevel = "info"
        case .warn: mappedLevel = "warn"
        case .error: mappedLevel = "error"
        }
        enqueueLog(level: mappedLevel, module: "service", message: message)
    }
}
