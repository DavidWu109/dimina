//
//  DMPPageNavigationControlsProvider.swift
//  dimina
//

import UIKit

/// The native action represented by the navigation bar's leading control.
public enum DMPPageLeadingAction: Equatable {
    case hidden
    case back
    case close
}

/// Immutable page information and host actions exposed to navigation controls.
public struct DMPPageNavigationControlsContext {
    public let appId: String
    public let appName: String
    public let pagePath: String
    public let query: [String: Any]
    public let back: () -> Void
    public let home: () -> Void
    public let close: () -> Void

    init(
        appId: String,
        appName: String,
        pagePath: String,
        query: [String: Any],
        back: @escaping () -> Void,
        home: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.appId = appId
        self.appName = appName
        self.pagePath = pagePath
        self.query = query
        self.back = back
        self.home = home
        self.close = close
    }
}

/// Declarative navigation state applied to host-provided controls.
public struct DMPPageNavigationControlsStyle {
    public let leadingAction: DMPPageLeadingAction
    public let showsHome: Bool
    public let foregroundColor: UIColor

    init(
        leadingAction: DMPPageLeadingAction,
        showsHome: Bool,
        foregroundColor: UIColor
    ) {
        self.leadingAction = leadingAction
        self.showsHome = showsHome
        self.foregroundColor = foregroundColor
    }
}

/// Supplies host UI for the navigation bar's leading and Home controls.
///
/// Dimina owns page-stack semantics and layout. The host owns component choice
/// and visual styling, without receiving the page controller itself.
@MainActor
public protocol DMPPageNavigationControlsProvider: AnyObject {
    func makeNavigationControls(for context: DMPPageNavigationControlsContext) -> UIView?

    func updateNavigationControls(
        _ controlsView: UIView,
        style: DMPPageNavigationControlsStyle
    )
}

public extension DMPPageNavigationControlsProvider {
    func updateNavigationControls(
        _ controlsView: UIView,
        style: DMPPageNavigationControlsStyle
    ) {}
}
