import CoreLocation
import Foundation
import SunStatusCore

/// Fetches current weather from the Open-Meteo public API (no API key required) and
/// caches the result for `cacheLifetime` seconds. A stale cached value is returned on
/// network failure when it belongs to the same nearby coordinate so the UI degrades to
/// the last-known conditions rather than dropping to nil, and the first fetch begins as
/// soon as a coordinate is available.
actor WeatherService {
    private let cacheLifetime: TimeInterval
    private let coordinateCacheRadius: CLLocationDistance
    private var cached: (coordinate: Coordinate, snapshot: WeatherSnapshot, fetchedAt: Date)?
    private var inFlight: (coordinate: Coordinate, task: Task<WeatherSnapshot?, Never>)?

    init(cacheLifetime: TimeInterval = 30 * 60, coordinateCacheRadius: CLLocationDistance = 250) {
        self.cacheLifetime = cacheLifetime
        self.coordinateCacheRadius = coordinateCacheRadius
    }

    /// Returns the most recent weather snapshot for `coordinate`, fetching a fresh one
    /// when the cache is cold or expired. Returns `nil` only when no data has ever been
    /// fetched and the network request fails.
    func weather(for coordinate: Coordinate) async -> WeatherSnapshot? {
        if let cached,
           Date.now.timeIntervalSince(cached.fetchedAt) < cacheLifetime,
           isNearby(cached.coordinate, coordinate) {
            return cached.snapshot
        }

        // Coalesce concurrent callers onto a single in-flight request.
        if let inFlight, isNearby(inFlight.coordinate, coordinate) {
            return await inFlight.task.value
        }

        let task = Task<WeatherSnapshot?, Never> { [weak self] in
            guard let self else { return nil }
            do {
                let snapshot = try await Self.fetch(coordinate: coordinate)
                await self.store(snapshot, coordinate: coordinate)
                return snapshot
            } catch {
                // Return stale data rather than dropping all weather fields.
                return await self.cachedSnapshot(near: coordinate)
            }
        }

        inFlight = (coordinate, task)
        let result = await task.value
        if let inFlight, isNearby(inFlight.coordinate, coordinate) {
            self.inFlight = nil
        }
        return result
    }

    private func store(_ snapshot: WeatherSnapshot, coordinate: Coordinate) {
        cached = (coordinate, snapshot, .now)
    }

    private func cachedSnapshot(near coordinate: Coordinate) -> WeatherSnapshot? {
        guard let cached, isNearby(cached.coordinate, coordinate) else {
            return nil
        }

        return cached.snapshot
    }

    private func isNearby(_ lhs: Coordinate, _ rhs: Coordinate) -> Bool {
        Self.distance(from: lhs, to: rhs) <= coordinateCacheRadius
    }

    private static func distance(from lhs: Coordinate, to rhs: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
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
            URLQueryItem(name: "forecast_days", value: "2"),
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
