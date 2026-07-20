//
//  DMPChannelProxy.swift
//  dimina
//
//  Created by Lehem on 2025/4/22.
//

import Foundation

class DMPChannelProxy {
    public static func messageHandler(
        type: String, body: DMPMap,
        target: String, app: DMPApp
    ) -> Any {
        let webViewId: Int = body.get("bridgeId") as? Int ?? 0
        let webview = app.render?.getWebView(byId: webViewId)
        if webViewId != 0 && webview != nil {
            body.set("pagePath", webview!.getPagePath())
            body.set("query", webview!.getQuery())
        }
        // 暂时升级为 info 排查 showModal/invokeAPI 不到 native 的问题
        if type == "invokeAPI" || type == "domReady" {
            let methodName = body.get("name") as? String ?? "?"
            DMPLog.bridge.info("messageHandler type=\(type) target=\(target) bridgeId=\(webViewId) name=\(methodName)")
        } else {
            DMPLog.bridge.debug("messageHandler type=\(type) target=\(target) bridgeId=\(webViewId)")
        }

        if target == "service" {
            let transMsg = DMPMap([
                "type": type,
                "body": body.toDictionary(),
            ])

            if type == "serviceResourceLoaded" || type == "renderResourceLoaded" {
                let resourceType: ResourceLoadType =
                    type == "serviceResourceLoaded" ? .serviceLoaded : .renderLoaded
                app.container!.hasLoadResource(webViewId: webViewId, type: resourceType)
                let loaded = app.container!.isResourceLoaded(webViewId: webViewId)
                DMPLog.bridge.info("\(type) bridgeId=\(webViewId) allLoaded=\(loaded)")

                if loaded {
                    body.set("scene", DMPScene.fromMainEntry.rawValue)
                    transMsg.set("type", "resourceLoaded")

                    Task { @MainActor in
                        await app.service?.postMessage(data: transMsg)
                    }
                    DMPLog.bridge.info("→ service resourceLoaded bridgeId=\(webViewId)")
                    return DMPMap()
                } else {
                    return DMPMap()
                }
            } else {
                Task { @MainActor in
                    await app.service?.postMessage(data: transMsg)
                }
            }
        } else if target == "container" {
            if type == "invokeAPI" {
                guard let name = body.get("name") as? String, !name.isEmpty else {
                    DMPLogger.debug("参数格式错误：name为空")
                    return DMPMap()
                }

                let param: DMPBridgeParam = DMPBridgeParam(value: body.get("params") as Any)
                return app.container!.callBridgeMethod(methodName: name, webViewId: webViewId, param: param, app: app)
            } else if type == "domReady" {
                app.container?.isNavigating = false
                if let webview = webview {
                    webview.hideLoading()
                }
                DMPLogger.debug("domReady")
            }
        } else if target == "webview" {
            // 处理 来自h5 jssdk 的消息
            // if type == "invokeAPI" {
            //     let name: String = body.get("name") as? String ?? ""

            //     if let params = body.get("params"),
            //        (params is String || params is Int || params is Bool || params is [Any]) {
            //         return app.container?.callBridgeMethods(methodName: name, webViewId: webViewId, params: params, app: app)
            //     } else {
            //         DMPLogger.debug("params is not String, Int, Bool, [Any]")
            //     }
            // }
        }

        return DMPMap()
    }

    static func containerToService(msg: DMPMap, app: DMPApp?) {
        DMPLogger.debug("🔴 DMPChannelProxy.containerToService: \(msg.toJsonString()) \(app)")
        app?.service?.fromContainer(data: msg)
    }

    static func containerToRender(msg: DMPMap, app: DMPApp?, webViewId: Int) {
        DMPLogger.debug("🔴 DMPChannelProxy.containerToRender: \(msg.toJsonString()) \(app) \(webViewId)")
        app?.render?.fromContainer(data: msg, webViewId: webViewId)
    }

    static func serviceToRender(msg: String, webViewId: Int, app: DMPApp?) {
        DMPLogger.debug("🔴 DMPChannelProxy.serviceToRender: \(msg) \(webViewId) \(app)")
        app?.render?.fromService(msg: msg, webViewId: webViewId)
    }

    static func renderToService(msg: String, app: DMPApp?) async {
        DMPLogger.debug("🔴 DMPChannelProxy.renderToService: \(msg) \(app)")
        await app?.service?.fromRender(data: msg)
    }
}
