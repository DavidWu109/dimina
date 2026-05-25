//
//  DiminaURLSchemeHandler.swift
//  dimina
//
//  Created by Lehem on 2025/5/16.
//

import Foundation
import WebKit

@available(iOS 11.0, *)
public class DifileURLSchemeHandler: NSObject, WKURLSchemeHandler {
    public var appId: String

    public init(appId: String) {
        self.appId = appId
        super.init()
    }
    
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            DMPLog.scheme.error("difile:// request has no URL")
            urlSchemeTask.didFailWithError(NSError(domain: "DiminaErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        guard let path = DMPFileUtil.sandboxPathFromVPath(from: url.absoluteString, appId: self.appId) else {
            DMPLog.scheme.error("difile cannot resolve vpath url=\(url.absoluteString) appId=\(appId)")
            urlSchemeTask.didFailWithError(NSError(domain: "DiminaErrorDomain", code: 404, userInfo: [NSLocalizedDescriptionKey: "无法获取资源路径"]))
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            DMPLog.scheme.error("difile not found url=\(url.absoluteString) path=\(path)")
            urlSchemeTask.didFailWithError(NSError(domain: "DiminaErrorDomain", code: 404, userInfo: [NSLocalizedDescriptionKey: "Resource does not exist: \(path)"]))
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let mimeType = mimeTypeForPath(path)
            let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "UTF-8")

            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()

            DMPLog.scheme.debug("difile ok \(url.path) → \(data.count)B \(mimeType)")
        } catch {
            let ns = error as NSError
            DMPLog.scheme.error("difile read fail url=\(url.absoluteString) path=\(path) domain=\(ns.domain) code=\(ns.code) msg=\(error.localizedDescription)")
            urlSchemeTask.didFailWithError(error)
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        DMPLog.scheme.debug("difile stop \(urlSchemeTask.request.url?.absoluteString ?? "nil")")
    }
    
    // Get MIME type based on file path
    private func mimeTypeForPath(_ path: String) -> String {
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        
        switch pathExtension {
        case "html", "htm":
            return "text/html"
        case "css":
            return "text/css"
        case "js":
            return "application/javascript"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "json":
            return "application/json"
        default:
            return "application/octet-stream"
        }
    }
}
