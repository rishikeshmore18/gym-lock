import Foundation
import Observation
import SwiftUI

/// The four states the streak can be in.
///
/// One enum rather than a set of booleans, because the states are genuinely
/// exclusive and several of them differ only in ways that booleans would blur:
/// an automatic presentation and a manual one look identical but behave
/// completely differently — one closes itself and shows no controls, the other
/// waits for the user.
enum StreakPresentation: Equatable {
    /// Resting: just the capsule in the header.
    case compact
    /// Mounted, but still exactly the capsule: same size, same place, same
    /// shape. Lasts a frame or two and exists so there is a rendered starting
    /// point to animate away from.
    case arming
    /// Playing the entrance on its own. No close button, closes itself.
    case autoPresenting
    /// Opened by the user. Has a close button, stays until dismissed.
    case manuallyExpanded
    /// Travelling back into the capsule, from either of the above.
    case collapsing
}

/// Owns the streak presentation and the timing of its entrance.
///
/// Kept outside the home view on purpose. The rule is "once per foreground
/// session", so the thing that remembers whether it has played must outlive
/// every tab switch and every scroll — if this lived in the view it would fire
/// again every time the user came back to Home, which is exactly the gimmick
/// this is meant not to be.
@MainActor
@Observable
final class StreakIntroController {
    private(set) var state: StreakPresentation = .compact

    /// Whether the card should exist in the hierarchy at all.
    ///
    /// Held true through the collapse so the animation has something to
    /// animate, then dropped — which is what unloads the Lottie player rather
    /// than leaving it rendering behind the header.
    var isMounted: Bool { state != .compact }

    /// Drives the morph. True while the card is out at full size.
    var isExpanded: Bool { state == .autoPresenting || state == .manuallyExpanded }

    /// Only a manually opened card takes touches. The automatic entrance is a
    /// presentation, not a modal — the user can keep using home straight
    /// through it.
    var isInteractive: Bool { state == .manuallyExpanded }

    /// The close button belongs only to the card the user opened themselves.
    var showsCloseButton: Bool { state == .manuallyExpanded }

    /// Bumped the moment the returning card reaches the capsule, so the capsule
    /// can visibly take it back rather than the card simply vanishing at the
    /// end of its journey.
    private(set) var absorbPulse = 0

    /// Set while a full-screen flow is covering home. The entrance is not spent
    /// playing to nobody behind a cover.
    var isSuspended = false

    private var hasPlayedThisSession = false
    private var leftForegroundAt: Date?
    private var playback: Task<Void, Never>?

    private let defaults: UserDefaults
    private static let lastSeenStreakKey = "gymlock.home.lastSeenStreak"

    /// How long the app must have been away before reopening counts as a new
    /// session. A glance at Control Centre is not a new session.
    private static let sessionGap: TimeInterval = 45

    // MARK: - Motion

    /// High damping throughout: this is a soft expansion, not a bounce. The
    /// response values are long enough to read as travel rather than a pop.
    static let expand: Animation = .spring(response: 0.62, dampingFraction: 0.92)
    static let collapse: Animation = .spring(response: 0.55, dampingFraction: 0.95)

    /// Reduce Motion keeps the same beats but drops the journey.
    static let reducedExpand: Animation = .easeOut(duration: 0.30)
    static let reducedCollapse: Animation = .easeIn(duration: 0.28)

    /// Long enough to guarantee the capsule-sized state is rendered before
    /// anything moves. Two frames at 60Hz, so it holds on a display that misses
    /// one.
    private static let armingFrames = 32

    /// How far into the collapse the capsule reacts. Slightly before the card
    /// lands, so the capsule is already opening as it arrives instead of
    /// twitching afterwards.
    private static let absorbPoint = 0.68

    /// The phases of the automatic entrance, in milliseconds.
    ///
    /// Most of the budget is deliberately spent while the flame is large and
    /// on screen — that is the part worth watching. The travel either side is
    /// long enough to follow and short enough not to feel slow.
    struct Timing {
        var settle: Int
        var expandTravel: Int
        var flameMoment: Int
        var hold: Int
        var collapseTravel: Int

        /// ~3.0s standard, ~2.9s with Reduce Motion — the shorter travel is
        /// given back to the hold so the flame still gets its full moment.
        static let standard = Timing(
            settle: 240, expandTravel: 620, flameMoment: 1100, hold: 520, collapseTravel: 560
        )
        static let reducedMotion = Timing(
            settle: 200, expandTravel: 340, flameMoment: 1100, hold: 900, collapseTravel: 340
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The streak the user was last shown, used only to decide how warm the
    /// haptic should be.
    ///
    /// This is a record of what the interface displayed, not a second streak
    /// calculation. `MomentumLog` remains the only thing that knows what the
    /// streak actually is.
    private var lastSeenStreak: Int? {
        get { defaults.object(forKey: Self.lastSeenStreakKey) as? Int }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.lastSeenStreakKey)
            } else {
                defaults.removeObject(forKey: Self.lastSeenStreakKey)
            }
        }
    }

    // MARK: - Automatic entrance

    /// Plays the entrance, if it hasn't already run this session.
    func play(streak: Int, reduceMotion: Bool) {
        guard !isSuspended, !hasPlayedThisSession, state == .compact else { return }
        hasPlayedThisSession = true

        let previous = lastSeenStreak
        lastSeenStreak = streak

        playback?.cancel()
        playback = Task { [weak self] in
            await self?.run(streak: streak, previous: previous, reduceMotion: reduceMotion)
        }
    }

    /// Called when a covering flow finishes, so a suppressed entrance still
    /// gets its turn.
    func resume(streak: Int, reduceMotion: Bool) {
        isSuspended = false
        play(streak: streak, reduceMotion: reduceMotion)
    }

    // MARK: - Manual presentation

    /// Opens the card because the user tapped the capsule.
    ///
    /// Available whether or not the automatic entrance has already run, and it
    /// takes over from one that is still playing — the user asking for it beats
    /// a presentation that was about to close itself.
    func open(reduceMotion: Bool) {
        switch state {
        case .manuallyExpanded:
            return
        case .autoPresenting:
            // Already out. Adopt it — give it a close button and stop its
            // timer — rather than replaying a journey the user just watched.
            playback?.cancel()
            playback = nil
            state = .manuallyExpanded
        default:
            arm(into: .manuallyExpanded, reduceMotion: reduceMotion)
        }
    }

    /// Mounts the card at the capsule's exact geometry, waits for it to be
    /// rendered there, and only then expands it.
    ///
    /// This frame is the difference between a morph and a fade. A view inserted
    /// in its final state has no previous value for SwiftUI to animate from, so
    /// the card would simply appear in the middle of the screen — which is
    /// precisely what it must not do.
    private func arm(into destination: StreakPresentation, reduceMotion: Bool) {
        playback?.cancel()
        state = .arming

        playback = Task { [weak self] in
            guard await self?.sleep(Self.armingFrames) == true else { return }
            guard let self, state == .arming else { return }

            withAnimation(reduceMotion ? Self.reducedExpand : Self.expand) {
                state = destination
            }
        }
    }

    /// Closes a manually opened card, by whichever route the user chose. Every
    /// route runs the same collapse, so the card is always absorbed back into
    /// the capsule rather than blinking away.
    /// The haptic is not fired here but when the card actually arrives, so the
    /// feedback lands with the capsule taking it back rather than with the
    /// user's finger half a second earlier.
    func close(reduceMotion: Bool) {
        guard state == .manuallyExpanded else { return }
        collapse(reduceMotion: reduceMotion, userInitiated: true)
    }

    // MARK: - Lifecycle

    /// Normalises state without ceremony.
    ///
    /// Used when the user leaves for another tab or backgrounds the app. There
    /// is no point animating a collapse onto a screen nobody is looking at, and
    /// correct state matters more than finishing the motion: the streak always
    /// ends up compact, never a stranded overlay, a dimmed tab, or an X button
    /// floating over somebody else's screen.
    func normalizeImmediately() {
        playback?.cancel()
        playback = nil
        state = .compact
    }

    func sceneLeftForeground() {
        leftForegroundAt = Date()
        normalizeImmediately()
    }

    func sceneBecameActive(streak: Int, reduceMotion: Bool, isHomeVisible: Bool) {
        if let leftForegroundAt, Date().timeIntervalSince(leftForegroundAt) > Self.sessionGap {
            hasPlayedThisSession = false
        }
        self.leftForegroundAt = nil

        // A card the user had open before backgrounding is not restored. They
        // left; coming back to a dimmed screen would be the app deciding what
        // they wanted.
        guard isHomeVisible else { return }
        play(streak: streak, reduceMotion: reduceMotion)
    }

    // MARK: - Sequence

    private func run(streak: Int, previous: Int?, reduceMotion: Bool) async {
        let timing = reduceMotion ? Timing.reducedMotion : Timing.standard

        // Let the screen settle first, so the card grows out of a header that
        // has already arrived rather than racing it.
        guard await sleep(timing.settle) else { return }

        state = .arming
        guard await sleep(Self.armingFrames), state == .arming else { return }

        withAnimation(reduceMotion ? Self.reducedExpand : Self.expand) {
            state = .autoPresenting
        }

        // The card has landed and the number has resolved by now.
        guard await sleep(timing.expandTravel) else { return }
        playHaptic(streak: streak, previous: previous)

        // The part worth watching, then a beat to take it in.
        guard await sleep(timing.flameMoment + timing.hold) else { return }

        // A manual open during the sequence wins; don't yank it closed.
        guard state == .autoPresenting else { return }
        collapse(reduceMotion: reduceMotion, userInitiated: false)
    }

    /// Runs the shared collapse, hands the capsule its cue, and unmounts once
    /// the card has finished travelling.
    private func collapse(reduceMotion: Bool, userInitiated: Bool) {
        let travel = (reduceMotion ? Timing.reducedMotion : Timing.standard).collapseTravel
        let absorbAt = Int(Double(travel) * Self.absorbPoint)

        playback?.cancel()
        withAnimation(reduceMotion ? Self.reducedCollapse : Self.collapse) {
            state = .collapsing
        }

        playback = Task { [weak self] in
            guard await self?.sleep(absorbAt) == true else { return }
            guard let self, state == .collapsing else { return }

            // Reduce Motion gets the feedback without the squeeze: there is no
            // journey to receive, so nothing should visibly flex.
            if !reduceMotion { absorbPulse &+= 1 }
            if userInitiated { Haptics.tap(intensity: 0.45) }

            guard await sleep(travel - absorbAt), state == .collapsing else { return }
            state = .compact
            playback = nil
        }
    }

    /// A streak that grew earns a little more warmth. A streak that reset earns
    /// no reaction at all — no shake, no red, no comment.
    private func playHaptic(streak: Int, previous: Int?) {
        guard streak > 0 else { return }

        if let previous, streak > previous {
            Haptics.commit()
        } else {
            Haptics.soft()
        }
    }

    /// Sleeps, reporting whether the sequence should continue.
    private func sleep(_ milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
