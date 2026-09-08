//
//  DMPTrackingEvent.swift
//  Dimina
//

import Foundation

/// Stable startup stages exposed to a host observability implementation.
/// Dimina reports semantic stages only; the host decides how they map to its
/// analytics product and must not depend on framework error descriptions.
public enum DMPTrackingStage: String {
    case bundle
    case service
    case render
    case page
    case unknown
}

/// Framework lifecycle signals used by a host to build launch and page metrics.
public enum DMPTrackingEvent {
    /// Vue has committed the page's first render. This is intentionally later
    /// than WKWebView navigation completion and resource loading.
    case pageContentRendered(path: String, webViewId: Int)

    /// The native page became visible. A new visit identifier is generated for
    /// every appearance so revisiting the same path is still a new page view.
    case pageDidBecomeVisible(path: String, webViewId: Int, visitId: String, query: [String: Any] = [:])

    /// Clears a pending visibility signal when a page leaves the screen before
    /// its first render completes.
    case pageDidBecomeHidden(webViewId: Int)

    /// A deterministic framework startup failure. Raw error text and stacks are
    /// deliberately excluded from this contract.
    case loadFailed(stage: DMPTrackingStage, code: String?)

    /// The app instance has been destroyed. Emitted at most once per instance.
    case destroyed
}

public typealias DMPTrackingHandler = (DMPTrackingEvent) -> Void
