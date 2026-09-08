import XCTest
@testable import Dimina

final class DMPNativeWebViewSupportTests: XCTestCase {
    func testParsesDictionaryAndJSONMessagesFromEmbeddedWebView() throws {
        let dictionaryMessage = try XCTUnwrap(
            DMPNativeWebViewMessage.parse([
                "type": "h5SdkAction",
                "target": "service",
                "body": ["parentWebViewId": 7],
            ])
        )
        XCTAssertEqual(dictionaryMessage.type, "h5SdkAction")
        XCTAssertEqual(dictionaryMessage.target, "service")
        XCTAssertEqual(dictionaryMessage.body["parentWebViewId"] as? Int, 7)

        let jsonMessage = try XCTUnwrap(
            DMPNativeWebViewMessage.parse(
                #"{"type":"invokeAPI","target":"webview","body":{"name":"getEnv"}}"#
            )
        )
        XCTAssertEqual(jsonMessage.type, "invokeAPI")
        XCTAssertEqual(jsonMessage.target, "webview")
        XCTAssertEqual(jsonMessage.body["name"] as? String, "getEnv")
    }

    func testRejectsIncompleteEmbeddedWebViewMessages() {
        XCTAssertNil(DMPNativeWebViewMessage.parse(["type": "h5SdkAction"]))
        XCTAssertNil(DMPNativeWebViewMessage.parse("not-json"))
    }

    func testBootstrapIncludesParentContextAndEscapesJavaScriptSeparators() {
        let script = DMPNativeWebViewScript.bootstrap(
            embeddedWebViewId: 11,
            parentWebViewId: 7,
            attributes: [
                "moduleId": "page\u{2028}module",
                "attrs": ["message": "handleMessage"],
            ]
        )

        XCTAssertTrue(script.contains("window.embed_webviewId = 11"))
        XCTAssertTrue(script.contains("\"parentWebViewId\":7"))
        XCTAssertTrue(script.contains("\"message\":\"handleMessage\""))
        XCTAssertTrue(script.contains("page\\u2028module"))
        XCTAssertFalse(script.contains("page\u{2028}module"))
    }

    func testBridgePostsObjectsThroughTheDedicatedMessageHandler() {
        let script = DMPNativeWebViewScript.bridge(handlerName: "embedded-handler")

        XCTAssertTrue(script.contains("messageHandlers[\"embedded-handler\"]"))
        XCTAssertTrue(script.contains("handler.postMessage(message)"))
    }

    func testCallbackTargetsTheJDiminaCallbackRegistry() {
        let script = DMPNativeWebViewScript.callback(
            id: "callback-1",
            arguments: ["data": ["miniprogram": true]]
        )

        XCTAssertTrue(script.contains("DiminaRenderBridge?.onMessage"))
        XCTAssertTrue(script.contains("\"id\":\"callback-1\""))
        XCTAssertTrue(script.contains("\"miniprogram\":true"))
        XCTAssertTrue(script.contains("\"type\":\"triggerCallback\""))
    }
}
