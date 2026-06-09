import XCTest
@testable import SunStatusCore

final class WeatherSnapshotTests: XCTestCase {
    // MARK: - Open-Meteo decoding

    func testDecodesFullResponse() throws {
        let json = """
        {
          "latitude": 37.775,
          "longitude": -122.4186,
          "current": {
            "time": "2026-06-09T13:00",
            "interval": 900,
            "cloud_cover": 25,
            "visibility": 24140.0,
            "uv_index": 5.8
          }
        }
        """.data(using: .utf8)!

        let snapshot = try WeatherSnapshot.decodeOpenMeteo(from: json)

        XCTAssertEqual(snapshot.cloudCover, 0.25, accuracy: 0.001)
        XCTAssertEqual(snapshot.uvIndex, 6)
        XCTAssertEqual(snapshot.visibilityMeters, 24_140, accuracy: 0.1)
    }

    func testUVIndexRoundsCorrectly() throws {
        let json = """
        {"current": {"cloud_cover": 0, "visibility": 10000, "uv_index": 3.4}}
        """.data(using: .utf8)!
        XCTAssertEqual(try WeatherSnapshot.decodeOpenMeteo(from: json).uvIndex, 3)

        let json2 = """
        {"current": {"cloud_cover": 0, "visibility": 10000, "uv_index": 3.5}}
        """.data(using: .utf8)!
        XCTAssertEqual(try WeatherSnapshot.decodeOpenMeteo(from: json2).uvIndex, 4)
    }

    func testCloudCoverConvertedFromPercentToFraction() throws {
        let json = """
        {"current": {"cloud_cover": 100, "visibility": 5000, "uv_index": 0}}
        """.data(using: .utf8)!
        let snapshot = try WeatherSnapshot.decodeOpenMeteo(from: json)
        XCTAssertEqual(snapshot.cloudCover, 1.0, accuracy: 0.001)

        let json2 = """
        {"current": {"cloud_cover": 0, "visibility": 5000, "uv_index": 8}}
        """.data(using: .utf8)!
        let snapshot2 = try WeatherSnapshot.decodeOpenMeteo(from: json2)
        XCTAssertEqual(snapshot2.cloudCover, 0.0, accuracy: 0.001)
    }

    func testNilFieldsOnMissingCurrentKeys() throws {
        // Open-Meteo may omit fields when data is unavailable.
        let json = """
        {"current": {}}
        """.data(using: .utf8)!

        let snapshot = try WeatherSnapshot.decodeOpenMeteo(from: json)

        XCTAssertNil(snapshot.cloudCover)
        XCTAssertNil(snapshot.uvIndex)
        XCTAssertNil(snapshot.visibilityMeters)
    }

    func testThrowsOnMalformedJSON() {
        let bad = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try WeatherSnapshot.decodeOpenMeteo(from: bad))
    }

    // MARK: - Brightness blending (via SolarDaylightProvider)

    func testFullOvercastDimsBrightness() {
        let coordinate = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let pacific = TimeZone(identifier: "America/Los_Angeles")!

        let clear = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: WeatherSnapshot(cloudCover: 0, uvIndex: nil, visibilityMeters: nil)
        )
        let overcast = SolarDaylightProvider(
            coordinate: coordinate,
            timezone: pacific,
            weather: WeatherSnapshot(cloudCover: 1.0, uvIndex: nil, visibilityMeters: nil)
        )
        let noon = solarNoon(timezone: pacific)

        XCTAssertGreaterThan(
            clear.status(at: noon).brightness.score,
            overcast.status(at: noon).brightness.score
        )
    }

    private func solarNoon(timezone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal.date(from: DateComponents(
            timeZone: timezone,
            year: 2026, month: 6, day: 21, hour: 13, minute: 5
        ))!
    }
}
