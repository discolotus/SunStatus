import Foundation

public struct SunPathPreviewTimeline: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let daylightStartDate: Date?
    public let daylightEndDate: Date?
    public let currentDate: Date

    public init(status: DaylightStatus) {
        let sortedArcPoints = status.arcPoints.sorted { $0.progress < $1.progress }
        let daylightStartDate = sortedArcPoints.first?.date ?? status.solar.sunrise
        let daylightEndDate = sortedArcPoints.last?.date ?? status.solar.sunset

        self.currentDate = status.solar.date
        self.daylightStartDate = daylightStartDate
        self.daylightEndDate = daylightEndDate

        if let daylightStartDate, daylightStartDate > status.solar.date {
            self.startDate = status.solar.date
            self.endDate = status.solar.date.addingTimeInterval(86_400)
        } else if let daylightEndDate {
            self.endDate = daylightEndDate
            self.startDate = daylightEndDate.addingTimeInterval(-86_400)
        } else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = status.timezone
            let civilStart = calendar.date(
                from: calendar.dateComponents([.year, .month, .day], from: status.solar.date)
            ) ?? status.solar.date
            self.startDate = civilStart
            self.endDate = civilStart.addingTimeInterval(86_400)
        }
    }

    public var currentProgress: Double {
        progress(for: currentDate)
    }

    public var daylightStartProgress: Double? {
        daylightStartDate.map { progress(for: $0) }
    }

    public var daylightEndProgress: Double? {
        daylightEndDate.map { progress(for: $0) }
    }

    public func date(at progress: Double) -> Date {
        let clampedProgress = min(max(progress, 0), 1)
        return startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) * clampedProgress)
    }

    public func progress(for date: Date) -> Double {
        let duration = endDate.timeIntervalSince(startDate)
        guard duration > 0 else {
            return 0
        }

        return min(max(date.timeIntervalSince(startDate) / duration, 0), 1)
    }

    public func daylightProgress(for date: Date) -> Double? {
        guard
            let daylightStartDate,
            let daylightEndDate,
            daylightEndDate > daylightStartDate,
            date >= daylightStartDate,
            date <= daylightEndDate
        else {
            return nil
        }

        return min(max(date.timeIntervalSince(daylightStartDate) / daylightEndDate.timeIntervalSince(daylightStartDate), 0), 1)
    }
}
