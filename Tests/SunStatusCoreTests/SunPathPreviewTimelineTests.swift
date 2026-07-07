import XCTest
@testable import SunStatusCore

final class SunPathPreviewTimelineTests: XCTestCase {
    func testAfterSunsetTimelineStartsAtCurrentNightAndReachesNextSunrise() throws {
        let provider = MockDaylightProvider()
        let now = try XCTUnwrap(makeDate(day: 7, hour: 23, minute: 0))
        let status = provider.status(at: now)
        let timeline = SunPathPreviewTimeline(status: status)
        let sunrise = try XCTUnwrap(timeline.daylightStartDate)
        let sunriseProgress = try XCTUnwrap(timeline.daylightStartProgress)

        XCTAssertEqual(timeline.startDate.timeIntervalSince(now), 0, accuracy: 0.001)
        XCTAssertEqual(timeline.endDate.timeIntervalSince(now.addingTimeInterval(86_400)), 0, accuracy: 0.001)
        XCTAssertEqual(timeline.currentProgress, 0, accuracy: 0.000_001)
        XCTAssertEqual(timeline.date(at: timeline.currentProgress).timeIntervalSince(now), 0, accuracy: 0.001)
        XCTAssertNil(timeline.daylightProgress(for: now))
        XCTAssertGreaterThan(sunrise, now)
        XCTAssertGreaterThan(sunriseProgress, timeline.currentProgress)
        XCTAssertEqual(sunriseProgress, sunrise.timeIntervalSince(now) / 86_400, accuracy: 0.000_001)
        let sunriseDaylightProgress = try XCTUnwrap(timeline.daylightProgress(for: sunrise))
        XCTAssertEqual(sunriseDaylightProgress, 0, accuracy: 0.000_001)
    }

    func testDaytimeTimelineKeepsCurrentTimeAndDaylightProgressAligned() throws {
        let provider = MockDaylightProvider()
        let now = try XCTUnwrap(makeDate(day: 7, hour: 12, minute: 0))
        let status = provider.status(at: now)
        let timeline = SunPathPreviewTimeline(status: status)
        let daylightProgress = try XCTUnwrap(status.solar.daylightProgress)

        XCTAssertEqual(timeline.date(at: timeline.currentProgress).timeIntervalSince(now), 0, accuracy: 0.001)
        let timelineDaylightProgress = try XCTUnwrap(timeline.daylightProgress(for: now))
        XCTAssertEqual(timelineDaylightProgress, daylightProgress, accuracy: 0.000_001)
    }

    private func makeDate(day: Int, hour: Int, minute: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: day,
            hour: hour,
            minute: minute
        ))
    }
}
