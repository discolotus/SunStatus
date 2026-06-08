import Foundation

public struct SolarDaylightProvider: DaylightProviding {
    public var locationName: String
    public var coordinate: Coordinate
    public var timezone: TimeZone

    public init(
        locationName: String,
        coordinate: Coordinate,
        timezone: TimeZone
    ) {
        self.locationName = locationName
        self.coordinate = coordinate
        self.timezone = timezone
    }

    public func status(at date: Date = .now) -> DaylightStatus {
        let position = SolarCalculator.position(
            at: date,
            coordinate: coordinate,
            timezone: timezone
        )
        let events = SolarCalculator.daylightEvents(
            on: date,
            coordinate: coordinate,
            timezone: timezone
        )
        let progress = daylightProgress(at: date, events: events)

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

        let score = brightnessScore(elevationDegrees: position.elevationDegrees)
        let brightness = BrightnessSnapshot(
            date: date,
            score: score,
            classification: brightnessClassification(score: score),
            cloudCover: nil,
            uvIndex: nil,
            visibilityMeters: nil,
            modifiers: brightnessModifiers(elevationDegrees: position.elevationDegrees)
        )

        return DaylightStatus(
            locationName: locationName,
            timezone: timezone,
            solar: solar,
            brightness: brightness,
            arcPoints: arcPoints(for: date, events: events)
        )
    }

    private func daylightProgress(at date: Date, events: SolarDaylightEvents) -> Double? {
        switch events.kind {
        case .regular:
            guard let sunrise = events.sunrise, let sunset = events.sunset, date >= sunrise, date <= sunset else {
                return nil
            }

            let duration = sunset.timeIntervalSince(sunrise)
            guard duration > 0 else {
                return nil
            }

            return clamped(date.timeIntervalSince(sunrise) / duration, lower: 0, upper: 1)
        case .allDaylight:
            return SolarCalculator.localDayProgress(at: date, timezone: timezone)
        case .allNight:
            return nil
        }
    }

    private func arcPoints(for date: Date, events: SolarDaylightEvents) -> [SunArcPoint] {
        let sampleCount = 12

        if let sunrise = events.sunrise, let sunset = events.sunset, sunset > sunrise {
            let duration = sunset.timeIntervalSince(sunrise)
            return (0...sampleCount).map { index in
                let progress = Double(index) / Double(sampleCount)
                let sampleDate = sunrise.addingTimeInterval(duration * progress)
                return arcPoint(at: sampleDate, progress: progress)
            }
        }

        return (0...sampleCount).compactMap { index in
            let progress = Double(index) / Double(sampleCount)
            guard let sampleDate = SolarCalculator.localDate(
                forMinutesAfterMidnight: progress * 1_440,
                on: date,
                timezone: timezone
            ) else {
                return nil
            }

            return arcPoint(at: sampleDate, progress: progress)
        }
    }

    private func arcPoint(at date: Date, progress: Double) -> SunArcPoint {
        let position = SolarCalculator.position(
            at: date,
            coordinate: coordinate,
            timezone: timezone
        )

        return SunArcPoint(
            date: date,
            progress: progress,
            elevationDegrees: position.elevationDegrees,
            azimuthDegrees: position.azimuthDegrees,
            brightnessScore: brightnessScore(elevationDegrees: position.elevationDegrees)
        )
    }

    private func brightnessScore(elevationDegrees: Double) -> Double {
        if elevationDegrees <= -6 {
            return 0.04
        }

        if elevationDegrees < 0 {
            return clamped(0.04 + ((elevationDegrees + 6) / 6) * 0.12, lower: 0.04, upper: 0.16)
        }

        let daylight = sin(SolarCalculator.degreesToRadians(clamped(elevationDegrees, lower: 0, upper: 90)))
        return clamped(0.16 + daylight * 0.84, lower: 0, upper: 1)
    }

    private func brightnessClassification(score: Double) -> BrightnessClassification {
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

    private func brightnessModifiers(elevationDegrees: Double) -> [BrightnessModifier] {
        switch elevationDegrees {
        case ..<0:
            return [.lowSun]
        case 0..<10:
            return [.lowSun, .goldenLight]
        case 10..<25:
            return [.goldenLight]
        default:
            return [.highSun]
        }
    }

    private func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

private struct SolarPosition {
    let elevationDegrees: Double
    let azimuthDegrees: Double
}

private struct SolarDaylightEvents {
    let sunrise: Date?
    let solarNoon: Date
    let sunset: Date?
    let kind: SolarDaylightKind
}

private enum SolarDaylightKind {
    case regular
    case allDaylight
    case allNight
}

private enum SolarCalculator {
    static func position(at date: Date, coordinate: Coordinate, timezone: TimeZone) -> SolarPosition {
        let latitude = normalizedLatitude(coordinate.latitude)
        let longitude = coordinate.longitude
        let calculations = solarCalculations(for: date)
        let localMinutes = localClockMinutes(at: date, timezone: timezone)
        let timezoneOffsetMinutes = Double(timezone.secondsFromGMT(for: date)) / 60
        let trueSolarTime = normalizedMinutes(
            localMinutes + calculations.equationOfTimeMinutes + (4 * longitude) - timezoneOffsetMinutes
        )
        var hourAngleDegrees = (trueSolarTime / 4) - 180
        if hourAngleDegrees < -180 {
            hourAngleDegrees += 360
        }

        let latitudeRadians = degreesToRadians(latitude)
        let declinationRadians = degreesToRadians(calculations.solarDeclinationDegrees)
        let hourAngleRadians = degreesToRadians(hourAngleDegrees)
        let cosineZenith = clamped(
            (sin(latitudeRadians) * sin(declinationRadians)) +
            (cos(latitudeRadians) * cos(declinationRadians) * cos(hourAngleRadians)),
            lower: -1,
            upper: 1
        )
        let zenithDegrees = radiansToDegrees(acos(cosineZenith))
        let geometricElevationDegrees = 90 - zenithDegrees
        let elevationDegrees = geometricElevationDegrees + atmosphericRefractionCorrection(
            elevationDegrees: geometricElevationDegrees
        )

        let azimuthDegrees = solarAzimuthDegrees(
            latitudeRadians: latitudeRadians,
            declinationRadians: declinationRadians,
            hourAngleDegrees: hourAngleDegrees,
            zenithDegrees: zenithDegrees
        )

        return SolarPosition(
            elevationDegrees: elevationDegrees,
            azimuthDegrees: azimuthDegrees
        )
    }

    static func daylightEvents(on date: Date, coordinate: Coordinate, timezone: TimeZone) -> SolarDaylightEvents {
        let latitude = normalizedLatitude(coordinate.latitude)
        let longitude = coordinate.longitude
        guard let localNoon = localDate(forMinutesAfterMidnight: 720, on: date, timezone: timezone) else {
            let fallbackNoon = date.addingTimeInterval(12 * 3_600)
            return SolarDaylightEvents(sunrise: nil, solarNoon: fallbackNoon, sunset: nil, kind: .allNight)
        }

        let calculations = solarCalculations(for: localNoon)
        let timezoneOffsetMinutes = Double(timezone.secondsFromGMT(for: localNoon)) / 60
        let solarNoonMinutes = 720 - (4 * longitude) - calculations.equationOfTimeMinutes + timezoneOffsetMinutes
        let solarNoon = localDate(
            forMinutesAfterMidnight: solarNoonMinutes,
            on: date,
            timezone: timezone
        ) ?? localNoon

        let latitudeRadians = degreesToRadians(latitude)
        let declinationRadians = degreesToRadians(calculations.solarDeclinationDegrees)
        let zenithRadians = degreesToRadians(90.833)
        let cosineHourAngle = (cos(zenithRadians) / (cos(latitudeRadians) * cos(declinationRadians))) -
            (tan(latitudeRadians) * tan(declinationRadians))

        if cosineHourAngle > 1 {
            return SolarDaylightEvents(sunrise: nil, solarNoon: solarNoon, sunset: nil, kind: .allNight)
        }

        if cosineHourAngle < -1 {
            return SolarDaylightEvents(sunrise: nil, solarNoon: solarNoon, sunset: nil, kind: .allDaylight)
        }

        let hourAngleDegrees = radiansToDegrees(acos(cosineHourAngle))
        let sunrise = localDate(
            forMinutesAfterMidnight: solarNoonMinutes - (hourAngleDegrees * 4),
            on: date,
            timezone: timezone
        )
        let sunset = localDate(
            forMinutesAfterMidnight: solarNoonMinutes + (hourAngleDegrees * 4),
            on: date,
            timezone: timezone
        )

        return SolarDaylightEvents(sunrise: sunrise, solarNoon: solarNoon, sunset: sunset, kind: .regular)
    }

    static func localDayProgress(at date: Date, timezone: TimeZone) -> Double {
        clamped(localClockMinutes(at: date, timezone: timezone) / 1_440, lower: 0, upper: 1)
    }

    static func localDate(forMinutesAfterMidnight minutes: Double, on date: Date, timezone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let secondsPerDay = 86_400
        let totalSeconds = Int((minutes * 60).rounded())
        let dayOffset = Int(floor(Double(totalSeconds) / Double(secondsPerDay)))
        let secondsInDay = totalSeconds - (dayOffset * secondsPerDay)

        let startOfDay = calendar.startOfDay(for: date)
        guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else {
            return nil
        }

        let hour = secondsInDay / 3_600
        let minute = (secondsInDay % 3_600) / 60
        let second = secondsInDay % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: targetDay)
    }

    static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func solarCalculations(for date: Date) -> SolarCalculations {
        let century = julianCentury(for: date)
        let geometricMeanLongitude = normalizedDegrees(280.46646 + century * (36_000.76983 + century * 0.0003032))
        let geometricMeanAnomaly = 357.52911 + century * (35_999.05029 - 0.0001537 * century)
        let eccentricity = 0.016708634 - century * (0.000042037 + 0.0000001267 * century)
        let equationOfCenter = sin(degreesToRadians(geometricMeanAnomaly)) *
            (1.914602 - century * (0.004817 + 0.000014 * century)) +
            sin(degreesToRadians(2 * geometricMeanAnomaly)) * (0.019993 - 0.000101 * century) +
            sin(degreesToRadians(3 * geometricMeanAnomaly)) * 0.000289
        let sunTrueLongitude = geometricMeanLongitude + equationOfCenter
        let omega = 125.04 - (1934.136 * century)
        let sunApparentLongitude = sunTrueLongitude - 0.00569 - (0.00478 * sin(degreesToRadians(omega)))
        let meanObliquity = 23 + ((26 + ((21.448 - century * (46.815 + century * (0.00059 - century * 0.001813))) / 60)) / 60)
        let obliquityCorrection = meanObliquity + (0.00256 * cos(degreesToRadians(omega)))
        let solarDeclination = radiansToDegrees(
            asin(sin(degreesToRadians(obliquityCorrection)) * sin(degreesToRadians(sunApparentLongitude)))
        )
        let y = pow(tan(degreesToRadians(obliquityCorrection) / 2), 2)
        let equationOfTime = 4 * radiansToDegrees(
            y * sin(2 * degreesToRadians(geometricMeanLongitude)) -
            2 * eccentricity * sin(degreesToRadians(geometricMeanAnomaly)) +
            4 * eccentricity * y * sin(degreesToRadians(geometricMeanAnomaly)) * cos(2 * degreesToRadians(geometricMeanLongitude)) -
            0.5 * y * y * sin(4 * degreesToRadians(geometricMeanLongitude)) -
            1.25 * eccentricity * eccentricity * sin(2 * degreesToRadians(geometricMeanAnomaly))
        )

        return SolarCalculations(
            equationOfTimeMinutes: equationOfTime,
            solarDeclinationDegrees: solarDeclination
        )
    }

    private static func solarAzimuthDegrees(
        latitudeRadians: Double,
        declinationRadians: Double,
        hourAngleDegrees: Double,
        zenithDegrees: Double
    ) -> Double {
        let zenithRadians = degreesToRadians(zenithDegrees)
        let denominator = cos(latitudeRadians) * sin(zenithRadians)
        guard abs(denominator) > 0.001 else {
            return latitudeRadians > 0 ? 180 : 0
        }

        let argument = clamped(
            ((sin(latitudeRadians) * cos(zenithRadians)) - sin(declinationRadians)) / denominator,
            lower: -1,
            upper: 1
        )
        let azimuth = radiansToDegrees(acos(argument))

        if hourAngleDegrees > 0 {
            return normalizedDegrees(azimuth + 180)
        }

        return normalizedDegrees(540 - azimuth)
    }

    private static func atmosphericRefractionCorrection(elevationDegrees: Double) -> Double {
        if elevationDegrees > 85 {
            return 0
        }

        let tangent = tan(degreesToRadians(elevationDegrees))
        if elevationDegrees > 5 {
            return (58.1 / tangent - 0.07 / pow(tangent, 3) + 0.000086 / pow(tangent, 5)) / 3_600
        }

        if elevationDegrees > -0.575 {
            return (
                1_735 -
                518.2 * elevationDegrees +
                103.4 * pow(elevationDegrees, 2) -
                12.79 * pow(elevationDegrees, 3) +
                0.711 * pow(elevationDegrees, 4)
            ) / 3_600
        }

        return (-20.774 / tangent) / 3_600
    }

    private static func julianCentury(for date: Date) -> Double {
        (julianDay(for: date) - 2_451_545) / 36_525
    }

    private static func julianDay(for date: Date) -> Double {
        (date.timeIntervalSince1970 / 86_400) + 2_440_587.5
    }

    private static func localClockMinutes(at date: Date, timezone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let seconds = Double(components.second ?? 0)
        let nanoseconds = Double(components.nanosecond ?? 0) / 1_000_000_000

        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0)) + ((seconds + nanoseconds) / 60)
    }

    private static func normalizedLatitude(_ latitude: Double) -> Double {
        clamped(latitude, lower: -89.8, upper: 89.8)
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    private static func normalizedMinutes(_ minutes: Double) -> Double {
        let value = minutes.truncatingRemainder(dividingBy: 1_440)
        return value >= 0 ? value : value + 1_440
    }

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

private struct SolarCalculations {
    let equationOfTimeMinutes: Double
    let solarDeclinationDegrees: Double
}
