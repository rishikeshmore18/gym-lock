import SwiftUI

/// The rhythm of a vibration, drawn as it plays: one mark per tap, a wider
/// bar per buzz, height by strength, each lighting up at the moment it is
/// felt.
///
/// It exists so the Haptics list can be read as well as felt. You can see
/// that S.O.S. is three short, three long, three short while your palm
/// confirms it, and on a device without a haptic engine the pattern is still
/// there to judge.
///
/// Driven by `TimelineView` from the moment the preview started, so it stays
/// in step with the haptic engine without any timers of its own. Reduce Motion
/// shows the whole pattern lit at once.
struct HapticBeatStrip: View {
    let haptic: AlarmHaptic
    let startedAt: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let beats = haptic.beats
        let span = max(
            beats.map { $0.time + max($0.duration, 0.08) }.max() ?? 0.3,
            0.3
        )
        let start = startedAt
        let settled = reduceMotion
        let active = Theme.ink
        let played = Theme.inkSecondary
        let waiting = Theme.inkTertiary.opacity(0.45)

        TimelineView(.animation(paused: reduceMotion)) { context in
            let elapsed = settled ? span : context.date.timeIntervalSince(start)

            Canvas { graphics, size in
                let tick: CGFloat = 3
                let track = max(size.width - tick, 1)

                for beat in beats {
                    let x = CGFloat(beat.time / span) * track
                    let width = beat.isContinuous
                        ? max(tick, CGFloat(beat.duration / span) * track)
                        : tick
                    let isNow = elapsed >= beat.time
                        && elapsed <= beat.time + max(beat.duration, 0.1)
                    let hasPlayed = elapsed >= beat.time

                    // The mark being felt right now stands a touch taller.
                    let strength = 0.4 + 0.6 * CGFloat(beat.intensity)
                    let height = size.height * strength * (isNow ? 1 : 0.86)
                    let rect = CGRect(
                        x: x,
                        y: (size.height - height) / 2,
                        width: width,
                        height: height
                    )

                    graphics.fill(
                        Path(roundedRect: rect, cornerRadius: tick / 2),
                        with: .color(isNow ? active : (hasPlayed ? played : waiting))
                    )
                }
            }
        }
        .frame(width: 60, height: 16)
        .accessibilityHidden(true)
    }
}
