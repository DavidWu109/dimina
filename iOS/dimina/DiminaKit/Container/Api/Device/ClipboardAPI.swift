//
//  ClipboardAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit

/**
 * Device - Clipboard API
 */
public class ClipboardAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("setClipboardData", handler: setClipboardData)
        register("getClipboardData", handler: getClipboardData)
    }

    private func setClipboardData(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        guard let data = param.getMap().get("data") as? String else {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "setClipboardData:fail data is required")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "data is required")
            return DMPAsyncResult()
        }

        // 直接设置剪贴板内容
        UIPasteboard.general.string = data

        let result = DMPMap()
        result.set("errMsg", "setClipboardData:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }

    private func getClipboardData(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        // 直接获取剪贴板内容
        let clipboardData = UIPasteboard.general.string

        let result = DMPMap()
        if let clipboardData = clipboardData {
            result.set("data", clipboardData)
        }
        result.set("errMsg", "getClipboardData:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }
}
