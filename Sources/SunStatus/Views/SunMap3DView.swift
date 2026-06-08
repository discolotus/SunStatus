import AppKit
import MapKit
import SwiftUI
import SunStatusCore

struct SunMap3DView: NSViewRepresentable {
    let centerCoordinate: Coordinate
    let pathSamples: [SunPathSample3D]
    let selectedSample: SunPathSample3D

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.showsCompass = true
        mapView.showsScale = false
        mapView.showsZoomControls = true
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinate = CLLocationCoordinate2D(
            latitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude
        )

        if context.coordinator.shouldSetInitialCamera(for: centerCoordinate) {
            let camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: 900,
                pitch: 58,
                heading: 0
            )
            mapView.setCamera(camera, animated: false)
        }

        context.coordinator.updateOverlays(
            in: mapView,
            center: coordinate,
            pathSamples: pathSamples,
            selectedSample: selectedSample
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var lastCameraCoordinate: Coordinate?
        private var overlayStyles: [ObjectIdentifier: SunMapOverlayStyle] = [:]

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

        func updateOverlays(
            in mapView: MKMapView,
            center: CLLocationCoordinate2D,
            pathSamples: [SunPathSample3D],
            selectedSample: SunPathSample3D
        ) {
            mapView.removeOverlays(mapView.overlays)
            overlayStyles.removeAll()

            let overlays = SunMapOverlayFactory.overlays(
                center: center,
                pathSamples: pathSamples,
                selectedSample: selectedSample
            )

            for overlay in overlays {
                overlayStyles[ObjectIdentifier(overlay.overlay as AnyObject)] = overlay.style
                mapView.addOverlay(overlay.overlay, level: .aboveLabels)
            }
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

private struct StyledSunMapOverlay {
    let overlay: any MKOverlay
    let style: SunMapOverlayStyle
}

private enum SunMapOverlayFactory {
    private static let pathRadiusMeters = 275.0

    static func overlays(
        center: CLLocationCoordinate2D,
        pathSamples: [SunPathSample3D],
        selectedSample: SunPathSample3D
    ) -> [StyledSunMapOverlay] {
        var overlays: [StyledSunMapOverlay] = [
            StyledSunMapOverlay(
                overlay: MKCircle(center: center, radius: pathRadiusMeters),
                style: .horizon
            ),
            StyledSunMapOverlay(
                overlay: MKCircle(center: center, radius: 8),
                style: .center
            )
        ]

        if let path = polyline(for: pathSamples, center: center, distanceMeters: pathRadiusMeters) {
            overlays.append(StyledSunMapOverlay(overlay: path, style: .path))
        }

        if let sunVector = vectorLine(
            center: center,
            direction: selectedSample.direction,
            distanceMeters: pathRadiusMeters
        ) {
            overlays.append(StyledSunMapOverlay(overlay: sunVector, style: .sunVector))
        }

        if let shadowDirection = selectedSample.shadowDirection,
           let shadowLine = vectorLine(
            center: center,
            direction: shadowDirection,
            distanceMeters: shadowLengthMeters(for: selectedSample)
           ) {
            overlays.append(StyledSunMapOverlay(overlay: shadowLine, style: .shadowVector))
        }

        return overlays
    }

    private static func polyline(
        for samples: [SunPathSample3D],
        center: CLLocationCoordinate2D,
        distanceMeters: Double
    ) -> MKPolyline? {
        let coordinates = samples.map {
            projectedCoordinate(
                center: center,
                eastMeters: $0.direction.x * distanceMeters,
                northMeters: $0.direction.z * distanceMeters
            )
        }

        return makePolyline(coordinates)
    }

    private static func vectorLine(
        center: CLLocationCoordinate2D,
        direction: SunVector3,
        distanceMeters: Double
    ) -> MKPolyline? {
        makePolyline([
            center,
            projectedCoordinate(
                center: center,
                eastMeters: direction.x * distanceMeters,
                northMeters: direction.z * distanceMeters
            )
        ])
    }

    private static func shadowLengthMeters(for sample: SunPathSample3D) -> Double {
        let elevationFactor = max(0, min(sample.elevationDegrees / 80, 1))
        return 135 + ((1 - elevationFactor) * 285)
    }

    private static func projectedCoordinate(
        center: CLLocationCoordinate2D,
        eastMeters: Double,
        northMeters: Double
    ) -> CLLocationCoordinate2D {
        let centerPoint = MKMapPoint(center)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(center.latitude)
        let mapPoint = MKMapPoint(
            x: centerPoint.x + (eastMeters * pointsPerMeter),
            y: centerPoint.y - (northMeters * pointsPerMeter)
        )

        return mapPoint.coordinate
    }

    private static func makePolyline(_ coordinates: [CLLocationCoordinate2D]) -> MKPolyline? {
        guard coordinates.count >= 2 else {
            return nil
        }

        var mutableCoordinates = coordinates
        return MKPolyline(coordinates: &mutableCoordinates, count: mutableCoordinates.count)
    }
}

private enum SunMapOverlayStyle {
    case center
    case horizon
    case path
    case sunVector
    case shadowVector

    func apply(to renderer: MKOverlayPathRenderer) {
        switch self {
        case .center:
            renderer.fillColor = NSColor.white.withAlphaComponent(0.9)
            renderer.strokeColor = NSColor.black.withAlphaComponent(0.4)
            renderer.lineWidth = 1.5
        case .horizon:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.42)
            renderer.lineWidth = 1.5
        case .path:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.95)
            renderer.lineWidth = 3.5
        case .sunVector:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.9)
            renderer.lineWidth = 3
        case .shadowVector:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.86)
            renderer.lineWidth = 3
        }
    }
}
