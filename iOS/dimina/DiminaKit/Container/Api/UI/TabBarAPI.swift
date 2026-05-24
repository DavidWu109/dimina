//
//  TabBarAPI.swift
//  dimina
//
//  TabBar API: setTabBarStyle / setTabBarItem / showTabBar / hideTabBar /
//  setTabBarBadge / removeTabBarBadge / showTabBarRedDot / hideTabBarRedDot
//
//  Dimina 的 tabBar 由 app-config.json 的 tabBar 段静态描述，宿主负责实际渲染。
//  iOS 端 mini-app 一般不真正显示 tabBar（小程序通常用单页面 + 自定义 tabbar），
//  这里实现的 API 当 success 返回，但不试图改宿主 UI —— 避免把 Kuril 主 TabBar
//  改得乱七八糟，同时保证 Taro/wx 调用不再抛 TypeError 导致整页白屏。
//

import Foundation

/// UI - TabBar API stubs
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

    private func setTabBarStyle(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let p = param.getMap()
        let color = p.get("color") as? String
        let selectedColor = p.get("selectedColor") as? String
        let backgroundColor = p.get("backgroundColor") as? String
        let borderStyle = p.get("borderStyle") as? String
        DMPLog.bridge.debug("setTabBarStyle color=\(color ?? "") selectedColor=\(selectedColor ?? "") backgroundColor=\(backgroundColor ?? "") borderStyle=\(borderStyle ?? "")")

        DispatchQueue.main.async {
            TabBarAPI.currentTabBar(env: env)?.applyStyle(
                color: color,
                selectedColor: selectedColor,
                backgroundColor: backgroundColor,
                borderStyle: borderStyle
            )
        }
        TabBarAPI.replySuccess(callback: callback, method: "setTabBarStyle")
        return nil
    }

    private func setTabBarItem(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let p = param.getMap()
        let index = (p.get("index") as? Int) ?? -1
        let text = p.get("text") as? String
        let iconPath = p.get("iconPath") as? String
        let selectedIconPath = p.get("selectedIconPath") as? String
        DMPLog.bridge.debug("setTabBarItem index=\(index) text=\(text ?? "")")

        DispatchQueue.main.async {
            TabBarAPI.currentTabBar(env: env)?.updateItem(
                index: index,
                text: text,
                iconPath: iconPath,
                selectedIconPath: selectedIconPath
            )
        }
        TabBarAPI.replySuccess(callback: callback, method: "setTabBarItem")
        return nil
    }

    private func showTabBar(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        DMPLog.bridge.debug("showTabBar")
        DispatchQueue.main.async {
            TabBarAPI.currentTabBar(env: env)?.isHidden = false
        }
        TabBarAPI.replySuccess(callback: callback, method: "showTabBar")
        return nil
    }

    private func hideTabBar(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        DMPLog.bridge.debug("hideTabBar")
        DispatchQueue.main.async {
            TabBarAPI.currentTabBar(env: env)?.isHidden = true
        }
        TabBarAPI.replySuccess(callback: callback, method: "hideTabBar")
        return nil
    }

    private func setTabBarBadge(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let p = param.getMap()
        DMPLog.bridge.debug("setTabBarBadge index=\(p.get("index") ?? "") text=\(p.get("text") ?? "")")
        TabBarAPI.replySuccess(callback: callback, method: "setTabBarBadge")
        return nil
    }

    private func removeTabBarBadge(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let p = param.getMap()
        DMPLog.bridge.debug("removeTabBarBadge index=\(p.get("index") ?? "")")
        TabBarAPI.replySuccess(callback: callback, method: "removeTabBarBadge")
        return nil
    }

    private func showTabBarRedDot(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let p = param.getMap()
        DMPLog.bridge.debug("showTabBarRedDot index=\(p.get("index") ?? "")")
        TabBarAPI.replySuccess(callback: callback, method: "showTabBarRedDot")
        return nil
    }

    private func hideTabBarRedDot(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let p = param.getMap()
        DMPLog.bridge.debug("hideTabBarRedDot index=\(p.get("index") ?? "")")
        TabBarAPI.replySuccess(callback: callback, method: "hideTabBarRedDot")
        return nil
    }

    private static func replySuccess(callback: DMPBridgeCallback?, method: String) {
        let result = DMPMap()
        result.set("errMsg", "\(method):ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
    }

    /// 取当前 nav 栈里的 DMPTabBarContainerController 持有的 tabBarView。
    fileprivate static func currentTabBar(env: DMPBridgeEnv) -> DMPTabBarView? {
        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)
        guard let navController = app?.getNavigator()?.navigationController else { return nil }
        let container = navController.viewControllers.compactMap { $0 as? DMPTabBarContainerController }.first
        return container?.tabBarView
    }
}
