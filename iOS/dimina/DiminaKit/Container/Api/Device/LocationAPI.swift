//
//  LocationAPI.swift
//  dimina
//

import CoreLocation
import Foundation
import UIKit

/// WeChat-compatible one-shot and foreground location bridge implementation.
public final class LocationAPI: DMPContainerApi {

    private struct Request {
        let method: String
        let fuzzy: Bool
        let callback: DMPBridgeCallback?
    }

    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        return manager
    }()

    private var requests: [Request] = []
    private var pendingStartCallbacks: [DMPBridgeCallback?] = []
    private var locationChangeListeners: [String: DMPBridgeCallback] = [:]
    private var isContinuousUpdateRequested = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("getLocation", handler: getLocation)
        register("getFuzzyLocation", handler: getFuzzyLocation)
        register("startLocationUpdate", handler: startLocationUpdate)
        register("stopLocationUpdate", handler: stopLocationUpdate)
        register("onLocationChange", handler: onLocationChange)
        register("offLocationChange", handler: offLocationChange)
        observeApplicationLifecycle()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func getLocation(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        requestLocation(method: "getLocation", scope: "scope.userLocation", fuzzy: false, callback: callback)
        return DMPAsyncResult()
    }

    private func getFuzzyLocation(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        requestLocation(
            method: "getFuzzyLocation",
            scope: "scope.userFuzzyLocation",
            fuzzy: true,
            callback: callback
        )
        return DMPAsyncResult()
    }

    private func startLocationUpdate(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        requestPermission(scope: "scope.userLocation", method: "startLocationUpdate", callback: callback) {
            [weak self] in
            self?.startContinuousLocationUpdate(callback: callback)
        }
        return DMPAsyncResult()
    }

    private func stopLocationUpdate(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isContinuousUpdateRequested = false
            self.locationManager.stopUpdatingLocation()
            self.failPendingStarts("interrupted")
            DMPContainerApi.invokeSuccess(callback: callback, param: nil)
        }
        return DMPAsyncResult()
    }

    private func onLocationChange(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let data = param.getMap()
        guard let callback,
              let callbackId = data.getString(key: "callback") ?? data.getString(key: "success"),
              !callbackId.isEmpty else {
            return DMPAsyncResult()
        }
        DispatchQueue.main.async { [weak self] in
            self?.locationChangeListeners[callbackId] = callback
        }
        return DMPAsyncResult()
    }

    private func offLocationChange(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let data = param.getMap()
        let callbackId = data.getString(key: "callback") ?? data.getString(key: "success")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let callbackId, !callbackId.isEmpty {
                self.locationChangeListeners.removeValue(forKey: callbackId)
            } else {
                self.locationChangeListeners.removeAll()
            }
        }
        return DMPAsyncResult()
    }

    private func requestLocation(
        method: String,
        scope: String,
        fuzzy: Bool,
        callback: DMPBridgeCallback?
    ) {
        requestPermission(scope: scope, method: method, callback: callback) { [weak self] in
            self?.startLocationRequest(method: method, fuzzy: fuzzy, callback: callback)
        }
    }

    private func requestPermission(
        scope: String,
        method: String,
        callback: DMPBridgeCallback?,
        allowed: @escaping () -> Void
    ) {
        guard let checker = getApp()?.getAppConfig()?.checkPermission else {
            allowed()
            return
        }
        checker(scope) { result in
            guard result == .allowed else {
                DMPContainerApi.invokeFailure(
                    callback: callback,
                    param: nil,
                    errMsg: SettingAPI.permissionErrorMessage(method: method, result: result)
                )
                return
            }
            allowed()
        }
    }

    private func startLocationRequest(
        method: String,
        fuzzy: Bool,
        callback: DMPBridgeCallback?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.startLocationRequestOnMain(method: method, fuzzy: fuzzy, callback: callback)
        }
    }

    private func startLocationRequestOnMain(
        method: String,
        fuzzy: Bool,
        callback: DMPBridgeCallback?
    ) {
        guard DMPPermissionManager.shared.isPermissionConfigured(.location) else {
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "\(method):fail location permission not configured"
            )
            return
        }

        let request = Request(method: method, fuzzy: fuzzy, callback: callback)
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requests.append(request)
            locationManager.requestLocation()
        case .notDetermined:
            requests.append(request)
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "\(method):fail system permission denied"
            )
        @unknown default:
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "\(method):fail location unavailable"
            )
        }
    }

    private func startContinuousLocationUpdate(callback: DMPBridgeCallback?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard DMPPermissionManager.shared.isPermissionConfigured(.location) else {
                DMPContainerApi.invokeFailure(
                    callback: callback,
                    param: nil,
                    errMsg: "startLocationUpdate:fail location permission not configured"
                )
                return
            }

            switch self.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.isContinuousUpdateRequested = true
                self.startUpdatingIfForeground()
                DMPContainerApi.invokeSuccess(callback: callback, param: nil)
            case .notDetermined:
                self.isContinuousUpdateRequested = true
                self.pendingStartCallbacks.append(callback)
                self.locationManager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                DMPContainerApi.invokeFailure(
                    callback: callback,
                    param: nil,
                    errMsg: "startLocationUpdate:fail system permission denied"
                )
            @unknown default:
                DMPContainerApi.invokeFailure(
                    callback: callback,
                    param: nil,
                    errMsg: "startLocationUpdate:fail location unavailable"
                )
            }
        }
    }

    private var authorizationStatus: CLAuthorizationStatus {
        if #available(iOS 14, *) {
            return locationManager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }

    private func failAll(_ message: String) {
        let pending = requests
        requests.removeAll()
        pending.forEach { request in
            DMPContainerApi.invokeFailure(
                callback: request.callback,
                param: nil,
                errMsg: "\(request.method):fail \(message)"
            )
        }
    }

    private func failPendingStarts(_ message: String) {
        let pending = pendingStartCallbacks
        pendingStartCallbacks.removeAll()
        pending.forEach { callback in
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "startLocationUpdate:fail \(message)"
            )
        }
    }

    private func finishPendingStarts() {
        let pending = pendingStartCallbacks
        pendingStartCallbacks.removeAll()
        pending.forEach { callback in
            DMPContainerApi.invokeSuccess(callback: callback, param: nil)
        }
    }

    private func startUpdatingIfForeground() {
        guard isContinuousUpdateRequested,
              UIApplication.shared.applicationState != .background else { return }
        locationManager.startUpdatingLocation()
    }

    private func observeApplicationLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.locationManager.stopUpdatingLocation()
            }
        )
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.startUpdatingIfForeground()
            }
        )
    }

    private func result(for location: CLLocation, fuzzy: Bool) -> [String: Any] {
        let latitude = fuzzy
            ? round(location.coordinate.latitude * 100) / 100
            : location.coordinate.latitude
        let longitude = fuzzy
            ? round(location.coordinate.longitude * 100) / 100
            : location.coordinate.longitude
        var result: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
        ]
        if !fuzzy {
            result["accuracy"] = location.horizontalAccuracy
            result["horizontalAccuracy"] = location.horizontalAccuracy
            result["verticalAccuracy"] = location.verticalAccuracy
            result["speed"] = location.speed
            result["altitude"] = location.altitude
        }
        return result
    }
}

extension LocationAPI: CLLocationManagerDelegate {

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if !requests.isEmpty {
                manager.requestLocation()
            }
            if isContinuousUpdateRequested {
                startUpdatingIfForeground()
                finishPendingStarts()
            }
        case .denied, .restricted:
            failAll("system permission denied")
            failPendingStarts("system permission denied")
            isContinuousUpdateRequested = false
        case .notDetermined:
            break
        @unknown default:
            failAll("location unavailable")
            failPendingStarts("location unavailable")
            isContinuousUpdateRequested = false
        }
    }

    public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            failAll("location unavailable")
            return
        }
        let pending = requests
        requests.removeAll()
        pending.forEach { request in
            DMPContainerApi.invokeSuccess(
                callback: request.callback,
                param: DMPMap(result(for: location, fuzzy: request.fuzzy))
            )
        }
        if isContinuousUpdateRequested {
            let payload = DMPMap(result(for: location, fuzzy: false))
            locationChangeListeners.values.forEach { callback in
                callback(payload, .success)
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        failAll(error.localizedDescription)
    }
}
