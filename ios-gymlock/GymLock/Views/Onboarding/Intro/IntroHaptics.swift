//
//  IntroHaptics.swift
//  GymLock
//
//  Core Haptics patterns for the chain-break intro. Each pattern is timed to the animation:
//    tap(level:)          taps 1–4: escalating hits + a short "crack" tick (stronger every tap)
//    chainBreak()         5th tap: full-strength snap, decaying rumble, scattered debris ticks
//    land()               V2: the chained logo drops in — deep thud
//    slam()               tagline stomps down — heavy impact + ground rumble
//    notificationStorm()  V2: app icons pop in with badges — rapid light buzzes
//  Falls back to UIKit feedback generators on devices without Core Haptics.
//

import CoreHaptics
import UIKit

@MainActor
final class IntroHaptics {
    static let shared = IntroHaptics()

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {}

    // MARK: lifecycle

    func prepare() {
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true            // never interrupts the user's audio
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    func shutdown() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    // MARK: patterns

    /// Taps 1…4 — each one harder and sharper than the last.
    func tap(level: Int) {
        let l = Float(max(1, min(4, level)))
        let intensity = min(1, 0.62 + 0.12 * (l - 1))       // 0.62 → 0.98
        let sharpness = min(1, 0.50 + 0.12 * (l - 1))
        var events: [CHHapticEvent] = [
            transient(0, intensity, sharpness),
            transient(0.045, intensity * 0.6, 0.95),          // the metal cracking
        ]
        if l >= 3 { events.append(continuous(0, 0.10, intensity * 0.65, 0.2)) }
        if l >= 4 { events.append(transient(0.09, 0.6, 1.0)) }
        play(events) { self.impact(.heavy, intensity) }
    }

    /// 5th tap — the chains snap. Strongest pattern in the intro.
    func chainBreak() {
        let events: [CHHapticEvent] = [
            transient(0, 1.0, 1.0),
            continuous(0, 0.55, 1.0, 0.35),
            transient(0.07, 0.85, 0.9),
            transient(0.13, 0.75, 0.7),
            transient(0.20, 0.60, 0.95),
            transient(0.28, 0.45, 0.6),
            transient(0.37, 0.35, 0.9),
            transient(0.46, 0.25, 0.8),
        ]
        let decay = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [.init(relativeTime: 0, value: 1.0), .init(relativeTime: 0.12, value: 0.75), .init(relativeTime: 0.55, value: 0.0)],
            relativeTime: 0
        )
        play(events, curves: [decay]) {
            self.impact(.rigid, 1.0)
            self.after(0.06) { self.impact(.heavy, 1.0) }
            self.after(0.16) { self.impact(.medium, 0.7) }
        }
    }

    /// Tagline slams into place like a boot stomping the ground.
    func slam() {
        let events: [CHHapticEvent] = [
            transient(0, 1.0, 0.55),
            continuous(0, 0.42, 1.0, 0.1),
            transient(0.06, 0.6, 0.8),
            transient(0.14, 0.45, 0.7),
            transient(0.24, 0.3, 0.8),
        ]
        let rumble = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [.init(relativeTime: 0, value: 1.0), .init(relativeTime: 0.08, value: 0.7), .init(relativeTime: 0.42, value: 0.0)],
            relativeTime: 0
        )
        play(events, curves: [rumble]) {
            self.impact(.heavy, 1.0)
            self.after(0.08) { self.impact(.medium, 0.6) }
        }
    }

    /// V2 — the chained logo drops onto the screen.
    func land() {
        let events: [CHHapticEvent] = [
            transient(0, 1.0, 0.2),
            continuous(0, 0.2, 0.75, 0.1),
        ]
        let decay = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [.init(relativeTime: 0, value: 1.0), .init(relativeTime: 0.2, value: 0.0)],
            relativeTime: 0
        )
        play(events, curves: [decay]) { self.impact(.heavy, 0.9) }
    }

    /// V2 — notifications flooding in.
    func notificationStorm() {
        let times: [TimeInterval] = [0, 0.11, 0.21, 0.34, 0.45, 0.58, 0.70, 0.84]
        let events = times.enumerated().map { i, t in transient(t, 0.38 + 0.04 * Float(i % 3), 0.9) }
        play(events) {
            for (i, t) in times.enumerated() where i % 2 == 0 {
                self.after(t) { self.impact(.light, 0.6) }
            }
        }
    }

    // MARK: helpers

    private func transient(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private func continuous(_ time: TimeInterval, _ duration: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = [], fallback: () -> Void) {
        if supportsHaptics && engine == nil { prepare() }
        guard let engine else { fallback(); return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try engine.start()                       // no-op if running; recovers after interruptions
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }

    private func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            block()
        }
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ intensity: Float) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: CGFloat(intensity))
    }
}
