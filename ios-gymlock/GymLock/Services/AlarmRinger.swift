import AVFoundation
import CoreHaptics
import Observation
import UIKit

/// The sound the user actually wakes up to.
///
/// Deliberately not `AlarmSoundPlayer`. That class is a six-second preview with
/// `.mixWithOthers`, and the two jobs are opposites: a preview politely shares
/// the audio session and stops itself, while an alarm interrupts whatever is
/// playing and keeps going until a human does something about it.
///
/// Three decisions worth stating.
///
/// **It escalates.** Volume starts at a quarter and reaches full over
/// forty-five seconds. Nobody should be detonated awake at maximum volume by an
/// app whose whole voice is quiet, and a sound that grows is harder to sleep
/// through than one that is simply loud.
///
/// **It stops escalating the moment the user touches anything.** Being awake is
/// the goal; once that is evident the app has no business getting louder.
///
/// **It has a ceiling.** Ten minutes, then silence, so a phone left in an empty
/// flat does not ring all day.
@Observable
@MainActor
final class AlarmRinger {
    private(set) var isRinging = false
    /// 0...1, driving the ring-level visual on the alarm screen.
    private(set) var intensity: Double = 0
    /// The track actually playing, which is not always the one requested: a
    /// deleted custom song falls back rather than ringing silence.
    private(set) var playingSound: AlarmSound?
    /// True when the chosen track was missing and a fallback is ringing.
    private(set) var isPlayingFallback = false

    /// Where the ramp starts. Audible, not alarming.
    static let startVolume: Float = 0.25
    /// How long it takes to reach full.
    static let escalationDuration: TimeInterval = 45
    /// Each `setVolume(_:fadeDuration:)` covers this much of the ramp.
    static let escalationStep: TimeInterval = 5
    /// The hard stop.
    static let maximumRingDuration: TimeInterval = 10 * 60

    private var player: AVAudioPlayer?
    private var escalation: Task<Void, Never>?
    private var ceiling: Task<Void, Never>?
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var fallbackHaptics: Task<Void, Never>?
    /// Frozen by the first interaction, so the ramp stops where it was.
    private var isEscalationFrozen = false

    // MARK: - Ringing

    /// Starts the alarm with the user's track, or the best available substitute.
    ///
    /// `profile` rather than a bare sound so the fallback chain can see the
    /// custom file name and the previously chosen bundled track.
    func start(for profile: OnboardingProfile) {
        guard let resolution = AlarmTrackResolver.resolve(
            sound: profile.alarmSound,
            customFileName: profile.effectiveCustomSoundFile,
            previousBundled: profile.previousBundledSound
        ) else { return }

        start(url: resolution.url, sound: resolution.sound, isFallback: resolution.isFallback)
    }

    /// The direct form, for the debug panel and for callers that already
    /// resolved a file.
    func start(url: URL, sound: AlarmSound, isFallback: Bool = false) {
        guard !isRinging else { return }

        do {
            // No `.mixWithOthers`: an alarm interrupts. `.playback` is also what
            // makes this ring on a phone left on silent, because that category
            // ignores the ringer switch.
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.isMeteringEnabled = true
            player.numberOfLoops = -1
            player.volume = Self.startVolume
            player.prepareToPlay()
            player.play()

            self.player = player
            isRinging = true
            isEscalationFrozen = false
            playingSound = sound
            isPlayingFallback = isFallback
            intensity = Double(Self.startVolume)

            startEscalating()
            startHaptics()
            startCeiling()
        } catch {
            // A ringer that cannot open its own audio session is a real
            // failure, but not one worth crashing the morning over: the
            // notification or system alarm already woke the user, and the
            // screen still shows the decision.
            stop()
        }
    }

    func stop() {
        escalation?.cancel()
        escalation = nil
        ceiling?.cancel()
        ceiling = nil

        stopHaptics()

        player?.stop()
        player = nil
        isRinging = false
        intensity = 0
        playingSound = nil
        isPlayingFallback = false
        isEscalationFrozen = false

        // Letting whatever was playing before resume, rather than leaving the
        // session claimed by an alarm that has finished.
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    /// Freezes the volume where it is.
    ///
    /// Called on any interaction with the alarm screen. The user is plainly
    /// awake, so continuing to get louder would only be punishment.
    func freezeEscalation() {
        guard isRinging, !isEscalationFrozen else { return }
        isEscalationFrozen = true
        escalation?.cancel()
        escalation = nil
    }

    /// Jumps the ramp to full, for the debug panel.
    func escalateToFull() {
        guard isRinging else { return }
        escalation?.cancel()
        escalation = nil
        player?.setVolume(1, fadeDuration: 0.2)
        intensity = 1
        updateHapticIntensity(1)
    }

    // MARK: - The ramp

    private func startEscalating() {
        escalation = Task { [weak self] in
            guard let self else { return }

            let steps = Int(Self.escalationDuration / Self.escalationStep)
            let span = 1 - Self.startVolume

            for step in 1...max(steps, 1) {
                guard !Task.isCancelled else { return }

                let target = Self.startVolume + span * Float(step) / Float(steps)
                player?.setVolume(target, fadeDuration: Self.escalationStep)

                try? await Task.sleep(for: .seconds(Self.escalationStep))
                guard !Task.isCancelled else { return }

                intensity = Double(target)
                updateHapticIntensity(Double(target))
            }
        }
    }

    /// The hard ceiling. A phone ringing into an empty room stops eventually.
    private func startCeiling() {
        ceiling = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumRingDuration))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    // MARK: - Vibration

    /// A repeating pulse whose strength tracks the volume ramp.
    ///
    /// Haptics ignore the silent switch entirely, so this is the part that
    /// works on a phone face-down on a nightstand with the ringer off.
    private func startHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine()
        else {
            startFallbackHaptics()
            return
        }

        engine.isAutoShutdownEnabled = false
        // An alarm outliving an audio-session interruption is the entire point,
        // so the engine restarts itself rather than going quiet.
        engine.resetHandler = { [weak engine] in try? engine?.start() }

        do {
            try engine.start()

            let pattern = try CHHapticPattern(events: pulseEvents(), parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)

            hapticEngine = engine
            hapticPlayer = player
            updateHapticIntensity(Double(Self.startVolume))
        } catch {
            hapticEngine = nil
            hapticPlayer = nil
            startFallbackHaptics()
        }
    }

    /// Two knocks and a gap: the shape of a phone buzzing on wood, rather than
    /// a continuous rumble that the hand stops noticing within seconds.
    private func pulseEvents() -> [CHHapticEvent] {
        func transient(at time: Double, strength: Float) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: strength),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
                ],
                relativeTime: time
            )
        }

        return [
            transient(at: 0, strength: 1),
            transient(at: 0.16, strength: 0.85),
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
                ],
                relativeTime: 0.32,
                duration: 0.45
            ),
            // The silence is deliberate: a pause is what makes the next pulse
            // register as a new demand rather than as background noise.
            transient(at: 1.5, strength: 0.01),
        ]
    }

    /// Scales the running pattern to match the volume ramp.
    private func updateHapticIntensity(_ value: Double) {
        guard let hapticPlayer else { return }

        let parameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: Float(max(0.3, value)),
            relativeTime: 0
        )
        try? hapticPlayer.sendParameters([parameter], atTime: CHHapticTimeImmediate)
    }

    /// Where Core Haptics is unavailable, the same rhythm on the impact
    /// generator. Coarser, but a phone that buzzes is the requirement.
    private func startFallbackHaptics() {
        fallbackHaptics = Task { [weak self] in
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()

            while !Task.isCancelled {
                guard let self, self.isRinging else { return }
                generator.impactOccurred(intensity: CGFloat(max(0.4, self.intensity)))
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                generator.impactOccurred(intensity: CGFloat(max(0.3, self.intensity * 0.85)))
                try? await Task.sleep(for: .milliseconds(1340))
            }
        }
    }

    private func stopHaptics() {
        fallbackHaptics?.cancel()
        fallbackHaptics = nil

        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticPlayer = nil

        hapticEngine?.stop()
        hapticEngine = nil
    }
}
