import SwiftUI

/// The completion dial: one continuous orange arc for what was completed, one
/// continuous grey arc for what was not, and a small gap where they meet.
///
/// The two gaps are the only breaks in the circle. Splitting the progress into
/// one segment per session — the obvious thing to do with this data — turns the
/// ring into a tally chart and makes 9 of 12 unreadable at a glance, which is
/// the one job it has.
struct ProgressCompletionRing: View {
    /// 0...1, or `nil` when nothing has been due yet.
    let fraction: Double?
    /// Centre line, e.g. "9/12".
    let valueText: String
    /// Caption under it, e.g. "workouts".
    let captionText: String
    let diameter: CGFloat
    let hasAppeared: Bool
    let reduceMotion: Bool

    /// Angular size of each junction gap. Small enough to read as a seam
    /// rather than as a missing slice.
    private let gap: Double = 0.012

    var body: some View {
        let lineWidth = diameter * 0.125
        let drawn = hasAppeared ? clamped : 0

        ZStack {
            if isPartial {
                // Both arcs pulled in from the junctions on each side.
                arc(from: drawn + gap, to: 1 - gap, color: ProgressPalette.track, lineWidth: lineWidth)
                arc(from: gap, to: max(gap, drawn - gap), color: ProgressPalette.quick, lineWidth: lineWidth)
            } else if isComplete {
                // Complete: one unbroken ring, no seam to explain.
                Circle()
                    .stroke(ProgressPalette.quick, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .opacity(hasAppeared ? 1 : 0)
            } else {
                Circle()
                    .stroke(ProgressPalette.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            VStack(spacing: 0) {
                Text(valueText)
                    .font(.system(size: diameter * 0.235, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.ink)

                Text(captionText)
                    .font(.system(size: diameter * 0.115, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, lineWidth + 2)
        }
        .frame(width: diameter, height: diameter)
        .animation(ringAnimation, value: drawn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func arc(from start: Double, to end: Double, color: Color, lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: min(start, end), to: max(start, end))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    private var clamped: Double {
        min(max(fraction ?? 0, 0), 1)
    }

    /// Partway round: two arcs and two seams.
    private var isPartial: Bool {
        guard let fraction else { return false }
        return fraction > 0 && fraction < 1
    }

    /// All the way round: one unbroken ring.
    private var isComplete: Bool {
        guard let fraction else { return false }
        return fraction >= 1
    }

    private var ringAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.75).delay(0.1)
    }

    private var accessibilityText: String {
        guard let fraction else { return "\(valueText) \(captionText). No completion rate yet." }
        return "\(valueText) \(captionText). \(Int((fraction * 100).rounded())) percent complete."
    }
}
