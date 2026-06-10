import AppKit
import MapKit

final class SunMapKitContainerView: NSView {
    private(set) var mapView: MKMapView!
    private(set) var arcOverlayView: SunMapKitArcOverlayView!

    func install(mapView: MKMapView, arcOverlayView: SunMapKitArcOverlayView) {
        subviews.forEach { $0.removeFromSuperview() }
        self.mapView = mapView
        self.arcOverlayView = arcOverlayView

        mapView.translatesAutoresizingMaskIntoConstraints = false
        arcOverlayView.translatesAutoresizingMaskIntoConstraints = false
        arcOverlayView.mapView = mapView

        addSubview(mapView)
        mapView.addSubview(arcOverlayView)

        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            arcOverlayView.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
            arcOverlayView.trailingAnchor.constraint(equalTo: mapView.trailingAnchor),
            arcOverlayView.topAnchor.constraint(equalTo: mapView.topAnchor),
            arcOverlayView.bottomAnchor.constraint(equalTo: mapView.bottomAnchor)
        ])
    }
}
