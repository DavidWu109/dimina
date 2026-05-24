//
//  MenuAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit

/**
 * UI - Menu API
 */
public class MenuAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("getMenuButtonBoundingClientRect", handler: getMenuButtonBoundingClientRect)
    }

    private func getMenuButtonBoundingClientRect(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        return DMPSyncResult(MenuAPI.getMenuButtonBoundingClientRect())
    }

    static func getMenuButtonBoundingClientRect() -> DMPMap {
        let screenWidth = UIScreen.main.bounds.width

        let width: CGFloat = 87.0
        let height: CGFloat = 32.0

        var top: CGFloat = 0

        let statusBarHeight = DMPUIManager.shared.getStatusBarHeight()

        if statusBarHeight >= 54 {
            top = statusBarHeight - 4
        } else if statusBarHeight > 20 {
            top = 48.0
        } else {
            top = 24.0
        }

        let right: CGFloat = screenWidth - 10.0
        let left: CGFloat = right - width
        let bottom: CGFloat = top + height

        let menuButtonInfo = DMPMap([
            "width": width,
            "height": height,
            "top": top,
            "right": right,
            "bottom": bottom,
            "left": left
        ])

        return menuButtonInfo
    }
}
