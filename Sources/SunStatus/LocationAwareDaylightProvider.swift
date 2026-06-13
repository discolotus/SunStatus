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

    private let weatherService = WeatherService()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        DispatchQueue.main.async { [weak self] in
            self?.updateAuthorization()
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
        guard currentLocationState().isPending else {
            return
        }

        setLocationState(.fallback("Location unavailable"))
        refreshWeather(for: LocationState.fallback("").coordinate)
    }

    private func updateAuthorization() {
        guard CLLocationManager.locationServicesEnabled() else {
            setLocationState(.fallback("Location unavailable"))
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            setLocationState(.pending)
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            setLocationState(.pending)
            manager.requestLocation()
        case .denied:
            setLocationState(.fallback("Location denied"))
            refreshWeather(for: LocationState.fallback("").coordinate)
        case .restricted:
            setLocationState(.fallback("Location restricted"))
            refreshWeather(for: LocationState.fallback("").coordinate)
        @unknown default:
            setLocationState(.fallback("Location unavailable"))
        }
    }

    private func refreshWeather(for coordinate: Coordinate) {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.weatherService.weather(for: coordinate)
            self.setWeather(snapshot)
        }
    }

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
}
