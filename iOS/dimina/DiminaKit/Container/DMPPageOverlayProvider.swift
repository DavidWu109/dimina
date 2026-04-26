//
//  DMPPageOverlayProvider.swift
//  dimina
//
//  Created by Claude on 2026/3/30.
//

import Foundation
import UIKit

/// Protocol for the host app to provide overlay views on mini-program pages.
/// The overlay is added on top of the WebView content (e.g., capsule button).
public protocol DMPPageOverlayProvider: AnyObject {
    /// Called when a DMPPageController's view is loaded.
    /// - Parameters:
    ///   - pageController: The page controller requesting the overlay
    ///   - isRoot: Whether this is the root page of the mini program
    /// - Returns: A UIView to overlay on top of the page, or nil
    func overlayView(for pageController: DMPPageController, isRoot: Bool) -> UIView?
}

/// Overlay 视图实现该协议后，可以响应 wx.setNavigationBarColor 的颜色更新（深 / 浅模式）
public protocol DMPNavigationBarColorApplicable: AnyObject {
    /// - Parameters:
    ///   - frontColor: 前景色，仅 "#ffffff" / "#000000"
    ///   - backgroundColor: 背景色 hex 字符串（可空，由实现决定如何兜底）
    func applyNavigationBarColor(frontColor: String, backgroundColor: String?)
}
