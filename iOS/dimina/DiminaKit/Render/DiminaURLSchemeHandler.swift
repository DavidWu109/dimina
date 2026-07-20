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
        guard let resolved = resolvePath(for: url) else {
            urlSchemeTask.didFailWithError(NSError(
                domain: "DiminaErrorDomain",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Resource path is outside the application sandbox"]
            ))
            return
        }
        let path = resolved.path
        let pathKind = resolved.kind

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

    private func resolvePath(for url: URL) -> (path: String, kind: String)? {
        guard url.scheme?.lowercased() == "dimina",
              url.user == nil,
              url.password == nil,
              url.host == nil || url.host?.isEmpty == true else {
            return nil
        }
        let path = url.path

        if path == "/pageFrame.html" {
            guard let resolvedPath = DMPFileUtil.confinedPath(
                rootPath: DMPSandboxManager.sdkMainBundlePath(),
                relativePath: "pageFrame.html"
            ) else { return nil }
            return (resolvedPath, "sdk")
        }

        if path.hasPrefix("/assets/") {
            guard let resolvedPath = DMPFileUtil.confinedPath(
                rootPath: DMPSandboxManager.sdkMainBundlePath(),
                relativePath: path
            ) else { return nil }
            return (resolvedPath, "sdk")
        }

        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: true)
        var resolvedAppId = appId
        var appRelativePath = path
        if let firstComponent = pathComponents.first.map(String.init),
           DiminaURLSchemeHandler.appVersionMap[firstComponent] != nil {
            resolvedAppId = firstComponent
            appRelativePath = pathComponents.dropFirst().joined(separator: "/")
        }
        let resolvedVersion = DiminaURLSchemeHandler.appVersionMap[resolvedAppId] ?? versionCode
        let rootPath = DMPSandboxManager.appBundlePath(
            resolvedAppId,
            versionCode: resolvedVersion
        )
        guard let resolvedPath = DMPFileUtil.confinedPath(
            rootPath: rootPath,
            relativePath: appRelativePath
        ) else { return nil }
        return (resolvedPath, "app(\(resolvedAppId)@v\(resolvedVersion ?? -1))")
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
