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
    
    // API method names
    private static let GET_DEVICE_INFO = "getDeviceInfo"
    private static let IS_DEBUG = "isDebug"
    
    // Get device information
    @BridgeMethod(GET_DEVICE_INFO)
    var getDeviceInfo: DMPBridgeMethodHandler = { param, env, callback in
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
    
    // Check if app is in debug mode
    @BridgeMethod(IS_DEBUG)
    var isDebug: DMPBridgeMethodHandler = { param, env, callback in
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
