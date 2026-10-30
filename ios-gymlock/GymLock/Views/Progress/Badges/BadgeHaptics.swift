//
//  BadgeHaptics.swift
//  GymLock — Badges
//
//  Core Haptics timed to the rank-up timeline (30-fps units → seconds):
//    f 4      badge appears            light tap
//    f 14–40  charge                   rising rumble (stronger for higher tiers)
//    f 38–60  spin                     a tick every time the badge turns edge-on
//    f 60     impact                   full-strength hit + decaying rumble
//    f 76     name slams in            heavy thud
//    f 92     tier chip                light tick
//  plus a soft double-tap when the badge lands in its slot.
//

import CoreHaptics
import UIKit

@MainActor
final class BadgeHaptics {
    static let shared = BadgeHaptics()
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {}

    private func prepare() {
        guard supported, engine == nil else { return }
        do {
            let e = try CHHapticEngine()
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = true
            e.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            try e.start()
            engine = e
        } catch { engine = nil }
    }

    func playRankUp(tier: BadgeTier, rate: Double = 1) {
        prepare()
        let I = Float(0.45 + 0.55 * Double(tier.rank) / 9)
        let s = 1.0 / 30.0 / max(0.05, rate)          // frames → seconds
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []

        events.append(transient(4 * s, 0.35, 0.5))
        // charge rumble
        let chargeStart = 14 * s, chargeLen = 26 * s
        events.append(continuous(chargeStart, chargeLen, 1.0, 0.35))
        curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: chargeStart, value: 0.12),
            .init(relativeTime: chargeStart + chargeLen * 0.7, value: 0.45 * I + 0.15),
            .init(relativeTime: chargeStart + chargeLen, value: 0.7 * I + 0.2),
        ], relativeTime: 0))
        // spin: ticks when the badge is edge-on (eased progress = 1/8, 3/8, 5/8, 7/8)
        for e in [0.125, 0.375, 0.625, 0.875] {
            let u = e < 0.5 ? cbrt(e / 4) : 1 - cbrt(2 * (1 - e)) / 2
            events.append(transient((38 + 22 * u) * s, 0.5 + 0.2 * Float(e), 0.9))
        }
        // impact
        let impact = 60 * s
        events.append(transient(impact, 1.0, 0.9))
        events.append(continuous(impact, 0.45 / max(0.05, rate), 1.0, 0.3))
        curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: impact, value: max(0.7, I)),
            .init(relativeTime: impact + 0.1 / max(0.05, rate), value: 0.6 * max(0.7, I)),
            .init(relativeTime: impact + 0.45 / max(0.05, rate), value: 0),
        ], relativeTime: 0))
        events.append(transient(impact + 0.07 / max(0.05, rate), 0.7, 0.8))
        events.append(transient(impact + 0.15 / max(0.05, rate), 0.5, 0.9))
        // name slam
        events.append(transient(76 * s, 0.85, 0.5))
        events.append(continuous(76 * s, 0.12 / max(0.05, rate), 0.5, 0.15))
        // tier chip
        events.append(transient(92 * s, 0.4, 0.95))

        play(events, curves) {
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.prepare()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(impact * 1_000_000_000))
                g.impactOccurred(intensity: 1)
            }
        }
    }

    /// Badge settles into its slot.
    func playLand() {
        prepare()
        play([transient(0, 0.7, 0.6), transient(0.08, 0.45, 0.8)], []) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
    }

    // MARK: helpers

    private func play(_ events: [CHHapticEvent], _ curves: [CHHapticParameterCurve], fallback: () -> Void) {
        guard let engine else { fallback(); return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            try? player?.stop(atTime: CHHapticTimeImmediate)
            let p = try engine.makePlayer(with: pattern)
            try engine.start()
            try p.start(atTime: CHHapticTimeImmediate)
            player = p
        } catch { fallback() }
    }

    private func transient(_ t: TimeInterval, _ i: Float, _ sh: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sh),
        ], relativeTime: t)
    }

    private func continuous(_ t: TimeInterval, _ d: TimeInterval, _ i: Float, _ sh: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sh),
        ], relativeTime: t, duration: d)
    }
}
