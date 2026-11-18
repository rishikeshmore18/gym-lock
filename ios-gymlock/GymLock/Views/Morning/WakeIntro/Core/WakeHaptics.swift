//
//  WakeHaptics.swift
//  GymLock · the "I'm up" wake page
//
//  Plays `WakePlan.haptics` on the same clock as the visuals. The page calls `tick(t)` once per drawn
//  frame with the `t` that frame is drawn for, so the tap lands on the frame where the line lands
//  (the web player fires on the first frame whose clock crosses the cue; this does the same).
//
//    heavy  = the commitment         UIImpactFeedbackGenerator(.heavy),  intensity 1.0
//    medium = the card lands         UIImpactFeedbackGenerator(.medium), intensity 0.8
//    soft   = every other chapter    UIImpactFeedbackGenerator(.soft),   intensity 0.6
//
//  Rules:
//    - Generators are prepared about 0.15 s before their cue, so the Taptic Engine is awake in time.
//    - A cue fires once, ever (one per chapter by construction, and a fired set guards it).
//    - Several cues crossed in one frame play as the strongest one only.
//    - A jump of the clock (tap to skip, a return from the background) is told to `resync`, which
//      drops what was jumped over. A frame hitch is handled by `tick` itself: a cue crossed more than
//      `staleWindow` (0.25 s) before the frame is dropped, a fresher one still plays.
//    - The first `tick` or `resync` also wakes the generator of a cue due within `lookahead`, so the
//      Reduce Motion cue (0.07 s in) is prepared before it fires.
//    - `stop()` silences it for good once the page has gone; nothing fires after the view disappears.
//    - The app's haptics switch (Profile > Preferences, `HeroHapticPlayer.isEnabled`,
//      "gymlock.hero.haptics") is honoured; the system switch is honoured by UIKit itself.
//
//  Why not `Haptics` (Utilities/Haptics.swift) directly: it has no heavy impact, no intensity on
//  medium or soft, and no prepare for those generators, and all three are needed for the timing and
//  the weights above. The app's switch is read through the same object the hero card uses.
//
//  Depends on: UIKit, CoreHaptics (capability check), WakeStage.swift (WakeHaptic, WakePlan),
//  Views/Home/Hero/HeroHaptics.swift (HeroHapticPlayer, the app-level switch).
//

import CoreHaptics
import UIKit

@MainActor
final class WakeHaptics {
    /// How far ahead a generator is woken.
    static let lookahead: Double = 0.15
    /// A cue that is already this late when its frame is drawn is stale: the clock hitched or jumped
    /// over it. It is dropped, never played late.
    static let staleWindow: Double = 0.25

    private let cues: [WakeHaptic]
    private var fired: Set<Int> = []
    private var lastT: Double?
    private var isActive = true

    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    init(plan: WakePlan) {
        cues = plan.haptics.sorted { $0.t < $1.t }
    }

    /// The app's switch, read live so a change in Preferences applies at once.
    private var isEnabled: Bool { supportsHaptics && HeroHapticPlayer.shared.isEnabled }

    /// Call once per drawn frame with the clock value the frame is drawn for. Safe to call again with
    /// the same `t` (a body evaluated twice for one frame): nothing crosses, nothing fires twice.
    func tick(_ t: Double) {
        guard isActive else { return }
        guard let last = lastT else {
            lastT = t
            prepareUpcoming(after: t)
            return
        }
        defer { lastT = t }
        // Paused (t == last), or the clock moved back: nothing crossed.
        guard t > last else { return }

        var strongest: WakeHapticKind?
        for (index, cue) in cues.enumerated() where cue.t > last && cue.t <= t && !fired.contains(index) {
            fired.insert(index)
            // Stale: the frame that should have carried this cue came more than a quarter second ago.
            if t - cue.t > Self.staleWindow { continue }
            if let current = strongest, current.rank >= cue.kind.rank { continue }
            strongest = cue.kind
        }

        prepareUpcoming(after: t)
        if let strongest { play(strongest) }
    }

    /// The clock jumped (skip, resume): continue from `t` without firing what was passed.
    func resync(to t: Double) {
        if let last = lastT, t > last { markCrossed(after: last, upTo: t) }
        lastT = t
        prepareUpcoming(after: t)
    }

    /// The page left the screen. Silent from here on.
    func stop() {
        isActive = false
    }

    /// The page is back on screen. The caller resyncs the clock first, so nothing stale fires.
    func resume(at t: Double) {
        resync(to: t)
        isActive = true
    }

    // MARK: Private

    private func markCrossed(after a: Double, upTo b: Double) {
        for (index, cue) in cues.enumerated() where cue.t > a && cue.t <= b {
            fired.insert(index)
        }
    }

    private func prepareUpcoming(after t: Double) {
        guard isEnabled else { return }
        for (index, cue) in cues.enumerated() where cue.t > t && !fired.contains(index) {
            if cue.t - t > Self.lookahead { break }
            generator(for: cue.kind).prepare()
        }
    }

    private func play(_ kind: WakeHapticKind) {
        guard isEnabled else { return }
        switch kind {
        case .heavy: heavy.impactOccurred(intensity: 1.0)
        case .medium: medium.impactOccurred(intensity: 0.8)
        case .soft: soft.impactOccurred(intensity: 0.6)
        }
    }

    private func generator(for kind: WakeHapticKind) -> UIImpactFeedbackGenerator {
        switch kind {
        case .heavy: heavy
        case .medium: medium
        case .soft: soft
        }
    }
}
