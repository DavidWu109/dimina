import XCTest
import UIKit
@testable import Dimina

@MainActor
final class DMPScreenShotProtectionControllerTests: XCTestCase {
    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.isHidden = false
        return window
    }

    func testRepeatedEnableAndRestorePreserveContentHierarchy() throws {
        let window = makeWindow()
        defer { window.isHidden = true }
        let content = try XCTUnwrap(window.rootViewController?.view)
        let parent = try XCTUnwrap(window.layer.superlayer)
        let contentParent = content.superview
        let controller = DMPScreenShotProtectionController()
        XCTAssertTrue(controller.setProtected(true, view: content))
        let secureLayer = window.layer.superlayer
        XCTAssertFalse(secureLayer === parent)
        XCTAssertTrue(content.superview === contentParent)
        XCTAssertTrue(controller.setProtected(true, view: content))
        XCTAssertTrue(window.layer.superlayer === secureLayer)
        controller.reset()
        controller.reset()
        XCTAssertTrue(window.layer.superlayer === parent)
        XCTAssertTrue(controller.setProtected(true, view: content))
        XCTAssertTrue(controller.setProtected(false, view: content))
        XCTAssertTrue(window.layer.superlayer === parent)
    }

    func testFailedReplacementPreservesOldProtectionAndCanRetry() throws {
        let window = makeWindow()
        defer { window.isHidden = true }
        let content = try XCTUnwrap(window.rootViewController?.view)
        let parent = try XCTUnwrap(window.layer.superlayer)
        let next = UIView()
        let controller = DMPScreenShotProtectionController()
        XCTAssertTrue(controller.setProtected(true, view: content))
        let secureLayer = window.layer.superlayer
        XCTAssertFalse(controller.setProtected(true, view: next))
        XCTAssertTrue(window.layer.superlayer === secureLayer)
        let nextWindow = makeWindow()
        defer { nextWindow.isHidden = true }
        let nextParent = try XCTUnwrap(nextWindow.layer.superlayer)
        nextWindow.rootViewController?.view.addSubview(next)
        XCTAssertTrue(controller.setProtected(true, view: next))
        XCTAssertTrue(window.layer.superlayer === parent)
        XCTAssertFalse(nextWindow.layer.superlayer === nextParent)
        controller.reset()
        XCTAssertTrue(nextWindow.layer.superlayer === nextParent)
    }

    func testDetachedViewFailsWithoutChangingHierarchy() {
        let view = UIView()
        let controller = DMPScreenShotProtectionController()
        XCTAssertFalse(controller.setProtected(true, view: view))
        XCTAssertNil(view.layer.superlayer)
        XCTAssertTrue(controller.setProtected(false, view: view))
    }
}
