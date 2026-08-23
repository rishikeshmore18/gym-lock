import CoreMotion
import Observation

/// Counts steps for the movement missions.
///
/// `CMPedometer` is used in its live-updates form rather than by querying
/// history, because the mission is "take twenty steps *now*" — crediting steps
/// the user took before the alarm went off would make the check meaningless.
/// The baseline is therefore the moment the mission starts.
@Observable
@MainActor
final class MotionMissionMonitor {
    enum Availability: Equatable {
        case unknown
        case ready
        case denied
        case unsupported
    }

    private(set) var availability: Availability = .unknown
    /// Steps taken since the mission began.
    private(set) var steps = 0
    private(set) var isRunning = false

    private let pedometer = CMPedometer()

    /// Whether step missions may be offered at all.
    var canVerify: Bool { availability == .ready }

    func refreshAvailability() {
        guard CMPedometer.isStepCountingAvailable() else {
            availability = .unsupported
            return
        }

        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted:
            availability = .denied
        default:
            // `.notDetermined` still counts as usable: the prompt appears when
            // updates start, and pre-emptively excluding the mission would mean
            // the user is never asked.
            availability = .ready
        }
    }

    func start() {
        guard !isRunning else { return }
        refreshAvailability()
        guard availability == .ready else { return }

        steps = 0
        isRunning = true

        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self else { return }

            Task { @MainActor in
                guard error == nil, let data else {
                    // The most common error here is the user declining the
                    // Motion prompt, which the mission screen turns into an
                    // offer of a different mission rather than a dead end.
                    if error != nil { self.availability = .denied }
                    return
                }
                self.steps = data.numberOfSteps.intValue
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        pedometer.stopUpdates()
        isRunning = false
    }

    func reset() {
        stop()
        steps = 0
    }
}
