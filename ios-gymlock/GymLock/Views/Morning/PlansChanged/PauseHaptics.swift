//
//  PauseHaptics.swift
//  GymLock · the "plans changed" pause
//
//  The pause's taps, on the same frame as what they mark:
//
//    light   a printer tick (rate-limited, so a fast row reads as a buzz, not a stutter)
//    soft    a line or beat lands
//    rigid   the choice changes
//    medium  the 30 seconds are up
//    heavy   the user commits (i'm going, start, can't today)
//
//  Looks are views evaluated every frame, so they never fire directly from `body`: they call
//  `cue(_:_:)` with a stable id, which plays once per id for the life of the screen. A jump of the
//  clock therefore never replays what was already felt.
//
//  The app's haptics switch (Profile > Preferences, HeroHapticPlayer.isEnabled) is honoured; the
//  system switch is honoured by UIKit itself.
//

import CoreHaptics
import UIKit

@MainActor
final class PauseHaptics {
    enum Kind {
        case light, soft, rigid, medium, heavy
    }

    /// Printer ticks closer than this merge into the previous one.
    static let lightInterval: CFTimeInterval = 0.07

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var fired: Set<String> = []
    private var lastLight: CFTimeInterval = -1
    private var isActive = true

    private var isEnabled: Bool { isActive && supportsHaptics && HeroHapticPlayer.shared.isEnabled }

    func prepare() {
        guard isEnabled else { return }
        [light, soft, rigid, medium, heavy].forEach { $0.prepare() }
    }

    /// Plays `kind` once for `id`. Safe to call on every frame.
    func cue(_ id: String, _ kind: Kind) {
        guard !fired.contains(id) else { return }
        fired.insert(id)
        play(kind)
    }

    /// Plays at once (taps the user made).
    func play(_ kind: Kind) {
        guard isEnabled else { return }
        switch kind {
        case .light:
            let now = CACurrentMediaTime()
            guard now - lastLight >= Self.lightInterval else { return }
            lastLight = now
            light.impactOccurred(intensity: 0.55)
            light.prepare()
        case .soft:
            soft.impactOccurred(intensity: 0.6)
            soft.prepare()
        case .rigid:
            rigid.impactOccurred(intensity: 0.7)
            rigid.prepare()
        case .medium:
            medium.impactOccurred(intensity: 0.8)
            medium.prepare()
        case .heavy:
            heavy.impactOccurred(intensity: 1)
        }
    }

    /// Silences it for good once the screen has gone.
    func stop() { isActive = false }
}
