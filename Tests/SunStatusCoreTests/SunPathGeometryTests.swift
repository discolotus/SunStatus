import XCTest
@testable import SunStatusCore

final class SunPathGeometryTests: XCTestCase {
    func testDirectionUsesCompassAzimuth() {
        let north = SunPathGeometry.direction(azimuthDegrees: 0, elevationDegrees: 0)
        XCTAssertEqual(north.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(north.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(north.z, 1, accuracy: 0.000_001)

        let east = SunPathGeometry.direction(azimuthDegrees: 90, elevationDegrees: 0)
        XCTAssertEqual(east.x, 1, accuracy: 0.000_001)
        XCTAssertEqual(east.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(east.z, 0, accuracy: 0.000_001)

        let overhead = SunPathGeometry.direction(azimuthDegrees: 215, elevationDegrees: 90)
        XCTAssertEqual(overhead.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(overhead.y, 1, accuracy: 0.000_001)
        XCTAssertEqual(overhead.z, 0, accuracy: 0.000_001)
    }

    func testShadowBearingOpposesSunAzimuth() throws {
        let shadowDirection = try XCTUnwrap(SunPathGeometry.shadowDirection(azimuthDegrees: 90, elevationDegrees: 30))
        XCTAssertEqual(shadowDirection.x, -1, accuracy: 0.000_001)
        XCTAssertEqual(shadowDirection.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(shadowDirection.z, 0, accuracy: 0.000_001)
        XCTAssertEqual(SunPathGeometry.shadowBearingDegrees(azimuthDegrees: 90, elevationDegrees: 30), 270)
        XCTAssertEqual(SunPathGeometry.shadowBearingDegrees(azimuthDegrees: 350, elevationDegrees: 10), 170)
    }

    func testNoSurfaceShadowWhenSunIsBelowHorizon() {
        XCTAssertNil(SunPathGeometry.shadowDirection(azimuthDegrees: 120, elevationDegrees: -2))
        XCTAssertNil(SunPathGeometry.shadowBearingDegrees(azimuthDegrees: 120, elevationDegrees: -2))
    }

    func testSampleInterpolatesBetweenArcPoints() {
        let startDate = Date(timeIntervalSince1970: 1_000)
        let endDate = Date(timeIntervalSince1970: 1_100)
        let points = [
            SunArcPoint(date: startDate, progress: 0, elevationDegrees: 0, azimuthDegrees: 80, brightnessScore: 0.2),
            SunArcPoint(date: endDate, progress: 1, elevationDegrees: 60, azimuthDegrees: 200, brightnessScore: 0.8)
        ]
        let fallback = SolarSnapshot(
            date: startDate,
            location: Coordinate(latitude: 0, longitude: 0),
            sunrise: nil,
            solarNoon: nil,
            sunset: nil,
            elevationDegrees: 5,
            azimuthDegrees: 90,
            daylightProgress: nil
        )

        let sample = SunPathGeometry.sample(at: 0.25, arcPoints: points, fallback: fallback)

        XCTAssertEqual(sample.date.timeIntervalSince1970, 1_025, accuracy: 0.000_001)
        XCTAssertEqual(sample.progress, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(sample.elevationDegrees, 15, accuracy: 0.000_001)
        XCTAssertEqual(sample.azimuthDegrees, 110, accuracy: 0.000_001)
    }
}
