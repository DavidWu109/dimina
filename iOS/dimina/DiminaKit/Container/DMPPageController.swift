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
    public private(set) weak var overlayView: UIView?

    // WebView related
    private var webview: DMPWebview
    private var hostingController: UIHostingController<DMPWebViewContainer>?

    // State
    private var isWebViewDestroyed = false
    /// 防止 loadPageFrame 被重复触发。
    /// isRoot 路径在 configWebView 里立刻置 true；非 root 路径等到 viewDidAppear 第一次再 load。
    private var hasLoadedPageFrame = false

    /// tab 页面由 DMPTabBarContainerController 容器作为 child VC 持有时不为 nil。
    /// 用于判断这个 page 是「容器里的 tab child」还是「独立 push 的 page」。
    public var isEmbeddedInTabBarContainer: Bool {
        return parent is DMPTabBarContainerController
    }

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

        // isRoot=true (tab 容器子页 / launch 根页): eager load —— 这条路径 WebView
        // 一上来就拿到稳定 frame，没观察到 zero-frame race
        // isRoot=false (navigateTo push 进来): 延迟到 viewDidAppear 才 load，避开
        // push 动画期间 WKWebView frame=0 导致 pageFrame.js 不 fire renderResourceLoaded 的 race
        // 详见 dimina/docs/Push-Page-Memory-Model.md
        if isRoot {
            hasLoadedPageFrame = true
            loadPageFrameAndWatchdog()
        }
    }

    /// 真正调 loadPageFrame + 挂 watchdog 兜底"didFinishLoad 来了但 render pipeline 卡死、
    /// renderResourceLoaded 永远不发"这种 case（上游 sharedProcessPool 设计的副作用，详见
    /// dimina/docs/Push-Page-Memory-Model.md L2 那段）。
    /// 3s 后没 allLoaded → warn + reset poolState + 再 loadPageFrame() 一次
    ///   （poolState reset 是必须的：DMPRender.webViewDidFinishLoad 里有 `poolState != .loading
    ///    → skip resource loading` 的短路，第一次 load 完已经把 poolState 改成 .ready，不 reset
    ///    的话 retry 会被该短路吞掉等于空操作）
    /// 6s 后还没 allLoaded → error，认输；这种 case WebKit 的 WebContent process 真的进了死状态，
    /// reload 也救不回来，需要用户 back 重 push（或者上 L3 完全重建 WebView，未实施）
    private func loadPageFrameAndWatchdog() {
        let id = webview.getWebViewId()
        webview.loadPageFrame()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, !self.isWebViewDestroyed else { return }
            if self.app?.container?.isResourceLoaded(webViewId: id) == true { return }
            DMPLog.render.warn("⚠️ render watchdog: bridgeId=\(id) pagePath=\(self.pagePath) not allLoaded after 3s — reset poolState + retry loadPageFrame")
            self.webview.poolState = .loading
            self.webview.loadPageFrame()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, !self.isWebViewDestroyed else { return }
                if self.app?.container?.isResourceLoaded(webViewId: id) == true { return }
                DMPLog.render.error("⚠️⚠️ render watchdog: bridgeId=\(id) pagePath=\(self.pagePath) STILL not allLoaded after 6s — giving up (likely WKProcessPool content process stuck, user must back+retry; L3 full WebView recreate not yet implemented)")
            }
        }
    }

    // View loaded
    public override func viewDidLoad() {
        super.viewDidLoad()

        // Set title
        self.title = appConfig.appName

        // 根据 navigationStyle 选 WebView 顶部约束：custom 沉浸式覆盖到屏顶；default 在 navBar 下方
        let pageConfig = app?.getBundleAppConfig()?.getPageConfig(pagePath: pagePath)
        let isImmersive = (pageConfig?["navigationStyle"] as? String) == "custom"
        if isImmersive {
            edgesForExtendedLayout = .all
            extendedLayoutIncludesOpaqueBars = true
        } else {
            edgesForExtendedLayout = []
        }

        // Create SwiftUI view container
        let webViewContainer = DMPWebViewContainer(webview: webview, isRoot: isRoot)
        hostingController = UIHostingController(rootView: webViewContainer)

        if let hostingController = hostingController {
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false

            let topAnchor: NSLayoutYAxisAnchor = isImmersive
                ? view.topAnchor
                : view.safeAreaLayoutGuide.topAnchor
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            hostingController.didMove(toParent: self)
        }

        installOverlay(isImmersive: isImmersive)

        // Set navigation bar style
        applyNavigationStyleToSelfNavigationItem()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 沉浸式才有自己挂的 subview overlay，保证置顶
        if let overlay = overlayView {
            view.bringSubviewToFront(overlay)
        }
    }

    // View will appear
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 嵌入容器时由容器同步 navigationItem，单独 push 时自己来
        if !isEmbeddedInTabBarContainer {
            applyNavigationStyleToSelfNavigationItem()
        }

        // 沉浸式：WebView 延伸到安全区域外
        let pageConfig = app?.getBundleAppConfig()?.getPageConfig(pagePath: pagePath)
        let isImmersive = (pageConfig?["navigationStyle"] as? String) == "custom"
        if isImmersive, let hostingController = hostingController {
            hostingController.view.insetsLayoutMarginsFromSafeArea = false
            if #available(iOS 16.4, *) {
                hostingController.safeAreaRegions = []
            }
        }
    }

    /// 把宿主提供的胶囊 overlay 安置到合适位置：
    ///   - 沉浸式（custom）：作为 self.view 子 view 浮在 view.safeArea.top（屏顶之下）
    ///   - 普通（default）：作为 navigationItem.rightBarButtonItem 嵌在 nav bar 右侧
    private func installOverlay(isImmersive: Bool) {
        guard let overlay = app?.pageOverlayProvider?.overlayView(for: self, isRoot: isRoot) else { return }
        overlay.isUserInteractionEnabled = true

        if isImmersive {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0)
            ])
            self.overlayView = overlay
        } else {
            // navigation bar 右侧。removeFromSuperview 一下避免它残留在某个旧 view 树里
            overlay.removeFromSuperview()
            overlay.translatesAutoresizingMaskIntoConstraints = true
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: overlay)
        }
    }

    // View did appear
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // 诊断：viewDidAppear 时 self / hosting / WKWebView 的实际 frame。
        // 留着方便后续观察 zero-height 救援的触发频率，以及万一别的页面又踩 race 时定位。
        let wkView = webview.getWebView()
        let hostFrame = hostingController?.view.frame ?? .zero
        DMPLog.app.info("viewDidAppear id=\(webview.getWebViewId()) isRoot=\(isRoot) parent=\(String(describing: type(of: parent))) hasLoaded=\(hasLoadedPageFrame) self.frame=\(view.frame) self.bounds=\(view.bounds) host.frame=\(hostFrame) wkView.frame=\(wkView.frame) wkView.window=\(wkView.window != nil)")

        // 非 root（navigateTo push）首次 appear 时才启动 pageFrame 加载，等 push 动画完、view 在 window 里、frame 稳定
        // 详见 dimina/docs/Push-Page-Memory-Model.md
        guard !hasLoadedPageFrame else { return }

        // zero-height guard：iOS 15+ WKWebView 已知 race —— viewDidAppear 偶发在 layout 完全 settle 前 fire，
        // 此时 self.view.bounds.height 仍是 0。立刻 loadPageFrame 会让 WebKit 在 0-frame 下不初始化 render
        // pipeline，pageFrame.js 跑不出 invoke(renderResourceLoaded) → 永久白屏。
        // 救援：检测到 0 时 warn 一下，挂 300ms async，等下一轮 layout 后再 load。
        // 实测保留 viewDidAppear 里读 frame 的诊断日志后这条 race 频率显著下降，可能 KVO/access 副作用 trigger 了
        // 一次 layout；但不能依赖那个副作用，必须显式 guard。
        if view.bounds.height > 0 {
            hasLoadedPageFrame = true
            DMPLog.render.info("deferred loadPageFrame id=\(webview.getWebViewId()) pagePath=\(pagePath) (push path, height=\(view.bounds.height))")
            loadPageFrameAndWatchdog()
        } else {
            DMPLog.render.warn("⚠️ viewDidAppear with ZERO height id=\(webview.getWebViewId()) pagePath=\(pagePath) — deferring loadPageFrame by 300ms (zero-frame race recovery)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self, !self.hasLoadedPageFrame else { return }
                self.hasLoadedPageFrame = true
                let h = self.view.bounds.height
                DMPLog.render.info("recovery loadPageFrame id=\(self.webview.getWebViewId()) pagePath=\(self.pagePath) (after 300ms, height=\(h))")
                self.loadPageFrameAndWatchdog()
            }
        }
    }

    /// 把当前 page 的 navigationBar 配置（标题、背景色、文字颜色等）写到 self.navigationItem。
    /// 同时同步 navigationController.setNavigationBarHidden（依据 navigationStyle）。
    /// 公开是为了让 DMPTabBarContainerController 取一次 child 的配置后复制到容器的 navigationItem。
    public func applyNavigationStyleToSelfNavigationItem() {
        navigationItem.hidesBackButton = true
        navigationItem.backButtonTitle = ""

        // 优先用 navigator 维护的 pageRecord（运行时可能被 setNavigationBarColor API 改过），
        // 不可用时回退到 bundleAppConfig 的页面静态配置。
        let navStyle = navigator?.getTopPageRecord()?.navStyle
            ?? app?.getBundleAppConfig()?.getPageConfig(pagePath: pagePath)

        // navigationStyle: "default" (默认) 显示系统导航栏；"custom" 沉浸式隐藏，由 mini-app 自绘
        let navigationStyle = (navStyle?["navigationStyle"] as? String) ?? "default"
        let shouldHide = navigationStyle == "custom"
        navigationController?.setNavigationBarHidden(shouldHide, animated: false)

        guard let navStyle = navStyle, !shouldHide else { return }

        navigationItem.title = navStyle["navigationBarTitleText"] as? String
        navigationItem.backButtonTitle = navStyle["navigationBarTitleText"] as? String

        // 由 API setNavigationBarColor 设置过 appearance 则不覆盖
        guard navigationItem.standardAppearance == nil,
              let backgroundColor = navStyle["navigationBarBackgroundColor"] as? String,
              let textStyle = navStyle["navigationBarTextStyle"] as? String else {
            navigationController?.navigationBar.setNeedsLayout()
            navigationController?.navigationBar.layoutIfNeeded()
            return
        }

        let darkStyle = textStyle == "white"
        if let navigator = navigator, !isRoot {
            navigationItem.leftBarButtonItem = navigator.createBackButton(darkStyle: darkStyle)
        }

        let bgColor = DMPUtil.colorFromHexString(backgroundColor) ?? .white
        let textColor: UIColor = darkStyle ? .white : .black

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bgColor
        appearance.titleTextAttributes = [.foregroundColor: textColor]

        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationItem.compactScrollEdgeAppearance = appearance
        }

        navigationController?.navigationBar.tintColor = textColor
        DMPUIManager.updateWindowStyle(isDarkTheme: darkStyle)

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
