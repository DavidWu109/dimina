//
//  DMPWebViewPool.swift
//  dimina
//
//  Created by Lehem on 2025/5/15.
//

import Foundation
import WebKit
import UIKit

/// WebView cache pool management class
/// Responsible for pre-creating, caching and reusing WebView instances to improve page opening speed
@MainActor
public class DMPWebViewPool {
    // MARK: - Singleton
    public static let shared = DMPWebViewPool()

    // MARK: - Properties
    private var webViews: [DMPWebview] = []
    private let maxPoolSize: Int = 4
    private let minPoolSize: Int = 1

    // Shared WKProcessPool instance - ensure creation on main thread
    internal static let sharedProcessPool: WKProcessPool = {
        // Ensure creation on main thread
        assert(Thread.isMainThread, "WKProcessPool must be created on main thread")
        let processPool = WKProcessPool()
        print("🔧 WebViewPool: Created shared WKProcessPool")
        return processPool
    }()

    // MARK: - Initialization
    private init() {
        setupNotifications()
        // Pre-warm during initialization - on main thread
        Task { @MainActor in
            await preloadWebViews()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webViews.removeAll()
        print("🧹 WebViewPool: Clear pool during deallocation")
    }

    // MARK: - Notification Setup
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Add application termination notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: - Public Methods

    /// Get a usable WebView instance
    /// - Parameters:
    ///   - delegate: WebView delegate
    ///   - appName: Application name
    ///   - appId: Application ID
    /// - Returns: Configured DMPWebview instance
    public func acquireWebView(delegate: DMPWebViewDelegate?, appName: String, appId: String) -> DMPWebview {
        let webview: DMPWebview
        let reused: Bool

        if let availableWebView = findAvailableWebView() {
            // Reuse existing WebView
            webview = availableWebView
            webview.poolState = .configuring
            webview.regenerateWebViewId()
            webview.setDelegate(delegate)
            webview.resetForReuse(appName: appName, appId: appId)
            reused = true
        } else {
            // Create new WebView
            webview = createNewWebView(delegate: delegate, appName: appName, appId: appId)
            webview.regenerateWebViewId()
            webview.poolState = .configuring
            webViews.append(webview)
            reused = false
        }

        DMPLog.pool.info("acquire id=\(webview.getWebViewId()) reused=\(reused) appId=\(appId) \(poolSnapshot())")

        // Asynchronous preload more WebViews - on main thread
        Task { @MainActor in
            await preloadWebViewsIfNeeded()
        }

        return webview
    }

    /// Release WebView instance back to pool
    /// - Parameter webview: WebView to release
    public func releaseWebView(_ webview: DMPWebview) {
        let webViewId = webview.getWebViewId()

        guard let targetWebView = webViews.first(where: { $0.getWebViewId() == webViewId && $0.poolState.isInUse }) else {
            DMPLog.pool.warn("release skipped, webview id=\(webViewId) not in use")
            return
        }

        targetWebView.poolState = .reseting
        DMPLog.pool.info("release id=\(webViewId) → reseting \(poolSnapshot())")

        // Asynchronously clean WebView state to avoid blocking main thread
        Task { @MainActor in
            targetWebView.prepareForReuse()
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            let totalCount = self.webViews.count
            if totalCount <= self.maxPoolSize {
                targetWebView.poolState = .available
                DMPLog.pool.info("recycled id=\(webViewId) → available \(self.poolSnapshot())")
            } else {
                self.webViews.removeAll { $0.getWebViewId() == webViewId }
                self.cleanupWebView(targetWebView)
                DMPLog.pool.info("pool full, destroyed id=\(webViewId) \(self.poolSnapshot())")
            }
        }
    }

    /// Snapshot of pool state for logging.
    fileprivate func poolSnapshot() -> String {
        let available = webViews.filter { $0.poolState.canReuse }.count
        let inUse = webViews.filter { $0.poolState.isInUse }.count
        let reseting = webViews.filter { $0.poolState == .reseting }.count
        return "(pool avail=\(available) inUse=\(inUse) reseting=\(reseting) total=\(webViews.count))"
    }

    /// Warm up WebView pool
    public func warmUp() {
        DMPLog.pool.debug("warmUp \(poolSnapshot())")
        Task { @MainActor in
            await preloadWebViews()
        }
    }

    /// Clear pool
    public func clearPool() {
        DMPLog.pool.info("clearPool start \(poolSnapshot())")

        // 1. Clean all non-using WebViews
        for webview in webViews {
            if !webview.poolState.isInUse {
                cleanupWebView(webview)
            }
        }

        // 2. Remove all non-using WebViews
        webViews.removeAll { !$0.poolState.isInUse }

        let stillInUseCount = webViews.filter { $0.poolState.isInUse }.count
        if stillInUseCount > 0 {
            DMPLog.pool.warn("clearPool: \(stillInUseCount) webviews still in use, not destroyed")
        }
        DMPLog.pool.info("clearPool done \(poolSnapshot())")
    }

    /// Completely clean single WebView
    private func cleanupWebView(_ webview: DMPWebview) {
        DMPLog.pool.debug("cleanupWebView id=\(webview.getWebViewId())")

        let wkView = webview.getWebView()
        wkView.endEditing(true)
        wkView.scrollView.endEditing(true)
        // Stop all network requests
        wkView.perform(NSSelectorFromString("stopLoading"))

        // Clean logger
        webview.logger?.cleanup()

        // Clean all message processors
        let userContentController = wkView.configuration.userContentController
        userContentController.removeAllUserScripts()

        // Clean all possible processors
        let allPossibleHandlers = ["invokeHandler", "publishHandler", "consoleLog", "consoleError",
                                 "consoleWarn", "consoleInfo", "jsError", "networkError", "resourceError"]

        for handlerName in allPossibleHandlers {
            do {
                userContentController.removeScriptMessageHandler(forName: handlerName)
            } catch {
                // Ignore cleanup error
            }
        }

        // Clean custom JS bridges
        for handlerName in webview.jsBridgeCallbacks.keys {
            if !allPossibleHandlers.contains(handlerName) {
                do {
                    userContentController.removeScriptMessageHandler(forName: handlerName)
                } catch {
                    // Ignore cleanup error
                }
            }
        }
        webview.jsBridgeCallbacks.removeAll()

        // Navigate to blank page
        wkView.loadHTMLString("<html><body></body></html>", baseURL: nil)

        print("🧹 WebViewPool: WebView (ID: \(webview.getWebViewId())) cleaned")
    }

    /// Get pool status information
    public func getPoolStatus() -> (available: Int, used: Int) {
        let availableCount = webViews.filter { $0.poolState.canReuse }.count
        let inUseCount = webViews.filter { $0.poolState.isInUse }.count
        return (available: availableCount, used: inUseCount)
    }

    /// Get detailed pool status for debugging
    public func getDetailedPoolStatus() -> (available: Int, inUse: Int, reseting: Int, total: Int) {
        let availableCount = webViews.filter { $0.poolState.canReuse }.count
        let inUseCount = webViews.filter { $0.poolState.isInUse }.count
        let resetingCount = webViews.filter { $0.poolState == .reseting }.count
        return (available: availableCount, inUse: inUseCount, reseting: resetingCount, total: webViews.count)
    }

    // MARK: - Private Methods

    /// Preload WebViews
    private func preloadWebViews() async {
        let currentCount = webViews.count
        let neededCount = max(0, minPoolSize - currentCount) // Ensure not negative

        print("🔧 WebViewPool: Current pool has \(currentCount) WebViews, need to preload \(neededCount)")

        // Create only when needed
        guard neededCount > 0 else {
            print("🔧 WebViewPool: WebView pool count meets minimum requirement, no need to preload")
            return
        }

        for i in 0..<neededCount {
            // Double check, ensure not exceed max pool size
            if webViews.count >= maxPoolSize {
                print("🔧 WebViewPool: Already reached max pool size, stop preloading")
                break
            }

            let webview = createNewWebView(delegate: nil, appName: "", appId: "")
            webview.poolState = .available  // Preloaded WebViews should be available state
            webViews.append(webview)
            print("🔧 WebViewPool: Preload WebView \(i+1)/\(neededCount) (ID: \(webview.getWebViewId())), state: \(webview.poolState.description)")
        }

        print("🔧 WebViewPool: Preload completed, current pool has \(webViews.count) WebViews")
    }

    /// Preload more WebViews as needed
    private func preloadWebViewsIfNeeded() async {
        let currentCount = webViews.count
        let availableCount = webViews.filter { $0.poolState.canReuse }.count

        // Only preload when available WebViews are less than minimum and total count is less than max
        if availableCount < minPoolSize && currentCount < maxPoolSize {
            let webview = createNewWebView(delegate: nil, appName: "", appId: "")
            webview.poolState = .available  // Preloaded WebViews should be available state
            webViews.append(webview)
            print("🔧 WebViewPool: Preload WebView as needed (ID: \(webview.getWebViewId())), state: \(webview.poolState.description), current pool has \(webViews.count) WebViews")
        } else {
            print("🔧 WebViewPool: Pool status good, no need to preload - Available: \(availableCount), Total: \(currentCount), Min: \(minPoolSize), Max: \(maxPoolSize)")
        }
    }

    /// Create new WebView instance - must be called on main thread
    private func createNewWebView(delegate: DMPWebViewDelegate?, appName: String, appId: String) -> DMPWebview {
        assert(Thread.isMainThread, "WebView must be created on main thread")

        let webview = DMPWebview(
            delegate: delegate,
            appName: appName,
            appId: appId,
            processPool: Self.sharedProcessPool
        )
        return webview
    }

    /// Find available WebView
    private func findAvailableWebView() -> DMPWebview? {
        // Select from WebViews in reusable state
        for webview in webViews where webview.poolState.canReuse {
            // Check if WebView is in a state suitable for reuse
            if webview.getWebView().isLoading {
                print("🟡 WebViewPool: WebView (ID: \(webview.getWebViewId())) is still loading, skipping")
                continue
            }

            print("🟢 WebViewPool: Found available WebView (ID: \(webview.getWebViewId())) for reuse")
            return webview
        }

        print("🔍 WebViewPool: No available WebView found, will create new one")
        return nil
    }

    // MARK: - Notification Handlers

    @objc private func applicationDidEnterBackground() {
        // When app enters background, consider cleaning some WebViews to save memory
        print("🌙 WebViewPool: App entering background")
    }

    @objc private func applicationWillEnterForeground() {
        // When app is about to enter foreground, warm up WebView pool
        print("🌅 WebViewPool: App about to enter foreground, warming up pool")
        warmUp()
    }

    @objc private func applicationDidReceiveMemoryWarning() {
        // When receive memory warning, clean some WebViews
        print("⚠️ WebViewPool: Received memory warning, cleaning pool")

        // Only keep minimum number of available WebViews, remove others
        let availableWrappers = webViews.filter { $0.poolState.canReuse }
        let keepCount = min(minPoolSize, availableWrappers.count)

        if availableWrappers.count > keepCount {
            let wrappersToRemove = Array(availableWrappers.dropFirst(keepCount))
            for wrapper in wrappersToRemove {
                cleanupWebView(wrapper)
            }
            webViews.removeAll { wrapper in
                wrapper.poolState.canReuse && wrappersToRemove.contains { $0.getWebViewId() == wrapper.getWebViewId() }
            }
            print("⚠️ WebViewPool: Cleaned \(wrappersToRemove.count) available WebViews due to memory warning")
        }
    }

    @objc private func applicationWillTerminate() {
        // When app is about to terminate, clean all WebViews
        print("🌙 WebViewPool: App about to terminate, cleaning all WebViews")
        clearPool()
    }

    /// Get shared process pool
    internal func getSharedProcessPool() -> WKProcessPool {
        return Self.sharedProcessPool
    }
}

// MARK: - WebView Pool Extensions
extension DMPWebview {
    /// Prepare WebView for reuse
    @MainActor
    fileprivate func prepareForReuse() {
        print("🧽 WebView (ID: \(getWebViewId())) start preparing for reuse")

        let wkView = getWebView()
        wkView.endEditing(true)
        wkView.scrollView.endEditing(true)
        wkView.perform(NSSelectorFromString("stopLoading"))

        let userContentController = wkView.configuration.userContentController
        userContentController.removeAllUserScripts()
        print("🧽 WebView (ID: \(getWebViewId())) cleaned user scripts")

        let allHandlerNames = [
            // JS bridge handlers
            "invokeHandler", "publishHandler",
            // Log handlers
            "consoleLog", "consoleError", "consoleWarn", "consoleInfo",
            // Error handlers
            "jsError", "networkError", "resourceError"
        ]

        // First clean known standard handlers
        for handlerName in allHandlerNames {
            do {
                userContentController.removeScriptMessageHandler(forName: handlerName)
                print("🧽 WebView (ID: \(getWebViewId())) cleaned handler: \(handlerName)")
            } catch {
                // If handler doesn't exist, ignore error
                print("🟡 WebView (ID: \(getWebViewId())) handler \(handlerName) doesn't exist, skip cleanup")
            }
        }

        // Then clean custom handlers recorded in jsBridgeCallbacks
        for handlerName in jsBridgeCallbacks.keys {
            if !allHandlerNames.contains(handlerName) {
                do {
                    userContentController.removeScriptMessageHandler(forName: handlerName)
                    print("🧽 WebView (ID: \(getWebViewId())) cleaned custom handler: \(handlerName)")
                } catch {
                    print("🟡 WebView (ID: \(getWebViewId())) custom handler cleanup failed: \(handlerName), error: \(error)")
                }
            }
        }

        // Clear callback records
        jsBridgeCallbacks.removeAll()
        print("🧽 WebView (ID: \(getWebViewId())) cleaned all JS bridge callbacks")

        if logger != nil {
            print("🧽 WebView (ID: \(getWebViewId())) keep existing logger to avoid double cleanup")
        }

        // Use minimized HTML to ensure WebView status is normal, but avoid completely blank page that might cause issues
        wkView.loadHTMLString("""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Preparing...</title>
        </head>
        <body>
            <script>
                // Clear potentially remaining global variables and event listeners
                if (typeof window.DiminaRenderBridge !== 'undefined') {
                    delete window.DiminaRenderBridge;
                }
                if (typeof window.DiminaServiceBridge !== 'undefined') {
                    delete window.DiminaServiceBridge;
                }

                // Remove all event listeners
                window.removeEventListener = function() {};
                document.removeEventListener = function() {};

                console.log('WebView prepared for reuse');
            </script>
        </body>
        </html>
        """, baseURL: nil)
    }

    /// Reset WebView for new application
    @MainActor
    fileprivate func resetForReuse(appName: String, appId: String) {
        print("🔄 WebView (ID: \(getWebViewId())) start reset for app: \(appName)")

        // Update application information
        self.appName = appName

        if self.logger == nil {
            // Re-initialize logger (only when no logger exists)
            self.logger = DMPWebViewLogger(webView: self.getWebView(), webViewId: self.getWebViewId())
            print("🔄 WebView (ID: \(getWebViewId())) re-initialized logger")
        } else {
            print("🔄 WebView (ID: \(getWebViewId())) logger already exists, skip re-initialization")
            // Ensure existing logger is in good state, update webViewId
            self.logger?.updateWebViewId(self.getWebViewId())
            print("🔄 WebView (ID: \(getWebViewId())) updated logger webViewId")
        }

        // Page path will be correctly set in DMPPageController.configWebView()
        self.query.removeAll()
        self.pagePath = ""
        print("🔄 WebView (ID: \(getWebViewId())) cleared query parameters and page path")
    }
}
