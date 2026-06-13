import XCTest
@testable import SunStatusCore

final class SunStatusPreviewFixturesTests: XCTestCase {
    func testBrightMorningCloudyAfternoonFixtureTransitionsFromClearToOvercast() throws {
        let status = SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus
        let morning = try XCTUnwrap(status.arcPoints.first { $0.progress > 0.20 && $0.progress < 0.35 })
        let afternoon = try XCTUnwrap(status.arcPoints.first { $0.progress > 0.65 && $0.progress < 0.85 })

        XCTAssertEqual(status.locationName, "Cloud Shift Test")
        XCTAssertLessThan(morning.cloudCover ?? 1, 0.10)
        XCTAssertGreaterThan(afternoon.cloudCover ?? 0, 0.90)
        XCTAssertGreaterThan(morning.brightnessScore ?? 0, afternoon.brightnessScore ?? 1)
        XCTAssertGreaterThan(status.brightness.cloudCover ?? 0, 0.90)
    }
}
