//
//  DMPContainer.swift
//  dimina
//
//  Created by Lehem on 2025/4/23.
//

import Foundation
import ObjectiveC

enum ResourceLoadType: Int {
    case initial = 0
    case serviceLoaded = 1
    case renderLoaded = 2
    case allLoaded = 3
}

public class DMPContainer {
    // MARK: - Properties
    private weak var app: DMPApp?
    private var loadStatusMap: [Int: ResourceLoadType] = [:]
    var isNavigating: Bool = false

    // MARK: - Initialization
    public init(app: DMPApp? = nil) {
        self.app = app
    }

    // MARK: - Public Methods
    public func getApp() -> DMPApp? {
        return app
    }

    public func resetStatus() {
        isNavigating = false
    }

    // MARK: - Resource Management
    func hasLoadResource(webViewId: Int, type: ResourceLoadType) {
        let status = loadStatusMap[webViewId] ?? .initial
        let newRawValue = status.rawValue | type.rawValue
        loadStatusMap[webViewId] = ResourceLoadType(rawValue: newRawValue) ?? .initial
    }

    func isResourceLoaded(webViewId: Int) -> Bool {
        return loadStatusMap[webViewId] == .allLoaded
    }

    private func createResourceMessage(webViewId: Int, pagePath: String) -> DMPMap {
        guard let app = app,
            let config = app.getBundleAppConfig()
        else { return DMPMap() }

        let root = config.getRootPackage(pagePath: pagePath)
        return DMPMap([
            "type": "loadResource",
            "body": [
                "bridgeId": webViewId,
                "appId": app.getAppId(),
                "pagePath": pagePath,
                "root": root,
            ],
        ])
    }

    func loadResourceService(webViewId: Int, pagePath: String) {
        guard let app = app else { return }
        let message = createResourceMessage(webViewId: webViewId, pagePath: pagePath)
        DMPChannelProxy.containerToService(msg: message, app: app)
    }

    func loadResourceRender(webViewId: Int, pagePath: String) {
        guard let app = app else { return }
        let message = createResourceMessage(webViewId: webViewId, pagePath: pagePath)
        DMPChannelProxy.containerToRender(msg: message, app: app, webViewId: webViewId)
    }

    // MARK: - Bridge Methods
    public func callWebviewBridgeMethod(
        methodName: String, webViewId: Int, params: Any, app: DMPApp
    ) -> Any {
        // TODO: 实现 WebView 桥接方法
        return DMPMap()
    }

    public func callBridgeMethod(
        methodName: String, webViewId: Int, param: DMPBridgeParam, app: DMPApp
    ) -> Any {
        let moduleName = "DMPContainerBridgesModule"
        print("Bridge call: module=\(moduleName), method=\(methodName)")
        var callback: DMPBridgeCallback = { _, _ in }

        if param.isAsync {
            var callbackIds = (success: "", fail: "", complete: "")
            let map = param.getMap()

            callbackIds.success = map["success"] as? String ?? ""
            callbackIds.fail = map["fail"] as? String ?? ""
            callbackIds.complete = map["complete"] as? String ?? ""

            callback = {
                [weak self] (args: DMPMap, cbType: DMPBridgeCallbackType) in
                guard let self = self else { return }

                let callbackId: String = {
                    switch cbType {
                    case .success: return callbackIds.success
                    case .fail: return callbackIds.fail
                    case .complete: return callbackIds.complete
                    }
                }()

                guard !callbackId.isEmpty else { return }

                let argsDict = args.toDictionary()
                let message = DMPMap([
                    "type": "triggerCallback",
                    "body": [
                        "id": callbackId,
                        "args": argsDict,
                    ],
                ])

                // 调试日志
                let messageJson = message.toJsonString()
                let isEmptyJson = messageJson == "{}"
                DMPEngineLog.writeToLogFile("📤 triggerCallback method=\(methodName) cbType=\(cbType) id=\(callbackId) jsonOK=\(!isEmptyJson) jsonLen=\(messageJson.count)")
                if isEmptyJson {
                    // JSON 序列化失败，打印原始数据帮助排查
                    DMPEngineLog.writeToLogFile("❌ JSON serialize FAILED! argsDict types: \(argsDict.mapValues { type(of: $0) })")
                }

                DMPChannelProxy.containerToService(msg: message, app: self.getApp())
            }
        }

        if let handler: DMPBridgeMethodHandler = DMPContainerApi.getHandler(for: methodName) {
            let env: DMPBridgeEnv = DMPBridgeEnv(
                appIndex: self.app?.getAppIndex() ?? 0, appId: self.app?.getAppId() ?? "",
                webViewId: webViewId)
            return handler(param, env, callback) ?? DMPMap()
        }

        print("Bridge invoke error: 未找到方法: \(methodName)")
        return ["error": "未找到方法: \(methodName)"]
    }

    // MARK: - Private Methods
    private static func getSubclasses(of baseClass: AnyClass) -> [AnyClass] {
        var count: UInt32 = 0
        guard let classesPtr = objc_copyClassList(&count) else { return [] }
        defer { free(UnsafeMutableRawPointer(classesPtr)) }

        var result: [AnyClass] = []
        let buffer = UnsafeBufferPointer(start: classesPtr, count: Int(count))
        for currentClass in buffer {
            if class_getSuperclass(currentClass) === baseClass {
                result.append(currentClass)
            }
        }
        return result
    }
}
