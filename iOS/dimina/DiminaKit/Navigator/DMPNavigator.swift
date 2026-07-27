//
//  DMPNavigator.swift
//  dimina
//
//  Created by Lehem on 2025/4/17.
//

import Foundation
import ObjectiveC
import SwiftUI
import UIKit

// 用于存储关联对象的键
private var navigatorAssociationKey: UInt8 = 0

/// DMPNavigator 是一个导航管理器，用于接管整个应用的导航动作
public class DMPNavigator: NSObject {
    // app 弱引用
    private weak var app: DMPApp?

    // 页面生命周期管理
    private lazy var pageLifecycle: DMPPageLifecycle? = DMPPageLifecycle(app: app!)

    // 当前的导航控制器
    public private(set) weak var navigationController: UINavigationController?

    // Dimina 与宿主共用 UINavigationController。保留宿主原始状态，
    // 小程序根页禁止侧滑，二级页开放侧滑，离开小程序后再恢复。
    private var hostInteractivePopGestureWasEnabled: Bool?

    // 页面记录
    private var pageRecords: [DMPPageRecord] = []

    // 公开初始化方法
    public init(app: DMPApp? = nil) {
        self.app = app
        super.init()
    }

    public func setup(navigationController: UINavigationController) {
        restoreHostInteractivePopGestureIfNeeded()
        self.navigationController = navigationController

        objc_setAssociatedObject(
            navigationController, &navigatorAssociationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        if let gesture = navigationController.interactivePopGestureRecognizer {
            hostInteractivePopGestureWasEnabled = gesture.isEnabled
            // launch 尚未建立第二个小程序页面，先按根页语义禁止。
            gesture.isEnabled = false
        }
    }

    /// 创建自定义返回按钮
    public func createBackButton(darkStyle: Bool = false) -> UIBarButtonItem {
        if let bundle = DMPResourceManager.assetsBundle {
            let imageName = darkStyle ? "arrow-back-dark" : "arrow-back-light"
            if let backImage = UIImage(named: imageName, in: bundle, compatibleWith: nil) {
                let originalImage = backImage.withRenderingMode(.alwaysOriginal)
                return UIBarButtonItem(
                    image: originalImage, style: .plain, target: self,
                    action: #selector(handleBackButtonTapped))
            }
        }

        return UIBarButtonItem(
            title: "back",
            style: .plain,
            target: self,
            action: #selector(handleBackButtonTapped)
        )
    }

    /// 处理返回按钮点击事件
    @objc public func handleBackButtonTapped() {
        // 确保在主线程上调用 navigateBack
        DispatchQueue.main.async { [weak self] in
            self?.navigateBack()
        }
    }

    /// 启动到指定页面。如果 path 是 app-config.json tabBar.list 里的页面，
    /// 创建 DMPTabBarContainerController（持有所有 tab pages）作为根；否则直接推 DMPPageController。
    @MainActor
    public func launch(to path: String, query: [String: Any]? = nil, animated: Bool = true) async {
        DMPLog.app.info("DMPNavigator launch path=\(path) navController=\(navigationController != nil)")
        guard let navigationController = navigationController else {
            DMPLog.app.error("DMPNavigator launch: navigationController not set or released")
            return
        }
        DMPLog.app.debug("nav stack before push: \(navigationController.viewControllers.map { String(describing: type(of: $0)) })")

        pageLifecycle?.onHide(webviewId: app!.getCurrentWebViewId())

        // 检查是否为 tab 页面 → 走容器路径
        let tabBarConfig = app?.getBundleAppConfig()?.tabBar
        let isTabPage = tabBarConfig?.contains(pagePath: path) ?? false

        let rootController: UIViewController
        let firstPageController: DMPPageController

        if isTabPage, let tabBarConfig = tabBarConfig, let app = app {
            let container = DMPTabBarContainerController(
                tabBarConfig: tabBarConfig,
                initialPagePath: path,
                query: query,
                app: app,
                navigator: self
            )
            rootController = container
            firstPageController = container.currentPageController!  // 一定存在：构造时已 init pageControllers
            DMPLog.app.info("launch: tab page → DMPTabBarContainerController with \(container.pageControllers.count) tabs, initial=\(path)")
        } else {
            firstPageController = DMPPageController(
                pagePath: path,
                query: query,
                appConfig: app!.getAppConfig()!,
                app: app,
                navigator: self,
                isRoot: true
            )
            rootController = firstPageController
        }

        let pageRecord = DMPPageRecord(
            webViewId: firstPageController.getWebView().getWebViewId(),
            fromWebViewId: app!.getCurrentWebViewId(), pagePath: path)
        pageRecord.query = query
        pageRecord.navStyle = app?.getBundleAppConfig()?.getPageConfig(pagePath: path)
        pageRecords.append(pageRecord)

        await app?.service?.loadSubPackage(pagePath: path)

        // setViewControllers 代替 push（避免转场动画时 push 被静默忽略）
        var viewControllers = navigationController.viewControllers
        viewControllers.append(rootController)
        navigationController.setViewControllers(viewControllers, animated: animated)
        DMPLog.app.debug("nav stack after launch: \(navigationController.viewControllers.map { String(describing: type(of: $0)) })")

        pageLifecycle?.onShow(webviewId: firstPageController.getWebView().getWebViewId())
    }

    /// 切到指定 tab 页面。栈里必须有 DMPTabBarContainerController。
    @MainActor
    public func switchTab(to path: String) -> Bool {
        guard let navigationController = navigationController else { return false }
        guard let container = navigationController.viewControllers.compactMap({ $0 as? DMPTabBarContainerController }).first else {
            DMPLog.app.warn("switchTab failed: no DMPTabBarContainerController in nav stack (path=\(path))")
            return false
        }
        guard let index = container.tabBarConfig.index(of: path) else {
            DMPLog.app.warn("switchTab failed: '\(path)' not in tabBar.list")
            return false
        }

        let oldWebViewId = container.currentPageController?.getWebView().getWebViewId() ?? -1
        pageLifecycle?.onHide(webviewId: oldWebViewId)
        container.switchTo(index: index)
        let newWebViewId = container.currentPageController?.getWebView().getWebViewId() ?? -1
        pageLifecycle?.onShow(webviewId: newWebViewId)
        return true
    }

    /// 导航到指定页面
    @MainActor
    public func navigateTo(to path: String, query: [String: Any]? = nil, animated: Bool = true)
        async
    {
        guard let navigationController = navigationController else {
            print("导航控制器未设置")
            return
        }

        pageLifecycle?.onHide(webviewId: app!.getCurrentWebViewId())

        // 使用DMPPageController创建页面
        let pageController = DMPPageController(
            pagePath: path,
            query: query,
            appConfig: app!.getAppConfig()!,
            app: app,
            navigator: self,
            isRoot: false
        )

        let pageRecord = DMPPageRecord(
            webViewId: pageController.getWebView().getWebViewId(),
            fromWebViewId: app!.getCurrentWebViewId(), pagePath: path)
        pageRecord.query = query
        pageRecord.navStyle = app?.getBundleAppConfig()?.getPageConfig(pagePath: path)
        pageRecords.append(pageRecord)

        // 打印调试信息
        print("navigateTo: Creating page controller for path: \(path), isRoot: false")

        await app?.service?.loadSubPackage(pagePath: path)

        // 推入视图控制器
        navigationController.pushViewController(pageController, animated: animated)

        pageLifecycle?.onShow(webviewId: pageController.getWebView().getWebViewId())
    }

    /// 返回上一页或多页
    @MainActor
    public func navigateBack(delta: Int = 1, animated: Bool = true, destroy: Bool = true) {
        guard let navigationController = navigationController else {
            print("导航控制器未设置")
            return
        }

        // 检查是否可以返回
        if navigationController.viewControllers.count <= 1 {
            if destroy {
                app?.destroy()
            }
            return
        }

        // 计算要返回的目标控制器索引
        let currentIndex = navigationController.viewControllers.count - 1
        let targetIndex = max(currentIndex - delta, 0)

        // 如果目标是根控制器，直接返回到根
        if targetIndex == 0 {
            pageLifecycle?.onUnload(webviewId: app!.getCurrentWebViewId())
            pageRecords.removeAll()
            navigationController.popToRootViewController(animated: animated)
            return
        }

        // 处理返回逻辑
        for _ in 0..<delta {
            if navigationController.viewControllers.count <= 1 || pageRecords.isEmpty {
                break
            }

            pageLifecycle?.onUnload(webviewId: app!.getCurrentWebViewId())
            pageRecords.removeLast()
        }

        // 返回到目标控制器
        let targetViewController = navigationController.viewControllers[targetIndex]
        navigationController.popToViewController(targetViewController, animated: animated)

        // 显示前一个页面
        if let previousPageRecord = pageRecords.last {
            pageLifecycle?.onShow(webviewId: previousPageRecord.webViewId)
        }
    }

    @MainActor
    public func redirectTo(to path: String, query: [String: Any]? = nil) async {
        guard let navigationController = navigationController else {
            print("导航控制器未设置")
            return
        }

        let currentIndex = navigationController.viewControllers.count - 1
        let isReplacingRootPage = pageRecords.count <= 1

        // 如果当前只有一个页面，则需要特殊处理
        if currentIndex == 0 {
            pageLifecycle?.onUnload(webviewId: app!.getCurrentWebViewId())

            if !pageRecords.isEmpty {
                pageRecords.removeLast()
            }

            let pageController = DMPPageController(
                pagePath: path,
                query: query,
                appConfig: app!.getAppConfig()!,
                app: app,
                navigator: self,
                isRoot: true
            )

            let pageRecord = DMPPageRecord(
                webViewId: pageController.getWebView().getWebViewId(),
                fromWebViewId: app!.getCurrentWebViewId(), pagePath: path)
            pageRecord.query = query
            pageRecord.navStyle = app?.getBundleAppConfig()?.getPageConfig(pagePath: path)
            pageRecords.append(pageRecord)

            await app?.service?.loadSubPackage(pagePath: path)

            let viewControllers = [pageController]
            navigationController.setViewControllers(viewControllers, animated: false)

            pageLifecycle?.onShow(webviewId: pageController.getWebView().getWebViewId())

            return
        }

        // 先触发当前页面的卸载生命周期
        pageLifecycle?.onUnload(webviewId: app!.getCurrentWebViewId())

        if !pageRecords.isEmpty {
            pageRecords.removeLast()
        }

        let pageController = DMPPageController(
            pagePath: path,
            query: query,
            appConfig: app!.getAppConfig()!,
            app: app,
            navigator: self,
            isRoot: isReplacingRootPage
        )

        let pageRecord = DMPPageRecord(
            webViewId: pageController.getWebView().getWebViewId(),
            fromWebViewId: app!.getCurrentWebViewId(), pagePath: path)
        pageRecord.query = query
        pageRecord.navStyle = app?.getBundleAppConfig()?.getPageConfig(pagePath: path)
        pageRecords.append(pageRecord)

        var viewControllers = navigationController.viewControllers
        viewControllers.removeLast()
        viewControllers.append(pageController)
        navigationController.setViewControllers(viewControllers, animated: false)
        pageLifecycle?.onShow(webviewId: pageController.getWebView().getWebViewId())
    }

    @MainActor
    public func relaunch(to path: String, query: [String: Any]? = nil, animated: Bool = true) async
    {
        guard let navigationController = navigationController else {
            print("导航控制器未设置")
            return
        }

        navigationController.popToRootViewController(animated: animated)
        pageRecords.removeAll()

        await launch(to: path, query: query, animated: animated)
    }

    /// 返回到根页面
    private func goBackToRoot(animated: Bool = true) {
        guard let navigationController = navigationController else {
            print("导航控制器未设置")
            return
        }

        navigationController.popToRootViewController(animated: animated)
        pageRecords.removeAll()
    }

    /// 当前页面栈深度
    public var pageCount: Int {
        return pageRecords.count
    }

    /// 获取当前页面记录
    public func getTopPageRecord() -> DMPPageRecord? {
        return pageRecords.last
    }

    /// Returns the page that is actually visible. A tab container owns its
    /// page controller as a child, so `topViewController` alone is not enough.
    @MainActor
    public func getCurrentPageController() -> DMPPageController? {
        if let container = navigationController?.topViewController as? DMPTabBarContainerController {
            return container.currentPageController
        }
        return navigationController?.topViewController as? DMPPageController
    }

    /// The route currently visible to the developer. Inspect only the top view
    /// controller: a tab container may still exist lower in the stack while a
    /// detail page is visible above it.
    func getCurrentRoute() -> (path: String, query: [String: Any]?)? {
        if let container = navigationController?.topViewController
            as? DMPTabBarContainerController,
           let webview = container.currentPageController?.getWebView() {
            return (webview.getPagePath(), webview.getQuery())
        }
        if let pageController = navigationController?.topViewController as? DMPPageController {
            let webview = pageController.getWebView()
            return (webview.getPagePath(), webview.getQuery())
        }
        guard let record = pageRecords.last else { return nil }
        return (record.pagePath, record.query)
    }

    /// 给外部容器（如 DMPTabBarContainerController）追加 pageRecord 用。
    public func appendPageRecord(_ record: DMPPageRecord) {
        pageRecords.append(record)
    }
}

// MARK: - Interactive pop gesture

extension DMPNavigator {

    /// Restores the gesture state owned by the host navigation controller.
    /// Safe to call repeatedly, including from `DMPApp.destroy()`.
    public func tearDownNavigation() {
        let restore = { [weak self] in
            guard let self else { return }
            self.restoreHostInteractivePopGestureIfNeeded()
            self.navigationController = nil
        }

        if Thread.isMainThread {
            restore()
        } else {
            DispatchQueue.main.async(execute: restore)
        }
    }

    /// Called after a mini-program page becomes the actually visible controller.
    /// Root pages must not swipe into the host stack; pushed pages use UIKit's
    /// interactive pop transition. The captured host state is only for restoration.
    @MainActor
    func pageControllerDidAppear(_ pageController: DMPPageController) {
        guard getCurrentPageController() === pageController,
              let gesture = navigationController?.interactivePopGestureRecognizer else {
            return
        }
        gesture.isEnabled = !pageController.isMiniProgramRoot
    }

    /// Keeps host pages from inheriting the root mini-program's disabled gesture.
    @MainActor
    func pageControllerDidDisappear(_ pageController: DMPPageController) {
        guard getCurrentPageController() !== pageController else {
            return
        }
        guard let topViewController = navigationController?.topViewController,
              !(topViewController is DMPPageController),
              !(topViewController is DMPTabBarContainerController) else {
            return
        }
        applyHostInteractivePopGestureState()
    }

    /// UIKit owns the visual interactive transition. Once it really completes,
    /// reconcile Dimina's logical stack and page lifecycle with the popped VC.
    /// A cancelled gesture never reaches this method.
    @MainActor
    func didCompleteInteractivePop(webViewId: Int) {
        guard let poppedIndex = pageRecords.lastIndex(where: { $0.webViewId == webViewId }) else {
            updateInteractivePopGestureForVisiblePage()
            return
        }

        pageRecords.removeSubrange(poppedIndex...)
        if let visiblePageRecord = pageRecords.last {
            pageLifecycle?.onShow(webviewId: visiblePageRecord.webViewId)
        }
        updateInteractivePopGestureForVisiblePage()
    }

    @MainActor
    private func updateInteractivePopGestureForVisiblePage() {
        guard let pageController = getCurrentPageController() else {
            applyHostInteractivePopGestureState()
            return
        }
        pageControllerDidAppear(pageController)
    }

    private func applyHostInteractivePopGestureState() {
        guard let gesture = navigationController?.interactivePopGestureRecognizer,
              let wasEnabled = hostInteractivePopGestureWasEnabled else {
            return
        }
        gesture.isEnabled = wasEnabled
    }

    private func restoreHostInteractivePopGestureIfNeeded() {
        guard let navigationController else {
            hostInteractivePopGestureWasEnabled = nil
            return
        }

        applyHostInteractivePopGestureState()
        if let associatedNavigator = objc_getAssociatedObject(
            navigationController,
            &navigatorAssociationKey
        ) as? DMPNavigator,
           associatedNavigator === self {
            objc_setAssociatedObject(
                navigationController,
                &navigatorAssociationKey,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
        hostInteractivePopGestureWasEnabled = nil
    }
}
