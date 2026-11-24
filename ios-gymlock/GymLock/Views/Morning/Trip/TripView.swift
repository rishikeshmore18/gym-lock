import CoreLocation
import SwiftUI

/// The trip to the gym, as one page.
///
/// Replaces the countdown, the "let's go!!" departure screen and the
/// "confirming arrival" screen with a single live screen that follows the user
/// from the wake page's "Let's go" to the gym door: a live map of the real
/// route, one countdown to the gym time, and the arrival check. It changes in
/// place instead of swapping screens, so leaving home and arriving read as
/// moments of one trip.
///
/// Nothing here decides anything. The phase comes from the coordinator's route
/// (which comes from the session), departure and arrival are still detected by
/// `SessionLocationMonitor` and `GymArrivalMonitor`, and the deadline is the
/// session's own. `TripModel` only adds what is needed to draw: live position,
/// Apple's route and its distance and time.
///
/// Drawn in the Home card's style: Ridge (a live map over the mountain band) or
/// Matrix (the same map rebuilt in dots).
struct TripView: View {
    let session: GymSession
    let route: MorningRoute
    let gym: GymLocation
    let onLeft: () -> Void
    let onEnd: () -> Void
    let onTrouble: () -> Void
    let onAcknowledgeDeparture: () -> Void
    /// The trip page is on screen for this session (the router uses it to
    /// decide whether the verified finale plays before the arrival screen).
    let onShown: () -> Void
    let onHidden: () -> Void
    let onFinaleDone: () -> Void

    @AppStorage(HeroCardStyle.storageKey) private var cardStyleRaw = HeroCardStyle.default.rawValue

    @State private var model: TripModel?
    /// The wake page sits on top on the first frame of a session that has not
    /// played it; the entry waits for its "Let's go".
    @State private var waitsForIntro: Bool
    @State private var entryStarted = false

    init(
        session: GymSession,
        route: MorningRoute,
        gym: GymLocation,
        onLeft: @escaping () -> Void,
        onEnd: @escaping () -> Void,
        onTrouble: @escaping () -> Void,
        onAcknowledgeDeparture: @escaping () -> Void,
        onShown: @escaping () -> Void,
        onHidden: @escaping () -> Void,
        onFinaleDone: @escaping () -> Void
    ) {
        self.session = session
        self.route = route
        self.gym = gym
        self.onLeft = onLeft
        self.onEnd = onEnd
        self.onTrouble = onTrouble
        self.onAcknowledgeDeparture = onAcknowledgeDeparture
        self.onShown = onShown
        self.onHidden = onHidden
        self.onFinaleDone = onFinaleDone
        _waitsForIntro = State(initialValue: route == .countdown && WakeIntroLedger.isEligible(session, route: .countdown))
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if let model {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    page(model: model, frame: frame(at: context.date, model: model))
                }
            }
        }
        // The "I'm up" wake page when missions are off, over the first frame.
        // Its capsule ("Let's go") closes it onto the trip, which then plays
        // its entry.
        .overlay {
            WakeIntroPresenter(session: session, route: .countdown) { _ in
                startEntry()
            }
        }
        .onAppear {
            if model == nil {
                let fresh = TripModel(gym: gym.coordinate)
                model = fresh
                fresh.start()
            }
            onShown()
            if !waitsForIntro { startEntry() }
        }
        .onDisappear {
            model?.stop()
            onHidden()
        }
        // The departure moment is a change on this page, not a screen: once it
        // has played, the router goes back to the plain trip.
        .task(id: route) {
            guard route == .departed else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            onAcknowledgeDeparture()
        }
    }

    @ViewBuilder
    private func page(model: TripModel, frame: TripFrame) -> some View {
        let actions = TripActions(left: onLeft, end: onEnd, trouble: onTrouble, finaleDone: onFinaleDone)
        if HeroCardStyle(rawValue: cardStyleRaw) == .matrix {
            MatrixTripView(model: model, frame: frame, actions: actions)
        } else {
            RidgeTripView(model: model, frame: frame, actions: actions)
        }
    }

    // MARK: - Derived

    private var phase: TripPhase {
        switch route {
        case .confirmingArrival: .verifying
        case .gymSuccess: .verified
        default: session.departedAt == nil ? .atHome : .onTheWay
        }
    }

    private func frame(at now: Date, model: TripModel) -> TripFrame {
        let phase = self.phase
        let voice = SessionVoice(session: self.session)
        let session = self.session
        return TripFrame(
            phase: phase,
            remaining: session.remaining(at: now),
            gymBy: session.deadline.map { TimeOfDay(from: $0).displayString },
            distanceLine: TripFormat.distanceLine(metres: model.remainingDistance, seconds: model.remainingTime),
            gymName: gym.name,
            heading: voice.windowHeading(hasLeft: phase.hasLeft),
            support: voice.windowSupport(hasLeft: phase.hasLeft),
            entryStarted: entryStarted,
            verifyProgress: { date in Self.verifyProgress(session: session, at: date) }
        )
    }

    /// How far through the two-minute check, from the session's own candidate
    /// time. The debug demo shortens it.
    private static func verifyProgress(session: GymSession, at date: Date) -> Double {
        #if DEBUG
        if let demo = TripSimulation.shared.dwellProgress { return demo }
        #endif
        if session.gymArrivalVerified { return 1 }
        return session.dwellProgress(at: date)
    }

    private func startEntry() {
        guard !entryStarted else { return }
        entryStarted = true
        #if DEBUG
        TripSimulation.shared.tripDidStart()
        #endif
    }
}
