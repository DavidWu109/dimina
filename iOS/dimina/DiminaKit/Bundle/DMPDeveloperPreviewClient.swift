//
//  DMPDeveloperPreviewClient.swift
//  Dimina
//
//  Debug-only transport for QDMP live device previews.
//

import CommonCrypto
import Foundation

public struct DMPDeveloperPreviewSession {
    fileprivate let manifestURL: URL
    fileprivate let targetAppId: String
    fileprivate let versionCode: Int
    fileprivate let revision: Int
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

    private weak var app: DMPApp?
    private let session: DMPDeveloperPreviewSession
    private var revision: Int
    private var updateTask: Task<Void, Never>?

    private init(session: DMPDeveloperPreviewSession, app: DMPApp) {
        self.session = session
        self.revision = session.revision
        self.app = app
    }

    /// Downloads and atomically installs the first QDMP snapshot before the
    /// mini app launches. The returned session can then be attached to DMPApp
    /// so subsequent style/full updates arrive automatically.
    public static func prepare(
        manifestURL: URL,
        targetAppId: String,
        versionCode: Int
    ) async throws -> DMPDeveloperPreviewSession {
        let manifest = try await fetchManifest(from: manifestURL)
        try await installFullSnapshot(
            manifest,
            manifestURL: manifestURL,
            targetAppId: targetAppId,
            versionCode: versionCode
        )
        return DMPDeveloperPreviewSession(
            manifestURL: manifestURL,
            targetAppId: targetAppId,
            versionCode: versionCode,
            revision: manifest.revision
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
                let manifest = try await Self.fetchManifest(from: session.manifestURL)
                let event = try await Self.waitForUpdate(
                    manifest: manifest,
                    manifestURL: session.manifestURL,
                    after: revision
                )
                guard let event, event.revision > revision else {
                    retryDelay = 300_000_000
                    continue
                }

                let updatedManifest = try await Self.fetchManifest(from: session.manifestURL)
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
                        versionCode: session.versionCode
                    )
                    await app?.applyDeveloperStyleUpdate(revision: updatedManifest.revision)
                } else {
                    try await Self.installFullSnapshot(
                        updatedManifest,
                        manifestURL: session.manifestURL,
                        targetAppId: session.targetAppId,
                        versionCode: session.versionCode
                    )
                    await app?.applyUpdate()
                }
                revision = updatedManifest.revision
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

    private static func fetchManifest(from url: URL) async throws -> Manifest {
        let (data, response) = try await request(url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.protocolVersion == supportedProtocolVersion else {
            throw DMPDeveloperPreviewError.unsupportedProtocol(manifest.protocolVersion)
        }
        guard manifest.revision > 0, !manifest.files.isEmpty else {
            throw DMPDeveloperPreviewError.invalidManifest("empty revision or file list")
        }
        return manifest
    }

    private static func waitForUpdate(
        manifest: Manifest,
        manifestURL: URL,
        after revision: Int
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
        let (data, response) = try await request(url)
        guard let http = response as? HTTPURLResponse else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        if http.statusCode == 204 {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        return try JSONDecoder().decode(UpdateEvent.self, from: data)
    }

    private static func installFullSnapshot(
        _ manifest: Manifest,
        manifestURL: URL,
        targetAppId: String,
        versionCode: Int
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
                let data = try await download(file, manifestURL: manifestURL)
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
        versionCode: Int
    ) async throws {
        let styles = manifest.files.filter { $0.path.lowercased().hasSuffix(".css") }
        guard !styles.isEmpty else {
            throw DMPDeveloperPreviewError.invalidManifest("style update contains no CSS")
        }
        let fileManager = FileManager.default
        let target = URL(
            fileURLWithPath: DMPSandboxManager.appBundlePath(
                targetAppId,
                versionCode: versionCode
            ),
            isDirectory: true
        )
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DiminaStylePreview-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for file in styles {
            try Task.checkCancellation()
            let temporary = try confinedURL(root: staging, relativePath: file.path)
            let data = try await download(file, manifestURL: manifestURL)
            try fileManager.createDirectory(
                at: temporary.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: temporary, options: .atomic)
        }

        for file in styles {
            let temporary = try confinedURL(root: staging, relativePath: file.path)
            let destination = try confinedURL(root: target, relativePath: file.path)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        }
    }

    private static func download(_ file: ManifestFile, manifestURL: URL) async throws -> Data {
        let url = try resolveURL(file.url, relativeTo: manifestURL)
        let (data, response) = try await request(url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw DMPDeveloperPreviewError.invalidFile(file.path)
        }
        guard data.count == file.size, sha256(data) == file.sha256.lowercased() else {
            throw DMPDeveloperPreviewError.checksumMismatch(file.path)
        }
        return data
    }

    private static func request(_ url: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: url) { data, response, error in
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

    private static func resolveURL(_ value: String, relativeTo manifestURL: URL) throws -> URL {
        guard let url = URL(string: value, relativeTo: manifestURL)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host == manifestURL.host,
              url.port == manifestURL.port else {
            throw DMPDeveloperPreviewError.invalidURL
        }
        return url
    }

    private static func confinedURL(root: URL, relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\0"),
              !relativePath.split(separator: "/").contains("..") else {
            throw DMPDeveloperPreviewError.invalidFile(relativePath)
        }
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
        let size: Int
        let sha256: String
        let url: String
    }

    private struct UpdateEvent: Decodable {
        let revision: Int
        let styleOnly: Bool
    }
}
