import AppKit
import MapKit
import SwiftUI
import SunStatusCore

struct SunMapKitView: NSViewRepresentable {
    let centerCoordinate: Coordinate
    let pathSamples: [SunPathSample3D]
    let selectedSample: SunPathSample3D
    var recenterRequestID = 0

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
        mapView.showsUserLocation = true
        mapView.showsZoomControls = true
        mapView.showsPitchControl = true
        container.install(mapView: mapView, arcOverlayView: arcOverlayView)
        context.coordinator.arcOverlayView = arcOverlayView
        return container
    }

    func updateNSView(_ container: SunMapKitContainerView, context: Context) {
        let mapView = container.mapView!
        let coordinate = CLLocationCoordinate2D(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude
        )

        if context.coordinator.shouldSetInitialCamera(for: centerCoordinate) {
            let launchCamera = SunMapKitLaunchCamera.default
            let camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: launchCamera.distance,
                pitch: launchCamera.pitch,
                heading: launchCamera.heading
            )
            mapView.setCamera(camera, animated: false)
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
        private var overlayStyles: [ObjectIdentifier: SunMapKitOverlayStyle] = [:]
        weak var arcOverlayView: SunMapKitArcOverlayView?

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
            if CLLocationCoordinate2DIsValid(mapView.userLocation.coordinate),
               mapView.userLocation.location != nil {
                mapView.setUserTrackingMode(.follow, animated: true)
                arcOverlayView?.needsDisplay = true
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
                selectedSample: selectedSample
            )
            mapView.removeOverlays(mapView.overlays)
            overlayStyles.removeAll()

            let overlays = SunMapKitOverlayFactory.overlays(
                center: center,
                selectedSample: selectedSample
            )

            for overlay in overlays {
                overlayStyles[ObjectIdentifier(overlay.overlay as AnyObject)] = overlay.style
                mapView.addOverlay(overlay.overlay, level: .aboveLabels)
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            arcOverlayView?.needsDisplay = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            arcOverlayView?.needsDisplay = true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            let style = overlayStyles[ObjectIdentifier(overlay as AnyObject)] ?? .path

            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                style.apply(to: renderer)
                return renderer
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                style.apply(to: renderer)
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

private struct SunMapKitLaunchCamera {
    var heading: CLLocationDirection
    var pitch: CGFloat
    var distance: CLLocationDistance

    static var `default`: SunMapKitLaunchCamera {
        var camera = SunMapKitLaunchCamera(heading: 0, pitch: 58, distance: 850)
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--angled-map") {
            camera.heading = 42
            camera.pitch = 42
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
