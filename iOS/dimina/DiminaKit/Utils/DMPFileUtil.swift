//
//  DMPFileUtil.swift
//  dimina
//
//  Created by Lehem on 2025/4/17.
//

import CommonCrypto
import Foundation
import ZIPFoundation

public class DMPFileUtil {

    public static let DMPFileURLScheme: String = "difile"
    private static let fileURLSchemeLock = NSLock()
    private static var fileURLSchemes: [String: String] = [:]

    private init() {}

    static func setFileURLScheme(_ scheme: String, forAppId appId: String) {
        let normalized = normalizedFileURLScheme(scheme) ?? DMPFileURLScheme
        fileURLSchemeLock.lock()
        fileURLSchemes[appId] = normalized
        fileURLSchemeLock.unlock()
    }

    static func removeFileURLScheme(forAppId appId: String) {
        fileURLSchemeLock.lock()
        fileURLSchemes.removeValue(forKey: appId)
        fileURLSchemeLock.unlock()
    }

    static func fileURLScheme(forAppId appId: String) -> String {
        fileURLSchemeLock.lock()
        defer { fileURLSchemeLock.unlock() }
        return fileURLSchemes[appId] ?? DMPFileURLScheme
    }

    private static func normalizedFileURLScheme(_ scheme: String) -> String? {
        let value = scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              value.range(of: "^[a-z][a-z0-9+.-]*$", options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    @discardableResult
    public static func unzipFile(
        at zipPath: String, to destinationPath: String, overwrite: Bool = true
    ) -> Bool {
        do {
            if overwrite && FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(atPath: destinationPath)
            }

            try FileManager.default.createDirectory(
                atPath: destinationPath, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.unzipItem(
                at: URL(fileURLWithPath: zipPath),
                to: URL(fileURLWithPath: destinationPath)
            )
            DMPLogger.debug("成功解压文件: \(zipPath) 到 \(destinationPath)")
            return true
        } catch {
            DMPLogger.debug("解压文件过程中发生错误: \(error)")
            return false
        }
    }

    @discardableResult
    public static func copyContents(
        from sourcePath: String, to destinationPath: String, excludeItems: [String] = []
    ) -> Bool {
        do {
            // 确保目标目录存在
            try FileManager.default.createDirectory(
                atPath: destinationPath, withIntermediateDirectories: true, attributes: nil)

            // 获取源目录下的所有内容
            let contents = try FileManager.default.contentsOfDirectory(atPath: sourcePath)

            // 遍历复制文件
            for item in contents {
                // 跳过需要排除的文件
                if excludeItems.contains(item) {
                    continue
                }

                let sourceItemPath = (sourcePath as NSString).appendingPathComponent(item)
                let destinationItemPath = (destinationPath as NSString).appendingPathComponent(item)

                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: sourceItemPath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        // 如果是目录，递归复制
                        try FileManager.default.createDirectory(
                            atPath: destinationItemPath, withIntermediateDirectories: true,
                            attributes: nil)
                        if !copyContents(from: sourceItemPath, to: destinationItemPath) {
                            return false
                        }
                    } else {
                        // 如果是文件，直接复制
                        if FileManager.default.fileExists(atPath: destinationItemPath) {
                            try FileManager.default.removeItem(atPath: destinationItemPath)
                        }
                        try FileManager.default.copyItem(
                            atPath: sourceItemPath, toPath: destinationItemPath)
                    }
                }
            }

            return true
        } catch {
            DMPLogger.debug("复制文件过程中发生错误: \(error)")
            return false
        }
    }

    @discardableResult
    public static func removeItem(at path: String) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
                return true
            }
            return false
        } catch {
            DMPLogger.debug("删除文件失败: \(error)")
            return false
        }
    }

    @discardableResult
    public static func createDirectory(at path: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            DMPLogger.debug("创建目录失败: \(error)")
            return false
        }
    }

    public static func fileExists(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    public static func readJsonFile(at path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func loadJSONFromFile(filePath: String) -> [String: Any]? {
        guard
            let fileURL = URL(fileURLWithPath: filePath).isFileURL
                ? URL(fileURLWithPath: filePath) : nil
        else {
            DMPLogger.debug("无效的文件路径")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        } catch {
            DMPLogger.debug("加载 JSON 文件失败: \(error)")
            return nil
        }
    }

    public static func vPathFromSandboxPath(sandboxPath: String, appId: String) -> String {
        let scheme = fileURLScheme(forAppId: appId)
        let storeDirectory: String = DMPSandboxManager.appStoreResourceDirectoryPath(appId: appId)
        if sandboxPath.hasPrefix(storeDirectory) {
            let relativePath: String = sandboxPath.replacingOccurrences(of: storeDirectory, with: "")
            return "\(scheme)://usr\(relativePath)"
        }
        let resourceDirectory: String = DMPSandboxManager.appTmpResourceDirectoryPath(appId: appId)
        let relativePath: String = sandboxPath
            .replacingOccurrences(of: resourceDirectory, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let vPath: String = "\(scheme)://\(relativePath)"
        return vPath
    }

    public static func sandboxPathFromVPath(from vPath: String, appId: String, version: String? = nil) -> String? {
        guard let components = URLComponents(string: vPath),
              let scheme = components.scheme?.lowercased(),
              scheme == DMPFileURLScheme || scheme == fileURLScheme(forAppId: appId),
              components.user == nil,
              components.password == nil else {
            return nil
        }

        let host = components.host ?? ""
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host == "usr" {
            return confinedPath(
                rootPath: DMPSandboxManager.appStoreResourceDirectoryPath(appId: appId),
                relativePath: path
            )
        }

        let resourceDirectory: String
        if let version = version {
            let appBundlePath = DMPSandboxManager.appBundlePath(appId)
            let versionPath = (appBundlePath as NSString).appendingPathComponent(version)
            resourceDirectory = (versionPath as NSString).appendingPathComponent("main")
        } else {
            resourceDirectory = DMPSandboxManager.appTmpResourceDirectoryPath(appId: appId)
        }

        let relativePath = ([host, path].filter { !$0.isEmpty }).joined(separator: "/")
        return confinedPath(rootPath: resourceDirectory, relativePath: relativePath)
    }

    /// Resolve a relative path while guaranteeing that the final filesystem
    /// location remains under `rootPath`, including after dot-segment and
    /// symlink resolution.
    public static func confinedPath(rootPath: String, relativePath: String) -> String? {
        guard !rootPath.isEmpty,
              !relativePath.contains("\0") else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let trimmedPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetURL = rootURL
            .appendingPathComponent(trimmedPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let root = rootURL.path
        let target = targetURL.path
        guard target == root || target.hasPrefix(root + "/") else {
            return nil
        }
        return target
    }

}

// MARK: - String MD5 扩展
extension String {
    var dmp_sha256: String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        _ = data.withUnsafeBytes { buffer in
            CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
