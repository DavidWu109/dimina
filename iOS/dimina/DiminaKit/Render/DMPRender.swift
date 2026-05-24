//
//  DMPRender.swift
//  dimina
//
//  Created by Lehem on 2025/4/22.
//

import Foundation
import SwiftUI
import WebKit

public class DMPRender: DMPWebViewDelegate {
    private var webviewsMap: [Int: DMPWebview] = [:]
    private weak var app: DMPApp?

    private lazy var invokeHandler: DMPWebViewInvoke = DMPWebViewInvoke(render: self)
    private lazy var publishHandler: DMPWebViewPublish = DMPWebViewPublish(render: self)

    public init(app: DMPApp? = nil) {
        self.app = app
    }

    public func getApp() -> DMPApp? {
        return app
    }

    @MainActor
    public func createWebView(appName: String) -> DMPWebview {
        let webview = DMPWebViewPool.shared.acquireWebView(
            delegate: self,
            appName: appName,
            appId: app?.getAppId() ?? ""
        )
        webviewsMap[webview.getWebViewId()] = webview
        return webview
    }

    // Release WebView instance
    @MainActor
    public func releaseWebView(_ webview: DMPWebview) {
        let webViewId = webview.getWebViewId()
        NativeComponentAPI.clear(webViewId: webViewId)
        webviewsMap.removeValue(forKey: webViewId)
        DMPWebViewPool.shared.releaseWebView(webview)
    }

    public func getWebView(byId id: Int) -> DMPWebview? {
        return webviewsMap[id]
    }

    // Execute JavaScript code
    public func executeJavaScript(webViewId: Int, _ script: String, completionHandler: ((Any?, Error?) -> Void)? = nil) -> Void {
        webviewsMap[webViewId]?.executeJavaScript(script, completionHandler: completionHandler)
    }

    // Register JavaScript method to allow Native to listen to JavaScript calls
    public func registerJSHandler(webViewId: Int, handlerName: String, callback: @escaping (Any) -> Void) {
        webviewsMap[webViewId]?.registerJSHandler(handlerName: handlerName, callback: callback)
    }

    // Set up JS bridge for single WebView
    public func setupJSBridge(webViewId: Int) {
        guard let webview = webviewsMap[webViewId] else { return }

        // Register handlers
        invokeHandler.registerInvokeHandler(webview: webview, webViewId: webViewId)
        publishHandler.registerPublishHandler(webview: webview)

        // Inject JavaScript code
        invokeHandler.injectInvokeJavaScript(webview: webview)
        publishHandler.injectPublishJavaScript(webview: webview)
    }

    // Provide WebView view for DMPPage
    public func getWebViewRepresentable(webViewId: Int) -> AnyView {
        if let webview = webviewsMap[webViewId] {
            // Use createWebView() method to create complete view
            return AnyView(webview.createWebView())
        }
        return AnyView(Text("WebView not initialized").padding())
    }

    // DMPWebViewDelegate protocol implementation - Handle WebView load completion event
    public func webViewDidFinishLoad(webViewId: Int) {
        DMPLog.render.info("webViewDidFinishLoad id=\(webViewId)")
        let webview = webviewsMap[webViewId]

        guard let webview = webview else {
            DMPLog.render.warn("webview id=\(webViewId) not found in map, skip resource loading")
            return
        }

        if webview.poolState != .loading {
            DMPLog.render.warn("webview id=\(webViewId) not in loading state (\(webview.poolState.description)), skip resource loading")
            return
        }

        let currentPagePath = webview.getPagePath()
        if currentPagePath.isEmpty || currentPagePath == "resetting" {
            DMPLog.render.warn("webview id=\(webViewId) invalid pagePath '\(currentPagePath)', skip resource loading")
            return
        }

        DMPLog.render.info("webview id=\(webViewId) ready, loading resources for path=\(currentPagePath)")
        Task { [weak self, weak webview] in
            await self?.app?.container?.loadResourceService(webViewId: webViewId, pagePath: currentPagePath)

            await MainActor.run { [weak self, weak webview] in
                guard let self = self, let webview = webview else { return }
                self.app?.container?.loadResourceRender(webViewId: webViewId, pagePath: currentPagePath)

                self.scheduleDOMDiagnostics(webview: webview, webViewId: webViewId)

                webview.poolState = .ready
                DMPLog.render.info("webview id=\(webViewId) marked as ready")
            }
        }
    }

    // DMPWebViewDelegate protocol implementation - Handle WebView load failure event
    public func webViewDidFailLoad(webViewId: Int, error: Error) {
        let ns = error as NSError
        DMPLog.render.error("webViewDidFailLoad id=\(webViewId) domain=\(ns.domain) code=\(ns.code) msg=\(error.localizedDescription)")
    }

    public func fromContainer(data: DMPMap, webViewId: Int) {
        let webview = webviewsMap[webViewId]
        let dataString = data.toJsonString()
        DMPLog.bridge.debug("container→render webViewId=\(webViewId) data=\(dataString)")

        DispatchQueue.main.async {
            webview?.executeJavaScript("DiminaRenderBridge.onMessage(\(dataString))", completionHandler: nil)
        }
    }

    public func fromService(msg: String, webViewId: Int) {
        let webview = webviewsMap[webViewId]
        DMPLog.bridge.debug("service→render webViewId=\(webViewId) msg=\(msg)")

        DispatchQueue.main.async {
            webview?.executeJavaScript("DiminaRenderBridge.onMessage(\(msg))", completionHandler: nil)
        }
    }

    /// 启动后延迟 dump WebView 实际 DOM/Vue 状态，定位白屏。
    private func scheduleDOMDiagnostics(webview: DMPWebview, webViewId: Int) {
        // 跑两次：3s 看异步数据是否到位，10s 看是否最终仍为空。
        for delay in [3.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak webview] in
                webview?.executeJavaScript(Self.domDiagnosticScript) { result, error in
                    if let error = error {
                        DMPLog.render.error("DOM diag id=\(webViewId) t=\(delay)s error=\(error)")
                        return
                    }
                    let json = (result as? String) ?? "nil"
                    DMPLog.render.info("DOM diag id=\(webViewId) t=\(delay)s \(json)")
                }
            }
        }
    }

    private static let domDiagnosticScript = """
    (function() {
        try {
            var html = document.documentElement;
            var body = document.body;
            var htmlFS = getComputedStyle(html).fontSize;
            var htmlSize = html.getBoundingClientRect();
            var bodySize = body ? body.getBoundingClientRect() : null;
            var bodyChildren = [];
            if (body) {
                for (var i = 0; i < body.children.length && i < 10; i++) {
                    var c = body.children[i];
                    var r = c.getBoundingClientRect();
                    var cs = getComputedStyle(c);
                    bodyChildren.push({
                        tag: c.tagName.toLowerCase(),
                        id: c.id || '',
                        cls: (c.className || '').toString().substring(0, 80),
                        w: r.width|0, h: r.height|0,
                        display: cs.display,
                        visibility: cs.visibility,
                        opacity: cs.opacity,
                        childCount: c.children.length
                    });
                }
            }
            // 抓 page-frame / mp-page-frame / app-root 这类 dimina 标志性容器
            var pageFrame = document.querySelector('page-frame, mp-page-frame, .page-frame, #pageFrame, app');
            var pageFrameHTML = pageFrame ? pageFrame.outerHTML.substring(0, 1500) : 'NOT FOUND';
            // 抓 JS 全局错误
            var errors = (window.__diminaErrors || []).slice(-10);
            // 抓最近 fetch/XHR 失败（如果有埋点）
            var netErrors = (window.__diminaNetworkErrors || []).slice(-10);
            // visibility / 是否在 DOM 里
            var bodyHTMLLen = body ? body.innerHTML.length : -1;
            return JSON.stringify({
                htmlFontSize: htmlFS,
                htmlRect: {w: htmlSize.width|0, h: htmlSize.height|0},
                bodyRect: bodySize ? {w: bodySize.width|0, h: bodySize.height|0} : null,
                bodyHTMLLen: bodyHTMLLen,
                bodyChildren: bodyChildren,
                pageFrame: pageFrameHTML,
                errors: errors,
                netErrors: netErrors,
                url: location.href
            });
        } catch (e) {
            return JSON.stringify({diagError: String(e), stack: e.stack || ''});
        }
    })()
    """
}
