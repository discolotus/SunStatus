import XCTest
@testable import SunStatusCore

final class SolarPositionTests: XCTestCase {
    private let sanFrancisco = Coordinate(latitude: 37.7749, longitude: -122.4194)
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    // MARK: - Declination

    func testDeclinationMatchesSolsticesAndEquinox() {
        // The sun's declination reaches ±23.44° at the solstices and crosses zero at the equinoxes.
        XCTAssertEqual(declination(year: 2026, month: 6, day: 21), 23.44, accuracy: 0.4)
        XCTAssertEqual(declination(year: 2026, month: 12, day: 21), -23.44, accuracy: 0.4)
        XCTAssertEqual(declination(year: 2026, month: 3, day: 20), 0, accuracy: 1.0)
        XCTAssertEqual(declination(year: 2026, month: 9, day: 22), 0, accuracy: 1.0)
    }

    // MARK: - Solar noon geometry

    func testSolarNoonElevationAndAzimuth() throws {
        let noon = try XCTUnwrap(events(year: 2026, month: 6, day: 21).solarNoon)
        let position = SolarPositionCalculator.position(at: noon, coordinate: sanFrancisco)

        // At local solar noon the sun is due south for a northern mid-latitude observer,
        // and its altitude is 90° − latitude + declination.
        let expectedElevation = 90 - sanFrancisco.latitude + position.declinationDegrees
        XCTAssertEqual(position.elevationDegrees, expectedElevation, accuracy: 0.8)
        XCTAssertEqual(position.azimuthDegrees, 180, accuracy: 2.0)
    }

    func testSolarNoonFallsAroundLocalSolarTime() throws {
        // San Francisco sits well west of its time-zone meridian, so solar noon lands
        // after 13:00 during Pacific Daylight Time.
        let noon = try XCTUnwrap(events(year: 2026, month: 6, day: 21).solarNoon)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let components = calendar.dateComponents([.hour, .minute], from: noon)

        XCTAssertEqual(components.hour, 13)
        XCTAssertLessThanOrEqual(components.minute ?? 0, 25)
    }

    // MARK: - Sunrise / sunset

    func testSunriseSunsetAreOrderedAndSymmetric() throws {
        let dayEvents = events(year: 2026, month: 6, day: 21)
        let sunrise = try XCTUnwrap(dayEvents.sunrise)
        let solarNoon = try XCTUnwrap(dayEvents.solarNoon)
        let sunset = try XCTUnwrap(dayEvents.sunset)

        XCTAssertLessThan(sunrise, solarNoon)
        XCTAssertLessThan(solarNoon, sunset)

        // Sunrise and sunset are symmetric about solar noon to within a minute.
        let morning = solarNoon.timeIntervalSince(sunrise)
        let evening = sunset.timeIntervalSince(solarNoon)
        XCTAssertEqual(morning, evening, accuracy: 90)
    }

    func testSunIsNearHorizonAtSunriseAndSunset() throws {
        let dayEvents = events(year: 2026, month: 6, day: 21)
        let sunrise = try XCTUnwrap(dayEvents.sunrise)
        let sunset = try XCTUnwrap(dayEvents.sunset)

        let sunrisePosition = SolarPositionCalculator.position(at: sunrise, coordinate: sanFrancisco)
        let sunsetPosition = SolarPositionCalculator.position(at: sunset, coordinate: sanFrancisco)

        // The sun straddles the horizon at the computed event times.
        XCTAssertEqual(sunrisePosition.elevationDegrees, 0, accuracy: 1.0)
        XCTAssertEqual(sunsetPosition.elevationDegrees, 0, accuracy: 1.0)

        // It rises in the eastern half of the sky and sets in the western half.
        XCTAssertLessThan(sunrisePosition.azimuthDegrees, 180)
        XCTAssertGreaterThan(sunsetPosition.azimuthDegrees, 180)
    }

    // MARK: - Output ranges

    func testAzimuthAndElevationStayWithinValidRanges() {
        let noonish = localDate(year: 2026, month: 6, day: 21, hour: 13, minute: 0)
        let position = SolarPositionCalculator.position(at: noonish, coordinate: sanFrancisco)

        XCTAssertTrue((0..<360).contains(position.azimuthDegrees))
        XCTAssertTrue((-90...90).contains(position.elevationDegrees))
    }

    // MARK: - Polar day / night

    func testPolarDayHasNoSunriseOrSunset() throws {
        let svalbard = Coordinate(latitude: 78.22, longitude: 15.63)
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        let midsummer = localDate(year: 2026, month: 6, day: 21, hour: 0, minute: 0, timezone: oslo)

        let dayEvents = SolarPositionCalculator.events(on: midsummer, coordinate: svalbard, timezone: oslo)
        XCTAssertNil(dayEvents.sunrise)
        XCTAssertNil(dayEvents.sunset)

        // The midnight sun stays above the horizon even at local midnight.
        let position = SolarPositionCalculator.position(at: midsummer, coordinate: svalbard)
        XCTAssertGreaterThan(position.elevationDegrees, 0)
    }

    func testPolarNightHasNoSunriseOrSunset() throws {
        let svalbard = Coordinate(latitude: 78.22, longitude: 15.63)
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        let midwinter = localDate(year: 2026, month: 12, day: 21, hour: 12, minute: 0, timezone: oslo)

        let dayEvents = SolarPositionCalculator.events(on: midwinter, coordinate: svalbard, timezone: oslo)
        XCTAssertNil(dayEvents.sunrise)
        XCTAssertNil(dayEvents.sunset)

        // The sun never climbs above the horizon, even at local noon.
        let position = SolarPositionCalculator.position(at: midwinter, coordinate: svalbard)
        XCTAssertLessThan(position.elevationDegrees, 0)
    }

    // MARK: - Helpers

    private func declination(year: Int, month: Int, day: Int) -> Double {
        let date = utcDate(year: year, month: month, day: day, hour: 12)
        let century = SolarPositionCalculator.julianCentury(SolarPositionCalculator.julianDay(from: date))
        return SolarPositionCalculator.solarDeclination(century)
    }

    private func events(year: Int, month: Int, day: Int) -> SolarDayEvents {
        let date = localDate(year: year, month: month, day: day, hour: 12, minute: 0)
        return SolarPositionCalculator.events(on: date, coordinate: sanFrancisco, timezone: pacific)
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func localDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        timezone: TimeZone? = nil
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone ?? pacific
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
