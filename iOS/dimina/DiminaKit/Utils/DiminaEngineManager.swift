//
//  DiminaEngineManager.swift
//  EchoWebKit
//
//  Created by David on 2025/1/15.
//  Copyright © 2025 EchoingTech. All rights reserved.
//

import Foundation
import echo_entity_swift
import KurilUniversalKit

/// Dimina Engine 管理器
/// 专门用于处理 Dimina Engine 的目录结构、缓存检查和下载管理
public class DiminaEngineManager {
    
    public static let shared = DiminaEngineManager()
    
    private init() {}
    
    // MARK: - 目录管理
    
    /// 获取 Dimina Engine 的根目录
    /// - Returns: Dimina 根目录的 URL
    public func getDiminaRootPath() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "")
        return documentsPath.appendingPathComponent("Dimina")
    }
    
    /// 获取指定小程序的 Dimina 目录路径
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选，用于路径构建）
    /// - Returns: 小程序的 Dimina 目录路径
    public func getAppPath(appId: String, versionCode: String? = nil) -> URL {
        let rootPath = getDiminaRootPath()
        
        // 使用 appId 和版本号构建路径
        let appPath = rootPath.appendingPathComponent(appId)
        let finalPath: URL
        
        if let versionCode = versionCode, !versionCode.isEmpty {
            // 如果有版本号，创建版本号子文件夹
            finalPath = appPath.appendingPathComponent(versionCode)
            print("📋 [DiminaEngine] 构建路径（包含版本号）: \(finalPath.path)")
            print("💡 [DiminaEngine] 注意：Dimina 资源包解压到版本号子文件夹中")
        } else {
            // 如果没有版本号，直接使用 appId 目录
            finalPath = appPath
            print("📋 [DiminaEngine] 构建路径（无版本号）: \(finalPath.path)")
            print("💡 [DiminaEngine] 注意：Dimina 资源包直接解压到 appId 目录，不创建版本号子文件夹")
        }
        
        return finalPath
    }
    
    /// 获取指定小程序的 Dimina 目录路径（使用模拟器路径）
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    ///   - deviceId: 模拟器设备ID（可选）
    ///   - appContainerId: 应用容器ID（可选）
    /// - Returns: 小程序的 Dimina 目录路径
    public func getSimulatorAppPath(appId: String, 
                                  versionCode: String? = nil,
                                  deviceId: String? = nil,
                                  appContainerId: String? = nil) -> URL {
        // 如果提供了模拟器特定的参数，使用模拟器路径
        if let deviceId = deviceId, let appContainerId = appContainerId {
            let simulatorPath = "/Users/david/Library/Developer/CoreSimulator/Devices/\(deviceId)/data/Containers/Data/Application/\(appContainerId)/Documents/Dimina"
            let basePath = URL(fileURLWithPath: simulatorPath)
            
            print("📱 [DiminaEngine] 构建模拟器路径:")
            print("   📂 设备ID: \(deviceId)")
            print("   📱 应用容器ID: \(appContainerId)")
            print("   🗂️ 基础路径: \(simulatorPath)")
            
            // 使用 appId 和版本号构建路径
            let appPath = basePath.appendingPathComponent(appId)
            let finalPath: URL
            
            if let versionCode = versionCode, !versionCode.isEmpty {
                // 如果有版本号，创建版本号子文件夹
                finalPath = appPath.appendingPathComponent(versionCode)
                print("   📋 最终路径（包含版本号）: \(finalPath.path)")
                print("   💡 注意：Dimina 资源包解压到版本号子文件夹中")
            } else {
                // 如果没有版本号，直接使用 appId 目录
                finalPath = appPath
                print("   📋 最终路径（无版本号）: \(finalPath.path)")
                print("   💡 注意：Dimina 资源包直接解压到 appId 目录，不创建版本号子文件夹")
            }
            
            return finalPath
        } else {
            // 否则使用默认的 Documents 目录
            print("⚠️ [DiminaEngine] 未提供模拟器参数，使用默认路径")
            return getAppPath(appId: appId, versionCode: versionCode)
        }
    }
    
    // MARK: - 缓存检查
    
    /// 检查小程序是否已在 Dimina Engine 中缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    ///   - useSimulatorPath: 是否使用模拟器路径
    ///   - deviceId: 模拟器设备ID（可选）
    ///   - appContainerId: 应用容器ID（可选）
    /// - Returns: 是否已缓存
    public func isAppCached(appId: String, 
                           versionCode: String? = nil,
                           useSimulatorPath: Bool = false,
                           deviceId: String? = nil,
                           appContainerId: String? = nil) -> Bool {
        
        print("🔍 [DiminaEngine] 检查小程序缓存状态: \(appId)")
        if let versionCode = versionCode {
            print("📋 [DiminaEngine] 版本号: \(versionCode)")
        }
        
        let localPath: URL
        if useSimulatorPath {
            localPath = getSimulatorAppPath(appId: appId, versionCode: versionCode, deviceId: deviceId, appContainerId: appContainerId)
            print("📱 [DiminaEngine] 使用模拟器路径检查: \(localPath.path)")
        } else {
            localPath = getAppPath(appId: appId, versionCode: versionCode)
            print("💾 [DiminaEngine] 使用默认路径检查: \(localPath.path)")
        }
        
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            print("❌ [DiminaEngine] 小程序目录不存在: \(localPath.path)")
            return false
        }
        
        print("✅ [DiminaEngine] 小程序目录存在，检查必要文件...")
        
        // 检查是否包含必要的文件
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        let indexPath2 = localPath.appendingPathComponent("index.html")
        
        let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
        let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)
        
        if hasH5Index {
            print("✅ [DiminaEngine] 找到 h5/index.html 文件")
        }
        if hasRootIndex {
            print("✅ [DiminaEngine] 找到 index.html 文件")
        }
        
        let isCached = hasH5Index || hasRootIndex
        if isCached {
            print("✅ [DiminaEngine] 小程序已缓存: \(appId)")
        } else {
            print("❌ [DiminaEngine] 小程序未缓存，缺少必要的 index.html 文件")
        }
        
        return isCached
    }
    
    /// 检查指定路径的小程序是否已缓存
    /// - Parameter localPath: 本地路径
    /// - Returns: 是否已缓存
    public func isAppCached(localPath: URL) -> Bool {
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            return false
        }
        
        // 检查 Dimina 引擎特有的目录结构
        let appId = localPath.lastPathComponent
        let diminaAppPath = localPath.appendingPathComponent(appId)
        let mainLogicPath = diminaAppPath.appendingPathComponent("main/logic.js")
        
        // 检查是否包含 Dimina 引擎特有的文件
        let hasMainLogic = FileManager.default.fileExists(atPath: mainLogicPath.path)
        
        // 检查是否包含必要的文件（兼容传统结构）
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        let indexPath2 = localPath.appendingPathComponent("index.html")
        
        let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
        let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)
        
        // Dimina 引擎优先检查特有文件，如果没有则检查传统文件
        return hasMainLogic || hasH5Index || hasRootIndex
    }
    
    // MARK: - 下载管理
    
    /// 使用 Dimina Engine 下载并解压小程序
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    ///   - downloadUrl: 下载URL
    ///   - useSimulatorPath: 是否使用模拟器路径
    ///   - deviceId: 模拟器设备ID（可选）
    ///   - appContainerId: 应用容器ID（可选）
    /// - Returns: 是否下载成功
    @discardableResult
    public func downloadAndExtractApp(appId: String, 
                                    versionCode: String? = nil,
                                    downloadUrl: String,
                                    useSimulatorPath: Bool = false,
                                    deviceId: String? = nil,
                                    appContainerId: String? = nil) async throws -> Bool {
        
        print("🚀 [DiminaEngine] 开始下载小程序: \(appId)")
        if let versionCode = versionCode {
            print("📋 [DiminaEngine] 版本号: \(versionCode)")
        }
        print("🔗 [DiminaEngine] 下载地址: \(downloadUrl)")
        
        let localPath: URL
        if useSimulatorPath {
            localPath = getSimulatorAppPath(appId: appId, versionCode: versionCode, deviceId: deviceId, appContainerId: appContainerId)
            print("📱 [DiminaEngine] 使用模拟器路径: \(localPath.path)")
        } else {
            localPath = getAppPath(appId: appId, versionCode: versionCode)
            print("💾 [DiminaEngine] 使用默认路径: \(localPath.path)")
        }
        
        // 检查目标目录是否已存在
        if FileManager.default.fileExists(atPath: localPath.path) {
            print("⚠️ [DiminaEngine] 目标目录已存在，将进行覆盖")
        }
        
        // 确保目录存在
        do {
            try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true, attributes: nil)
            print("✅ [DiminaEngine] 目标目录创建成功: \(localPath.path)")
        } catch {
            print("❌ [DiminaEngine] 创建目标目录失败: \(error.localizedDescription)")
            throw error
        }
        
        print("⏳ [DiminaEngine] 开始调用 DownloadManager 进行下载...")
        
        // 检查下载URL是否为 emp 格式
        let isEMPFormat = downloadUrl.lowercased().contains(".emp") || downloadUrl.lowercased().contains("emp")
        
        if isEMPFormat {
            print("📦 [DiminaEngine] 检测到 EMP 格式，使用自定义下载逻辑")
            // 使用自定义的 emp 下载逻辑
            return try await downloadAndExtractEMPApp(localPath: localPath, downloadUrl: downloadUrl)
        } else {
            print("📦 [DiminaEngine] 非 EMP 格式，尝试使用 DownloadManager")
            // 使用 DownloadManager 下载并解压
            // 注意：这里假设 DownloadManager 支持自定义路径
            if let result = try? await DownloadManager.shared.downloadAndExtract(appId: appId, versionCode: versionCode ?? "", downloadUrl: downloadUrl) {
                // 如果 DownloadManager 支持自定义路径，直接使用
                let success = result != nil
                if success {
                    print("✅ [DiminaEngine] 小程序下载并解压成功: \(appId)")
                    print("📁 [DiminaEngine] 文件位置: \(localPath.path)")
                    
                    // 验证下载结果
                    if isValidAppPath(localPath) {
                        print("✅ [DiminaEngine] 文件验证通过，包含必要的 index.html 文件")
                    } else {
                        print("⚠️ [DiminaEngine] 文件验证失败，可能缺少必要的文件")
                    }
                } else {
                    print("❌ [DiminaEngine] 小程序下载失败: \(appId)")
                }
                return success
            } else {
                // 如果不支持，则使用默认路径，然后复制到 Dimina 目录
                // 这里需要根据实际的 DownloadManager 实现来调整
                print("⚠️ [DiminaEngine] DownloadManager 不支持自定义路径，使用默认实现")
                print("💡 [DiminaEngine] 建议: 需要实现自定义路径的下载逻辑")
                return false
            }
        }
    }
    
    /// 使用指定路径下载并解压小程序
    /// - Parameters:
    ///   - localPath: 本地路径
    ///   - downloadUrl: 下载URL
    /// - Returns: 是否下载成功
    @discardableResult
    public func downloadAndExtractApp(localPath: URL, downloadUrl: String) async throws -> Bool {
        print("🚀 [DiminaEngine] 开始下载小程序到指定路径: \(localPath.path)")
        print("🔗 [DiminaEngine] 下载地址: \(downloadUrl)")
        
        // 检查目标目录是否已存在
        let targetExists = FileManager.default.fileExists(atPath: localPath.path)
        if targetExists {
            print("📁 [DiminaEngine] 目标目录已存在，将进行版本升级")
            print("💡 [DiminaEngine] 使用临时目录策略确保升级安全")
        }
        
        // 创建临时目录用于下载和解压
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DiminaDownload_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        print("📁 [DiminaEngine] 临时目录创建成功: \(tempDir.path)")
        
        // 使用 defer 确保临时文件夹总是被清理
        defer {
            do {
                if FileManager.default.fileExists(atPath: tempDir.path) {
                    try FileManager.default.removeItem(at: tempDir)
                    print("🧹 [DiminaEngine] 临时文件夹清理完成: \(tempDir.path)")
                }
            } catch {
                print("⚠️ [DiminaEngine] 临时文件夹清理失败: \(error.localizedDescription)")
            }
        }
        
        // 检查下载URL格式
        let isZipFormat = downloadUrl.lowercased().contains(".zip") || downloadUrl.lowercased().contains("zip")
        
        do {
            if isZipFormat {
                print("📦 [DiminaEngine] 检测到 ZIP 格式，使用 ZIP 处理逻辑")
                return try await downloadAndExtractZipApp(localPath: localPath, downloadUrl: downloadUrl, tempDir: tempDir)
            } else {
                print("📦 [DiminaEngine] 检测到其他格式，使用 EMP 处理逻辑")
                return try await downloadAndExtractEMPApp(localPath: localPath, downloadUrl: downloadUrl, tempDir: tempDir)
            }
        } catch {
            print("❌ [DiminaEngine] 下载或解压过程中发生错误: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - URL 管理
    
    /// 获取 Dimina Engine 小程序的基础URL
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    ///   - useSimulatorPath: 是否使用模拟器路径
    ///   - deviceId: 模拟器设备ID（可选）
    ///   - appContainerId: 应用容器ID（可选）
    /// - Returns: 小程序的基础URL
    public func getBaseURL(appId: String, 
                          versionCode: String? = nil,
                          useSimulatorPath: Bool = false,
                          deviceId: String? = nil,
                          appContainerId: String? = nil) -> URL {
        
        let localPath: URL
        if useSimulatorPath {
            localPath = getSimulatorAppPath(appId: appId, versionCode: versionCode, deviceId: deviceId, appContainerId: appContainerId)
        } else {
            localPath = getAppPath(appId: appId, versionCode: versionCode)
        }
        
        // 优先检查 h5/index.html
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        if FileManager.default.fileExists(atPath: indexPath.path) {
            return indexPath
        }
        
        // 如果没有 h5 目录，则使用根目录的 index.html
        return localPath.appendingPathComponent("index.html")
    }
    
    /// 获取指定路径的基础URL
    /// - Parameter localPath: 本地路径
    /// - Returns: 基础URL
    public func getBaseURL(localPath: URL) -> URL {
        // 优先检查 h5/index.html
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        if FileManager.default.fileExists(atPath: indexPath.path) {
            return indexPath
        }
        
        // 如果没有 h5 目录，则使用根目录的 index.html
        return localPath.appendingPathComponent("index.html")
    }
    
    /// 读取小程序的 app-config.json 配置
    /// - Parameter localPath: 本地路径
    /// - Returns: 应用配置对象
    public func getAppConfig(localPath: URL) -> DMPBundleAppConfig? {
        print("🔍 [DiminaEngine] 读取小程序配置: \(localPath.path)")
        
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            print("❌ [DiminaEngine] 目录不存在，无法读取配置")
            return nil
        }
        
        // 获取 appId（目录名）
        let appId = localPath.lastPathComponent
        
        // 构建 app-config.json 的路径
        let appConfigPath = localPath.appendingPathComponent(appId).appendingPathComponent("main/app-config.json")
        print("📁 [DiminaEngine] 配置文件路径: \(appConfigPath.path)")
        
        // 检查配置文件是否存在
        guard FileManager.default.fileExists(atPath: appConfigPath.path) else {
            print("❌ [DiminaEngine] app-config.json 文件不存在")
            return nil
        }
        
        // 读取配置文件内容
        do {
            let jsonData = try Data(contentsOf: appConfigPath)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            guard let appConfig = DMPBundleAppConfig.fromJsonString(json: jsonString) else {
                print("❌ [DiminaEngine] 解析 app-config.json 失败")
                return nil
        }
            
            print("✅ [DiminaEngine] 成功读取小程序配置")
            print("📋 [DiminaEngine] 入口页面: \(appConfig.entryPagePath)")
            print("📋 [DiminaEngine] 页面列表: \(appConfig.pages ?? [])")
            
            return appConfig
        } catch {
            print("❌ [DiminaEngine] 读取 app-config.json 失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 获取小程序的入口页面路径
    /// - Parameter localPath: 本地路径
    /// - Returns: 入口页面路径
    public func getEntryPagePath(localPath: URL) -> String? {
        print("🔍 [DiminaEngine] 获取小程序入口页面路径: \(localPath.path)")
        
        guard let appConfig = getAppConfig(localPath: localPath) else {
            print("❌ [DiminaEngine] 无法获取应用配置，无法确定入口页面")
            return nil
        }
        
        let entryPagePath = appConfig.entryPagePath
        if !entryPagePath.isEmpty {
            print("✅ [DiminaEngine] 找到入口页面路径: \(entryPagePath)")
            return entryPagePath
        } else {
            print("❌ [DiminaEngine] 入口页面路径为空")
            return nil
        }
    }
    
    /// 获取小程序的完整加载路径
    /// - Parameter localPath: 本地路径
    /// - Returns: 完整的加载路径
    public func getLoadPath(localPath: URL) -> URL? {
        print("🔍 [DiminaEngine] 获取小程序加载路径: \(localPath.path)")
        
        guard let entryPagePath = getEntryPagePath(localPath: localPath) else {
            print("❌ [DiminaEngine] 无法获取入口页面路径")
            return nil
        }
        
        // 获取 appId（目录名）
        let appId = localPath.lastPathComponent
        
        // 构建完整的加载路径
        // 例如：如果 entryPagePath 是 "pages/index/index"，则构建为 "pages/index/index.html"
        let htmlFileName = entryPagePath.hasSuffix(".html") ? entryPagePath : "\(entryPagePath).html"
        let fullLoadPath = localPath.appendingPathComponent(appId).appendingPathComponent(htmlFileName)
        
        print("📁 [DiminaEngine] 完整加载路径: \(fullLoadPath.path)")
        
        // 检查文件是否存在
        if FileManager.default.fileExists(atPath: fullLoadPath.path) {
            print("✅ [DiminaEngine] 加载路径文件存在")
            return fullLoadPath
        } else {
            print("❌ [DiminaEngine] 加载路径文件不存在")
            return nil
        }
    }
    
    // MARK: - 缓存管理
    
    /// 清理指定小程序的 Dimina 缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    ///   - useSimulatorPath: 是否使用模拟器路径
    ///   - deviceId: 模拟器设备ID（可选）
    ///   - appContainerId: 应用容器ID（可选）
    /// - Returns: 是否清理成功
    @discardableResult
    public func clearCache(appId: String, 
                          versionCode: String? = nil,
                          useSimulatorPath: Bool = false,
                          deviceId: String? = nil,
                          appContainerId: String? = nil) -> Bool {
        
        let localPath: URL
        if useSimulatorPath {
            localPath = getSimulatorAppPath(appId: appId, versionCode: versionCode, deviceId: deviceId, appContainerId: appContainerId)
        } else {
            localPath = getAppPath(appId: appId, versionCode: versionCode)
        }
        
        return clearCache(localPath: localPath)
    }
    
    /// 清理指定路径的缓存
    /// - Parameter localPath: 本地路径
    /// - Returns: 是否清理成功
    @discardableResult
    public func clearCache(localPath: URL) -> Bool {
        print("🧹 [DiminaEngine] 开始清理缓存: \(localPath.path)")
        
        do {
            if FileManager.default.fileExists(atPath: localPath.path) {
                print("📁 [DiminaEngine] 找到缓存目录，开始删除...")
                try FileManager.default.removeItem(at: localPath)
                print("✅ [DiminaEngine] 缓存清理成功: \(localPath.path)")
                return true
            } else {
                print("ℹ️ [DiminaEngine] 缓存目录不存在，无需清理")
                return true
            }
        } catch {
            print("❌ [DiminaEngine] 清理缓存失败: \(error.localizedDescription)")
            print("   📍 路径: \(localPath.path)")
            return false
        }
    }
    
    /// 获取所有已缓存的 Dimina 小程序
    /// - Parameter useSimulatorPath: 是否使用模拟器路径
    /// - Returns: 已缓存的小程序ID数组
    public func getAllCachedApps(useSimulatorPath: Bool = false) -> [String] {
        let rootPath: URL
        if useSimulatorPath {
            // 这里需要提供具体的模拟器路径参数
            print("使用模拟器路径需要提供具体的设备ID和应用容器ID")
            return []
        } else {
            rootPath = getDiminaRootPath()
        }
        
        guard FileManager.default.fileExists(atPath: rootPath.path) else {
            return []
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: rootPath, includingPropertiesForKeys: nil)
            var cachedApps: [String] = []
            
            for url in contents {
                let appName = url.lastPathComponent
                print("📱 [DiminaEngine] 检查应用目录: \(appName)")
                
                // 检查是否直接包含小程序文件（无版本号结构）
                if isValidAppPath(url) {
                    print("✅ [DiminaEngine] 发现缓存的小程序（无版本号）: \(appName)")
                    cachedApps.append(appName)
                } else {
                    // 检查是否包含版本号子目录
                    do {
                        let versionContents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                        for versionUrl in versionContents {
                            if isValidAppPath(versionUrl) {
                                let versionName = versionUrl.lastPathComponent
                                print("✅ [DiminaEngine] 发现缓存的小程序（版本号 \(versionName)）: \(appName)")
                                if !cachedApps.contains(appName) {
                                    cachedApps.append(appName)
                                }
                                break
                            }
                        }
                    } catch {
                        print("⚠️ [DiminaEngine] 检查版本号目录失败: \(error)")
                    }
                }
            }
            
            return cachedApps
        } catch {
            print("获取已缓存的 Dimina 小程序失败: \(error)")
            return []
        }
    }
    
    // MARK: - 工具方法
    
    /// 获取小程序的版本信息
    /// - Parameter appPath: 小程序路径
    /// - Returns: 版本信息（如果有的话）
    public func getAppVersion(from appPath: URL) -> String? {
        let appName = appPath.lastPathComponent
        if appName.contains("_") {
            let components = appName.components(separatedBy: "_")
            return components.count > 1 ? components.last : nil
        }
        return nil
    }
    
    /// 检查路径是否为有效的 Dimina 小程序路径
    /// - Parameter path: 路径
    /// - Returns: 是否为有效路径
    public func isValidAppPath(_ path: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else {
            print("❌ [DiminaEngine] 路径不存在: \(path.path)")
            return false
        }
        
        print("🔍 [DiminaEngine] 验证路径: \(path.path)")
        
        // 检查 Dimina 引擎特有的目录结构
        let appId = path.lastPathComponent
        
        // 检查两种可能的 Dimina 引擎结构：
        // 1. {appId}/main/logic.js (嵌套结构)
        let diminaAppPath = path.appendingPathComponent(appId)
        let mainLogicPath = diminaAppPath.appendingPathComponent("main/logic.js")
        let hasMainLogicNested = FileManager.default.fileExists(atPath: mainLogicPath.path)
        
        // 2. main/logic.js (直接结构，如当前情况)
        let mainLogicPathDirect = path.appendingPathComponent("main/logic.js")
        let hasMainLogicDirect = FileManager.default.fileExists(atPath: mainLogicPathDirect.path)
        
        let hasMainLogic = hasMainLogicNested || hasMainLogicDirect
        if hasMainLogicNested {
            print("✅ [DiminaEngine] 找到嵌套的 Dimina 引擎文件: \(mainLogicPath.path)")
        }
        if hasMainLogicDirect {
            print("✅ [DiminaEngine] 找到直接的 Dimina 引擎文件: \(mainLogicPathDirect.path)")
        }
        
        // 检查 app-config.json 文件（Dimina 引擎配置）
        let appConfigPath = path.appendingPathComponent("main/app-config.json")
        let hasAppConfig = FileManager.default.fileExists(atPath: appConfigPath.path)
        if hasAppConfig {
            print("✅ [DiminaEngine] 找到 app-config.json: \(appConfigPath.path)")
        }
        
        // 检查是否包含必要的文件（兼容传统结构）
        let indexPath = path.appendingPathComponent("h5/index.html")
        let indexPath2 = path.appendingPathComponent("index.html")
        
        let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
        let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)
        
        if hasH5Index {
            print("✅ [DiminaEngine] 找到 h5/index.html: \(indexPath.path)")
        }
        if hasRootIndex {
            print("✅ [DiminaEngine] 找到 index.html: \(indexPath2.path)")
        }
        
        // 如果没有找到任何预期的文件，列出目录内容以便调试
        if !hasMainLogic && !hasAppConfig && !hasH5Index && !hasRootIndex {
            print("⚠️ [DiminaEngine] 未找到预期的文件，列出目录内容:")
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
                for item in contents {
                    let isDirectory = (try? item.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
                    let type = isDirectory ? "📁" : "📄"
                    print("   \(type) \(item.lastPathComponent)")
                    
                    // 如果是目录，也检查其内容
                    if isDirectory {
                        do {
                            let subContents = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                            for subItem in subContents.prefix(5) { // 只显示前5个项目
                                let subIsDirectory = (try? subItem.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
                                let subType = subIsDirectory ? "📁" : "📄"
                                print("     \(subType) \(subItem.lastPathComponent)")
                            }
                            if subContents.count > 5 {
                                print("     ... 还有 \(subContents.count - 5) 个项目")
                            }
                        } catch {
                            print("     ❌ 无法读取子目录内容")
                        }
                    }
                }
            } catch {
                print("❌ [DiminaEngine] 无法列出目录内容: \(error.localizedDescription)")
            }
        }
        
        // Dimina 引擎优先检查特有文件，如果没有则检查传统文件
        let isValid = hasMainLogic || hasAppConfig || hasH5Index || hasRootIndex
        
        // 如果没有找到必要的文件，尝试修复 ZIP 文件结构
        if !isValid {
            print("🔧 [DiminaEngine] 尝试修复 ZIP 文件结构...")
            if tryFixZipStructure(path) {
                // 重新验证
                return isValidAppPath(path)
            }
            
            // 如果修复失败，尝试创建 index.html 入口文件
            print("🔧 [DiminaEngine] 尝试创建 index.html 入口文件...")
            if createDiminaIndexHtml(path) {
                // 重新验证
                return isValidAppPath(path)
            }
            
            // 如果创建 index.html 失败，尝试检查并创建入口页面
            print("🔧 [DiminaEngine] 尝试检查并创建入口页面...")
            if checkAndCreateEntryPage(path) {
                // 重新验证
                return isValidAppPath(path)
            }
        }
        
        print("🔍 [DiminaEngine] 路径验证结果: \(isValid ? "✅ 有效" : "❌ 无效")")
        return isValid
    }
    
    /// 尝试修复 ZIP 文件结构问题
    /// - Parameter path: 路径
    /// - Returns: 是否修复成功
    private func tryFixZipStructure(_ path: URL) -> Bool {
        print("🔧 [DiminaEngine] 尝试修复 ZIP 文件结构: \(path.path)")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            
            // 如果目录中只有一个项目，且该项目是一个目录，可能是 ZIP 文件解压后的常见结构
            if contents.count == 1, let firstItem = contents.first {
                let isDirectory = (try? firstItem.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
                
                if isDirectory {
                    print("📁 [DiminaEngine] 检测到单层目录结构，尝试展开...")
                    
                    // 检查这个子目录是否包含必要的文件
                    let subContents = try FileManager.default.contentsOfDirectory(at: firstItem, includingPropertiesForKeys: nil)
                    
                    // 如果子目录包含必要的文件，将其内容移动到父目录
                    let hasNecessaryFiles = subContents.contains { item in
                        let itemName = item.lastPathComponent.lowercased()
                        return itemName == "index.html" || itemName == "logic.js" || itemName == "app-config.json" || itemName == "main"
                    }
                    
                    if hasNecessaryFiles {
                        print("✅ [DiminaEngine] 子目录包含必要文件，开始展开...")
                        
                        for item in subContents {
                            let sourcePath = item
                            let destPath = path.appendingPathComponent(item.lastPathComponent)
                            try FileManager.default.moveItem(at: sourcePath, to: destPath)
                        }
                        
                        // 删除空的子目录
                        try FileManager.default.removeItem(at: firstItem)
                        print("✅ [DiminaEngine] ZIP 文件结构修复成功")
                        return true
                    }
                }
            }
            
            // 如果目录中有多个项目，检查是否有嵌套的目录结构
            for item in contents {
                let isDirectory = (try? item.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
                
                if isDirectory {
                    let itemName = item.lastPathComponent.lowercased()
                    
                    // 检查是否是常见的嵌套目录名
                    if itemName == "dist" || itemName == "build" || itemName == "public" || itemName == "www" {
                        print("📁 [DiminaEngine] 检测到构建目录: \(item.lastPathComponent)，尝试展开...")
                        
                        let subContents = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                        
                        for subItem in subContents {
                            let sourcePath = subItem
                            let destPath = path.appendingPathComponent(subItem.lastPathComponent)
                            try FileManager.default.moveItem(at: sourcePath, to: destPath)
                        }
                        
                        // 删除空的构建目录
                        try FileManager.default.removeItem(at: item)
                        print("✅ [DiminaEngine] ZIP 文件结构修复成功")
                        return true
                    }
                    
                    // 检查是否是 main 目录（Dimina 引擎特有）
                    if itemName == "main" {
                        print("📁 [DiminaEngine] 检测到 main 目录: \(item.lastPathComponent)，检查内容...")
                        
                        let subContents = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                        let hasLogicJs = subContents.contains { subItem in
                            subItem.lastPathComponent.lowercased() == "logic.js"
                        }
                        let hasAppConfig = subContents.contains { subItem in
                            subItem.lastPathComponent.lowercased() == "app-config.json"
                        }
                        
                        if hasLogicJs || hasAppConfig {
                            print("✅ [DiminaEngine] main 目录包含必要的 Dimina 引擎文件，无需修复")
                            return true
                        }
                    }
                }
            }
            
        } catch {
            print("❌ [DiminaEngine] 修复 ZIP 文件结构失败: \(error.localizedDescription)")
        }
        
        return false
    }
    
    /// 为 Dimina 引擎创建基本的 index.html 入口文件
    /// - Parameter path: 路径
    /// - Returns: 是否创建成功
    private func createDiminaIndexHtml(_ path: URL) -> Bool {
        print("🔧 [DiminaEngine] 尝试创建 Dimina 引擎入口文件...")
        
        let indexPath = path.appendingPathComponent("index.html")
        
        // 检查是否已经存在 index.html
        if FileManager.default.fileExists(atPath: indexPath.path) {
            print("✅ [DiminaEngine] index.html 已存在")
            return true
        }
        
        // 尝试从 app-config.json 读取入口页面信息
        let appConfigPath = path.appendingPathComponent("main/app-config.json")
        var entryPagePath = "pages/index/index"
        
        if FileManager.default.fileExists(atPath: appConfigPath.path) {
            do {
                let jsonData = try Data(contentsOf: appConfigPath)
                if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let entryPage = json["entryPagePath"] as? String {
                    entryPagePath = entryPage
                    print("📋 [DiminaEngine] 从 app-config.json 读取到入口页面: \(entryPagePath)")
                }
            } catch {
                print("⚠️ [DiminaEngine] 读取 app-config.json 失败，使用默认入口页面")
            }
        }
        
        // 创建基本的 Dimina 引擎入口文件
        let htmlContent = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Dimina 小程序</title>
            <style>
                body { margin: 0; padding: 20px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
                .loading { text-align: center; padding: 50px; }
                .error { color: red; text-align: center; padding: 50px; }
            </style>
        </head>
        <body>
            <div id="app">
                <div class="loading">正在加载 Dimina 小程序...</div>
            </div>
            
            <script>
                // Dimina 引擎入口
                try {
                    // 检查是否有 main/logic.js
                    if (typeof require !== 'undefined') {
                        const logic = require('./main/logic.js');
                        console.log('Dimina 引擎加载成功');
                        
                        // 如果有入口页面配置，尝试加载
                        if (logic && logic.entryPagePath) {
                            console.log('加载入口页面:', logic.entryPagePath);
                        }
                    } else {
                        // 如果 require 不可用，尝试动态加载
                        const script = document.createElement('script');
                        script.src = './main/logic.js';
                        script.onload = function() {
                            console.log('Dimina 引擎动态加载成功');
                        };
                        script.onerror = function() {
                            document.getElementById('app').innerHTML = '<div class="error">Dimina 引擎加载失败</div>';
                        };
                        document.head.appendChild(script);
                    }
                } catch (error) {
                    console.error('Dimina 引擎初始化失败:', error);
                    document.getElementById('app').innerHTML = '<div class="error">Dimina 引擎初始化失败</div>';
                }
            </script>
        </body>
        </html>
        """
        
        do {
            try htmlContent.write(to: indexPath, atomically: true, encoding: .utf8)
            print("✅ [DiminaEngine] 成功创建 index.html: \(indexPath.path)")
            return true
        } catch {
            print("❌ [DiminaEngine] 创建 index.html 失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 检查并创建入口页面文件
    /// - Parameter path: 路径
    /// - Returns: 是否成功
    private func checkAndCreateEntryPage(_ path: URL) -> Bool {
        print("🔧 [DiminaEngine] 检查入口页面文件...")
        
        let appConfigPath = path.appendingPathComponent("main/app-config.json")
        
        guard FileManager.default.fileExists(atPath: appConfigPath.path) else {
            print("⚠️ [DiminaEngine] app-config.json 不存在，无法确定入口页面")
            return false
        }
        
        do {
            let jsonData = try Data(contentsOf: appConfigPath)
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let entryPagePath = json["entryPagePath"] as? String else {
                print("⚠️ [DiminaEngine] 无法从 app-config.json 读取入口页面路径")
                return false
            }
            
            print("📋 [DiminaEngine] 入口页面路径: \(entryPagePath)")
            
            // 检查入口页面文件是否存在
            let entryPageFile = path.appendingPathComponent("main").appendingPathComponent(entryPagePath).appendingPathExtension("html")
            
            if FileManager.default.fileExists(atPath: entryPageFile.path) {
                print("✅ [DiminaEngine] 入口页面文件存在: \(entryPageFile.path)")
                return true
            } else {
                print("⚠️ [DiminaEngine] 入口页面文件不存在: \(entryPageFile.path)")
                
                // 尝试创建入口页面文件
                let htmlContent = """
                <!DOCTYPE html>
                <html lang="zh-CN">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>\(entryPagePath)</title>
                    <link rel="stylesheet" href="app.css">
                </head>
                <body>
                    <div id="app">
                        <div class="loading">正在加载页面: \(entryPagePath)</div>
                    </div>
                    
                    <script src="logic.js"></script>
                    <script src="\(entryPagePath).js"></script>
                </body>
                </html>
                """
                
                try htmlContent.write(to: entryPageFile, atomically: true, encoding: .utf8)
                print("✅ [DiminaEngine] 成功创建入口页面文件: \(entryPageFile.path)")
                return true
            }
            
        } catch {
            print("❌ [DiminaEngine] 处理入口页面失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - 文件处理
    
    /// 下载 ZIP 文件
    /// - Parameters:
    ///   - urlString: 下载URL
    ///   - destination: 目标文件路径
    /// - Returns: 是否下载成功
    private func downloadZipFile(from urlString: String, to destination: URL) async throws -> Bool {
        guard let url = URL(string: urlString) else {
            print("❌ [DiminaEngine] 无效的下载URL: \(urlString)")
            return false
        }
        
        print("📥 [DiminaEngine] 开始下载 ZIP 文件: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [DiminaEngine] 无效的HTTP响应")
                return false
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ [DiminaEngine] HTTP错误: \(httpResponse.statusCode)")
                return false
            }
            
            print("✅ [DiminaEngine] ZIP 文件下载完成，文件大小: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
            
            // 写入文件
            try data.write(to: destination)
            print("💾 [DiminaEngine] ZIP 文件保存成功: \(destination.path)")
            
            return true
        } catch {
            print("❌ [DiminaEngine] ZIP 文件下载失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// 解压 ZIP 文件
    /// - Parameters:
    ///   - zipFile: ZIP 文件路径
    ///   - destination: 解压目标路径
    /// - Returns: 是否解压成功
    private func extractZipFile(from zipFile: URL, to destination: URL) async throws -> Bool {
        print("📦 [DiminaEngine] 开始解压 ZIP 文件: \(zipFile.path)")
        print("📁 [DiminaEngine] 解压目标: \(destination.path)")
        
        // 检查 ZIP 文件是否存在
        guard FileManager.default.fileExists(atPath: zipFile.path) else {
            print("❌ [DiminaEngine] ZIP 文件不存在: \(zipFile.path)")
            return false
        }
        
        // 检查目标目录是否已存在文件
        if FileManager.default.fileExists(atPath: destination.path) {
            print("⚠️ [DiminaEngine] 目标目录已存在，检查是否有文件冲突...")
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
                if !contents.isEmpty {
                    print("📁 [DiminaEngine] 目标目录包含 \(contents.count) 个文件/文件夹")
                    
                    // 检查是否包含必要的文件
                    let indexPath = destination.appendingPathComponent("h5/index.html")
                    let indexPath2 = destination.appendingPathComponent("index.html")
                    
                    let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
                    let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)
                    
                    if hasH5Index || hasRootIndex {
                        print("✅ [DiminaEngine] 目标目录已包含有效的 index.html 文件，跳过解压")
                        return true
                    } else {
                        print("⚠️ [DiminaEngine] 目标目录存在但无效，将清理后重新解压")
                        
                        // 清理目标目录
                        try FileManager.default.removeItem(at: destination)
                        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
                        print("🧹 [DiminaEngine] 目标目录清理并重新创建成功")
                    }
                }
            } catch {
                print("⚠️ [DiminaEngine] 检查目标目录内容失败，将清理后重新解压: \(error.localizedDescription)")
                
                // 清理目标目录
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
                print("🧹 [DiminaEngine] 目标目录清理并重新创建成功")
            }
        }
        
        do {
            // 使用系统解压功能
            if #available(iOS 14.0, *) {
                try FileManager.default.unzipItem(at: zipFile, to: destination)
                print("✅ [DiminaEngine] ZIP 文件系统解压成功")
                return true
            } else {
                print("⚠️ [DiminaEngine] 系统版本过低，不支持 ZIP 解压")
                return false
            }
        } catch {
            print("❌ [DiminaEngine] ZIP 文件解压失败: \(error.localizedDescription)")
            
            // 如果是文件冲突错误，尝试清理后重新解压
            if error.localizedDescription.contains("已存在同名文件") {
                print("🔄 [DiminaEngine] 检测到文件冲突，尝试清理后重新解压...")
                
                do {
                    // 清理目标目录
                    try FileManager.default.removeItem(at: destination)
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
                    print("🧹 [DiminaEngine] 冲突文件清理成功，重新解压...")
                    
                    // 重新尝试解压
                    try FileManager.default.unzipItem(at: zipFile, to: destination)
                    print("✅ [DiminaEngine] ZIP 文件重新解压成功")
                    return true
                } catch {
                    print("❌ [DiminaEngine] 重新解压仍然失败: \(error.localizedDescription)")
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    // MARK: - EMP 文件处理
    
    /// 下载并解压 EMP 格式的小程序
    /// - Parameters:
    ///   - localPath: 本地路径
    ///   - downloadUrl: 下载URL
    /// - Returns: 是否下载成功
    private func downloadAndExtractEMPApp(localPath: URL, downloadUrl: String) async throws -> Bool {
        print("🚀 [DiminaEngine] 开始下载 EMP 格式小程序到指定路径: \(localPath.path)")
        print("🔗 [DiminaEngine] 下载地址: \(downloadUrl)")
        
        // 确保目录存在
        try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true, attributes: nil)
        print("✅ [DiminaEngine] 目标目录创建成功")
        
        // 创建临时目录用于下载
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DiminaEMP_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        print("📁 [DiminaEngine] 临时目录创建成功: \(tempDir.path)")
        
        // 下载文件到临时目录
        let tempFile = tempDir.appendingPathComponent("app.emp")
        print("⏳ [DiminaEngine] 开始下载 EMP 文件...")
        
        do {
            let success = try await downloadEMPFile(from: downloadUrl, to: tempFile)
            if !success {
                print("❌ [DiminaEngine] EMP 文件下载失败")
                return false
            }
            
            print("✅ [DiminaEngine] EMP 文件下载成功，开始解压...")
            
            // 解压 EMP 文件到目标目录
            let extractSuccess = try await extractEMPFile(from: tempFile, to: localPath)
            if extractSuccess {
                print("✅ [DiminaEngine] EMP 文件解压成功")
                
                // 验证解压结果
                if isValidAppPath(localPath) {
                    print("✅ [DiminaEngine] 文件验证通过，包含必要的 index.html 文件")
                } else {
                    print("⚠️ [DiminaEngine] 文件验证失败，可能缺少必要的文件")
                }
                
                // 注意：临时文件清理由主方法中的 defer 语句处理
                
                return true
            } else {
                print("❌ [DiminaEngine] EMP 文件解压失败")
                return false
            }
        } catch {
            print("❌ [DiminaEngine] 下载或解压过程中发生错误: \(error.localizedDescription)")
            // 注意：临时文件清理由主方法中的 defer 语句处理
            throw error
        }
    }
    
    /// 下载 EMP 文件
    /// - Parameters:
    ///   - urlString: 下载URL
    ///   - destination: 目标文件路径
    /// - Returns: 是否下载成功
    private func downloadEMPFile(from urlString: String, to destination: URL) async throws -> Bool {
        guard let url = URL(string: urlString) else {
            print("❌ [DiminaEngine] 无效的下载URL: \(urlString)")
            return false
        }
        
        print("📥 [DiminaEngine] 开始下载: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [DiminaEngine] 无效的HTTP响应")
                return false
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ [DiminaEngine] HTTP错误: \(httpResponse.statusCode)")
                return false
            }
            
            print("✅ [DiminaEngine] 下载完成，文件大小: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
            
            // 写入文件
            try data.write(to: destination)
            print("💾 [DiminaEngine] 文件保存成功: \(destination.path)")
            
            return true
        } catch {
            print("❌ [DiminaEngine] 下载失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// 解压 EMP 文件
    /// - Parameters:
    ///   - empFile: EMP 文件路径
    ///   - destination: 解压目标路径
    /// - Returns: 是否解压成功
    private func extractEMPFile(from empFile: URL, to destination: URL) async throws -> Bool {
        print("📦 [DiminaEngine] 开始解压 EMP 文件: \(empFile.path)")
        print("📁 [DiminaEngine] 解压目标: \(destination.path)")
        
        // 检查 EMP 文件是否存在
        guard FileManager.default.fileExists(atPath: empFile.path) else {
            print("❌ [DiminaEngine] EMP 文件不存在: \(empFile.path)")
            return false
        }
        
        do {
            // 尝试使用系统解压功能
            let extractSuccess = try await extractWithSystemArchive(empFile: empFile, destination: destination)
            if extractSuccess {
                return true
            }
            
            // 如果系统解压失败，尝试自定义解压逻辑
            print("⚠️ [DiminaEngine] 系统解压失败，尝试自定义解压逻辑")
            return try await extractWithCustomLogic(empFile: empFile, destination: destination)
            
        } catch {
            print("❌ [DiminaEngine] 解压失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// 使用系统解压功能
    /// - Parameters:
    ///   - empFile: EMP 文件路径
    ///   - destination: 解压目标路径
    /// - Returns: 是否解压成功
    private func extractWithSystemArchive(empFile: URL, destination: URL) async throws -> Bool {
        print("🔧 [DiminaEngine] 尝试使用系统解压功能")
        
        do {
            // 使用 FileManager 的 unzipItem 方法（iOS 14.0+）
            if #available(iOS 14.0, *) {
                try FileManager.default.unzipItem(at: empFile, to: destination)
                print("✅ [DiminaEngine] 系统解压成功")
                return true
            } else {
                print("⚠️ [DiminaEngine] 系统版本过低，不支持 unzipItem")
                return false
            }
        } catch {
            print("❌ [DiminaEngine] 系统解压失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 使用自定义解压逻辑
    /// - Parameters:
    ///   - empFile: EMP 文件路径
    ///   - destination: 解压目标路径
    /// - Returns: 是否解压成功
    private func extractWithCustomLogic(empFile: URL, destination: URL) async throws -> Bool {
        print("🔧 [DiminaEngine] 使用自定义解压逻辑")
        
        // 这里可以实现自定义的 EMP 文件解压逻辑
        // 由于 EMP 可能是特殊的压缩格式，需要根据具体格式实现
        
        // 临时实现：尝试将 EMP 文件作为 ZIP 文件处理
        do {
            // 重命名为 .zip 文件
            let zipFile = empFile.deletingPathExtension().appendingPathExtension("zip")
            try FileManager.default.moveItem(at: empFile, to: zipFile)
            
            print("📝 [DiminaEngine] 重命名文件为 .zip: \(zipFile.path)")
            
            // 尝试解压 ZIP 文件
            if #available(iOS 14.0, *) {
                try FileManager.default.unzipItem(at: zipFile, to: destination)
                print("✅ [DiminaEngine] ZIP 解压成功")
                
                // 恢复原文件名
                try FileManager.default.moveItem(at: zipFile, to: empFile)
                return true
            } else {
                print("⚠️ [DiminaEngine] 系统版本过低，不支持 ZIP 解压")
                // 恢复原文件名
                try FileManager.default.moveItem(at: zipFile, to: empFile)
                return false
            }
        } catch {
            print("❌ [DiminaEngine] 自定义解压失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 下载并解压 ZIP 格式的小程序（使用临时目录策略）
    /// - Parameters:
    ///   - localPath: 本地路径
    ///   - downloadUrl: 下载URL
    ///   - tempDir: 临时目录
    /// - Returns: 是否下载成功
    private func downloadAndExtractZipApp(localPath: URL, downloadUrl: String, tempDir: URL) async throws -> Bool {
        print("🚀 [DiminaEngine] 开始下载 ZIP 格式小程序")
        print("📁 [DiminaEngine] 目标路径: \(localPath.path)")
        print("🔗 [DiminaEngine] 下载地址: \(downloadUrl)")
        print("📁 [DiminaEngine] 临时目录: \(tempDir.path)")
        
        // 下载 ZIP 文件到临时目录
        let tempFile = tempDir.appendingPathComponent("app.zip")
        print("⏳ [DiminaEngine] 开始下载 ZIP 文件...")
        
        do {
            let success = try await downloadZipFile(from: downloadUrl, to: tempFile)
            if !success {
                print("❌ [DiminaEngine] ZIP 文件下载失败")
                return false
            }
            
            print("✅ [DiminaEngine] ZIP 文件下载成功，开始解压到临时目录...")
            
            // 解压 ZIP 文件到临时目录
            let tempExtractDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true, attributes: nil)
            
            let extractSuccess = try await extractZipFile(from: tempFile, to: tempExtractDir)
            if !extractSuccess {
                print("❌ [DiminaEngine] ZIP 文件解压到临时目录失败")
                return false
            }
            
                            print("✅ [DiminaEngine] ZIP 文件解压到临时目录成功")
                
                // 验证解压结果 - 先检查临时目录的基本结构
                print("🔍 [DiminaEngine] 检查临时目录结构: \(tempExtractDir.path)")
                do {
                    let tempContents = try FileManager.default.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil)
                    print("📁 [DiminaEngine] 临时目录包含 \(tempContents.count) 个项目:")
                    for item in tempContents {
                        let isDirectory = (try? item.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
                        let type = isDirectory ? "📁" : "📄"
                        print("   \(type) \(item.lastPathComponent)")
                    }
                } catch {
                    print("⚠️ [DiminaEngine] 无法列出临时目录内容: \(error.localizedDescription)")
                }
                
                // 不在这里进行完整验证，等文件移动到最终位置后再验证
                
                // 如果目标目录已存在，先备份或删除
                var backupDir: URL?
                if FileManager.default.fileExists(atPath: localPath.path) {
                    print("📁 [DiminaEngine] 目标目录已存在，准备进行版本升级...")
                    
                    // 创建备份目录（可选）
                    backupDir = localPath.deletingLastPathComponent().appendingPathComponent("\(localPath.lastPathComponent)_backup_\(Int(Date().timeIntervalSince1970))")
                    
                    do {
                        // 先尝试备份
                        try FileManager.default.moveItem(at: localPath, to: backupDir!)
                        print("✅ [DiminaEngine] 原版本备份成功: \(backupDir!.path)")
                    } catch {
                        print("⚠️ [DiminaEngine] 备份失败，直接删除原版本: \(error.localizedDescription)")
                        try FileManager.default.removeItem(at: localPath)
                        backupDir = nil
                    }
                }
                
                // 确保目标目录存在
                try FileManager.default.createDirectory(at: localPath.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                
                // 将临时目录中的内容移动到目标目录
                print("🔄 [DiminaEngine] 开始将文件从临时目录移动到目标目录...")
                
                do {
                    // 获取临时目录中的内容
                    let tempContents = try FileManager.default.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil)
                    
                    // 如果临时目录中只有一个子目录，直接移动该子目录的内容
                    if tempContents.count == 1, let firstItem = tempContents.first {
                        
                        let sourcePath = firstItem
                        let isDirectory = (try? sourcePath.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
                        
                        if isDirectory {
                            // 移动子目录的内容到目标目录
                            try FileManager.default.moveItem(at: sourcePath, to: localPath)
                            print("✅ [DiminaEngine] 文件移动成功")
                        } else {
                            // 移动文件到目标目录
                            try FileManager.default.moveItem(at: sourcePath, to: localPath)
                            print("✅ [DiminaEngine] 文件移动成功")
                        }
                    } else {
                        // 移动所有内容到目标目录
                        for item in tempContents {
                            let sourcePath = item
                            let destPath = localPath.appendingPathComponent(item.lastPathComponent)
                            try FileManager.default.moveItem(at: sourcePath, to: destPath)
                        }
                        print("✅ [DiminaEngine] 所有内容移动成功")
                    }
                
                print("✅ [DiminaEngine] 版本升级完成: \(localPath.path)")
                
                // 现在验证最终目录
                print("🔍 [DiminaEngine] 验证最终目录: \(localPath.path)")
                if isValidAppPath(localPath) {
                    print("✅ [DiminaEngine] 最终目录验证通过")
                    
                    // 版本升级成功，清理备份文件夹
                    if let backupDir = backupDir, FileManager.default.fileExists(atPath: backupDir.path) {
                        do {
                            try FileManager.default.removeItem(at: backupDir)
                            print("🧹 [DiminaEngine] 备份文件夹清理成功: \(backupDir.path)")
                        } catch {
                            print("⚠️ [DiminaEngine] 备份文件夹清理失败: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print("❌ [DiminaEngine] 最终目录验证失败")
                    
                    // 尝试最后一次修复
                    print("🔧 [DiminaEngine] 尝试最后一次修复...")
                    if tryFixZipStructure(localPath) && isValidAppPath(localPath) {
                        print("✅ [DiminaEngine] 修复后验证通过")
                        
                        // 修复成功，清理备份文件夹
                        if let backupDir = backupDir, FileManager.default.fileExists(atPath: backupDir.path) {
                            do {
                                try FileManager.default.removeItem(at: backupDir)
                                print("🧹 [DiminaEngine] 备份文件夹清理成功: \(backupDir.path)")
                            } catch {
                                print("⚠️ [DiminaEngine] 备份文件夹清理失败: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        print("❌ [DiminaEngine] 修复后仍然验证失败")
                        // 如果验证失败，尝试恢复备份
                        if let backupDir = backupDir, FileManager.default.fileExists(atPath: backupDir.path) {
                            print("🔄 [DiminaEngine] 尝试恢复原版本...")
                            try? FileManager.default.removeItem(at: localPath)
                            try? FileManager.default.moveItem(at: backupDir, to: localPath)
                            print("✅ [DiminaEngine] 原版本恢复成功")
                        }
                        return false
                    }
                }
                
                // 注意：临时文件清理由主方法中的 defer 语句处理
                
                return true
                
            } catch {
                print("❌ [DiminaEngine] 文件移动失败: \(error.localizedDescription)")
                
                // 如果移动失败，尝试恢复备份
                if let backupDir = backupDir, FileManager.default.fileExists(atPath: backupDir.path) {
                    print("🔄 [DiminaEngine] 尝试恢复原版本...")
                    try? FileManager.default.moveItem(at: backupDir, to: localPath)
                    print("✅ [DiminaEngine] 原版本恢复成功")
                }
                
                throw error
            }
            
        } catch {
            print("❌ [DiminaEngine] ZIP 文件下载或解压过程中发生错误: \(error.localizedDescription)")
            // 注意：临时文件清理由主方法中的 defer 语句处理
            throw error
        }
    }
    
    /// 下载并解压 EMP 格式的小程序（使用临时目录策略）
    /// - Parameters:
    ///   - localPath: 本地路径
    ///   - downloadUrl: 下载URL
    ///   - tempDir: 临时目录
    /// - Returns: 是否下载成功
    private func downloadAndExtractEMPApp(localPath: URL, downloadUrl: String, tempDir: URL) async throws -> Bool {
        print("🚀 [DiminaEngine] 开始下载 EMP 格式小程序")
        print("📁 [DiminaEngine] 目标路径: \(localPath.path)")
        print("🔗 [DiminaEngine] 下载地址: \(downloadUrl)")
        print("📁 [DiminaEngine] 临时目录: \(tempDir.path)")
        
        // 下载 EMP 文件到临时目录
        let tempFile = tempDir.appendingPathComponent("app.emp")
        print("⏳ [DiminaEngine] 开始下载 EMP 文件...")
        
        do {
            let success = try await downloadEMPFile(from: downloadUrl, to: tempFile)
            if !success {
                print("❌ [DiminaEngine] EMP 文件下载失败")
                return false
            }
            
            print("✅ [DiminaEngine] EMP 文件下载成功，开始解压到临时目录...")
            
            // 解压 EMP 文件到临时目录
            let tempExtractDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true, attributes: nil)
            
            let extractSuccess = try await extractEMPFile(from: tempFile, to: tempExtractDir)
            if !extractSuccess {
                print("❌ [DiminaEngine] EMP 文件解压到临时目录失败")
                return false
            }
            
            print("✅ [DiminaEngine] EMP 文件解压到临时目录成功")
            
            // 检查临时目录结构 - 不进行完整验证
            print("🔍 [DiminaEngine] 检查临时目录结构: \(tempExtractDir.path)")
            do {
                let tempContents = try FileManager.default.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil)
                print("📁 [DiminaEngine] 临时目录包含 \(tempContents.count) 个项目:")
                for item in tempContents {
                    let isDirectory = (try? item.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
                    let type = isDirectory ? "📁" : "📄"
                    print("   \(type) \(item.lastPathComponent)")
                }
            } catch {
                print("⚠️ [DiminaEngine] 无法列出临时目录内容: \(error.localizedDescription)")
            }
            
            // 如果目标目录已存在，先备份或删除
            var backupDir: URL?
            if FileManager.default.fileExists(atPath: localPath.path) {
                print("📁 [DiminaEngine] 目标目录已存在，准备进行版本升级...")
                
                // 创建备份目录（可选）
                backupDir = localPath.deletingLastPathComponent().appendingPathComponent("\(localPath.lastPathComponent)_backup_\(Int(Date().timeIntervalSince1970))")
                
                do {
                    // 先尝试备份
                    try FileManager.default.moveItem(at: localPath, to: backupDir!)
                    print("✅ [DiminaEngine] 原版本备份成功: \(backupDir!.path)")
                } catch {
                    print("⚠️ [DiminaEngine] 备份失败，直接删除原版本: \(error.localizedDescription)")
                    try FileManager.default.removeItem(at: localPath)
                    backupDir = nil
                }
            }
            
            // 确保目标目录存在
            try FileManager.default.createDirectory(at: localPath.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            
            // 将临时目录中的内容移动到目标目录
            print("🔄 [DiminaEngine] 开始将文件从临时目录移动到目标目录...")
            
            do {
                // 获取临时目录中的内容
                let tempContents = try FileManager.default.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil)
                
                // 如果临时目录中只有一个子目录，直接移动该子目录的内容
                if tempContents.count == 1, let firstItem = tempContents.first {
                    let sourcePath = firstItem
                    let isDirectory = (try? sourcePath.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
                    
                    if isDirectory {
                        // 移动子目录的内容到目标目录
                        try FileManager.default.moveItem(at: sourcePath, to: localPath)
                        print("✅ [DiminaEngine] 子目录内容移动成功")
                    } else {
                        // 移动文件到目标目录
                        try FileManager.default.moveItem(at: sourcePath, to: localPath)
                        print("✅ [DiminaEngine] 文件移动成功")
                    }
                } else {
                    // 移动所有内容到目标目录
                    for item in tempContents {
                        let sourcePath = item
                        let destPath = localPath.appendingPathComponent(item.lastPathComponent)
                        try FileManager.default.moveItem(at: sourcePath, to: destPath)
                    }
                    print("✅ [DiminaEngine] 所有内容移动成功")
                }
                
                print("✅ [DiminaEngine] 版本升级完成: \(localPath.path)")
                
                // 现在验证最终目录
                print("🔍 [DiminaEngine] 验证最终目录: \(localPath.path)")
                if isValidAppPath(localPath) {
                    print("✅ [DiminaEngine] 最终目录验证通过")
                    
                    // 版本升级成功，清理备份文件夹
                    if let backupDir = backupDir, FileManager.default.fileExists(atPath: backupDir.path) {
                        do {
                            try FileManager.default.removeItem(at: backupDir)
                            print("🧹 [DiminaEngine] 备份文件夹清理成功: \(backupDir.path)")
                        } catch {
                            print("⚠️ [DiminaEngine] 备份文件夹清理失败: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print("❌ [DiminaEngine] 最终目录验证失败")
                    
                    // 尝试最后一次修复
                    print("🔧 [DiminaEngine] 尝试最后一次修复...")
                    if tryFixZipStructure(localPath) && isValidAppPath(localPath) {
                        print("✅ [DiminaEngine] 修复后验证通过")
                        
                        // 修复成功，清理备份文件夹
                        if let backupDir = backupDir, FileManager.default.fileExists(atPath: backupDir.path) {
                            do {
                                try FileManager.default.removeItem(at: backupDir)
                                print("🧹 [DiminaEngine] 备份文件夹清理成功: \(backupDir.path)")
                            } catch {
                                print("⚠️ [DiminaEngine] 备份文件夹清理失败: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        print("❌ [DiminaEngine] 修复后仍然验证失败")
                        // 如果验证失败，尝试恢复备份
                        if let backupDir = backupDir, FileManager.default.fileExists(atPath: backupDir.path) {
                            print("🔄 [DiminaEngine] 尝试恢复原版本...")
                            try? FileManager.default.removeItem(at: localPath)
                            try? FileManager.default.moveItem(at: backupDir, to: localPath)
                            print("✅ [DiminaEngine] 原版本恢复成功")
                        }
                        return false
                    }
                }
                
                // 注意：临时文件清理由主方法中的 defer 语句处理
                
                return true
                
            } catch {
                print("❌ [DiminaEngine] 文件移动失败: \(error.localizedDescription)")
                
                // 如果移动失败，尝试恢复备份
                if let backupDir = backupDir, FileManager.default.fileExists(atPath: backupDir.path) {
                    print("🔄 [DiminaEngine] 尝试恢复原版本...")
                    try? FileManager.default.moveItem(at: backupDir, to: localPath)
                    print("✅ [DiminaEngine] 原版本恢复成功")
                }
                
                throw error
                }
                
        } catch {
            print("❌ [DiminaEngine] EMP 文件下载或解压过程中发生错误: \(error.localizedDescription)")
            // 注意：临时文件清理由主方法中的 defer 语句处理
            throw error
        }
    }
}
