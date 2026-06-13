import XCTest
@testable import SunStatusCore

final class SolarDaylightProviderTests: XCTestCase {
    func testStatusContainsOrderedSolarEvents() throws {
        let provider = SolarDaylightProvider()
        let now = try XCTUnwrap(makeDate(hour: 12, minute: 0))

        let status = provider.status(at: now)
        let sunrise = try XCTUnwrap(status.solar.sunrise)
        let solarNoon = try XCTUnwrap(status.solar.solarNoon)
        let sunset = try XCTUnwrap(status.solar.sunset)

        XCTAssertLessThan(sunrise, solarNoon)
        XCTAssertLessThan(solarNoon, sunset)
    }

    func testDaylightProgressIsAvailableDuringDay() throws {
        let provider = SolarDaylightProvider()
        let now = try XCTUnwrap(makeDate(hour: 12, minute: 0))

        let status = provider.status(at: now)
        let progress = try XCTUnwrap(status.solar.daylightProgress)

        XCTAssertGreaterThan(progress, 0)
        XCTAssertLessThan(progress, 1)
    }

    func testDaylightProgressIsNilAtNight() throws {
        let provider = SolarDaylightProvider()
        let now = try XCTUnwrap(makeDate(hour: 1, minute: 0))

        let status = provider.status(at: now)

        XCTAssertNil(status.solar.daylightProgress)
        XCTAssertEqual(status.brightness.classification, .dark)
    }

    func testNightArcPointsAfterSunsetUseNextDaylightPath() throws {
        let provider = SolarDaylightProvider()
        let now = try XCTUnwrap(makeDate(hour: 23, minute: 0))

        let status = provider.status(at: now)
        let firstPoint = try XCTUnwrap(status.arcPoints.first)
        let lastPoint = try XCTUnwrap(status.arcPoints.last)

        XCTAssertNil(status.solar.daylightProgress)
        XCTAssertGreaterThan(firstPoint.date, now)
        XCTAssertGreaterThan(lastPoint.date, firstPoint.date)
        XCTAssertEqual(firstPoint.progress, 0)
        XCTAssertEqual(lastPoint.progress, 1)
    }

    func testArcPointsCoverFullDaylightPath() throws {
        let provider = SolarDaylightProvider()
        let now = try XCTUnwrap(makeDate(hour: 12, minute: 0))

        let status = provider.status(at: now)
        let progresses = status.arcPoints.map(\.progress)

        XCTAssertEqual(progresses.first, 0)
        XCTAssertEqual(progresses.last, 1)
        XCTAssertEqual(progresses, progresses.sorted())
        XCTAssertTrue(status.arcPoints.allSatisfy { point in
            guard let score = point.brightnessScore else {
                return false
            }

            return (0...1).contains(score)
        })
    }

    func testArcPeaksNearSolarNoonElevation() throws {
        let provider = SolarDaylightProvider()
        let now = try XCTUnwrap(makeDate(hour: 12, minute: 0))

        let status = provider.status(at: now)
        let maxArcElevation = try XCTUnwrap(status.arcPoints.map(\.elevationDegrees).max())
        let solarNoon = try XCTUnwrap(status.solar.solarNoon)
        let noonElevation = SolarPositionCalculator.position(
            at: solarNoon,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194)
        ).elevationDegrees

        // The highest sampled point should sit just shy of the true solar-noon altitude.
        XCTAssertEqual(maxArcElevation, noonElevation, accuracy: 1.0)
        XCTAssertGreaterThan(maxArcElevation, 0)
    }

    private func makeDate(hour: Int, minute: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 21,
            hour: hour,
            minute: minute
        ))
    }
}
