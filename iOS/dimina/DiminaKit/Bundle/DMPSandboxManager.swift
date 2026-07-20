//
//  DMPSandboxManager.swift
//  dimina
//
//  Created by Lehem on 2025/4/17.
//

import Foundation
import SwiftUI

public class DMPSandboxManager {
    private init() {}
    
    // 资源目录常量
    private static let DMPResourceDirectoryName = "resources"
    private static let DMPTmpResourceDirectoryName = "tmp"
    private static let DMPStoreResourceDirectoryName = "store"
    
    // sdk 沙盒路径
    private static var _sandboxPath: String? = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let root = paths[0].path
        let sandbox = (root as NSString).appendingPathComponent("Dimina")
        
        if DMPFileUtil.createDirectory(at: sandbox) {
            return sandbox
        } else {
            DMPLogger.debug("创建沙盒目录失败")
            return nil
        }
    }()
    
    @discardableResult
    public static func initBundleDirectoryForApp(appId: String, sandbox: String? = nil) -> Bool {
        guard let sandboxPath = _sandboxPath else { return false }
        
        let appBundlePath = (sandboxPath as NSString).appendingPathComponent(appId)
        let resourcePath = (appBundlePath as NSString).appendingPathComponent(DMPResourceDirectoryName)
        let tmpPath = (resourcePath as NSString).appendingPathComponent(DMPTmpResourceDirectoryName)
        let storePath = (resourcePath as NSString).appendingPathComponent(DMPStoreResourceDirectoryName)
        
        // 创建所需的目录结构
        if !DMPFileUtil.createDirectory(at: appBundlePath)
            || !DMPFileUtil.createDirectory(at: tmpPath)
            || !DMPFileUtil.createDirectory(at: storePath) {
            DMPLogger.debug("创建目录失败")
            return false
        }
        
        return true
    }

    // MARK: Directory

    public static func sandboxPath() -> String {
        guard let sandboxPath = _sandboxPath else { return "" }
        return sandboxPath
    }
    
    // MARK: App

    public static func appResourceDirectoryPath(appId: String) -> String {
        guard let sandboxPath = _sandboxPath else { return "" }
        return (sandboxPath as NSString).appendingPathComponent(appId + "/" + DMPResourceDirectoryName)
    }

    public static func appTmpResourceDirectoryPath(appId: String) -> String {
        guard let sandboxPath = _sandboxPath else { return "" }
        return (sandboxPath as NSString).appendingPathComponent(appId + "/" + DMPResourceDirectoryName + "/" + DMPTmpResourceDirectoryName)
    }

    public static func appStoreResourceDirectoryPath(appId: String) -> String {
        guard let sandboxPath = _sandboxPath else { return "" }
        return (sandboxPath as NSString).appendingPathComponent(appId + "/" + DMPResourceDirectoryName + "/" + DMPStoreResourceDirectoryName)
    }
    
    public static func appBundlePath(_ appId: String, versionCode: Int? = nil) -> String {
        guard let sandboxPath = _sandboxPath else { return "" }
        if let version = versionCode {
            return sandboxPath + "/" + appId + "/\(version)"
        }
        return sandboxPath + "/" + appId
    }

    // 获取 app 的 service, logic.js
    public static func appServicePath(appId: String, versionCode: Int? = nil) -> String {
        return appBundlePath(appId, versionCode: versionCode) + "/main/logic.js"
    }

    public static func appSubPackagePath(appId: String, packageName: String, versionCode: Int? = nil) -> String {
        return appBundlePath(appId, versionCode: versionCode) + "/\(packageName)" + "/logic.js"
    }

    // 获取 app 的 config.json
    public static func appConfigPath(appId: String, versionCode: Int? = nil) -> String {
        return appBundlePath(appId, versionCode: versionCode) + "/main/app-config.json"
    }
    
    // 获取应用配置路径（不需要版本号，用于查找现有配置）
    public static func appBundleConfigPath(appId: String) -> String {
        guard let sandboxPath = _sandboxPath else { return "" }
        return sandboxPath + "/" + appId + "/config.json"
    }
    
    // MARK: SDK
    
    public static func sdkBundlePath() -> String {
        return DMPSandboxManager.sandboxPath() + "/sdk"
    }
    
    public static func sdkMainBundlePath() -> String {
        return DMPSandboxManager.sdkBundlePath() + "/main"
    }
    
    // 获取 sdk 的 service 目录
    public static func sdkServicePath() -> String {
        return DMPSandboxManager.sdkMainBundlePath() + "/assets/service.js"
    }
    
    // 获取 sdk 的 pageFrame.html
    public static func sdkPageFramePath() -> String {
        return DMPSandboxManager.sdkMainBundlePath() + "/pageFrame.html"
    }
    
    // 获取 sdk 的 config.json
    public static func sdkConfigPath() -> String {
        return DMPSandboxManager.sdkBundlePath() + "/config.json"
    }
    
    // MARK: Remote Bundle
    
    // 获取远程JSApp Bundle的路径
    public static func remoteJsAppBundlePath() -> String {
        return DMPSandboxManager.sandboxPath() + "/remote-jsapp-bundle"
    }
    
}
