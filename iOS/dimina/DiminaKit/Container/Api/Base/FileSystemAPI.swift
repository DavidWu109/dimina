//
//  FileSystemAPI.swift
//  dimina
//
//  Created by David on 2026/3/30.
//

import Foundation

/**
 * FileSystemManager API
 * https://developers.weixin.qq.com/miniprogram/dev/api/file/wx.getFileSystemManager.html
 *
 * getFileSystemManager 是同步 API，返回文件系统管理器对象。
 * 后续的 readFile/writeFile/mkdir 等操作通过 Bridge 异步调用。
 */
public class FileSystemAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("getFileSystemManager", handler: getFileSystemManager)
        register("fsReadFile", handler: fsReadFile)
        register("fsWriteFile", handler: fsWriteFile)
        register("fsMkdir", handler: fsMkdir)
        register("fsRmdir", handler: fsRmdir)
        register("fsUnlink", handler: fsUnlink)
        register("fsStat", handler: fsStat)
        register("fsAccess", handler: fsAccess)
        register("fsReaddir", handler: fsReaddir)
        register("fsCopyFile", handler: fsCopyFile)
        register("fsRename", handler: fsRename)
    }

    private func getFileSystemManager(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["result": true]))
        return DMPAsyncResult()
    }

    private func fsReadFile(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let params = param.getMap()
        let filePath = params.getString(key: "filePath") ?? ""
        let encoding = params.getString(key: "encoding") ?? "utf8"

        guard !filePath.isEmpty else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "readFile:fail filePath is required")
            return DMPAsyncResult()
        }

        let resolvedPath = FileSystemAPI.resolvePath(filePath, appId: env.appId)

        DispatchQueue.global().async {
            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "readFile:fail no such file or directory")
                return
            }

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: resolvedPath))
                let result = DMPMap()

                if encoding == "base64" {
                    result.set("data", data.base64EncodedString())
                } else {
                    result.set("data", String(data: data, encoding: .utf8) ?? "")
                }

                DMPContainerApi.invokeSuccess(callback: callback, param: result)
            } catch {
                DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "readFile:fail \(error.localizedDescription)")
            }
        }

        return DMPAsyncResult()
    }

    private func fsWriteFile(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let params = param.getMap()
        let filePath = params.getString(key: "filePath") ?? ""
        let dataString = params.getString(key: "data") ?? ""
        let encoding = params.getString(key: "encoding") ?? "utf8"

        guard !filePath.isEmpty else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "writeFile:fail filePath is required")
            return DMPAsyncResult()
        }

        let resolvedPath = FileSystemAPI.resolvePath(filePath, appId: env.appId)

        DispatchQueue.global().async {
            do {
                let dirPath = (resolvedPath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

                let fileData: Data
                if encoding == "base64" {
                    fileData = Data(base64Encoded: dataString) ?? Data()
                } else {
                    fileData = dataString.data(using: .utf8) ?? Data()
                }

                try fileData.write(to: URL(fileURLWithPath: resolvedPath))
                DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
            } catch {
                DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "writeFile:fail \(error.localizedDescription)")
            }
        }

        return DMPAsyncResult()
    }

    private func fsMkdir(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let params = param.getMap()
        let dirPath = params.getString(key: "dirPath") ?? ""
        let recursive = params.get("recursive") as? Bool ?? false

        let resolvedPath = FileSystemAPI.resolvePath(dirPath, appId: env.appId)

        do {
            try FileManager.default.createDirectory(atPath: resolvedPath, withIntermediateDirectories: recursive)
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "mkdir:fail \(error.localizedDescription)")
        }

        return DMPAsyncResult()
    }

    private func fsRmdir(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let dirPath = param.getMap().getString(key: "dirPath") ?? ""
        let resolvedPath = FileSystemAPI.resolvePath(dirPath, appId: env.appId)

        do {
            try FileManager.default.removeItem(atPath: resolvedPath)
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "rmdir:fail \(error.localizedDescription)")
        }

        return DMPAsyncResult()
    }

    private func fsUnlink(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let filePath = param.getMap().getString(key: "filePath") ?? ""
        let resolvedPath = FileSystemAPI.resolvePath(filePath, appId: env.appId)

        do {
            try FileManager.default.removeItem(atPath: resolvedPath)
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "unlink:fail \(error.localizedDescription)")
        }

        return DMPAsyncResult()
    }

    private func fsStat(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let filePath = param.getMap().getString(key: "path") ?? ""
        let resolvedPath = FileSystemAPI.resolvePath(filePath, appId: env.appId)

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: resolvedPath)
            let result = DMPMap()
            result.set("size", attrs[.size] as? Int ?? 0)
            result.set("isDirectory", (attrs[.type] as? FileAttributeType) == .typeDirectory)
            result.set("isFile", (attrs[.type] as? FileAttributeType) == .typeRegular)
            result.set("lastModifiedTime", (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)

            let stats = DMPMap()
            stats.set("stats", result.toDictionary())
            DMPContainerApi.invokeSuccess(callback: callback, param: stats)
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "stat:fail \(error.localizedDescription)")
        }

        return DMPAsyncResult()
    }

    private func fsAccess(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let filePath = param.getMap().getString(key: "path") ?? ""
        let resolvedPath = FileSystemAPI.resolvePath(filePath, appId: env.appId)

        if FileManager.default.fileExists(atPath: resolvedPath) {
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "access:fail no such file or directory")
        }

        return DMPAsyncResult()
    }

    private func fsReaddir(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let dirPath = param.getMap().getString(key: "dirPath") ?? ""
        let resolvedPath = FileSystemAPI.resolvePath(dirPath, appId: env.appId)

        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: resolvedPath)
            let result = DMPMap()
            result.set("files", files)
            DMPContainerApi.invokeSuccess(callback: callback, param: result)
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "readdir:fail \(error.localizedDescription)")
        }

        return DMPAsyncResult()
    }

    private func fsCopyFile(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let params = param.getMap()
        let srcPath = params.getString(key: "srcPath") ?? ""
        let destPath = params.getString(key: "destPath") ?? ""

        let resolvedSrc = FileSystemAPI.resolvePath(srcPath, appId: env.appId)
        let resolvedDest = FileSystemAPI.resolvePath(destPath, appId: env.appId)

        do {
            let destDir = (resolvedDest as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: resolvedSrc, toPath: resolvedDest)
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "copyFile:fail \(error.localizedDescription)")
        }

        return DMPAsyncResult()
    }

    private func fsRename(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let params = param.getMap()
        let oldPath = params.getString(key: "oldPath") ?? ""
        let newPath = params.getString(key: "newPath") ?? ""

        let resolvedOld = FileSystemAPI.resolvePath(oldPath, appId: env.appId)
        let resolvedNew = FileSystemAPI.resolvePath(newPath, appId: env.appId)

        do {
            try FileManager.default.moveItem(atPath: resolvedOld, toPath: resolvedNew)
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "rename:fail \(error.localizedDescription)")
        }

        return DMPAsyncResult()
    }

    // MARK: - 路径解析

    /// 将小程序路径（wx:// 或相对路径）解析为沙箱绝对路径
    private static func resolvePath(_ path: String, appId: String) -> String {
        if path.hasPrefix("/") || path.hasPrefix("file://") {
            return path.replacingOccurrences(of: "file://", with: "")
        }

        // wx://usr/ 或 wxfile://usr/ 前缀 → 用户文件目录
        if path.hasPrefix("wx://usr/") || path.hasPrefix("wxfile://usr/") {
            let relativePath = path
                .replacingOccurrences(of: "wx://usr/", with: "")
                .replacingOccurrences(of: "wxfile://usr/", with: "")
            return DMPSandboxManager.appStoreResourceDirectoryPath(appId: appId) + "/" + relativePath
        }

        // wx://tmp/ 前缀 → 临时文件目录
        if path.hasPrefix("wx://tmp/") || path.hasPrefix("wxfile://tmp/") {
            let relativePath = path
                .replacingOccurrences(of: "wx://tmp/", with: "")
                .replacingOccurrences(of: "wxfile://tmp/", with: "")
            return DMPSandboxManager.appTmpResourceDirectoryPath(appId: appId) + "/" + relativePath
        }

        // 默认作为相对路径处理
        return DMPSandboxManager.appBundlePath(appId) + "/" + path
    }
}
