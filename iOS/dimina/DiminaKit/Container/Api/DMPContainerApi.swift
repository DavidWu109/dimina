//
//  DMPContainerApi.swift
//  dimina
//
//  Created by Lehem on 2025/4/27.
//

import Foundation

// 定义回调类型枚举
@objc public enum DMPBridgeCallbackType: Int {
    case success
    case fail
    case complete
}

public class DMPBridgeEnv {
    public let appIndex: Int
    public let appId: String
    public let webViewId: Int

    init(appIndex: Int, appId: String, webViewId: Int) {
        self.appIndex = appIndex
        self.appId = appId
        self.webViewId = webViewId
    }
}

// 定义回调闭包类型
public typealias DMPBridgeCallback = (_ args: DMPMap, _ cbType: DMPBridgeCallbackType) -> Void

// 定义桥接方法处理程序类型
public typealias DMPBridgeMethodHandler = (_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult

// @BridgeMethod 仍保留供 EchoWebKit 等外部 pod 使用。
// dimina 内置 API 已全量迁移到 init + register() 实例方法模式。
@propertyWrapper
public struct BridgeMethod {
    public let name: String
    public var wrappedValue: DMPBridgeMethodHandler

    public init(_ name: String) {
        self.name = name
        self.wrappedValue = { _, _, _ in DMPNoneResult() }
        DMPContainerApi.registerMethod(name: name)
    }

    public init(wrappedValue: @escaping DMPBridgeMethodHandler, _ name: String) {
        self.name = name
        self.wrappedValue = wrappedValue
        DMPContainerApi.registerMethod(name: name, handler: wrappedValue)
    }
}

@objc public protocol BridgeMethodProtocol {
    // 协议可以留空，主要用于类型约束
    // 实际的桥接方法通过@BridgeMethod注解自动注册
    init()
}

public class DMPContainerApi: NSObject {
    private weak var app: DMPApp?
    static var bridgeHandlerMap: [String: DMPBridgeMethodHandler] = [:]
    
    // 存储API类型，而不是实例
    static var registeredAPITypes: [String: BridgeMethodProtocol.Type] = [:]
    
    public init(app: DMPApp? = nil) {
        self.app = app
        super.init()
    }
    
    public static func create(app: DMPApp? = nil) -> DMPContainerApi {
        // 1. 注册内置 API（DMPContainerApi 子类，init 里通过 register() 注册 handler）
        DMPLog.bridge.debug("registering built-in APIs")
        _ = RouteAPI(app: app)
        _ = BaseAPI(app: app)
        _ = SystemAPI(app: app)
        _ = UpdateAPI(app: app)
        _ = NetworkAPI(app: app)
        _ = StorageAPI(app: app)
        _ = InteractionAPI(app: app)
        _ = ImageAPI(app: app)
        _ = AudioAPI(app: app)
        _ = VideoAPI(app: app)
        _ = FileSystemAPI(app: app)
        _ = MenuAPI(app: app)
        _ = NavigationBarAPI(app: app)
        _ = ScrollAPI(app: app)
        _ = NativeComponentAPI(app: app)
        _ = TabBarAPI(app: app)
        _ = LoginAPI(app: app)
        // Device APIs
        _ = ClipboardAPI(app: app)
        _ = ContactAPI(app: app)
        _ = KeyboardAPI(app: app)
        _ = NetworkTypeAPI(app: app)
        _ = PhoneAPI(app: app)
        _ = VibrateAPI(app: app)
        _ = DeviceAPI(app: app)
        let sortedKeys = bridgeHandlerMap.keys.sorted().joined(separator: ",")
        DMPLog.bridge.info("built-in APIs registered, bridgeHandlerMap=\(bridgeHandlerMap.count) keys=\(sortedKeys)")

        // 2. 注册外部自定义 API（BridgeMethodProtocol 类型，通过 registerCustomAPI 注册）
        registerDefaultAPITypes()
        initializeAllAPIs(app: app)

        return DMPContainerApi(app: app)
    }
    
    /// 注册默认的API类型
    /// 注意：此方法只注册API类型，不会创建实例
    public static func registerDefaultAPITypes() {
        print("开始注册默认API类型...")
        
        // 注册默认API类型（如果可用）
        // 注意：这些API类需要在编译时可用
        // 如果遇到编译错误，请确保所有API类都已正确导入
        
        // 内置 API 已在 create() 中通过直接实例化注册
        // 这里只处理外部自定义 API（BridgeMethodProtocol 类型）
        
        print("默认API类型注册完成")
    }
    
    /// 动态注册自定义API类型
    /// - Parameter apiType: 实现了BridgeMethodProtocol的API类型
    /// 注意：此方法只注册API类型，不会创建实例，实例在需要时才创建
    public static func registerCustomAPI<T: BridgeMethodProtocol>(_ apiType: T.Type) {
        let typeName = String(describing: apiType)
        print("开始注册自定义API类型: \(typeName)")
        
        // 注册API类型，而不是实例
        registeredAPITypes[typeName] = apiType
        
        print("自定义API类型注册完成: \(typeName)")
    }
    
    /// 批量注册自定义API类型
    /// - Parameter apiTypes: 实现了BridgeMethodProtocol的API类型数组
    public static func registerCustomAPITypes<T: BridgeMethodProtocol>(_ apiTypes: [T.Type]) {
        for apiType in apiTypes {
            registerCustomAPI(apiType)
        }
    }
    
    /// 创建并初始化所有已注册的API实例
    /// - Parameter app: 应用实例
    /// 注意：此方法应该在容器创建时调用，用于初始化所有API
    public static func initializeAllAPIs(app: DMPApp? = nil) {
        print("开始初始化所有已注册的API...")
        
        for (typeName, apiType) in registeredAPITypes {
            print("初始化API类型: \(typeName)")
            
            // 创建API实例，init 中的 register() 调用会注册 handler
            if let apiClass = apiType as? NSObject.Type {
                let _ = apiClass.init()
            }
        }
        
        print("所有API初始化完成，已注册方法数: \(bridgeHandlerMap.count)")
    }
    
    /// 清除所有已注册的方法
    public static func clearAllMethods() {
        bridgeHandlerMap.removeAll()
    }
    
    /// 移除指定的方法
    /// - Parameter methodName: 要移除的方法名
    public static func removeMethod(_ methodName: String) {
        bridgeHandlerMap.removeValue(forKey: methodName)
    }
    
    /// 检查方法是否已注册
    /// - Parameter methodName: 方法名
    /// - Returns: 是否已注册
    public static func isMethodRegistered(_ methodName: String) -> Bool {
        return bridgeHandlerMap[methodName] != nil
    }
    
    /// 获取已注册方法的数量
    public static func getRegisteredMethodCount() -> Int {
        return bridgeHandlerMap.count
    }
    
    /// 获取已注册的API类型数量
    public static func getRegisteredAPITypeCount() -> Int {
        return registeredAPITypes.count
    }
    
    /// 获取所有已注册的API类型名称
    public static func getAllRegisteredAPITypes() -> [String] {
        return Array(registeredAPITypes.keys)
    }
    
    /// 检查API类型是否已注册
    /// - Parameter apiType: API类型
    /// - Returns: 是否已注册
    public static func isAPITypeRegistered<T: BridgeMethodProtocol>(_ apiType: T.Type) -> Bool {
        let typeName = String(describing: apiType)
        return registeredAPITypes[typeName] != nil
    }
    
    /// 移除指定的API类型
    /// - Parameter apiType: 要移除的API类型
    public static func removeAPIType<T: BridgeMethodProtocol>(_ apiType: T.Type) {
        let typeName = String(describing: apiType)
        registeredAPITypes.removeValue(forKey: typeName)
        print("已移除API类型: \(typeName)")
    }
    
    /// 清除所有已注册的API类型
    public static func clearAllAPITypes() {
        registeredAPITypes.removeAll()
        print("已清除所有API类型")
    }
    
    public func getApp() -> DMPApp? {
        return app
    }
    
    // 统一注册方法
    public static func registerMethod(name: String, handler: DMPBridgeMethodHandler? = nil) {
        if let handler = handler {
            bridgeHandlerMap[name] = handler
        }
    }

    public func register(_ name: String, handler: @escaping DMPBridgeMethodHandler) {
        DMPContainerApi.registerMethod(name: name, handler: handler)
    }
    
    public static func getHandler(for methodName: String) -> DMPBridgeMethodHandler? {
        return bridgeHandlerMap[methodName]
    }
    
    public static func getAllRegisteredMethods() -> [String] {
        return Array(bridgeHandlerMap.keys)
    }
    
    public func invokeBridgeMethod(name: String, data: DMPBridgeParam, env: DMPBridgeEnv, callback: DMPBridgeCallback? = nil) -> DMPAPIResult {
        if let handler = Self.getHandler(for: name) {
            return handler(data, env, callback)
        }
        print("未找到方法: \(name)")
        return DMPNoneResult()
    }
    
    // 统一的回调处理方法
    public static func invokeCallback(_ callback: DMPBridgeCallback?, type: DMPBridgeCallbackType, param: DMPMap?, errMsg: String? = nil) {
        guard let callback = callback else { return }

        let finalParam = param ?? DMPMap()

        if type == .fail, let errMsg = errMsg {
            finalParam.set("data", ["errMsg": errMsg])
        }
        callback(finalParam, type)
        
        // 所有回调最终都会触发complete
        if type != .complete {
            callback(DMPMap(), .complete)
        }
    }
    
    // 成功回调
    public func invokeSuccessCallback(callback: DMPBridgeCallback?, param: DMPMap?) {
        DMPContainerApi.invokeCallback(callback, type: .success, param: param)
    }
    
    // 失败回调
    public func invokeFailureCallback(callback: DMPBridgeCallback?, param: DMPMap?, errMsg: String) {
        DMPContainerApi.invokeCallback(callback, type: .fail, param: param, errMsg: errMsg)
    }
    
    // 成功回调（静态方法）
    public static func invokeSuccess(callback: DMPBridgeCallback?, param: DMPMap?) {
        invokeCallback(callback, type: .success, param: param)
    }
    
    // 失败回调（静态方法）
    public static func invokeFailure(callback: DMPBridgeCallback?, param: DMPMap?, errMsg: String) {
        invokeCallback(callback, type: .fail, param: param, errMsg: errMsg)
    }
}

