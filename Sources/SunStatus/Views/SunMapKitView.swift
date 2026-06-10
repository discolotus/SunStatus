import AppKit
import MapKit
import SwiftUI
import SunStatusCore

struct SunMapKitView: NSViewRepresentable {
    let centerCoordinate: Coordinate
    let pathSamples: [SunPathSample3D]
    let selectedSample: SunPathSample3D
    var mode: SunMapKitViewMode = .compact
    var recenterRequestID = 0
    var onRecenterToUserLocation: (Coordinate) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SunMapKitContainerView {
        let container = SunMapKitContainerView()
        let mapView = MKMapView()
        let arcOverlayView = SunMapKitArcOverlayView()
        mapView.delegate = context.coordinator
        mapView.mapType = .hybridFlyover
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.showsCompass = true
        mapView.showsScale = false
        mapView.showsUserLocation = followsUserLocation
        mapView.showsZoomControls = true
        mapView.showsPitchControl = true
        container.install(mapView: mapView, arcOverlayView: arcOverlayView)
        context.coordinator.arcOverlayView = arcOverlayView
        context.coordinator.configureInteractionPause(for: mapView)
        return container
    }

    static func dismantleNSView(_ nsView: SunMapKitContainerView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    func updateNSView(_ container: SunMapKitContainerView, context: Context) {
        let mapView = container.mapView!
        context.coordinator.onRecenterToUserLocation = onRecenterToUserLocation
        context.coordinator.pathRadiusMeters = mode.pathRadiusMeters
        context.coordinator.projectedOverlayLineWidthScale = mode.projectedOverlayLineWidthScale
        context.coordinator.followsUserLocation = followsUserLocation
        mapView.showsUserLocation = followsUserLocation
        context.coordinator.configureOrbit(for: mode, in: mapView)
        let coordinate = CLLocationCoordinate2D(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude
        )

        if context.coordinator.shouldSetInitialCamera(for: centerCoordinate) {
            let launchCamera = mode.launchCamera
            let camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: launchCamera.distance,
                pitch: launchCamera.pitch,
                heading: launchCamera.heading
            )
            mapView.setCamera(camera, animated: false)
        }

        if followsUserLocation {
            context.coordinator.centerOnCurrentLocationIfAvailable(
                in: mapView,
                animated: false
            )
        }

        context.coordinator.recenterIfNeeded(
            in: mapView,
            center: coordinate,
            requestID: recenterRequestID
        )

        context.coordinator.updateOverlays(
            in: mapView,
            arcOverlayView: container.arcOverlayView!,
            center: coordinate,
            pathSamples: pathSamples,
            selectedSample: selectedSample
        )
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var lastCameraCoordinate: Coordinate?
        private var lastRecenterRequestID: Int?
        private var lastCenteredUserCoordinate: CLLocationCoordinate2D?
        private var lastReportedUserCoordinate: Coordinate?
        private var orbitTimer: Timer?
        private var orbitMode: SunMapKitViewMode?
        private var previousOrbitTickDate: Date?
        private var orbitPausedUntil: Date?
        private var interactionEventMonitor: Any?
        private var overlayStyles: [ObjectIdentifier: OverlayRenderStyle] = [:]
        private var staticMapOverlays: [any MKOverlay] = []
        private var dynamicMapOverlays: [any MKOverlay] = []
        private var staticOverlayState: StaticOverlayState?
        private var dynamicOverlayState: DynamicOverlayState?
        weak var arcOverlayView: SunMapKitArcOverlayView?
        var pathRadiusMeters = SunMapKitViewMode.expanded.pathRadiusMeters
        var projectedOverlayLineWidthScale: CGFloat = 1
        var followsUserLocation = true
        var onRecenterToUserLocation: (Coordinate) -> Void = { _ in }
        private let interactionPauseDuration: TimeInterval = 30

        private struct OverlayRenderStyle {
            let style: SunMapKitOverlayStyle
            let lineWidthScale: CGFloat
        }

        private struct StaticOverlayState: Equatable {
            let center: Coordinate
            let pathSamples: [SunPathSample3D]
            let pathRadiusMeters: Double
            let lineWidthScale: CGFloat
        }

        private struct DynamicOverlayState: Equatable {
            let center: Coordinate
            let selectedSample: SunPathSample3D
            let pathRadiusMeters: Double
            let lineWidthScale: CGFloat
        }

        func shouldSetInitialCamera(for coordinate: Coordinate) -> Bool {
            defer {
                lastCameraCoordinate = coordinate
            }

            guard let lastCameraCoordinate else {
                return true
            }

            return abs(lastCameraCoordinate.latitude - coordinate.latitude) > 0.000_001
                || abs(lastCameraCoordinate.longitude - coordinate.longitude) > 0.000_001
        }

        func recenterIfNeeded(
            in mapView: MKMapView,
            center: CLLocationCoordinate2D,
            requestID: Int
        ) {
            guard let lastRecenterRequestID else {
                self.lastRecenterRequestID = requestID
                return
            }

            guard requestID != lastRecenterRequestID else {
                return
            }

            self.lastRecenterRequestID = requestID
            if followsUserLocation,
               centerOnCurrentLocationIfAvailable(in: mapView, animated: true, force: true) {
                return
            }

            let camera = MKMapCamera(
                lookingAtCenter: center,
                fromDistance: mapView.camera.centerCoordinateDistance,
                pitch: mapView.camera.pitch,
                heading: mapView.camera.heading
            )
            mapView.setCamera(camera, animated: true)
            arcOverlayView?.needsDisplay = true
        }

        func configureOrbit(for mode: SunMapKitViewMode, in mapView: MKMapView) {
            guard mode.shouldOrbitCamera else {
                stopOrbit()
                orbitMode = mode
                return
            }

            guard orbitMode != mode || orbitTimer == nil else {
                return
            }

            orbitMode = mode
            previousOrbitTickDate = Date()
            orbitTimer?.invalidate()
            orbitTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self, weak mapView] _ in
                guard let self, let mapView else {
                    return
                }

                Task { @MainActor in
                    self.advanceOrbit(in: mapView)
                }
            }
        }

        @discardableResult
        func centerOnCurrentLocationIfAvailable(
            in mapView: MKMapView,
            animated: Bool,
            force: Bool = false
        ) -> Bool {
            guard followsUserLocation else {
                return false
            }

            guard let location = mapView.userLocation.location else {
                return false
            }

            let userCoordinate = location.coordinate
            guard CLLocationCoordinate2DIsValid(userCoordinate) else {
                return false
            }

            if force || shouldMoveCamera(to: userCoordinate) {
                let camera = MKMapCamera(
                    lookingAtCenter: userCoordinate,
                    fromDistance: mapView.camera.centerCoordinateDistance,
                    pitch: mapView.camera.pitch,
                    heading: mapView.camera.heading
                )
                mapView.setCamera(camera, animated: animated)
                lastCenteredUserCoordinate = userCoordinate
                arcOverlayView?.needsDisplay = true
            }

            reportCurrentLocationIfNeeded(userCoordinate, force: force)
            return true
        }

        func configureInteractionPause(for mapView: MKMapView) {
            guard interactionEventMonitor == nil else {
                return
            }

            let eventMask: NSEvent.EventTypeMask = [
                .leftMouseDown,
                .leftMouseDragged,
                .rightMouseDown,
                .rightMouseDragged,
                .otherMouseDown,
                .otherMouseDragged,
                .scrollWheel,
                .keyDown
            ]

            interactionEventMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self, weak mapView] event in
                guard let self, let mapView else {
                    return event
                }

                if self.shouldPauseOrbit(for: event, in: mapView) {
                    self.pauseOrbitForUserInteraction()
                }

                return event
            }
        }

        func tearDown() {
            stopOrbit()
            if let interactionEventMonitor {
                NSEvent.removeMonitor(interactionEventMonitor)
                self.interactionEventMonitor = nil
            }
        }

        func stopOrbit() {
            orbitTimer?.invalidate()
            orbitTimer = nil
            previousOrbitTickDate = nil
            orbitPausedUntil = nil
        }

        private func advanceOrbit(in mapView: MKMapView) {
            guard let orbitMode, orbitMode.shouldOrbitCamera else {
                stopOrbit()
                return
            }

            let now = Date()
            if let orbitPausedUntil, now < orbitPausedUntil {
                previousOrbitTickDate = now
                return
            }

            orbitPausedUntil = nil
            let elapsed = previousOrbitTickDate.map { now.timeIntervalSince($0) } ?? 0
            previousOrbitTickDate = now
            guard elapsed > 0 else {
                return
            }

            let center = orbitCenter(in: mapView)
            let nextHeading = normalizedHeading(
                mapView.camera.heading + (orbitMode.orbitDegreesPerSecond * elapsed)
            )
            let camera = MKMapCamera(
                lookingAtCenter: center,
                fromDistance: mapView.camera.centerCoordinateDistance,
                pitch: mapView.camera.pitch,
                heading: nextHeading
            )
            mapView.setCamera(camera, animated: false)
            arcOverlayView?.needsDisplay = true
        }

        private func pauseOrbitForUserInteraction() {
            guard orbitMode?.shouldOrbitCamera == true else {
                return
            }

            orbitPausedUntil = Date().addingTimeInterval(interactionPauseDuration)
            previousOrbitTickDate = nil
        }

        private func shouldPauseOrbit(for event: NSEvent, in mapView: MKMapView) -> Bool {
            guard orbitMode?.shouldOrbitCamera == true,
                  let eventWindow = event.window,
                  eventWindow === mapView.window else {
                return false
            }

            let pointInMap = mapView.convert(event.locationInWindow, from: nil)
            return mapView.bounds.contains(pointInMap)
        }

        func updateOverlays(
            in mapView: MKMapView,
            arcOverlayView: SunMapKitArcOverlayView,
            center: CLLocationCoordinate2D,
            pathSamples: [SunPathSample3D],
            selectedSample: SunPathSample3D
        ) {
            arcOverlayView.update(
                mapView: mapView,
                center: center,
                pathSamples: pathSamples,
                selectedSample: selectedSample,
                pathRadiusMeters: pathRadiusMeters
            )
            let coordinate = Coordinate(
                latitude: center.latitude,
                longitude: center.longitude
            )

            let staticState = StaticOverlayState(
                center: coordinate,
                pathSamples: pathSamples,
                pathRadiusMeters: pathRadiusMeters,
                lineWidthScale: projectedOverlayLineWidthScale
            )
            if staticState != staticOverlayState {
                remove(staticMapOverlays, from: mapView)
                let overlays = SunMapKitOverlayFactory.staticOverlays(
                    center: center,
                    pathSamples: pathSamples,
                    pathRadiusMeters: pathRadiusMeters,
                    lineWidthScale: projectedOverlayLineWidthScale
                )
                staticMapOverlays = install(overlays, in: mapView)
                staticOverlayState = staticState
                dynamicOverlayState = nil
            }

            let dynamicState = DynamicOverlayState(
                center: coordinate,
                selectedSample: selectedSample,
                pathRadiusMeters: pathRadiusMeters,
                lineWidthScale: projectedOverlayLineWidthScale
            )
            if dynamicState != dynamicOverlayState {
                remove(dynamicMapOverlays, from: mapView)
                let overlays = SunMapKitOverlayFactory.dynamicOverlays(
                    center: center,
                    selectedSample: selectedSample,
                    pathRadiusMeters: pathRadiusMeters,
                    lineWidthScale: projectedOverlayLineWidthScale
                )
                dynamicMapOverlays = install(overlays, in: mapView)
                dynamicOverlayState = dynamicState
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            arcOverlayView?.needsDisplay = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            arcOverlayView?.needsDisplay = true
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard followsUserLocation else {
                return
            }

            centerOnCurrentLocationIfAvailable(in: mapView, animated: true)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            let renderStyle = overlayStyles[ObjectIdentifier(overlay as AnyObject)]
                ?? OverlayRenderStyle(style: .path, lineWidthScale: 1)

            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderStyle.style.apply(to: renderer, lineWidthScale: renderStyle.lineWidthScale)
                return renderer
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderStyle.style.apply(to: renderer, lineWidthScale: renderStyle.lineWidthScale)
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        private func shouldMoveCamera(to coordinate: CLLocationCoordinate2D) -> Bool {
            guard let lastCenteredUserCoordinate else {
                return true
            }

            return distance(from: lastCenteredUserCoordinate, to: coordinate) > 5
        }

        private func install(
            _ styledOverlays: [StyledSunMapKitOverlay],
            in mapView: MKMapView
        ) -> [any MKOverlay] {
            styledOverlays.map { styledOverlay in
                overlayStyles[ObjectIdentifier(styledOverlay.overlay as AnyObject)] = OverlayRenderStyle(
                    style: styledOverlay.style,
                    lineWidthScale: styledOverlay.lineWidthScale
                )
                mapView.addOverlay(styledOverlay.overlay, level: .aboveLabels)
                return styledOverlay.overlay
            }
        }

        private func remove(_ overlays: [any MKOverlay], from mapView: MKMapView) {
            guard !overlays.isEmpty else {
                return
            }

            mapView.removeOverlays(overlays)
            overlays.forEach {
                overlayStyles.removeValue(forKey: ObjectIdentifier($0 as AnyObject))
            }
        }

        private func reportCurrentLocationIfNeeded(_ coordinate: CLLocationCoordinate2D, force: Bool) {
            let currentCoordinate = Coordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )

            if force || lastReportedUserCoordinate.map({ distance(from: $0, to: currentCoordinate) > 5 }) ?? true {
                lastReportedUserCoordinate = currentCoordinate
                let onRecenterToUserLocation = onRecenterToUserLocation
                Task { @MainActor in
                    onRecenterToUserLocation(currentCoordinate)
                }
            }
        }

        private func distance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
            distance(
                from: Coordinate(latitude: lhs.latitude, longitude: lhs.longitude),
                to: Coordinate(latitude: rhs.latitude, longitude: rhs.longitude)
            )
        }

        private func distance(from lhs: Coordinate, to rhs: Coordinate) -> CLLocationDistance {
            CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
                .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
        }

        private func orbitCenter(in mapView: MKMapView) -> CLLocationCoordinate2D {
            guard followsUserLocation else {
                return mapView.camera.centerCoordinate
            }

            guard let userLocation = mapView.userLocation.location?.coordinate,
                  CLLocationCoordinate2DIsValid(userLocation) else {
                return mapView.camera.centerCoordinate
            }

            lastCenteredUserCoordinate = userLocation
            return userLocation
        }

        private func normalizedHeading(_ heading: CLLocationDirection) -> CLLocationDirection {
            let remainder = heading.truncatingRemainder(dividingBy: 360)
            return remainder >= 0 ? remainder : remainder + 360
        }
    }
}

private extension SunMapKitView {
    var followsUserLocation: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("--readme-screenshots")
            && !arguments.contains("--generic-location")
    }
}

enum SunMapKitViewMode {
    case compact
    case expanded

    var pathRadiusMeters: Double {
        switch self {
        case .compact:
            return 145
        case .expanded:
            return 275
        }
    }

    fileprivate var launchCamera: SunMapKitLaunchCamera {
        let baseCamera: SunMapKitLaunchCamera
        switch self {
        case .compact:
            baseCamera = SunMapKitLaunchCamera(heading: 0, pitch: 70, distance: 560)
        case .expanded:
            baseCamera = SunMapKitLaunchCamera(heading: 0, pitch: 58, distance: 850)
        }

        return baseCamera.applyingLaunchArguments()
    }

    fileprivate var shouldOrbitCamera: Bool {
        switch self {
        case .compact:
            return true
        case .expanded:
            return false
        }
    }

    fileprivate var orbitDegreesPerSecond: CLLocationDirection {
        switch self {
        case .compact:
            return 0.96
        case .expanded:
            return 0
        }
    }

    fileprivate var projectedOverlayLineWidthScale: CGFloat {
        switch self {
        case .compact:
            return 1.25
        case .expanded:
            return 1
        }
    }
}

fileprivate struct SunMapKitLaunchCamera {
    var heading: CLLocationDirection
    var pitch: CGFloat
    var distance: CLLocationDistance

    func applyingLaunchArguments() -> SunMapKitLaunchCamera {
        var camera = self
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--angled-map") {
            camera.heading = 42
            camera.pitch = max(camera.pitch, 62)
        }
        if arguments.contains("--wide-map") {
            camera.distance = 3_200
        }
        if arguments.contains("--close-map") {
            camera.distance = 430
        }

        return camera
    }
}
