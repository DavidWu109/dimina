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
        register("getAppBaseInfo", handler: getAppBaseInfo)
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
        return DMPSyncResult(SystemAPI.getSystemInfo(app: getApp()))
    }

    private func getSystemInfoAsync(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let systemInfo = SystemAPI.getSystemInfo(app: getApp())
        DMPContainerApi.invokeSuccess(callback: callback, param: systemInfo)
        return DMPAsyncResult()
    }

    private func getSystemInfo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let systemInfo = SystemAPI.getSystemInfo(app: getApp())
        DMPContainerApi.invokeSuccess(callback: callback, param: systemInfo)
        return DMPSyncResult(systemInfo)
    }

    private func getAppBaseInfo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        return DMPSyncResult(SystemAPI.getAppBaseInfo(app: getApp()))
    }

    static func getSystemInfo(app: DMPApp? = nil) -> DMPMap {
        let displayInfo = DMPMap(DMPUIManager.shared.getDeviceDisplayInfo())
        let windowWidth = displayInfo.getDouble(key: "windowWidth") ?? 0
        let windowHeight = displayInfo.getDouble(key: "windowHeight") ?? 0

        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif

        let baseFontSize: CGFloat = 16
        let scaledFontSize = UIFontMetrics.default.scaledValue(for: baseFontSize)

        let systemInfo = DMPMap([
            "brand": "Apple",
            "model": UIDevice.current.model,

            "language": Locale.current.languageCode ?? "zh_CN",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "system": UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
            "platform": "ios",
            "SDKVersion": DiminaVersion.sdkVersion,
            "enableDebug": app?.getAppConfig()?.isDebugMode ?? isDebugBuild,
            "host": ["appId": app?.getAppId() ?? ""],
            "fontSizeScaleFactor": scaledFontSize / baseFontSize,
            "fontSizeSetting": Int(scaledFontSize.rounded()),
            "deviceOrientation": windowWidth > windowHeight ? "landscape" : "portrait",

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

    static func getAppBaseInfo(app: DMPApp? = nil) -> DMPMap {
        return pick(
            getSystemInfo(app: app),
            keys: [
                "SDKVersion",
                "enableDebug",
                "host",
                "language",
                "version",
                "theme",
                "fontSizeScaleFactor",
                "fontSizeSetting",
            ]
        )
    }

    static func getDeviceInfo() -> DMPMap {
        #if arch(arm64)
        let abi = "arm64"
        #elseif arch(x86_64)
        let abi = "x86_64"
        #else
        let abi = "unknown"
        #endif

        return DMPMap([
            "abi": abi,
            "benchmarkLevel": -1,
            "brand": "Apple",
            "model": UIDevice.current.model,
            "platform": "ios",
            "system": UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
        ])
    }

    private static func pick(_ source: DMPMap, keys: [String]) -> DMPMap {
        let result = DMPMap()
        for key in keys {
            if let value = source.get(key) {
                result.set(key, value)
            }
        }
        return result
    }
}
