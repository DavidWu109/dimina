//
//  DMPDeveloperArchiveInstaller.swift
//  Dimina
//
//  Atomic installer for developer-preview ZIP snapshots.
//

import Foundation

public enum DMPDeveloperArchiveInstaller {
    private static let maxArchiveBytes: Int64 = 256 * 1_024 * 1_024
    private static let maxExpandedBytes: Int64 = 512 * 1_024 * 1_024
    private static let maxExpandedEntries = 50_000
    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 5 * 60
        return URLSession(configuration: configuration)
    }()

    public static func install(
        bundleURL: URL,
        targetAppId: String,
        versionCode: Int
    ) async throws {
        guard isAllowedBundleURL(bundleURL), !targetAppId.isEmpty else {
            throw DMPDeveloperPreviewError.invalidURL
        }

        let data = try await download(bundleURL)
        let fileManager = FileManager.default
        let working = fileManager.temporaryDirectory.appendingPathComponent(
            "DMPDeveloperArchive-\(UUID().uuidString)",
            isDirectory: true
        )
        let archive = working.appendingPathComponent("preview.zip")
        let extracted = working.appendingPathComponent("extracted", isDirectory: true)
        let normalized = working.appendingPathComponent("normalized", isDirectory: true)
        defer { try? fileManager.removeItem(at: working) }

        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        try data.write(to: archive, options: .atomic)
        guard DMPFileUtil.unzipFile(at: archive.path, to: extracted.path) else {
            throw DMPDeveloperPreviewError.installationFailed("failed to unzip preview archive")
        }

        try validateExtractedTree(extracted)
        try normalize(extracted: extracted, destination: normalized)
        try validate(normalized)
        try installAtomically(normalized, targetAppId: targetAppId, versionCode: versionCode)
    }

    public static func isAllowedBundleURL(_ url: URL) -> Bool {
        guard url.user == nil,
              url.password == nil,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    private static func download(_ url: URL) async throws -> Data {
        let result: (Data, URLResponse)
        if #available(iOS 15.0, *) {
            result = try await urlSession.data(from: url)
        } else {
            result = try await withCheckedThrowingContinuation { continuation in
                urlSession.dataTask(with: url) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, let response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: DMPDeveloperPreviewError.invalidResponse)
                    }
                }.resume()
            }
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let responseURL = response.url,
              isAllowedBundleURL(responseURL),
              responseURL.host?.lowercased() == url.host?.lowercased(),
              response.expectedContentLength <= maxArchiveBytes,
              Int64(data.count) <= maxArchiveBytes else {
            throw DMPDeveloperPreviewError.invalidResponse
        }
        return data
    }

    private static func normalize(extracted: URL, destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let source = try bundleRoot(in: extracted)
        let sourceMain = source.appendingPathComponent("main", isDirectory: true)
        if isCompleteMainDirectory(sourceMain) {
            try moveContents(from: source, to: destination)
        } else if isCompleteMainDirectory(source) {
            let main = destination.appendingPathComponent("main", isDirectory: true)
            try fileManager.createDirectory(at: main, withIntermediateDirectories: true)
            try moveContents(from: source, to: main)
        } else {
            throw DMPDeveloperPreviewError.installationFailed(
                "missing main/app-config.json or main/logic.js"
            )
        }

        let resourceRoot = destination.appendingPathComponent("resources", isDirectory: true)
        try fileManager.createDirectory(
            at: resourceRoot.appendingPathComponent("tmp", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: resourceRoot.appendingPathComponent("store", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    /// Developer tools commonly wrap the snapshot in one arbitrary directory.
    /// Unwrap only directory-only shells; never guess through mixed content.
    private static func bundleRoot(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        var candidate = directory
        for _ in 0..<3 {
            if isCompleteMainDirectory(candidate)
                || isCompleteMainDirectory(candidate.appendingPathComponent("main")) {
                return candidate
            }
            let children = try fileManager.contentsOfDirectory(
                at: candidate,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            guard children.count == 1,
                  let only = children.first,
                  (try only.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
                return candidate
            }
            candidate = only
        }
        return candidate
    }

    private static func isCompleteMainDirectory(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(
            atPath: directory.appendingPathComponent("app-config.json").path
        ) && fileManager.fileExists(
            atPath: directory.appendingPathComponent("logic.js").path
        )
    }

    private static func moveContents(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        for item in try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ) {
            try fileManager.moveItem(
                at: item,
                to: destination.appendingPathComponent(item.lastPathComponent)
            )
        }
    }

    private static func validate(_ root: URL) throws {
        let main = root.appendingPathComponent("main", isDirectory: true)
        guard isCompleteMainDirectory(main) else {
            throw DMPDeveloperPreviewError.installationFailed("invalid preview bundle")
        }
    }

    private static func validateExtractedTree(_ root: URL) throws {
        let fileManager = FileManager.default
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw DMPDeveloperPreviewError.installationFailed("failed to inspect preview archive")
        }

        var entryCount = 0
        var expandedBytes: Int64 = 0
        for case let item as URL in enumerator {
            entryCount += 1
            guard entryCount <= maxExpandedEntries else {
                throw DMPDeveloperPreviewError.installationFailed("preview archive has too many files")
            }
            let values = try item.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw DMPDeveloperPreviewError.installationFailed("symbolic links are not allowed")
            }
            if values.isRegularFile == true {
                expandedBytes += Int64(values.fileSize ?? 0)
                guard expandedBytes <= maxExpandedBytes else {
                    throw DMPDeveloperPreviewError.installationFailed("preview archive is too large")
                }
            }
        }
        if let enumerationError {
            throw DMPDeveloperPreviewError.installationFailed(
                "failed to inspect preview archive: \(enumerationError.localizedDescription)"
            )
        }
    }

    private static func installAtomically(
        _ staging: URL,
        targetAppId: String,
        versionCode: Int
    ) throws {
        let fileManager = FileManager.default
        let target = URL(
            fileURLWithPath: DMPSandboxManager.appBundlePath(
                targetAppId,
                versionCode: versionCode
            ),
            isDirectory: true
        )
        let parent = target.deletingLastPathComponent()
        let backup = parent.appendingPathComponent(
            ".\(target.lastPathComponent).preview-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
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
            throw DMPDeveloperPreviewError.installationFailed(error.localizedDescription)
        }
    }
}
