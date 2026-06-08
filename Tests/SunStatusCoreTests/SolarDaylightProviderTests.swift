import XCTest
@testable import SunStatusCore

final class SolarDaylightProviderTests: XCTestCase {
    func testSummerStatusContainsOrderedSolarEventsAndAngles() throws {
        let provider = sanFranciscoProvider()
        let noon = try XCTUnwrap(makeDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0))

        let status = provider.status(at: noon)
        let sunrise = try XCTUnwrap(status.solar.sunrise)
        let solarNoon = try XCTUnwrap(status.solar.solarNoon)
        let sunset = try XCTUnwrap(status.solar.sunset)

        XCTAssertLessThan(sunrise, solarNoon)
        XCTAssertLessThan(solarNoon, sunset)
        XCTAssertGreaterThan(sunset.timeIntervalSince(sunrise), 14 * 3_600)
        XCTAssertLessThan(sunset.timeIntervalSince(sunrise), 15.5 * 3_600)
        XCTAssertGreaterThan(status.solar.elevationDegrees, 60)
        XCTAssertLessThan(status.solar.elevationDegrees, 75)
        XCTAssertGreaterThan(status.solar.azimuthDegrees, 120)
        XCTAssertLessThan(status.solar.azimuthDegrees, 190)
        XCTAssertNotNil(status.solar.daylightProgress)
    }

    func testNightStatusFallsBelowHorizon() throws {
        let provider = sanFranciscoProvider()
        let night = try XCTUnwrap(makeDate(year: 2026, month: 6, day: 21, hour: 23, minute: 0))

        let status = provider.status(at: night)

        XCTAssertLessThan(status.solar.elevationDegrees, 0)
        XCTAssertNil(status.solar.daylightProgress)
        XCTAssertEqual(status.brightness.classification, .dark)
    }

    func testArcPointsCoverCalculatedDaylightPath() throws {
        let provider = sanFranciscoProvider()
        let noon = try XCTUnwrap(makeDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0))

        let status = provider.status(at: noon)
        let sunrise = try XCTUnwrap(status.solar.sunrise)
        let sunset = try XCTUnwrap(status.solar.sunset)
        let progresses = status.arcPoints.map(\.progress)

        XCTAssertEqual(status.arcPoints.count, 13)
        XCTAssertEqual(progresses.first, 0)
        XCTAssertEqual(progresses.last, 1)
        XCTAssertEqual(progresses, progresses.sorted())
        XCTAssertEqual(status.arcPoints.first?.date, sunrise)
        XCTAssertEqual(status.arcPoints.last?.date, sunset)
        XCTAssertTrue(status.arcPoints.allSatisfy { point in
            guard let score = point.brightnessScore else {
                return false
            }

            return (0...1).contains(score)
        })
    }

    private func sanFranciscoProvider() -> SolarDaylightProvider {
        SolarDaylightProvider(
            locationName: "San Francisco",
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            timezone: TimeZone(identifier: "America/Los_Angeles")!
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))
    }
}
