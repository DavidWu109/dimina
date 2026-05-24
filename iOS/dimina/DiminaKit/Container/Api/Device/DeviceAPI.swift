//
//  DeviceAPI.swift
//  dimina
//
//  Created by David on 2025/2/25.
//  Copyright © 2025 EchoingTech. All rights reserved.
//

import Foundation

/**
 * Device API implementation
 */
public class DeviceAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("getDeviceInfo", handler: getDeviceInfo)
        register("isDebug", handler: isDebug)
    }

    private func getDeviceInfo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let result = DMPMap()
        let data = DMPMap()

        // Note: These CGFloat extensions would need to be available or replaced with standard UIKit values
//        let screenBounds = UIScreen.main.bounds
//        let statusBarHeight = UIApplication.shared.statusBarFrame.height
//        let navigationBarHeight: CGFloat = 44 // Standard navigation bar height
//
//        data.set("screenWidth", Int(screenBounds.width))
//        data.set("screenHeight", Int(screenBounds.height))
//        data.set("navigationBarHeight", Int(navigationBarHeight))
//        data.set("statusBarHeight", Int(statusBarHeight))
//
//        result.set("data", data)
//        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return true
    }

    private func isDebug(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let result = DMPMap()

        #if DEBUG
        let isDebugMode = true
        #else
        let isDebugMode = false
        #endif

        result.set("data", isDebugMode)
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return true
    }
}
