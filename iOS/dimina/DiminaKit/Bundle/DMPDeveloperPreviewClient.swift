//
//  DMPDeveloperPreviewClient.swift
//  Dimina
//
//  Debug-only transport for QDMP live device previews.
//

import CommonCrypto
import Foundation

public struct DMPDeveloperPreviewLimits {
    public let maxManifestBytes: Int
    public let maxFileCount: Int
    public let maxFileBytes: Int64
    public let maxTotalBytes: Int64

    public init(
        maxManifestBytes: Int = 2 * 1_024 * 1_024,
        maxFileCount: Int = 4_096,
        maxFileBytes: Int64 = 32 * 1_024 * 1_024,
        maxTotalBytes: Int64 = 256 * 1_024 * 1_024
    ) {
        self.maxManifestBytes = maxManifestBytes
        self.maxFileCount = maxFileCount
        self.maxFileBytes = maxFileBytes
        self.maxTotalBytes = maxTotalBytes
    }
}

public struct DMPDeveloperPreviewSession {
    fileprivate let manifestURL: URL
    fileprivate let expectedAppId: String
    fileprivate let targetAppId: String
    fileprivate let versionCode: Int
    fileprivate let revision: Int
    fileprivate let cssPaths: Set<String>
    fileprivate let limits: DMPDeveloperPreviewLimits
}

public enum DMPDeveloperPreviewError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unsupportedProtocol(Int)
    case invalidManifest(String)
    case invalidFile(String)
    case checksumMismatch(String)
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "预览地址无效"
        case .invalidResponse:
            return "QDMP 预览服务响应无效"
        case .unsupportedProtocol(let version):
            return "不支持的 QDMP 预览协议版本：\(version)"
        case .invalidManifest(let reason):
            return "QDMP 预览清单无效：\(reason)"
        case .invalidFile(let path):
            return "QDMP 预览文件无效：\(path)"
        case .checksumMismatch(let path):
            return "QDMP 预览文件校验失败：\(path)"
        case .installationFailed(let reason):
            return "QDMP 预览资源安装失败：\(reason)"
        }
    }
}

public final class DMPDeveloperPreviewClient {
    private static let supportedProtocolVersion = 1
    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 5 * 60
        return URLSession(configuration: configuration)
    }()

    private weak var app: DMPApp?
    private let session: DMPDeveloperPreviewSession
    private var revision: Int
    private var currentCSSPaths: Set<String>
    private var updateTask: Task<Void, Never>?

    private init(session: DMPDeveloperPreviewSession, app: DMPApp) {
        self.session = session
        self.revision = session.revision
        self.currentCSSPaths = session.cssPaths
        self.app = app
    }

    /// Downloads and atomically installs the first QDMP snapshot before the
    /// mini app launches. The returned session can then be attached to DMPApp
    /// so subsequent style/full updates arrive automatically.
    public static func prepare(
        manifestURL: URL,
        expectedAppId: String,
        targetAppId: String,
        versionCode: Int,
        limits: DMPDeveloperPreviewLimits = DMPDeveloperPreviewLimits()
    ) async throws -> DMPDeveloperPreviewSession {
        guard origin(of: manifestURL) != nil else {
            throw DMPDeveloperPreviewError.invalidURL
        }
        let manifest = try await fetchManifest(
            from: manifestURL,
            expectedAppId: expectedAppId,
            limits: limits
        )
        try await installFullSnapshot(
            manifest,
            manifestURL: manifestURL,
            targetAppId: targetAppId,
            versionCode: versionCode,
            limits: limits
        )
        return DMPDeveloperPreviewSession(
            manifestURL: manifestURL,
            expectedAppId: expectedAppId,
            targetAppId: targetAppId,
            versionCode: versionCode,
            revision: manifest.revision,
            cssPaths: cssPaths(in: manifest),
            limits: limits
        )
    }

    static func attach(session: DMPDeveloperPreviewSession, to app: DMPApp)
        -> DMPDeveloperPreviewClient
    {
        return DMPDeveloperPreviewClient(session: session, app: app)
    }

    func start() {
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            await self?.listenForUpdates()
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    deinit {
        updateTask?.cancel()
    }

    private func listenForUpdates() async {
        var retryDelay: UInt64 = 300_000_000
        while !Task.isCancelled {
            do {
                let manifest = try await Self.fetchManifest(
                    from: session.manifestURL,
                    expectedAppId: session.expectedAppId,
                    limits: session.limits
                )
                let event = try await Self.waitForUpdate(
                    manifest: manifest,
                    manifestURL: session.manifestURL,
                    after: revision,
                    limits: session.limits
                )
                guard let event, event.revision > revision else {
                    retryDelay = 300_000_000
                    continue
                }

                let updatedManifest = try await Self.fetchManifest(
                    from: session.manifestURL,
                    expectedAppId: session.expectedAppId,
                    limits: session.limits
                )
                guard updatedManifest.revision >= event.revision else {
                    throw DMPDeveloperPreviewError.invalidManifest(
                        "manifest revision \(updatedManifest.revision) is behind event \(event.revision)"
                    )
                }

                // The manifest endpoint may advance again between the wait
                // response and this fetch. In that case the event's styleOnly
                // flag no longer describes the fetched snapshot, so use the
                // safe full-update path instead of potentially skipping JS.
                let canApplyStyleOnly = event.styleOnly
                    && updatedManifest.revision == event.revision
                if canApplyStyleOnly {
                    try await Self.installStyles(
                        updatedManifest,
                        manifestURL: session.manifestURL,
                        targetAppId: session.targetAppId,
                        versionCode: session.versionCode,
                        previousCSSPaths: currentCSSPaths,
                        limits: session.limits
                    )
                    await app?.applyDeveloperStyleUpdate(revision: updatedManifest.revision)
                } else {
                    try await Self.installFullSnapshot(
                        updatedManifest,
                        manifestURL: session.manifestURL,
                        targetAppId: session.targetAppId,
                        versionCode: session.versionCode,
                        limits: session.limits
                    )
                    await app?.applyUpdate()
                }
                revision = updatedManifest.revision
                currentCSSPaths = Self.cssPaths(in: updatedManifest)
                retryDelay = 300_000_000
            } catch is CancellationError {
                return
            } catch {
                DMPLog.bundle.warn("developer preview update failed: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: retryDelay)
                retryDelay = min(retryDelay * 2, 4_800_000_000)
            }
        }
    }

    private static func fetchManifest(
        from url: URL,
        expectedAppId: String,
        limits: DMPDeveloperPreviewLimits
    ) async throws -> Manifest {
        let (data, response) = try await request(
            url,
            maxBytes: Int64(limits.maxManifestBytes)
        )
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.protocolVersion == supportedProtocolVersion else {
            throw DMPDeveloperPreviewError.unsupportedProtocol(manifest.protocolVersion)
        }
        try validateManifest(
            manifest,
            manifestURL: url,
            expectedAppId: expectedAppId,
            limits: limits
        )
        return manifest
    }

    private static func waitForUpdate(
        manifest: Manifest,
        manifestURL: URL,
        after revision: Int,
        limits: DMPDeveloperPreviewLimits
    ) async throws -> UpdateEvent? {
        guard var components = URLComponents(
            url: try resolveURL(manifest.waitUrl, relativeTo: manifestURL),
            resolvingAgainstBaseURL: false
        ) else {
            throw DMPDeveloperPreviewError.invalidURL
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "after" }
        items.append(URLQueryItem(name: "after", value: String(revision)))
        components.queryItems = items
        guard let url = components.url else {
            throw DMPDeveloperPreviewError.invalidURL
        }
        let (data, response) = try await request(
            url,
            maxBytes: Int64(limits.maxManifestBytes)
        )
        guard let http = response as? HTTPURLResponse else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        if http.statusCode == 204 {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        let event = try JSONDecoder().decode(UpdateEvent.self, from: data)
        guard event.revision > revision else {
            throw DMPDeveloperPreviewError.invalidManifest(
                "update revision \(event.revision) is not newer than \(revision)"
            )
        }
        return event
    }

    private static func installFullSnapshot(
        _ manifest: Manifest,
        manifestURL: URL,
        targetAppId: String,
        versionCode: Int,
        limits: DMPDeveloperPreviewLimits
    ) async throws {
        let fileManager = FileManager.default
        let target = URL(
            fileURLWithPath: DMPSandboxManager.appBundlePath(
                targetAppId,
                versionCode: versionCode
            ),
            isDirectory: true
        )
        let parent = target.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(
            ".\(target.lastPathComponent).preview-\(UUID().uuidString)",
            isDirectory: true
        )
        let backup = parent.appendingPathComponent(
            ".\(target.lastPathComponent).backup-\(UUID().uuidString)",
            isDirectory: true
        )

        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for file in manifest.files {
                try Task.checkCancellation()
                let destination = try confinedURL(root: staging, relativePath: file.path)
                let data = try await download(
                    file,
                    manifestURL: manifestURL,
                    limits: limits
                )
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: destination, options: .atomic)
            }
            try validateSnapshot(staging)

            if fileManager.fileExists(atPath: target.path) {
                try fileManager.moveItem(at: target, to: backup)
            }
            do {
                try fileManager.moveItem(at: staging, to: target)
                try? fileManager.removeItem(at: backup)
            } catch {
                if !fileManager.fileExists(atPath: target.path),
                   fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: target)
                }
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private static func installStyles(
        _ manifest: Manifest,
        manifestURL: URL,
        targetAppId: String,
        versionCode: Int,
        previousCSSPaths: Set<String>,
        limits: DMPDeveloperPreviewLimits
    ) async throws {
        let styles = manifest.files.filter { $0.path.lowercased().hasSuffix(".css") }
        let nextCSSPaths = Set(styles.map(\.path))
        let removedCSSPaths = previousCSSPaths.subtracting(nextCSSPaths)
        let fileManager = FileManager.default
        let target = URL(
            fileURLWithPath: DMPSandboxManager.appBundlePath(
                targetAppId,
                versionCode: versionCode
            ),
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: target.path) else {
            throw DMPDeveloperPreviewError.installationFailed("preview bundle is missing")
        }
        let parent = target.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(
            ".\(target.lastPathComponent).style-preview-\(UUID().uuidString)",
            isDirectory: true
        )
        let backup = parent.appendingPathComponent(
            ".\(target.lastPathComponent).style-backup-\(UUID().uuidString)",
            isDirectory: true
        )

        try fileManager.copyItem(at: target, to: staging)
        do {
            for file in styles {
                try Task.checkCancellation()
                let destination = try confinedURL(root: staging, relativePath: file.path)
                let data = try await download(
                    file,
                    manifestURL: manifestURL,
                    limits: limits
                )
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: destination, options: .atomic)
            }

            for path in removedCSSPaths {
                let obsoleteFile = try confinedURL(root: staging, relativePath: path)
                if fileManager.fileExists(atPath: obsoleteFile.path) {
                    try fileManager.removeItem(at: obsoleteFile)
                }
            }
            try validateSnapshot(staging)

            try fileManager.moveItem(at: target, to: backup)
            do {
                try fileManager.moveItem(at: staging, to: target)
                try? fileManager.removeItem(at: backup)
            } catch {
                if !fileManager.fileExists(atPath: target.path),
                   fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: target)
                }
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private static func download(
        _ file: ManifestFile,
        manifestURL: URL,
        limits: DMPDeveloperPreviewLimits
    ) async throws -> Data {
        let url = try resolveURL(file.url, relativeTo: manifestURL)
        let (data, response) = try await request(url, maxBytes: limits.maxFileBytes)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw DMPDeveloperPreviewError.invalidFile(file.path)
        }
        guard Int64(data.count) == file.size,
              sha256(data) == file.sha256.lowercased() else {
            throw DMPDeveloperPreviewError.checksumMismatch(file.path)
        }
        return data
    }

    private static func request(
        _ url: URL,
        maxBytes: Int64
    ) async throws -> (Data, URLResponse) {
        guard maxBytes > 0 else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        let request = URLRequest(url: url)
        let result: (Data, URLResponse)
        if #available(iOS 15.0, *) {
            result = try await urlSession.data(for: request)
        } else {
            result = try await withCheckedThrowingContinuation { continuation in
                urlSession.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(
                            throwing: DMPDeveloperPreviewError.invalidResponse
                        )
                        return
                    }
                    continuation.resume(returning: (data, response))
                }.resume()
            }
        }
        let (data, response) = result
        if response.expectedContentLength > maxBytes || Int64(data.count) > maxBytes {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        return (data, response)
    }

    private static func validateManifest(
        _ manifest: Manifest,
        manifestURL: URL,
        expectedAppId: String,
        limits: DMPDeveloperPreviewLimits
    ) throws {
        guard !expectedAppId.isEmpty, manifest.appId == expectedAppId else {
            throw DMPDeveloperPreviewError.invalidManifest(
                "manifest appId \(manifest.appId) does not match \(expectedAppId)"
            )
        }
        guard manifest.revision > 0, !manifest.files.isEmpty else {
            throw DMPDeveloperPreviewError.invalidManifest("empty revision or file list")
        }
        guard limits.maxManifestBytes > 0,
              limits.maxFileCount > 0,
              limits.maxFileBytes > 0,
              limits.maxTotalBytes > 0,
              manifest.files.count <= limits.maxFileCount else {
            throw DMPDeveloperPreviewError.invalidManifest("resource limits exceeded")
        }

        var paths = Set<String>()
        var totalBytes: Int64 = 0
        for file in manifest.files {
            try validateRelativePath(file.path)
            guard paths.insert(file.path).inserted else {
                throw DMPDeveloperPreviewError.invalidManifest(
                    "duplicate file path \(file.path)"
                )
            }
            guard file.size >= 0,
                  file.size <= limits.maxFileBytes,
                  totalBytes <= limits.maxTotalBytes - file.size else {
                throw DMPDeveloperPreviewError.invalidManifest(
                    "file size limit exceeded for \(file.path)"
                )
            }
            totalBytes += file.size
            guard isValidSHA256(file.sha256) else {
                throw DMPDeveloperPreviewError.invalidManifest(
                    "invalid sha256 for \(file.path)"
                )
            }
            _ = try resolveURL(file.url, relativeTo: manifestURL)
        }
        _ = try resolveURL(manifest.waitUrl, relativeTo: manifestURL)
    }

    private static func validateRelativePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !path.contains("\\"),
              !path.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DMPDeveloperPreviewError.invalidFile(path)
        }
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static func origin(of url: URL) -> Origin? {
        guard url.user == nil,
              url.password == nil,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        return Origin(
            scheme: scheme,
            host: host,
            port: url.port ?? (scheme == "https" ? 443 : 80)
        )
    }

    private static func cssPaths(in manifest: Manifest) -> Set<String> {
        return Set(
            manifest.files.lazy
                .map(\.path)
                .filter { $0.lowercased().hasSuffix(".css") }
        )
    }

    private static func resolveURL(_ value: String, relativeTo manifestURL: URL) throws -> URL {
        guard let url = URL(string: value, relativeTo: manifestURL)?.absoluteURL,
              let candidateOrigin = origin(of: url),
              let manifestOrigin = origin(of: manifestURL),
              candidateOrigin == manifestOrigin else {
            throw DMPDeveloperPreviewError.invalidURL
        }
        return url
    }

    private static func confinedURL(root: URL, relativePath: String) throws -> URL {
        try validateRelativePath(relativePath)
        let standardizedRoot = root.standardizedFileURL
        let candidate = standardizedRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        guard candidate.path == standardizedRoot.path
                || candidate.path.hasPrefix(standardizedRoot.path + "/") else {
            throw DMPDeveloperPreviewError.invalidFile(relativePath)
        }
        return candidate
    }

    private static func validateSnapshot(_ root: URL) throws {
        let required = ["main/app-config.json", "main/logic.js"]
        for path in required {
            let url = try confinedURL(root: root, relativePath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DMPDeveloperPreviewError.installationFailed("missing \(path)")
            }
        }
    }

    private static func sha256(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct Manifest: Decodable {
        let protocolVersion: Int
        let revision: Int
        let appId: String
        let name: String
        let files: [ManifestFile]
        let waitUrl: String
    }

    private struct ManifestFile: Decodable {
        let path: String
        let size: Int64
        let sha256: String
        let url: String
    }

    private struct UpdateEvent: Decodable {
        let revision: Int
        let styleOnly: Bool
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int
    }
}
