import Foundation
import echo_entity_swift

/// MiniProgramInfo的扩展，添加引擎类型判断
extension MiniProgramInfo {
    
    /// 引擎类型枚举
    public enum EngineType: String {
        case dimina = "dimina"      // Dimina引擎
        case webView = "webview"    // WebView引擎
    }
    
    /// 引擎类型（从配置中获取）
    public var engine: EngineType {
        // 优先使用loader字段判断
        if let loader = self.loader, !loader.isEmpty {
            return loader == "EMP" ? .dimina : .webView
        }
        
        return .webView
    }

}
