import CoreLocation
import Observation

/// Watches whether the user has actually left where they started this morning.
///
/// The anchor is captured at the moment they tap "I'm going" and is deleted when
/// the session ends. It is emphatically **not** a home address:
///
/// - it is never labelled as one anywhere in the app,
/// - it is never written outside the active session record,
/// - it works identically in a hotel, at a partner's flat, or on holiday,
/// - and it is discarded on departure, cancellation, expiry, or completion.
///
/// The only question it answers is "has this person moved away from wherever
/// they woke up", which is the difference between a plan and a decision.
@Observable
@MainActor
final class SessionLocationMonitor: NSObject {
    enum Availability: Equatable {
        case unknown
        case ready
        case denied
        case unsupported
    }

    private(set) var availability: Availability = .unknown
    private(set) var hasLeftAnchor = false
    /// Metres from the anchor, for diagnostics only. Never shown as a map.
    private(set) var distanceFromAnchor: Double = 0

    private let manager = CLLocationManager()
    private var anchor: SessionAnchor?
    private var onDeparture: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Only report once the user has moved a meaningful distance, so this
        // costs almost nothing while they are still in the bathroom.
        manager.distanceFilter = 50
    }

    var canTrack: Bool { availability == .ready }

    func refreshAvailability() {
        guard CLLocationManager.locationServicesEnabled() else {
            availability = .unsupported
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: availability = .ready
        case .denied, .restricted: availability = .denied
        default: availability = .unknown
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Captures the temporary start point and begins watching for departure.
    ///
    /// Returns nil when location is unavailable, in which case the morning still
    /// works end to end — departure is simply confirmed by the user instead of
    /// detected.
    @discardableResult
    func beginSession(onDeparture: @escaping () -> Void) -> SessionAnchor? {
        refreshAvailability()
        guard availability == .ready, let location = manager.location else {
            self.onDeparture = onDeparture
            manager.startUpdatingLocation()
            return nil
        }

        let anchor = SessionAnchor(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            capturedAt: Date()
        )

        self.anchor = anchor
        self.onDeparture = onDeparture
        hasLeftAnchor = false
        distanceFromAnchor = 0
        manager.startUpdatingLocation()

        return anchor
    }

    /// Restores watching after a relaunch mid-session.
    func resume(from anchor: SessionAnchor, onDeparture: @escaping () -> Void) {
        refreshAvailability()
        self.anchor = anchor
        self.onDeparture = onDeparture
        guard availability == .ready else { return }
        manager.startUpdatingLocation()
    }

    /// Stops tracking and forgets the anchor entirely.
    func endSession() {
        manager.stopUpdatingLocation()
        anchor = nil
        onDeparture = nil
        hasLeftAnchor = false
        distanceFromAnchor = 0
    }
}

// MARK: - CLLocationManagerDelegate

extension SessionLocationMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        let coordinate = latest.coordinate

        Task { @MainActor in
            guard let anchor else {
                // No anchor yet means authorisation only just landed; the first
                // fix becomes the start point.
                self.anchor = SessionAnchor(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    capturedAt: Date()
                )
                return
            }

            let origin = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            let distance = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ).distance(from: origin)

            distanceFromAnchor = distance

            guard !hasLeftAnchor, distance >= SessionAnchor.departureRadius else { return }
            hasLeftAnchor = true
            onDeparture?()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in refreshAvailability() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix is not worth interrupting a morning over. Departure just
        // falls back to the user confirming it themselves.
    }
}
