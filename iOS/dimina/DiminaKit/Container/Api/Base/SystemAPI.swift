//
//  SystemAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit
import CoreBluetooth
import CoreLocation

/**
 * System API implementation
 *
 * Handles system-related operations like getting device information
 */
public class SystemAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("getWindowInfo", handler: getWindowInfo)
        register("getSystemSetting", handler: getSystemSetting)
        register("getSystemInfoSync", handler: getSystemInfoSync)
        register("getSystemInfoAsync", handler: getSystemInfoAsync)
        register("getSystemInfo", handler: getSystemInfo)
    }

    private func getWindowInfo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let windowInfo = DMPMap(DMPUIManager.shared.getDeviceDisplayInfo())
        return DMPSyncResult(windowInfo)
    }

    private func getSystemSetting(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        // 公司 fork 故意不主动调 CBCentralManager / CLLocationManager 等
        // 触发权限弹窗的 API，保持空 dict 返回。详见 reference-dimina-upstream-merge-strategy。
        let result = DMPMap()
        return DMPSyncResult(result)
    }

    private func getSystemInfoSync(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        return DMPSyncResult(SystemAPI.getSystemInfo())
    }

    private func getSystemInfoAsync(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let systemInfo = SystemAPI.getSystemInfo()
        DMPContainerApi.invokeSuccess(callback: callback, param: systemInfo)
        return DMPAsyncResult()
    }

    private func getSystemInfo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let systemInfo = SystemAPI.getSystemInfo()
        DMPContainerApi.invokeSuccess(callback: callback, param: systemInfo)
        return DMPSyncResult(systemInfo)
    }

    static func getSystemInfo() -> DMPMap {
        let displayInfo = DMPMap(DMPUIManager.shared.getDeviceDisplayInfo())

        let systemInfo = DMPMap([
            "brand": UIDevice.current.model,
            "model": UIDevice.current.model,

            "language": Locale.current.languageCode ?? "zh_CN",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "system": UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
            "platform": "ios",
            "SDKVersion": "1.0.0",

            "albumAuthorized": false,
            "cameraAuthorized": false,
            "locationAuthorized": false,
            "microphoneAuthorized": false,

            "theme": UITraitCollection.current.userInterfaceStyle == .dark ? "dark" : "light",
        ])

        // 合并显示信息
        systemInfo.merge(displayInfo)
        return systemInfo
    }
}
