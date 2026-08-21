import CoreHaptics
import UIKit

/// Small wrapper around the feedback engines so views stay declarative.
///
/// The selection generator is kept alive and pre-warmed because the word reel
/// ticks it many times in quick succession, and a cold generator adds latency
/// that would break the picker-wheel illusion.
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// One iOS picker-style tick. Call only when the selected item actually
    /// changes — never per animation frame.
    static func selection() {
        selectionGenerator.selectionChanged()
    }

    /// Pre-warms the selection generator so the first tick is not late.
    static func prepareSelection() {
        selectionGenerator.prepare()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func commit() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Breaking glass

    private static var engine: CHHapticEngine?
    private static var glassPlayer: CHHapticPatternPlayer?
    private static var isEngineUnsupported = false

    /// Spins the haptic engine up ahead of time.
    ///
    /// Starting an engine takes long enough to be felt, and the break has to
    /// land on the same frame as the user's finger leaving the screen. This is
    /// called as soon as the break becomes possible, not when it happens.
    static func prepareGlassBreak() {
        _ = runningEngine()
    }

    /// The full break, as one continuous piece of choreography.
    ///
    /// A single thud is wrong for this: breaking glass is one hard, bright crack
    /// followed by an irregular scatter that thins out as the pieces come to
    /// rest. The pattern below is timed against the animation — the crack lands
    /// with the fracture, and the scatter decays over the fall.
    static func glassBreak() {
        guard let engine = runningEngine() else {
            Task { await playFallbackGlassBreak() }
            return
        }

        do {
            let pattern = try CHHapticPattern(events: glassBreakEvents(), parameters: [])
            let player = try engine.makePlayer(with: pattern)
            // Held for the duration of playback: a released player stops.
            glassPlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            Task { await playFallbackGlassBreak() }
        }
    }

    /// The scatter, as `(seconds, strength)` pairs. Deliberately uneven — evenly
    /// spaced taps read as a machine, not as falling debris.
    private static let glassScatter: [(time: Double, strength: Double)] = [
        (0.17, 0.58), (0.24, 0.38), (0.30, 0.52), (0.39, 0.31),
        (0.47, 0.43), (0.57, 0.25), (0.68, 0.30), (0.80, 0.18), (0.94, 0.12),
    ]

    private static func glassBreakEvents() -> [CHHapticEvent] {
        func transient(at time: Double, strength: Double, sharpness: Double) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(strength)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
                ],
                relativeTime: time
            )
        }

        var events: [CHHapticEvent] = [
            // The crack itself: as hard and as bright as the hardware allows.
            transient(at: 0, strength: 1, sharpness: 1),
            // The pane tearing open underneath it — very short, or it turns into
            // a rumble and stops sounding like glass.
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85),
                ],
                relativeTime: 0.012,
                duration: 0.1
            ),
        ]

        events.append(
            contentsOf: glassScatter.map { piece in
                transient(
                    at: piece.time,
                    strength: piece.strength,
                    // Smaller pieces read as sharper, lighter clicks.
                    sharpness: 0.95 - piece.strength * 0.25
                )
            }
        )

        return events
    }

    /// Where Core Haptics is unavailable, the same shape played on the standard
    /// impact generators. Coarser, but it still reads as a crack and a scatter
    /// rather than a single bump.
    private static func playFallbackGlassBreak() async {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)

        let debris = UIImpactFeedbackGenerator(style: .light)
        debris.prepare()

        var elapsed: Double = 0
        for piece in glassScatter {
            let wait = piece.time - elapsed
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
            }
            elapsed = piece.time
            debris.impactOccurred(intensity: CGFloat(piece.strength))
        }
    }

    /// The shared engine, started on demand.
    ///
    /// `isAutoShutdownEnabled` lets the engine idle itself out to save power;
    /// calling `start()` on an already-running engine is a no-op, so this is
    /// also the restart path and no reset handlers are needed.
    private static func runningEngine() -> CHHapticEngine? {
        guard !isEngineUnsupported,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics
        else {
            isEngineUnsupported = true
            return nil
        }

        if let engine {
            try? engine.start()
            return engine
        }

        guard let created = try? CHHapticEngine() else {
            isEngineUnsupported = true
            return nil
        }

        created.isAutoShutdownEnabled = true
        try? created.start()
        engine = created
        return created
    }
}
