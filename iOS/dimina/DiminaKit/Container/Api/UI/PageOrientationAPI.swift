//
//  PageOrientationAPI.swift
//  dimina
//

import Foundation

/// Internal bridge used by `<page-meta page-orientation>`.
///
/// This intentionally does not expose a public `wx.setDeviceOrientation` API:
/// regular mini programs use page configuration and page-meta semantics.
final class PageOrientationAPI: DMPContainerApi {

    override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("__setPageOrientation", handler: setPageOrientation)
    }

    private func setPageOrientation(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let rawValue = param.getMap().getString(key: "pageOrientation") ?? ""
        let orientation: DMPPageOrientation?

        if rawValue.isEmpty {
            orientation = nil
        } else if let parsed = DMPPageOrientation(rawValue: rawValue) {
            orientation = parsed
        } else {
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "pageOrientation:fail invalid value"
            )
            return DMPAsyncResult()
        }

        let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex)
        Task { @MainActor in
            app?.applyPageOrientation(orientation, webViewId: env.webViewId)
            DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap())
        }
        return DMPAsyncResult()
    }
}
