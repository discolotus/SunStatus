import AppKit
import MapKit
import SunStatusCore

struct StyledSunMapKitOverlay {
    let overlay: any MKOverlay
    let style: SunMapKitOverlayStyle
}

enum SunMapKitOverlayFactory {
    private static let pathRadiusMeters = 275.0

    static func overlays(
        center: CLLocationCoordinate2D,
        selectedSample: SunPathSample3D
    ) -> [StyledSunMapKitOverlay] {
        var overlays: [StyledSunMapKitOverlay] = [
            StyledSunMapKitOverlay(
                overlay: MKCircle(center: center, radius: pathRadiusMeters),
                style: .horizon
            ),
            StyledSunMapKitOverlay(
                overlay: MKCircle(center: center, radius: 8),
                style: .center
            )
        ]

        if let shadowDirection = selectedSample.shadowDirection,
           let shadowLine = vectorLine(
            center: center,
            direction: shadowDirection,
            distanceMeters: shadowLengthMeters(for: selectedSample)
           ) {
            overlays.append(StyledSunMapKitOverlay(overlay: shadowLine, style: .shadowVector))
        }

        return overlays
    }

    private static func vectorLine(
        center: CLLocationCoordinate2D,
        direction: SunVector3,
        distanceMeters: Double
    ) -> MKPolyline? {
        makePolyline([
            center,
            SunMapKitGeometry.coordinate(
                from: center,
                eastMeters: direction.x * distanceMeters,
                northMeters: direction.z * distanceMeters
            )
        ])
    }

    private static func shadowLengthMeters(for sample: SunPathSample3D) -> Double {
        let elevationFactor = max(0, min(sample.elevationDegrees / 80, 1))
        return 135 + ((1 - elevationFactor) * 285)
    }

    private static func makePolyline(_ coordinates: [CLLocationCoordinate2D]) -> MKPolyline? {
        guard coordinates.count >= 2 else {
            return nil
        }

        var mutableCoordinates = coordinates
        return MKPolyline(coordinates: &mutableCoordinates, count: mutableCoordinates.count)
    }
}

enum SunMapKitOverlayStyle {
    case center
    case horizon
    case path
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
            renderer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.32)
            renderer.lineWidth = 1.4
        case .shadowVector:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.86)
            renderer.lineWidth = 3
        }
    }
}
