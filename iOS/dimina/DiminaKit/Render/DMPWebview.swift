//
//  DMPWebview.swift
//  dimina
//
//  Created by Lehem on 2025/4/22.
//

import Foundation
import WebKit
import SwiftUI

/// WebView state enum
public enum DMPWebViewState {
    case available          // Available state, can be reused
    case configuring        // Configuring, setting page path and parameters
    case loading            // Loading, loading page content
    case ready              // Ready state, page load completed, can interact
    case reseting           // Resetting, clearing state, cannot be reused
    
    var description: String {
        switch self {
        case .available: return "available"
        case .configuring: return "configuring"
        case .loading: return "loading"
        case .ready: return "ready"
        case .reseting: return "reseting"
        }
    }
    
    /// Whether it can be reused
    var canReuse: Bool {
        return self == .available
    }
    
    /// Whether it is in use
    var isInUse: Bool {
        return self == .configuring || self == .loading || self == .ready
    }
    
    /// Whether page interaction is possible
    var canInteract: Bool {
        return self == .ready
    }
    
    /// Whether it is loading
    var isLoading: Bool {
        return self == .loading
    }
}

// Define WebView delegate protocol
public protocol DMPWebViewDelegate: AnyObject {
    func webViewDidFinishLoad(webViewId: Int)
    func webViewDidFailLoad(webViewId: Int, error: Error)
}

public class DMPWebview: NSObject, WKNavigationDelegate, WKScriptMessageHandler, ObservableObject {
    private var webView: WKWebView
    private weak var delegate: DMPWebViewDelegate?
    internal var jsBridgeCallbacks: [String: (Any) -> Void] = [:]

    // Add WebViewLogger member variable
    internal var logger: DMPWebViewLogger?

    private var webViewId: Int
    internal var pagePath: String
    internal var query: [String: Any] = [:]
    
    public let createdAt: Date = Date()
    
    // Add default configuration method
    private static func defaultConfiguration(appId: String, processPool: WKProcessPool? = nil) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        
        // Use performance optimizer to apply all optimization configurations
        DMPWebViewOptimizer.shared.applyOptimizations(to: config, appId: appId, processPool: processPool)
        
        return config
    }

    public var appName: String
    
    // Publish notification when state changes
    @Published public var poolState: DMPWebViewState = .available {
        didSet {
            // When the state changes, trigger UI update
            objectWillChange.send()
        }
    }
    
    // Calculate property: based on state return whether it is loading
    public var isLoading: Bool {
        return poolState.isLoading
    }

    // Modify constructor
    public init(delegate: DMPWebViewDelegate?, appName: String, appId: String, processPool: WKProcessPool? = nil) {
        let config = DMPWebview.defaultConfiguration(appId: appId, processPool: processPool)

        self.webView = WKWebView(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) {
            self.webView.isInspectable = true
        }
        self.delegate = delegate
        self.webViewId = DMPIdProvider.generateWebViewId()
        self.pagePath = ""
        self.appName = appName

        super.init()

        self.webView.navigationDelegate = self

        // Apply WebView instance optimization
        DMPWebViewOptimizer.shared.optimizeWebViewInstance(self.webView)

        // Initialize log recorder
        self.logger = DMPWebViewLogger(webView: self.webView, webViewId: self.webViewId)
    }

    // Set delegate method
    public func setDelegate(_ delegate: DMPWebViewDelegate?) {
        self.delegate = delegate
    }

    // Set log handler delegate
    public func setLoggerDelegate(_ delegate: DMPWebViewLoggerDelegate?) {
        self.logger?.setDelegate(delegate)
    }
    
    // Inject CSS JS IMG resources
    private func injectResourceFixScript() {
        let resourceFixScript = WKUserScript(source: """
        (function() {
        
            function convertTodiminaURL(url) {
                if (!url) return url;
                
                if (url.startsWith('file:///')) {
                    const newUrl = 'dimina:///' + url.substring(8);
                    return newUrl;
                }
                
                if (url.startsWith('/')) {
                    const newUrl = 'dimina:///' + url.substring(1);
                    return newUrl;
                }
                
                return url;
            }

            // Intercept document.createElement
            const originalCreateElement = document.createElement;
            document.createElement = function(tagName) {
                const element = originalCreateElement.call(document, tagName);
                // Special handling for image elements
                if (tagName.toLowerCase() === 'img') {
                    console.log('[DEBUG] Creating image element, starting interception');
                    // Override setAttribute method
                    const originalSetAttribute = element.setAttribute;
                    element.setAttribute = function(name, value) {
                        if (name === 'src') {
                            if (value && (value.startsWith('file:///') || value.startsWith('/'))) {
                                value = convertTodiminaURL(value);
                                console.log('[DEBUG] Converted src attribute:', value);
                            }
                        }
                        return originalSetAttribute.call(this, name, value);
                    };
                    
                    // Override src property
                    const originalSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
                    Object.defineProperty(element, 'src', {
                        get: function() {
                            return originalSrcDescriptor.get.call(this);
                        },
                        set: function(value) {
                            if (value && (value.startsWith('file:///') || value.startsWith('/'))) {
                                value = convertTodiminaURL(value);
                                console.log('[DEBUG] Converted src value:', value);
                            }
                            return originalSrcDescriptor.set.call(this, value);
                        }
                    });
                }
                return element;
            };

            // Intercept document.head.append and appendChild
            const originalAppendChild = Node.prototype.appendChild;
            Node.prototype.appendChild = function(node) {
                // Fix resource URLs before adding to DOM
                if (node.nodeName === 'LINK' && node.rel === 'stylesheet' && node.href && node.href.startsWith('file:///')) {
                    console.log('Intercepted CSS addition:', node.href);
                    node.href = 'dimina:' + node.href.substring(5);
                }
                else if (node.nodeName === 'SCRIPT' && node.src && node.src.startsWith('file:///')) {
                    console.log('Intercepted JS addition:', node.src);
                    node.src = 'dimina:' + node.src.substring(5);
                }
                else if (node.nodeName === 'IMG') {
                    console.log('[DEBUG] appendChild image:', node.src);
                    if (node.src && (node.src.startsWith('file:///') || node.src.startsWith('/'))) {
                        node.src = convertTodiminaURL(node.src);
                        console.log('[DEBUG] appendChild after image src:', node.src);
                    }
                }
                return originalAppendChild.call(this, node);
            };

            // Intercept Element.prototype.append
            if (Element.prototype.append) {
                const originalAppend = Element.prototype.append;
                Element.prototype.append = function() {
                    for (let i = 0; i < arguments.length; i++) {
                        const node = arguments[i];
                        if (node && node.nodeName) {
                            if (node.nodeName === 'LINK' && node.rel === 'stylesheet' && node.href && node.href.startsWith('file:///')) {
                                console.log('Intercepted CSS addition (append):', node.href);
                                node.href = 'dimina:' + node.href.substring(5);
                            }
                            else if (node.nodeName === 'SCRIPT' && node.src && node.src.startsWith('file:///')) {
                                console.log('Intercepted JS addition (append):', node.src);
                                node.src = 'dimina:' + node.src.substring(5);
                            }
                            else if (node.nodeName === 'IMG') {
                                console.log('[DEBUG] append image:', node.src);
                                if (node.src && (node.src.startsWith('file:///') || node.src.startsWith('/'))) {
                                    node.src = convertTodiminaURL(node.src);
                                    console.log('[DEBUG] append after image src:', node.src);
                                }
                            }
                        }
                    }
                    return originalAppend.apply(this, arguments);
                };
            }

            // Immediately add an observer to monitor dynamically added resources
            const observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    if (mutation.type === 'childList') {
                        mutation.addedNodes.forEach(function(node) {
                            // Handle resource nodes already added to DOM
                            if (node.nodeName === 'LINK' && node.rel === 'stylesheet' && node.href && node.href.startsWith('file:///')) {
                                console.log('Found unintercepted CSS:', node.href);
                                const newHref = 'dimina:' + node.href.substring(5);
                                node.href = newHref; // Try to modify directly
                            }
                            else if (node.nodeName === 'SCRIPT' && node.src && node.src.startsWith('file:///')) {
                                console.log('Found unintercepted JS:', node.src);
                                // For scripts, may need to remove and re-add
                                const newSrc = 'dimina:' + node.src.substring(5);
                                node.src = newSrc;
                            }
                            else if (node.nodeName === 'IMG') {
                                console.log('[DEBUG] Observed new image:', node.src);
                                if (node.src && (node.src.startsWith('file:///') || node.src.startsWith('/'))) {
                                    node.src = convertTodiminaURL(node.src);
                                    console.log('[DEBUG] Processed image src:', node.src);
                                }
                            }
                        });
                    }
                    
                    // Special handling for attribute changes, check changes to image src attributes
                    else if (mutation.type === 'attributes' && mutation.attributeName === 'src' && mutation.target.nodeName === 'IMG') {
                        const img = mutation.target;
                        if (img.src && (img.src.startsWith('file:///') || img.src.startsWith('/'))) {
                            console.log('[DEBUG] Image attribute change:', img.src);
                            img.src = convertTodiminaURL(img.src);
                            console.log('[DEBUG] After attribute change image src:', img.src);
                        }
                    }
                });
            });
            
            // Start observer, also monitor attribute changes
            observer.observe(document, { 
                childList: true, 
                subtree: true,
                attributes: true,
                attributeFilter: ['src', 'href']
            });
            
            // Handle existing images before document loading completes and resource loading
            document.addEventListener('DOMContentLoaded', function() {
                console.log('[DEBUG] Processing existing images:', img.src);
                if (img.src && (img.src.startsWith('file:///') || img.src.startsWith('/'))) {
                    img.src = convertTodiminaURL(img.src);
                    console.log('[DEBUG] Processed image src:', img.src);
                }
            });
            
            // Check image tags on page
            document.addEventListener('DOMContentLoaded', function() {
                console.log('[DEBUG] DOMContentLoaded triggered, looking for images');
                const imgs = document.querySelectorAll('img');
                console.log('[DEBUG] Found image count:', imgs.length);
                imgs.forEach(function(img, index) {
                    console.log(`[DEBUG] Image${index} src:`, img.src);
                    if (img.src && (img.src.startsWith('file:///') || img.src.startsWith('/'))) {
                        const oldSrc = img.src;
                        img.src = convertTodiminaURL(img.src);
                        console.log(`[DEBUG] Image${index} converted: ${oldSrc} -> ${img.src}`);
                    }
                });
            });
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        
        webView.configuration.userContentController.addUserScript(resourceFixScript)
    }

    // Load page framework
    public func loadPageFrame() {
        injectResourceFixScript()

        // Use loadFileURL to load files and allow access to entire sandbox directory
        let fileURL = URL(fileURLWithPath: DMPSandboxManager.sdkPageFramePath())
        let allowingReadAccessTo = URL(fileURLWithPath: DMPSandboxManager.sandboxPath())
        webView.loadFileURL(fileURL, allowingReadAccessTo: allowingReadAccessTo)
    }

    // Register a JS message handler to allow JS to call native methods
    public func registerJSHandler(handlerName: String, callback: @escaping (Any) -> Void) {
        print("🔧 WebView (ID: \(getWebViewId())) trying to register handler: \(handlerName)")
        
        // Check if this handler is already registered
        if jsBridgeCallbacks[handlerName] != nil {
            print("⚠️ WebView (ID: \(getWebViewId())) handler \(handlerName) already exists, clean first then re-register")
            // Remove existing handler first
            webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
            print("🧹 WebView (ID: \(getWebViewId())) cleaned handler: \(handlerName)")
        }
        
        // Use safe way to register handler to prevent system-level duplicate registration exceptions
        webView.configuration.userContentController.add(self, name: handlerName)
        jsBridgeCallbacks[handlerName] = callback
        print("✅ WebView (ID: \(getWebViewId())) successfully registered handler: \(handlerName)")
    }

    // Execute JavaScript code
    public func executeJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)? = nil) -> Void {
        if Thread.isMainThread {
            webView.evaluateJavaScript(script, completionHandler: completionHandler)
        } else {
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(script, completionHandler: completionHandler)
            }
        }
    }

    // WKScriptMessageHandler implementation
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let callback = jsBridgeCallbacks[message.name] {
            callback(message.body)
        }
    }

    // WKNavigationDelegate implementation - Use delegate pattern instead of direct dependency
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🔴 DMPWebview: Web page load completed \(webViewId)")
        // Notify web page load completion through delegate callback
        delegate?.webViewDidFinishLoad(webViewId: self.webViewId)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("Web page load failed: \(error.localizedDescription)")
        // Add detailed error information logging
        let errorInfo: [String: Any] = [
            "message": error.localizedDescription,
            "domain": (error as NSError).domain,
            "code": (error as NSError).code,
            "userInfo": (error as NSError).userInfo,
            "webViewId": self.webViewId
        ]
        print("Detailed error information: \(errorInfo)")
        // Notify web page load failure through delegate callback
        delegate?.webViewDidFailLoad(webViewId: self.webViewId, error: error)
    }

    // Use custom URL scheme to handle resource loading
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Empty implementation, allow all navigation requests
        decisionHandler(.allow)
    }

    // Get underlying WKWebView
    public func getWebView() -> WKWebView {
        return webView
    }

    // Get WebView's unique ID
    public func getWebViewId() -> Int {
        return webViewId
    }

    // Get WebView's page path
    public func getPagePath() -> String {
        return self.pagePath
    }

    public func setPagePath(pagePath: String) {
        self.pagePath = pagePath
    }

    public func getQuery() -> [String: Any] {
        return self.query
    }

    public func setQuery(query: [String: Any]) {
        self.query = query
    }

    // Add internal method to regenerate webViewId
    internal func regenerateWebViewId() {
        self.webViewId = DMPIdProvider.generateWebViewId()
        // Also update logger's webViewId if it exists
        if let logger = self.logger {
            logger.updateWebViewId(self.webViewId)
        }
    }

    // SwiftUI view wrapper
    public struct WebViewRepresentable: UIViewRepresentable {
        @ObservedObject var webview: DMPWebview  // Use @ObservedObject

        public init(webview: DMPWebview) {
            self.webview = webview
        }

        public func makeUIView(context: Context) -> WKWebView {
            return webview.getWebView()
        }

        public func updateUIView(_ uiView: WKWebView, context: Context) {
            // Update UI view (if needed)
        }
    }

    deinit {
        // Clean registered message handlers
        for handlerName in jsBridgeCallbacks.keys {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
        }
        // Clean log recorder
        logger?.cleanup()
        logger = nil
    }

    // Modify hideLoading method
    public func hideLoading() {
        if Thread.isMainThread {
            withAnimation(.easeOut(duration: 0.3)) {
                if self.poolState == .loading {
                    self.poolState = .ready
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    if self.poolState == .loading {
                        self.poolState = .ready
                    }
                }
            }
        }
    }

    public struct WebViewContainer: View {
        @ObservedObject var webview: DMPWebview
        var isRoot: Bool = false

        public init(webview: DMPWebview, isRoot: Bool = false) {
            self.webview = webview
            self.isRoot = isRoot
        }

        public var body: some View {
            if #available(iOS 14.0, *) {
                ZStack {
                    WebViewRepresentable(webview: webview)
                    
                    if webview.isLoading && isRoot {
                        DMPLoadingView(appName: webview.appName)
                            .transition(.opacity)
                    }
                }
                .onChange(of: webview.isLoading) { newValue in
                    print("🔴 DMPWebview: isLoading changed to \(newValue)")
                }
            } else {
                // Fallback on earlier versions
            }
        }
    }

    public func createWebView(isRoot: Bool = false) -> some View {
        WebViewContainer(webview: self, isRoot: isRoot)
    }
}

public struct DMPLoadingView: View {
    let appName: String
    @State private var rotation: Double = 0.0
    let timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()

    public var body: some View {
        ZStack {
            if #available(iOS 14.0, *) {
                Color.white
                    .ignoresSafeArea()
            } else {
                // Fallback on earlier versions
            }

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        .frame(width: 60, height: 60)

                    Circle()
                        .fill(DMPUtil.generateColorFromName(name: appName))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(appName.prefix(1)))
                                .font(.system(size: 16))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )

                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .offset(y: -30)
                        .rotationEffect(.degrees(rotation))
                }
                .frame(width: 60, height: 60)

                Text(appName)
                    .font(.system(size: 14))
                    .fontWeight(.medium)
            }
        }
        .onReceive(timer) { _ in
            withAnimation {
                rotation += 3.0
            }
        }
    }
}

#Preview("LoadingView") {
    DMPLoadingView(appName: "Test App")
}
