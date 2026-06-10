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
    /// Forecast cloud-cover samples, ordered by time, in [0, 1].
    public let cloudCoverForecast: [CloudCoverSample]

    public init(
        cloudCover: Double?,
        uvIndex: Int?,
        visibilityMeters: Double?,
        cloudCoverForecast: [CloudCoverSample] = []
    ) {
        self.cloudCover = cloudCover
        self.uvIndex = uvIndex
        self.visibilityMeters = visibilityMeters
        self.cloudCoverForecast = cloudCoverForecast.sorted { $0.date < $1.date }
    }

    public func cloudCover(at date: Date) -> Double? {
        guard !cloudCoverForecast.isEmpty else {
            return cloudCover
        }

        return cloudCoverForecast
            .min { lhs, rhs in
                abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
            }?
            .cloudCover
    }
}

public struct CloudCoverSample: Equatable, Sendable {
    public let date: Date
    public let cloudCover: Double

    public init(date: Date, cloudCover: Double) {
        self.date = date
        self.cloudCover = min(max(cloudCover, 0), 1)
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
            visibilityMeters: current.visibility,
            cloudCoverForecast: response.hourly?.cloudCoverSamples ?? []
        )
    }

    private struct OpenMeteoResponse: Decodable {
        let current: CurrentWeather
        let hourly: HourlyWeather?

        struct CurrentWeather: Decodable {
            let cloud_cover: Double?
            let uv_index: Double?
            let visibility: Double?
        }

        struct HourlyWeather: Decodable {
            let time: [String]
            let cloud_cover: [Double?]

            var cloudCoverSamples: [CloudCoverSample] {
                zip(time, cloud_cover).compactMap { timestamp, cloudCoverPercent in
                    guard let date = Self.dateFormatter.date(from: timestamp),
                          let cloudCoverPercent else {
                        return nil
                    }

                    return CloudCoverSample(date: date, cloudCover: cloudCoverPercent / 100)
                }
            }

            private static let dateFormatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                return formatter
            }()
        }
    }
}
