//
//  DMPResourceManager.swift
//  dimina
//
//  Created by Lehem on 2025/4/17.
//

import Foundation
import SwiftUI

public class DMPResourceManager {
    private init() {}

    public static func prepareApp(appId: String) {
        let bundlePath = DMPSandboxManager.appBundlePath(appId)
        let bundle = DMPResourceManager.jsappBundle

        if FileManager.default.fileExists(atPath: bundlePath) {
            // 首先尝试直接读取应用根目录下的config.json
            let appConfigPath = DMPSandboxManager.appBundleConfigPath(appId: appId)
            var existingVersionCode = 0
            var existingVersion: String? = nil

            if FileManager.default.fileExists(atPath: appConfigPath) {
                // 如果根目录有config.json，直接读取
                if let config = DMPFileUtil.loadJSONFromFile(filePath: appConfigPath),
                   let versionCode = config["versionCode"] as? Int {
                    existingVersionCode = versionCode
                    existingVersion = "root"
                }
            } else {
                // 如果根目录没有config.json，查找版本目录
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: bundlePath)
                    // 查找版本目录（通常以数字或版本号命名）
                    for item in contents {
                        let itemPath = (bundlePath as NSString).appendingPathComponent(item)
                        var isDirectory: ObjCBool = false

                        if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                            // 检查是否是版本目录（包含config.json）
                            let configPath = (itemPath as NSString).appendingPathComponent("config.json")
                            if FileManager.default.fileExists(atPath: configPath) {
                                if let config = DMPFileUtil.loadJSONFromFile(filePath: configPath),
                                   let versionCode = config["versionCode"] as? Int {
                                    if versionCode > existingVersionCode {
                                        existingVersionCode = versionCode
                                        existingVersion = item
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    print("读取应用目录失败: \(error)")
                }
            }

            // 获取新版本的版本号
            var newVersionCode: Int = 0
            if let resourcePath = bundle?.resourcePath {
                let configBundle = DMPFileUtil.loadJSONFromFile(
                    filePath: resourcePath + "/\(appId)/config.json")
                newVersionCode = configBundle?["versionCode"] as? Int ?? 0
            } else {
                print("无法获取JSApp Bundle资源路径，跳过版本比较")
                return
            }

            // 比较版本号
            if existingVersionCode >= newVersionCode {
                print("App 目标路径已存在，现有版本 \(existingVersionCode) >= 新版本 \(newVersionCode)，跳过复制操作")
                return
            } else {
                print("发现新版本，现有版本 \(existingVersionCode) < 新版本 \(newVersionCode)，开始更新")

                // 可选：清理旧版本目录（如果需要）
                if let existingVersion = existingVersion {
                    let oldVersionPath = (bundlePath as NSString).appendingPathComponent(existingVersion)
                    do {
                        try FileManager.default.removeItem(atPath: oldVersionPath)
                        print("已清理旧版本目录: \(oldVersionPath)")
                    } catch {
                        print("清理旧版本目录失败: \(error)")
                        // 继续执行，不因为清理失败而中断
                    }
                }
            }
        }

        // 确保目标目录存在
        if DMPFileUtil.createDirectory(at: bundlePath) {
            if let resourcePath = bundle?.resourcePath {
                if DMPFileUtil.copyContents(
                    from: (resourcePath as NSString).appendingPathComponent(appId),
                    to: bundlePath,
                    excludeItems: ["\(appId).zip"]
                ) {
                    print("成功复制JSApp资源到沙盒路径: \(bundlePath)")
                } else {
                    print("复制JSApp资源失败")
                }

                // 再检查是否存在对应应用的zip文件并解压
                let appResourcePath = (resourcePath as NSString).appendingPathComponent(appId)
                let appZipPath = (appResourcePath as NSString).appendingPathComponent(
                    "\(appId).zip")
                if FileManager.default.fileExists(atPath: appZipPath) {
                    // 解压应用zip到目标路径
                    if DMPFileUtil.unzipFile(at: appZipPath, to: bundlePath) {
                        print("成功解压\(appId).zip到沙盒路径: \(bundlePath)")
                    } else {
                        print("解压\(appId).zip失败")
                    }
                }
            } else {
                print("无法获取JSApp Bundle资源路径")
            }
        } else {
            print("创建目标目录失败: \(bundlePath)")
        }
    }

    public static func prepareSdk() {
        let sdkBundlePath = DMPSandboxManager.sdkBundlePath()
        let bundle = DMPResourceManager.jssdkBundle

        if FileManager.default.fileExists(atPath: sdkBundlePath) {
            if let config = DMPFileUtil.loadJSONFromFile(filePath: DMPSandboxManager.sdkConfigPath())
            {
                let versionCodeOld = config["versionCode"] as? Int ?? 0

                // 加载 bundle 下的 config.json
                let resourcePath = (bundle?.resourcePath)!
                let configBundle = DMPFileUtil.loadJSONFromFile(
                    filePath: resourcePath + "/config.json")
                let versionCodeNew = configBundle?["versionCode"] as? Int ?? 0

                // 比较版本号
                if versionCodeOld >= versionCodeNew {
                    print("SDK目标路径已存在，跳过复制操作")
                    return
                }
            }
        }

        // 确保目标目录存在
        if DMPFileUtil.createDirectory(at: sdkBundlePath) {
            // 复制JSSDK资源到沙盒路径
            if let resourcePath = bundle?.resourcePath {
                // 先复制其他资源文件（排除main.zip）
                if DMPFileUtil.copyContents(from: resourcePath, to: sdkBundlePath, excludeItems: ["main.zip"])
                {
                    print("成功复制JSSDK资源到沙盒路径: \(sdkBundlePath)")
                } else {
                    print("复制JSSDK资源失败")
                }

                // 再检查是否存在main.zip文件并解压
                let mainZipPath = (resourcePath as NSString).appendingPathComponent("main.zip")
                if FileManager.default.fileExists(atPath: mainZipPath) {
                    // 解压main.zip到目标路径
                    if DMPFileUtil.unzipFile(at: mainZipPath, to: sdkBundlePath) {
                        print("成功解压main.zip到沙盒路径: \(sdkBundlePath)")
                    } else {
                        print("解压main.zip失败")
                    }
                }

                // 合并沙盒路径
//                let sandboxPath = DMPSandboxManager.sandboxPath()
//                // 如果 sandboxPath 不存在 assets 目录，并且也不存在 pageFrame.html，那么执行复制
//                if !DMPFileUtil.fileExists(at: sandboxPath + "/assets")
//                    || !DMPFileUtil.fileExists(at: sandboxPath + "/pageFrame.html")
//                {
//                    let mainPath = sdkBundlePath + "/main"
//                    if DMPFileUtil.copyContents(from: mainPath, to: sandboxPath) {
//                        print("成功复制main目录内容到沙盒路径: \(sandboxPath)")
//                    } else {
//                        print("复制main目录内容失败")
//                    }
//                }
            } else {
                print("无法获取JSSDK Bundle资源路径")
            }
        } else {
            print("创建目标目录失败: \(sdkBundlePath)")
        }
    }

    // jsapp的Bundle - 支持SPM模块Bundle、本地main Bundle和远程下载三种方式（三段式fallback）
    static var jsappBundle: Bundle? = {
        // 1. SPM module bundle path (upstream)
        #if SWIFT_PACKAGE
        if let bundleURL = Bundle.module.url(forResource: "JsApp", withExtension: "bundle") {
            return Bundle(url: bundleURL)
        }
        #endif

        // 2. Local main bundle (company fork)
        if let bundleURL = Bundle.main.url(forResource: "JsApp", withExtension: "bundle") {
            return Bundle(url: bundleURL)
        }

        // 3. Remote download fallback (company fork)
        return downloadRemoteJsAppBundle()
    }()

    // 远程下载JSApp Bundle
    private static func downloadRemoteJsAppBundle() -> Bundle? {
        print("🔍 检查远程JSApp Bundle...")

        // 检查是否已经有下载的远程Bundle
        let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: remoteBundlePath) {
            print("✅ 发现现有远程Bundle: \(remoteBundlePath)")

            // 验证Bundle是否有效
            if let bundle = Bundle(path: remoteBundlePath) {
                print("✅ 远程Bundle有效，返回现有Bundle")
                return bundle
            } else {
                print("⚠️ 现有远程Bundle无效，将重新下载")
                // 删除无效的Bundle
                try? fileManager.removeItem(atPath: remoteBundlePath)
            }
        } else {
            print("ℹ️ 远程Bundle不存在，需要下载")
        }

        // 确保目录结构存在
        let sandboxPath = DMPSandboxManager.sandboxPath()
        if !DMPFileUtil.createDirectory(at: sandboxPath) {
            print("❌ 创建沙盒根目录失败")
            return nil
        }

        if !DMPFileUtil.createDirectory(at: remoteBundlePath) {
            print("❌ 创建远程Bundle目录失败")
            return nil
        }

        print("✅ 目录结构准备完成，开始下载...")

        // 如果没有下载的Bundle，尝试下载
        downloadJsAppBundleFromRemote { success in
            if success {
                print("✅ 远程JSApp Bundle下载成功")
            } else {
                print("❌ 远程JSApp Bundle下载失败")
            }
        }

        return nil
    }

    // 从远程服务器下载JSApp Bundle
    private static func downloadJsAppBundleFromRemote(completion: @escaping (Bool) -> Void) {
        // 这里可以配置远程下载URL，可以通过配置文件或环境变量设置
        let remoteURLString = getRemoteJsAppBundleURL()

        // 如果URL为空，跳过下载但创建目录结构
        if remoteURLString.isEmpty {
            print("ℹ️ 远程URL为空，跳过下载，仅创建目录结构")

            // 创建必要的目录结构
            let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()
            let sandboxPath = DMPSandboxManager.sandboxPath()

            if DMPFileUtil.createDirectory(at: sandboxPath) && DMPFileUtil.createDirectory(at: remoteBundlePath) {
                print("✅ 目录结构创建成功，跳过下载")
                completion(true)
            } else {
                print("❌ 目录结构创建失败")
                completion(false)
            }
            return
        }

        guard let remoteURL = URL(string: remoteURLString) else {
            print("❌ 无效的远程URL: \(remoteURLString)")
            completion(false)
            return
        }

        print("🚀 开始下载远程JSApp Bundle: \(remoteURL)")

        // 预先创建必要的目录结构
        let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()
        let sandboxPath = DMPSandboxManager.sandboxPath()

        print("📁 沙盒根路径: \(sandboxPath)")
        print("📁 远程Bundle路径: \(remoteBundlePath)")

        // 确保沙盒根目录存在
        if !DMPFileUtil.createDirectory(at: sandboxPath) {
            print("❌ 创建沙盒根目录失败")
            completion(false)
            return
        }

        // 确保远程Bundle目录存在
        if !DMPFileUtil.createDirectory(at: remoteBundlePath) {
            print("❌ 创建远程Bundle目录失败")
            completion(false)
            return
        }

        print("✅ 目录创建成功，开始下载...")

        let task = URLSession.shared.downloadTask(with: remoteURL) { localURL, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 下载JSApp Bundle失败: \(error)")
                    completion(false)
                    return
                }

                guard let localURL = localURL else {
                    print("❌ 下载完成但本地URL为空")
                    completion(false)
                    return
                }

                print("📥 下载完成，本地文件路径: \(localURL.path)")

                // 检查下载的文件是否存在
                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: localURL.path) else {
                    print("❌ 下载的文件不存在: \(localURL.path)")
                    completion(false)
                    return
                }

                // 获取文件大小
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: localURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    print("📊 下载文件大小: \(fileSize) bytes")
                } catch {
                    print("⚠️ 无法获取文件大小: \(error)")
                }

                // 解压下载的文件到远程Bundle路径
                print("📦 开始解压文件...")
                if DMPFileUtil.unzipFile(at: localURL.path, to: remoteBundlePath) {
                    print("✅ 成功解压远程JSApp Bundle到: \(remoteBundlePath)")

                    // 验证解压结果
                    do {
                        let contents = try fileManager.contentsOfDirectory(atPath: remoteBundlePath)
                        print("📋 远程Bundle目录内容: \(contents)")

                        // 检查是否有配置文件
                        let configFiles = contents.filter { $0.hasSuffix(".json") }
                        if !configFiles.isEmpty {
                            print("✅ 发现配置文件: \(configFiles)")
                        } else {
                            print("⚠️ 未发现配置文件")
                        }

                    } catch {
                        print("⚠️ 无法读取远程Bundle目录内容: \(error)")
                    }

                    completion(true)
                } else {
                    print("❌ 解压远程JSApp Bundle失败")
                    completion(false)
                }
            }
        }

        // 设置下载进度监控
        task.progress.observe(\.fractionCompleted) { progress, _ in
            let percentage = Int(progress.fractionCompleted * 100)
            print("📥 下载进度: \(percentage)%")
        }

        task.resume()
        print("🔄 下载任务已启动")
    }

    // 获取远程JSApp Bundle的URL
    private static func getRemoteJsAppBundleURL() -> String {
        // 从配置文件获取远程下载URL
        let configURL = DMPResourceConfig.shared.remoteJsAppBundleURL

        // 如果配置的URL是默认的无效URL，提供一个备选方案
        if configURL == "https://your-server.com/jsapp-bundle.zip" {
            print("⚠️ 检测到默认无效URL，使用备选URL")
            // 这里你可以设置一个实际的测试URL，或者返回空字符串来跳过下载
            return "" // 返回空字符串将跳过下载
        }

        return configURL
    }

    // 检查远程Bundle是否需要更新
    public static func checkRemoteBundleUpdate(completion: @escaping (Bool) -> Void) {
        let remoteURLString = getRemoteJsAppBundleURL()
        guard let remoteURL = URL(string: remoteURLString) else {
            completion(false)
            return
        }

        // 这里可以实现版本检查逻辑
        // 例如：发送HEAD请求检查Last-Modified头，或者下载一个小的版本信息文件
        let task = URLSession.shared.dataTask(with: remoteURL) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse {
                    let needsUpdate = httpResponse.statusCode == 200
                    completion(needsUpdate)
                } else {
                    completion(false)
                }
            }
        }
        task.resume()
    }

    // 强制刷新远程Bundle
    public static func refreshRemoteBundle(completion: @escaping (Bool) -> Void) {
        print("🔄 开始强制刷新远程Bundle...")

        // 删除现有的远程Bundle
        let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: remoteBundlePath) {
            do {
                try fileManager.removeItem(atPath: remoteBundlePath)
                print("✅ 成功删除现有远程Bundle: \(remoteBundlePath)")
            } catch {
                print("⚠️ 删除现有远程Bundle失败: \(error)")
                // 继续执行，不因为删除失败而中断
            }
        } else {
            print("ℹ️ 远程Bundle目录不存在，无需删除")
        }

        // 确保目录结构存在
        let sandboxPath = DMPSandboxManager.sandboxPath()
        if !DMPFileUtil.createDirectory(at: sandboxPath) {
            print("❌ 创建沙盒根目录失败")
            completion(false)
            return
        }

        if !DMPFileUtil.createDirectory(at: remoteBundlePath) {
            print("❌ 创建远程Bundle目录失败")
            completion(false)
            return
        }

        print("✅ 目录结构准备完成，开始重新下载...")

        // 重新下载
        downloadJsAppBundleFromRemote(completion: completion)
    }

    // 获取当前可用的JSApp Bundle（优先SPM模块Bundle，其次本地，最后远程）
    public static func getAvailableJsAppBundle() -> Bundle? {
        // 首先尝试SPM模块Bundle
        #if SWIFT_PACKAGE
        if let spmBundle = Bundle.module.url(forResource: "JsApp", withExtension: "bundle"),
           let bundle = Bundle(url: spmBundle) {
            return bundle
        }
        #endif

        // 然后尝试本地Bundle
        if let localBundle = Bundle.main.url(forResource: "JsApp", withExtension: "bundle"),
           let bundle = Bundle(url: localBundle) {
            return bundle
        }

        // 最后尝试远程Bundle
        let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()
        if FileManager.default.fileExists(atPath: remoteBundlePath) {
            return Bundle(path: remoteBundlePath)
        }

        return nil
    }

    // MARK: - 手动目录管理

    /// 手动创建远程小程序所需的目录结构
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - engineType: 引擎类型 (可选，用于判断下载目录)
    ///   - launchType: 启动类型 (可选，用于判断下载策略)
    ///   - loaderType: Loader类型 (可选，用于判断loader类型)
    /// - Returns: 是否创建成功
    public static func createRemoteMiniProgramDirectories(
        appId: String,
        engineType: String? = nil,
        launchType: String? = nil,
        loaderType: String? = nil
    ) -> Bool {
        print("🏗️ 开始创建远程小程序目录结构...")
        print("🔧 应用ID: \(appId)")
        print("🔧 引擎类型: \(engineType ?? "未指定")")
        print("🔧 启动类型: \(launchType ?? "未指定")")
        print("🔧 Loader类型: \(loaderType ?? "未指定")")

        // 检查loader是否为DMP类型
        let isDMP = isDMPLoader(loaderType)
        print("🔍 Loader类型检查: \(isDMP ? "✅ DMP Loader" : "❌ 非DMP Loader")")

        // 根据引擎类型和启动类型确定下载策略
        let downloadStrategy = determineDownloadStrategy(engineType: engineType, launchType: launchType)
        print("📋 下载策略: \(downloadStrategy.description)")

        let sandboxPath = DMPSandboxManager.sandboxPath()
        let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()
        let appPath = DMPSandboxManager.appBundlePath(appId)

        // 根据策略确定具体的目录路径
        let targetPaths = getTargetPathsForStrategy(
            strategy: downloadStrategy,
            appId: appId,
            sandboxPath: sandboxPath,
            remoteBundlePath: remoteBundlePath,
            appPath: appPath
        )

        print("📁 沙盒根路径: \(sandboxPath)")
        print("📁 远程Bundle路径: \(remoteBundlePath)")
        print("📁 应用路径: \(appPath)")
        print("📁 目标下载路径: \(targetPaths.targetPath)")

        // 1. 创建沙盒根目录
        if !DMPFileUtil.createDirectory(at: sandboxPath) {
            print("❌ 创建沙盒根目录失败")
            return false
        }
        print("✅ 沙盒根目录创建成功")

        // 2. 根据策略创建相应的目录
        if !createDirectoriesForStrategy(strategy: downloadStrategy, paths: targetPaths) {
            print("❌ 创建策略相关目录失败")
            return false
        }

        // 3. 如果是DMP Loader，创建额外的DMP特定目录
        if isDMP {
            print("🏗️ 检测到DMP Loader，创建DMP特定目录...")
            let dmpSpecificPath = (targetPaths.targetPath as NSString).appendingPathComponent("dmp")
            if DMPFileUtil.createDirectory(at: dmpSpecificPath) {
                print("✅ DMP特定目录创建成功: \(dmpSpecificPath)")
            } else {
                print("⚠️ DMP特定目录创建失败")
            }
        }

        // 4. 创建应用目录结构
        if !DMPSandboxManager.initBundleDirectoryForApp(appId: appId) {
            print("❌ 创建应用目录结构失败")
            return false
        }
        print("✅ 应用目录结构创建成功")

        // 5. 验证目录创建结果
        let fileManager = FileManager.default
        let sandboxExists = fileManager.fileExists(atPath: sandboxPath)
        let remoteExists = fileManager.fileExists(atPath: remoteBundlePath)
        let appExists = fileManager.fileExists(atPath: appPath)
        let targetExists = fileManager.fileExists(atPath: targetPaths.targetPath)

        print("🔍 目录验证结果:")
        print("  - 沙盒根目录: \(sandboxExists ? "✅" : "❌")")
        print("  - 远程Bundle目录: \(remoteExists ? "✅" : "❌")")
        print("  - 应用目录: \(appExists ? "✅" : "❌")")
        print("  - 目标下载目录: \(targetExists ? "✅" : "❌")")

        // 6. 列出沙盒目录内容
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: sandboxPath)
            print("📋 沙盒目录内容: \(contents)")
        } catch {
            print("⚠️ 无法读取沙盒目录内容: \(error)")
        }

        return sandboxExists && remoteExists && appExists && targetExists
    }

    /// 检查远程小程序目录结构是否完整
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - engineType: 引擎类型 (可选)
    ///   - launchType: 启动类型 (可选)
    /// - Returns: 目录结构是否完整
    public static func checkRemoteMiniProgramDirectories(
        appId: String,
        engineType: String? = nil,
        launchType: String? = nil
    ) -> Bool {
        let fileManager = FileManager.default
        let sandboxPath = DMPSandboxManager.sandboxPath()
        let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()
        let appPath = DMPSandboxManager.appBundlePath(appId)

        // 根据引擎类型和启动类型确定下载策略
        let downloadStrategy = determineDownloadStrategy(engineType: engineType, launchType: launchType)
        let targetPaths = getTargetPathsForStrategy(
            strategy: downloadStrategy,
            appId: appId,
            sandboxPath: sandboxPath,
            remoteBundlePath: remoteBundlePath,
            appPath: appPath
        )

        let sandboxExists = fileManager.fileExists(atPath: sandboxPath)
        let remoteExists = fileManager.fileExists(atPath: remoteBundlePath)
        let appExists = fileManager.fileExists(atPath: appPath)
        let targetExists = fileManager.fileExists(atPath: targetPaths.targetPath)

        print("🔍 远程小程序目录结构检查:")
        print("  - 沙盒根目录: \(sandboxExists ? "✅" : "❌")")
        print("  - 远程Bundle目录: \(remoteExists ? "✅" : "❌")")
        print("  - 应用目录: \(appExists ? "✅" : "❌")")
        print("  - 目标下载目录: \(targetExists ? "✅" : "❌")")
        print("  - 下载策略: \(downloadStrategy.description)")

        return sandboxExists && remoteExists && appExists && targetExists
    }

    // MARK: - 引擎类型判断和下载策略

    /// 下载策略枚举
    public enum DownloadStrategy {
        case quickJS          // QuickJS引擎
        case v8               // V8引擎
        case jscore           // JavaScriptCore引擎
        case harmony          // HarmonyOS引擎
        case android          // Android引擎
        case ios              // iOS引擎
        case web              // Web引擎
        case unknown          // 未知引擎

        var description: String {
            switch self {
            case .quickJS: return "QuickJS引擎"
            case .v8: return "V8引擎"
            case .jscore: return "JavaScriptCore引擎"
            case .harmony: return "HarmonyOS引擎"
            case .android: return "Android引擎"
            case .ios: return "iOS引擎"
            case .web: return "Web引擎"
            case .unknown: return "未知引擎"
            }
        }

        var directorySuffix: String {
            switch self {
            case .quickJS: return "qjs"
            case .v8: return "v8"
            case .jscore: return "jscore"
            case .harmony: return "harmony"
            case .android: return "android"
            case .ios: return "ios"
            case .web: return "web"
            case .unknown: return "unknown"
            }
        }
    }

    /// 启动类型枚举
    public enum LaunchType {
        case online           // 在线启动
        case giftUrl          // 礼品URL启动
        case localBuild       // 本地构建启动
        case debugUrl         // 调试URL启动
        case unknown          // 未知启动类型

        var description: String {
            switch self {
            case .online: return "在线启动"
            case .giftUrl: return "礼品URL启动"
            case .localBuild: return "本地构建启动"
            case .debugUrl: return "调试URL启动"
            case .unknown: return "未知启动类型"
            }
        }
    }

    /// Loader类型枚举
    public enum LoaderType {
        case dmp              // DMP Loader
        case quickjs          // QuickJS Loader
        case v8               // V8 Loader
        case jscore           // JavaScriptCore Loader
        case harmony          // HarmonyOS Loader
        case android          // Android Loader
        case ios              // iOS Loader
        case web              // Web Loader
        case unknown          // 未知Loader

        var description: String {
            switch self {
            case .dmp: return "DMP Loader"
            case .quickjs: return "QuickJS Loader"
            case .v8: return "V8 Loader"
            case .jscore: return "JavaScriptCore Loader"
            case .harmony: return "HarmonyOS Loader"
            case .android: return "Android Loader"
            case .ios: return "iOS Loader"
            case .web: return "Web Loader"
            case .unknown: return "未知Loader"
            }
        }

        var directorySuffix: String {
            switch self {
            case .dmp: return "dmp"
            case .quickjs: return "qjs"
            case .v8: return "v8"
            case .jscore: return "jscore"
            case .harmony: return "harmony"
            case .android: return "android"
            case .ios: return "ios"
            case .web: return "web"
            case .unknown: return "unknown"
            }
        }

        var isDMPLoader: Bool {
            return self == .dmp
        }
    }

    /// 根据引擎类型和启动类型确定下载策略
    /// - Parameters:
    ///   - engineType: 引擎类型字符串
    ///   - launchType: 启动类型字符串
    /// - Returns: 下载策略
    private static func determineDownloadStrategy(engineType: String?, launchType: String?) -> DownloadStrategy {
        // 根据引擎类型字符串判断
        if let engineType = engineType?.lowercased() {
            if engineType.contains("quickjs") || engineType.contains("qjs") {
                return .quickJS
            } else if engineType.contains("v8") {
                return .v8
            } else if engineType.contains("jscore") || engineType.contains("javascriptcore") {
                return .jscore
            } else if engineType.contains("harmony") || engineType.contains("arkts") {
                return .harmony
            } else if engineType.contains("android") {
                return .android
            } else if engineType.contains("ios") {
                return .ios
            } else if engineType.contains("web") || engineType.contains("webview") {
                return .web
            }
        }

        // 根据启动类型判断
        if let launchType = launchType?.lowercased() {
            if launchType.contains("debug") || launchType.contains("local") {
                return .jscore  // 调试和本地模式通常使用JSCore
            } else if launchType.contains("online") {
                return .quickJS // 在线模式通常使用QuickJS
            }
        }

        // 根据平台判断
        #if os(iOS)
        return .jscore
        #elseif os(macOS)
        return .jscore
        #elseif os(Android)
        return .quickJS
        #elseif os(HarmonyOS)
        return .harmony
        #else
        return .unknown
        #endif
    }

    /// 根据loader类型字符串判断loader类型
    /// - Parameter loaderType: loader类型字符串
    /// - Returns: Loader类型枚举
    public static func determineLoaderType(from loaderType: String?) -> LoaderType {
        guard let loaderType = loaderType?.lowercased() else {
            return .unknown
        }

        if loaderType.contains("dmp") || loaderType.contains("dimina") {
            return .dmp
        } else if loaderType.contains("quickjs") || loaderType.contains("qjs") {
            return .quickjs
        } else if loaderType.contains("v8") {
            return .v8
        } else if loaderType.contains("jscore") || loaderType.contains("javascriptcore") {
            return .jscore
        } else if loaderType.contains("harmony") || loaderType.contains("arkts") {
            return .harmony
        } else if loaderType.contains("android") {
            return .android
        } else if loaderType.contains("ios") {
            return .ios
        } else if loaderType.contains("web") || loaderType.contains("webview") {
            return .web
        }

        return .unknown
    }

    /// 检查loader是否为DMP类型
    /// - Parameter loaderType: loader类型字符串
    /// - Returns: 是否为DMP loader
    public static func isDMPLoader(_ loaderType: String?) -> Bool {
        let loader = determineLoaderType(from: loaderType)
        return loader.isDMPLoader
    }

    /// 目标路径结构
    private struct TargetPaths {
        let targetPath: String
        let engineSpecificPath: String
        let launchSpecificPath: String
    }

    /// 根据策略获取目标路径
    /// - Parameters:
    ///   - strategy: 下载策略
    ///   - appId: 应用ID
    ///   - sandboxPath: 沙盒路径
    ///   - remoteBundlePath: 远程Bundle路径
    ///   - appPath: 应用路径
    /// - Returns: 目标路径结构
    private static func getTargetPathsForStrategy(
        strategy: DownloadStrategy,
        appId: String,
        sandboxPath: String,
        remoteBundlePath: String,
        appPath: String
    ) -> TargetPaths {
        let engineSpecificPath = (remoteBundlePath as NSString).appendingPathComponent(strategy.directorySuffix)
        let launchSpecificPath = (engineSpecificPath as NSString).appendingPathComponent(appId)
        let targetPath = launchSpecificPath

        return TargetPaths(
            targetPath: targetPath,
            engineSpecificPath: engineSpecificPath,
            launchSpecificPath: launchSpecificPath
        )
    }

    /// 根据策略创建相应的目录
    /// - Parameters:
    ///   - strategy: 下载策略
    ///   - paths: 目标路径结构
    /// - Returns: 是否创建成功
    private static func createDirectoriesForStrategy(strategy: DownloadStrategy, paths: TargetPaths) -> Bool {
        print("🏗️ 根据策略创建目录: \(strategy.description)")

        // 创建引擎特定目录
        if !DMPFileUtil.createDirectory(at: paths.engineSpecificPath) {
            print("❌ 创建引擎特定目录失败: \(paths.engineSpecificPath)")
            return false
        }
        print("✅ 引擎特定目录创建成功: \(paths.engineSpecificPath)")

        // 创建启动特定目录
        if !DMPFileUtil.createDirectory(at: paths.launchSpecificPath) {
            print("❌ 创建启动特定目录失败: \(paths.launchSpecificPath)")
            return false
        }
        print("✅ 启动特定目录创建成功: \(paths.launchSpecificPath)")

        // 创建最终目标目录
        if !DMPFileUtil.createDirectory(at: paths.targetPath) {
            print("❌ 创建目标目录失败: \(paths.targetPath)")
            return false
        }
        print("✅ 目标目录创建成功: \(paths.targetPath)")

                return true
    }

    // MARK: - 应用缓存检查

    /// 检查应用是否已缓存（模拟AppConfigManager.isAppCached的逻辑）
    /// - Parameters:
    ///   - appId: 应用ID
    ///   - versionCode: 版本代码
    ///   - engineType: 引擎类型
    ///   - launchType: 启动类型
    ///   - loaderType: Loader类型
    /// - Returns: 是否已缓存
    public static func isAppCached(
        appId: String,
        versionCode: Int,
        engineType: String? = nil,
        launchType: String? = nil,
        loaderType: String? = nil
    ) -> Bool {
        print("🔍 检查应用缓存状态...")
        print("  - 应用ID: \(appId)")
        print("  - 版本代码: \(versionCode)")
        print("  - 引擎类型: \(engineType ?? "未指定")")
        print("  - 启动类型: \(launchType ?? "未指定")")
        print("  - Loader类型: \(loaderType ?? "未指定")")

        // 检查loader是否为DMP类型
        let isDMP = isDMPLoader(loaderType)
        print("  - Loader类型检查: \(isDMP ? "✅ DMP Loader" : "❌ 非DMP Loader")")

        // 根据引擎类型和启动类型确定下载策略
        let downloadStrategy = determineDownloadStrategy(engineType: engineType, launchType: launchType)
        print("  - 下载策略: \(downloadStrategy.description)")

        let fileManager = FileManager.default
        let sandboxPath = DMPSandboxManager.sandboxPath()
        let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()

        // 获取目标路径
        let targetPaths = getTargetPathsForStrategy(
            strategy: downloadStrategy,
            appId: appId,
            sandboxPath: sandboxPath,
            remoteBundlePath: remoteBundlePath,
            appPath: DMPSandboxManager.appBundlePath(appId)
        )

        // 检查各个目录是否存在
        let sandboxExists = fileManager.fileExists(atPath: sandboxPath)
        let remoteExists = fileManager.fileExists(atPath: remoteBundlePath)
        let engineExists = fileManager.fileExists(atPath: targetPaths.engineSpecificPath)
        let appExists = fileManager.fileExists(atPath: targetPaths.targetPath)

        print("  - 沙盒目录: \(sandboxExists ? "✅" : "❌")")
        print("  - 远程Bundle目录: \(remoteExists ? "✅" : "❌")")
        print("  - 引擎特定目录: \(engineExists ? "✅" : "❌")")
        print("  - 应用目录: \(appExists ? "✅" : "❌")")

        // 如果是DMP Loader，检查DMP特定目录
        if isDMP {
            let dmpSpecificPath = (targetPaths.targetPath as NSString).appendingPathComponent("dmp")
            let dmpExists = fileManager.fileExists(atPath: dmpSpecificPath)
            print("  - DMP特定目录: \(dmpExists ? "✅" : "❌")")

            // 检查DMP特定配置文件
            let dmpConfigPath = (dmpSpecificPath as NSString).appendingPathComponent("dmp-config.json")
            let dmpConfigExists = fileManager.fileExists(atPath: dmpConfigPath)
            print("  - DMP配置文件: \(dmpConfigExists ? "✅" : "❌")")
        }

        // 检查配置文件是否存在
        let configPath = (targetPaths.targetPath as NSString).appendingPathComponent("config.json")
        let configExists = fileManager.fileExists(atPath: configPath)
        print("  - 配置文件: \(configExists ? "✅" : "❌")")

        // 检查版本信息
        var versionMatch = false
        if configExists {
            if let configData = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
               let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
               let cachedVersionCode = config["versionCode"] as? Int {
                versionMatch = cachedVersionCode >= versionCode
                print("  - 缓存版本: \(cachedVersionCode)")
                print("  - 版本匹配: \(versionMatch ? "✅" : "❌")")
            }
        }

        let isCached = sandboxExists && remoteExists && engineExists && appExists && configExists && versionMatch
        print("  - 最终缓存状态: \(isCached ? "✅ 已缓存" : "❌ 未缓存")")

        return isCached
    }

    /// 根据引擎类型和启动类型获取应用缓存路径
    /// - Parameters:
    ///   - appId: 应用ID
    ///   - engineType: 引擎类型
    ///   - launchType: 启动类型
    ///   - loaderType: Loader类型
    /// - Returns: 缓存路径
    public static func getAppCachePath(
        appId: String,
        engineType: String? = nil,
        launchType: String? = nil,
        loaderType: String? = nil
    ) -> String {
        let downloadStrategy = determineDownloadStrategy(engineType: engineType, launchType: launchType)
        let sandboxPath = DMPSandboxManager.sandboxPath()
        let remoteBundlePath = DMPSandboxManager.remoteJsAppBundlePath()

        let targetPaths = getTargetPathsForStrategy(
            strategy: downloadStrategy,
            appId: appId,
            sandboxPath: sandboxPath,
            remoteBundlePath: remoteBundlePath,
            appPath: DMPSandboxManager.appBundlePath(appId)
        )

        // 如果是DMP Loader，返回DMP特定路径
        if isDMPLoader(loaderType) {
            let dmpPath = (targetPaths.targetPath as NSString).appendingPathComponent("dmp")
            return dmpPath
        }

        return targetPaths.targetPath
    }

    // MARK: - DMP Loader 专用方法

    /// 专门用于DMP Loader的目录创建
    /// - Parameter appId: 应用ID
    /// - Returns: 是否创建成功
    public static func createDMPLoaderDirectories(appId: String) -> Bool {
        print("🏗️ 开始创建DMP Loader专用目录结构...")
        print("🔧 应用ID: \(appId)")
        print("🔧 Loader类型: DMP")

        return createRemoteMiniProgramDirectories(
            appId: appId,
            engineType: "jscore",  // DMP通常使用JSCore
            launchType: "online",  // DMP通常是在线启动
            loaderType: "dmp"      // 明确指定为DMP Loader
        )
    }

    /// 专门用于DMP Loader的缓存检查
    /// - Parameters:
    ///   - appId: 应用ID
    ///   - versionCode: 版本代码
    /// - Returns: 是否已缓存
    public static func isDMPAppCached(appId: String, versionCode: Int) -> Bool {
        print("🔍 检查DMP应用缓存状态...")
        return isAppCached(
            appId: appId,
            versionCode: versionCode,
            engineType: "jscore",
            launchType: "online",
            loaderType: "dmp"
        )
    }

    /// 获取DMP Loader的专用缓存路径
    /// - Parameter appId: 应用ID
    /// - Returns: DMP专用缓存路径
    public static func getDMPAppCachePath(appId: String) -> String {
        let basePath = getAppCachePath(
            appId: appId,
            engineType: "jscore",
            launchType: "online",
            loaderType: "dmp"
        )
        return basePath
    }

    // jssdk的Bundle
    static var jssdkBundle: Bundle? = {
        #if SWIFT_PACKAGE
        if let bundleURL = Bundle.module.url(forResource: "JsSdk", withExtension: "bundle") {
            return Bundle(url: bundleURL)
        }
        #endif

        if let bundleURL = Bundle(for: DMPResourceManager.self).url(forResource: "DiminaJsSdk", withExtension: "bundle") {
            return Bundle(url: bundleURL)
        }

        if let bundleURL = Bundle.main.url(forResource: "JsSdk", withExtension: "bundle") {
            return Bundle(url: bundleURL)
        }

        return nil
    }()


    public static var assetsBundle: Bundle? = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        if let bundleURL = Bundle(for: DMPResourceManager.self).url(forResource: "DiminaAssets", withExtension: "bundle") {
            return Bundle(url: bundleURL)
        }

        return Bundle.main
        #endif
    }()


    /// 获取所有JSAppBundle下的config.json文件
    /// - Returns: DMPAppConfig数组
    public static func getDMPAppConfigs() -> [DMPAppConfig] {
        var appItems = [DMPAppConfig]()

        guard let jsappBundle = jsappBundle,
            let jsappPath = jsappBundle.resourcePath
        else {
            return appItems
        }

        do {
            // 直接获取bundle中所有应用目录
            let folderContents = try FileManager.default.contentsOfDirectory(atPath: jsappPath)

            for folder in folderContents {
                let folderPath = (jsappPath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false

                if FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir),
                    isDir.boolValue
                {
                    // 检查应用目录中的config.json文件
                    let configPath = (folderPath as NSString).appendingPathComponent("config.json")

                    if FileManager.default.fileExists(atPath: configPath) {
                        // 读取并解析config.json
                        if let jsonObject = DMPFileUtil.loadJSONFromFile(filePath: configPath),
                            let name = jsonObject["name"] as? String,
                            let path = jsonObject["path"] as? String,
                            let versionCode = jsonObject["versionCode"] as? Int,
                            let versionName = jsonObject["versionName"] as? String
                        {

                            // 生成应用图标颜色和文字
                            let randomColor = Color(
                                red: Double.random(in: 0...1),
                                green: Double.random(in: 0...1),
                                blue: Double.random(in: 0...1)
                            )
                            let icon = name.isEmpty ? "?" : String(name.prefix(1))

                            // 创建DMPAppConfig并添加到列表
                            var appItem = DMPAppConfig(
                                appName: name, appId: folder
                            )
                            appItem.path = path
                            appItem.versionCode = versionCode
                            appItem.versionName = versionName
                            appItem.color = randomColor
                            appItem.icon = icon

                            appItems.append(appItem)
                        }
                    }
                }
            }
        } catch {
            print("读取JSAppBundle目录失败: \(error)")
        }

        return appItems
    }
}
