//
//  LoginAPI.swift
//  dimina
//
//  wx.login → 转给宿主注入的 DMPLoginProvider 拿临时 code。
//  Dimina 自己不知道怎么调宿主 OpenAPI，由宿主（如 Kuril/EchoWebKit）实现 provider。
//

import Foundation

/// 宿主实现：把 mini-app 的 wx.login 请求转成宿主的 OAuth code 流程。
public protocol DMPLoginProvider: AnyObject {
    /// - Parameters:
    ///   - appId: 当前 mini-app 的 appId
    ///   - completion: 返回 mini-app 期望的 data dict（通常含 `code` 字段），或者 error
    func login(appId: String, completion: @escaping (Result<[String: Any], Error>) -> Void)
}

public class LoginAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("login", handler: login)
    }

    private func login(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        guard let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex) else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "login:fail app not found")
            return DMPAsyncResult()
        }
        guard let provider = app.loginProvider else {
            DMPLog.bridge.warn("login: no DMPLoginProvider on app \(app.getAppId()) — host must set app.loginProvider")
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "login:fail no provider")
            return DMPAsyncResult()
        }

        provider.login(appId: app.getAppId()) { result in
            switch result {
            case .success(let data):
                let res = DMPMap()
                res.set("errMsg", "login:ok")
                for (key, value) in data {
                    res.set(key, value)
                }
                DMPContainerApi.invokeSuccess(callback: callback, param: res)
            case .failure(let err):
                DMPLog.bridge.error("login failed: \(err.localizedDescription)")
                DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "login:fail \(err.localizedDescription)")
            }
        }
        return DMPAsyncResult()
    }
}
