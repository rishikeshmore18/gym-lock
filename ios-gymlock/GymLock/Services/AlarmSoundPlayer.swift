import AVFoundation
import Observation

/// Previews the bundled alarm tracks.
///
/// Only one preview may play at a time — starting a new one stops whatever was
/// running — and playback fades in rather than starting at full volume, because
/// an alarm sound arriving instantly at full level while the user is choosing
/// between them is genuinely unpleasant.
@Observable
@MainActor
final class AlarmSoundPlayer {
    /// The track currently previewing, if any.
    private(set) var playing: AlarmSound?
    /// Rough 0...1 loudness, driving the waveform next to the playing row.
    private(set) var level: Double = 0

    private var player: AVAudioPlayer?
    private var meter: Task<Void, Never>?

    /// How long a preview runs before stopping itself.
    private static let previewDuration: Double = 6

    func toggle(_ sound: AlarmSound) {
        if playing == sound {
            stop()
        } else {
            play(sound)
        }
    }

    func play(_ sound: AlarmSound) {
        stop()

        guard let name = sound.resourceName,
              let url = Bundle.main.url(forResource: name, withExtension: "mp3")
        else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.isMeteringEnabled = true
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            player.setVolume(0.85, fadeDuration: 0.35)

            self.player = player
            playing = sound
            meter = Task { await runMeter() }
        } catch {
            // A preview that cannot start is not worth interrupting the user
            // over; the row simply stays unplayed.
            playing = nil
        }
    }

    func stop() {
        meter?.cancel()
        meter = nil

        player?.setVolume(0, fadeDuration: 0.18)
        let fading = player
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            fading?.stop()
        }

        player = nil
        playing = nil
        level = 0
    }

    /// Samples the player's own output so the waveform reflects the actual
    /// track rather than a decorative loop.
    private func runMeter() async {
        let deadline = Date().addingTimeInterval(Self.previewDuration)

        while !Task.isCancelled, let player, player.isPlaying {
            player.updateMeters()

            // Average power is in decibels, roughly -60 (silent) to 0 (peak).
            let decibels = Double(player.averagePower(forChannel: 0))
            let normalised = max(0, min(1, (decibels + 45) / 45))
            level = normalised

            if Date() >= deadline {
                stop()
                return
            }

            try? await Task.sleep(for: .milliseconds(70))
        }
    }
}
