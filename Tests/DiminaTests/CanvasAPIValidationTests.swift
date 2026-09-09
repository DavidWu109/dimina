import XCTest
@testable import Dimina

final class CanvasAPIValidationTests: XCTestCase {
    private let pngBase64 = "iVBORw0KGgo="

    func testAcceptsRawBase64FromCurrentJSSDK() {
        XCTAssertEqual(CanvasAPI.canvasBase64(from: pngBase64, fileType: "png"), pngBase64)
    }

    func testKeepsCompatibilityWithFullDataURL() {
        XCTAssertEqual(
            CanvasAPI.canvasBase64(from: "data:image/png;base64,\(pngBase64)", fileType: "png"),
            pngBase64
        )
        XCTAssertEqual(
            CanvasAPI.canvasBase64(from: "DATA:IMAGE/PNG;BASE64,\(pngBase64)", fileType: "png"),
            pngBase64
        )
        XCTAssertEqual(
            CanvasAPI.canvasBase64(from: "data:image/jpeg;base64,/9j/4AAQ", fileType: "jpg"),
            "/9j/4AAQ"
        )
    }

    func testRejectsUnsupportedOrMismatchedDataURL() {
        XCTAssertNil(
            CanvasAPI.canvasBase64(from: "data:text/plain;base64,\(pngBase64)", fileType: "png")
        )
        XCTAssertNil(
            CanvasAPI.canvasBase64(from: "data:image/jpeg;base64,/9j/4AAQ", fileType: "png")
        )
    }

    func testValidatesBase64BeforeDecoding() {
        XCTAssertEqual(CanvasAPI.validatedBase64ByteCount(pngBase64), pngBase64.utf8.count)
        XCTAssertNil(CanvasAPI.validatedBase64ByteCount("iVBORw0KGgo==="))
        XCTAssertNil(CanvasAPI.validatedBase64ByteCount("iVBORw0KGgo=\n"))
        XCTAssertNil(CanvasAPI.validatedBase64ByteCount("图片"))
    }

    func testNormalizesSupportedFileTypesAndRejectsUnknownValues() {
        XCTAssertEqual(CanvasAPI.normalizedFileType(nil), "png")
        XCTAssertEqual(CanvasAPI.normalizedFileType("PNG"), "png")
        XCTAssertEqual(CanvasAPI.normalizedFileType("jpeg"), "jpg")
        XCTAssertNil(CanvasAPI.normalizedFileType("webp"))
    }

    func testImageSignatureMustMatchFileType() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])

        XCTAssertTrue(CanvasAPI.matchesImageType(png, fileType: "png"))
        XCTAssertFalse(CanvasAPI.matchesImageType(png, fileType: "jpg"))
        XCTAssertTrue(CanvasAPI.matchesImageType(jpeg, fileType: "jpg"))
        XCTAssertFalse(CanvasAPI.matchesImageType(jpeg, fileType: "png"))
    }

    func testRejectsAppIdsThatCanEscapeTheSandbox() {
        XCTAssertTrue(CanvasAPI.isValidAppId("echo9vnbMUAoQRt43hxi"))
        XCTAssertFalse(CanvasAPI.isValidAppId("../other-app"))
        XCTAssertFalse(CanvasAPI.isValidAppId("foo/bar"))
        XCTAssertFalse(CanvasAPI.isValidAppId("foo\\bar"))
    }

    func testRawBase64ExportWritesAFileAndReturnsSuccess() throws {
        let api = CanvasAPI()
        let handler = try XCTUnwrap(api.getHandler(for: "saveCanvasTempFile"))
        let appId = "canvas-test-\(UUID().uuidString)"
        let appDirectory = URL(
            fileURLWithPath: DMPSandboxManager.appResourceDirectoryPath(appId: appId)
        ).deletingLastPathComponent()
        defer {
            CanvasAPI.clearApp(appId)
            try? FileManager.default.removeItem(at: appDirectory)
        }
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let param = DMPBridgeParam(value: [
            "dataURL": imageData.base64EncodedString(),
            "fileType": "png",
        ] as [String: Any])
        let env = DMPBridgeEnv(appIndex: 0, appId: appId, webViewId: 0)
        let completed = expectation(description: "canvas export completed")

        _ = handler(param, env) { result, type in
            guard type == .success else { return }
            XCTAssertEqual(result.getString(key: "errMsg"), "canvasToTempFilePath:ok")
            XCTAssertNotNil(result.getString(key: "tempFilePath"))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        let files = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: DMPSandboxManager.appTmpResourceDirectoryPath(appId: appId)),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(files.first)), imageData)
    }

    func testExportRejectsAnAppDirectorySymlinkOutsideTheSandbox() throws {
        let api = CanvasAPI()
        let handler = try XCTUnwrap(api.getHandler(for: "saveCanvasTempFile"))
        let appId = "canvas-symlink-\(UUID().uuidString)"
        let appURL = URL(
            fileURLWithPath: DMPSandboxManager.sandboxPath(),
            isDirectory: true
        ).appendingPathComponent(appId, isDirectory: true)
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: appURL, withDestinationURL: outsideURL)
        defer {
            CanvasAPI.clearApp(appId)
            try? FileManager.default.removeItem(at: appURL)
            try? FileManager.default.removeItem(at: outsideURL)
        }
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let param = DMPBridgeParam(value: [
            "dataURL": imageData.base64EncodedString(),
            "fileType": "png",
        ] as [String: Any])
        let env = DMPBridgeEnv(appIndex: 0, appId: appId, webViewId: 0)
        let completed = expectation(description: "unsafe export rejected")

        _ = handler(param, env) { _, type in
            guard type == .fail else { return }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: outsideURL.appendingPathComponent("resources/tmp").path
            )
        )
    }
}
