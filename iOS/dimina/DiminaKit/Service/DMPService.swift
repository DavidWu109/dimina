//
//  DMPService.swift
//  dimina
//
//  Created by Lehem on 2025/4/16.
//

import Foundation
import JavaScriptCore

public class DMPService {
    
    private(set) var engine: DMPEngine
    
    private var isInitialized: Bool = false
    
    private weak var app: DMPApp?
    
    public init(app: DMPApp) {
        self.app = app
        self.engine = DMPEngine()
        
        DMPEngineInvoke.registerAppResolver { [weak self] in
            return self?.app
        }
        DMPEnginePublish.registerAppResolver { [weak self] in
            return self?.app
        }
    }
    
    public func initialize() -> Bool {
        guard !isInitialized else {
            return true
        }
        isInitialized = true
        
        
        return isInitialized
    }
    
    public func getEngine() -> DMPEngine {
        return engine
    }
    
    @discardableResult
    public func evaluateScript(_ script: String) async -> JSValue? {
        return await engine.evaluateScript(script)
    }

    public func loadFile(path: String) async {
        print("DMPService: 加载文件，path: \(path)")
        await engine.loadFile(path: path)
    }

    public func postMessage(data: DMPMap) async {
        let dataString = data.toJsonString()
        let script: String = "DiminaServiceBridge.onMessage(\(dataString))"
        await self.evaluateScript(script)
    }
    
    public func loadSubPackage(pagePath: String) async {
        let bundleAppConfig = app?.getBundleAppConfig()
        let packageName = bundleAppConfig?.getRootPackage(pagePath: pagePath) ?? "main"
        
        if (packageName == "main") {
            print("DMPService: 加载主包，pagePath: \(pagePath)")
            return
        }
        
        let subPackagePath = DMPSandboxManager.appSubPackagePath(appId: app?.getAppId() ?? "", packageName: packageName)
        print("DMPService: 加载分包，packageName: \(packageName), subPackagePath: \(subPackagePath)")
        await loadFile(path: subPackagePath)
    }

    public func fromRender(data: String) async {
        let script: String = "DiminaServiceBridge.onMessage(\(data))"
        await self.evaluateScript(script)
    }
    
    func fromContainer(data: DMPMap) {
        Task {
            let jsonString = data.toJsonString()

            // 记录 triggerCallback 消息的完整 JSON
            if jsonString.contains("triggerCallback") && jsonString.contains("request") {
                DMPEngineLog.writeToLogFile("📨 fromContainer JSON(len=\(jsonString.count)): \(jsonString.prefix(1000))")
            }

            let script: String = "DiminaServiceBridge.onMessage(\(jsonString))"
            await self.evaluateScript(script)
        }
    }
    
    public func destroy() {
        isInitialized = false
        engine.destroy()
    }
}
