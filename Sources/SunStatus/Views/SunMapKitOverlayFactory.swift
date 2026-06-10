import AppKit
import MapKit
import SunStatusCore

struct StyledSunMapKitOverlay {
    let overlay: any MKOverlay
    let style: SunMapKitOverlayStyle
    let lineWidthScale: CGFloat

    init(
        overlay: any MKOverlay,
        style: SunMapKitOverlayStyle,
        lineWidthScale: CGFloat = 1
    ) {
        self.overlay = overlay
        self.style = style
        self.lineWidthScale = lineWidthScale
    }
}

enum SunMapKitOverlayFactory {
    static func overlays(
        center: CLLocationCoordinate2D,
        pathSamples: [SunPathSample3D],
        selectedSample: SunPathSample3D,
        pathRadiusMeters: Double,
        lineWidthScale: CGFloat = 1
    ) -> [StyledSunMapKitOverlay] {
        staticOverlays(
            center: center,
            pathSamples: pathSamples,
            pathRadiusMeters: pathRadiusMeters,
            lineWidthScale: lineWidthScale
        ) + dynamicOverlays(
            center: center,
            selectedSample: selectedSample,
            pathRadiusMeters: pathRadiusMeters,
            lineWidthScale: lineWidthScale
        )
    }

    static func staticOverlays(
        center: CLLocationCoordinate2D,
        pathSamples: [SunPathSample3D],
        pathRadiusMeters: Double,
        lineWidthScale: CGFloat = 1
    ) -> [StyledSunMapKitOverlay] {
        var overlays: [StyledSunMapKitOverlay] = []

        if let horizon = projectedCircle(
            center: center,
            radiusMeters: pathRadiusMeters,
            segmentCount: 96
        ) {
            overlays.append(
                StyledSunMapKitOverlay(
                    overlay: horizon,
                    style: .horizon,
                    lineWidthScale: lineWidthScale
                )
            )
        }

        if let groundPath = groundProjectedPath(
            center: center,
            pathSamples: pathSamples,
            pathRadiusMeters: pathRadiusMeters
        ) {
            overlays.append(
                StyledSunMapKitOverlay(
                    overlay: groundPath,
                    style: .groundSunPath,
                    lineWidthScale: lineWidthScale
                )
            )
        }

        return overlays
    }

    static func dynamicOverlays(
        center: CLLocationCoordinate2D,
        selectedSample: SunPathSample3D,
        pathRadiusMeters: Double,
        lineWidthScale: CGFloat = 1
    ) -> [StyledSunMapKitOverlay] {
        var overlays: [StyledSunMapKitOverlay] = []

        if let sunDirectionLine = sunDirectionLine(
            center: center,
            sample: selectedSample,
            pathRadiusMeters: pathRadiusMeters
        ) {
            overlays.append(
                StyledSunMapKitOverlay(
                    overlay: sunDirectionLine,
                    style: .groundSunDirection,
                    lineWidthScale: lineWidthScale
                )
            )
        }

        if let shadowDirection = selectedSample.shadowDirection,
           let shadowLine = vectorLine(
            center: center,
            direction: shadowDirection,
            distanceMeters: groundProjectionLengthMeters(
                for: selectedSample,
                pathRadiusMeters: pathRadiusMeters
            )
           ) {
            overlays.append(
                StyledSunMapKitOverlay(
                    overlay: shadowLine,
                    style: .shadowVector,
                    lineWidthScale: lineWidthScale
                )
            )
        }

        if let centerRing = projectedCircle(
            center: center,
            radiusMeters: 8,
            segmentCount: 32
        ) {
            overlays.append(
                StyledSunMapKitOverlay(
                    overlay: centerRing,
                    style: .center,
                    lineWidthScale: lineWidthScale
                )
            )
        }

        return overlays
    }

    private static func groundProjectedPath(
        center: CLLocationCoordinate2D,
        pathSamples: [SunPathSample3D],
        pathRadiusMeters: Double
    ) -> MKPolyline? {
        let coordinates = pathSamples
            .filter { $0.elevationDegrees >= -1 }
            .map { sample in
                groundProjectionCoordinate(
                    center: center,
                    direction: sample.direction,
                    pathRadiusMeters: pathRadiusMeters
                )
            }

        return makePolyline(coordinates)
    }

    private static func sunDirectionLine(
        center: CLLocationCoordinate2D,
        sample: SunPathSample3D,
        pathRadiusMeters: Double
    ) -> MKPolyline? {
        guard sample.elevationDegrees >= -1 else {
            return nil
        }

        return makePolyline([
            center,
            groundProjectionCoordinate(
                center: center,
                direction: sample.direction,
                pathRadiusMeters: pathRadiusMeters
            )
        ])
    }

    private static func groundProjectionCoordinate(
        center: CLLocationCoordinate2D,
        direction: SunVector3,
        pathRadiusMeters: Double
    ) -> CLLocationCoordinate2D {
        SunMapKitGeometry.coordinate(
            from: center,
            eastMeters: direction.x * pathRadiusMeters,
            northMeters: direction.z * pathRadiusMeters
        )
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

    private static func groundProjectionLengthMeters(
        for sample: SunPathSample3D,
        pathRadiusMeters: Double
    ) -> Double {
        hypot(sample.direction.x, sample.direction.z) * pathRadiusMeters
    }

    private static func projectedCircle(
        center: CLLocationCoordinate2D,
        radiusMeters: Double,
        segmentCount: Int
    ) -> MKPolyline? {
        guard segmentCount >= 8, radiusMeters > 0 else {
            return nil
        }

        let coordinates = (0...segmentCount).map { index in
            let angle = (Double(index) / Double(segmentCount)) * (2 * Double.pi)
            return SunMapKitGeometry.coordinate(
                from: center,
                eastMeters: sin(angle) * radiusMeters,
                northMeters: cos(angle) * radiusMeters
            )
        }

        return makePolyline(coordinates)
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
    case groundSunPath
    case groundSunDirection
    case path
    case shadowVector

    func apply(to renderer: MKOverlayPathRenderer, lineWidthScale: CGFloat = 1) {
        switch self {
        case .center:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.white.withAlphaComponent(0.95)
            renderer.lineWidth = 2.2 * lineWidthScale
        case .horizon:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.42)
            renderer.lineWidth = 1.5 * lineWidthScale
        case .groundSunPath:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.72)
            renderer.lineWidth = 2.2 * lineWidthScale
            renderer.lineDashPattern = [8, 6]
        case .groundSunDirection:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.66)
            renderer.lineWidth = 3 * lineWidthScale
            renderer.lineDashPattern = [8, 6]
        case .path:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.32)
            renderer.lineWidth = 1.4
        case .shadowVector:
            renderer.fillColor = NSColor.clear
            renderer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.66)
            renderer.lineWidth = 2.8 * lineWidthScale
            renderer.lineDashPattern = [8, 6]
        }
    }
}
