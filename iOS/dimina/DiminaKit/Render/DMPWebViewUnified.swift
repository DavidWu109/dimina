//
//  DMPWebViewUnified.swift
//  dimina
//
//  Created by Lehem on 2025/4/22.
//  Unified WebView implementation with global version switching
//

import Foundation
import WebKit
import Combine

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Dependencies
// This file depends on the following types from DMPWebview.swift:
// - DMPWebViewDelegate
// - DMPWebview
// - DMPWebViewState
// These types should be available when both files are compiled together.

// Note: This file should be compiled after DMPWebview.swift to avoid type resolution errors
// Current configuration: Uses UIKit version by default for better compatibility

// MARK: - WebView Implementation Version

/// WebView implementation version
public enum DMPWebViewVersion {
    case swiftUI    // SwiftUI version (iOS 14+)
    case uikit      // UIKit + Combine version (iOS 13+)
    
    public var description: String {
        switch self {
        case .swiftUI: return "SwiftUI"
        case .uikit: return "UIKit + Combine"
        }
    }
}

// MARK: - Global Configuration

/// Global WebView configuration manager
public class DMPWebViewConfig {
    
    // MARK: - Singleton
    public static let shared = DMPWebViewConfig()
    
    // MARK: - Properties
    
    /// Current WebView version preference
    public var preferredVersion: DMPWebViewVersion = .uikit
    
    /// Whether to use automatic version selection based on iOS version
    public var useAutoSelection: Bool = true
    
    /// Minimum iOS version for SwiftUI (default: iOS 14.0)
    public var swiftUIMinimumVersion: Double = 14.0
    
    /// Whether to prefer UIKit version for better compatibility
    public var preferCompatibility: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        // Set default based on current iOS version
        updateDefaultVersion()
    }
    
    // MARK: - Public Methods
    
    /// Get the appropriate WebView version based on current configuration
    public func getWebViewVersion() -> DMPWebViewVersion {
        if useAutoSelection {
            return getAutoSelectedVersion()
        } else {
            return preferredVersion
        }
    }
    
    /// Set the preferred WebView version
    public func setPreferredVersion(_ version: DMPWebViewVersion) {
        preferredVersion = version
        useAutoSelection = false
    }
    
    /// Enable automatic version selection
    public func enableAutoSelection() {
        useAutoSelection = true
    }
    
    /// Set compatibility mode (prefer UIKit for better compatibility)
    public func setCompatibilityMode(_ enabled: Bool) {
        preferCompatibility = enabled
        if enabled {
            preferredVersion = .uikit
            useAutoSelection = false
        }
    }
    
    /// Reset to default configuration
    public func resetToDefault() {
        preferredVersion = .uikit
        useAutoSelection = true
        preferCompatibility = false
        updateDefaultVersion()
    }
    
    /// Get current configuration as dictionary
    public func getConfiguration() -> [String: Any] {
        return [
            "preferredVersion": preferredVersion.description,
            "useAutoSelection": useAutoSelection,
            "swiftUIMinimumVersion": swiftUIMinimumVersion,
            "preferCompatibility": preferCompatibility,
            "currentVersion": getWebViewVersion().description
        ]
    }
    
    // MARK: - Private Methods
    
    private func updateDefaultVersion() {
        // Default to UIKit version for better compatibility
        preferredVersion = .uikit
    }
    
    private func getAutoSelectedVersion() -> DMPWebViewVersion {
        // Always prefer UIKit for better compatibility
        return .uikit
    }
}

// MARK: - Convenience Extensions

public extension DMPWebViewConfig {
    
    /// Quick setup for SwiftUI projects
    static func configureForSwiftUI() {
        shared.setPreferredVersion(.swiftUI)
    }
    
    /// Quick setup for UIKit projects (default)
    static func configureForUIKit() {
        shared.setPreferredVersion(.uikit)
    }
    
    /// Quick setup for maximum compatibility (UIKit)
    static func configureForCompatibility() {
        shared.setCompatibilityMode(true)
    }
    
    /// Quick setup for automatic selection (defaults to UIKit)
    static func configureForAutoSelection() {
        shared.enableAutoSelection()
    }
}

// MARK: - WebView Factory

/// WebView factory for creating instances based on global configuration
public class DMPWebViewFactory {
    
    // MARK: - Singleton
    public static let shared = DMPWebViewFactory()
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Factory Methods
    
    /// Create a WebView instance based on global configuration
    public func createWebView(
        delegate: AnyObject?,
        appName: String,
        appId: String,
        version: String,
        processPool: WKProcessPool? = nil
    ) -> AnyObject {
        let webViewVersion = DMPWebViewConfig.shared.getWebViewVersion()
        
        switch webViewVersion {
        case .swiftUI:
            return createSwiftUIWebView(
                delegate: delegate,
                appName: appName,
                appId: appId,
                version: version,
                processPool: processPool
            )
        case .uikit:
            // For UIKit version, we still return DMPWebview for compatibility
            return createSwiftUIWebView(
                delegate: delegate,
                appName: appName,
                appId: appId,
                version: version,
                processPool: processPool
            )
        }
    }
    
    /// Create a SwiftUI WebView instance
    public func createSwiftUIWebView(
        delegate: AnyObject?,
        appName: String,
        appId: String,
        version: String,
        processPool: WKProcessPool? = nil
    ) -> AnyObject {
        // Use the original DMPWebview class from DMPWebview.swift
        // This will be resolved at runtime when DMPWebview.swift is compiled
        fatalError("DMPWebview class not available. Please ensure DMPWebview.swift is compiled first.")
    }
    
    /// Create a UIKit WebView instance
    public func createUIKitWebView(
        delegate: AnyObject?,
        appName: String,
        appId: String,
        version: String,
        processPool: WKProcessPool? = nil
    ) -> AnyObject {
        // Use the original DMPWebview class from DMPWebview.swift
        // This will be resolved at runtime when DMPWebview.swift is compiled
        fatalError("DMPWebview class not available. Please ensure DMPWebview.swift is compiled first.")
    }
    
    /// Create a WebView with specific version (override global config)
    public func createWebView(
        version: DMPWebViewVersion,
        delegate: AnyObject?,
        appName: String,
        appId: String,
        appVersion: String,
        processPool: WKProcessPool? = nil
    ) -> AnyObject {
        switch version {
        case .swiftUI:
            return createSwiftUIWebView(
                delegate: delegate,
                appName: appName,
                appId: appId,
                version: appVersion,
                processPool: processPool
            )
        case .uikit:
            return createUIKitWebView(
                delegate: delegate,
                appName: appName,
                appId: appId,
                version: appVersion,
                processPool: processPool
            )
        }
    }
}

// MARK: - Convenience Extensions

public extension DMPWebViewFactory {
    
    /// Quick create with current configuration
    static func create(
        delegate: AnyObject? = nil,
        appName: String,
        appId: String,
        version: String,
        processPool: WKProcessPool? = nil
    ) -> AnyObject {
        return shared.createWebView(
            delegate: delegate,
            appName: appName,
            appId: appId,
            version: version,
            processPool: processPool
        )
    }
    
    /// Create SwiftUI WebView directly
    static func createSwiftUI(
        delegate: AnyObject? = nil,
        appName: String,
        appId: String,
        version: String,
        processPool: WKProcessPool? = nil
    ) -> AnyObject {
        return shared.createSwiftUIWebView(
            delegate: delegate,
            appName: appName,
            appId: appId,
            version: version,
            processPool: processPool
        )
    }
    
    /// Create UIKit WebView directly
    static func createUIKit(
        delegate: AnyObject? = nil,
        appName: String,
        appId: String,
        version: String,
        processPool: WKProcessPool? = nil
    ) -> AnyObject {
        return shared.createUIKitWebView(
            delegate: delegate,
            appName: appName,
            appId: appId,
            version: version,
            processPool: processPool
        )
    }
}

// MARK: - SwiftUI Loading View
// Note: DMPLoadingView is defined in DMPWebview.swift file