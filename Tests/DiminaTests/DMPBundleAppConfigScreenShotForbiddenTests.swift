import XCTest
@testable import Dimina

final class DMPBundleAppConfigScreenShotForbiddenTests: XCTestCase {
    func testPageValueTakesPriorityOverGlobalValue() {
        let config = makeConfig(global: true, page: false)

        XCTAssertFalse(config.isScreenShotForbidden(pagePath: "pages/index/index"))
        XCTAssertEqual(
            config.getPageConfig(pagePath: "pages/index/index")["screenShotForbidden"] as? Bool,
            false
        )
    }

    func testGlobalValueIsUsedWhenPageValueIsMissing() {
        let config = makeConfig(global: true, page: nil)

        XCTAssertTrue(config.isScreenShotForbidden(pagePath: "pages/index/index"))
    }

    func testMissingValuesDefaultToFalse() {
        let config = makeConfig(global: nil, page: nil)

        XCTAssertFalse(config.isScreenShotForbidden(pagePath: "pages/index/index"))
    }

    private func makeConfig(global: Bool?, page: Bool?) -> DMPBundleAppConfig {
        var window: [String: Any] = [:]
        if let global {
            window["screenShotForbidden"] = global
        }

        var pageConfig: [String: Any] = [:]
        if let page {
            pageConfig["screenShotForbidden"] = page
        }

        return DMPBundleAppConfig(data: [
            "app": [
                "pages": ["pages/index/index"],
                "window": window
            ],
            "modules": [
                "pages/index/index": pageConfig
            ]
        ])
    }
}

@MainActor
final class DMPScreenShotProtectionControllerTests: XCTestCase {
    func testProtectionRestoresOriginalLayerHierarchy() {
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let protectedView = UIView(frame: hostView.bounds)
        hostView.addSubview(protectedView)
        let controller = DMPScreenShotProtectionController()

        XCTAssertTrue(controller.setProtected(true, view: protectedView))
        XCTAssertFalse(protectedView.layer.superlayer === hostView.layer)

        controller.reset()

        XCTAssertTrue(protectedView.layer.superlayer === hostView.layer)
    }
}
