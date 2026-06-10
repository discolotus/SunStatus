import Foundation

public struct MockDaylightProvider: DaylightProviding {
    public var locationName: String
    public var coordinate: Coordinate
    public var timezone: TimeZone

    public init(
        locationName: String = "San Francisco",
        coordinate: Coordinate = Coordinate(latitude: 37.7749, longitude: -122.4194),
        timezone: TimeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
    ) {
        self.locationName = locationName
        self.coordinate = coordinate
        self.timezone = timezone
    }

    public func status(at date: Date = .now) -> DaylightStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let sunrise = calendar.date(bySettingHour: 6, minute: 11, second: 0, of: date)
        let solarNoon = calendar.date(bySettingHour: 13, minute: 4, second: 0, of: date)
        let sunset = calendar.date(bySettingHour: 20, minute: 37, second: 0, of: date)
        let progress = daylightProgress(now: date, sunrise: sunrise, sunset: sunset)
        let elevation = mockElevation(progress: progress)
        let azimuth = mockAzimuth(progress: progress)

        let solar = SolarSnapshot(
            date: date,
            location: coordinate,
            sunrise: sunrise,
            solarNoon: solarNoon,
            sunset: sunset,
            elevationDegrees: elevation,
            azimuthDegrees: azimuth,
            daylightProgress: progress
        )

        let brightness = BrightnessSnapshot(
            date: date,
            score: brightnessScore(progress: progress),
            classification: brightnessClassification(progress: progress),
            cloudCover: 0.18,
            uvIndex: progress.map { $0 > 0.72 ? 4 : 6 },
            visibilityMeters: 18_000,
            modifiers: modifiers(progress: progress)
        )

        return DaylightStatus(
            locationName: locationName,
            timezone: timezone,
            solar: solar,
            brightness: brightness,
            arcPoints: arcPoints(for: date, calendar: calendar),
        )
    }

    private func daylightProgress(now: Date, sunrise: Date?, sunset: Date?) -> Double? {
        guard let sunrise, let sunset else {
            return nil
        }

        guard now >= sunrise, now <= sunset else {
            return nil
        }

        let elapsed = now.timeIntervalSince(sunrise)
        let duration = sunset.timeIntervalSince(sunrise)
        guard duration > 0 else {
            return nil
        }

        return min(max(elapsed / duration, 0), 1)
    }

    private func mockElevation(progress: Double?) -> Double {
        guard let progress else {
            return -12
        }

        return sin(progress * .pi) * 68
    }

    private func mockAzimuth(progress: Double?) -> Double {
        guard let progress else {
            return 290
        }

        return 72 + (progress * 218)
    }

    private func brightnessScore(progress: Double?) -> Double {
        guard let progress else {
            return 0.08
        }

        let daylight = sin(progress * .pi)
        let lateDayWarmth = progress > 0.72 ? 0.86 : 1
        return min(max((0.18 + daylight * 0.78) * lateDayWarmth, 0), 1)
    }

    private func brightnessClassification(progress: Double?) -> BrightnessClassification {
        let score = brightnessScore(progress: progress)

        switch score {
        case 0..<0.18:
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

    private func modifiers(progress: Double?) -> [BrightnessModifier] {
        guard let progress else {
            return [.lowSun]
        }

        switch progress {
        case 0..<0.18:
            return [.lowSun, .goldenLight, .clearVisibility]
        case 0.18..<0.72:
            return [.highSun, .lightClouds, .clearVisibility]
        default:
            return [.goldenLight, .lightClouds, .clearVisibility]
        }
    }

    private func arcPoints(for date: Date, calendar: Calendar) -> [SunArcPoint] {
        guard
            let sunrise = calendar.date(bySettingHour: 6, minute: 11, second: 0, of: date),
            let sunset = calendar.date(bySettingHour: 20, minute: 37, second: 0, of: date)
        else {
            return []
        }

        let duration = sunset.timeIntervalSince(sunrise)

        return stride(from: 0, through: 12, by: 1).map { index in
            let progress = Double(index) / 12
            let pointDate = sunrise.addingTimeInterval(duration * progress)

            return SunArcPoint(
                date: pointDate,
                progress: progress,
                elevationDegrees: mockElevation(progress: progress),
                azimuthDegrees: mockAzimuth(progress: progress),
                brightnessScore: brightnessScore(progress: progress),
                cloudCover: mockCloudCover(progress: progress)
            )
        }
    }

    private func mockCloudCover(progress: Double) -> Double {
        switch progress {
        case 0..<0.25:
            return 0.12
        case 0.25..<0.55:
            return 0.68
        case 0.55..<0.78:
            return 0.35
        default:
            return 0.08
        }
    }
}
