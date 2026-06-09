import Foundation

/// Current atmospheric conditions at a location, used to enrich brightness estimates.
/// All fields are optional — the app degrades gracefully when weather data is unavailable.
public struct WeatherSnapshot: Equatable, Sendable {
    /// Fraction of sky covered by cloud, in [0, 1]. 0 = clear, 1 = fully overcast.
    public let cloudCover: Double?
    /// UV index (whole number), or nil if unavailable or the sun is below the horizon.
    public let uvIndex: Int?
    /// Horizontal visibility in metres.
    public let visibilityMeters: Double?

    public init(cloudCover: Double?, uvIndex: Int?, visibilityMeters: Double?) {
        self.cloudCover = cloudCover
        self.uvIndex = uvIndex
        self.visibilityMeters = visibilityMeters
    }
}

// MARK: - Open-Meteo decoding

extension WeatherSnapshot {
    /// Decodes a `WeatherSnapshot` from a raw Open-Meteo `/v1/forecast` JSON response.
    /// Only the `current` object is read; all fields are optional so partial responses
    /// still produce a usable snapshot.
    public static func decodeOpenMeteo(from data: Data) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let current = response.current

        let cloudCover = current.cloud_cover.map { $0 / 100.0 }
        let uvIndex = current.uv_index.map { max(0, Int($0.rounded())) }

        return WeatherSnapshot(
            cloudCover: cloudCover,
            uvIndex: uvIndex,
            visibilityMeters: current.visibility
        )
    }

    private struct OpenMeteoResponse: Decodable {
        let current: CurrentWeather

        struct CurrentWeather: Decodable {
            let cloud_cover: Double?
            let uv_index: Double?
            let visibility: Double?
        }
    }
}
