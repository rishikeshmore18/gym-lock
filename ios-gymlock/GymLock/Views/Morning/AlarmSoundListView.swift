import SwiftUI

/// The Sound page, after Apple's own in Edit Alarm: Haptics at the top, the
/// tracks in one grouped card with a checkmark column on the leading edge,
/// and a separate card at the foot. Where Apple puts "None", this puts the
/// way in to choosing your own song, because an alarm that makes no sound
/// is not something this app offers.
///
/// Tapping a track chooses it *and* plays it, as Apple's list does, so there
/// is no separate preview control to find. Tapping the playing track again
/// stops it.
struct AlarmSoundListView: View {
    @Environment(AppStore.self) private var store
    @Environment(AlarmSoundPlayer.self) private var player: AlarmSoundPlayer?

    @State private var isTrimming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AlarmGroupCard {
                    NavigationLink(value: AlarmOptionRoute.haptics) {
                        AlarmValueRow(title: "haptics", value: store.plan.alarmHaptic.label)
                    }
                    .buttonStyle(AlarmRowButtonStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    AlarmSectionHeader(text: "tracks")

                    AlarmGroupCard {
                        ForEach(Array(tracks.enumerated()), id: \.element) { index, sound in
                            if index > 0 { AlarmRowDivider(inset: Self.checkColumn) }
                            trackRow(sound)
                        }
                    }
                }
                .padding(.top, 6)

                AlarmGroupCard {
                    Button {
                        Haptics.tap()
                        player?.stop()
                        isTrimming = true
                    } label: {
                        AlarmValueRow(
                            title: hasCustomSong ? "choose a different song" : "choose your own song",
                            value: ""
                        )
                    }
                    .buttonStyle(AlarmRowButtonStyle())
                }
                .padding(.top, 6)

                Text("tap a track to hear it. your own song plays 28 seconds of any track you own.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(Theme.ink)
        .onDisappear { player?.stop() }
        .fullScreenCover(isPresented: $isTrimming) {
            SongTrimmerView()
        }
    }

    /// Width of the leading checkmark column, so names line up whether or
    /// not their row is the chosen one, and the dividers start where the
    /// names do, as in Apple's list.
    private static let checkColumn: CGFloat = 30

    /// The bundled tracks, then the user's own song if one is really on disk.
    private var tracks: [AlarmSound] {
        hasCustomSong ? AlarmSound.bundled + [.ownSong] : AlarmSound.bundled
    }

    /// Whether there is a usable track on disk right now, rather than just a
    /// name in the profile: a deleted file must not be offered as a choice.
    private var hasCustomSong: Bool {
        AlarmTrackResolver.customSongExists(named: store.profile.effectiveCustomSoundFile)
    }

    private func trackRow(_ sound: AlarmSound) -> some View {
        let isSelected = store.profile.alarmSound == sound
        let isPlaying = player?.playing == sound

        return Button {
            select(sound)
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.5)
                    .frame(width: Self.checkColumn, alignment: .leading)

                Text(sound == .ownSong ? store.profile.alarmSoundLabel : sound.label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if isPlaying {
                    MiniWaveform(level: player?.level ?? 0, tint: Theme.inkTertiary)
                        .transition(.opacity)
                } else if sound == .ownSong {
                    Text("your song")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 50)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isSelected)
            .animation(Theme.stateChange, value: isPlaying)
        }
        .buttonStyle(AlarmRowButtonStyle())
        .accessibilityLabel(sound == .ownSong ? store.profile.alarmSoundLabel : sound.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Plays a preview")
    }

    private func select(_ sound: AlarmSound) {
        // Remembered before the switch, so a custom song that later goes
        // missing falls back to a track the user actually picked.
        if sound == .ownSong, store.profile.alarmSound != .ownSong {
            store.profile.previousBundledSound = store.profile.alarmSound
        }
        if store.profile.alarmSound != sound {
            Haptics.selection()
            store.profile.alarmSound = sound
        } else {
            Haptics.tap()
        }
        player?.toggle(sound, profile: store.profile)
    }
}
