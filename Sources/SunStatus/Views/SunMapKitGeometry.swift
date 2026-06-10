import MapKit

enum SunMapKitGeometry {
    struct MercatorOffset {
        let eastMeters: Double
        let northMeters: Double
    }

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

    static func mercatorOffset(
        from origin: CLLocationCoordinate2D,
        to coordinate: CLLocationCoordinate2D
    ) -> MercatorOffset {
        let originPoint = MKMapPoint(origin)
        let coordinatePoint = MKMapPoint(coordinate)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(origin.latitude)

        var deltaX = coordinatePoint.x - originPoint.x
        let worldWidth = MKMapRect.world.size.width
        if deltaX > worldWidth / 2 {
            deltaX -= worldWidth
        } else if deltaX < -worldWidth / 2 {
            deltaX += worldWidth
        }

        return MercatorOffset(
            eastMeters: deltaX / pointsPerMeter,
            northMeters: -(coordinatePoint.y - originPoint.y) / pointsPerMeter
        )
    }
}
