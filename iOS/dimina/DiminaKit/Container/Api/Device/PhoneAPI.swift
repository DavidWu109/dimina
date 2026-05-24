//
//  PhoneAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit

/**
 * Device - Phone API
 */
public class PhoneAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("makePhoneCall", handler: makePhoneCall)
    }

    private func makePhoneCall(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        // 获取电话号码
        let phoneNumber = param.getMap().get("phoneNumber") as? String ?? ""

        // 检查电话号码是否为空
        if phoneNumber.isEmpty {
            let result = DMPMap()
            result.set("errMsg", "makePhoneCall:fail phoneNumber is required")
            DMPContainerApi.invokeFailure(callback: callback, param: result, errMsg: "phoneNumber is required")
            return DMPAsyncResult()
        }

        // 构建电话 URL
        guard let url = URL(string: "tel:\(phoneNumber)") else {
            let result = DMPMap()
            result.set("errMsg", "makePhoneCall:fail invalid phone number")
            DMPContainerApi.invokeFailure(callback: callback, param: result, errMsg: "invalid phone number")
            return DMPAsyncResult()
        }

        // 检查设备是否支持拨号
        guard UIApplication.shared.canOpenURL(url) else {
            let result = DMPMap()
            result.set("errMsg", "makePhoneCall:fail device does not support phone calls")
            DMPContainerApi.invokeFailure(callback: callback, param: result, errMsg: "device does not support phone calls")
            return DMPAsyncResult()
        }

        // 在主线程上打开 URL
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                let result = DMPMap()
                if success {
                    result.set("errMsg", "makePhoneCall:ok")
                    DMPContainerApi.invokeSuccess(callback: callback, param: result)
                } else {
                    result.set("errMsg", "makePhoneCall:fail unable to make phone call")
                    DMPContainerApi.invokeFailure(callback: callback, param: result, errMsg: "unable to make phone call")
                }
            }
        }
        return DMPAsyncResult()
    }
}
