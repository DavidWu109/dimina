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
    private func setupJSBridge(webViewId: Int) {
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
        print("🔴 DMPRender: WebView load completed \(webViewId)")
        let webview = webviewsMap[webViewId]

        setupJSBridge(webViewId: webViewId)

        guard let webview = webview else {
            print("🟡DMPRender: WebView (ID: \(webViewId)) not found in map")
            return
        }
        
        if webview.poolState != .loading {
            print("🟡 DMPRender: WebView (ID: \(webViewId)) is not in loading state (\(webview.poolState.description)), skip resource loading")
            return
        }
        
        let currentPagePath = webview.getPagePath()
        if currentPagePath.isEmpty || currentPagePath == "resetting" {
            print("🟡 DMPRender: WebView (ID: \(webViewId)) has invalid page path '\(currentPagePath)', skip resource loading")
            return
        }
        
        print("✅ DMPRender: WebView (ID: \(webViewId)) ready for resource loading with path: \(currentPagePath)")
        self.app?.container?.loadResourceService(webViewId: webViewId, pagePath: currentPagePath);
        self.app?.container?.loadResourceRender(webViewId: webViewId, pagePath: currentPagePath);

        // 诊断：获取完整 DOM 结构（延迟 8 秒等数据加载）
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            webview.executeJavaScript("""
                (function() {
                    function getTree(el, depth) {
                        if (!el || depth > 10) return null;
                        var tag = el.tagName ? el.tagName.toLowerCase() : '#text';
                        var cls = el.className || '';
                        var text = '';
                        if (el.nodeType === 3) text = el.textContent.trim().substring(0, 200);
                        var children = [];
                        if (el.childNodes) {
                            for (var i = 0; i < el.childNodes.length && i < 30; i++) {
                                var c = getTree(el.childNodes[i], depth + 1);
                                if (c) children.push(c);
                            }
                        }
                        var src = el.getAttribute ? (el.getAttribute('src') || '') : '';
                        var style = el.getAttribute ? (el.getAttribute('style') || '') : '';
                        var display = '';
                        try { display = getComputedStyle(el).display; } catch(e) {}
                        return {tag: tag, cls: typeof cls === 'string' ? cls.substring(0, 100) : '', text: text, src: src.substring(0, 200), style: style.substring(0, 150), display: display, children: children};
                    }
                    var htmlFS = getComputedStyle(document.documentElement).fontSize;
                    var qc = document.querySelector('.question-content');
                    var qcHTML = qc ? qc.innerHTML.substring(0, 2000) : 'NOT FOUND';
                    // 检查 JS 错误
                    var errors = window.__dimina_errors || [];
                    // 检查 console.error 输出
                    var consoleErrors = window.__console_errors || [];
                    return JSON.stringify({htmlFontSize: htmlFS, questionContentHTML: qcHTML, errors: errors, consoleErrors: consoleErrors});
                })()
            """) { result, error in
                let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("dimina_jsdiag.log")
                let line = "\(result ?? "nil")"
                try? line.data(using: .utf8)?.write(to: logFile)
            }
        }

        webview.poolState = .ready
        print("✅ DMPRender: WebView (ID: \(webViewId)) marked as ready")
    }

    // DMPWebViewDelegate protocol implementation - Handle WebView load failure event
    public func webViewDidFailLoad(webViewId: Int, error: Error) {
        print("🔴 DMPRender: WebView load failed: \(error.localizedDescription)")
    }

    public func fromContainer(data: DMPMap, webViewId: Int) {
        let webview = webviewsMap[webViewId]
        let dataString = data.toJsonString()

        // 写文件日志
        let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("dimina_render.log")
        let line = "fromContainer webViewId=\(webViewId) data=\(dataString)\n"
        if let logData = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(logData)
                handle.closeFile()
            } else { try? logData.write(to: logFile) }
        }

        DispatchQueue.main.async {
            webview?.executeJavaScript("DiminaRenderBridge.onMessage(\(dataString))", completionHandler: nil)
        }
    }

    public func fromService(msg: String, webViewId: Int) {
        let webview = webviewsMap[webViewId]
        
        DispatchQueue.main.async {
            webview?.executeJavaScript("DiminaRenderBridge.onMessage(\(msg))", completionHandler: nil)
        }
    }
}

