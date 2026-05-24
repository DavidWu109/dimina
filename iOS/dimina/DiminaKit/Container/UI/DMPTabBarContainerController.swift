//
//  DMPTabBarContainerController.swift
//  dimina
//
//  自定义 tabBar 容器 VC，给 mini-app 提供「多个 tab 页面 + 底部 tabBar」的根容器。
//
//  视图复用走标准 UIKit 内存管理（attach/detach），跟 navigateTo push page 一套机制：
//  - 每个 tab 的 DMPPageController 首次访问时 lazy 创建并永久 addChild 进容器
//  - 切 tab = 旧 tab.view.removeFromSuperview() + 新 tab attach 到 currentChildContainer
//  - 永不 removeFromParent（会触发 DMPPageController.viewDidDisappear 的 isMovingFromParent
//    分支去 destroyWebView，把 WebView 还池子，等于摧毁了 tab 状态）
//  - 容器自身从 nav stack 弹出时统一 deinit，children deinit 触发各 tab 的 destroyWebView
//
//  完整设计说明 / 快速点击下的边界行为 / 跟上游 didi/dimina alive-but-hidden 方案的对比，
//  见 dimina/docs/TabBar-Memory-Model.md
//

import Foundation
import UIKit

public class DMPTabBarContainerController: UIViewController {

    public let tabBarConfig: DMPTabBarConfig
    /// 按 index 存储 tab page controllers。初始全 nil；首次切到该 tab 时 lazy 创建并 addChild，
    /// 之后永久保留（即使 view 被 detach 出视图层级，VC 实例和它持有的 WebView 仍在）。
    /// lazy 是为了不破坏 mini-app service worker「一次只激活一个 page」的并发假设。
    public private(set) var pageControllers: [DMPPageController?]
    public private(set) var selectedIndex: Int = 0
    public private(set) var tabBarView: DMPTabBarView!

    private let initialQuery: [String: Any]?
    private weak var app: DMPApp?
    private weak var navigator: DMPNavigator?
    private var currentChildContainer: UIView!

    public init(
        tabBarConfig: DMPTabBarConfig,
        initialPagePath: String,
        query: [String: Any]?,
        app: DMPApp,
        navigator: DMPNavigator
    ) {
        self.tabBarConfig = tabBarConfig
        self.app = app
        self.navigator = navigator
        self.initialQuery = query
        self.pageControllers = Array(repeating: nil, count: tabBarConfig.list.count)
        self.selectedIndex = tabBarConfig.index(of: initialPagePath) ?? 0
        super.init(nibName: nil, bundle: nil)

        // 立即构造初始 tab 的 page controller（含 addChild）；其余 lazy。
        // view 还没创建，attach 到 currentChildContainer 留到 viewDidLoad。
        _ = ensurePageController(at: selectedIndex, query: query)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // 1. 底部 tabBar
        tabBarView = DMPTabBarView(
            config: tabBarConfig,
            appId: app?.getAppId() ?? "",
            versionCode: app?.getAppConfig()?.versionCode
        )
        tabBarView.delegate = self
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBarView)
        NSLayoutConstraint.activate([
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 2. 当前 child 的容器（tabBar 之上）
        currentChildContainer = UIView()
        currentChildContainer.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(currentChildContainer, belowSubview: tabBarView)
        NSLayoutConstraint.activate([
            currentChildContainer.topAnchor.constraint(equalTo: view.topAnchor),
            currentChildContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            currentChildContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            currentChildContainer.bottomAnchor.constraint(equalTo: tabBarView.topAnchor),
        ])

        // 3. attach 初始 tab 的 view（其他 tab 切到时再 attach）
        if let initialPC = pageControllers[selectedIndex] {
            attachChildView(initialPC)
        }

        tabBarView.setSelected(pagePath: tabBarConfig.list[selectedIndex].pagePath)
        syncNavigationItemFromCurrentChild()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncNavigationItemFromCurrentChild()
    }

    /// 切到指定 tab。lazy 创建未初始化的 page controller，已创建的复用（保留状态）。
    ///
    /// 切换语义：旧 tab.view 从视图层级 detach，新 tab.view attach 到 currentChildContainer。
    /// 旧 tab 的 WebView window=nil → WebKit 干净 suspend；reattach 时 resume。
    /// 跟 UINavigationController.pushViewController 之后旧 VC 的 view 被 detach 是同一套机制。
    @MainActor
    public func switchTo(index: Int, animated: Bool = false) {
        guard index >= 0, index < pageControllers.count else { return }
        guard index != selectedIndex else { return }
        DMPLog.app.info("tabBar switch \(selectedIndex)→\(index) pagePath=\(tabBarConfig.list[index].pagePath)")

        let oldPC = pageControllers[selectedIndex]
        guard let newPC = ensurePageController(at: index, query: nil) else { return }

        // detach 旧 tab 的 view；VC 仍是 child（保留 WebView + JS 状态）
        oldPC?.view.removeFromSuperview()
        // attach 新 tab 的 view
        attachChildView(newPC)

        selectedIndex = index
        tabBarView.setSelected(pagePath: tabBarConfig.list[index].pagePath)
        syncNavigationItemFromCurrentChild()
    }

    /// 当前选中的 child VC。
    public var currentPageController: DMPPageController? {
        guard pageControllers.indices.contains(selectedIndex) else { return nil }
        return pageControllers[selectedIndex]
    }

    /// 拿（或 lazy 创建）指定 index 的 DMPPageController。
    /// 创建时同步 `addChild` + `didMove(toParent: self)`，之后 永不 `removeFromParent`。
    @discardableResult
    private func ensurePageController(at index: Int, query: [String: Any]?) -> DMPPageController? {
        guard index >= 0, index < pageControllers.count else { return nil }
        if let existing = pageControllers[index] { return existing }
        guard let app = app, let appConfig = app.getAppConfig() else { return nil }
        let item = tabBarConfig.list[index]
        let pc = DMPPageController(
            pagePath: item.pagePath,
            query: query,
            appConfig: appConfig,
            app: app,
            navigator: navigator,
            isRoot: true
        )
        // 同步 pageRecord（让 navigator.getTopPageRecord() 等 API 找得到该 webView 对应的记录）
        let pageRecord = DMPPageRecord(
            webViewId: pc.getWebView().getWebViewId(),
            fromWebViewId: -1,
            pagePath: item.pagePath
        )
        pageRecord.navStyle = app.getBundleAppConfig()?.getPageConfig(pagePath: item.pagePath)
        navigator?.appendPageRecord(pageRecord)

        // 永久建立 parent-child 关系（view 还没 attach，留给调用方）
        addChild(pc)
        pc.didMove(toParent: self)

        pageControllers[index] = pc
        return pc
    }

    // MARK: - Private

    /// 把 child 的 view 加入 currentChildContainer。如果它已经在其他 superview 下（理论不该有），
    /// 先 remove。constraints 在 removeFromSuperview 时自动失效，每次 attach 都重新激活。
    private func attachChildView(_ child: DMPPageController) {
        if child.view.superview != nil {
            child.view.removeFromSuperview()
        }
        currentChildContainer.addSubview(child.view)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: currentChildContainer.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: currentChildContainer.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: currentChildContainer.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: currentChildContainer.bottomAnchor),
        ])
    }

    /// 容器自身的 navigationItem 跟随当前 child（标题、appearance、rightBarButtonItem）。
    /// 系统 UINavigationBar 读 topViewController.navigationItem，而我们的 child 不在 nav 栈顶，
    /// 所以必须把 child 配好的 navigationItem 复制到 self.
    private func syncNavigationItemFromCurrentChild() {
        guard let child = currentPageController else { return }
        // 让 child 把它自己 navigationItem 配好（标题/颜色/leftBackButton/etc）
        child.applyNavigationStyleToSelfNavigationItem()

        navigationItem.title = child.navigationItem.title
        navigationItem.standardAppearance = child.navigationItem.standardAppearance
        navigationItem.scrollEdgeAppearance = child.navigationItem.scrollEdgeAppearance
        navigationItem.compactAppearance = child.navigationItem.compactAppearance
        if #available(iOS 15.0, *) {
            navigationItem.compactScrollEdgeAppearance = child.navigationItem.compactScrollEdgeAppearance
        }
        // tabBar 容器是 isRoot=true 入栈，不要 back button
        navigationItem.leftBarButtonItem = nil
        navigationItem.hidesBackButton = true
        navigationItem.rightBarButtonItem = child.navigationItem.rightBarButtonItem

        // hidesBar 由 child 在 applyNavigationStyleToSelfNavigationItem 里同步过 nav controller 了
    }
}

// MARK: - TabBar delegate

extension DMPTabBarContainerController: DMPTabBarViewDelegate {
    public func tabBarView(_ tabBarView: DMPTabBarView, didSelectIndex index: Int, item: DMPTabBarItem) {
        Task { @MainActor in
            switchTo(index: index, animated: false)
        }
    }
}
