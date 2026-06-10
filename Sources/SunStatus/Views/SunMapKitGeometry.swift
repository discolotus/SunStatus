import MapKit

enum SunMapKitGeometry {
    static func coordinate(
        from center: CLLocationCoordinate2D,
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
}
