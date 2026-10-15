import Foundation
import Observation
import SwiftUI

/// The states the streak can be in.
///
/// One enum rather than a set of booleans, because the states are genuinely
/// exclusive and several of them differ only in ways that booleans would blur:
/// an automatic presentation and a manual one look identical but behave
/// completely differently — one closes itself and shows no controls, the other
/// waits for the user.
enum StreakPresentation: Equatable {
    /// Resting: just the capsule in the header.
    case compact
    /// Playing the entrance on its own. No close button, closes itself.
    case autoPresenting
    /// Opened by the user. Has a close button, stays until dismissed.
    case manuallyExpanded
    /// Travelling back into the capsule, from either of the above.
    case collapsing
}

/// Owns the streak presentation and the timing of its entrance.
///
/// The card opens on its own for exactly one reason: the user has just kept
/// the week — reached the week's goal, whatever their plan makes it. That
/// celebration is earned once per week, remembered on disk by the week's
/// Monday, and only ever starts while Home is actually on screen. Reopening
/// the app, backgrounding it, or switching tabs never replays it.
///
/// Kept outside the home view on purpose, so the pending celebration survives
/// a cold launch into Progress and waits for the user's first visit to Home.
@MainActor
@Observable
final class StreakIntroController {
    private(set) var state: StreakPresentation = .compact

    /// Whether the card layers should be visible.
    ///
    /// The layers themselves never leave the hierarchy — see
    /// `TodayHomeView.streakOverlay`. Kept permanently, they always have a
    /// rendered capsule-sized starting point for the expansion to animate
    /// from, and the flame player is already built by the time the user taps.
    /// Held true through the collapse so the journey home is visible, then
    /// dropped, which snaps the header capsule back and pauses the flame.
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

    private var playback: Task<Void, Never>?

    private let defaults: UserDefaults
    private let calendar: Calendar

    /// Monday of the last week whose completion was celebrated on Home.
    static let lastCelebratedWeekStartKey = "gymlock.streak.lastCelebratedWeekStart"
    /// Set once this rule has looked at the streak for the first time, so an
    /// existing user's already-kept week is not mistaken for a new one.
    static let celebrationBaselineKey = "gymlock.streak.celebrationBaselined"
    /// Written by the retired once-per-session entrance; cleared on sight.
    private static let retiredLastSeenStreakKey = "gymlock.home.lastSeenStreak"

    // MARK: - Motion

    /// Quick off the mark, settling with the faintest overshoot. The capsule
    /// should be visibly stretching on the first frame after the tap and land
    /// like liquid finding its shape — not slide into place, and not bounce.
    static let expand: Animation = .spring(response: 0.46, dampingFraction: 0.8)

    /// Home is brisk and fully damped: the capsule's own pulse as it takes the
    /// card back is what gives the landing its life, so the travel itself
    /// should not compete with it.
    static let collapse: Animation = .spring(response: 0.42, dampingFraction: 0.9)

    /// Reduce Motion keeps the same beats but drops the journey.
    static let reducedExpand: Animation = .easeOut(duration: 0.30)
    static let reducedCollapse: Animation = .easeIn(duration: 0.28)

    /// How far into the collapse the capsule reacts. Slightly before the card
    /// lands, so the capsule is already opening as it arrives instead of
    /// twitching afterwards.
    private static let absorbPoint = 0.68

    /// The phases of the automatic entrance, in milliseconds.
    ///
    /// Most of the budget is deliberately spent while the flame is large and
    /// on screen — that is the part worth watching. The travel either side
    /// matches the springs above: long enough to follow, short enough to feel
    /// like a response rather than a sequence.
    struct Timing {
        var settle: Int
        var expandTravel: Int
        var flameMoment: Int
        var hold: Int
        var collapseTravel: Int

        /// ~2.8s standard, ~2.9s with Reduce Motion — the shorter travel is
        /// given back to the hold so the flame still gets its full moment.
        static let standard = Timing(
            settle: 240, expandTravel: 480, flameMoment: 1100, hold: 520, collapseTravel: 440
        )
        static let reducedMotion = Timing(
            settle: 200, expandTravel: 340, flameMoment: 1100, hold: 900, collapseTravel: 340
        )
    }

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        defaults.removeObject(forKey: Self.retiredLastSeenStreakKey)
    }

    /// Monday of the week that has already had its celebration, if any.
    ///
    /// A record of what the interface did, not a second streak calculation:
    /// the engine alone decides whether a week is kept.
    private(set) var lastCelebratedWeekStart: Date? {
        get { defaults.object(forKey: Self.lastCelebratedWeekStartKey) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.lastCelebratedWeekStartKey)
            } else {
                defaults.removeObject(forKey: Self.lastCelebratedWeekStartKey)
            }
        }
    }

    private func hasCelebrated(weekStarting week: Date) -> Bool {
        guard let lastCelebratedWeekStart else { return false }
        return calendar.isDate(lastCelebratedWeekStart, inSameDayAs: week)
    }

    // MARK: - Automatic entrance

    /// Whether the live week has been kept and not yet celebrated.
    ///
    /// Pure: asking never consumes anything. A frozen week that fell short is
    /// not kept, so it is not a celebration.
    func hasPendingCelebration(for streak: StreakSnapshot) -> Bool {
        baselineIfNeeded(streak)
        return streak.isThisWeekKept && !hasCelebrated(weekStarting: streak.liveWeekStart)
    }

    /// Starts the earned celebration if one is pending and Home can show it.
    ///
    /// The week is marked celebrated the moment the presentation is committed
    /// here — not when the app merely learnt about the completion on another
    /// tab, and not at the end of the animation. Returns whether it began.
    @discardableResult
    func presentEarnedCelebrationIfNeeded(
        streak: StreakSnapshot,
        reduceMotion: Bool,
        isHomeVisible: Bool
    ) -> Bool {
        guard hasPendingCelebration(for: streak) else { return false }
        guard !isSuspended, isHomeVisible, state == .compact else { return false }

        lastCelebratedWeekStart = streak.liveWeekStart

        playback?.cancel()
        playback = Task { [weak self] in
            await self?.run(streak: streak.weeks, reduceMotion: reduceMotion)
        }
        return true
    }

    /// Called when a covering flow finishes, so a celebration held back behind
    /// it still gets its turn.
    func resume(streak: StreakSnapshot, reduceMotion: Bool, isHomeVisible: Bool) {
        isSuspended = false
        presentEarnedCelebrationIfNeeded(streak: streak, reduceMotion: reduceMotion, isHomeVisible: isHomeVisible)
    }

    /// First run of this rule on a device: a week that was already kept before
    /// the rule existed counts as seen, so installing the update is never
    /// mistaken for a fresh completion. Completions after this point are
    /// genuinely new and celebrate as normal.
    private func baselineIfNeeded(_ streak: StreakSnapshot) {
        guard !defaults.bool(forKey: Self.celebrationBaselineKey) else { return }
        if lastCelebratedWeekStart == nil, streak.isThisWeekKept {
            lastCelebratedWeekStart = streak.liveWeekStart
        }
        defaults.set(true, forKey: Self.celebrationBaselineKey)
    }

    // MARK: - Manual presentation

    /// Opens the card because the user tapped the capsule.
    ///
    /// Available whether or not the automatic entrance has already run, and it
    /// takes over from one that is still playing — the user asking for it beats
    /// a presentation that was about to close itself.
    ///
    /// One animated write and nothing else. There is no intermediate state, no
    /// sleep, no task between the tap and the expansion: the card's layers are
    /// already rendered at the capsule's geometry, so the first frame SwiftUI
    /// draws after this returns is the capsule already stretching.
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
            playback?.cancel()
            playback = nil
            withAnimation(reduceMotion ? Self.reducedExpand : Self.expand) {
                state = .manuallyExpanded
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
        normalizeImmediately()
    }

    /// A card the user had open before backgrounding is not restored. They
    /// left; coming back to a dimmed screen would be the app deciding what
    /// they wanted. Only a celebration that is still owed can open here, and
    /// only onto a visible Home.
    func sceneBecameActive(streak: StreakSnapshot, reduceMotion: Bool, isHomeVisible: Bool) {
        presentEarnedCelebrationIfNeeded(streak: streak, reduceMotion: reduceMotion, isHomeVisible: isHomeVisible)
    }

    // MARK: - Sequence

    private func run(streak: Int, reduceMotion: Bool) async {
        let timing = reduceMotion ? Timing.reducedMotion : Timing.standard

        // Let the screen settle first, so the card grows out of a header that
        // has already arrived rather than racing it.
        guard await sleep(timing.settle), state == .compact else { return }

        withAnimation(reduceMotion ? Self.reducedExpand : Self.expand) {
            state = .autoPresenting
        }

        // The card has landed and the number has resolved by now.
        guard await sleep(timing.expandTravel) else { return }
        // The card only opens itself for a week just kept: the streak grew.
        if streak > 0 { Haptics.commit() }

        // The part worth watching, then a beat to take it in.
        guard await sleep(timing.flameMoment + timing.hold) else { return }

        // A manual open during the sequence wins; don't yank it closed.
        guard state == .autoPresenting else { return }
        collapse(reduceMotion: reduceMotion, userInitiated: false)
    }

    /// Runs the shared collapse, hands the capsule its cue, and hides the
    /// layers once the card has finished travelling.
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
