//
//  StorageAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation

/**
 * Storage API implementation
 *
 * Handles data storage operations like setting, getting, and removing stored data
 */
public class StorageAPI: DMPContainerApi {

    override public init(app: DMPApp? = nil) {
        super.init(app: app)

        register("setStorageSync", handler: setStorageSync)
        register("getStorageSync", handler: getStorageSync)
        register("removeStorageSync", handler: removeStorageSync)
        register("clearStorageSync", handler: clearStorageSync)
        register("setStorage", handler: setStorage)
        register("getStorage", handler: getStorage)
        register("removeStorage", handler: removeStorage)
        register("clearStorage", handler: clearStorage)
        register("getStorageInfoSync", handler: getStorageInfoSync)
        register("getStorageInfo", handler: getStorageInfo)
    }

    private func setStorageSync(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let key: String
        let data: Any
        let encrypt: Bool

        if let array = param.getValue() as? [Any], array.count >= 2 {
            guard let k = array[0] as? String else { return DMPSyncResult(false) }
            key = k
            data = array[1]
            encrypt = false
        } else {
            let map = param.getMap()
            guard let k = map.get("key") as? String else { return DMPSyncResult(false) }
            guard let d = map.get("data") else { return DMPSyncResult(false) }
            key = k
            data = d
            encrypt = map.get("encrypt") as? Bool ?? false
        }

        let result = DMPStorage.storage(for: env.appId).set(key: key, value: data, encrypted: encrypt)
        return DMPSyncResult(result)
    }

    private func getStorageSync(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let key: String
        if let k = param.getValue() as? String {
            key = k
        } else if let k = param.getMap().get("key") as? String {
            key = k
        } else {
            return DMPNoneResult()
        }
        let value = DMPStorage.storage(for: env.appId).get(key: key, encrypted: false)
        return DMPSyncResult(DMPBridgeParam(value: value))
    }

    private func removeStorageSync(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let key: String
        if let k = param.getValue() as? String {
            key = k
        } else if let k = param.getMap().get("key") as? String {
            key = k
        } else {
            return DMPSyncResult(false)
        }
        let encrypt = param.getMap().get("encrypt") as? Bool ?? false

        DMPStorage.storage(for: env.appId).remove(key: key, encrypted: encrypt)
        return DMPSyncResult(true)
    }

    private func clearStorageSync(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        DMPStorage.storage(for: env.appId).clearAllStorage()
        return DMPSyncResult(true)
    }

    private func setStorage(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let key = param.get("key") as? String else {
            NSLog("🗄️ [setStorage] FAIL: missing key, param=%@", param.toDictionary().description)
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setStorage:fail missing parameter key")
            return DMPAsyncResult()
        }

        let data = param.get("data")
        let encrypt = param.get("encrypt") as? Bool ?? false

        guard let data = data else {
            NSLog("🗄️ [setStorage] FAIL: missing data for key=%@", key)
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setStorage:fail missing parameter data")
            return DMPAsyncResult()
        }

        DispatchQueue.global().async {
            let success = DMPStorage.storage(for: env.appId).set(key: key, value: data, encrypted: encrypt)

            DispatchQueue.main.async {
                if success {
                    let resultMap = DMPMap()
                    resultMap.set("errMsg", "setStorage:ok")
                    DMPContainerApi.invokeSuccess(callback: callback, param: resultMap)
                } else {
                    DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "setStorage:fail")
                }
            }
        }

        return DMPAsyncResult()
    }

    private func getStorage(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let key = param.get("key") as? String else {
            NSLog("🗄️ [getStorage] FAIL: missing key, param=%@", param.toDictionary().description)
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "getStorage:fail missing parameter key")
            return DMPAsyncResult()
        }

        let encrypt = param.get("encrypt") as? Bool ?? false

        DispatchQueue.global().async {
            let value = DMPStorage.storage(for: env.appId).get(key: key, encrypted: encrypt)

            DispatchQueue.main.async {
                if let value = value {
                    let resultMap = DMPMap()
                    resultMap.set("data", value)
                    resultMap.set("errMsg", "getStorage:ok")
                    DMPContainerApi.invokeSuccess(callback: callback, param: resultMap)
                } else {
                    DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "getStorage:fail data not found")
                }
            }
        }

        return DMPAsyncResult()
    }

    private func removeStorage(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        guard let key = param.get("key") as? String else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "removeStorage:fail missing parameter key")
            return DMPAsyncResult()
        }

        let encrypt = param.get("encrypt") as? Bool ?? false

        DispatchQueue.global().async {
            DMPStorage.storage(for: env.appId).remove(key: key, encrypted: encrypt)

            DispatchQueue.main.async {
                let resultMap = DMPMap()
                resultMap.set("errMsg", "removeStorage:ok")
                DMPContainerApi.invokeSuccess(callback: callback, param: resultMap)
            }
        }

        return DMPAsyncResult()
    }

    private func clearStorage(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        DispatchQueue.global().async {
            DMPStorage.storage(for: env.appId).clearAllStorage()

            DispatchQueue.main.async {
                let resultMap = DMPMap()
                resultMap.set("errMsg", "clearStorage:ok")
                DMPContainerApi.invokeSuccess(callback: callback, param: resultMap)
            }
        }

        return DMPAsyncResult()
    }

    private func getStorageInfoSync(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let storageInfo = DMPStorage.storage(for: env.appId).getAllStorageInfo()

        let result = DMPMap()
        result.set("keys", storageInfo.keys)
        result.set("currentSize", storageInfo.currentSize)
        result.set("limitSize", storageInfo.limitSize)

        return DMPSyncResult(result)
    }

    private func getStorageInfo(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        DispatchQueue.global().async {
            let storageInfo = DMPStorage.storage(for: env.appId).getAllStorageInfo()

            DispatchQueue.main.async {
                let resultMap = DMPMap()
                resultMap.set("keys", storageInfo.keys)
                resultMap.set("currentSize", storageInfo.currentSize)
                resultMap.set("limitSize", storageInfo.limitSize)
                resultMap.set("errMsg", "getStorageInfo:ok")

                DMPContainerApi.invokeSuccess(callback: callback, param: resultMap)
            }
        }

        return DMPAsyncResult()
    }
}
