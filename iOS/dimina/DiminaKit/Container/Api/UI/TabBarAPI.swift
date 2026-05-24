//
//  TabBarAPI.swift
//  dimina
//
//  TabBar API: setTabBarStyle / setTabBarItem / showTabBar / hideTabBar /
//  setTabBarBadge / removeTabBarBadge / showTabBarRedDot / hideTabBarRedDot
//

import Foundation

public class TabBarAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("setTabBarStyle", handler: setTabBarStyle)
        register("setTabBarItem", handler: setTabBarItem)
        register("showTabBar", handler: showTabBar)
        register("hideTabBar", handler: hideTabBar)
        register("setTabBarBadge", handler: setTabBarBadge)
        register("removeTabBarBadge", handler: removeTabBarBadge)
        register("showTabBarRedDot", handler: showTabBarRedDot)
        register("hideTabBarRedDot", handler: hideTabBarRedDot)
    }

    private func setTabBarStyle(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let p = param.getMap()
        guard let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex),
              let bundleConfig = app.getBundleAppConfig(),
              var tabBarConfig = bundleConfig.tabBar
        else {
            TabBarAPI.fail(callback, "setTabBarStyle", "tabBar not configured")
            return DMPAsyncResult()
        }

        let color = p.getString(key: "color")
        let selectedColor = p.getString(key: "selectedColor")
        let backgroundColor = p.getString(key: "backgroundColor")
        let borderStyle = p.getString(key: "borderStyle")

        tabBarConfig.color = color ?? tabBarConfig.color
        tabBarConfig.selectedColor = selectedColor ?? tabBarConfig.selectedColor
        tabBarConfig.backgroundColor = backgroundColor ?? tabBarConfig.backgroundColor
        if borderStyle == "black" || borderStyle == "white" {
            tabBarConfig.borderStyle = borderStyle!
        }
        bundleConfig.tabBar = tabBarConfig

        DispatchQueue.main.async {
            TabBarAPI.currentContainer(app: app)?.setTabBarStyle(
                color: color, selectedColor: selectedColor,
                backgroundColor: backgroundColor, borderStyle: borderStyle
            )
            TabBarAPI.success(callback, "setTabBarStyle")
        }
        return DMPAsyncResult()
    }

    private func setTabBarItem(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let p = param.getMap()
        guard let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex),
              let bundleConfig = app.getBundleAppConfig(),
              let tabBarConfig = bundleConfig.tabBar
        else {
            TabBarAPI.fail(callback, "setTabBarItem", "tabBar not configured")
            return DMPAsyncResult()
        }

        let index = TabBarAPI.intFromParam(p.get("index"))
        guard index >= 0, index < tabBarConfig.list.count else {
            TabBarAPI.fail(callback, "setTabBarItem", "invalid index \(index)")
            return DMPAsyncResult()
        }

        let text = p.getString(key: "text")
        let iconPath = p.getString(key: "iconPath")
        let selectedIconPath = p.getString(key: "selectedIconPath")

        var item = tabBarConfig.list[index]
        if let t = text { item.text = t }
        if let i = iconPath { item.iconPath = i }
        if let s = selectedIconPath { item.selectedIconPath = s }
        tabBarConfig.list[index] = item

        DispatchQueue.main.async {
            TabBarAPI.currentContainer(app: app)?.setTabBarItem(
                index: index, text: text, iconPath: iconPath, selectedIconPath: selectedIconPath
            )
            TabBarAPI.success(callback, "setTabBarItem")
        }
        return DMPAsyncResult()
    }

    private func showTabBar(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)
        DispatchQueue.main.async {
            TabBarAPI.currentContainer(app: app)?.setTabBarVisible(true)
            TabBarAPI.success(callback, "showTabBar")
        }
        return DMPAsyncResult()
    }

    private func hideTabBar(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)
        DispatchQueue.main.async {
            TabBarAPI.currentContainer(app: app)?.setTabBarVisible(false)
            TabBarAPI.success(callback, "hideTabBar")
        }
        return DMPAsyncResult()
    }

    private func setTabBarBadge(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        return handleIndexedAction(param, env, callback, "setTabBarBadge") { container, index, p in
            container.setTabBarBadge(index: index, text: p.getString(key: "text") ?? "")
        }
    }

    private func removeTabBarBadge(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        return handleIndexedAction(param, env, callback, "removeTabBarBadge") { container, index, _ in
            container.removeTabBarBadge(index: index)
        }
    }

    private func showTabBarRedDot(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        return handleIndexedAction(param, env, callback, "showTabBarRedDot") { container, index, _ in
            container.showTabBarRedDot(index: index)
        }
    }

    private func hideTabBarRedDot(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        return handleIndexedAction(param, env, callback, "hideTabBarRedDot") { container, index, _ in
            container.hideTabBarRedDot(index: index)
        }
    }

    // MARK: - Helpers

    private func handleIndexedAction(
        _ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?,
        _ apiName: String,
        action: @escaping (DMPTabBarContainerController, Int, DMPMap) -> Void
    ) -> DMPAPIResult {
        let p = param.getMap()
        guard let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex),
              let listCount = app.getBundleAppConfig()?.tabBar?.list.count, listCount > 0
        else {
            TabBarAPI.fail(callback, apiName, "tabBar not configured")
            return DMPAsyncResult()
        }

        let index = TabBarAPI.intFromParam(p.get("index"))
        guard index >= 0, index < listCount else {
            TabBarAPI.fail(callback, apiName, "invalid index \(index)")
            return DMPAsyncResult()
        }

        DispatchQueue.main.async {
            if let container = TabBarAPI.currentContainer(app: app) {
                action(container, index, p)
            }
            TabBarAPI.success(callback, apiName)
        }
        return DMPAsyncResult()
    }

    private static func currentContainer(app: DMPApp?) -> DMPTabBarContainerController? {
        guard let nav = app?.getNavigator()?.navigationController else { return nil }
        let vcs = nav.viewControllers
        if let top = vcs.last as? DMPTabBarContainerController { return top }
        return vcs.last { $0 is DMPTabBarContainerController } as? DMPTabBarContainerController
    }

    private static func success(_ callback: DMPBridgeCallback?, _ apiName: String) {
        let result = DMPMap()
        result.set("errMsg", "\(apiName):ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
    }

    private static func fail(_ callback: DMPBridgeCallback?, _ apiName: String, _ message: String) {
        DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "\(apiName):fail \(message)")
    }

    private static func intFromParam(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double, d.rounded(.towardZero) == d { return Int(d) }
        if let s = value as? String, let i = Int(s) { return i }
        return -1
    }
}
