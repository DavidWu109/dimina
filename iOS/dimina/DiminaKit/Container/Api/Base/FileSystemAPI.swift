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

    private static let GET_FILE_SYSTEM_MANAGER = "getFileSystemManager"
    private static let FS_READ_FILE = "fsReadFile"
    private static let FS_WRITE_FILE = "fsWriteFile"
    private static let FS_MKDIR = "fsMkdir"
    private static let FS_RMDIR = "fsRmdir"
    private static let FS_UNLINK = "fsUnlink"
    private static let FS_STAT = "fsStat"
    private static let FS_ACCESS = "fsAccess"
    private static let FS_READ_DIR = "fsReaddir"
    private static let FS_COPY_FILE = "fsCopyFile"
    private static let FS_RENAME = "fsRename"

    // MARK: - getFileSystemManager（同步，返回确认）

    @BridgeMethod(GET_FILE_SYSTEM_MANAGER)
    var getFileSystemManager: DMPBridgeMethodHandler = { param, env, callback in
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["result": true]))
        return nil
    }

    // MARK: - readFile

    @BridgeMethod(FS_READ_FILE)
    var readFile: DMPBridgeMethodHandler = { param, env, callback in
        let params = param.getMap()
        let filePath = params.getString(key: "filePath") ?? ""
        let encoding = params.getString(key: "encoding") ?? "utf8"

        guard !filePath.isEmpty else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "readFile:fail filePath is required")
            return nil
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

        return nil
    }

    // MARK: - writeFile

    @BridgeMethod(FS_WRITE_FILE)
    var writeFile: DMPBridgeMethodHandler = { param, env, callback in
        let params = param.getMap()
        let filePath = params.getString(key: "filePath") ?? ""
        let dataString = params.getString(key: "data") ?? ""
        let encoding = params.getString(key: "encoding") ?? "utf8"

        guard !filePath.isEmpty else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "writeFile:fail filePath is required")
            return nil
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

        return nil
    }

    // MARK: - mkdir

    @BridgeMethod(FS_MKDIR)
    var mkdir: DMPBridgeMethodHandler = { param, env, callback in
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

        return nil
    }

    // MARK: - rmdir

    @BridgeMethod(FS_RMDIR)
    var rmdir: DMPBridgeMethodHandler = { param, env, callback in
        let dirPath = param.getMap().getString(key: "dirPath") ?? ""
        let resolvedPath = FileSystemAPI.resolvePath(dirPath, appId: env.appId)

        do {
            try FileManager.default.removeItem(atPath: resolvedPath)
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "rmdir:fail \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - unlink

    @BridgeMethod(FS_UNLINK)
    var unlink: DMPBridgeMethodHandler = { param, env, callback in
        let filePath = param.getMap().getString(key: "filePath") ?? ""
        let resolvedPath = FileSystemAPI.resolvePath(filePath, appId: env.appId)

        do {
            try FileManager.default.removeItem(atPath: resolvedPath)
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } catch {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "unlink:fail \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - stat

    @BridgeMethod(FS_STAT)
    var stat: DMPBridgeMethodHandler = { param, env, callback in
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

        return nil
    }

    // MARK: - access

    @BridgeMethod(FS_ACCESS)
    var access: DMPBridgeMethodHandler = { param, env, callback in
        let filePath = param.getMap().getString(key: "path") ?? ""
        let resolvedPath = FileSystemAPI.resolvePath(filePath, appId: env.appId)

        if FileManager.default.fileExists(atPath: resolvedPath) {
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        } else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "access:fail no such file or directory")
        }

        return nil
    }

    // MARK: - readdir

    @BridgeMethod(FS_READ_DIR)
    var readdir: DMPBridgeMethodHandler = { param, env, callback in
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

        return nil
    }

    // MARK: - copyFile

    @BridgeMethod(FS_COPY_FILE)
    var copyFile: DMPBridgeMethodHandler = { param, env, callback in
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

        return nil
    }

    // MARK: - rename

    @BridgeMethod(FS_RENAME)
    var rename: DMPBridgeMethodHandler = { param, env, callback in
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

        return nil
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
