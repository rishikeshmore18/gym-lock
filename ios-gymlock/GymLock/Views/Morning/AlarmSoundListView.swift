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
///
/// Motion, and why:
/// - The checkmark is one mark that glides from the old row to the new one,
///   rather than one fading out while another fades in. The eye follows the
///   choice moving, which is what actually happened.
/// - The playing track's name lifts to full weight and a live level meter
///   grows in beside it, so which row is sounding is never a guess.
/// - Single-row cards are Liquid Glass buttons that give under the finger.
struct AlarmSoundListView: View {
    @Environment(AppStore.self) private var store
    @Environment(AlarmSoundPlayer.self) private var player: AlarmSoundPlayer?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var checkSpace

    var body: some View {
        AlarmSubpage(title: "Sound") {
            NavigationLink(value: AlarmOptionRoute.haptics) {
                AlarmValueRow(title: "haptics", value: store.plan.alarmHaptic.label)
                    .animation(Theme.stateChange, value: store.plan.alarmHaptic)
            }
            .buttonStyle(AlarmGlassCardButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { Haptics.press(intensity: 0.4) })

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

            NavigationLink(value: AlarmOptionRoute.song) {
                AlarmValueRow(
                    title: hasCustomSong ? "choose a different song" : "choose your own song",
                    value: ""
                )
            }
            .buttonStyle(AlarmGlassCardButtonStyle())
            .simultaneousGesture(TapGesture().onEnded {
                Haptics.press(intensity: 0.4)
                player?.stop()
            })
            .padding(.top, 6)

            Text("tap a track to hear it. your own song plays 28 seconds of any track you own.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
        .onAppear { Haptics.preparePress() }
        .onDisappear { player?.stop() }
    }

    /// Width of the leading checkmark column, so names line up whether or
    /// not their row is the chosen one, and the dividers start where the
    /// names do, as in Apple's list.
    private static let checkColumn: CGFloat = 30

    /// Quick and settled, with a trace of life at the end so the mark lands
    /// rather than stops. Critically damped under Reduce Motion.
    private var glide: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.34, dampingFraction: 0.78)
    }

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
        let name = sound == .ownSong ? store.profile.alarmSoundLabel : sound.label

        return Button {
            select(sound)
        } label: {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .matchedGeometryEffect(id: "check", in: checkSpace)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .frame(width: Self.checkColumn, alignment: .leading)

                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .scaleEffect(isPlaying && !reduceMotion ? 1.02 : 1, anchor: .leading)

                Spacer(minLength: 12)

                if isPlaying {
                    MiniWaveform(level: player?.level ?? 0, tint: Theme.inkSecondary)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.3, anchor: .trailing).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                } else if sound == .ownSong {
                    Text("your song")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 50)
            .animation(glide, value: isPlaying)
        }
        .buttonStyle(AlarmRowButtonStyle())
        .accessibilityLabel(name)
        .accessibilityValue(isPlaying ? "playing" : "")
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
            withAnimation(glide) {
                store.profile.alarmSound = sound
            }
        } else {
            Haptics.tap(intensity: 0.6)
        }
        player?.toggle(sound, profile: store.profile)
    }
}
