//
//  RouteAPI.swift
//  dimina
//
//  Created by Lehem on 2025/4/27.
//

import Foundation

/**
 * Navigation API implementation
 *
 * Handles all page navigation operations:
 * - navigateTo: Navigate to a new page
 * - redirectTo: Replace current page with a new one
 * - navigateBack: Navigate back to the previous page
 * - reLaunch: Close all pages and open a specific page
 */
public class RouteAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("switchTab", handler: switchTab)
        register("navigateTo", handler: navigateTo)
        register("redirectTo", handler: redirectTo)
        register("navigateBack", handler: navigateBack)
        register("reLaunch", handler: reLaunch)
    }

    private func switchTab(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let url = param.get("url") as? String, !url.isEmpty else {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "switchTab:fail URL cannot be empty")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "URL cannot be empty")
            return DMPAsyncResult()
        }
        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)
        let urlData = DMPUtil.queryPath(path: url)
        let pagePath = urlData["pagePath"] as! String

        // 校验是不是 tabBar 页面
        if let tabBar = app?.getBundleAppConfig()?.tabBar, !tabBar.contains(pagePath: pagePath) {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "switchTab:fail '\(pagePath)' is not a tabBar page")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "not a tabBar page")
            return DMPAsyncResult()
        }

        Task { @MainActor in
            _ = app?.getNavigator()?.switchTab(to: pagePath)
        }

        let result = DMPMap()
        result.set("errMsg", "switchTab:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }

    private func navigateTo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let url = param.get("url") as? String, !url.isEmpty else {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "navigateTo:fail URL cannot be empty")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "URL cannot be empty")
            return DMPAsyncResult()
        }

        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)

        let urlData = DMPUtil.queryPath(path: url)
        let pagePath = urlData["pagePath"] as! String
        let query = urlData["query"] as! [String: Any]
        DMPLog.bridge.info("navigateTo url=\(url) → pagePath=\(pagePath) query=\(query)")

        Task { @MainActor in
            await app?.getNavigator()?.navigateTo(to: pagePath, query: query)
        }

        let result = DMPMap()
        result.set("errMsg", "navigateTo:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }

    private func redirectTo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let url = param.get("url") as? String, !url.isEmpty else {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "redirectTo:fail URL cannot be empty")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "URL cannot be empty")
            return DMPAsyncResult()
        }

        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)

        let urlData = DMPUtil.queryPath(path: url)
        let pagePath = urlData["pagePath"] as! String
        let query = urlData["query"] as! [String: Any]

        Task { @MainActor in
            await app?.getNavigator()?.redirectTo(to: pagePath, query: query)
        }

        let result = DMPMap()
        result.set("errMsg", "redirectTo:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }

    private func navigateBack(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)

        Task { @MainActor in
            app?.getNavigator()?.navigateBack(delta: param.getInt(key: "delta") ?? 1)
        }

        let result = DMPMap()
        result.set("errMsg", "navigateBack:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }

    private func reLaunch(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let url = param.get("url") as? String, !url.isEmpty else {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "reLaunch:fail URL cannot be empty")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "URL cannot be empty")
            return DMPAsyncResult()
        }

        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)

        let urlData = DMPUtil.queryPath(path: url)
        let pagePath = urlData["pagePath"] as! String
        let query = urlData["query"] as! [String: Any]

        Task { @MainActor in
            await app?.getNavigator()?.relaunch(to: pagePath, query: query)
        }

        let result = DMPMap()
        result.set("errMsg", "reLaunch:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }
}
