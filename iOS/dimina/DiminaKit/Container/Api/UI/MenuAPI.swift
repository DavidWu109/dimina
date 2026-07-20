//
//  MenuAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit

enum DMPMenuButtonLayout {
    static let capsuleSize = CGSize(width: 87, height: 32)
    static let trailingSpacing: CGFloat = 10
    static let navigationBarContentHeight: CGFloat = 44
    static let titleTrailingGap: CGFloat = 13
    static var titleTrailingInset: CGFloat {
        trailingSpacing + capsuleSize.width + titleTrailingGap
    }

    static func rect(
        windowWidth: CGFloat,
        statusBarHeight: CGFloat,
        safeAreaTop: CGFloat
    ) -> CGRect {
        let top = max(statusBarHeight, safeAreaTop)
            + (navigationBarContentHeight - capsuleSize.height) / 2
        let right = max(windowWidth - trailingSpacing, capsuleSize.width)
        return CGRect(
            x: right - capsuleSize.width,
            y: top,
            width: capsuleSize.width,
            height: capsuleSize.height
        )
    }
}

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
        let displayInfo = DMPUIManager.shared.getDeviceDisplayInfo()
        let windowWidth = displayInfo["windowWidth"] as? CGFloat
            ?? DMPUIManager.getCurrentWindow()?.bounds.width
            ?? UIScreen.main.bounds.width
        let statusBarHeight = DMPUIManager.shared.getStatusBarHeight()
        let safeAreaTop = DMPUIManager.shared.getSafeAreaInsets().top
        let rect = DMPMenuButtonLayout.rect(
            windowWidth: windowWidth,
            statusBarHeight: statusBarHeight,
            safeAreaTop: safeAreaTop
        )

        let menuButtonInfo = DMPMap([
            "width": rect.width,
            "height": rect.height,
            "top": rect.minY,
            "right": rect.maxX,
            "bottom": rect.maxY,
            "left": rect.minX,
            "x": rect.minX,
            "y": rect.minY
        ])

        return menuButtonInfo
    }
}
