import XCTest
@testable import Dimina

final class DMPNativeWebViewPresentationTests: XCTestCase {
    func testWebViewOverridesCustomNavigation() {
        XCTAssertFalse(DMPNativeWebViewPresentation.usesCustomNavigation(requested: true, hasWebView: true))
        XCTAssertFalse(DMPNativeWebViewPresentation.usesCustomNavigation(requested: false, hasWebView: true))
    }

    func testOrdinaryPageKeepsConfiguredNavigation() {
        XCTAssertTrue(DMPNativeWebViewPresentation.usesCustomNavigation(requested: true, hasWebView: false))
        XCTAssertFalse(DMPNativeWebViewPresentation.usesCustomNavigation(requested: false, hasWebView: false))
    }

    func testContentFillsHostViewportIgnoringBoundsOrigin() {
        XCTAssertEqual(
            DMPNativeWebViewPresentation.contentFrame(in: CGRect(x: 12, y: 180, width: 390, height: 700)),
            CGRect(x: 0, y: 0, width: 390, height: 700)
        )
    }

    func testResizedViewportControlsContentSize() {
        XCTAssertEqual(
            DMPNativeWebViewPresentation.contentFrame(in: CGRect(x: 0, y: 0, width: 844, height: 300)),
            CGRect(x: 0, y: 0, width: 844, height: 300)
        )
        XCTAssertEqual(DMPNativeWebViewPresentation.contentFrame(in: .zero), .zero)
    }
}
