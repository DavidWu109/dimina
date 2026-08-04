//
//  SettingAPI.swift
//  dimina
//

import Foundation

/// Mini-program authorization settings bridge.
public final class SettingAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("getSetting", handler: getSetting)
        register("openSetting", handler: openSetting)
        register("authorize", handler: authorize)
    }

    private func getSetting(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        guard let getter = getApp()?.getAppConfig()?.getAuthSetting else {
            DMPContainerApi.invokeSuccess(
                callback: callback,
                param: DMPMap(["authSetting": [String: Bool]()])
            )
            return DMPAsyncResult()
        }

        getter { result in
            switch result {
            case .success(let settings):
                DMPContainerApi.invokeSuccess(
                    callback: callback,
                    param: DMPMap(["authSetting": settings])
                )
            case .failure:
                DMPContainerApi.invokeFailure(
                    callback: callback,
                    param: nil,
                    errMsg: "getSetting:fail"
                )
            }
        }
        return DMPAsyncResult()
    }

    private func openSetting(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        if let action = getApp()?.getAppConfig()?.onMenuSettingClick {
            DispatchQueue.main.async(execute: action)
        } else {
            DispatchQueue.main.async {
                DMPPermissionManager.shared.openSettings()
            }
        }
        DMPContainerApi.invokeSuccess(callback: callback, param: nil)
        return DMPAsyncResult()
    }

    private func authorize(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let scope = param.getMap().get("scope") as? String ?? ""
        guard !scope.isEmpty else {
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "authorize:fail invalid scope"
            )
            return DMPAsyncResult()
        }

        guard let checker = getApp()?.getAppConfig()?.checkPermission else {
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "authorize:fail unsupported scope"
            )
            return DMPAsyncResult()
        }

        checker(scope) { result in
            guard result == .allowed else {
                DMPContainerApi.invokeFailure(
                    callback: callback,
                    param: nil,
                    errMsg: Self.permissionErrorMessage(method: "authorize", result: result)
                )
                return
            }
            DMPContainerApi.invokeSuccess(callback: callback, param: nil)
        }
        return DMPAsyncResult()
    }

    static func permissionErrorMessage(
        method: String,
        result: DMPPermissionCheckResult
    ) -> String {
        switch result {
        case .allowed:
            return "\(method):ok"
        case .systemDenied:
            return "\(method):fail system permission denied"
        case .userDenied:
            return "\(method):fail user permission denied"
        case .scopeNotConfigured:
            return "\(method):fail scope not configured in app.json"
        }
    }
}
