//
//  NetworkAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import Alamofire

/**
 * Network API implementation
 * Provides bridge methods for network operations compatible with WeChat Mini Program API
 * Handles HTTP requests, file downloads, and file uploads
 * Uses DMPNetwork for underlying network operations
 */
public class NetworkAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)

        register("request", handler: request)
        register("downloadFile", handler: downloadFile)
        register("uploadFile", handler: uploadFile)
    }

    private func request(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        let url = param.getString(key: "url") ?? ""
        let data = param.get("data")
        let headerDict = param.getDictionary(key: "header")
        let timeout = param.getDouble(key: "timeout") ?? 60000
        let methodStr = param.getString(key: "method")?.uppercased() ?? "GET"
        let dataType = param.getString(key: "dataType") ?? "json"

        guard let _ = URL(string: url) else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "request:fail invalid url")
            return DMPAsyncResult()
        }

        var header: [String: String]?
        if let headerDict = headerDict {
            header = headerDict.reduce(into: [String: String]()) { (result, keyValue) in
                if let key = keyValue.key as? String,
                   let value = keyValue.value as? String {
                    result[key] = value
                }
            }
        }

        let method = HTTPMethod(rawValue: methodStr)

        DMPNetwork.shared.request(
            url: url,
            method: method,
            data: data,
            header: header,
            timeout: timeout / 1000,
            dataType: dataType,
            success: { (responseData, statusCode, responseHeaders, cookies) in
                let resultMap = DMPMap()

                if let data = responseData {
                    if dataType.lowercased() == "json" {
                        do {
                            let jsonObject = try JSONSerialization.jsonObject(with: data)
                            resultMap.set("data", jsonObject)
                        } catch {
                            let dataString = String(data: data, encoding: .utf8) ?? ""
                            resultMap.set("data", dataString)
                        }
                    } else {
                        let dataString = String(data: data, encoding: .utf8) ?? ""
                        resultMap.set("data", dataString)
                    }
                }

                resultMap.set("statusCode", statusCode)
                resultMap.set("header", responseHeaders)

                if !cookies.isEmpty {
                    resultMap.set("cookies", cookies)
                }

                DMPContainerApi.invokeSuccess(callback: callback, param: resultMap)
            },
            fail: { (errMsg, errno) in
                let errorMap = DMPMap()
                errorMap.set("errMsg", errMsg)

                if let errno = errno {
                    errorMap.set("errno", errno)
                }

                DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: errMsg)
            },
            complete: {
                DMPContainerApi.invokeCallback(callback, type: .complete, param: nil)
            }
        )

        return DMPAsyncResult()
    }

    private func downloadFile(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        let url = param.getString(key: "url") ?? ""
        let headerDict = param.getDictionary(key: "header")
        let timeout = param.getDouble(key: "timeout") ?? 60000
        let filePath = param.getString(key: "filePath")

        guard let _ = URL(string: url) else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "downloadFile:fail invalid url")
            return DMPAsyncResult()
        }

        var header: [String: String]?
        if let headerDict = headerDict {
            header = headerDict.reduce(into: [String: String]()) { (result, keyValue) in
                if let key = keyValue.key as? String,
                   let value = keyValue.value as? String {
                    result[key] = value
                }
            }
        }

        DMPNetwork.shared.downloadFile(
            url: url,
            header: header,
            timeout: timeout / 1000,
            filePath: filePath,
            success: { (savedPath, statusCode) in
                let resultMap = DMPMap()

                if filePath != nil {
                    resultMap.set("filePath", savedPath)
                } else {
                    resultMap.set("tempFilePath", savedPath)
                }

                resultMap.set("statusCode", statusCode)

                DMPContainerApi.invokeSuccess(callback: callback, param: resultMap)
            },
            fail: { (errMsg) in
                DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: errMsg)
            },
            complete: {
                DMPContainerApi.invokeCallback(callback, type: .complete, param: nil)
            }
        )

        return DMPAsyncResult()
    }

    private func uploadFile(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> DMPAPIResult {
        let param = param.getMap()
        let url = param.getString(key: "url") ?? ""
        let rawFilePath = param.getString(key: "filePath") ?? ""
        let name = param.getString(key: "name") ?? ""
        let headerDict = param.getDictionary(key: "header")
        let formDataDict = param.getDictionary(key: "formData")
        let timeout = param.getDouble(key: "timeout") ?? 60000

        let filePath = DMPFileUtil.sandboxPathFromVPath(from: rawFilePath, appId: env.appId) ?? rawFilePath
        print("📤 [uploadFile] url=\(url), rawFilePath=\(rawFilePath), resolved=\(filePath), name=\(name)")

        if url.isEmpty || filePath.isEmpty || name.isEmpty {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "uploadFile:fail missing required parameters")
            return DMPAsyncResult()
        }

        guard let _ = URL(string: url) else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "uploadFile:fail invalid url")
            return DMPAsyncResult()
        }

        if !FileManager.default.fileExists(atPath: filePath) {
            print("📤 [uploadFile] FAIL: file does not exist at \(filePath)")
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "uploadFile:fail file does not exist")
            return DMPAsyncResult()
        }
        print("📤 [uploadFile] params OK, starting upload...")

        var header: [String: String]?
        if let headerDict = headerDict {
            header = headerDict.reduce(into: [String: String]()) { (result, keyValue) in
                if let key = keyValue.key as? String,
                   let value = keyValue.value as? String {
                    result[key] = value
                }
            }
        }

        var formData: [String: Any]?
        if let formDataDict = formDataDict {
            formData = formDataDict.reduce(into: [String: Any]()) { (result, keyValue) in
                if let key = keyValue.key as? String {
                    result[key] = keyValue.value
                }
            }
        }

        DMPNetwork.shared.uploadFile(
            url: url,
            filePath: filePath,
            name: name,
            header: header,
            formData: formData,
            timeout: timeout / 1000,
            success: { (responseData, statusCode) in
                let resultMap = DMPMap()

                resultMap.set("data", responseData)
                resultMap.set("statusCode", statusCode)

                DMPContainerApi.invokeSuccess(callback: callback, param: resultMap)
            },
            fail: { (errMsg) in
                DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: errMsg)
            },
            complete: {
                DMPContainerApi.invokeCallback(callback, type: .complete, param: nil)
            }
        )

        return DMPAsyncResult()
    }
}
