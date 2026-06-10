import Foundation
import SunStatusCore

/// Fetches current weather from the Open-Meteo public API (no API key required) and
/// caches the result for `cacheLifetime` seconds. A stale cached value is returned on
/// network failure so the UI degrades to the last-known conditions rather than dropping
/// to nil, and the first fetch begins as soon as a coordinate is available.
actor WeatherService {
    private let cacheLifetime: TimeInterval
    private var cached: (snapshot: WeatherSnapshot, fetchedAt: Date)?
    private var inFlight: Task<WeatherSnapshot?, Never>?

    init(cacheLifetime: TimeInterval = 30 * 60) {
        self.cacheLifetime = cacheLifetime
    }

    /// Returns the most recent weather snapshot for `coordinate`, fetching a fresh one
    /// when the cache is cold or expired. Returns `nil` only when no data has ever been
    /// fetched and the network request fails.
    func weather(for coordinate: Coordinate) async -> WeatherSnapshot? {
        if let cached, Date.now.timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached.snapshot
        }

        // Coalesce concurrent callers onto a single in-flight request.
        if let inFlight {
            return await inFlight.value
        }

        let task = Task<WeatherSnapshot?, Never> { [weak self] in
            guard let self else { return nil }
            do {
                let snapshot = try await Self.fetch(coordinate: coordinate)
                await self.store(snapshot)
                return snapshot
            } catch {
                // Return stale data rather than dropping all weather fields.
                return await self.cachedSnapshot()
            }
        }

        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func store(_ snapshot: WeatherSnapshot) {
        cached = (snapshot, .now)
    }

    private func cachedSnapshot() -> WeatherSnapshot? {
        cached?.snapshot
    }

    // MARK: - Network

    private static func fetch(coordinate: Coordinate) async throws -> WeatherSnapshot {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "cloud_cover,visibility,uv_index"),
            URLQueryItem(name: "hourly", value: "cloud_cover"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "GMT"),
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try WeatherSnapshot.decodeOpenMeteo(from: data)
    }
}
