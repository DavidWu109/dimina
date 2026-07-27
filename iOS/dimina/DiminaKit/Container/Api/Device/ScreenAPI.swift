import Foundation
import UIKit

/** WeChat-compatible user screenshot event bridge. */
public final class ScreenAPI: DMPContainerApi {
    private static func bridge(
        _ name: String,
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        ScreenAPIManager.shared.handle(
            name: name,
            data: param.getMap(),
            appId: env.appId,
            callback: callback
        )
        return DMPAsyncResult()
    }

    @BridgeMethod("onUserCaptureScreen")
    var onUserCaptureScreen: DMPBridgeMethodHandler = {
        bridge("onUserCaptureScreen", $0, $1, $2)
    }

    @BridgeMethod("offUserCaptureScreen")
    var offUserCaptureScreen: DMPBridgeMethodHandler = {
        bridge("offUserCaptureScreen", $0, $1, $2)
    }
}

final class ScreenAPIManager {
    static let shared = ScreenAPIManager()

    private struct Listener {
        let callbackId: String
        let callback: DMPBridgeCallback
    }

    private var listeners: [String: Listener] = [:]
    private var screenshotObserver: NSObjectProtocol?

    private init() {}

    func handle(
        name: String,
        data: DMPMap,
        appId: String,
        callback: DMPBridgeCallback?
    ) {
        onMain { [weak self] in
            guard let self else { return }
            switch name {
            case "onUserCaptureScreen":
                self.addListener(data: data, appId: appId, callback: callback)
            case "offUserCaptureScreen":
                self.removeListener(data: data, appId: appId)
            default:
                break
            }
        }
    }

    func clearApp(_ appId: String) {
        onMain { [weak self] in
            guard let self else { return }
            self.listeners.removeValue(forKey: appId)
            self.stopObservingIfNeeded()
        }
    }

    private func addListener(
        data: DMPMap,
        appId: String,
        callback: DMPBridgeCallback?
    ) {
        guard
            let callback,
            let callbackId = data.getString(key: "callbackId") ?? data.getString(key: "success"),
            !callbackId.isEmpty
        else {
            return
        }

        // wx.onUserCaptureScreen has a single active listener. A new listener
        // replaces the previous listener for the same mini app.
        listeners[appId] = Listener(callbackId: callbackId, callback: callback)
        startObservingIfNeeded()
    }

    private func removeListener(data: DMPMap, appId: String) {
        if let callbackId = data.getString(key: "callbackId"), !callbackId.isEmpty {
            guard listeners[appId]?.callbackId == callbackId else { return }
        }
        listeners.removeValue(forKey: appId)
        stopObservingIfNeeded()
    }

    private func startObservingIfNeeded() {
        guard screenshotObserver == nil, !listeners.isEmpty else { return }
        screenshotObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notifyCaptured()
        }
    }

    private func stopObservingIfNeeded() {
        guard listeners.isEmpty, let screenshotObserver else { return }
        NotificationCenter.default.removeObserver(screenshotObserver)
        self.screenshotObserver = nil
    }

    private func notifyCaptured() {
        let callbacks = listeners.values.map(\.callback)
        callbacks.forEach { $0(DMPMap(), .success) }
    }

    private func onMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
}
