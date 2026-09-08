//
//  DMPNativeWebViewSupport.swift
//  dimina
//

import CoreGraphics
import Foundation

enum DMPNativeWebViewPresentation {
    static func usesCustomNavigation(requested: Bool, hasWebView: Bool) -> Bool {
        requested && !hasWebView
    }

    /// The host viewport already excludes the standard navigation bar. Business
    /// rect, CSS offsets and outer-page scroll must not affect embedded WebViews.
    static func contentFrame(in viewportBounds: CGRect) -> CGRect {
        CGRect(origin: .zero, size: viewportBounds.size)
    }
}

struct DMPNativeWebViewMessage {
    let type: String
    let body: [String: Any]
    let target: String

    static func parse(_ value: Any) -> DMPNativeWebViewMessage? {
        let object: Any
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            object = decoded
        } else {
            object = value
        }

        guard
            let message = object as? [String: Any],
            let type = message["type"] as? String,
            !type.isEmpty,
            let body = message["body"] as? [String: Any],
            let target = message["target"] as? String,
            !target.isEmpty
        else {
            return nil
        }

        return DMPNativeWebViewMessage(type: type, body: body, target: target)
    }
}

enum DMPNativeWebViewScript {
    static func bridge(handlerName: String) -> String {
        let encodedHandlerName = jsonString(handlerName)
        return """
        (function() {
            window.DiminaRenderBridge = window.DiminaRenderBridge || {};
            window.DiminaRenderBridge.invoke = function(message) {
                var handler = window.webkit && window.webkit.messageHandlers &&
                    window.webkit.messageHandlers[\(encodedHandlerName)];
                if (!handler) {
                    console.error('DiminaRenderBridge.invoke: native handler not ready');
                    return;
                }
                handler.postMessage(message);
            };
        })();
        """
    }

    static func bootstrap(
        embeddedWebViewId: Int,
        parentWebViewId: Int,
        attributes: [String: Any]
    ) -> String {
        let metadata: [String: Any] = [
            "moduleId": attributes["moduleId"] as? String ?? "",
            "attrs": attributes["attrs"] as? [String: Any] ?? [:],
            "parentWebViewId": parentWebViewId,
        ]
        return """
        window.embed_webviewId = \(embeddedWebViewId);
        window.embed_webview_data = \(jsonObject(metadata));
        """
    }

    static func callback(id: String, arguments: [String: Any]) -> String {
        let message: [String: Any] = [
            "type": "triggerCallback",
            "body": [
                "id": id,
                "args": arguments,
            ],
        ]
        return "window.DiminaRenderBridge?.onMessage?.(\(jsonObject(message)));"
    }

    private static func jsonString(_ value: String) -> String {
        jsonObject(value)
    }

    private static func jsonObject(_ value: Any) -> String {
        guard
            JSONSerialization.isValidJSONObject([value]),
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            var json = String(data: data, encoding: .utf8)
        else {
            return "null"
        }
        json.removeFirst()
        json.removeLast()
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
