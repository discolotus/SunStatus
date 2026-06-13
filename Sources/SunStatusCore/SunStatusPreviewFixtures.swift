import Foundation

public enum SunStatusPreviewFixtures {
    public static var brightMorningCloudyAfternoonStatus: DaylightStatus {
        brightMorningCloudyAfternoonStatus(hour: 14, minute: 30)
    }

    public static func brightMorningCloudyAfternoonStatus(hour: Int, minute: Int) -> DaylightStatus {
        let timezone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let coordinate = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let date = fixtureDate(hour: hour, minute: minute, timezone: timezone)
        let events = SolarPositionCalculator.events(on: date, coordinate: coordinate, timezone: timezone)
        let position = SolarPositionCalculator.position(at: date, coordinate: coordinate)
        let daylightProgress = daylightProgress(at: date, sunrise: events.sunrise, sunset: events.sunset)
        let currentCloudCover = daylightProgress.map(cloudCover)
        let score = brightnessScore(elevationDegrees: position.elevationDegrees, cloudCover: currentCloudCover)

        return DaylightStatus(
            locationName: "Cloud Shift Test",
            timezone: timezone,
            solar: SolarSnapshot(
                date: date,
                location: coordinate,
                sunrise: events.sunrise,
                solarNoon: events.solarNoon,
                sunset: events.sunset,
                elevationDegrees: position.elevationDegrees,
                azimuthDegrees: position.azimuthDegrees,
                daylightProgress: daylightProgress
            ),
            brightness: BrightnessSnapshot(
                date: date,
                score: score,
                classification: brightnessClassification(score: score),
                cloudCover: currentCloudCover,
                uvIndex: clearSkyUVIndex(elevationDegrees: position.elevationDegrees),
                visibilityMeters: currentCloudCover.map { 24_000 - ($0 * 16_000) },
                modifiers: modifiers(elevationDegrees: position.elevationDegrees, cloudCover: currentCloudCover)
            ),
            arcPoints: arcPoints(events: events, coordinate: coordinate)
        )
    }

    private static func fixtureDate(hour: Int, minute: Int, timezone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        return calendar.date(from: DateComponents(
            timeZone: timezone,
            year: 2026,
            month: 6,
            day: 21,
            hour: hour,
            minute: minute
        )) ?? Date(timeIntervalSince1970: 1_781_999_000)
    }

    private static func arcPoints(events: SolarDayEvents, coordinate: Coordinate) -> [SunArcPoint] {
        guard let sunrise = events.sunrise, let sunset = events.sunset, sunset > sunrise else {
            return []
        }

        let duration = sunset.timeIntervalSince(sunrise)

        return stride(from: 0, through: 12, by: 1).map { index in
            let progress = Double(index) / 12
            let date = sunrise.addingTimeInterval(duration * progress)
            let position = SolarPositionCalculator.position(at: date, coordinate: coordinate)
            let cloudCover = cloudCover(for: progress)

            return SunArcPoint(
                date: date,
                progress: progress,
                elevationDegrees: position.elevationDegrees,
                azimuthDegrees: position.azimuthDegrees,
                brightnessScore: brightnessScore(elevationDegrees: position.elevationDegrees, cloudCover: cloudCover),
                cloudCover: cloudCover
            )
        }
    }

    private static func daylightProgress(at date: Date, sunrise: Date?, sunset: Date?) -> Double? {
        guard let sunrise, let sunset, sunset > sunrise, date >= sunrise, date <= sunset else {
            return nil
        }

        return min(max(date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise), 0), 1)
    }

    private static func cloudCover(for progress: Double) -> Double {
        switch progress {
        case ..<0.42:
            return 0.03
        case 0.42..<0.58:
            let ratio = (progress - 0.42) / 0.16
            return 0.03 + (0.94 * ratio)
        default:
            return 0.97
        }
    }

    private static func brightnessScore(elevationDegrees: Double, cloudCover: Double?) -> Double {
        let clearSky: Double

        if elevationDegrees <= -6 {
            clearSky = 0.05
        } else if elevationDegrees <= 0 {
            clearSky = 0.05 + (elevationDegrees + 6) / 6 * 0.13
        } else {
            let daylight = sin(elevationDegrees * .pi / 180)
            clearSky = min(max(0.18 + daylight * 0.78, 0), 1)
        }

        guard let cloudCover else {
            return clearSky
        }

        return min(max(clearSky * (1 - cloudCover * 0.80), 0.05), 1)
    }

    private static func brightnessClassification(score: Double) -> BrightnessClassification {
        switch score {
        case ..<0.18:
            return .dark
        case 0.18..<0.38:
            return .dim
        case 0.38..<0.62:
            return .muted
        case 0.62..<0.86:
            return .bright
        default:
            return .vivid
        }
    }

    private static func modifiers(elevationDegrees: Double, cloudCover: Double?) -> [BrightnessModifier] {
        var result: [BrightnessModifier] = []

        if elevationDegrees <= 0 {
            result.append(.lowSun)
        } else if elevationDegrees < 8 {
            result.append(.lowSun)
            result.append(.goldenLight)
        } else {
            result.append(.highSun)
        }

        if let cloudCover {
            result.append(cloudCover > 0.05 ? .lightClouds : .clearVisibility)
        } else if elevationDegrees >= 45 {
            result.append(.clearVisibility)
        }

        return result
    }

    private static func clearSkyUVIndex(elevationDegrees: Double) -> Int? {
        guard elevationDegrees > 0 else {
            return nil
        }

        let uv = 12 * pow(sin(elevationDegrees * .pi / 180), 1.2)
        return max(0, Int(uv.rounded()))
    }
}
