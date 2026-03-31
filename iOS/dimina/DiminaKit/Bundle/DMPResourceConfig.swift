//
//  DMPResourceConfig.swift
//  dimina
//
//  Created by Lehem on 2025/4/17.
//

import Foundation

/// 资源配置管理类
public class DMPResourceConfig {
    
    // MARK: - Singleton
    public static let shared = DMPResourceConfig()
    private init() {}
    
    // MARK: - Configuration Keys
    private enum ConfigKeys {
        static let remoteJsAppBundleURL = "remoteJsAppBundleURL"
        static let remoteJsSdkBundleURL = "remoteJsSdkBundleURL"
        static let enableAutoDownload = "enableAutoDownload"
        static let downloadTimeout = "downloadTimeout"
        static let maxRetryCount = "maxRetryCount"
    }
    
    // MARK: - Default Values
    private let defaultConfig: [String: Any] = [
        ConfigKeys.remoteJsAppBundleURL: "https://your-server.com/jsapp-bundle.zip",
        ConfigKeys.remoteJsSdkBundleURL: "https://your-server.com/jssdk-bundle.zip",
        ConfigKeys.enableAutoDownload: true,
        ConfigKeys.downloadTimeout: 30.0,
        ConfigKeys.maxRetryCount: 3
    ]
    
    // MARK: - Configuration Storage
    private var userDefaults: UserDefaults {
        return UserDefaults.standard
    }
    
    // MARK: - Public Properties
    
    /// 远程JSApp Bundle下载URL
    public var remoteJsAppBundleURL: String {
        get {
            return userDefaults.string(forKey: ConfigKeys.remoteJsAppBundleURL) ?? 
                   defaultConfig[ConfigKeys.remoteJsAppBundleURL] as! String
        }
        set {
            userDefaults.set(newValue, forKey: ConfigKeys.remoteJsAppBundleURL)
        }
    }
    
    /// 远程JSSDK Bundle下载URL
    public var remoteJsSdkBundleURL: String {
        get {
            return userDefaults.string(forKey: ConfigKeys.remoteJsSdkBundleURL) ?? 
                   defaultConfig[ConfigKeys.remoteJsSdkBundleURL] as! String
        }
        set {
            userDefaults.set(newValue, forKey: ConfigKeys.remoteJsSdkBundleURL)
        }
    }
    
    /// 是否启用自动下载
    public var enableAutoDownload: Bool {
        get {
            return userDefaults.bool(forKey: ConfigKeys.enableAutoDownload)
        }
        set {
            userDefaults.set(newValue, forKey: ConfigKeys.enableAutoDownload)
        }
    }
    
    /// 下载超时时间（秒）
    public var downloadTimeout: TimeInterval {
        get {
            return userDefaults.double(forKey: ConfigKeys.downloadTimeout)
        }
        set {
            userDefaults.set(newValue, forKey: ConfigKeys.downloadTimeout)
        }
    }
    
    /// 最大重试次数
    public var maxRetryCount: Int {
        get {
            return userDefaults.integer(forKey: ConfigKeys.maxRetryCount)
        }
        set {
            userDefaults.set(newValue, forKey: ConfigKeys.maxRetryCount)
        }
    }
    
    // MARK: - Configuration Methods
    
    /// 重置为默认配置
    public func resetToDefault() {
        for (key, value) in defaultConfig {
            userDefaults.set(value, forKey: key)
        }
    }
    
    /// 从配置文件加载配置
    public func loadFromFile(_ filePath: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        for (key, value) in config {
            userDefaults.set(value, forKey: ConfigKeys.remoteJsAppBundleURL)
        }
        
        return true
    }
    
    /// 保存配置到文件
    public func saveToFile(_ filePath: String) -> Bool {
        var config: [String: Any] = [:]
        config[ConfigKeys.remoteJsAppBundleURL] = remoteJsAppBundleURL
        config[ConfigKeys.remoteJsSdkBundleURL] = remoteJsSdkBundleURL
        config[ConfigKeys.enableAutoDownload] = enableAutoDownload
        config[ConfigKeys.downloadTimeout] = downloadTimeout
        config[ConfigKeys.maxRetryCount] = maxRetryCount
        
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: URL(fileURLWithPath: filePath))
            return true
        } catch {
            print("保存配置文件失败: \(error)")
            return false
        }
    }
    
    /// 验证配置是否有效
    public func validateConfig() -> [String] {
        var errors: [String] = []
        
        if !isValidURL(remoteJsAppBundleURL) {
            errors.append("无效的JSApp Bundle URL: \(remoteJsAppBundleURL)")
        }
        
        if !isValidURL(remoteJsSdkBundleURL) {
            errors.append("无效的JSSDK Bundle URL: \(remoteJsSdkBundleURL)")
        }
        
        if downloadTimeout <= 0 {
            errors.append("下载超时时间必须大于0")
        }
        
        if maxRetryCount < 0 {
            errors.append("最大重试次数不能为负数")
        }
        
        return errors
    }
    
    // MARK: - Private Methods
    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
}
