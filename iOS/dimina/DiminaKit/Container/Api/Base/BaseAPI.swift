//
//  BaseAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation

/**
 * Base API implementation
 */
public class BaseAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("canIUse", handler: canIUse)
    }

    private func canIUse(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        guard let schema = param.getMap().get("schema") as? String else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "canIUse:fail missing parameter schema")
            return DMPSyncResult(false)
        }

        let registeredMethods = DMPAppManager.sharedInstance()
            .getApp(appIndex: env.appIndex)?
            .containerApi?
            .getAllRegisteredMethods() ?? []

        let isAvailable = registeredMethods.contains(schema)

        return DMPSyncResult(isAvailable)
    }
}
