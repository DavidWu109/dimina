//
//  DMPAppConfig.swift
//  dimina
//
//  Created by Lehem on 2025/4/17.
//

import SwiftUI

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

    // 符合Identifiable协议的id属性
    public var id: String { appId }

    public init(appName: String, appId: String) {
        self.appName = appName
        self.appId = appId
    }
}
