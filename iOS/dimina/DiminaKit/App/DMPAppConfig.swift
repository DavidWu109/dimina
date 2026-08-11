//
//  DMPAppConfig.swift
//  dimina
//
//  Created by Lehem on 2025/4/17.
//

import SwiftUI

/// Display orientation requested by a mini-program page.
///
/// Values match WeChat's `pageOrientation` configuration.
public enum DMPPageOrientation: String, Equatable {
    case portrait
    case landscape
    case auto
}

/// Result returned by the host permission gate.
///
/// Raw values intentionally match the Harmony implementation so hosts can
/// share the same bridge contract across platforms.
public enum DMPPermissionCheckResult: Int {
    case allowed = 0
    case systemDenied = 1
    case userDenied = 2
    case scopeNotConfigured = 3
}

public typealias DMPPermissionCheckHandler = (
    _ scope: String,
    _ completion: @escaping (DMPPermissionCheckResult) -> Void
) -> Void

public typealias DMPAuthSettingHandler = (
    _ completion: @escaping (Result<[String: Bool], Error>) -> Void
) -> Void

public struct DMPAppConfig : Identifiable {
    public var appName: String
    public var appId: String

    public var path: String?
    public var versionCode: Int?
    public var versionName: String?
    public var updateManifestUrl: String?
    public var isDebugMode: Bool = false

    /// Virtual file URL scheme exposed by container APIs. The framework keeps
    /// `difile` as its default; hosts may provide their own compatible scheme.
    public var fileURLScheme: String = DMPFileUtil.DMPFileURLScheme

    public var color: Color?
    public var icon: String?

    /// Called by the container menu and `openSetting` bridge. The host owns
    /// the mini-program settings UI; when absent, Dimina opens iOS Settings.
    public var onMenuSettingClick: (() -> Void)?

    /// Host permission gate used by sensitive bridge APIs. The host is
    /// responsible for system permission, its own consent state, and UI.
    public var checkPermission: DMPPermissionCheckHandler?

    /// Host-provided authorization states used by `getSetting`. Only scopes
    /// that have already been decided should be returned.
    public var getAuthSetting: DMPAuthSettingHandler?

    /// Optional framework lifecycle observer. Dimina emits semantic events and
    /// remains independent of the host's analytics SDK.
    public var trackingHandler: DMPTrackingHandler?

    /// Applies the orientation resolved for the currently visible page.
    /// Dimina invokes this on the main thread. The host remains responsible for
    /// updating its application-level orientation mask and requesting rotation.
    public var setPageOrientation: (@MainActor (_ orientation: DMPPageOrientation) -> Void)?

    /// Restores the host orientation state captured before the mini program
    /// became active. Called when the app is destroyed after having requested
    /// at least one page orientation.
    public var resetPageOrientation: (@MainActor () -> Void)?

    // 符合Identifiable协议的id属性
    public var id: String { appId }

    public init(appName: String, appId: String) {
        self.appName = appName
        self.appId = appId
    }
}
