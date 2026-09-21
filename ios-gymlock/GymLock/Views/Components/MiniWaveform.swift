import SwiftUI

/// Three bars that move with the preview's actual output level.
///
/// Extracted from `MorningAlarmPlanView` so the alarm settings screen can show
/// the same live waveform. The tint is a parameter rather than a second copy:
/// the alarm settings screen keeps its one coral accent for the dial, so its
/// waveform renders in grey.
struct MiniWaveform: View {
    let level: Double
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { bar in
                // Staggered scaling so the bars do not move as one block.
                let weight = [0.7, 1.0, 0.55][bar]
                let height = 6 + level * 18 * weight

                Capsule()
                    .fill(tint.opacity(level > 0.02 ? 0.9 : 0.25))
                    .frame(width: 3, height: max(6, height))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}
