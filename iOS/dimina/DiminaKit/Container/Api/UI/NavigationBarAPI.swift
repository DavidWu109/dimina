//
//  NavigationBarAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit

/**
 * UI - Navigation Bar API
 */
public class NavigationBarAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("setNavigationBarTitle", handler: setNavigationBarTitle)
        register("setNavigationBarColor", handler: setNavigationBarColor)
    }

    private func setNavigationBarTitle(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let title = param.get("title") as? String else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setNavigationBarTitle:fail missing parameter title")
            return DMPAsyncResult()
        }

        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)

        guard let navigationController = app?.getNavigator()?.navigationController else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setNavigationBarTitle:fail navigation controller not found")
            return DMPAsyncResult()
        }

        DispatchQueue.main.async {
            navigationController.topViewController?.title = title

            let result = DMPMap()
            result.set("errMsg", "setNavigationBarTitle:ok")
            DMPContainerApi.invokeSuccess(callback: callback, param: result)
        }

        return DMPAsyncResult()
    }

    private func setNavigationBarColor(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let frontColor = param.get("frontColor") as? String,
              let backgroundColor = param.get("backgroundColor") as? String else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setNavigationBarColor:fail missing required parameters")
            return DMPAsyncResult()
        }

        guard frontColor == "#ffffff" || frontColor == "#000000" else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setNavigationBarColor:fail frontColor only supports #ffffff or #000000")
            return DMPAsyncResult()
        }

        let animation = param.getDMPMap(key: "animation")
        let duration = animation?.getInt(key: "duration") ?? 0
        let timingFunc = animation?.getString(key: "timingFunc") ?? "linear"

        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)

        DispatchQueue.main.async {
            guard let navigationController = app?.getNavigator()?.navigationController,
                  let topViewController = navigationController.topViewController else {
                DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setNavigationBarColor:fail navigation controller not found")
                return
            }

            let bgColor = DMPUtil.colorFromHexString(backgroundColor) ?? .white
            let textColor = frontColor == "#ffffff" ? UIColor.white : UIColor.black

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = bgColor
            appearance.titleTextAttributes = [.foregroundColor: textColor]

            let animationDuration = TimeInterval(duration) / 1000.0

            let animationOptions: UIView.AnimationOptions = {
                switch timingFunc {
                case "easeIn":
                    return .curveEaseIn
                case "easeOut":
                    return .curveEaseOut
                case "easeInOut":
                    return .curveEaseInOut
                default:
                    return .curveLinear
                }
            }()

            UIView.animate(withDuration: animationDuration, delay: 0, options: animationOptions) {
                topViewController.navigationItem.standardAppearance = appearance
                topViewController.navigationItem.scrollEdgeAppearance = appearance
                topViewController.navigationItem.compactAppearance = appearance
                topViewController.navigationItem.leftBarButtonItem = app?.getNavigator()?.createBackButton(darkStyle: frontColor == "#ffffff")

                if #available(iOS 15.0, *) {
                    topViewController.navigationItem.compactScrollEdgeAppearance = appearance
                }

                navigationController.navigationBar.tintColor = textColor
                navigationController.navigationBar.setNeedsLayout()

                // 通知 overlay (宿主胶囊) 切换深/浅模式 —— overlayView 需要宿主通过 pageOverlayProvider 注入
                if let pageController = topViewController as? DMPPageController,
                   pageController.responds(to: Selector(("overlayView"))),
                   let overlay = pageController.value(forKey: "overlayView"),
                   let stylable = overlay as? DMPNavigationBarColorApplicable {
                    stylable.applyNavigationBarColor(frontColor: frontColor, backgroundColor: backgroundColor)
                }
            }

            let updatedNavStyle: [String: Any] = {
                var s = app?.getNavigator()?.getTopPageRecord()?.navStyle ?? [:]
                s["navigationBarBackgroundColor"] = backgroundColor
                s["navigationBarTextStyle"] = frontColor == "#ffffff" ? "white" : "black"
                return s
            }()
            app?.getNavigator()?.getTopPageRecord()?.navStyle = updatedNavStyle
            if let pageController = topViewController as? DMPPageController {
                pageController.updateCachedNavStyle(updatedNavStyle)
            }

            let result = DMPMap()
            result.set("errMsg", "setNavigationBarColor:ok")
            DMPContainerApi.invokeSuccess(callback: callback, param: result)
        }

        return DMPAsyncResult()
    }
}
