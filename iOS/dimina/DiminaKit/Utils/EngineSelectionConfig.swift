import Foundation

/// 引擎选择配置
public struct EngineSelectionConfig {
    
    /// 新版本引擎的配置
    public struct NewEngineConfig {
        /// 使用新版本引擎的环境类型
        public let devEnvironmentTypes: [String]
        /// 使用新版本引擎的小程序ID列表
        public let appIds: [String]
        /// 使用新版本引擎的版本号前缀
        public let versionPrefixes: [String]
        /// 使用新版本引擎的最小版本号
        public let minVersionNumber: Double

        
        public init(
            devEnvironmentTypes: [String] = ["dev", "test"],
            appIds: [String] = ["wxe5f52902cf4de896", "wx92269e3b2f304afc"],
            versionPrefixes: [String] = ["new", "v2", "beta"],
            minVersionNumber: Double = 200
        ) {
            self.devEnvironmentTypes = devEnvironmentTypes
            self.appIds = appIds
            self.versionPrefixes = versionPrefixes
            self.minVersionNumber = minVersionNumber
        }
    }
    
    /// 默认配置
    public static let `default` = NewEngineConfig()
    
    /// 自定义配置
    public static var custom: NewEngineConfig = NewEngineConfig()
    
    /// 重置为默认配置
    public static func resetToDefault() {
        custom = NewEngineConfig()
    }
    
    /// 更新配置
    /// - Parameter config: 新的配置
    public static func updateConfig(_ config: NewEngineConfig) {
        custom = config
    }
}

/// 引擎选择策略
public enum EngineSelectionStrategy {
    /// 自动选择（根据配置规则）
    case automatic
    /// 强制使用新版本
    case forceNew
    /// 强制使用老版本
    case forceOld
}

/// 引擎类型
public enum EngineType {
    /// Dimina引擎（新版本）
    case dimina
    /// WebView引擎（老版本）
    case webView
    /// 未知
    case unknown
}
