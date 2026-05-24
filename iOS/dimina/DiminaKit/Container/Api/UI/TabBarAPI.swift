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

    private static let SET_TAB_BAR_STYLE   = "setTabBarStyle"
    private static let SET_TAB_BAR_ITEM    = "setTabBarItem"
    private static let SHOW_TAB_BAR        = "showTabBar"
    private static let HIDE_TAB_BAR        = "hideTabBar"
    private static let SET_TAB_BAR_BADGE   = "setTabBarBadge"
    private static let REMOVE_TAB_BAR_BADGE = "removeTabBarBadge"
    private static let SHOW_TAB_BAR_RED_DOT = "showTabBarRedDot"
    private static let HIDE_TAB_BAR_RED_DOT = "hideTabBarRedDot"

    @BridgeMethod(SET_TAB_BAR_STYLE)
    var setTabBarStyle: DMPBridgeMethodHandler = { param, env, callback in
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
        TabBarAPI.replySuccess(callback: callback, method: SET_TAB_BAR_STYLE)
        return nil
    }

    @BridgeMethod(SET_TAB_BAR_ITEM)
    var setTabBarItem: DMPBridgeMethodHandler = { param, env, callback in
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
        TabBarAPI.replySuccess(callback: callback, method: SET_TAB_BAR_ITEM)
        return nil
    }

    @BridgeMethod(SHOW_TAB_BAR)
    var showTabBar: DMPBridgeMethodHandler = { _, env, callback in
        DMPLog.bridge.debug("showTabBar")
        DispatchQueue.main.async {
            TabBarAPI.currentTabBar(env: env)?.isHidden = false
        }
        TabBarAPI.replySuccess(callback: callback, method: SHOW_TAB_BAR)
        return nil
    }

    @BridgeMethod(HIDE_TAB_BAR)
    var hideTabBar: DMPBridgeMethodHandler = { _, env, callback in
        DMPLog.bridge.debug("hideTabBar")
        DispatchQueue.main.async {
            TabBarAPI.currentTabBar(env: env)?.isHidden = true
        }
        TabBarAPI.replySuccess(callback: callback, method: HIDE_TAB_BAR)
        return nil
    }

    @BridgeMethod(SET_TAB_BAR_BADGE)
    var setTabBarBadge: DMPBridgeMethodHandler = { param, _, callback in
        let p = param.getMap()
        DMPLog.bridge.debug("setTabBarBadge index=\(p.get("index") ?? "") text=\(p.get("text") ?? "")")
        TabBarAPI.replySuccess(callback: callback, method: SET_TAB_BAR_BADGE)
        return nil
    }

    @BridgeMethod(REMOVE_TAB_BAR_BADGE)
    var removeTabBarBadge: DMPBridgeMethodHandler = { param, _, callback in
        let p = param.getMap()
        DMPLog.bridge.debug("removeTabBarBadge index=\(p.get("index") ?? "")")
        TabBarAPI.replySuccess(callback: callback, method: REMOVE_TAB_BAR_BADGE)
        return nil
    }

    @BridgeMethod(SHOW_TAB_BAR_RED_DOT)
    var showTabBarRedDot: DMPBridgeMethodHandler = { param, _, callback in
        let p = param.getMap()
        DMPLog.bridge.debug("showTabBarRedDot index=\(p.get("index") ?? "")")
        TabBarAPI.replySuccess(callback: callback, method: SHOW_TAB_BAR_RED_DOT)
        return nil
    }

    @BridgeMethod(HIDE_TAB_BAR_RED_DOT)
    var hideTabBarRedDot: DMPBridgeMethodHandler = { param, _, callback in
        let p = param.getMap()
        DMPLog.bridge.debug("hideTabBarRedDot index=\(p.get("index") ?? "")")
        TabBarAPI.replySuccess(callback: callback, method: HIDE_TAB_BAR_RED_DOT)
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
