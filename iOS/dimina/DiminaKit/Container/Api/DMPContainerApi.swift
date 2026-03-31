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
    let appId: String
    let webViewId: Int

    init(appIndex: Int, appId: String, webViewId: Int) {
        self.appIndex = appIndex
        self.appId = appId
        self.webViewId = webViewId
    }
}

// 定义回调闭包类型
public typealias DMPBridgeCallback = (_ args: DMPMap, _ cbType: DMPBridgeCallbackType) -> Void

// 定义桥接方法处理程序类型
public typealias DMPBridgeMethodHandler = (_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any?

// 自定义属性
@propertyWrapper
public struct BridgeMethod {
    public let name: String
    public var wrappedValue: DMPBridgeMethodHandler
    
    public init(_ name: String) {
        self.name = name
        self.wrappedValue = { _, _, _ in }
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
        // 1. 注册内置 API（DMPContainerApi 子类，直接实例化注册 @BridgeMethod）
        print("📦 [DMPContainerApi] 注册内置 API（DMPContainerApi 子类）...")
        _ = RouteAPI(app: app)
        _ = NetworkAPI(app: app)
        _ = StorageAPI()
        _ = InteractionAPI()
        _ = ImageAPI(app: app)
        _ = AudioAPI(app: app)
        _ = FileSystemAPI(app: app)
        print("📦 [DMPContainerApi] 内置 API 注册完成")

        // 2. 注册外部自定义 API（BridgeMethodProtocol 类型，通过 registerCustomAPI 注册）
        registerDefaultAPITypes()
        initializeAllAPIs(app: app)

        print("📦 [DMPContainerApi] 全部 API 注册完成，bridgeHandlerMap 共 \(bridgeHandlerMap.count) 个方法")

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
            
            // 创建API实例，这会触发@BridgeMethod注解的自动注册
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
    
    public static func getHandler(for methodName: String) -> DMPBridgeMethodHandler? {
        return bridgeHandlerMap[methodName]
    }
    
    public static func getAllRegisteredMethods() -> [String] {
        return Array(bridgeHandlerMap.keys)
    }
    
    public func invokeBridgeMethod(name: String, data: DMPBridgeParam, env: DMPBridgeEnv, callback: DMPBridgeCallback? = nil) -> Any? {
        if let handler = Self.getHandler(for: name) {
            return handler(data, env, callback)
        }
        print("未找到方法: \(name)")
        return nil
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

// MARK: - 使用示例
/*
 
 如何使用 @BridgeMethod 注解和新的类型注册系统：
 
 1. 创建自定义API类，实现 BridgeMethodProtocol：
 
 class MyCustomAPI: BridgeMethodProtocol {
     // 使用 @BridgeMethod 注解自动注册方法
     @BridgeMethod("myCustomMethod")
     var myCustomMethod: DMPBridgeMethodHandler = { param, env, callback in
         // 实现你的自定义逻辑
         let result = DMPMap()
         result.set("message", "Hello from custom API!")
         DMPContainerApi.invokeSuccess(callback: callback, param: result)
         return nil
     }
     
     @BridgeMethod("anotherMethod")
     var anotherMethod: DMPBridgeMethodHandler = { param, env, callback in
         // 另一个自定义方法
         let result = DMPMap()
         result.set("data", ["custom": "value"])
         DMPContainerApi.invokeSuccess(callback: callback, param: result)
         return nil
     }
 }
 
 2. 注册自定义API类型（不创建实例）：
 
 // 单个注册
 DMPContainerApi.registerCustomAPI(MyCustomAPI.self)
 
 // 批量注册
 DMPContainerApi.registerCustomAPITypes([MyCustomAPI.self, AnotherAPI.self])
 
 3. 在需要时初始化所有API：
 
 // 这通常在容器创建时调用，会自动创建所有已注册API的实例
 DMPContainerApi.initializeAllAPIs(app: app)
 
 4. 验证注册结果：
 
 let apiTypes = DMPContainerApi.getAllRegisteredAPITypes()
 print("已注册的API类型: \(apiTypes)")
 
 let apiTypeCount = DMPContainerApi.getRegisteredAPITypeCount()
 print("API类型总数: \(apiTypeCount)")
 
 let methods = DMPContainerApi.getAllRegisteredMethods()
 print("已注册的方法: \(methods)")
 
 let methodCount = DMPContainerApi.getRegisteredMethodCount()
 print("方法总数: \(methodCount)")
 
 新的设计优势：
 
 1. 类型注册 vs 实例创建分离：
    - registerCustomAPI() 只注册类型，不创建实例
    - initializeAllAPIs() 在需要时才创建实例并注册方法
 
 2. 避免重复创建：
    - 每个容器不会重复创建API实例
    - 只在需要时创建一次，然后复用已注册的方法
 
 3. 更好的资源管理：
    - 可以动态添加/移除API类型
    - 实例创建时机可控
 
 4. 性能优化：
    - 避免不必要的实例创建
    - 方法注册只发生一次
 
 工作原理：
 - @BridgeMethod 注解在API实例初始化时自动调用 registerMethod
 - registerCustomAPI 只存储API类型，不创建实例
 - initializeAllAPIs 创建所有已注册类型的实例，触发方法注册
 - 所有方法都存储在 bridgeHandlerMap 中，可以通过方法名调用
 */
