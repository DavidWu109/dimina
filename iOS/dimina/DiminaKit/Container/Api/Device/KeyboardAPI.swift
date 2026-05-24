//
//  KeyboardAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit

/**
 * Device - Keyboard API
 */
public class KeyboardAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("hideKeyboard", handler: hideKeyboard)
        register("adjustPosition", handler: adjustPosition)
    }

    private func hideKeyboard(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        // 让当前第一响应者放弃响应状态来隐藏键盘
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        let result = DMPMap()
        result.set("errMsg", "hideKeyboard:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }

    private func adjustPosition(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        // Empty implementation for adjusting the keyboard position
        return DMPNoneResult()
    }

}
