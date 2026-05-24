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

    public var color: Color?
    public var icon: String?

    // 符合Identifiable协议的id属性
    public var id: String { appId }

    public init(appName: String, appId: String) {
        self.appName = appName
        self.appId = appId
    }
}
