import Foundation
import Observation
import SwiftUI

/// Owns the timing of the streak entrance.
///
/// Kept outside the home view on purpose. The rule is "once per foreground
/// session", so the thing that remembers whether it has played must outlive
/// every tab switch and every scroll — if this lived in the view it would fire
/// again every time the user came back to Home, which is exactly the gimmick
/// this is meant not to be.
@MainActor
@Observable
final class StreakIntroController {
    /// Drives the morph. True while the card is out.
    private(set) var isExpanded = false

    /// Whether the card should exist in the hierarchy at all.
    ///
    /// Held true through the collapse so the animation has something to
    /// animate, then dropped — which is what unloads the Lottie player rather
    /// than leaving it rendering behind the header.
    private(set) var isMounted = false

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

    // Motion. High damping throughout: this is a soft expansion, not a bounce.
    static let expand: Animation = .spring(response: 0.42, dampingFraction: 0.92)
    static let collapse: Animation = .spring(response: 0.40, dampingFraction: 0.94)
    static let reducedMotion: Animation = .easeInOut(duration: 0.30)

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

    /// Plays the entrance, if it hasn't already run this session.
    func play(streak: Int, reduceMotion: Bool) {
        guard !isSuspended, !hasPlayedThisSession else { return }
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

    /// Ends the animation cleanly, wherever it had got to.
    ///
    /// Used when the user leaves for another tab or backgrounds the app. The
    /// streak always ends up back in its compact resting state — never two
    /// numbers, never a missing chip, never a half-finished morph.
    func cancel() {
        playback?.cancel()
        playback = nil

        guard isMounted || isExpanded else { return }
        withAnimation(Self.collapse) { isExpanded = false }
        isMounted = false
    }

    func sceneLeftForeground() {
        leftForegroundAt = Date()
        cancel()
    }

    func sceneBecameActive(streak: Int, reduceMotion: Bool, isHomeVisible: Bool) {
        if let leftForegroundAt, Date().timeIntervalSince(leftForegroundAt) > Self.sessionGap {
            hasPlayedThisSession = false
        }
        leftForegroundAt = nil

        guard isHomeVisible else { return }
        play(streak: streak, reduceMotion: reduceMotion)
    }

    // MARK: - Sequence

    private func run(streak: Int, previous: Int?, reduceMotion: Bool) async {
        let expandAnimation = reduceMotion ? Self.reducedMotion : Self.expand
        let collapseAnimation = reduceMotion ? Self.reducedMotion : Self.collapse

        // Let the screen settle first, so the card grows out of a header that
        // has already arrived rather than racing it.
        guard await sleep(milliseconds: reduceMotion ? 160 : 260) else { return }

        isMounted = true
        withAnimation(expandAnimation) { isExpanded = true }

        // The number has resolved by now.
        guard await sleep(milliseconds: reduceMotion ? 200 : 430) else { return }
        playHaptic(streak: streak, previous: previous)

        // Brief hold, then away. Nobody should be waiting on this.
        guard await sleep(milliseconds: reduceMotion ? 640 : 820) else { return }

        withAnimation(collapseAnimation) { isExpanded = false }

        // Unmount only once the collapse has finished travelling.
        guard await sleep(milliseconds: 460) else { return }
        isMounted = false
        playback = nil
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
    private func sleep(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
