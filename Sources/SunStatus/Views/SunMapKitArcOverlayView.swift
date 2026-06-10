import AppKit
import MapKit
import SunStatusCore

final class SunMapKitArcOverlayView: NSView {
    weak var mapView: MKMapView?
    private var center: CLLocationCoordinate2D?
    private var pathSamples: [SunPathSample3D] = []
    private var selectedSample: SunPathSample3D?
    private var pathRadiusMeters = 275.0

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(
        mapView: MKMapView,
        center: CLLocationCoordinate2D,
        pathSamples: [SunPathSample3D],
        selectedSample: SunPathSample3D,
        pathRadiusMeters: Double
    ) {
        self.mapView = mapView
        self.center = center
        self.pathSamples = pathSamples
        self.selectedSample = selectedSample
        self.pathRadiusMeters = pathRadiusMeters
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let mapView, let center, let selectedSample else {
            return
        }

        drawPath(pathSamples.map { screenPoint(for: $0, mapView: mapView, center: center) })

        guard let centerPoint = screenPoint(forGroundCoordinate: center, mapView: mapView),
              let selectedPoint = screenPoint(for: selectedSample, mapView: mapView, center: center) else {
            return
        }

        drawSunVector(from: centerPoint, to: selectedPoint)
        drawSunDisc(at: selectedPoint)
    }

    private func screenPoint(
        for sample: SunPathSample3D,
        mapView: MKMapView,
        center: CLLocationCoordinate2D
    ) -> CGPoint? {
        guard sample.elevationDegrees >= -1 else {
            return nil
        }

        let direction = sample.direction
        let worldPoint = SunVector3(
            x: direction.x * pathRadiusMeters,
            y: max(direction.y * pathRadiusMeters, 4),
            z: direction.z * pathRadiusMeters
        )
        let camera = SunArcCamera(
            headingDegrees: mapView.camera.heading,
            pitchDegrees: mapView.camera.pitch,
            centerDistanceMeters: mapView.camera.centerCoordinateDistance
        )
        let cameraCenterOffset = SunMapKitGeometry.mercatorOffset(
            from: center,
            to: mapView.camera.centerCoordinate
        )
        let pointRelativeToCameraCenter = SunVector3(
            x: worldPoint.x - cameraCenterOffset.eastMeters,
            y: worldPoint.y,
            z: worldPoint.z - cameraCenterOffset.northMeters
        )

        guard let groundPointRelativeToCameraCenter = SunArcProjection.groundIntersection(
            of: pointRelativeToCameraCenter,
            camera: camera
        ) else {
            return nil
        }
        let groundPoint = SunVector3(
            x: groundPointRelativeToCameraCenter.x + cameraCenterOffset.eastMeters,
            y: 0,
            z: groundPointRelativeToCameraCenter.z + cameraCenterOffset.northMeters
        )

        let coordinate = SunMapKitGeometry.coordinate(
            from: center,
            eastMeters: groundPoint.x,
            northMeters: groundPoint.z
        )
        return screenPoint(forGroundCoordinate: coordinate, mapView: mapView)
    }

    private func screenPoint(
        forGroundCoordinate coordinate: CLLocationCoordinate2D,
        mapView: MKMapView
    ) -> CGPoint? {
        let point = mapView.convert(coordinate, toPointTo: self)
        guard point.x.isFinite, point.y.isFinite else {
            return nil
        }
        return point
    }

    private func drawPath(_ points: [CGPoint?]) {
        let casing = connectedPath(from: points)
        casing.lineWidth = 7
        NSColor.black.withAlphaComponent(0.32).setStroke()
        casing.stroke()

        let glow = connectedPath(from: points)
        glow.lineWidth = 4
        NSColor.systemYellow.withAlphaComponent(0.32).setStroke()
        glow.stroke()

        let path = connectedPath(from: points)
        path.lineWidth = 2.6
        NSColor.systemYellow.withAlphaComponent(0.92).setStroke()
        path.stroke()
    }

    private func connectedPath(from points: [CGPoint?]) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        var didMove = false
        for point in points {
            guard let point else {
                didMove = false
                continue
            }

            if didMove {
                path.line(to: point)
            } else {
                path.move(to: point)
                didMove = true
            }
        }

        return path
    }

    private func drawSunVector(from centerPoint: CGPoint, to sunPoint: CGPoint) {
        let path = NSBezierPath()
        path.move(to: centerPoint)
        path.line(to: sunPoint)
        path.lineCapStyle = .round
        path.lineWidth = 3.2

        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.stroke()

        path.lineWidth = 2.2
        NSColor.systemOrange.withAlphaComponent(0.95).setStroke()
        path.stroke()
    }

    private func drawSunDisc(at point: CGPoint) {
        let diameter: CGFloat = 34
        let rect = NSRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.set()

        let disc = NSBezierPath(ovalIn: rect)
        NSColor.systemOrange.setFill()
        disc.fill()

        NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0)
        NSColor.white.withAlphaComponent(0.92).setStroke()
        disc.lineWidth = 2
        disc.stroke()

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let symbol = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Current sun position")?
            .withSymbolConfiguration(symbolConfiguration)
        symbol?.draw(
            in: rect.insetBy(dx: 8, dy: 8),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }
}
