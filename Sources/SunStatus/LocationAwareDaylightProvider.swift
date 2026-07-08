import CoreLocation
import Foundation
#if canImport(SunStatusCore)
import SunStatusCore
#endif

protocol RefreshingDaylightProviding: AnyObject, DaylightProviding {
    var onStatusChanged: (@Sendable () -> Void)? { get set }
    func start()
}

final class LocationAwareDaylightProvider: NSObject, RefreshingDaylightProviding, CLLocationManagerDelegate, @unchecked Sendable {
    var onStatusChanged: (@Sendable () -> Void)?

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var locationState = LocationState.pending
    private var cachedWeather: WeatherSnapshot?
    private var refreshTimer: Timer?
    private var retryTask: Task<Void, Never>?

    private let weatherService = WeatherService()

    /// Delay before retrying `requestLocation()` after a transient failure
    /// (e.g. `kCLErrorLocationUnknown`), which is common right after launch.
    private let failureRetryDelay: TimeInterval = 30

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    deinit {
        refreshTimer?.invalidate()
        retryTask?.cancel()
    }

    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateAuthorization()
            self.scheduleRefreshTimer()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.userDefaultsDidChange),
                name: UserDefaults.didChangeNotification,
                object: nil
            )
        }
    }

    func status(at date: Date = .now) -> DaylightStatus {
        let state = currentLocationState()
        let weather = currentWeather()
        let provider = SolarDaylightProvider(
            locationName: state.locationName,
            coordinate: state.coordinate,
            timezone: state.timezone,
            weather: weather
        )

        return provider.status(at: date)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else {
            return
        }

        let coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        setLocationState(.current(coordinate))
        refreshWeather(for: coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        scheduleFailureRetry()

        guard currentLocationState().isPending else {
            return
        }

        let fallback = LocationState.fallback("Location unavailable")
        setLocationState(fallback)
        refreshWeather(for: fallback.coordinate)
    }

    private func updateAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            setLocationState(.pending)
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            // Keep showing the last good coordinate while a fresh fix is requested.
            if !currentLocationState().isCurrent {
                setLocationState(.pending)
            }
            manager.requestLocation()
        case .denied:
            applyFallback(.fallback("Location denied"))
        case .restricted:
            applyFallback(.fallback("Location restricted"))
        @unknown default:
            applyFallback(.fallback("Location unavailable"))
        }
    }

    // MARK: - Periodic refresh

    /// Refresh cadence follows the "Update interval" setting (1-30 minutes, default 5).
    /// The weather service caches responses, so short intervals stay cheap.
    private static func preferredRefreshInterval() -> TimeInterval {
        let minutes = UserDefaults.standard.double(forKey: "updateIntervalMinutes")
        guard minutes >= 1 else {
            return 5 * 60
        }

        return min(max(minutes, 1), 30) * 60
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()

        let interval = Self.preferredRefreshInterval()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.periodicRefresh()
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func userDefaultsDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let refreshTimer = self.refreshTimer else { return }

            if refreshTimer.timeInterval != Self.preferredRefreshInterval() {
                self.scheduleRefreshTimer()
            }
        }
    }

    private func periodicRefresh() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // Re-fetch weather for the last known coordinate even if the location
            // fix doesn't change, and ask for a fresh fix in case it did.
            refreshWeather(for: currentLocationState().coordinate)
            manager.requestLocation()
        case .notDetermined:
            // Still no answer after a full interval - stop claiming "Locating..."
            // but keep asking; granting later recovers via the delegate callback.
            if currentLocationState().isPending {
                applyFallback(.fallback("Location unavailable"))
            }
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            refreshWeather(for: currentLocationState().coordinate)
        @unknown default:
            refreshWeather(for: currentLocationState().coordinate)
        }
    }

    private func scheduleFailureRetry() {
        guard retryTask == nil else {
            return
        }

        let delay = failureRetryDelay
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.retryTask = nil

                switch self.manager.authorizationStatus {
                case .authorizedAlways, .authorizedWhenInUse:
                    self.manager.requestLocation()
                default:
                    break
                }
            }
        }
    }

    private func applyFallback(_ state: LocationState) {
        setLocationState(state)
        refreshWeather(for: state.coordinate)
    }

    // MARK: - State

    private func currentLocationState() -> LocationState {
        lock.lock()
        defer { lock.unlock() }
        return locationState
    }

    private func currentWeather() -> WeatherSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return cachedWeather
    }

    private func refreshWeather(for coordinate: Coordinate) {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.weatherService.weather(for: coordinate)
            self.setWeather(snapshot)
        }
    }

    private func setLocationState(_ state: LocationState) {
        lock.lock()
        let didChange = locationState != state
        locationState = state
        lock.unlock()

        guard didChange else {
            return
        }

        onStatusChanged?()
    }

    private func setWeather(_ snapshot: WeatherSnapshot?) {
        lock.lock()
        let didChange = cachedWeather != snapshot
        cachedWeather = snapshot
        lock.unlock()

        guard didChange else {
            return
        }

        onStatusChanged?()
    }
}

private enum LocationState: Equatable {
    case pending
    case current(Coordinate)
    case fallback(String)

    var coordinate: Coordinate {
        switch self {
        case .current(let coordinate):
            return coordinate
        case .pending, .fallback:
            return Coordinate(latitude: 37.7749, longitude: -122.4194)
        }
    }

    var locationName: String {
        switch self {
        case .current:
            return "Current Location"
        case .pending:
            return "Locating..."
        case .fallback(let reason):
            return "\(reason) - San Francisco fallback"
        }
    }

    var timezone: TimeZone {
        switch self {
        case .current:
            return .current
        case .pending, .fallback:
            return TimeZone(identifier: "America/Los_Angeles") ?? .current
        }
    }

    var isPending: Bool {
        if case .pending = self {
            return true
        }

        return false
    }

    var isCurrent: Bool {
        if case .current = self {
            return true
        }

        return false
    }
}
