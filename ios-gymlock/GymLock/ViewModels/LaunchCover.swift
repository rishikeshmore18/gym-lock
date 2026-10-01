import Foundation
import Observation

/// The branded cover a cold launch opens on, while the real app mounts and
/// prepares underneath it.
///
/// Once per process, and only in memory. It is created on the first frame the
/// app draws and never again until the process dies, so a tab switch, a trip
/// to Control Centre or a return from the background can never bring it back.
/// Nothing is persisted: this is not a first-install screen.
///
/// It never delays anything. The app underneath is built at the same moment
/// the cover is, and the cover only decides when that already-built app is
/// shown: after a short minimum, as soon as the content says it has settled,
/// and never later than a hard deadline.
@MainActor
@Observable
final class LaunchCover {
    enum Phase: Equatable {
        /// Fully opaque, taking every touch, the app hidden from VoiceOver.
        case covering
        /// Fading away. Inert: the app underneath already takes touches.
        case revealing
        /// Gone from the hierarchy.
        case finished
    }

    struct Timing: Equatable {
        /// Shortest time the logo is held, so it reads as a moment rather
        /// than a flicker.
        var minimum: Duration
        /// Latest the reveal may start, ready or not. A slow flame must
        /// never hold the app hostage.
        var deadline: Duration
        /// How long the fade takes before the cover leaves the hierarchy.
        var exit: Duration

        /// About 0.9s visible normally, never more than about 1.3s.
        static let standard = Timing(
            minimum: .milliseconds(700),
            deadline: .milliseconds(1050),
            exit: .milliseconds(240)
        )
    }

    /// The one cover for this process.
    static let shared = LaunchCover(timing: .standard, startsClock: true)

    private(set) var phase: Phase = .covering

    /// True until the reveal begins. While it holds, the app underneath keeps
    /// its launch-time presentations (the streak entrance, sheets, setup) to
    /// itself.
    var isHoldingApp: Bool { phase == .covering }

    /// Whether the cover is in the hierarchy at all.
    var isVisible: Bool { phase != .finished }

    let timing: Timing

    @ObservationIgnored private var isContentReady = false
    @ObservationIgnored private var hasMetMinimum = false
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var exit: Task<Void, Never>?

    /// - Parameter startsClock: false in tests, which drive the minimum and the
    ///   deadline by hand.
    init(timing: Timing, startsClock: Bool) {
        self.timing = timing
        guard startsClock else { return }
        clock = Task { [weak self] in
            try? await Task.sleep(for: timing.minimum)
            guard !Task.isCancelled else { return }
            self?.minimumElapsed()

            try? await Task.sleep(for: timing.deadline - timing.minimum)
            guard !Task.isCancelled else { return }
            self?.deadlinePassed()
        }
    }

    /// The screen underneath has settled: mounted, measured, and done with
    /// its expensive first-time preparation (or given up on it).
    func contentIsReady() {
        guard !isContentReady else { return }
        isContentReady = true
        revealIfDue()
    }

    func minimumElapsed() {
        hasMetMinimum = true
        revealIfDue()
    }

    func deadlinePassed() {
        reveal()
    }

    /// A live morning outranks branding. Starts the fade at once, with no
    /// minimum, underneath the morning flow that is already being presented.
    func yieldToMorning() {
        reveal()
    }

    /// Ends the cover with no animation, for when nobody is watching it (the
    /// app went to the background mid-intro). Never replays.
    func finishImmediately() {
        clock?.cancel()
        exit?.cancel()
        phase = .finished
    }

    private func revealIfDue() {
        guard isContentReady, hasMetMinimum else { return }
        reveal()
    }

    private func reveal() {
        guard phase == .covering else { return }
        clock?.cancel()
        phase = .revealing
        exit = Task { [weak self, timing] in
            try? await Task.sleep(for: timing.exit)
            guard !Task.isCancelled, let self, phase == .revealing else { return }
            phase = .finished
        }
    }
}
