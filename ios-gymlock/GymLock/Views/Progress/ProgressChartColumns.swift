import SwiftUI

// MARK: - Month level

/// One week of the month, drawn as a stack of physical cards.
///
/// The count sits above the stack and the real date range below it, so the bar
/// itself never has to carry a label.
///
/// `isActive` is what makes the zoom work: the column stays mounted when the
/// chart moves to the week level and animates out of the way instead of being
/// removed. A view that has been torn off the screen cannot animate back.
struct ProgressMonthWeekColumn: View {
    let week: ProgressWeekSummary
    let unitHeight: CGFloat
    /// The column the chart is zooming into.
    let isFocused: Bool
    /// True while the month level is the one being shown.
    let isActive: Bool
    let hasLoaded: Bool
    let reduceMotion: Bool
    /// Stagger for the first-load rise.
    let riseDelay: Double
    /// Stagger for the month/week zoom.
    let levelDelay: Double
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                countLabel
                    .frame(height: ProgressCardMetrics.topLabelHeight)

                stackArea
                    .frame(height: ProgressCardMetrics.chartHeight, alignment: .bottom)
                    .padding(.top, 4)

                Text(week.rangeLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isFocused ? Theme.ink : Theme.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 7)
                    .frame(height: ProgressCardMetrics.footerHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isActive ? 1 : 0)
        // A touch of blur on the way out sells the depth change: the month is
        // not sliding aside, it is going out of focus as the week comes in.
        .blur(radius: isActive || reduceMotion ? 0 : 4)
        .animation(levelAnimation, value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.accessibilityText)
        .accessibilityHint("Shows this week day by day")
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(!isActive)
    }

    private var levelAnimation: Animation {
        guard !reduceMotion else { return .easeInOut(duration: 0.2) }
        return .spring(response: 0.42, dampingFraction: 0.88).delay(levelDelay)
    }

    private var countLabel: some View {
        Text(week.stackCountLabel ?? " ")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isFocused ? Theme.ink : Theme.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .opacity(hasLoaded ? 1 : 0)
            .animation(.easeOut(duration: 0.25).delay(riseDelay + 0.2), value: hasLoaded)
    }

    @ViewBuilder
    private var stackArea: some View {
        if week.tally.hasPlan {
            ProgressLayeredBar(
                layers: week.tally.layers,
                unitHeight: unitHeight,
                hasAppeared: hasLoaded,
                reduceMotion: reduceMotion,
                baseDelay: riseDelay
            )
        } else {
            // Nothing planned: a baseline keeps the month's rhythm without
            // drawing a bar that would imply a failure.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ProgressPalette.track)
                .frame(height: 6)
        }
    }
}

// MARK: - Week level

/// One day of the focused week, in the same card language as the month.
///
/// Every day gets the same channel so the week keeps its rhythm; what changes
/// is how much of that channel is filled and with what.
struct ProgressWeekDayColumn: View {
    let day: ProgressDay
    /// Height of the full channel, matching the month's plotting area.
    let channelHeight: CGFloat
    /// True while the week level is the one being shown.
    let isActive: Bool
    let hasLoaded: Bool
    let reduceMotion: Bool
    let riseDelay: Double
    let levelDelay: Double

    var body: some View {
        VStack(spacing: 0) {
            // Matches the month column's count row so both levels share a
            // baseline and the bars do not jump vertically during the zoom.
            Color.clear
                .frame(height: ProgressCardMetrics.topLabelHeight)

            ZStack(alignment: .bottom) {
                // The channel. Present on every day, including rest days, so
                // the columns line up.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ProgressPalette.track)
                    .frame(height: channelHeight)

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
            .frame(height: channelHeight, alignment: .bottom)
            .padding(.top, 4)

            VStack(spacing: 1) {
                Text(day.weekdayLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(day.isToday ? Theme.ink : Theme.inkSecondary)

                Text(day.dateLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.top, 7)
            .frame(height: ProgressCardMetrics.footerHeight, alignment: .top)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .opacity(isActive ? 1 : 0)
        .blur(radius: isActive || reduceMotion ? 0 : 4)
        .animation(levelAnimation, value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityText)
        .accessibilityHidden(!isActive)
    }

    private var levelAnimation: Animation {
        guard !reduceMotion else { return .easeInOut(duration: 0.2) }
        return .spring(response: 0.44, dampingFraction: 0.88).delay(levelDelay)
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
        case .gymVerified, .quickWorkoutVerified: channelHeight
        case .missed: channelHeight * 0.34
        case .upcoming, .unresolved: channelHeight * 0.55
        case .excused, .rest: 0
        }
    }
}
