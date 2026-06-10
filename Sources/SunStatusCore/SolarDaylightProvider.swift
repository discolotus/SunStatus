import Foundation

/// A `DaylightProviding` implementation backed by real astronomy and optional live weather.
///
/// Solar position data (elevation, azimuth, sunrise, sunset, solar noon) comes from
/// `SolarPositionCalculator`. When a `WeatherSnapshot` is supplied, its cloud cover,
/// UV index, and visibility values replace the clear-sky heuristics — making the
/// brightness readouts reflect actual atmospheric conditions.
public struct SolarDaylightProvider: DaylightProviding {
    public var locationName: String
    public var coordinate: Coordinate
    public var timezone: TimeZone

    /// Live weather to blend into the brightness snapshot. When nil, brightness falls
    /// back to a clear-sky estimate derived from solar elevation alone.
    public var weather: WeatherSnapshot?

    /// Number of sampled points along the daily sun path used to build the 3D arc.
    private let arcSampleCount: Int

    public init(
        locationName: String = "San Francisco",
        coordinate: Coordinate = Coordinate(latitude: 37.7749, longitude: -122.4194),
        timezone: TimeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current,
        weather: WeatherSnapshot? = nil,
        arcSampleCount: Int = 48
    ) {
        self.locationName = locationName
        self.coordinate = coordinate
        self.timezone = timezone
        self.weather = weather
        self.arcSampleCount = max(arcSampleCount, 2)
    }

    public func status(at date: Date = .now) -> DaylightStatus {
        let events = SolarPositionCalculator.events(on: date, coordinate: coordinate, timezone: timezone)
        let position = SolarPositionCalculator.position(at: date, coordinate: coordinate)
        let progress = daylightProgress(now: date, sunrise: events.sunrise, sunset: events.sunset)

        let solar = SolarSnapshot(
            date: date,
            location: coordinate,
            sunrise: events.sunrise,
            solarNoon: events.solarNoon,
            sunset: events.sunset,
            elevationDegrees: position.elevationDegrees,
            azimuthDegrees: position.azimuthDegrees,
            daylightProgress: progress
        )

        let cloudCover = weather?.cloudCover
        let uvIndex = weather?.uvIndex ?? clearSkyUVIndex(elevationDegrees: position.elevationDegrees)
        let score = brightnessScore(elevationDegrees: position.elevationDegrees, cloudCover: cloudCover)

        let brightness = BrightnessSnapshot(
            date: date,
            score: score,
            classification: brightnessClassification(score: score),
            cloudCover: cloudCover,
            uvIndex: uvIndex,
            visibilityMeters: weather?.visibilityMeters,
            modifiers: modifiers(elevationDegrees: position.elevationDegrees, cloudCover: cloudCover)
        )

        return DaylightStatus(
            locationName: locationName,
            timezone: timezone,
            solar: solar,
            brightness: brightness,
            arcPoints: arcPoints(for: arcDate(for: date, events: events))
        )
    }

    // MARK: - Daylight progress

    private func daylightProgress(now: Date, sunrise: Date?, sunset: Date?) -> Double? {
        guard let sunrise, let sunset, sunset > sunrise else {
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

    // MARK: - Sun-path samples

    /// Builds evenly spaced sun-path samples across the day. When the location has a
    /// normal sunrise/sunset, the arc spans daylight (progress 0 → 1 from sunrise to
    /// sunset). During polar day/night the arc spans the full civil day so the 3D
    /// overlay still has a continuous path to draw.
    private func arcDate(for date: Date, events: SolarDayEvents) -> Date {
        guard let sunset = events.sunset, date > sunset else {
            return date
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
    }

    private func arcPoints(for date: Date) -> [SunArcPoint] {
        let events = SolarPositionCalculator.events(on: date, coordinate: coordinate, timezone: timezone)
        let span = daylightSpan(for: date, events: events)
        let duration = span.end.timeIntervalSince(span.start)
        guard duration > 0 else {
            return []
        }

        return (0...arcSampleCount).map { index in
            let ratio = Double(index) / Double(arcSampleCount)
            let pointDate = span.start.addingTimeInterval(duration * ratio)
            let position = SolarPositionCalculator.position(at: pointDate, coordinate: coordinate)
            let pointCloudCover = weather?.cloudCover(at: pointDate)

            return SunArcPoint(
                date: pointDate,
                progress: ratio,
                elevationDegrees: position.elevationDegrees,
                azimuthDegrees: position.azimuthDegrees,
                brightnessScore: brightnessScore(elevationDegrees: position.elevationDegrees, cloudCover: pointCloudCover),
                cloudCover: pointCloudCover
            )
        }
    }

    private var cloudCover: Double? { weather?.cloudCover }

    private func daylightSpan(for date: Date, events: SolarDayEvents) -> (start: Date, end: Date) {
        if let sunrise = events.sunrise, let sunset = events.sunset, sunset > sunrise {
            return (sunrise, sunset)
        }

        // Polar day/night fallback: span the whole civil day.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let start = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: date)) ?? date
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    // MARK: - Brightness heuristics

    /// Base clear-sky brightness from solar elevation, attenuated by cloud cover when available.
    private func brightnessScore(elevationDegrees: Double, cloudCover: Double?) -> Double {
        let clearSky: Double

        if elevationDegrees <= -6 {
            clearSky = 0.05
        } else if elevationDegrees <= 0 {
            // Civil twilight: ramp from 0.05 to 0.18.
            clearSky = 0.05 + (elevationDegrees + 6) / 6 * 0.13
        } else {
            let daylight = sin(elevationDegrees * .pi / 180)
            clearSky = min(max(0.18 + daylight * 0.78, 0), 1)
        }

        guard let cloudCover else {
            return clearSky
        }

        // Overcast sky transmits roughly 20% of clear-sky light at full cover.
        // Linear blend between full-sun and overcast floor.
        let attenuated = clearSky * (1 - cloudCover * 0.80)
        return min(max(attenuated, 0.05), 1)
    }

    private func brightnessClassification(score: Double) -> BrightnessClassification {
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

    private func modifiers(elevationDegrees: Double, cloudCover: Double?) -> [BrightnessModifier] {
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
            if cloudCover > 0.05 {
                result.append(.lightClouds)
            } else {
                result.append(.clearVisibility)
            }
        } else if elevationDegrees >= 45 {
            result.append(.clearVisibility)
        }

        return result
    }

    /// A clear-sky UV estimate used when live weather doesn't supply a UV value.
    private func clearSkyUVIndex(elevationDegrees: Double) -> Int? {
        guard elevationDegrees > 0 else {
            return nil
        }

        let uv = 12 * pow(sin(elevationDegrees * .pi / 180), 1.2)
        return max(0, Int(uv.rounded()))
    }
}
