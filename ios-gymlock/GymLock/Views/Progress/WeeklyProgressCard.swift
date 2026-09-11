import SwiftUI

/// The expanded week: what actually happened, day by day.
///
/// Physically the same card as the month — it grows out of the column the user
/// tapped and returns to it — so this is one object at two levels of detail
/// rather than a second screen. Tapping anywhere on the surface closes it.
struct WeeklyProgressCard: View {
    let week: ProgressWeekSummary
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            dayRow
            ProgressLegend()
                .padding(.top, 16)
            summaryRow
        }
        .padding(ProgressCardMetrics.padding)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: .rect(cornerRadius: ProgressCardMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ProgressCardMetrics.cornerRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        // Lifted further than the month card: it is in front of a scrim now.
        .shadow(color: .black.opacity(0.16), radius: 26, y: 12)
        // The tap target for closing. The chevron is for discoverability, not
        // the only way out.
        .contentShape(.rect(cornerRadius: ProgressCardMetrics.cornerRadius))
        .onTapGesture(perform: onClose)
        .task {
            if reduceMotion {
                hasLoaded = true
            } else {
                try? await Task.sleep(for: .seconds(0.08))
                hasLoaded = true
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Theme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to month")

            VStack(alignment: .leading, spacing: 2) {
                Text(week.rangeLabel)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(Theme.ink)

                Text(week.detailHeadline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Days

    private var dayRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(week.days.enumerated()), id: \.element.id) { offset, day in
                WeeklyDayStack(
                    day: day,
                    unitHeight: 44,
                    hasLoaded: hasLoaded,
                    reduceMotion: reduceMotion,
                    riseDelay: Double(offset) * 0.035
                )
            }
        }
        .padding(.top, 18)
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryRow: some View {
        if week.tally.hasPlan {
            HStack(spacing: 10) {
                summaryTile(
                    value: "\(week.tally.completed)/\(max(week.headlineTotal, week.tally.completed))",
                    caption: week.isLive ? "due completed" : "completed"
                )
                summaryTile(value: week.percentText, caption: "completion")

                if week.tally.quickWorkout > 0 {
                    summaryTile(
                        value: "\(week.tally.verifiedGym)·\(week.tally.quickWorkout)",
                        caption: "gym · quick"
                    )
                }
            }
            .padding(.top, 14)
        }
    }

    private func summaryTile(value: String, caption: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Theme.ink)

            Text(caption)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One day column

/// A single day, in the same card language as the month.
///
/// Every day gets the same channel so the week keeps its rhythm; what changes
/// is how much of that channel is filled and with what.
struct WeeklyDayStack: View {
    let day: ProgressDay
    let unitHeight: CGFloat
    let hasLoaded: Bool
    let reduceMotion: Bool
    let riseDelay: Double

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // The channel. Present on every day, including rest days, so
                // the columns line up.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ProgressPalette.track)
                    .frame(height: unitHeight + 16)

                if let layer = layerKind {
                    ProgressLayeredBar(
                        layers: [ProgressLayer(kind: layer, units: 1)],
                        unitHeight: fillHeight,
                        overlap: 0,
                        hasAppeared: hasLoaded,
                        reduceMotion: reduceMotion,
                        baseDelay: riseDelay
                    )
                }
            }
            .frame(height: unitHeight + 16, alignment: .bottom)

            Text(day.weekdayLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(day.isToday ? Theme.ink : Theme.inkSecondary)
                .padding(.top, 7)

            Text(day.dateLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 1)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityText)
    }

    /// Which card this day draws, if any.
    private var layerKind: ProgressLayerKind? {
        switch day.status {
        case .gymVerified: .gym
        case .quickWorkoutVerified: .quick
        case .missed: .missed
        case .upcoming, .unresolved: .ghost
        // A deliberate skip and a plain rest day both draw nothing: the empty
        // channel already says everything true about them.
        case .excused, .rest: nil
        }
    }

    /// Completed days fill the channel; everything else sits lower, so the
    /// week's shape alone tells the user how it went.
    private var fillHeight: CGFloat {
        switch day.status {
        case .gymVerified, .quickWorkoutVerified: unitHeight + 16
        case .missed: unitHeight * 0.42
        case .upcoming, .unresolved: unitHeight * 0.66
        case .excused, .rest: 0
        }
    }
}
