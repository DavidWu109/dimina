import Foundation
import echo_entity_swift
import RxSwift
import MMKV
import KurilUniversalKit

public class AppConfigManager: DisposeBagProvider {
    public static let shared = AppConfigManager()
    
    private init() {}
    
    // MARK: - 配置读取
    
    /// 获取小程序信息
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - type: 环境类型
    /// - Returns: 小程序信息
    public func loadMiniProgram(appId: String, type: String?) async -> MiniProgramInfo? {
        return await withCheckedContinuation { continuation in
            
            let string = MMKV.default()?.string(forKey: "lookup_apps_list")
            let apps = [MiniProgramInfo].deserialize(from: string)?.compactMap({ $0 })
            
            if let app = apps?.first(where: { $0.id == appId }) {
                continuation.resume(returning: app)
            } else {
                Network.miniProgramLookupAppDetail(appId: appId, type: type)
                    .request()
                    .asObservable()
                    .mapObject(to: KurilBaseResponse<MiniProgramInfo>.self)
                    .subscribe(onNext: { response in
                        continuation.resume(returning: response.data)
                    }, onError: { error in
                        continuation.resume(returning: nil)
                    })
                    .disposed(by: self.disposeBag)
            }
        }
    }
        
    /// 获取本地已安装的小程序配置列表
    /// - Returns: 小程序配置数组
    public func getLocalAppConfigs() -> [Any] {
        // 注意：这里返回空数组，因为不再在这个库里处理Dimina版本
        // 外部需要自己管理Dimina版本的检测
        // 返回类型改为 [Any] 以避免依赖特定的配置类型
        return []
    }
    
    // MARK: - 下载管理
    
    /// 检查并下载小程序
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    ///   - downloadUrl: 下载URL
    /// - Returns: 是否下载成功
    @discardableResult
    public func downloadAndExtractApp(appId: String, versionCode: String, downloadUrl: String) async throws -> Bool {
        return (try? await DownloadManager.shared.downloadAndExtract(appId: appId, versionCode: versionCode, downloadUrl: downloadUrl)) != nil
    }
    
    /// 引擎类型枚举
    public enum EngineType: String, CaseIterable {
        case dimina = "dimina"
        case webview = "webview"
        
        public var description: String {
            switch self {
            case .dimina: return "Dimina 引擎"
            case .webview: return "WebView 引擎"
            }
        }
    }
    
    /// 检查小程序是否已缓存（统一方法）
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    ///   - engineType: 引擎类型（nil=检查所有引擎，.dimina=只检查Dimina引擎，.webview=只检查WebView引擎）
    /// - Returns: 是否已缓存
    public func isAppCached(
        appId: String, 
        versionCode: String,
        engineType: EngineType? = nil
    ) -> Bool {
        debugPrint("🔍 [AppConfigManager] 检查小程序缓存: \(appId), 版本: \(versionCode), 引擎: \(engineType?.description ?? "所有引擎")")
        return checkAppCache(appId: appId, versionCode: versionCode, engineType: engineType)
    }
    
    /// 检查小程序缓存（明确指定引擎）
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    ///   - engineType: 引擎类型（nil=检查所有引擎）
    /// - Returns: 是否已缓存
    private func checkAppCache(appId: String, versionCode: String, engineType: EngineType? = nil) -> Bool {
        debugPrint("🔍 [AppConfigManager] 开始检查缓存: \(appId)")
        
        if let engineType = engineType {
            // 检查指定引擎
            switch engineType {
            case .dimina:
                return checkDiminaEngineCache(appId: appId, versionCode: versionCode)
            case .webview:
                return checkWebViewEngineCache(appId: appId, versionCode: versionCode)
            }
        } else {
            // 检查所有引擎
            // 1. 检查 Dimina 引擎缓存
            let diminaCached = checkDiminaEngineCache(appId: appId, versionCode: versionCode)
            if diminaCached {
                debugPrint("✅ [AppConfigManager] 找到 Dimina 引擎缓存")
                return true
            }
            
            // 2. 检查 WebView 引擎缓存
            let webViewCached = checkWebViewEngineCache(appId: appId, versionCode: versionCode)
            if webViewCached {
                debugPrint("✅ [AppConfigManager] 找到 WebView 引擎缓存")
                return true
            }
            
            debugPrint("❌ [AppConfigManager] 未找到任何引擎缓存")
            return false
        }
    }
    
    /// 检查 Dimina 引擎缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    /// - Returns: 是否已缓存
    private func checkDiminaEngineCache(appId: String, versionCode: String) -> Bool {
        debugPrint("🔍 [AppConfigManager] 检查 Dimina 引擎缓存...")
        return checkEngineCache(appId: appId, versionCode: versionCode, engineType: .dimina)
    }
    
    /// 检查 WebView 引擎缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    /// - Returns: 是否已缓存
    private func checkWebViewEngineCache(appId: String, versionCode: String) -> Bool {
        debugPrint("🔍 [AppConfigManager] 检查 WebView 引擎缓存...")
        return checkEngineCache(appId: appId, versionCode: versionCode, engineType: .webview)
    }
    
    /// 检查指定引擎的缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    ///   - engineType: 引擎类型
    /// - Returns: 是否已缓存
    private func checkEngineCache(appId: String, versionCode: String, engineType: EngineType) -> Bool {
        let localPath = getEngineLocalPath(appId: appId, versionCode: versionCode, engineType: engineType)
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            debugPrint("❌ [AppConfigManager] 引擎路径不存在: \(localPath.path)")
            return false
        }

        // 检查 index.html（可能在根目录或 h5 子目录）
        let indexPath = localPath.appendingPathComponent("index.html")
        let h5IndexPath = localPath.appendingPathComponent("h5/index.html")
        let hasIndex = FileManager.default.fileExists(atPath: indexPath.path)
        let hasH5Index = FileManager.default.fileExists(atPath: h5IndexPath.path)

        debugPrint("🔍 [AppConfigManager] 检查 \(engineType.description) 路径: \(localPath.path)")
        debugPrint("🔍 [AppConfigManager] 检查 index.html: \(indexPath.path) -> \(hasIndex)")
        debugPrint("🔍 [AppConfigManager] 检查 h5/index.html: \(h5IndexPath.path) -> \(hasH5Index)")

        return hasIndex || hasH5Index
    }
    
    /// 获取引擎本地路径
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    ///   - engineType: 引擎类型
    /// - Returns: 本地路径
    private func getEngineLocalPath(appId: String, versionCode: String, engineType: EngineType) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        switch engineType {
        case .dimina:
            // Dimina 引擎路径: Documents/Dimina/appId/versionCode/
            return documentsPath
                .appendingPathComponent("Dimina")
                .appendingPathComponent(appId)
                .appendingPathComponent(versionCode)
        case .webview:
            // WebView 引擎路径: Documents/ew/appId/versionCode/
            return documentsPath
                .appendingPathComponent("ew")
                .appendingPathComponent(appId)
                .appendingPathComponent(versionCode)
        }
    }
    
    // MARK: - 引擎特定缓存检查方法
    
    /// 检查 Dimina 引擎缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    /// - Returns: 是否已缓存
    public func isDiminaEngineCached(appId: String, versionCode: String) -> Bool {
        return isAppCached(appId: appId, versionCode: versionCode, engineType: .dimina)
    }
    
    /// 检查 WebView 引擎缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    /// - Returns: 是否已缓存
    public func isWebViewEngineCached(appId: String, versionCode: String) -> Bool {
        return isAppCached(appId: appId, versionCode: versionCode, engineType: .webview)
    }
    
    
    /// 获取小程序下载信息
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    /// - Returns: 下载信息
    public func getDownloadInfo(appId: String, versionCode: String) async -> MiniProgramDownloadInfo? {
        do {
            let response: KurilBaseResponse<MiniProgramDownloadInfo>? = try await Network.miniProgramDownload(appId: appId, versionCode: versionCode).requestByAsync()
            if let downloadInfo = response?.data {
                // 自动缓存下载信息
                cacheDownloadInfo(appId: appId, versionCode: versionCode, downloadInfo: downloadInfo)
                return downloadInfo
            }
            return nil
        } catch {
            debugPrint("获取小程序下载信息失败: \(error)")
            return nil
        }
    }
    
    /// 获取小程序下载信息（同步版本，从缓存获取）
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    /// - Returns: 下载信息
    public func getDownloadInfoSync(appId: String, versionCode: String) -> MiniProgramDownloadInfo? {
        // 这里可以从本地缓存获取下载信息
        // 例如从 UserDefaults 或 MMKV 中读取
        let cacheKey = "download_info_\(appId)_\(versionCode)"
        if let data = MMKV.default()?.data(forKey: cacheKey),
           let downloadInfo = try? JSONDecoder().decode(MiniProgramDownloadInfo.self, from: data) {
            return downloadInfo
        }
        return nil
    }
    
    /// 缓存小程序下载信息
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号
    ///   - downloadInfo: 下载信息
    public func cacheDownloadInfo(appId: String, versionCode: String, downloadInfo: MiniProgramDownloadInfo) {
        let cacheKey = "download_info_\(appId)_\(versionCode)"
        if let data = try? JSONEncoder().encode(downloadInfo) {
            MMKV.default()?.set(data, forKey: cacheKey)
        }
    }
    
    // MARK: - 环境管理
    
    /// 获取本地路径
    /// - Parameter env: 环境类型
    /// - Returns: 本地路径
    public func getLocalPath(env: MiniAPPType) -> URL {
        return DownloadManager.shared.getLocalPath(env: env)
    }
    
    /// 获取基础URL
    /// - Parameter type: 环境类型
    /// - Returns: 基础URL
    public func getBaseURL(_ type: MiniAPPType) -> URL {
        return getLocalPath(env: type).appendingPathComponent("h5/index.html")
    }
    
    // MARK: - 版本检查
    
    /// 检查小程序更新
    /// - Parameter currentInfo: 当前小程序信息
    public func checkUpdate(currentInfo: MiniProgramInfo) {
        // 这里可以添加版本检查逻辑
        // 例如检查是否有新版本可用
    }
    
    // MARK: - Dimina Engine 支持
    
    /// 获取 Dimina Engine 的本地路径
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（必需，用于路径构建）
    /// - Returns: Dimina Engine 的本地路径
    public func getDiminaLocalPath(appId: String, versionCode: String? = nil) -> URL {
        debugPrint("🔍 [AppConfigManager] 获取 Dimina 本地路径: \(appId)")
        if let versionCode = versionCode {
            debugPrint("📋 [AppConfigManager] 版本号: \(versionCode)")
        }
        
        // 获取应用的 Documents 目录
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "")
        debugPrint("📁 [AppConfigManager] Documents 目录: \(documentsPath.path)")
        
        // 构建 Dimina 目录路径
        let diminaPath = documentsPath.appendingPathComponent("Dimina")
        debugPrint("🗂️ [AppConfigManager] Dimina 根目录: \(diminaPath.path)")
        
        // 使用 appId 和版本号构建路径
        let appPath = diminaPath.appendingPathComponent(appId)
        let finalPath: URL
        
        if let versionCode = versionCode, !versionCode.isEmpty {
            // 如果有版本号，创建版本号子文件夹
            finalPath = appPath.appendingPathComponent(versionCode)
            debugPrint("📋 [AppConfigManager] 最终路径（包含版本号）: \(finalPath.path)")
            debugPrint("💡 [AppConfigManager] 注意：Dimina 资源包解压到版本号子文件夹中")
        } else {
            // 如果没有版本号，直接使用 appId 目录
            finalPath = appPath
            debugPrint("📋 [AppConfigManager] 最终路径（无版本号）: \(finalPath.path)")
            debugPrint("💡 [AppConfigManager] 注意：Dimina 资源包直接解压到 appId 目录，不创建版本号子文件夹")
        }
        
        return finalPath
    }
    
    /// 检查 Dimina Engine 小程序是否已缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    /// - Returns: 是否已缓存
    public func isDiminaAppCached(appId: String, versionCode: String? = nil) -> Bool {
        debugPrint("🔍 [AppConfigManager] 检查 Dimina 小程序缓存: \(appId)")
        
        let localPath = getDiminaLocalPath(appId: appId, versionCode: versionCode)
        
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            debugPrint("❌ [AppConfigManager] Dimina 小程序目录不存在: \(localPath.path)")
            return false
        }
        
        debugPrint("✅ [AppConfigManager] Dimina 小程序目录存在，检查必要文件...")
        
        // 检查 Dimina 引擎特有的目录结构（localPath 已包含 appId/version）
        let mainLogicPath = localPath.appendingPathComponent("main/logic.js")

        // 检查是否包含 Dimina 引擎特有的文件
        let hasMainLogic = FileManager.default.fileExists(atPath: mainLogicPath.path)

        if hasMainLogic {
            debugPrint("✅ [AppConfigManager] 找到 Dimina 引擎特有文件: \(mainLogicPath.path)")
        }

        // 检查是否包含必要的文件（兼容传统结构）
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        let indexPath2 = localPath.appendingPathComponent("index.html")

        let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
        let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)

        if hasH5Index {
            debugPrint("✅ [AppConfigManager] 找到 h5/index.html 文件")
        }
        if hasRootIndex {
            debugPrint("✅ [AppConfigManager] 找到 index.html 文件")
        }

        // Dimina 引擎优先检查特有文件，如果没有则检查传统文件
        let isCached = hasMainLogic || hasH5Index || hasRootIndex
        if isCached {
            debugPrint("✅ [AppConfigManager] Dimina 小程序已缓存: \(appId)")
        } else {
            debugPrint("❌ [AppConfigManager] Dimina 小程序未缓存，缺少必要的文件")
        }

        return isCached
    }
    
    /// 检查 Dimina 版本的 dev 环境小程序是否已缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    /// - Returns: 是否已缓存
    public func isDiminaDevAppCached(appId: String, versionCode: String? = nil) -> Bool {
        debugPrint("🔍 [AppConfigManager] 检查 Dimina dev 版本小程序缓存: \(appId)")
        
        // 对于 dev 环境，检查 Dimina 引擎特有的文件结构
        let localPath = getDiminaLocalPath(appId: appId, versionCode: versionCode)
        
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            debugPrint("❌ [AppConfigManager] Dimina dev 小程序目录不存在: \(localPath.path)")
            return false
        }
        
        debugPrint("✅ [AppConfigManager] Dimina dev 小程序目录存在，检查必要文件...")
        
        // 检查 Dimina 引擎特有的目录结构（localPath 已包含 appId/version）
        let mainLogicPath = localPath.appendingPathComponent("main/logic.js")
        let devConfigPath = localPath.appendingPathComponent("dev/config.json")
        
        // 检查是否包含 Dimina 引擎特有的文件
        let hasMainLogic = FileManager.default.fileExists(atPath: mainLogicPath.path)
        let hasDevConfig = FileManager.default.fileExists(atPath: devConfigPath.path)
        
        if hasMainLogic {
            debugPrint("✅ [AppConfigManager] 找到 Dimina 引擎特有文件: \(mainLogicPath.path)")
        }
        if hasDevConfig {
            debugPrint("✅ [AppConfigManager] 找到 dev 配置文件: \(devConfigPath.path)")
        }
        
        // 检查是否包含必要的文件（兼容传统结构）
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        let indexPath2 = localPath.appendingPathComponent("index.html")
        
        let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
        let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)
        
        if hasH5Index {
            debugPrint("✅ [AppConfigManager] 找到 h5/index.html 文件")
        }
        if hasRootIndex {
            debugPrint("✅ [AppConfigManager] 找到 index.html 文件")
        }
        
        // Dimina dev 版本优先检查特有文件，包括 dev 配置
        let isCached = hasMainLogic || hasDevConfig || hasH5Index || hasRootIndex
        if isCached {
            debugPrint("✅ [AppConfigManager] Dimina dev 版本小程序已缓存: \(appId)")
        } else {
            debugPrint("❌ [AppConfigManager] Dimina dev 版本小程序未缓存，缺少必要的文件")
        }
        
        return isCached
    }
    
    /// 检查 Dimina Engine 小程序是否已缓存（使用模拟器路径）
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    ///   - deviceId: 模拟器设备ID
    ///   - appContainerId: 应用容器ID
    /// - Returns: 是否已缓存
    public func isDiminaAppCachedWithSimulator(appId: String, 
                                              versionCode: String? = nil,
                                              deviceId: String,
                                              appContainerId: String) -> Bool {
        debugPrint("🔍 [AppConfigManager] 检查模拟器路径下的 Dimina 小程序缓存: \(appId)")
        debugPrint("📱 [AppConfigManager] 设备ID: \(deviceId)")
        debugPrint("📱 [AppConfigManager] 应用容器ID: \(appContainerId)")
        
        // 构建模拟器路径
        let simulatorPath = "/Users/david/Library/Developer/CoreSimulator/Devices/\(deviceId)/data/Containers/Data/Application/\(appContainerId)/Documents/Dimina"
        let basePath = URL(fileURLWithPath: simulatorPath)
        
        // 使用 appId 和版本号构建路径
        let appPath = basePath.appendingPathComponent(appId)
        let localPath: URL
        
        if let versionCode = versionCode, !versionCode.isEmpty {
            // 如果有版本号，创建版本号子文件夹
            localPath = appPath.appendingPathComponent(versionCode)
        } else {
            // 如果没有版本号，直接使用 appId 目录
            localPath = appPath
        }
        
        debugPrint("📁 [AppConfigManager] 模拟器路径: \(localPath.path)")
        
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            debugPrint("❌ [AppConfigManager] 模拟器路径下的 Dimina 小程序目录不存在")
            return false
        }
        
        debugPrint("✅ [AppConfigManager] 模拟器路径下的 Dimina 小程序目录存在，检查必要文件...")
        
        // 检查 Dimina 引擎特有的目录结构（localPath 已包含 appId/version）
        let mainLogicPath = localPath.appendingPathComponent("main/logic.js")

        // 检查是否包含 Dimina 引擎特有的文件
        let hasMainLogic = FileManager.default.fileExists(atPath: mainLogicPath.path)

        if hasMainLogic {
            debugPrint("✅ [AppConfigManager] 找到 Dimina 引擎特有文件: \(mainLogicPath.path)")
        }

        // 检查是否包含必要的文件（兼容传统结构）
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        let indexPath2 = localPath.appendingPathComponent("index.html")

        let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
        let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)

        if hasH5Index {
            debugPrint("✅ [AppConfigManager] 找到 h5/index.html 文件")
        }
        if hasRootIndex {
            debugPrint("✅ [AppConfigManager] 找到 index.html 文件")
        }

        // Dimina 引擎优先检查特有文件，如果没有则检查传统文件
        let isCached = hasMainLogic || hasH5Index || hasRootIndex
        if isCached {
            debugPrint("✅ [AppConfigManager] 模拟器路径下的 Dimina 小程序已缓存: \(appId)")
        } else {
            debugPrint("❌ [AppConfigManager] 模拟器路径下的 Dimina 小程序未缓存，缺少必要的文件")
        }

        return isCached
    }

    /// 检查指定路径的 Dimina 小程序是否已缓存
    /// - Parameter localPath: 本地路径
    /// - Returns: 是否已缓存
    public func isDiminaAppCachedAtPath(_ localPath: URL) -> Bool {
        debugPrint("🔍 [AppConfigManager] 检查指定路径的 Dimina 小程序缓存: \(localPath.path)")
        
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            debugPrint("❌ [AppConfigManager] 指定路径的目录不存在")
            return false
        }
        
        debugPrint("✅ [AppConfigManager] 指定路径的目录存在，检查必要文件...")
        
        // 检查 Dimina 引擎特有的目录结构（localPath 已指向最终目录）
        let mainLogicPath = localPath.appendingPathComponent("main/logic.js")
        
        // 检查是否包含 Dimina 引擎特有的文件
        let hasMainLogic = FileManager.default.fileExists(atPath: mainLogicPath.path)
        
        if hasMainLogic {
            debugPrint("✅ [AppConfigManager] 找到 Dimina 引擎特有文件: \(mainLogicPath.path)")
        }
        
        // 检查是否包含必要的文件（兼容传统结构）
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        let indexPath2 = localPath.appendingPathComponent("index.html")
        
        let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
        let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)
        
        if hasH5Index {
            debugPrint("✅ [AppConfigManager] 找到 h5/index.html 文件")
        }
        if hasRootIndex {
            debugPrint("✅ [AppConfigManager] 找到 index.html 文件")
        }
        
        // Dimina 引擎优先检查特有文件，如果没有则检查传统文件
        let isCached = hasMainLogic || hasH5Index || hasRootIndex
        if isCached {
            debugPrint("✅ [AppConfigManager] 指定路径的 Dimina 小程序已缓存")
        } else {
            debugPrint("❌ [AppConfigManager] 指定路径的 Dimina 小程序未缓存，缺少必要的文件")
        }
        
        return isCached
    }
    
    /// 使用 Dimina Engine 下载并解压小程序
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    ///   - downloadUrl: 下载URL
    /// - Returns: 是否下载成功
    @discardableResult
    public func downloadAndExtractDiminaApp(appId: String, versionCode: String? = nil, downloadUrl: String) async throws -> Bool {
        debugPrint("🚀 [AppConfigManager] 开始下载 Dimina 小程序: \(appId)")
        if let versionCode = versionCode {
            debugPrint("📋 [AppConfigManager] 版本号: \(versionCode)")
        }
        debugPrint("🔗 [AppConfigManager] 下载地址: \(downloadUrl)")
        
        let localPath = getDiminaLocalPath(appId: appId, versionCode: versionCode)
        
        // 检查目标目录是否已存在且有效
        if FileManager.default.fileExists(atPath: localPath.path) {
            debugPrint("📁 [AppConfigManager] 目标目录已存在，检查是否有效...")
            
            // 检查是否包含必要的文件
            let indexPath = localPath.appendingPathComponent("h5/index.html")
            let indexPath2 = localPath.appendingPathComponent("index.html")
            
            let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
            let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)
            
            if hasH5Index || hasRootIndex {
                debugPrint("✅ [AppConfigManager] 目标目录已存在且有效，包含必要的 index.html 文件")
                debugPrint("📁 [AppConfigManager] 跳过下载，直接使用现有文件")
                return true
            } else {
                debugPrint("⚠️ [AppConfigManager] 目标目录存在但无效，将清理后重新下载")
                
                // 清理无效的目录
                do {
                    try FileManager.default.removeItem(at: localPath)
                    debugPrint("🧹 [AppConfigManager] 无效目录清理成功")
                } catch {
                    debugPrint("❌ [AppConfigManager] 清理无效目录失败: \(error.localizedDescription)")
                    throw error
                }
            }
        }
        
        // 确保目录存在
        do {
            try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true, attributes: nil)
            debugPrint("✅ [AppConfigManager] 目标目录创建成功: \(localPath.path)")
        } catch {
            debugPrint("❌ [AppConfigManager] 创建目标目录失败: \(error.localizedDescription)")
            throw error
        }
        
        debugPrint("⏳ [AppConfigManager] 开始调用 DownloadManager 进行下载...")
        
        // 检查下载URL是否为 zip 格式
        let isZipFormat = downloadUrl.lowercased().contains(".zip") || downloadUrl.lowercased().contains("zip")
        
        if isZipFormat {
            debugPrint("📦 [AppConfigManager] 检测到 ZIP 格式，使用 Dimina 引擎处理")
            
            // 使用 DiminaEngineManager 下载并解压 ZIP 文件
            do {
                let success = try await DiminaEngineManager.shared.downloadAndExtractApp(
                    localPath: localPath,
                    downloadUrl: downloadUrl
                )
                
                if success {
                    debugPrint("✅ [AppConfigManager] Dimina 小程序 ZIP 文件下载并解压成功: \(appId)")
                    debugPrint("📁 [AppConfigManager] 文件位置: \(localPath.path)")
                } else {
                    debugPrint("❌ [AppConfigManager] Dimina 小程序 ZIP 文件下载失败: \(appId)")
                }
                return success
            } catch {
                debugPrint("❌ [AppConfigManager] Dimina 小程序 ZIP 文件下载异常: \(error.localizedDescription)")
                throw error
            }
        } else {
            debugPrint("📦 [AppConfigManager] 非 ZIP 格式，尝试使用 DownloadManager")
            
            // 使用 DownloadManager 下载并解压
            // 注意：这里假设 DownloadManager 支持自定义路径
            if let result = try? await DownloadManager.shared.downloadAndExtract(appId: appId, versionCode: versionCode ?? "", downloadUrl: downloadUrl) {
                // 如果 DownloadManager 支持自定义路径，直接使用
                let success = result != nil
                if success {
                    debugPrint("✅ [AppConfigManager] Dimina 小程序下载并解压成功: \(appId)")
                    debugPrint("📁 [AppConfigManager] 文件位置: \(localPath.path)")
                } else {
                    debugPrint("❌ [AppConfigManager] Dimina 小程序下载失败: \(appId)")
                }
                return success
            } else {
                // 如果不支持，则使用默认路径，然后复制到 Dimina 目录
                // 这里需要根据实际的 DownloadManager 实现来调整
                debugPrint("⚠️ [AppConfigManager] DownloadManager 不支持自定义路径，使用默认实现")
                debugPrint("💡 [AppConfigManager] 建议: 需要实现自定义路径的下载逻辑")
                return false
            }
        }
    }
    
    /// 获取 Dimina Engine 的基础URL
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    /// - Returns: Dimina Engine 的基础URL
    public func getDiminaBaseURL(appId: String, versionCode: String? = nil) -> URL {
        let localPath = getDiminaLocalPath(appId: appId, versionCode: versionCode)
        
        // 优先检查 h5/index.html
        let indexPath = localPath.appendingPathComponent("h5/index.html")
        if FileManager.default.fileExists(atPath: indexPath.path) {
            return indexPath
        }
        
        // 如果没有 h5 目录，则使用根目录的 index.html
        return localPath.appendingPathComponent("index.html")
    }
    
    /// 读取 Dimina Engine 小程序的 app-config.json 配置
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    /// - Returns: 应用配置对象
    public func getDiminaAppConfig(appId: String, versionCode: String? = nil) -> DMPBundleAppConfig? {
        debugPrint("🔍 [AppConfigManager] 读取 Dimina 小程序配置: \(appId)")
        
        let localPath = getDiminaLocalPath(appId: appId, versionCode: versionCode)
        
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            debugPrint("❌ [AppConfigManager] Dimina 小程序目录不存在，无法读取配置")
            return nil
        }
        
        // 构建 app-config.json 的路径
        let appConfigPath = localPath.appendingPathComponent("main/app-config.json")
        debugPrint("📁 [AppConfigManager] 配置文件路径: \(appConfigPath.path)")
        
        // 检查配置文件是否存在
        guard FileManager.default.fileExists(atPath: appConfigPath.path) else {
            debugPrint("❌ [AppConfigManager] app-config.json 文件不存在")
            return nil
        }
        
        // 读取配置文件内容
        do {
            let jsonData = try Data(contentsOf: appConfigPath)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            guard let appConfig = DMPBundleAppConfig.fromJsonString(json: jsonString) else {
                debugPrint("❌ [AppConfigManager] 解析 app-config.json 失败")
                return nil
            }
            
            debugPrint("✅ [AppConfigManager] 成功读取 Dimina 小程序配置")
            debugPrint("📋 [AppConfigManager] 入口页面: \(appConfig.entryPagePath)")
            debugPrint("📋 [AppConfigManager] 页面列表: \(appConfig.pages ?? [])")
            
            return appConfig
        } catch {
            debugPrint("❌ [AppConfigManager] 读取 app-config.json 失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 获取 Dimina Engine 小程序的入口页面路径
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    /// - Returns: 入口页面路径
    public func getDiminaEntryPagePath(appId: String, versionCode: String? = nil) -> String? {
        debugPrint("🔍 [AppConfigManager] 获取 Dimina 小程序入口页面路径: \(appId)")
        
        guard let appConfig = getDiminaAppConfig(appId: appId, versionCode: versionCode) else {
            debugPrint("❌ [AppConfigManager] 无法获取应用配置，无法确定入口页面")
            return nil
        }
        
        let entryPagePath = appConfig.entryPagePath
        if !entryPagePath.isEmpty {
            debugPrint("✅ [AppConfigManager] 找到入口页面路径: \(entryPagePath)")
            return entryPagePath
        } else {
            debugPrint("❌ [AppConfigManager] 入口页面路径为空")
            return nil
        }
    }
    
    /// 获取 Dimina Engine 小程序的完整加载路径
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    /// - Returns: 完整的加载路径
    public func getDiminaLoadPath(appId: String, versionCode: String? = nil) -> URL? {
        debugPrint("🔍 [AppConfigManager] 获取 Dimina 小程序加载路径: \(appId)")
        
        guard let entryPagePath = getDiminaEntryPagePath(appId: appId, versionCode: versionCode) else {
            debugPrint("❌ [AppConfigManager] 无法获取入口页面路径")
            return nil
        }
        
        let localPath = getDiminaLocalPath(appId: appId, versionCode: versionCode)
        
        // 构建完整的加载路径
        // 例如：如果 entryPagePath 是 "pages/index/index"，则构建为 "pages/index/index.html"
        let htmlFileName = entryPagePath.hasSuffix(".html") ? entryPagePath : "\(entryPagePath).html"
        let fullLoadPath = localPath.appendingPathComponent(htmlFileName)
        
        debugPrint("📁 [AppConfigManager] 完整加载路径: \(fullLoadPath.path)")
        
        // 检查文件是否存在
        if FileManager.default.fileExists(atPath: fullLoadPath.path) {
            debugPrint("✅ [AppConfigManager] 加载路径文件存在")
            return fullLoadPath
        } else {
            debugPrint("❌ [AppConfigManager] 加载路径文件不存在")
            return nil
        }
    }
    
    /// 清理 Dimina Engine 的缓存
    /// - Parameters:
    ///   - appId: 小程序ID
    ///   - versionCode: 版本号（可选）
    /// - Returns: 是否清理成功
    @discardableResult
    public func clearDiminaCache(appId: String, versionCode: String? = nil) -> Bool {
        let localPath = getDiminaLocalPath(appId: appId, versionCode: versionCode)
        
        do {
            if FileManager.default.fileExists(atPath: localPath.path) {
                try FileManager.default.removeItem(at: localPath)
                return true
            }
            return true
        } catch {
            debugPrint("清理 Dimina 缓存失败: \(error)")
            return false
        }
    }
    
    /// 获取所有已缓存的 Dimina 小程序
    /// - Returns: 已缓存的小程序ID数组
    public func getAllCachedDiminaApps() -> [String] {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "")
        let diminaPath = documentsPath.appendingPathComponent("Dimina")
        
        guard FileManager.default.fileExists(atPath: diminaPath.path) else {
            return []
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: diminaPath, includingPropertiesForKeys: nil)
            var cachedApps: [String] = []
            
            for url in contents {
                let appName = url.lastPathComponent
                debugPrint("📱 [AppConfigManager] 检查应用目录: \(appName)")
                
                // 检查是否直接包含小程序文件（无版本号结构）
                let indexPath = url.appendingPathComponent("h5/index.html")
                let indexPath2 = url.appendingPathComponent("index.html")
                let diminaAppPath = url.appendingPathComponent(appName).appendingPathComponent("main/logic.js")
                
                let hasH5Index = FileManager.default.fileExists(atPath: indexPath.path)
                let hasRootIndex = FileManager.default.fileExists(atPath: indexPath2.path)
                let hasMainLogic = FileManager.default.fileExists(atPath: diminaAppPath.path)
                
                if hasH5Index || hasRootIndex || hasMainLogic {
                    debugPrint("✅ [AppConfigManager] 发现缓存的小程序（无版本号）: \(appName)")
                    cachedApps.append(appName)
                } else {
                    // 检查是否包含版本号子目录
                    do {
                        let versionContents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                        for versionUrl in versionContents {
                            let versionName = versionUrl.lastPathComponent
                            let versionIndexPath = versionUrl.appendingPathComponent("h5/index.html")
                            let versionIndexPath2 = versionUrl.appendingPathComponent("index.html")
                            let versionDiminaAppPath = versionUrl.appendingPathComponent(appName).appendingPathComponent("main/logic.js")
                            
                            let versionHasH5Index = FileManager.default.fileExists(atPath: versionIndexPath.path)
                            let versionHasRootIndex = FileManager.default.fileExists(atPath: versionIndexPath2.path)
                            let versionHasMainLogic = FileManager.default.fileExists(atPath: versionDiminaAppPath.path)
                            
                            if versionHasH5Index || versionHasRootIndex || versionHasMainLogic {
                                debugPrint("✅ [AppConfigManager] 发现缓存的小程序（版本号 \(versionName)）: \(appName)")
                                if !cachedApps.contains(appName) {
                                    cachedApps.append(appName)
                                }
                                break
                            }
                        }
                    } catch {
                        debugPrint("⚠️ [AppConfigManager] 检查版本号目录失败: \(error)")
                    }
                }
            }
            
            return cachedApps
        } catch {
            debugPrint("获取已缓存的 Dimina 小程序失败: \(error)")
            return []
        }
    }
}

// MARK: - 小程序启动配置
public struct AppLaunchConfig {
    public let appId: String
    public let path: String
    public let type: String?
    public let ws: String?
    public let query: String?
    public let useDimina: Bool
    
    public init(appId: String, path: String = "", type: String? = nil, ws: String? = nil, query: String? = nil, useDimina: Bool = false) {
        self.appId = appId
        self.path = path
        self.type = type
        self.ws = ws
        self.query = query
        self.useDimina = useDimina
    }
}
