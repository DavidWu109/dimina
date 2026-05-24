//
//  DiminaURLSchemeHandler.swift
//  dimina
//
//  Created by Lehem on 2025/4/25.
//

import Foundation
import WebKit

@available(iOS 11.0, *)
class DiminaURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let appId: String
    private let versionCode: Int?

    /// appId → versionCode 全局映射，由 DMPApp.launch 时注册
    static var appVersionMap: [String: Int] = [:]

    init(appId: String, versionCode: Int? = nil) {
        self.appId = appId
        self.versionCode = versionCode
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            DMPLog.scheme.error("dimina:// request has no URL")
            urlSchemeTask.didFailWithError(NSError(domain: "DiminaErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        var path = ""
        var pathKind = ""

        if url.path.contains("pageFrame") || url.path.contains("vconsole") {
            path = DMPSandboxManager.sdkMainBundlePath() + url.path
            pathKind = "sdk"
        } else {
            // URL path 格式: /<appId>/main/app.css 或 /main/app.css
            let urlPath = url.path
            let pathComponents = urlPath.split(separator: "/", maxSplits: 2)

            var resolvedAppId = appId
            var resourcePath = urlPath

            // URL 第一段如果在 appVersionMap 中，就是 appId，剥离它
            if pathComponents.count >= 2,
               let firstComponent = pathComponents.first.map(String.init),
               DiminaURLSchemeHandler.appVersionMap[firstComponent] != nil {
                resolvedAppId = firstComponent
                resourcePath = "/" + pathComponents.dropFirst().joined(separator: "/")
            }

            let resolvedVersion = DiminaURLSchemeHandler.appVersionMap[resolvedAppId] ?? versionCode
            path = DMPSandboxManager.appBundlePath(resolvedAppId, versionCode: resolvedVersion) + resourcePath
            pathKind = "app(\(resolvedAppId)@v\(resolvedVersion ?? -1))"
        }

        guard FileManager.default.fileExists(atPath: path) else {
            let parent = (path as NSString).deletingLastPathComponent
            let siblings = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
            DMPLog.scheme.error("not found [\(pathKind)] url=\(url.absoluteString) path=\(path) siblings=\(siblings)")
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

            DMPLog.scheme.debug("ok [\(pathKind)] \(url.path) → \(data.count)B \(mimeType)")
        } catch {
            let ns = error as NSError
            DMPLog.scheme.error("read fail [\(pathKind)] url=\(url.absoluteString) path=\(path) domain=\(ns.domain) code=\(ns.code) msg=\(error.localizedDescription)")
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        DMPLog.scheme.debug("stop \(urlSchemeTask.request.url?.absoluteString ?? "nil")")
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
