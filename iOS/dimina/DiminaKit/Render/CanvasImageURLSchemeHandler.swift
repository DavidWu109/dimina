//
//  CanvasImageURLSchemeHandler.swift
//  dimina
//

import Foundation
import WebKit

/// Loads remote canvas images outside WebKit's custom-scheme CORS model.
///
/// A render page uses the `dimina://` origin. Some image servers serialize
/// that origin incorrectly in `Access-Control-Allow-Origin`, so loading an
/// image with `crossOrigin = "anonymous"` fails before it can be drawn.
/// Keeping the load anonymous while proxying it through a host-owned scheme
/// also keeps the canvas exportable.
final class CanvasImageURLSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "diminacanvasimage"

    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let proxyURL = urlSchemeTask.request.url,
              let remoteURL = Self.remoteURL(from: proxyURL) else {
            urlSchemeTask.didFailWithError(Self.error(
                code: 400,
                message: "Invalid canvas image URL"
            ))
            return
        }

        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.cachePolicy = .returnCacheDataElseLoad

        let dataTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self, self.removeTask(identifier) != nil else { return }

            if let error {
                urlSchemeTask.didFailWithError(error)
                return
            }
            guard let data,
                  let httpResponse = response as? HTTPURLResponse else {
                urlSchemeTask.didFailWithError(Self.error(
                    code: 502,
                    message: "Canvas image response is empty"
                ))
                return
            }

            var headers: [String: String] = [
                "Access-Control-Allow-Origin": "*",
                "Content-Length": String(data.count),
            ]
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                headers["Content-Type"] = contentType
            }
            if let cacheControl = httpResponse.value(forHTTPHeaderField: "Cache-Control") {
                headers["Cache-Control"] = cacheControl
            }

            guard let proxyResponse = HTTPURLResponse(
                url: proxyURL,
                statusCode: httpResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                urlSchemeTask.didFailWithError(Self.error(
                    code: 502,
                    message: "Failed to create canvas image response"
                ))
                return
            }

            urlSchemeTask.didReceive(proxyResponse)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }

        storeTask(dataTask, identifier: identifier)
        dataTask.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        removeTask(identifier)?.cancel()
    }

    private static func remoteURL(from proxyURL: URL) -> URL? {
        guard proxyURL.scheme?.lowercased() == scheme,
              proxyURL.host?.lowercased() == "proxy",
              proxyURL.user == nil,
              proxyURL.password == nil,
              let components = URLComponents(url: proxyURL, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let remoteURL = URL(string: value),
              ["http", "https"].contains(remoteURL.scheme?.lowercased() ?? ""),
              remoteURL.host != nil,
              remoteURL.user == nil,
              remoteURL.password == nil else {
            return nil
        }
        return remoteURL
    }

    private func storeTask(_ task: URLSessionDataTask, identifier: ObjectIdentifier) {
        lock.lock()
        tasks[identifier] = task
        lock.unlock()
    }

    @discardableResult
    private func removeTask(_ identifier: ObjectIdentifier) -> URLSessionDataTask? {
        lock.lock()
        defer { lock.unlock() }
        return tasks.removeValue(forKey: identifier)
    }

    private static func error(code: Int, message: String) -> NSError {
        NSError(
            domain: "DiminaCanvasImageErrorDomain",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
