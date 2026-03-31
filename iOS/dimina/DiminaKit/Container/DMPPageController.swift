//
//  DMPPageController.swift
//  dimina
//
//  Created by Lehem on 2025/5/15.
//

import Foundation
import SwiftUI
import UIKit
import WebKit

/// DMPPageController is a specialized view controller for displaying mini-program pages
/// It directly integrates the functionality of both DMPPage and DMPViewController
public class DMPPageController: UIViewController {

    // Weak reference to the navigator
    private weak var navigator: DMPNavigator?

    // Page properties
    private let pagePath: String
    private let query: [String: Any]?
    private let appConfig: DMPAppConfig
    private weak var app: DMPApp?
    private let isRoot: Bool
    private weak var overlayView: UIView?

    // WebView related
    private var webview: DMPWebview
    private var hostingController: UIHostingController<DMPWebViewContainer>?

    // State
    private var isWebViewDestroyed = false

    /// Initialization method
    /// - Parameters:
    ///   - pagePath: Page path
    ///   - query: Query parameters
    ///   - appConfig: App configuration
    ///   - app: App instance
    ///   - navigator: Navigator
    ///   - isRoot: Whether this is a root view controller
    public init(
        pagePath: String, query: [String: Any]?, appConfig: DMPAppConfig, app: DMPApp?,
        navigator: DMPNavigator?, isRoot: Bool = false
    ) {
        self.pagePath = pagePath
        self.query = query
        self.appConfig = appConfig
        self.app = app
        self.navigator = navigator
        self.isRoot = isRoot

        // Create WebView
        self.webview = (app?.render!.createWebView(appName: appConfig.appName))!

        super.init(nibName: nil, bundle: nil)

        // Configure WebView - Configure immediately to ensure page path is set correctly
        configWebView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Configure WebView
    private func configWebView() {        
        // Set page path and query parameters
        self.webview.setPagePath(pagePath: pagePath)
        if let query = query {
            self.webview.setQuery(query: query)
        }
        
        print("🔧 DMPPageController: WebView (ID: \(webview.getWebViewId())) configuration completed, current page path: \(webview.getPagePath())")
        
        webview.poolState = .loading
        webview.loadPageFrame()
    }

    // View loaded
    public override func viewDidLoad() {
        super.viewDidLoad()

        // 沉浸式全屏
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        // Set title
        self.title = appConfig.appName

        // Create SwiftUI view container
        let webViewContainer = DMPWebViewContainer(webview: webview, isRoot: isRoot)
        hostingController = UIHostingController(rootView: webViewContainer)

        // Add child view controller
        if let hostingController = hostingController {
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            hostingController.didMove(toParent: self)
        }

        // Set navigation bar style
        setupNavigationBar()

        // Add host app overlay (e.g., capsule button)
        if let overlay = app?.pageOverlayProvider?.overlayView(for: self, isRoot: isRoot) {
            view.addSubview(overlay)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.isUserInteractionEnabled = true
            NSLayoutConstraint.activate([
                overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0)
            ])
            self.overlayView = overlay
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 确保 overlay 始终在最上层，避免被 UIHostingController 的 view 遮挡
        if let overlay = overlayView {
            view.bringSubviewToFront(overlay)
        }
    }

    // View will appear
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupNavigationBar()

        // 沉浸式：WebView 延伸到安全区域外
        if let hostingController = hostingController {
            hostingController.view.insetsLayoutMarginsFromSafeArea = false
            if #available(iOS 16.4, *) {
                hostingController.safeAreaRegions = []
            }
        }
    }

    // View did appear
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // setupNavigationBar()
    }

    // Set navigation bar style
    private func setupNavigationBar() {
        navigationItem.hidesBackButton = true
        navigationItem.backButtonTitle = ""

        // 默认沉浸式，隐藏系统导航栏
        // TODO: 后续根据 app-config.json 的 navigationStyle 配置决定是否显示
        navigationController?.setNavigationBarHidden(true, animated: false)

        let navStyle = navigator?.getTopPageRecord()?.navStyle
        if let navStyle = navStyle {
            // Set title
            navigationItem.title = navStyle["navigationBarTitleText"] as? String
            navigationItem.backButtonTitle = navStyle["navigationBarTitleText"] as? String

            // Only set default style if navigationItem has not been customized
            // This ensures that styles set via API are not overridden
            if navigationItem.standardAppearance == nil,
                let backgroundColor = navStyle["navigationBarBackgroundColor"] as? String,
                let textStyle = navStyle["navigationBarTextStyle"] as? String
            {

                let darkStyle = textStyle == "white"

                if let navigator = navigator {
                    navigationItem.leftBarButtonItem = navigator.createBackButton(
                        darkStyle: darkStyle)
                }

                let bgColor = DMPUtil.colorFromHexString(backgroundColor) ?? .white
                let textColor: UIColor = darkStyle ? .white : .black

                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = bgColor
                appearance.titleTextAttributes = [.foregroundColor: textColor]

                // Set navigation bar appearance for the current controller
                navigationItem.standardAppearance = appearance
                navigationItem.scrollEdgeAppearance = appearance
                navigationItem.compactAppearance = appearance

                if #available(iOS 15.0, *) {
                    navigationItem.compactScrollEdgeAppearance = appearance
                }

                // Set navigation bar button color
                navigationController?.navigationBar.tintColor = textColor

                DMPUIManager.updateWindowStyle(isDarkTheme: darkStyle)
            }
        }

        navigationController?.navigationBar.setNeedsLayout()
        navigationController?.navigationBar.layoutIfNeeded()
    }

    // Back button tap event
    @objc private func backButtonTapped() {
        if let navigator = navigator {
            navigator.handleBackButtonTapped()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    // Get WebView instance
    public func getWebView() -> DMPWebview {
        return webview
    }

    // Get navigator instance (for overlay close/back actions)
    public func getNavigator() -> DMPNavigator? {
        return navigator
    }

    // Get app instance (for overlay destroy actions)
    public func getApp() -> DMPApp? {
        return app
    }

    // Called when page is shown
    public func onShow() {
        // Add your logic here
    }
    
    // MARK: - Lifecycle Methods
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Notify lifecycle management when page completely disappears
        if isMovingFromParent {
            // Page is removed from navigation stack
            destroyWebView()
        }
    }
    
    // Destroy WebView
    private func destroyWebView() {
        // Add state check to prevent duplicate destruction
        guard !isWebViewDestroyed else {
            print("🟡 DMPPageController: WebView (ID: \(webview.getWebViewId())) has already been destroyed, skipping duplicate operation")
            return
        }
        
        print("🗑️ DMPPageController: Destroy WebView (ID: \(webview.getWebViewId()))")
        isWebViewDestroyed = true
        
        // Notify page unload
        if let app = app {
            let msg = DMPMap([
                "type": "pageUnload",
                "body": [
                    "bridgeId": webview.getWebViewId()
                ]
            ])
            DMPChannelProxy.containerToService(msg: msg, app: app)
        }
        
        // Release WebView back to pool
        app?.render?.releaseWebView(webview)
    }
    
    // Manual destroy method (for external calls)
    public func destroy() {
        destroyWebView()
    }
    
    deinit {
        print("🗑️ DMPPageController: deinit (WebView ID: \(webview.getWebViewId()))")
        // Ensure WebView is correctly released
        destroyWebView()
    }
}

// SwiftUI view container for displaying WebView
public struct DMPWebViewContainer: View {
    @ObservedObject var webview: DMPWebview
    var isRoot: Bool = false

    public init(webview: DMPWebview, isRoot: Bool = false) {
        self.webview = webview
        self.isRoot = isRoot
    }

    public var body: some View {
        if #available(iOS 14.0, *) {
            ZStack {
                DMPWebview.WebViewRepresentable(webview: webview)
                
                if webview.isLoading && isRoot {
                    DMPLoadingView(appName: webview.appName)
                        .transition(.opacity)
                }
            }
            .onChange(of: webview.isLoading) { newValue in
                // WebView loading state changed
            }
        } else {
            // Fallback on earlier versions
        }
    }
}
