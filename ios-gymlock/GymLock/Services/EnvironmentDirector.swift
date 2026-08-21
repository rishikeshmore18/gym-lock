import CoreLocation
import Foundation
import Observation
import WeatherKit

/// Decides which environment the mountain should be rendered under.
///
/// The rules here are deliberately defensive. The mountain is the centrepiece
/// of a screen the user opens every morning, so it has to look right when there
/// is no location permission, no network, no weather entitlement and no cache.
/// The device clock alone is always enough for a correct-looking scene; weather
/// only ever *improves* it.
@Observable
@MainActor
final class EnvironmentDirector: NSObject {
    private enum Key {
        static let cachedCondition = "gymlock.weather.condition"
        static let cachedAt = "gymlock.weather.fetchedAt"
    }

    /// The environment currently in force.
    private(set) var state: EnvironmentState = EnvironmentState(
        phase: DayPhase.current(),
        condition: .clear
    )

    /// True while the scene is running on the clock alone.
    private(set) var isUsingLocalTimeOnly = true
    /// Set when the user could turn weather on but has not been asked yet.
    private(set) var canOfferWeather = false
    private(set) var lastError: String?

    private let defaults: UserDefaults
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared

    private var clockTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var lastFetch: Date?
    private var isRunning = false

    /// Weather is polled at most twice an hour. Mountain weather does not
    /// change fast enough to justify anything more, and the battery cost of a
    /// chattier loop would be paid on the home screen.
    private let minimumFetchInterval: TimeInterval = 30 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        // A cached condition means yesterday's snow is still on the mountain
        // when the app opens in a tunnel, rather than a sudden clear day.
        if let raw = defaults.string(forKey: Key.cachedCondition),
           let cached = SkyCondition(rawValue: raw) {
            state = EnvironmentState(phase: DayPhase.current(), condition: cached)
            isUsingLocalTimeOnly = false
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshPhase()
        startClock()
        evaluateAuthorisation()
    }

    func stop() {
        isRunning = false
        clockTask?.cancel()
        clockTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        locationManager.stopUpdatingLocation()
    }

    /// Ticks the time of day. Cheap, and the only loop that always runs.
    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                self.refreshPhase()
                self.refreshWeatherIfStale()
            }
        }
    }

    private func refreshPhase() {
        let phase = DayPhase.current()
        guard phase != state.phase else { return }
        state = EnvironmentState(phase: phase, condition: state.condition)
    }

    // MARK: - Location

    private func evaluateAuthorisation() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            canOfferWeather = false
            locationManager.requestLocation()
        case .notDetermined:
            // Never asked on launch. The mountain works without it, so the
            // prompt is an offer the user can accept, not a toll gate.
            canOfferWeather = true
        case .denied, .restricted:
            canOfferWeather = false
            isUsingLocalTimeOnly = defaults.string(forKey: Key.cachedCondition) == nil
        @unknown default:
            canOfferWeather = false
        }
    }

    /// Called from the small "enable local weather" affordance.
    func requestWeatherAccess() {
        canOfferWeather = false
        locationManager.requestWhenInUseAuthorization()
    }

    private func refreshWeatherIfStale() {
        guard let lastFetch else {
            evaluateAuthorisation()
            return
        }
        guard Date().timeIntervalSince(lastFetch) > minimumFetchInterval else { return }
        evaluateAuthorisation()
    }

    // MARK: - Weather

    private func fetchWeather(for location: CLLocation) {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let weather = try await self.weatherService.weather(for: location)
                guard !Task.isCancelled else { return }

                let condition = Self.map(
                    weather.currentWeather.condition,
                    cloudCover: weather.currentWeather.cloudCover,
                    isDaylight: weather.currentWeather.isDaylight
                )
                self.commit(condition)
                self.lastFetch = Date()
                self.lastError = nil
            } catch {
                // Missing entitlement, no network, throttling — all handled the
                // same way, because the user does not care which it was.
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.isUsingLocalTimeOnly = self.defaults.string(forKey: Key.cachedCondition) == nil
            }
        }
    }

    private func commit(_ condition: SkyCondition) {
        isUsingLocalTimeOnly = false
        defaults.set(condition.rawValue, forKey: Key.cachedCondition)
        defaults.set(Date(), forKey: Key.cachedAt)

        guard condition != state.condition else { return }
        state = EnvironmentState(phase: DayPhase.current(), condition: condition)
    }

    /// Collapses WeatherKit's long condition list into the six looks the scene
    /// knows how to draw.
    ///
    /// The mapping is intentionally lossy: "drizzle", "rain" and "heavy rain"
    /// all become one rain state so a passing shower cannot restage the scene
    /// three times in ten minutes.
    nonisolated static func map(
        _ condition: WeatherCondition,
        cloudCover: Double,
        isDaylight: Bool
    ) -> SkyCondition {
        switch condition {
        case .thunderstorms, .strongStorms, .tropicalStorm, .hurricane:
            return .storm

        case .blizzard, .blowingSnow, .flurries, .heavySnow, .snow, .sunFlurries,
             .wintryMix, .sleet, .freezingRain, .freezingDrizzle, .hail:
            return .snow

        case .drizzle, .rain, .heavyRain, .sunShowers, .isolatedThunderstorms:
            return .rain

        case .foggy, .haze, .smoky:
            return .fog

        case .cloudy, .mostlyCloudy, .breezy, .windy, .blowingDust:
            return .cloudy

        case .clear, .mostlyClear, .hot, .frigid:
            return cloudCover > 0.72 ? .cloudy : .clear

        case .partlyCloudy:
            return cloudCover > 0.62 ? .cloudy : .clear

        @unknown default:
            return cloudCover > 0.72 ? .cloudy : .clear
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension EnvironmentDirector: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.evaluateAuthorisation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.fetchWeather(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // No modal, no banner, no retry storm — the scene simply stays on
            // the clock.
            self.lastError = error.localizedDescription
            self.isUsingLocalTimeOnly = self.defaults.string(forKey: Key.cachedCondition) == nil
        }
    }
}
