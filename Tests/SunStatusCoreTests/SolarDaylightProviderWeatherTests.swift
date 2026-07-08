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

    func testWeatherFieldsPassThroughWhenProvided() throws {
        let weather = WeatherSnapshot(cloudCover: 0.35, uvIndex: 4, visibilityMeters: 15_000)
        let provider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: weather
        )
        let status = provider.status(at: solarNoon)

        XCTAssertEqual(try XCTUnwrap(status.brightness.cloudCover), 0.35, accuracy: 0.001)
        XCTAssertEqual(status.brightness.uvIndex, 4)
        XCTAssertEqual(try XCTUnwrap(status.brightness.visibilityMeters), 15_000, accuracy: 0.1)
    }

    func testArcPointsUseForecastCloudCoverForTheirTime() throws {
        let morning = date(hour: 7)
        let midday = date(hour: 13)
        let evening = date(hour: 19)
        let weather = WeatherSnapshot(
            cloudCover: 0.2,
            uvIndex: nil,
            visibilityMeters: nil,
            cloudCoverForecast: [
                CloudCoverSample(date: morning, cloudCover: 0.05),
                CloudCoverSample(date: midday, cloudCover: 0.85),
                CloudCoverSample(date: evening, cloudCover: 0.15),
            ]
        )
        let provider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: weather
        )

        let status = provider.status(at: solarNoon)
        let cloudyPoint = try XCTUnwrap(status.arcPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(midday)) < abs(rhs.date.timeIntervalSince(midday))
        })
        let clearPoint = try XCTUnwrap(status.arcPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(morning)) < abs(rhs.date.timeIntervalSince(morning))
        })

        XCTAssertEqual(try XCTUnwrap(cloudyPoint.cloudCover), 0.85, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(clearPoint.cloudCover), 0.05, accuracy: 0.02)
    }

    func testStatusUsesForecastCloudCoverForQueriedTime() throws {
        // The fetch-time "current" cloud cover (0.2) is hours stale by solar noon;
        // the hourly forecast says solar noon is heavily overcast.
        let weather = WeatherSnapshot(
            cloudCover: 0.2,
            uvIndex: nil,
            visibilityMeters: nil,
            cloudCoverForecast: [
                CloudCoverSample(date: date(hour: 7), cloudCover: 0.05),
                CloudCoverSample(date: date(hour: 13), cloudCover: 0.85),
                CloudCoverSample(date: date(hour: 19), cloudCover: 0.15),
            ]
        )
        let provider = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: weather
        )

        let noonStatus = provider.status(at: date(hour: 13))
        XCTAssertEqual(try XCTUnwrap(noonStatus.brightness.cloudCover), 0.85, accuracy: 0.001)

        let morningStatus = provider.status(at: date(hour: 7))
        XCTAssertEqual(try XCTUnwrap(morningStatus.brightness.cloudCover), 0.05, accuracy: 0.001)

        // Overcast noon should score darker than the nearly clear morning would
        // if it shared noon's sun elevation - verify attenuation actually applied.
        let clearNoonStatus = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: WeatherSnapshot(cloudCover: 0.05, uvIndex: nil, visibilityMeters: nil)
        ).status(at: date(hour: 13))
        XCTAssertLessThan(noonStatus.brightness.score, clearNoonStatus.brightness.score)
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
        date(hour: 13, minute: 5)
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar.date(from: DateComponents(
            timeZone: pacific, year: 2026, month: 6, day: 21, hour: hour, minute: minute
        ))!
    }
}
