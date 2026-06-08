import Foundation

public struct Coordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct SolarSnapshot: Equatable, Sendable {
    public let date: Date
    public let location: Coordinate
    public let sunrise: Date?
    public let solarNoon: Date?
    public let sunset: Date?
    public let elevationDegrees: Double
    public let azimuthDegrees: Double
    public let daylightProgress: Double?

    public init(
        date: Date,
        location: Coordinate,
        sunrise: Date?,
        solarNoon: Date?,
        sunset: Date?,
        elevationDegrees: Double,
        azimuthDegrees: Double,
        daylightProgress: Double?
    ) {
        self.date = date
        self.location = location
        self.sunrise = sunrise
        self.solarNoon = solarNoon
        self.sunset = sunset
        self.elevationDegrees = elevationDegrees
        self.azimuthDegrees = azimuthDegrees
        self.daylightProgress = daylightProgress
    }
}

public enum BrightnessClassification: String, CaseIterable, Equatable, Sendable {
    case dark
    case dim
    case muted
    case bright
    case vivid

    public var displayName: String {
        switch self {
        case .dark: "Dark"
        case .dim: "Dim"
        case .muted: "Muted"
        case .bright: "Bright"
        case .vivid: "Vivid"
        }
    }
}

public enum BrightnessModifier: String, CaseIterable, Equatable, Sendable {
    case highSun
    case lightClouds
    case clearVisibility
    case goldenLight
    case lowSun

    public var displayName: String {
        switch self {
        case .highSun: "High sun"
        case .lightClouds: "Light clouds"
        case .clearVisibility: "Clear visibility"
        case .goldenLight: "Golden light"
        case .lowSun: "Low sun"
        }
    }
}

public struct BrightnessSnapshot: Equatable, Sendable {
    public let date: Date
    public let score: Double
    public let classification: BrightnessClassification
    public let cloudCover: Double?
    public let uvIndex: Int?
    public let visibilityMeters: Double?
    public let modifiers: [BrightnessModifier]

    public init(
        date: Date,
        score: Double,
        classification: BrightnessClassification,
        cloudCover: Double?,
        uvIndex: Int?,
        visibilityMeters: Double?,
        modifiers: [BrightnessModifier]
    ) {
        self.date = date
        self.score = score
        self.classification = classification
        self.cloudCover = cloudCover
        self.uvIndex = uvIndex
        self.visibilityMeters = visibilityMeters
        self.modifiers = modifiers
    }
}

public struct SunArcPoint: Equatable, Sendable, Identifiable {
    public var id: Date { date }

    public let date: Date
    public let progress: Double
    public let elevationDegrees: Double
    public let azimuthDegrees: Double
    public let brightnessScore: Double?

    public init(
        date: Date,
        progress: Double,
        elevationDegrees: Double,
        azimuthDegrees: Double,
        brightnessScore: Double?
    ) {
        self.date = date
        self.progress = progress
        self.elevationDegrees = elevationDegrees
        self.azimuthDegrees = azimuthDegrees
        self.brightnessScore = brightnessScore
    }
}

public struct DaylightStatus: Equatable, Sendable {
    public let locationName: String
    public let timezone: TimeZone
    public let solar: SolarSnapshot
    public let brightness: BrightnessSnapshot
    public let arcPoints: [SunArcPoint]

    public init(
        locationName: String,
        timezone: TimeZone,
        solar: SolarSnapshot,
        brightness: BrightnessSnapshot,
        arcPoints: [SunArcPoint]
    ) {
        self.locationName = locationName
        self.timezone = timezone
        self.solar = solar
        self.brightness = brightness
        self.arcPoints = arcPoints
    }

    public var nextTransition: DaylightTransition? {
        let candidates = [
            solar.sunrise.map { DaylightTransition(kind: .sunrise, date: $0) },
            solar.solarNoon.map { DaylightTransition(kind: .solarNoon, date: $0) },
            solar.sunset.map { DaylightTransition(kind: .sunset, date: $0) }
        ].compactMap { $0 }

        return candidates
            .filter { $0.date > solar.date }
            .sorted { $0.date < $1.date }
            .first
    }
}

public struct DaylightTransition: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case sunrise
        case solarNoon
        case sunset

        public var displayName: String {
            switch self {
            case .sunrise: "sunrise"
            case .solarNoon: "solar noon"
            case .sunset: "sunset"
            }
        }
    }

    public let kind: Kind
    public let date: Date

    public init(kind: Kind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

public protocol DaylightProviding: Sendable {
    func status(at date: Date) -> DaylightStatus
}
