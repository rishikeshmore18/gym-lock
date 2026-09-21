import SwiftUI

/// Reuses the tracks and the import path already built in onboarding.
///
/// Deliberately thin: there is exactly one alarm-audio system in this app, and
/// this is a second door into it rather than a second copy of it. Extracted
/// from `MorningAlarmPlanView` so the alarm settings screen opens the
/// identical picker rather than a drifting copy.
struct AlarmSoundPickerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(AlarmSoundPlayer.self) private var player: AlarmSoundPlayer?
    @Environment(\.dismiss) private var dismiss

    @State private var isTrimming = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(AlarmSound.bundled) { sound in
                            row(for: sound)
                        }

                        if hasCustomSong {
                            row(for: .ownSong)
                        }

                        ownSongRow
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("alarm sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") {
                        player?.stop()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
            .onDisappear { player?.stop() }
            .fullScreenCover(isPresented: $isTrimming) {
                SongTrimmerView()
            }
        }
    }

    /// Whether there is a usable track on disk right now, rather than just a
    /// name in the profile: a deleted file must not be offered as a choice.
    private var hasCustomSong: Bool {
        AlarmTrackResolver.customSongExists(named: store.profile.effectiveCustomSoundFile)
    }

    /// The way in to the trimmer, which is also the way to replace a song
    /// that is already chosen.
    private var ownSongRow: some View {
        Button {
            Haptics.tap()
            player?.stop()
            isTrimming = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 38, height: 38)
                    .background(Theme.surfaceMuted, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hasCustomSong ? "trim a different song" : "use my own song")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("pick 28 seconds of any track you own")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }

    private func row(for sound: AlarmSound) -> some View {
        let isSelected = store.profile.alarmSound == sound
        let isPlaying = player?.playing == sound

        return Button {
            // Remembered before the switch, so a custom song that later goes
            // missing falls back to a track the user actually picked.
            if sound == .ownSong, store.profile.alarmSound != .ownSong {
                store.profile.previousBundledSound = store.profile.alarmSound
            }
            store.profile.alarmSound = sound
            Haptics.tap()
            player?.toggle(sound, profile: store.profile)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sound == .ownSong ? store.profile.alarmSoundLabel : sound.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(sound.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isPlaying {
                    MiniWaveform(level: player?.level ?? 0)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.border)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }
}
