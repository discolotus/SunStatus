import Foundation

public struct SunVector3: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var length: Double {
        sqrt((x * x) + (y * y) + (z * z))
    }

    public var normalized: SunVector3 {
        let vectorLength = length
        guard vectorLength > 0 else {
            return SunVector3(x: 0, y: 0, z: 0)
        }

        return SunVector3(x: x / vectorLength, y: y / vectorLength, z: z / vectorLength)
    }
}

public struct SunPathSample3D: Equatable, Sendable, Identifiable {
    public var id: Date { date }

    public let date: Date
    public let progress: Double
    public let elevationDegrees: Double
    public let azimuthDegrees: Double
    public let direction: SunVector3
    public let shadowDirection: SunVector3?
    public let shadowBearingDegrees: Double?

    public init(date: Date, progress: Double, elevationDegrees: Double, azimuthDegrees: Double) {
        self.date = date
        self.progress = progress
        self.elevationDegrees = elevationDegrees
        self.azimuthDegrees = azimuthDegrees
        self.direction = SunPathGeometry.direction(azimuthDegrees: azimuthDegrees, elevationDegrees: elevationDegrees)
        self.shadowDirection = SunPathGeometry.shadowDirection(azimuthDegrees: azimuthDegrees, elevationDegrees: elevationDegrees)
        self.shadowBearingDegrees = SunPathGeometry.shadowBearingDegrees(azimuthDegrees: azimuthDegrees, elevationDegrees: elevationDegrees)
    }
}

public enum SunPathGeometry {
    public static func direction(azimuthDegrees: Double, elevationDegrees: Double) -> SunVector3 {
        let azimuth = degreesToRadians(normalizedDegrees(azimuthDegrees))
        let elevation = degreesToRadians(elevationDegrees)
        let horizontal = cos(elevation)

        return SunVector3(
            x: sin(azimuth) * horizontal,
            y: sin(elevation),
            z: cos(azimuth) * horizontal
        ).normalized
    }

    public static func shadowDirection(azimuthDegrees: Double, elevationDegrees: Double) -> SunVector3? {
        guard elevationDegrees > 0 else {
            return nil
        }

        let sunDirection = direction(azimuthDegrees: azimuthDegrees, elevationDegrees: elevationDegrees)
        let horizontalShadow = SunVector3(x: -sunDirection.x, y: 0, z: -sunDirection.z)
        guard horizontalShadow.length > 0.000_001 else {
            return nil
        }

        return horizontalShadow.normalized
    }

    public static func shadowBearingDegrees(azimuthDegrees: Double, elevationDegrees: Double) -> Double? {
        guard shadowDirection(azimuthDegrees: azimuthDegrees, elevationDegrees: elevationDegrees) != nil else {
            return nil
        }

        return normalizedDegrees(azimuthDegrees + 180)
    }

    public static func samples(from arcPoints: [SunArcPoint]) -> [SunPathSample3D] {
        arcPoints
            .sorted { $0.progress < $1.progress }
            .map {
                SunPathSample3D(
                    date: $0.date,
                    progress: $0.progress,
                    elevationDegrees: $0.elevationDegrees,
                    azimuthDegrees: $0.azimuthDegrees
                )
            }
    }

    public static func sample(
        at progress: Double,
        arcPoints: [SunArcPoint],
        fallback solar: SolarSnapshot
    ) -> SunPathSample3D {
        let clampedProgress = min(max(progress, 0), 1)
        let sortedPoints = arcPoints.sorted { $0.progress < $1.progress }

        guard let firstPoint = sortedPoints.first else {
            return SunPathSample3D(
                date: solar.date,
                progress: solar.daylightProgress ?? clampedProgress,
                elevationDegrees: solar.elevationDegrees,
                azimuthDegrees: solar.azimuthDegrees
            )
        }

        guard clampedProgress > firstPoint.progress else {
            return SunPathSample3D(
                date: firstPoint.date,
                progress: firstPoint.progress,
                elevationDegrees: firstPoint.elevationDegrees,
                azimuthDegrees: firstPoint.azimuthDegrees
            )
        }

        guard let lastPoint = sortedPoints.last, clampedProgress < lastPoint.progress else {
            let point = sortedPoints.last ?? firstPoint
            return SunPathSample3D(
                date: point.date,
                progress: point.progress,
                elevationDegrees: point.elevationDegrees,
                azimuthDegrees: point.azimuthDegrees
            )
        }

        for (lower, upper) in zip(sortedPoints, sortedPoints.dropFirst()) {
            guard clampedProgress >= lower.progress, clampedProgress <= upper.progress else {
                continue
            }

            let span = upper.progress - lower.progress
            let ratio = span > 0 ? (clampedProgress - lower.progress) / span : 0
            let date = lower.date.addingTimeInterval(upper.date.timeIntervalSince(lower.date) * ratio)

            return SunPathSample3D(
                date: date,
                progress: clampedProgress,
                elevationDegrees: interpolate(lower.elevationDegrees, upper.elevationDegrees, ratio: ratio),
                azimuthDegrees: interpolateAngle(lower.azimuthDegrees, upper.azimuthDegrees, ratio: ratio)
            )
        }

        return SunPathSample3D(
            date: firstPoint.date,
            progress: firstPoint.progress,
            elevationDegrees: firstPoint.elevationDegrees,
            azimuthDegrees: firstPoint.azimuthDegrees
        )
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private static func interpolate(_ lower: Double, _ upper: Double, ratio: Double) -> Double {
        lower + ((upper - lower) * ratio)
    }

    private static func interpolateAngle(_ lower: Double, _ upper: Double, ratio: Double) -> Double {
        let lower = normalizedDegrees(lower)
        let upper = normalizedDegrees(upper)
        let delta = ((upper - lower + 540).truncatingRemainder(dividingBy: 360)) - 180
        return normalizedDegrees(lower + (delta * ratio))
    }
}
