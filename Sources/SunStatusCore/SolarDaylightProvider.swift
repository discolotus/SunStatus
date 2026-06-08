import Foundation

/// A `DaylightProviding` implementation backed by real astronomy.
///
/// This replaces the sine-curve `MockDaylightProvider` for production use: every
/// elevation, azimuth, sunrise, solar noon, and sunset value comes from
/// `SolarPositionCalculator`, so the 2D arc and 3D sun-path overlays are now
/// physically trustworthy. Brightness is still a clear-sky heuristic derived from the
/// real solar elevation, since weather data is a separate roadmap milestone.
public struct SolarDaylightProvider: DaylightProviding {
    public var locationName: String
    public var coordinate: Coordinate
    public var timezone: TimeZone

    /// Number of sampled points along the daily sun path used to build the 3D arc.
    private let arcSampleCount: Int

    public init(
        locationName: String = "San Francisco",
        coordinate: Coordinate = Coordinate(latitude: 37.7749, longitude: -122.4194),
        timezone: TimeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current,
        arcSampleCount: Int = 48
    ) {
        self.locationName = locationName
        self.coordinate = coordinate
        self.timezone = timezone
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

        let brightness = BrightnessSnapshot(
            date: date,
            score: brightnessScore(elevationDegrees: position.elevationDegrees),
            classification: brightnessClassification(elevationDegrees: position.elevationDegrees),
            cloudCover: nil,
            uvIndex: clearSkyUVIndex(elevationDegrees: position.elevationDegrees),
            visibilityMeters: nil,
            modifiers: modifiers(elevationDegrees: position.elevationDegrees)
        )

        return DaylightStatus(
            locationName: locationName,
            timezone: timezone,
            solar: solar,
            brightness: brightness,
            arcPoints: arcPoints(for: date, events: events)
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
    private func arcPoints(for date: Date, events: SolarDayEvents) -> [SunArcPoint] {
        let span = daylightSpan(for: date, events: events)
        let duration = span.end.timeIntervalSince(span.start)
        guard duration > 0 else {
            return []
        }

        return (0...arcSampleCount).map { index in
            let ratio = Double(index) / Double(arcSampleCount)
            let pointDate = span.start.addingTimeInterval(duration * ratio)
            let position = SolarPositionCalculator.position(at: pointDate, coordinate: coordinate)

            return SunArcPoint(
                date: pointDate,
                progress: ratio,
                elevationDegrees: position.elevationDegrees,
                azimuthDegrees: position.azimuthDegrees,
                brightnessScore: brightnessScore(elevationDegrees: position.elevationDegrees)
            )
        }
    }

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

    // MARK: - Brightness heuristics (clear-sky, elevation-driven)

    private func brightnessScore(elevationDegrees: Double) -> Double {
        if elevationDegrees <= -6 {
            return 0.05
        }

        if elevationDegrees <= 0 {
            // Civil twilight: ramp from night (0.05) to horizon (0.18).
            return 0.05 + (elevationDegrees + 6) / 6 * 0.13
        }

        let daylight = sin(elevationDegrees * .pi / 180)
        return min(max(0.18 + daylight * 0.78, 0), 1)
    }

    private func brightnessClassification(elevationDegrees: Double) -> BrightnessClassification {
        switch brightnessScore(elevationDegrees: elevationDegrees) {
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

    private func modifiers(elevationDegrees: Double) -> [BrightnessModifier] {
        if elevationDegrees <= 0 {
            return [.lowSun]
        }

        if elevationDegrees < 8 {
            return [.lowSun, .goldenLight]
        }

        if elevationDegrees < 45 {
            return [.highSun]
        }

        return [.highSun, .clearVisibility]
    }

    /// A clear-sky UV index estimate from solar elevation. This is genuinely derivable
    /// from the sun's altitude (it scales with the cosine of the zenith angle); it does
    /// not account for clouds, ozone, or altitude.
    private func clearSkyUVIndex(elevationDegrees: Double) -> Int? {
        guard elevationDegrees > 0 else {
            return nil
        }

        let uv = 12 * pow(sin(elevationDegrees * .pi / 180), 1.2)
        return max(0, Int(uv.rounded()))
    }
}
