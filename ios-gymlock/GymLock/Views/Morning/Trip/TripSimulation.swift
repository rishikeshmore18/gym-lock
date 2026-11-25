#if DEBUG
import CoreLocation
import Observation

/// Drives the trip screen without anyone moving, for the Day Flow Simulator's
/// "trip demo" scenario.
///
/// It stands in for GPS only. Everything else is the real thing: the real
/// session, the real coordinator calls for leaving home, entering the gym area
/// and confirming arrival, and Apple's real route between a made-up start point
/// and the user's real gym. Nothing here runs in a release build.
@MainActor
@Observable
final class TripSimulation {
    static let shared = TripSimulation()

    /// True from the scenario starting until the demo has handed over to the
    /// arrival screen.
    private(set) var isActive = false
    /// The demo's own dwell, 0...1, so the two-minute check plays in seconds.
    private(set) var dwellProgress: Double?

    @ObservationIgnored private weak var coordinator: GymSessionCoordinator?
    @ObservationIgnored private weak var model: TripModel?
    @ObservationIgnored private var gym = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @ObservationIgnored private var start = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var hasStartedTrip = false

    /// Seconds of standing at home before walking off.
    private static let holdAtHome: Double = 3
    /// Seconds the walk to the gym takes in the demo.
    private static let tripSeconds: Double = 30
    /// Seconds the demo's dwell takes (two minutes in real life).
    private static let dwellSeconds: Double = 8

    private init() {}

    /// Arms the demo for `gym`. The walk starts when the trip screen says it is
    /// on screen (after the wake page's "Let's go", if that page plays).
    func begin(gym: CLLocationCoordinate2D, coordinator: GymSessionCoordinator) {
        stop()
        self.gym = gym
        self.coordinator = coordinator
        // About 1.2 km south-west of the gym, far enough to need a real route.
        start = CLLocationCoordinate2D(latitude: gym.latitude - 0.0075, longitude: gym.longitude - 0.0095)
        isActive = true
    }

    func stop() {
        task?.cancel()
        task = nil
        isActive = false
        dwellProgress = nil
        hasStartedTrip = false
        model = nil
    }

    /// Called by `TripModel.start()` instead of turning GPS on.
    func attach(_ model: TripModel) {
        self.model = model
        model.ingest(start)
    }

    /// Called by the trip screen once its entry has started playing.
    func tripDidStart() {
        guard isActive, !hasStartedTrip else { return }
        hasStartedTrip = true
        task = Task { [weak self] in await self?.run() }
    }

    // MARK: - The script

    private func run() async {
        try? await Task.sleep(for: .seconds(Self.holdAtHome))
        guard !Task.isCancelled, let model else { return }

        // Give Apple up to five seconds to answer with a real route.
        var waited = 0
        while model.route.count < 2, waited < 50, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        let path = model.route.count >= 2 ? model.route : [start, gym]
        var sums: [Double] = [0]
        for index in 1..<path.count {
            sums.append(sums[index - 1] + TripModel.distance(path[index - 1], path[index]))
        }
        let total = max(sums.last ?? 0, 1)

        let began = Date()
        var hasDeparted = false
        while !Task.isCancelled {
            guard isTripLive else { stop(); return }
            let fraction = min(1, Date().timeIntervalSince(began) / Self.tripSeconds)
            let point = Self.point(along: fraction * total, path: path, sums: sums)
            model.ingest(point)

            if !hasDeparted, TripModel.distance(point, start) >= SessionAnchor.departureRadius {
                hasDeparted = true
                coordinator?.markDeparted(detected: true)
            }
            if fraction >= 1 { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }

        // Inside the gym area: the real candidate path, then a short dwell.
        coordinator?.debugNoteCandidate()
        let dwellBegan = Date()
        while !Task.isCancelled {
            guard isTripLive else { stop(); return }
            let fraction = min(1, Date().timeIntervalSince(dwellBegan) / Self.dwellSeconds)
            dwellProgress = fraction
            if fraction >= 1 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !Task.isCancelled, isTripLive else { stop(); return }

        coordinator?.confirmArrival()
        // Long enough for the verified finale to play, then GPS is real again.
        try? await Task.sleep(for: .seconds(6))
        stop()
    }

    /// The demo only acts while the session is still on its way to the gym:
    /// "End", "can't today" or an expired window stop it.
    private var isTripLive: Bool {
        guard let state = coordinator?.session?.state else { return false }
        return state == .preparing || state == .departed || state == .approachingGym
    }

    private static func point(along distance: Double, path: [CLLocationCoordinate2D], sums: [Double]) -> CLLocationCoordinate2D {
        guard let last = path.last else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        for index in 1..<path.count where sums[index] >= distance {
            let segment = sums[index] - sums[index - 1]
            let t = segment > 0 ? (distance - sums[index - 1]) / segment : 0
            let a = path[index - 1], b = path[index]
            return CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * t,
                longitude: a.longitude + (b.longitude - a.longitude) * t
            )
        }
        return last
    }
}
#endif
