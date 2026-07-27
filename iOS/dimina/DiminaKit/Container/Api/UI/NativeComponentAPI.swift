//
//  NativeComponentAPI.swift
//  dimina
//

import AVFoundation
import Foundation
import MapKit
import UIKit
import WebKit

public class NativeComponentAPI: DMPContainerApi {
    private static let COMPONENT_MOUNT = "componentMount"
    private static let PROPS_UPDATE = "propsUpdate"
    private static let COMPONENT_UNMOUNT = "componentUnmount"
    private static let VIDEO_CONTEXT = "videoContext"
    private static let MAP_CONTEXT_METHODS = [
        "addMarkers",
        "removeMarkers",
        "includePoints",
        "setCenterOffset",
        "getCenterLocation",
        "getScale",
        "moveToLocation",
        "translateMarker",
        "addArc",
        "removeArc",
        "calculateRoute",
        "openNavigation",
    ]

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        Self.MAP_CONTEXT_METHODS.forEach { command in
            register(command) { param, env, callback in
                Self.handleMapCommand(command: command, param: param, env: env, callback: callback)
            }
        }
    }

    @BridgeMethod(COMPONENT_MOUNT)
    var componentMount: DMPBridgeMethodHandler = { param, env, _ in
        NativeComponentAPI.handleComponent(apiName: COMPONENT_MOUNT, param: param, env: env)
        return DMPNoneResult()
    }

    @BridgeMethod(PROPS_UPDATE)
    var propsUpdate: DMPBridgeMethodHandler = { param, env, _ in
        NativeComponentAPI.handleComponent(apiName: PROPS_UPDATE, param: param, env: env)
        return DMPNoneResult()
    }

    @BridgeMethod(COMPONENT_UNMOUNT)
    var componentUnmount: DMPBridgeMethodHandler = { param, env, _ in
        NativeComponentAPI.handleComponent(apiName: COMPONENT_UNMOUNT, param: param, env: env)
        return DMPNoneResult()
    }

    @BridgeMethod(VIDEO_CONTEXT)
    var videoContext: DMPBridgeMethodHandler = { param, env, _ in
        NativeComponentAPI.handleComponent(apiName: VIDEO_CONTEXT, param: param, env: env)
        return DMPNoneResult()
    }

    private static func handleComponent(apiName: String, param: DMPBridgeParam, env: DMPBridgeEnv) {
        let params = param.getMap()
        let type = params.getString(key: "type") ?? "native/video"
        guard type == "native/video" || type == "native/map" else { return }

        guard let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex),
              let webview = app.render?.getWebView(byId: env.webViewId) else {
            return
        }

        DispatchQueue.main.async {
            let host = DMPIOSNativeComponentHost.host(for: webview, app: app, webViewId: env.webViewId)
            host.handle(apiName: apiName, params: params)
        }
    }

    private static func handleMapCommand(
        command: String,
        param: DMPBridgeParam,
        env: DMPBridgeEnv,
        callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let params = param.getMap()
        guard let mapId = params.getString(key: "mapId"), !mapId.isEmpty else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "\(command):fail invalid mapId")
            return DMPAsyncResult()
        }
        guard let app = DMPAppManager.sharedInstance().getApp(appIndex: env.appIndex),
              let webview = app.render?.getWebView(byId: env.webViewId) else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "\(command):fail invalid webview")
            return DMPAsyncResult()
        }

        DispatchQueue.main.async {
            let host = DMPIOSNativeComponentHost.host(for: webview, app: app, webViewId: env.webViewId)
            host.handleMapCommand(id: mapId, command: command, params: params) { result in
                switch result {
                case let .success(payload):
                    DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(payload))
                case let .failure(error):
                    DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "\(command):fail \(error.localizedDescription)")
                }
            }
        }
        return DMPAsyncResult()
    }

    public static func clear(webViewId: Int) {
        DispatchQueue.main.async {
            DMPIOSNativeComponentHost.clear(webViewId: webViewId)
        }
    }
}

private final class DMPIOSNativeComponentHost {
    private static var hosts: [Int: DMPIOSNativeComponentHost] = [:]

    private weak var app: DMPApp?
    private weak var webview: DMPWebview?
    private weak var wkWebView: WKWebView?
    private let webViewId: Int
    private let overlayView = DMPPassthroughView()
    private var videos: [String: DMPIOSNativeVideoComponent] = [:]
    private var maps: [String: DMPIOSNativeMapComponent] = [:]
    private var scrollObservation: NSKeyValueObservation?

    static func host(for webview: DMPWebview, app: DMPApp, webViewId: Int) -> DMPIOSNativeComponentHost {
        if let host = hosts[webViewId] {
            return host
        }
        let host = DMPIOSNativeComponentHost(webview: webview, app: app, webViewId: webViewId)
        hosts[webViewId] = host
        return host
    }

    static func clear(webViewId: Int) {
        guard let host = hosts.removeValue(forKey: webViewId) else { return }
        host.release()
    }

    private init(webview: DMPWebview, app: DMPApp, webViewId: Int) {
        self.webview = webview
        self.wkWebView = webview.getWebView()
        self.app = app
        self.webViewId = webViewId

        overlayView.backgroundColor = .clear
        overlayView.clipsToBounds = true

        if let wkWebView = wkWebView {
            wkWebView.clipsToBounds = true
            overlayView.frame = wkWebView.bounds
            overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            wkWebView.addSubview(overlayView)
            scrollObservation = wkWebView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                self?.updateLayouts()
            }
        }
    }

    func handle(apiName: String, params: DMPMap) {
        guard let id = params.getString(key: "id"), !id.isEmpty else { return }
        let type = params.getString(key: "type") ?? (maps[id] == nil ? "native/video" : "native/map")
        switch apiName {
        case "componentMount":
            if type == "native/map" {
                mountMap(id: id, params: params)
            } else {
                mountVideo(id: id, params: params)
            }
        case "propsUpdate":
            if type == "native/map" {
                updateMap(id: id, params: params)
            } else {
                updateVideo(id: id, params: params)
            }
        case "componentUnmount":
            if type == "native/map" || maps[id] != nil {
                unmountMap(id: id)
            } else {
                unmountVideo(id: id)
            }
        case "videoContext":
            videos[id]?.handleCommand(params)
        default:
            break
        }
    }

    func handleMapCommand(
        id: String,
        command: String,
        params: DMPMap,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let map = maps[id] else {
            completion(.failure(DMPIOSMapError.mapNotFound(id)))
            return
        }
        map.handleCommand(command, params: params, completion: completion)
    }

    private func release() {
        scrollObservation = nil
        videos.values.forEach { $0.release() }
        videos.removeAll()
        maps.values.forEach { $0.release() }
        maps.removeAll()
        overlayView.removeFromSuperview()
    }

    private func mountVideo(id: String, params: DMPMap) {
        let video = videos[id] ?? DMPIOSNativeVideoComponent(id: id, host: self)
        if videos[id] == nil {
            videos[id] = video
            overlayView.addSubview(video.view)
        }
        video.update(params)
    }

    private func updateVideo(id: String, params: DMPMap) {
        if let video = videos[id] {
            video.update(params)
        } else {
            mountVideo(id: id, params: params)
        }
    }

    private func unmountVideo(id: String) {
        guard let video = videos.removeValue(forKey: id) else { return }
        video.release()
        video.view.removeFromSuperview()
    }

    private func mountMap(id: String, params: DMPMap) {
        let map = maps[id] ?? DMPIOSNativeMapComponent(id: id, host: self)
        if maps[id] == nil {
            maps[id] = map
            overlayView.addSubview(map.view)
        }
        map.update(params)
    }

    private func updateMap(id: String, params: DMPMap) {
        if let map = maps[id] {
            map.update(params)
        } else {
            mountMap(id: id, params: params)
        }
    }

    private func unmountMap(id: String) {
        guard let map = maps.removeValue(forKey: id) else { return }
        map.release()
        map.view.removeFromSuperview()
    }

    fileprivate func updateLayouts() {
        overlayView.frame = wkWebView?.bounds ?? .zero
        videos.values.forEach { $0.applyLastLayout() }
        maps.values.forEach { $0.applyLastLayout() }
    }

    fileprivate func calculateLayout(_ params: DMPMap) -> CGRect? {
        guard let rect = params.getDMPMap(key: "rect"), let wkWebView = wkWebView else { return nil }
        let width = rect.getDouble(key: "width") ?? 0
        let height = rect.getDouble(key: "height") ?? 0
        if width <= 0 || height <= 0 { return nil }

        let scrollOffset = wkWebView.scrollView.contentOffset
        let pageLeft = rect.getDouble(key: "pageLeft") ?? rect.getDouble(key: "left") ?? 0
        let pageTop = rect.getDouble(key: "pageTop") ?? rect.getDouble(key: "top") ?? 0
        return CGRect(
            x: pageLeft - scrollOffset.x,
            y: pageTop - scrollOffset.y,
            width: width,
            height: height
        )
    }

    fileprivate func sendEvent(_ eventName: String, body: [String: Any]) {
        let msg = DMPMap([
            "type": eventName,
            "body": body,
        ])
        DMPChannelProxy.containerToRender(msg: msg, app: app, webViewId: webViewId)
    }
}

private final class DMPPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}

private enum DMPIOSMapError: LocalizedError {
    case mapNotFound(String)
    case invalidCoordinate
    case markerNotFound(String)
    case routeRequiresTwoPoints
    case routeUnavailable
    case navigationUnavailable

    var errorDescription: String? {
        switch self {
        case let .mapNotFound(id):
            return "map \(id) is not mounted"
        case .invalidCoordinate:
            return "invalid coordinate"
        case let .markerNotFound(id):
            return "marker \(id) not found"
        case .routeRequiresTwoPoints:
            return "route requires at least two coordinates"
        case .routeUnavailable:
            return "route is unavailable"
        case .navigationUnavailable:
            return "external navigation is unavailable"
        }
    }
}

private final class DMPIOSMapAnnotation: MKPointAnnotation {
    let markerId: Any
    let markerKey: String
    var color: UIColor
    var glyphText: String?

    init(markerId: Any, markerKey: String, color: UIColor) {
        self.markerId = markerId
        self.markerKey = markerKey
        self.color = color
        super.init()
    }
}

private struct DMPIOSMapOverlayStyle {
    let strokeColor: UIColor
    let fillColor: UIColor
    let lineWidth: CGFloat
    let dotted: Bool
}

private final class DMPIOSNativeMapComponent: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    let view = MKMapView()
    private weak var host: DMPIOSNativeComponentHost?
    private let id: String
    private var lastParams: DMPMap?
    private var propertyAnnotations: [DMPIOSMapAnnotation] = []
    private var contextAnnotations: [String: DMPIOSMapAnnotation] = [:]
    private var propertyOverlays: [MKOverlay] = []
    private var contextOverlays: [String: MKOverlay] = [:]
    private var overlayStyles: [ObjectIdentifier: DMPIOSMapOverlayStyle] = [:]
    private var lastCameraSignature = ""
    private var centerOffset = CGPoint.zero
    private var hasRendered = false
    private var isApplyingProgrammaticRegion = false
    private var activeDirections: [MKDirections] = []

    init(id: String, host: DMPIOSNativeComponentHost) {
        self.id = id
        self.host = host
        super.init()

        view.delegate = self
        view.showsCompass = false
        view.showsScale = false
        view.pointOfInterestFilter = .includingAll
        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    func update(_ params: DMPMap) {
        lastParams = params
        applyLayout()
        applySettings(params)
        applyCamera(params)
        replacePropertyAnnotations(params)
        replacePropertyOverlays(params)

        if let points = mapDictionaryArray(params.get("includePoints")), !points.isEmpty {
            includePoints(points, padding: nil, animated: false)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.host?.sendEvent("bindupdated", body: ["id": self.id, "mapId": self.id])
            if !self.hasRendered {
                self.hasRendered = true
                self.host?.sendEvent("bindrendersuccess", body: ["id": self.id, "mapId": self.id])
            }
        }
    }

    func applyLastLayout() {
        applyLayout()
    }

    func release() {
        activeDirections.forEach { $0.cancel() }
        activeDirections.removeAll()
        view.delegate = nil
        view.removeAnnotations(propertyAnnotations)
        view.removeAnnotations(Array(contextAnnotations.values))
        view.removeOverlays(propertyOverlays)
        view.removeOverlays(Array(contextOverlays.values))
        propertyAnnotations.removeAll()
        contextAnnotations.removeAll()
        propertyOverlays.removeAll()
        contextOverlays.removeAll()
        overlayStyles.removeAll()
    }

    func handleCommand(
        _ command: String,
        params: DMPMap,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        switch command {
        case "addMarkers":
            addMarkers(mapDictionaryArray(params.get("markers")) ?? [])
            completion(.success(["errMsg": "addMarkers:ok"]))
        case "removeMarkers":
            let ids = mapArray(params.get("markerIds")).map(markerKey)
            removeMarkers(ids)
            completion(.success(["errMsg": "removeMarkers:ok"]))
        case "includePoints":
            guard let points = mapDictionaryArray(params.get("points")), !points.isEmpty else {
                completion(.failure(DMPIOSMapError.invalidCoordinate))
                return
            }
            includePoints(points, padding: mapDoubleArray(params.get("padding")), animated: true)
            completion(.success(["errMsg": "includePoints:ok"]))
        case "setCenterOffset":
            let offset = mapDoubleArray(params.get("offset"))
            centerOffset = CGPoint(x: offset.first ?? 0, y: offset.dropFirst().first ?? 0)
            setCenter(view.centerCoordinate, animated: false)
            completion(.success(["errMsg": "setCenterOffset:ok"]))
        case "getCenterLocation":
            let center = view.centerCoordinate
            completion(.success([
                "latitude": center.latitude,
                "longitude": center.longitude,
                "errMsg": "getCenterLocation:ok",
            ]))
        case "getScale":
            completion(.success(["scale": currentScale(), "errMsg": "getScale:ok"]))
        case "moveToLocation":
            if let coordinate = coordinate(from: params.toDictionary()) {
                setCenter(coordinate, animated: true)
                completion(.success(["errMsg": "moveToLocation:ok"]))
            } else if CLLocationCoordinate2DIsValid(view.userLocation.coordinate),
                      view.userLocation.location != nil {
                setCenter(view.userLocation.coordinate, animated: true)
                completion(.success(["errMsg": "moveToLocation:ok"]))
            } else {
                completion(.failure(DMPIOSMapError.invalidCoordinate))
            }
        case "translateMarker":
            translateMarker(params, completion: completion)
        case "addArc":
            addArc(params, completion: completion)
        case "removeArc":
            removeArc(params)
            completion(.success(["errMsg": "removeArc:ok"]))
        case "calculateRoute":
            calculateRoute(params, completion: completion)
        case "openNavigation":
            openNavigation(params, completion: completion)
        default:
            completion(.failure(DMPIOSMapError.mapNotFound(id)))
        }
    }

    private func applyLayout() {
        guard let lastParams, let frame = host?.calculateLayout(lastParams) else {
            view.isHidden = true
            return
        }
        view.isHidden = lastParams.getBool(key: "hidden") ?? false
        view.frame = frame
    }

    private func applySettings(_ params: DMPMap) {
        view.isZoomEnabled = params.getBool(key: "enableZoom") ?? true
        view.isScrollEnabled = params.getBool(key: "enableScroll") ?? true
        view.isRotateEnabled = params.getBool(key: "enableRotate") ?? false
        view.isPitchEnabled = params.getBool(key: "enableOverlooking") ?? false
        view.showsUserLocation = params.getBool(key: "showLocation") ?? false
        view.showsScale = params.getBool(key: "showScale") ?? false
        view.showsCompass = params.getBool(key: "showCompass") ?? false
        view.mapType = (params.getBool(key: "enableSatellite") ?? false) ? .satellite : .standard
        if params.getBool(key: "enablePoi") == false || params.getBool(key: "enablePOI") == false {
            view.pointOfInterestFilter = .excludingAll
        } else {
            view.pointOfInterestFilter = .includingAll
        }
    }

    private func applyCamera(_ params: DMPMap) {
        guard let latitude = params.getDouble(key: "latitude"),
              let longitude = params.getDouble(key: "longitude") else { return }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let minScale = params.getDouble(key: "minScale") ?? 3
        let maxScale = params.getDouble(key: "maxScale") ?? 22
        let scale = min(max(params.getDouble(key: "scale") ?? 16, minScale), maxScale)
        let signature = "\(latitude),\(longitude),\(scale)"
        guard signature != lastCameraSignature else { return }
        lastCameraSignature = signature
        setRegion(center: coordinate, scale: scale, animated: false)
    }

    private func setRegion(center: CLLocationCoordinate2D, scale: Double, animated: Bool) {
        let longitudeDelta = max(360 / pow(2, scale), 0.000_001)
        let aspectRatio = Double(max(view.bounds.height, 1) / max(view.bounds.width, 1))
        let span = MKCoordinateSpan(
            latitudeDelta: min(longitudeDelta * aspectRatio, 180),
            longitudeDelta: min(longitudeDelta, 360)
        )
        isApplyingProgrammaticRegion = true
        view.setRegion(MKCoordinateRegion(center: center, span: span), animated: animated)
    }

    private func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        guard centerOffset != .zero, view.bounds.width > 0, view.bounds.height > 0 else {
            isApplyingProgrammaticRegion = true
            view.setCenter(coordinate, animated: animated)
            return
        }
        let desiredPoint = CGPoint(
            x: view.bounds.midX - centerOffset.x,
            y: view.bounds.midY - centerOffset.y
        )
        let targetPoint = view.convert(coordinate, toPointTo: view)
        let adjustedPoint = CGPoint(
            x: targetPoint.x + view.bounds.midX - desiredPoint.x,
            y: targetPoint.y + view.bounds.midY - desiredPoint.y
        )
        isApplyingProgrammaticRegion = true
        view.setCenter(view.convert(adjustedPoint, toCoordinateFrom: view), animated: animated)
    }

    private func replacePropertyAnnotations(_ params: DMPMap) {
        view.removeAnnotations(propertyAnnotations)
        propertyAnnotations.removeAll()
        let markers = (mapDictionaryArray(params.get("markers")) ?? []) +
            (mapDictionaryArray(params.get("covers")) ?? [])
        propertyAnnotations = markers.compactMap(makeAnnotation)
        view.addAnnotations(propertyAnnotations)
    }

    private func addMarkers(_ markers: [[String: Any]]) {
        for marker in markers {
            guard let annotation = makeAnnotation(marker) else { continue }
            if let old = contextAnnotations.removeValue(forKey: annotation.markerKey) {
                view.removeAnnotation(old)
            }
            contextAnnotations[annotation.markerKey] = annotation
            view.addAnnotation(annotation)
        }
    }

    private func removeMarkers(_ ids: [String]) {
        let idSet = Set(ids)
        let propertyMatches = propertyAnnotations.filter { idSet.contains($0.markerKey) }
        propertyAnnotations.removeAll { idSet.contains($0.markerKey) }
        view.removeAnnotations(propertyMatches)
        for markerId in idSet {
            if let annotation = contextAnnotations.removeValue(forKey: markerId) {
                view.removeAnnotation(annotation)
            }
        }
    }

    private func makeAnnotation(_ marker: [String: Any]) -> DMPIOSMapAnnotation? {
        guard let point = coordinate(from: marker) else { return nil }
        let rawId = marker["id"] ?? UUID().uuidString
        let annotation = DMPIOSMapAnnotation(
            markerId: rawId,
            markerKey: markerKey(rawId),
            color: mapColor(marker["color"] as? String, fallback: UIColor(red: 0.70, green: 0.33, blue: 0.28, alpha: 1))
        )
        annotation.coordinate = point
        let label = mapDictionary(marker["label"])
        let callout = mapDictionary(marker["callout"])
        annotation.title = marker["title"] as? String ?? callout?["content"] as? String ?? label?["content"] as? String
        if let glyphText = label?["content"] as? String, glyphText.count <= 3 {
            annotation.glyphText = glyphText
        } else if let markerNumber = mapDouble(rawId),
                  markerNumber.rounded() == markerNumber,
                  markerNumber >= 0,
                  markerNumber <= 999 {
            annotation.glyphText = String(Int(markerNumber))
        }
        return annotation
    }

    private func replacePropertyOverlays(_ params: DMPMap) {
        view.removeOverlays(propertyOverlays)
        propertyOverlays.forEach { overlayStyles.removeValue(forKey: ObjectIdentifier($0 as AnyObject)) }
        propertyOverlays.removeAll()

        for item in mapDictionaryArray(params.get("polyline")) ?? [] {
            let coordinates = coordinates(from: item["points"])
            guard coordinates.count >= 2 else { continue }
            var mutableCoordinates = coordinates
            let overlay = MKPolyline(coordinates: &mutableCoordinates, count: mutableCoordinates.count)
            propertyOverlays.append(overlay)
            overlayStyles[ObjectIdentifier(overlay)] = DMPIOSMapOverlayStyle(
                strokeColor: mapColor(item["color"] as? String, fallback: .systemBlue),
                fillColor: .clear,
                lineWidth: CGFloat(mapDouble(item["width"]) ?? 4),
                dotted: mapBool(item["dottedLine"]) ?? false
            )
        }
        for item in mapDictionaryArray(params.get("polygons")) ?? [] {
            let coordinates = coordinates(from: item["points"])
            guard coordinates.count >= 3 else { continue }
            var mutableCoordinates = coordinates
            let overlay = MKPolygon(coordinates: &mutableCoordinates, count: mutableCoordinates.count)
            propertyOverlays.append(overlay)
            overlayStyles[ObjectIdentifier(overlay)] = DMPIOSMapOverlayStyle(
                strokeColor: mapColor(item["strokeColor"] as? String, fallback: .systemBlue),
                fillColor: mapColor(item["fillColor"] as? String, fallback: UIColor.systemBlue.withAlphaComponent(0.15)),
                lineWidth: CGFloat(mapDouble(item["strokeWidth"]) ?? 2),
                dotted: false
            )
        }
        for item in mapDictionaryArray(params.get("circles")) ?? [] {
            guard let center = coordinate(from: item) else { continue }
            let overlay = MKCircle(center: center, radius: mapDouble(item["radius"]) ?? 0)
            propertyOverlays.append(overlay)
            overlayStyles[ObjectIdentifier(overlay)] = DMPIOSMapOverlayStyle(
                strokeColor: mapColor(item["color"] as? String, fallback: .systemBlue),
                fillColor: mapColor(item["fillColor"] as? String, fallback: UIColor.systemBlue.withAlphaComponent(0.15)),
                lineWidth: CGFloat(mapDouble(item["strokeWidth"]) ?? 2),
                dotted: false
            )
        }
        view.addOverlays(propertyOverlays)
    }

    private func includePoints(_ points: [[String: Any]], padding: [Double]?, animated: Bool) {
        let coordinates = points.compactMap(coordinate)
        guard !coordinates.isEmpty else { return }
        if coordinates.count == 1, let first = coordinates.first {
            setCenter(first, animated: animated)
            return
        }
        var mapRect = MKMapRect.null
        coordinates.forEach { coordinate in
            let point = MKMapPoint(coordinate)
            mapRect = mapRect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let values = padding ?? []
        let edgePadding = UIEdgeInsets(
            top: CGFloat(values.indices.contains(0) ? values[0] : 24),
            left: CGFloat(values.indices.contains(3) ? values[3] : (values.indices.contains(1) ? values[1] : 24)),
            bottom: CGFloat(values.indices.contains(2) ? values[2] : 24),
            right: CGFloat(values.indices.contains(1) ? values[1] : 24)
        )
        isApplyingProgrammaticRegion = true
        view.setVisibleMapRect(mapRect, edgePadding: edgePadding, animated: animated)
    }

    private func translateMarker(
        _ params: DMPMap,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let rawId = params.get("markerId") ?? ""
        let key = markerKey(rawId)
        let annotation = contextAnnotations[key] ?? propertyAnnotations.first(where: { $0.markerKey == key })
        guard let annotation else {
            completion(.failure(DMPIOSMapError.markerNotFound(key)))
            return
        }
        guard let destination = coordinate(from: mapDictionary(params.get("destination")) ?? params.toDictionary()) else {
            completion(.failure(DMPIOSMapError.invalidCoordinate))
            return
        }
        let duration = max(params.getDouble(key: "duration") ?? 0, 0) / 1000
        UIView.animate(withDuration: duration, animations: {
            annotation.coordinate = destination
        }, completion: { _ in
            completion(.success(["errMsg": "translateMarker:ok"]))
        })
    }

    private func addArc(
        _ params: DMPMap,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let coordinates = coordinates(from: params.get("points"))
        let endpoints = coordinates.isEmpty ? [
            coordinate(from: mapDictionary(params.get("start")) ?? [:]),
            coordinate(from: mapDictionary(params.get("end")) ?? [:]),
        ].compactMap { $0 } : coordinates
        guard endpoints.count >= 2 else {
            completion(.failure(DMPIOSMapError.invalidCoordinate))
            return
        }
        var mutableCoordinates = endpoints
        let overlay = MKGeodesicPolyline(coordinates: &mutableCoordinates, count: mutableCoordinates.count)
        let key = markerKey(params.get("id") ?? params.get("arcId") ?? UUID().uuidString)
        if let old = contextOverlays.removeValue(forKey: key) {
            view.removeOverlay(old)
            overlayStyles.removeValue(forKey: ObjectIdentifier(old as AnyObject))
        }
        contextOverlays[key] = overlay
        overlayStyles[ObjectIdentifier(overlay)] = DMPIOSMapOverlayStyle(
            strokeColor: mapColor(params.getString(key: "color"), fallback: .systemBlue),
            fillColor: .clear,
            lineWidth: CGFloat(params.getDouble(key: "width") ?? 4),
            dotted: params.getBool(key: "dottedLine") ?? false
        )
        view.addOverlay(overlay)
        completion(.success(["errMsg": "addArc:ok", "id": key]))
    }

    private func removeArc(_ params: DMPMap) {
        let values = mapArray(params.get("arcIds")) + [params.get("id"), params.get("arcId")].compactMap { $0 }
        for key in values.map(markerKey) {
            if let overlay = contextOverlays.removeValue(forKey: key) {
                view.removeOverlay(overlay)
                overlayStyles.removeValue(forKey: ObjectIdentifier(overlay as AnyObject))
            }
        }
    }

    private func calculateRoute(
        _ params: DMPMap,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let points = coordinates(from: params.get("points"))
        guard points.count >= 2 else {
            completion(.failure(DMPIOSMapError.routeRequiresTwoPoints))
            return
        }

        activeDirections.forEach { $0.cancel() }
        activeDirections.removeAll()

        let transportType = mapTransportType(params.getString(key: "transportType"))
        var segmentPayloads: [[String: Any]] = []
        var routePoints: [[String: Any]] = []
        var totalDistance: CLLocationDistance = 0
        var totalDuration: TimeInterval = 0

        func calculateSegment(_ index: Int) {
            guard index < points.count - 1 else {
                self.activeDirections.removeAll()
                completion(.success([
                    "errMsg": "calculateRoute:ok",
                    "provider": "mapkit",
                    "transportType": mapTransportTypeName(transportType),
                    "distance": totalDistance,
                    "duration": totalDuration,
                    "points": routePoints,
                    "segments": segmentPayloads,
                ]))
                return
            }

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: points[index]))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: points[index + 1]))
            request.requestsAlternateRoutes = false
            request.transportType = transportType
            let directions = MKDirections(request: request)
            self.activeDirections.append(directions)
            directions.calculate { [weak self] response, error in
                guard let self else { return }
                self.activeDirections.removeAll { $0 === directions }
                guard error == nil, let route = response?.routes.first else {
                    self.activeDirections.forEach { $0.cancel() }
                    self.activeDirections.removeAll()
                    completion(.failure(error ?? DMPIOSMapError.routeUnavailable))
                    return
                }

                let segmentPoints = mapCoordinates(route.polyline)
                if routePoints.isEmpty {
                    routePoints.append(contentsOf: segmentPoints)
                } else {
                    routePoints.append(contentsOf: segmentPoints.dropFirst())
                }
                totalDistance += route.distance
                totalDuration += route.expectedTravelTime
                segmentPayloads.append([
                    "index": index,
                    "distance": route.distance,
                    "duration": route.expectedTravelTime,
                    "transportType": mapTransportTypeName(transportType),
                    "points": segmentPoints,
                ])
                calculateSegment(index + 1)
            }
        }

        calculateSegment(0)
    }

    private func openNavigation(
        _ params: DMPMap,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let destination = coordinate(from: params.toDictionary()) else {
            completion(.failure(DMPIOSMapError.invalidCoordinate))
            return
        }
        let name = params.getString(key: "name") ?? params.getString(key: "title") ?? "目的地"
        let provider = params.getString(key: "provider")?.lowercased() ?? "apple"

        if provider == "amap", let url = amapNavigationURL(destination: destination, name: name) {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    completion(.success(["errMsg": "openNavigation:ok", "provider": "amap"]))
                } else {
                    self.openAppleNavigation(destination: destination, name: name, completion: completion)
                }
            }
            return
        }
        openAppleNavigation(destination: destination, name: name, completion: completion)
    }

    private func openAppleNavigation(
        destination: CLLocationCoordinate2D,
        name: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        item.name = name
        let success = item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ])
        if success {
            completion(.success(["errMsg": "openNavigation:ok", "provider": "apple"]))
        } else {
            completion(.failure(DMPIOSMapError.navigationUnavailable))
        }
    }

    private func amapNavigationURL(destination: CLLocationCoordinate2D, name: String) -> URL? {
        var components = URLComponents(string: "iosamap://path")
        components?.queryItems = [
            URLQueryItem(name: "sourceApplication", value: "Dimina"),
            URLQueryItem(name: "dlat", value: String(destination.latitude)),
            URLQueryItem(name: "dlon", value: String(destination.longitude)),
            URLQueryItem(name: "dname", value: name),
            URLQueryItem(name: "dev", value: "0"),
            URLQueryItem(name: "t", value: "0"),
        ]
        return components?.url
    }

    private func currentScale() -> Double {
        let longitudeDelta = max(view.region.span.longitudeDelta, 0.000_001)
        return min(max(log2(360 / longitudeDelta), 3), 22)
    }

    @objc private func mapTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: view)
        let coordinate = view.convert(point, toCoordinateFrom: view)
        host?.sendEvent("bindtap", body: [
            "id": id,
            "mapId": id,
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
        ])
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        host?.sendEvent("bindregionchange", body: [
            "id": id,
            "mapId": id,
            "type": "begin",
            "causedBy": isApplyingProgrammaticRegion ? "update" : "gesture",
        ])
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        let center = mapView.centerCoordinate
        host?.sendEvent("bindregionchange", body: [
            "id": id,
            "mapId": id,
            "type": "end",
            "causedBy": isApplyingProgrammaticRegion ? "update" : "gesture",
            "latitude": center.latitude,
            "longitude": center.longitude,
            "scale": currentScale(),
        ])
        isApplyingProgrammaticRegion = false
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation as? DMPIOSMapAnnotation else { return }
        host?.sendEvent("bindmarkertap", body: [
            "id": id,
            "mapId": id,
            "markerId": annotation.markerId,
        ])
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let marker = annotation as? DMPIOSMapAnnotation else { return nil }
        let reuseId = "dimina-map-marker"
        let markerView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: marker, reuseIdentifier: reuseId)
        markerView.annotation = marker
        markerView.markerTintColor = marker.color
        markerView.glyphText = marker.glyphText
        markerView.canShowCallout = marker.title?.isEmpty == false
        return markerView
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let style = overlayStyles[ObjectIdentifier(overlay as AnyObject)] ?? DMPIOSMapOverlayStyle(
            strokeColor: .systemBlue,
            fillColor: UIColor.systemBlue.withAlphaComponent(0.15),
            lineWidth: 3,
            dotted: false
        )
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = style.strokeColor
            renderer.lineWidth = style.lineWidth
            renderer.lineDashPattern = style.dotted ? [6, 6] : nil
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
        if let polygon = overlay as? MKPolygon {
            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.strokeColor = style.strokeColor
            renderer.fillColor = style.fillColor
            renderer.lineWidth = style.lineWidth
            return renderer
        }
        if let circle = overlay as? MKCircle {
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = style.strokeColor
            renderer.fillColor = style.fillColor
            renderer.lineWidth = style.lineWidth
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return !(touch.view is MKAnnotationView || touch.view is UIControl)
    }
}

private func mapDictionary(_ value: Any?) -> [String: Any]? {
    if let value = value as? [String: Any] { return value }
    if let value = value as? DMPMap { return value.toDictionary() }
    return nil
}

private func mapDictionaryArray(_ value: Any?) -> [[String: Any]]? {
    guard let values = value as? [Any] else { return nil }
    return values.compactMap(mapDictionary)
}

private func mapArray(_ value: Any?) -> [Any] {
    return value as? [Any] ?? []
}

private func mapDoubleArray(_ value: Any?) -> [Double] {
    return mapArray(value).compactMap(mapDouble)
}

private func mapDouble(_ value: Any?) -> Double? {
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
}

private func mapTransportType(_ value: String?) -> MKDirectionsTransportType {
    switch value?.lowercased() {
    case "walking":
        return .walking
    case "transit":
        return .transit
    default:
        return .automobile
    }
}

private func mapTransportTypeName(_ value: MKDirectionsTransportType) -> String {
    if value == .walking { return "walking" }
    if value == .transit { return "transit" }
    return "driving"
}

private func mapCoordinates(_ polyline: MKPolyline) -> [[String: Any]] {
    var coordinates = [CLLocationCoordinate2D](
        repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        count: polyline.pointCount
    )
    coordinates.withUnsafeMutableBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else { return }
        polyline.getCoordinates(baseAddress, range: NSRange(location: 0, length: polyline.pointCount))
    }
    return coordinates.map { coordinate in
        ["latitude": coordinate.latitude, "longitude": coordinate.longitude]
    }
}

private func mapBool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    return nil
}

private func markerKey(_ value: Any) -> String {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return String(describing: value)
}

private func coordinate(from dictionary: [String: Any]) -> CLLocationCoordinate2D? {
    guard let latitude = mapDouble(dictionary["latitude"]),
          let longitude = mapDouble(dictionary["longitude"]) else { return nil }
    let value = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    return CLLocationCoordinate2DIsValid(value) ? value : nil
}

private func coordinates(from value: Any?) -> [CLLocationCoordinate2D] {
    return (mapDictionaryArray(value) ?? []).compactMap(coordinate)
}

private func mapColor(_ value: String?, fallback: UIColor) -> UIColor {
    guard var hex = value?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
        return fallback
    }
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6 || hex.count == 8, let raw = UInt64(hex, radix: 16) else { return fallback }
    if hex.count == 8 {
        return UIColor(
            red: CGFloat((raw >> 24) & 0xff) / 255,
            green: CGFloat((raw >> 16) & 0xff) / 255,
            blue: CGFloat((raw >> 8) & 0xff) / 255,
            alpha: CGFloat(raw & 0xff) / 255
        )
    }
    return UIColor(
        red: CGFloat((raw >> 16) & 0xff) / 255,
        green: CGFloat((raw >> 8) & 0xff) / 255,
        blue: CGFloat(raw & 0xff) / 255,
        alpha: 1
    )
}

private final class DMPIOSNativeVideoComponent: NSObject, UIGestureRecognizerDelegate {
    let view = UIView()
    private weak var host: DMPIOSNativeComponentHost?
    private let id: String
    private let playerLayer = AVPlayerLayer()
    private let controlBar = UIView()
    private let playButton = UIButton(type: .system)
    private let seekSlider = UISlider()
    private let timeLabel = UILabel()
    private let centerPlayButton = UIButton(type: .system)
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var lastParams: DMPMap?
    private var src = ""
    private var controls = true
    private var controlsVisible = true
    private var showProgress = true
    private var showPlayBtn = true
    private var showCenterPlayBtn = true
    private var autoplay = false
    private var loop = false
    private var muted = false
    private var initialTime: Double = 0
    private var playbackRate: Float = 1
    private var isUserSeeking = false
    private var pendingPlay = false
    private var playbackRequested = false
    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(toggleControlBar))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    init(id: String, host: DMPIOSNativeComponentHost) {
        self.id = id
        self.host = host
        super.init()

        view.backgroundColor = .black
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapRecognizer)
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        setupControls()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    func update(_ params: DMPMap) {
        lastParams = params
        applyLayout()

        autoplay = params.getBool(key: "autoplay") ?? autoplay
        loop = params.getBool(key: "loop") ?? loop
        muted = params.getBool(key: "muted") ?? muted
        initialTime = params.getDouble(key: "initialTime") ?? initialTime
        controls = params.getBool(key: "controls") ?? controls
        showProgress = params.getBool(key: "showProgress") ?? showProgress
        showPlayBtn = params.getBool(key: "showPlayBtn") ?? showPlayBtn
        showCenterPlayBtn = params.getBool(key: "showCenterPlayBtn") ?? showCenterPlayBtn
        playerLayer.videoGravity = videoGravity(for: params.getString(key: "objectFit"))

        player?.isMuted = muted
        applyControlsVisibility()

        let nextSrc = params.getString(key: "src") ?? src
        if nextSrc != src {
            src = nextSrc
            loadSource()
        } else if autoplay {
            play()
        }
    }

    func applyLastLayout() {
        applyLayout()
    }

    private func applyLayout() {
        guard let lastParams, let frame = host?.calculateLayout(lastParams) else {
            view.isHidden = true
            return
        }
        let hidden = lastParams.getBool(key: "hidden") ?? false
        view.isHidden = hidden
        view.frame = frame
        playerLayer.frame = view.bounds
        layoutControls()
    }

    func handleCommand(_ params: DMPMap) {
        switch params.getString(key: "command") {
        case "play":
            play()
        case "pause":
            pause()
        case "stop":
            stop()
        case "seek":
            seek(params.getDouble(key: "position") ?? 0)
        case "playbackRate":
            playbackRate = Float(params.getDouble(key: "rate") ?? 1)
            if player?.timeControlStatus == .playing {
                player?.rate = playbackRate
            }
        default:
            break
        }
    }

    func release() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation = nil
        player?.pause()
        player = nil
        playerLayer.player = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func loadSource() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation = nil
        pendingPlay = autoplay
        playbackRequested = autoplay
        player?.pause()
        player = nil
        playerLayer.player = nil
        updatePlayButton()
        updateControlProgress()

        guard let url = makeURL(src) else { return }

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        nextPlayer.isMuted = muted
        player = nextPlayer
        playerLayer.player = nextPlayer
        installTimeObserver()
        observeItemStatus(item)
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self.handleReadyToPlay()
                case .failed:
                    self.pendingPlay = false
                    self.playbackRequested = false
                    self.updatePlayButton()
                    self.host?.sendEvent("binderror", body: [
                        "id": self.id,
                        "src": self.src,
                        "errMsg": self.playerItemErrorMessage(item),
                    ])
                default:
                    break
                }
            }
        }
    }

    private func handleReadyToPlay() {
        if initialTime > 0 {
            seek(initialTime)
        } else {
            seek(0.001)
        }

        host?.sendEvent("bindloadedmetadata", body: [
            "id": id,
            "src": src,
            "duration": durationSeconds(),
        ])
        updateControlProgress()
        if autoplay || pendingPlay {
            pendingPlay = false
            play()
        } else {
            updatePlayButton()
        }
    }

    private func installTimeObserver() {
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.updateControlProgress()
            self.host?.sendEvent("bindtimeupdate", body: [
                "id": self.id,
                "src": self.src,
                "currentTime": CMTimeGetSeconds(time),
                "duration": self.durationSeconds(),
            ])
        }
    }

    private func play() {
        playbackRequested = true
        guard let player, player.currentItem?.status == .readyToPlay else {
            pendingPlay = true
            updatePlayButton()
            return
        }
        player.play()
        if playbackRate != 1 {
            player.rate = playbackRate
        }
        pendingPlay = false
        updatePlayButton()
        updateControlProgress()
        host?.sendEvent("bindplay", body: ["id": id, "src": src])
    }

    private func pause() {
        pendingPlay = false
        playbackRequested = false
        player?.pause()
        updatePlayButton()
        updateControlProgress()
        host?.sendEvent("bindpause", body: ["id": id, "src": src])
    }

    private func stop() {
        pendingPlay = false
        playbackRequested = false
        player?.pause()
        seek(0)
        updatePlayButton()
        updateControlProgress()
        host?.sendEvent("bindpause", body: ["id": id, "src": src])
    }

    private func seek(_ seconds: Double) {
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateControlProgress()
            }
        }
    }

    @objc private func playerDidEnd(_ notification: Notification) {
        guard notification.object as? AVPlayerItem === player?.currentItem else { return }
        pendingPlay = false
        playbackRequested = false
        updatePlayButton()
        updateControlProgress()
        host?.sendEvent("bindended", body: ["id": id, "src": src])
        if loop {
            seek(0)
            play()
        }
    }

    private func setupControls() {
        controlBar.backgroundColor = UIColor(white: 0, alpha: 0.43)
        controlBar.isUserInteractionEnabled = true
        view.addSubview(controlBar)

        playButton.tintColor = .white
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        controlBar.addSubview(playButton)

        seekSlider.minimumValue = 0
        seekSlider.maximumValue = 1
        seekSlider.value = 0
        seekSlider.minimumTrackTintColor = .white
        seekSlider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.47)
        seekSlider.thumbTintColor = .white
        let thumbImage = makeSliderThumbImage(diameter: 10)
        seekSlider.setThumbImage(thumbImage, for: .normal)
        seekSlider.setThumbImage(thumbImage, for: .highlighted)
        seekSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        seekSlider.addTarget(self, action: #selector(sliderTouchEnded(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        controlBar.addSubview(seekSlider)

        timeLabel.text = "00:00/00:00"
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        controlBar.addSubview(timeLabel)

        centerPlayButton.tintColor = .white
        centerPlayButton.backgroundColor = UIColor(white: 0, alpha: 0.47)
        centerPlayButton.layer.cornerRadius = 28
        centerPlayButton.clipsToBounds = true
        centerPlayButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        centerPlayButton.addTarget(self, action: #selector(centerPlayButtonTapped), for: .touchUpInside)
        view.addSubview(centerPlayButton)

        applyControlsVisibility()
    }

    private func layoutControls() {
        playerLayer.frame = view.bounds

        let controlHeight = min(CGFloat(44), view.bounds.height)
        controlBar.frame = CGRect(
            x: 0,
            y: max(0, view.bounds.height - controlHeight),
            width: view.bounds.width,
            height: controlHeight
        )

        let playButtonWidth = showPlayBtn ? CGFloat(40) : 0
        playButton.frame = CGRect(x: 0, y: 0, width: playButtonWidth, height: controlHeight)

        let horizontalPadding = CGFloat(8)
        let labelWidth = showProgress ? CGFloat(86) : 0
        timeLabel.frame = CGRect(
            x: max(0, controlBar.bounds.width - horizontalPadding - labelWidth),
            y: 0,
            width: labelWidth,
            height: controlHeight
        )

        let sliderX = showPlayBtn ? playButton.frame.maxX : horizontalPadding
        let sliderRight = showProgress ? timeLabel.frame.minX - horizontalPadding : controlBar.bounds.width - horizontalPadding
        seekSlider.frame = CGRect(
            x: sliderX,
            y: 0,
            width: max(0, sliderRight - sliderX),
            height: controlHeight
        )

        let centerSize = CGFloat(56)
        centerPlayButton.frame = CGRect(
            x: (view.bounds.width - centerSize) / 2,
            y: (view.bounds.height - centerSize) / 2,
            width: centerSize,
            height: centerSize
        )

        view.bringSubviewToFront(controlBar)
        view.bringSubviewToFront(centerPlayButton)
    }

    private func applyControlsVisibility() {
        if !controls {
            controlsVisible = false
        } else if controlBar.isHidden {
            controlsVisible = true
        }

        controlBar.isHidden = !(controls && controlsVisible)
        playButton.isHidden = !showPlayBtn
        seekSlider.isHidden = !showProgress
        timeLabel.isHidden = !showProgress
        layoutControls()
        updatePlayButton()
        updateControlProgress()
    }

    @objc private func toggleControlBar() {
        if !controls {
            return
        }
        controlsVisible.toggle()
        applyControlsVisibility()
    }

    @objc private func playButtonTapped() {
        togglePlay()
    }

    @objc private func centerPlayButtonTapped() {
        play()
    }

    @objc private func sliderTouchDown() {
        isUserSeeking = true
    }

    @objc private func sliderValueChanged(_ sender: UISlider) {
        timeLabel.text = formatVideoTime(position: Double(sender.value), duration: durationSeconds())
    }

    @objc private func sliderTouchEnded(_ sender: UISlider) {
        isUserSeeking = false
        seek(Double(sender.value))
    }

    private func togglePlay() {
        if isPlaybackActive {
            pause()
        } else {
            play()
        }
    }

    private var isPlaybackActive: Bool {
        playbackRequested ||
        player?.timeControlStatus == .playing ||
        player?.timeControlStatus == .waitingToPlayAtSpecifiedRate ||
        (player?.rate ?? 0) > 0
    }

    private func updatePlayButton() {
        let imageName = isPlaybackActive ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: imageName), for: .normal)
        centerPlayButton.isHidden = !(
            controls &&
            controlsVisible &&
            showCenterPlayBtn &&
            !isPlaybackActive
        )
    }

    private func updateControlProgress() {
        if !controls || isUserSeeking {
            return
        }
        let duration = durationSeconds()
        let currentTime = currentTimeSeconds()
        seekSlider.maximumValue = Float(max(duration, 1))
        seekSlider.value = Float(min(max(currentTime, 0), Double(seekSlider.maximumValue)))
        timeLabel.text = formatVideoTime(position: currentTime, duration: duration)
    }

    private func currentTimeSeconds() -> Double {
        guard let currentTime = player?.currentTime() else { return 0 }
        let seconds = CMTimeGetSeconds(currentTime)
        return seconds.isFinite ? seconds : 0
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl {
            return false
        }
        let point = touch.location(in: view)
        if !controlBar.isHidden && controlBar.frame.contains(point) {
            return false
        }
        if !centerPlayButton.isHidden && centerPlayButton.frame.contains(point) {
            return false
        }
        return true
    }

    private func videoGravity(for objectFit: String?) -> AVLayerVideoGravity {
        switch objectFit {
        case "fill":
            return .resize
        case "cover":
            return .resizeAspectFill
        default:
            return .resizeAspect
        }
    }

    private func durationSeconds() -> Double {
        guard let duration = player?.currentItem?.duration else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }

    private func playerItemErrorMessage(_ item: AVPlayerItem) -> String {
        var messages: [String] = []
        if let error = item.error as NSError? {
            messages.append("\(error.domain)(\(error.code)): \(error.localizedDescription)")
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                messages.append("underlying \(underlying.domain)(\(underlying.code)): \(underlying.localizedDescription)")
            }
        }
        if let event = item.errorLog()?.events.last {
            messages.append("server \(event.errorStatusCode): \(event.errorComment ?? "") \(event.uri ?? "")")
        }
        return messages.isEmpty ? "video:error" : messages.joined(separator: "; ")
    }

    private func makeURL(_ src: String) -> URL? {
        if src.isEmpty {
            return nil
        }
        if src.hasPrefix("http://") || src.hasPrefix("https://") || src.hasPrefix("file://") {
            return URL(string: src)
        }
        return URL(fileURLWithPath: src)
    }
}

private func formatVideoTime(position: Double, duration: Double) -> String {
    return "\(formatVideoTimePart(position))/\(formatVideoTimePart(max(duration, 0)))"
}

private func formatVideoTimePart(_ time: Double) -> String {
    let totalSeconds = max(Int(time), 0)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

private func makeSliderThumbImage(diameter: CGFloat) -> UIImage {
    let size = CGSize(width: diameter, height: diameter)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
    }.withRenderingMode(.alwaysOriginal)
}
