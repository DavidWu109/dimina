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
        register("hideHomeButton", handler: hideHomeButton)
    }

    private func setNavigationBarTitle(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let title = param.get("title") as? String else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setNavigationBarTitle:fail missing parameter title")
            return DMPAsyncResult()
        }

        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)

        guard let navigator = app?.getNavigator() else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setNavigationBarTitle:fail navigation controller not found")
            return DMPAsyncResult()
        }

        DispatchQueue.main.async {
            guard let pageController = navigator.getCurrentPageController() else {
                DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setNavigationBarTitle:fail page controller not found")
                return
            }
            pageController.mergeCachedNavStyle(["navigationBarTitleText": title])
            pageController.updateNavigationTitle(title)

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
            guard let navigator = app?.getNavigator(),
                  let navigationController = navigator.navigationController,
                  let pageController = navigator.getCurrentPageController() else {
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
                pageController.navigationItem.standardAppearance = appearance
                pageController.navigationItem.scrollEdgeAppearance = appearance
                pageController.navigationItem.compactAppearance = appearance

                if #available(iOS 15.0, *) {
                    pageController.navigationItem.compactScrollEdgeAppearance = appearance
                }

                navigationController.navigationBar.tintColor = textColor
                navigationController.navigationBar.setNeedsLayout()
                pageController.updateNavigationColor(
                    backgroundColor: bgColor,
                    textColor: textColor,
                    darkStyle: frontColor == "#ffffff"
                )
            }

            pageController.mergeCachedNavStyle([
                "navigationBarBackgroundColor": backgroundColor,
                "navigationBarTextStyle": frontColor == "#ffffff" ? "white" : "black",
            ])

            let result = DMPMap()
            result.set("errMsg", "setNavigationBarColor:ok")
            DMPContainerApi.invokeSuccess(callback: callback, param: result)
        }

        return DMPAsyncResult()
    }

    private func hideHomeButton(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)
        DispatchQueue.main.async {
            guard let pageController = app?.getNavigator()?.getCurrentPageController() else {
                DMPContainerApi.invokeFailure(
                    callback: callback,
                    param: nil,
                    errMsg: "hideHomeButton:fail page controller not found"
                )
                return
            }
            pageController.hideHomeButton()
            let result = DMPMap()
            result.set("errMsg", "hideHomeButton:ok")
            DMPContainerApi.invokeSuccess(callback: callback, param: result)
        }
        return DMPAsyncResult()
    }
}
