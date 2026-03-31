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

    static func writeLog(_ msg: String) {
        let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("dimina_scheme.log")
        let line = "\(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    init(appId: String, versionCode: Int? = nil) {
        self.appId = appId
        self.versionCode = versionCode
        super.init()
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "DiminaErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        print("🔗 DiminaURLSchemeHandler 开始处理请求:")
        print("  📱 原始URL: \(url.absoluteString)")
        print("  📱 URL Scheme: \(url.scheme ?? "无")")
        print("  📱 URL Host: \(url.host ?? "无")")
        print("  📱 URL Path: \(url.path)")
        print("  📱 URL Query: \(url.query ?? "无")")
        print("  📱 URL Fragment: \(url.fragment ?? "无")")
        
        var path = ""
        var pathType = ""
        
        if url.path.contains("pageFrame") || url.path.contains("vconsole") {
            path = DMPSandboxManager.sdkMainBundlePath() + url.path
            pathType = "SDK主Bundle路径"
        } else {
            // 应用资源：URL path 可能以 /appId/ 开头（如 /echonxINllZW44kgtMW9/main/app.css）
            // 也可能不带 appId（如 /main/app.css）
            let resolvedVersion = versionCode ?? DiminaURLSchemeHandler.appVersionMap[appId]
            let urlPath = url.path
            if urlPath.hasPrefix("/\(appId)/") {
                // URL 已包含 appId，只需加 versionCode
                if let version = resolvedVersion {
                    path = DMPSandboxManager.sandboxPath() + "/\(appId)/\(version)" + urlPath.dropFirst(appId.count + 1)
                } else {
                    path = DMPSandboxManager.sandboxPath() + urlPath
                }
            } else {
                // URL 不含 appId，用 appBundlePath
                path = DMPSandboxManager.appBundlePath(appId, versionCode: resolvedVersion) + urlPath
            }
            pathType = "应用Bundle路径(appId=\(appId), version=\(resolvedVersion ?? -1))"
        }
        
        print("  🔄 路径转换过程:")
        print("    - 判断类型: \(url.path.contains("pageFrame") || url.path.contains("vconsole") ? "SDK资源" : "应用资源")")
        print("    - 最终路径: \(path)")
        print("    - 路径类型: \(pathType)")
        print("    - 原始路径: \(url.path)")
        print("    - 是否包含pageFrame: \(url.path.contains("pageFrame"))")
        print("    - 是否包含vconsole: \(url.path.contains("vconsole"))")
        
        print("📦 DiminaURLSchemeHandler loading resource: \(path)")
        // 写日志到文件
        Self.writeLog("REQ: \(url.absoluteString) → \(path) [\(pathType)] exists=\(FileManager.default.fileExists(atPath: path))")

        // Check if the file exists
        guard FileManager.default.fileExists(atPath: path) else {
            let errorMessage = "Resource does not exist: \(path)"
            print("❌ \(errorMessage)")
            Self.writeLog("❌ NOT FOUND: \(path)")
            print("  🔍 文件不存在检查:")
            print("    - 检查路径: \(path)")
            print("    - 路径类型: \(pathType)")
            
            // 尝试列出父目录内容以帮助调试
            let parentPath = (path as NSString).deletingLastPathComponent
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: parentPath)
                print("    - 父目录内容: \(contents)")
            } catch {
                print("    - 无法读取父目录: \(error.localizedDescription)")
            }
            
            urlSchemeTask.didFailWithError(NSError(domain: "DiminaErrorDomain", code: 404, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
            return
        }
        
        do {
            // Read file data
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            
            // Set response headers
            let mimeType = mimeTypeForPath(path)
            let headers = ["Content-Type": mimeType, "Access-Control-Allow-Origin": "*"]
            let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "UTF-8")
            
            print("  📊 文件信息:")
            print("    - 文件大小: \(data.count) bytes")
            print("    - MIME类型: \(mimeType)")
            print("    - 编码: UTF-8")
            
            // Return response and data
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            
            print("✅ Resource loaded successfully: \(url.absoluteString)")
            print("  🎯 加载完成:")
            print("    - 原始URL: \(url.absoluteString)")
            print("    - 本地路径: \(path)")
            print("    - 路径类型: \(pathType)")
            print("    - 文件大小: \(data.count) bytes")
        } catch {
            print("❌ Resource loading failed: \(error.localizedDescription)")
            print("  🔍 加载失败详情:")
            print("    - 错误类型: \(type(of: error))")
            print("    - 错误描述: \(error.localizedDescription)")
            print("    - 错误域: \((error as NSError).domain)")
            print("    - 错误代码: \((error as NSError).code)")
            if let userInfo = (error as NSError).userInfo as? [String: Any] {
                print("    - 用户信息: \(userInfo)")
            }
            urlSchemeTask.didFailWithError(error)
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Cleanup operations when the task is stopped
        print("🛑 Stopping resource loading")
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
