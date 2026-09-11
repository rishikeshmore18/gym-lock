import SwiftUI

/// Shared geometry for the period card.
///
/// Every zone is a fixed height so the card is exactly the same size at both
/// zoom levels. That is the whole trick behind the transition reading as one
/// chart changing resolution: if the card resized, the surrounding page would
/// reflow and it would look like a new view arriving instead.
enum ProgressCardMetrics {
    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 18
    /// Height of the plotting area, excluding the labels above and below.
    static let chartHeight: CGFloat = 118
    /// Tallest a single session slot is allowed to draw.
    static let maxUnitHeight: CGFloat = 34
    /// Shortest, so a month with many sessions a week still reads as cards.
    static let minUnitHeight: CGFloat = 13
    /// Reserved for the count above a column.
    static let topLabelHeight: CGFloat = 14
    /// Reserved for the labels under a column — two lines at the week level,
    /// one at the month level.
    static let footerHeight: CGFloat = 30
    /// Title, subtitle and the ring cluster. Must clear the ring itself
    /// (66pt) or the header would overlap the chart below it.
    static let headerHeight: CGFloat = 74

    static var totalChartHeight: CGFloat {
        topLabelHeight + 4 + chartHeight + footerHeight
    }
}

/// The progress chart: how the user is doing against the sessions they planned.
///
/// One card at two levels of detail. Tapping a week does not open anything —
/// the month's bars compress into the column that was tapped and the seven day
/// bars expand out of that same point, inside the same surface, with the same
/// ring re-reading itself. Tapping back reverses it.
///
/// Every number is derived from the ledger; nothing is estimated and no day is
/// drawn as a miss unless a miss was recorded.
struct ProgressPeriodCard: View {
    let model: ProgressPeriodModel
    /// Stagger so the card lands after the two stat tiles above it.
    var appearanceDelay: Double = 0.16
    let onSelectWeek: (Int) -> Void
    let onCollapseWeek: () -> Void
    let onStepMonth: (Int) -> Void
    let onStepWeek: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var chartHasLoaded = false

    private var month: ProgressMonthSummary { model.month }
    private var isWeekLevel: Bool { model.isWeekExpanded }

    /// The week the chart is focused on, or was focused on last.
    ///
    /// Kept after a collapse so the day bars still exist while they animate
    /// away — they cannot compress back into the month if they have already
    /// been torn off the screen.
    private var focusWeek: ProgressWeekSummary? {
        month.week(at: model.selectedWeek ?? model.lastWeekIndex)
    }

    /// Whichever level the header and ring are currently describing.
    private var activeSummary: any ProgressPeriodPresentation {
        if isWeekLevel, let focusWeek { return focusWeek }
        return month
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            chartArea
            ProgressLegend()
                .padding(.top, 16)
        }
        .padding(ProgressCardMetrics.padding)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: .rect(cornerRadius: ProgressCardMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ProgressCardMetrics.cornerRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 10, y: 4)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16)
        // A horizontal flick moves through months at the month level and
        // through weeks at the week level — the same gesture, scoped to
        // whatever the chart is currently showing.
        .gesture(horizontalSwipe)
        .task {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
                chartHasLoaded = true
            } else {
                withAnimation(Theme.settle.delay(appearanceDelay)) { hasAppeared = true }
                try? await Task.sleep(for: .seconds(appearanceDelay + 0.12))
                chartHasLoaded = true
            }
        }
    }

    // MARK: Header

    /// Both header variants are always mounted and crossfade in place, so the
    /// title swap cannot change the card's height mid-animation.
    private var header: some View {
        ZStack(alignment: .topLeading) {
            monthHeader
                .opacity(isWeekLevel ? 0 : 1)
                .offset(x: isWeekLevel ? -12 : 0)

            weekHeader
                .opacity(isWeekLevel ? 1 : 0)
                .offset(x: isWeekLevel ? 0 : 12)
                .allowsHitTesting(isWeekLevel)
        }
        .frame(height: ProgressCardMetrics.headerHeight, alignment: .topLeading)
    }

    private var monthHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(month.titleLabel)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(Theme.ink)

                Text(month.subtitleLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            if month.tally.hasPlan {
                ringCluster
            } else {
                monthStepper
            }
        }
    }

    @ViewBuilder
    private var weekHeader: some View {
        if let focusWeek {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onCollapseWeek) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to month")

                VStack(alignment: .leading, spacing: 2) {
                    Text(focusWeek.rangeLabel)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.ink)

                    Text(focusWeek.breakdownLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 8)

                if focusWeek.tally.hasPlan {
                    ringCluster
                }
            }
        }
    }

    /// One ring, shared by both levels. It re-reads itself rather than being
    /// replaced, so the numbers roll over instead of cutting.
    private var ringCluster: some View {
        HStack(spacing: 10) {
            ProgressCompletionRing(
                fraction: activeSummary.completionFraction,
                valueText: activeSummary.fractionText,
                captionText: activeSummary.fractionCaption,
                diameter: 66,
                hasAppeared: chartHasLoaded,
                reduceMotion: reduceMotion
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(activeSummary.percentText)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.ink)

                Text(activeSummary.percentCaption)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                // Keeps a live period honest: "3 of 4 due" without hiding
                // that twelve were planned.
                if let note = activeSummary.planNote {
                    Text(note)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }
            .frame(width: 72, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// Only shown in the empty state, where the ring would say nothing.
    private var monthStepper: some View {
        HStack(spacing: 4) {
            stepButton(-1, "chevron.left", enabled: model.canGoBack)
            stepButton(1, "chevron.right", enabled: model.canGoForward)
        }
    }

    private func stepButton(_ step: Int, _ icon: String, enabled: Bool) -> some View {
        Button {
            onStepMonth(step)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Theme.inkSecondary : Theme.inkTertiary.opacity(0.4))
                .frame(width: 30, height: 30)
                .background(Theme.surfaceMuted, in: Circle())
        }
        .disabled(!enabled)
        .accessibilityLabel(step < 0 ? "Previous month" : "Next month")
    }

    // MARK: Chart

    @ViewBuilder
    private var chartArea: some View {
        if let empty = month.emptyStateText {
            emptyState(empty)
        } else {
            ZStack(alignment: .bottom) {
                monthRow
                weekRow
            }
            .frame(height: ProgressCardMetrics.totalChartHeight, alignment: .bottom)
            .padding(.top, 14)
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ProgressCardMetrics.totalChartHeight)
        .padding(.top, 14)
    }

    /// The month's weeks. They squeeze horizontally into the focused column
    /// as the week level takes over.
    private var monthRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(month.weeks) { week in
                ProgressMonthWeekColumn(
                    week: week,
                    unitHeight: unitHeight,
                    isFocused: model.selectedWeek == week.index,
                    isActive: !isWeekLevel,
                    hasLoaded: chartHasLoaded,
                    reduceMotion: reduceMotion,
                    // Left to right, so the month reads in the direction it
                    // was lived.
                    riseDelay: Double(week.index) * 0.05,
                    // Columns nearest the focus move last on the way out,
                    // which is what makes the set look like it is folding
                    // into that point rather than just shrinking.
                    levelDelay: staggerFromFocus(week.index)
                ) {
                    onSelectWeek(week.index)
                }
            }
        }
        .scaleEffect(
            x: isWeekLevel ? 0.3 : 1,
            y: isWeekLevel ? 0.94 : 1,
            anchor: compressionAnchor
        )
        .allowsHitTesting(!isWeekLevel)
    }

    /// The focused week's days. They expand out of the same point the month
    /// collapsed into.
    @ViewBuilder
    private var weekRow: some View {
        if let focusWeek {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(focusWeek.days.enumerated()), id: \.element.id) { offset, day in
                    ProgressWeekDayColumn(
                        day: day,
                        channelHeight: ProgressCardMetrics.chartHeight,
                        isActive: isWeekLevel,
                        hasLoaded: chartHasLoaded,
                        reduceMotion: reduceMotion,
                        riseDelay: Double(offset) * 0.03,
                        levelDelay: Double(offset) * 0.028
                    )
                }
            }
            .scaleEffect(
                x: isWeekLevel ? 1 : 0.3,
                y: isWeekLevel ? 1 : 0.94,
                anchor: compressionAnchor
            )
            .allowsHitTesting(isWeekLevel)
        }
    }

    /// The point both sets converge on: the horizontal centre of the focused
    /// week's column.
    ///
    /// Derived from the column's index rather than a measured frame — the row
    /// is an even split, so the arithmetic is exact and there is no layout
    /// feedback loop to manage.
    private var compressionAnchor: UnitPoint {
        let count = month.weeks.count
        guard count > 0 else { return .bottom }
        let index = model.selectedWeek ?? model.lastWeekIndex
        let clamped = min(max(index, 0), count - 1)
        return UnitPoint(x: (CGFloat(clamped) + 0.5) / CGFloat(count), y: 1)
    }

    /// Distance from the focused column, so the fold ripples outwards.
    private func staggerFromFocus(_ index: Int) -> Double {
        let focus = model.selectedWeek ?? model.lastWeekIndex
        return Double(abs(index - focus)) * 0.022
    }

    /// One session slot's height, chosen so the tallest week fills the area.
    private var unitHeight: CGFloat {
        let tallest = max(month.maxSlots, 1)
        let raw = ProgressCardMetrics.chartHeight / CGFloat(tallest)
        return min(ProgressCardMetrics.maxUnitHeight, max(ProgressCardMetrics.minUnitHeight, raw))
    }

    // MARK: Navigation

    private var horizontalSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let step = value.translation.width < 0 ? 1 : -1
                if isWeekLevel {
                    onStepWeek(step)
                } else {
                    onStepMonth(step)
                }
            }
    }
}
