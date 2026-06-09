import XCTest
@testable import SunStatusCore

final class SolarDaylightProviderWeatherTests: XCTestCase {
    private let coordinate = Coordinate(latitude: 37.7749, longitude: -122.4194)
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    // MARK: - Weather blending

    func testClearSkyFallbackWhenNoWeather() throws {
        let provider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: nil
        )
        let status = provider.status(at: solarNoon)

        // Cloud cover and visibility should be nil; UV should be the clear-sky estimate.
        XCTAssertNil(status.brightness.cloudCover)
        XCTAssertNil(status.brightness.visibilityMeters)
        let uv = try XCTUnwrap(status.brightness.uvIndex)
        XCTAssertGreaterThan(uv, 0)
    }

    func testWeatherFieldsPassThroughWhenProvided() {
        let weather = WeatherSnapshot(cloudCover: 0.35, uvIndex: 4, visibilityMeters: 15_000)
        let provider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: weather
        )
        let status = provider.status(at: solarNoon)

        XCTAssertEqual(status.brightness.cloudCover, 0.35, accuracy: 0.001)
        XCTAssertEqual(status.brightness.uvIndex, 4)
        XCTAssertEqual(status.brightness.visibilityMeters, 15_000, accuracy: 0.1)
    }

    func testOvercastReducesBrightnessScore() {
        let clearProvider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: WeatherSnapshot(cloudCover: 0, uvIndex: nil, visibilityMeters: nil)
        )
        let overcastProvider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: WeatherSnapshot(cloudCover: 1.0, uvIndex: nil, visibilityMeters: nil)
        )

        let clearScore = clearProvider.status(at: solarNoon).brightness.score
        let overcastScore = overcastProvider.status(at: solarNoon).brightness.score

        XCTAssertGreaterThan(clearScore, overcastScore)
        XCTAssertGreaterThan(overcastScore, 0)
    }

    func testLiveUVIndexPreferredOverClearSkyEstimate() {
        // Live UV=2 in heavy haze vs the clear-sky estimate at high sun angle (~10).
        let weather = WeatherSnapshot(cloudCover: 0.80, uvIndex: 2, visibilityMeters: nil)
        let provider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: weather
        )
        let status = provider.status(at: solarNoon)

        XCTAssertEqual(status.brightness.uvIndex, 2)
    }

    func testCloudyModifierAppearsWhenCloudCoverIsHigh() {
        let weather = WeatherSnapshot(cloudCover: 0.60, uvIndex: nil, visibilityMeters: nil)
        let provider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: weather
        )
        let status = provider.status(at: solarNoon)

        XCTAssertTrue(status.brightness.modifiers.contains(.lightClouds))
    }

    // MARK: - Helpers

    private var solarNoon: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar.date(from: DateComponents(
            timeZone: pacific,
            year: 2026, month: 6, day: 21, hour: 13, minute: 5
        ))!
    }
}
