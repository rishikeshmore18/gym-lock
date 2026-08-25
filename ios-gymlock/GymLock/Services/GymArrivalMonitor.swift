import CoreLocation
import Observation

/// Watches for the user actually arriving at their gym.
///
/// This is the single most consequential piece of automation in the product: it
/// is what unlocks the user's apps without them touching the phone. That makes
/// both failure modes expensive, and they pull in opposite directions.
///
/// - **A false positive** unlocks Instagram while the user is still at home, and
///   the product silently stops working.
/// - **A false negative** leaves someone standing in their gym with their apps
///   locked and no idea why, which is worse.
///
/// The design threads that needle in three steps:
///
/// 1. **Region entry is only a candidate.** iOS geofences are coarse and fire
///    from a surprising distance.
/// 2. **Fixes are quality-gated.** A position reported as accurate to 500 m
///    cannot distinguish a gym from the café next door, so it is discarded
///    rather than trusted.
/// 3. **A short dwell confirms it.** Driving past does not unlock anything.
///
/// If none of that succeeds within the timeout, the monitor reports honest
/// failure and the app offers a way out. It never guesses.
@Observable
@MainActor
final class GymArrivalMonitor: NSObject {
    enum Availability: Equatable {
        case unknown
        case ready
        /// Granted only while the app is open. Region monitoring will not wake
        /// the app, so arrival is detected on next foreground instead.
        case whenInUseOnly
        case denied
        case unsupported
    }

    /// Where confirmation currently stands.
    enum Phase: Equatable {
        case idle
        /// Watching the geofence; nothing has happened yet.
        case armed
        /// Inside the region, running the dwell check.
        case confirming(since: Date)
        /// Confirmed.
        case arrived
        /// Could not be established. Carries a plain-language reason.
        case trouble(String)
    }

    private(set) var availability: Availability = .unknown
    private(set) var phase: Phase = .idle
    /// Best recent accuracy in metres, for the debug panel only.
    private(set) var lastAccuracy: Double?
    private(set) var lastDistance: Double?

    private let manager = CLLocationManager()
    private var gym: GymLocation?
    private var onArrival: (() -> Void)?
    private var onCandidate: (() -> Void)?
    private var onTrouble: ((String) -> Void)?

    private var dwellTask: Task<Void, Never>?
    private var startedConfirmingAt: Date?
    private var confirmationDeadline: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    // MARK: - Availability

    var canDetectArrival: Bool {
        availability == .ready || availability == .whenInUseOnly
    }

    /// True when the OS will wake the app for a geofence crossing.
    ///
    /// Without Always authorisation the user has to open GymLock for arrival to
    /// register, so the UI needs to know which world it is in.
    var canDetectInBackground: Bool { availability == .ready }

    func refreshAvailability() {
        guard CLLocationManager.locationServicesEnabled(),
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        else {
            availability = .unsupported
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways: availability = .ready
        case .authorizedWhenInUse: availability = .whenInUseOnly
        case .denied, .restricted: availability = .denied
        default: availability = .unknown
        }
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// Asks to upgrade to Always.
    ///
    /// Requested contextually — after the user has picked a gym and can see why
    /// it matters — rather than in a cold prompt at launch.
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Monitoring

    /// Registers the long-lived geofence around the gym.
    ///
    /// Kept armed between sessions rather than started per morning: region
    /// monitoring survives app termination and reboot, which is precisely what
    /// makes arrival detection work without the user opening anything.
    func arm(for gym: GymLocation) {
        refreshAvailability()
        self.gym = gym

        guard canDetectArrival else { return }

        // Replace rather than add, so changing gym cannot leave the old fence
        // running and unlocking apps at a place the user no longer trains.
        disarmRegions()
        manager.startMonitoring(for: gym.region())

        if case .idle = phase { phase = .armed }
    }

    func disarm() {
        dwellTask?.cancel()
        dwellTask = nil
        disarmRegions()
        manager.stopUpdatingLocation()
        gym = nil
        phase = .idle
        startedConfirmingAt = nil
        confirmationDeadline = nil
        onArrival = nil
        onCandidate = nil
        onTrouble = nil
    }

    private func disarmRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix("gymlock.gym.") {
            manager.stopMonitoring(for: region)
        }
    }

    /// Begins watching for arrival during an active session.
    func beginWatching(
        gym: GymLocation,
        onCandidate: @escaping () -> Void,
        onArrival: @escaping () -> Void,
        onTrouble: @escaping (String) -> Void
    ) {
        self.onCandidate = onCandidate
        self.onArrival = onArrival
        self.onTrouble = onTrouble

        arm(for: gym)

        // The user may already be standing in the gym — they might have opened
        // the app on the way in, or beaten their own alarm. A geofence only
        // fires on a *crossing*, so an explicit state request is the only way to
        // notice somebody who is already inside.
        manager.requestState(for: gym.region())
        manager.startUpdatingLocation()
    }

    /// Restores confirmation after a relaunch that happened mid-dwell.
    func resumeConfirming(since candidateAt: Date) {
        guard gym != nil else { return }
        startedConfirmingAt = candidateAt
        phase = .confirming(since: candidateAt)
        confirmationDeadline = Date().addingTimeInterval(ArrivalTuning.confirmationTimeout)
        manager.startUpdatingLocation()
        startDwellCheck()
    }

    // MARK: - Confirmation

    private func noteCandidate() {
        guard gym != nil else { return }
        guard startedConfirmingAt == nil else { return }

        let now = Date()
        startedConfirmingAt = now
        confirmationDeadline = now.addingTimeInterval(ArrivalTuning.confirmationTimeout)
        phase = .confirming(since: now)

        manager.startUpdatingLocation()
        onCandidate?()
        startDwellCheck()
    }

    /// Polls position for the dwell period.
    ///
    /// Sampling rather than trusting one fix: a single reading at the moment of
    /// region entry is exactly the reading most likely to be wrong, because the
    /// radio has usually only just woken up.
    private func startDwellCheck() {
        dwellTask?.cancel()
        dwellTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ArrivalTuning.samplePeriod))
                guard let self else { return }
                await MainActor.run { self.evaluateDwell() }
            }
        }
    }

    private func evaluateDwell() {
        guard let gym, let since = startedConfirmingAt else { return }

        if let deadline = confirmationDeadline, Date() >= deadline {
            fail("GymLock couldn't confirm your location.")
            return
        }

        guard let location = manager.location else { return }

        let accuracy = location.horizontalAccuracy
        lastAccuracy = accuracy

        // A negative accuracy means the fix is invalid; a huge one means it is
        // useless. Neither is evidence of anything, so neither is acted on —
        // the loop simply waits for a better sample.
        guard accuracy > 0, accuracy <= ArrivalTuning.maximumAcceptableAccuracy else { return }

        let distance = gym.distance(from: location)
        lastDistance = distance

        // Drifting well outside the radius mid-dwell means they were passing,
        // not arriving. Reset to armed and wait for a real entry.
        guard distance <= gym.radius + ArrivalTuning.dwellTolerance else {
            resetToArmed()
            return
        }

        guard Date().timeIntervalSince(since) >= ArrivalTuning.dwellSeconds else { return }

        confirmArrival()
    }

    private func confirmArrival() {
        dwellTask?.cancel()
        dwellTask = nil
        manager.stopUpdatingLocation()
        phase = .arrived
        startedConfirmingAt = nil
        confirmationDeadline = nil
        onArrival?()
    }

    private func resetToArmed() {
        dwellTask?.cancel()
        dwellTask = nil
        startedConfirmingAt = nil
        confirmationDeadline = nil
        phase = .armed
        manager.stopUpdatingLocation()
    }

    private func fail(_ message: String) {
        dwellTask?.cancel()
        dwellTask = nil
        manager.stopUpdatingLocation()
        startedConfirmingAt = nil
        confirmationDeadline = nil
        phase = .trouble(message)
        onTrouble?(message)
    }

    // MARK: - Manual confirmation

    /// Accepts arrival on the user's word after detection has genuinely failed.
    ///
    /// Only reachable from the trouble screen, and only after the automatic
    /// attempt timed out. Someone standing in their gym with locked apps must
    /// have a way out that does not depend on the weather over their GPS.
    func acceptManualConfirmation() {
        guard case .trouble = phase else { return }
        phase = .arrived
        onArrival?()
    }

    #if DEBUG
    /// Debug hooks. Compiled out of release entirely.
    func debugSimulateRegionEntry() { noteCandidate() }
    func debugSimulateArrival() { confirmArrival() }
    func debugSimulateDriveBy() { noteCandidate(); resetToArmed() }
    func debugSimulateTrouble() { fail("GymLock couldn't confirm your location.") }
    func debugSetAccuracy(_ value: Double) { lastAccuracy = value }
    #endif
}

// MARK: - CLLocationManagerDelegate

extension GymArrivalMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard region.identifier.hasPrefix("gymlock.gym.") else { return }
        Task { @MainActor in noteCandidate() }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        guard region.identifier.hasPrefix("gymlock.gym.") else { return }
        Task { @MainActor in
            // Leaving before the dwell completed is the drive-by case.
            if case .confirming = phase { resetToArmed() }
        }
    }

    /// Answers the explicit state request used to catch someone already inside.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        guard region.identifier.hasPrefix("gymlock.gym."), state == .inside else { return }
        Task { @MainActor in noteCandidate() }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        let accuracy = latest.horizontalAccuracy

        Task { @MainActor in
            lastAccuracy = accuracy
            // A good fix is worth evaluating immediately rather than waiting for
            // the next poll, so arrival lands as promptly as it honestly can.
            if case .confirming = phase { evaluateDwell() }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refreshAvailability()
            // Re-arm on an upgrade to Always, so a user who grants background
            // access later gets background detection without re-setup.
            if canDetectArrival, let gym { arm(for: gym) }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        Task { @MainActor in
            guard case .confirming = phase else { return }
            fail("GymLock couldn't watch for your gym right now.")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A single bad fix is normal indoors and is not worth surfacing. The
        // confirmation timeout is what eventually reports honest failure.
    }
}
