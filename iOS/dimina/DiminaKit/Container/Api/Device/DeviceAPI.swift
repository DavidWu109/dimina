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

    private func getDeviceInfo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        return DMPSyncResult(SystemAPI.getDeviceInfo())
    }

    private func isDebug(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let result = DMPMap()

        #if DEBUG
        let isDebugMode = true
        #else
        let isDebugMode = false
        #endif

        result.set("data", isDebugMode)
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPSyncResult(true)
    }
}
