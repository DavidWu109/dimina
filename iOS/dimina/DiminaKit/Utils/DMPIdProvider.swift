//
//  DMPIdProvider.swift
//  dimina
//
//  Created by Lehem on 2025/4/23.
//

import Foundation

public final class DMPIdProvider {
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var stackId: Int = 0
        private var webViewId: Int = 0

        func currentStackId() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return stackId
        }

        func increaseStackId() {
            lock.lock()
            stackId += 1
            lock.unlock()
        }

        func generateStackId() -> Int {
            lock.lock()
            defer { lock.unlock() }
            stackId += 1
            return stackId
        }

        func currentWebViewId() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return webViewId
        }

        func increaseWebViewId() {
            lock.lock()
            webViewId += 1
            lock.unlock()
        }

        func generateWebViewId() -> Int {
            lock.lock()
            defer { lock.unlock() }
            webViewId += 1
            return webViewId
        }
    }

    private static let state = State()
    
    // 获取当前的栈ID
    public static var stackId: Int {
        return state.currentStackId()
    }
    
    // 增加栈ID计数
    public static func increaseStackId() {
        state.increaseStackId()
    }
    
    // 生成新的栈ID并返回
    public static func generateStackId() -> Int {
        return state.generateStackId()
    }
    
    // 获取当前的WebView ID
    public static var webViewId: Int {
        return state.currentWebViewId()
    }
    
    // 生成新的WebView ID并返回
    public static func generateWebViewId() -> Int {
        return state.generateWebViewId()
    }
    
    // 增加WebView ID计数
    public static func increaseWebViewId() {
        state.increaseWebViewId()
    }
}
