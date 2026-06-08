import Foundation

/// The sun's instantaneous position in the local sky.
public struct SolarPosition: Equatable, Sendable {
    /// Angle above the horizon in degrees, corrected for atmospheric refraction.
    /// Negative values mean the sun is below the horizon.
    public let elevationDegrees: Double
    /// Compass bearing of the sun in degrees, measured clockwise from true north
    /// (0° = North, 90° = East, 180° = South, 270° = West).
    public let azimuthDegrees: Double
    /// Solar declination in degrees for the instant (useful for diagnostics/tests).
    public let declinationDegrees: Double

    public init(elevationDegrees: Double, azimuthDegrees: Double, declinationDegrees: Double) {
        self.elevationDegrees = elevationDegrees
        self.azimuthDegrees = azimuthDegrees
        self.declinationDegrees = declinationDegrees
    }
}

/// Sunrise, solar noon, and sunset for a single civil day at a location.
public struct SolarDayEvents: Equatable, Sendable {
    public let sunrise: Date?
    public let solarNoon: Date?
    public let sunset: Date?

    public init(sunrise: Date?, solarNoon: Date?, sunset: Date?) {
        self.sunrise = sunrise
        self.solarNoon = solarNoon
        self.sunset = sunset
    }
}

/// A real solar-position engine implementing the NOAA solar calculations, which are
/// derived from Jean Meeus' *Astronomical Algorithms*. Accuracy is on the order of
/// ±0.01° for elevation/azimuth and within a minute for sunrise/sunset for dates
/// between roughly 1800 and 2100 — far more than enough for a daylight tracker, and a
/// drop-in replacement for the previous sine-curve mock.
public enum SolarPositionCalculator {
    /// The geometric altitude of the sun's center, in degrees, at which sunrise/sunset
    /// is defined. -0.833° accounts for the sun's apparent radius plus mean atmospheric
    /// refraction at the horizon.
    private static let sunriseZenith = 90.833

    // MARK: - Instantaneous position

    /// Computes the refraction-corrected elevation and azimuth of the sun for an exact
    /// instant. The result depends only on the absolute moment and the observer's
    /// coordinate, so no time zone is required.
    public static func position(at date: Date, coordinate: Coordinate) -> SolarPosition {
        let jd = julianDay(from: date)
        let t = julianCentury(jd)
        let declination = solarDeclination(t)
        let eqTime = equationOfTime(t)

        let trueSolarTime = trueSolarTimeMinutes(at: date, longitude: coordinate.longitude, equationOfTime: eqTime)
        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 {
            hourAngle += 360
        }

        let latRad = radians(coordinate.latitude)
        let declRad = radians(declination)
        let haRad = radians(hourAngle)

        let cosZenith = sin(latRad) * sin(declRad) + cos(latRad) * cos(declRad) * cos(haRad)
        let zenith = degrees(acos(clamp(cosZenith, lower: -1, upper: 1)))
        let geometricElevation = 90 - zenith
        let elevation = geometricElevation + refractionCorrection(geometricElevation)

        let azimuth = solarAzimuth(
            latitudeRadians: latRad,
            declinationDegrees: declination,
            zenithDegrees: zenith,
            hourAngleDegrees: hourAngle
        )

        return SolarPosition(
            elevationDegrees: elevation,
            azimuthDegrees: azimuth,
            declinationDegrees: declination
        )
    }

    // MARK: - Daily events

    /// Computes sunrise, solar noon, and sunset for the civil day that contains `date`
    /// in the supplied `timezone`. Returns `nil` for sunrise/sunset during polar day or
    /// polar night, while still reporting solar noon.
    public static func events(on date: Date, coordinate: Coordinate, timezone: TimeZone) -> SolarDayEvents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        guard let localMidnight = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: date)) else {
            return SolarDayEvents(sunrise: nil, solarNoon: nil, sunset: nil)
        }

        // Evaluate the slowly-varying solar terms near local noon for best accuracy.
        let noonReference = localMidnight.addingTimeInterval(12 * 3_600)
        let t = julianCentury(julianDay(from: noonReference))
        let declination = solarDeclination(t)
        let eqTime = equationOfTime(t)
        let tzOffsetHours = Double(timezone.secondsFromGMT(for: noonReference)) / 3_600

        // Minutes after local midnight when the sun crosses the meridian (true solar time = 720).
        let solarNoonMinutes = 720 - eqTime - 4 * coordinate.longitude + 60 * tzOffsetHours
        let solarNoon = localMidnight.addingTimeInterval(solarNoonMinutes * 60)

        let latRad = radians(coordinate.latitude)
        let declRad = radians(declination)
        let cosHourAngle = cos(radians(sunriseZenith)) / (cos(latRad) * cos(declRad)) - tan(latRad) * tan(declRad)

        guard abs(cosHourAngle) <= 1 else {
            // Polar day or night: the sun never reaches the sunrise/sunset altitude.
            return SolarDayEvents(sunrise: nil, solarNoon: solarNoon, sunset: nil)
        }

        let hourAngle = degrees(acos(cosHourAngle))
        let sunrise = localMidnight.addingTimeInterval((solarNoonMinutes - 4 * hourAngle) * 60)
        let sunset = localMidnight.addingTimeInterval((solarNoonMinutes + 4 * hourAngle) * 60)

        return SolarDayEvents(sunrise: sunrise, solarNoon: solarNoon, sunset: sunset)
    }

    // MARK: - Core astronomical terms (NOAA / Meeus)

    /// Julian Day number for an instant, expressed in Universal Time.
    static func julianDay(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    /// Julian centuries since the J2000.0 epoch.
    static func julianCentury(_ julianDay: Double) -> Double {
        (julianDay - 2_451_545) / 36_525
    }

    /// Geometric mean longitude of the sun in degrees, normalized to [0, 360).
    private static func geometricMeanLongitude(_ t: Double) -> Double {
        normalizedDegrees(280.46646 + t * (36_000.76983 + t * 0.0003032))
    }

    /// Geometric mean anomaly of the sun in degrees.
    private static func geometricMeanAnomaly(_ t: Double) -> Double {
        357.52911 + t * (35_999.05029 - 0.0001537 * t)
    }

    /// Eccentricity of Earth's orbit (dimensionless).
    private static func earthOrbitEccentricity(_ t: Double) -> Double {
        0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    }

    /// The sun's equation of the center in degrees.
    private static func sunEquationOfCenter(_ t: Double) -> Double {
        let m = radians(geometricMeanAnomaly(t))
        return sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289
    }

    /// Apparent ecliptic longitude of the sun in degrees, corrected for nutation/aberration.
    private static func sunApparentLongitude(_ t: Double) -> Double {
        let trueLongitude = geometricMeanLongitude(t) + sunEquationOfCenter(t)
        let omega = 125.04 - 1_934.136 * t
        return trueLongitude - 0.00569 - 0.00478 * sin(radians(omega))
    }

    /// Obliquity of the ecliptic in degrees, corrected for nutation.
    private static func obliquityCorrection(_ t: Double) -> Double {
        let seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        let meanObliquity = 23 + (26 + seconds / 60) / 60
        let omega = 125.04 - 1_934.136 * t
        return meanObliquity + 0.00256 * cos(radians(omega))
    }

    /// Solar declination in degrees for a given Julian century.
    static func solarDeclination(_ t: Double) -> Double {
        let obliquity = radians(obliquityCorrection(t))
        let lambda = radians(sunApparentLongitude(t))
        return degrees(asin(sin(obliquity) * sin(lambda)))
    }

    /// The equation of time in minutes (apparent solar time minus mean solar time).
    static func equationOfTime(_ t: Double) -> Double {
        let epsilon = radians(obliquityCorrection(t))
        let l0 = radians(geometricMeanLongitude(t))
        let m = radians(geometricMeanAnomaly(t))
        let e = earthOrbitEccentricity(t)

        let y = pow(tan(epsilon / 2), 2)
        let term = y * sin(2 * l0)
            - 2 * e * sin(m)
            + 4 * e * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * e * e * sin(2 * m)

        return 4 * degrees(term)
    }

    // MARK: - Helpers

    /// True solar time in minutes [0, 1440) for an instant, derived from UTC time-of-day,
    /// the equation of time, and the observer's longitude.
    private static func trueSolarTimeMinutes(at date: Date, longitude: Double, equationOfTime: Double) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let utcMinutes = Double(components.hour ?? 0) * 60
            + Double(components.minute ?? 0)
            + Double(components.second ?? 0) / 60
            + Double(components.nanosecond ?? 0) / 60e9

        let raw = utcMinutes + equationOfTime + 4 * longitude
        let wrapped = raw.truncatingRemainder(dividingBy: 1_440)
        return wrapped >= 0 ? wrapped : wrapped + 1_440
    }

    /// Solar azimuth in degrees clockwise from true north, following the NOAA formulation.
    private static func solarAzimuth(
        latitudeRadians latRad: Double,
        declinationDegrees declination: Double,
        zenithDegrees zenith: Double,
        hourAngleDegrees hourAngle: Double
    ) -> Double {
        let zenithRad = radians(zenith)
        let denominator = cos(latRad) * sin(zenithRad)

        guard abs(denominator) > 0.000_001 else {
            // Sun directly overhead or at a pole: azimuth is undefined; pick a stable value.
            return latRad >= 0 ? 180 : 0
        }

        let cosAzimuth = (sin(latRad) * cos(zenithRad) - sin(radians(declination))) / denominator
        let azimuth = degrees(acos(clamp(cosAzimuth, lower: -1, upper: 1)))

        if hourAngle > 0 {
            return normalizedDegrees(azimuth + 180)
        } else {
            return normalizedDegrees(540 - azimuth)
        }
    }

    /// Atmospheric refraction correction in degrees, added to the geometric elevation.
    /// Uses the piecewise approximation from the NOAA solar calculator.
    private static func refractionCorrection(_ elevationDegrees: Double) -> Double {
        guard elevationDegrees <= 85 else {
            return 0
        }

        let elevationRad = radians(elevationDegrees)
        let tangent = tan(elevationRad)
        let arcSeconds: Double

        if elevationDegrees > 5 {
            arcSeconds = 58.1 / tangent
                - 0.07 / pow(tangent, 3)
                + 0.000086 / pow(tangent, 5)
        } else if elevationDegrees > -0.575 {
            arcSeconds = 1_735
                + elevationDegrees * (-518.2
                + elevationDegrees * (103.4
                + elevationDegrees * (-12.79
                + elevationDegrees * 0.711)))
        } else {
            arcSeconds = -20.772 / tangent
        }

        return arcSeconds / 3_600
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
