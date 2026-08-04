//
//  LocationAPI.swift
//  dimina
//

import CoreLocation
import Foundation

/// Standard `getLocation` and `getFuzzyLocation` bridge implementation.
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

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("getLocation", handler: getLocation)
        register("getFuzzyLocation", handler: getFuzzyLocation)
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

    private func requestLocation(
        method: String,
        scope: String,
        fuzzy: Bool,
        callback: DMPBridgeCallback?
    ) {
        if let checker = getApp()?.getAppConfig()?.checkPermission {
            checker(scope) { [weak self] result in
                guard let self else { return }
                guard result == .allowed else {
                    DMPContainerApi.invokeFailure(
                        callback: callback,
                        param: nil,
                        errMsg: SettingAPI.permissionErrorMessage(method: method, result: result)
                    )
                    return
                }
                self.startLocationRequest(method: method, fuzzy: fuzzy, callback: callback)
            }
            return
        }
        startLocationRequest(method: method, fuzzy: fuzzy, callback: callback)
    }

    private func startLocationRequest(
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
}

extension LocationAPI: CLLocationManagerDelegate {

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requests.isEmpty else { return }
            manager.requestLocation()
        case .denied, .restricted:
            failAll("system permission denied")
        case .notDetermined:
            break
        @unknown default:
            failAll("location unavailable")
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
            let latitude = request.fuzzy
                ? round(location.coordinate.latitude * 100) / 100
                : location.coordinate.latitude
            let longitude = request.fuzzy
                ? round(location.coordinate.longitude * 100) / 100
                : location.coordinate.longitude
            var result: [String: Any] = [
                "latitude": latitude,
                "longitude": longitude,
            ]
            if !request.fuzzy {
                result["accuracy"] = location.horizontalAccuracy
                result["speed"] = location.speed
                result["altitude"] = location.altitude
            }
            DMPContainerApi.invokeSuccess(callback: request.callback, param: DMPMap(result))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        failAll(error.localizedDescription)
    }
}
