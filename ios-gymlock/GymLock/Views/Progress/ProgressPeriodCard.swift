import SwiftUI

/// Shared geometry for the period card, so the month and week surfaces agree.
enum ProgressCardMetrics {
    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 18
    /// Height of the plotting area, excluding the labels above and below.
    static let chartHeight: CGFloat = 118
    /// Tallest a single session slot is allowed to draw.
    static let maxUnitHeight: CGFloat = 34
    /// Shortest, so a month with many sessions a week still reads as cards.
    static let minUnitHeight: CGFloat = 13
}

/// The month card: how the user is doing against the sessions they planned.
///
/// One question, answered in about a second — then a week can be opened for
/// the detail. Every number is derived from the ledger; nothing is estimated
/// and no day is drawn as a miss unless a miss was recorded.
struct ProgressPeriodCard: View {
    let model: ProgressPeriodModel
    /// Where each week column sits, filled in during layout so the expanded
    /// card knows which bar it came from.
    let frames: WeekFrameStore
    /// Stagger so the card lands after the two stat tiles above it.
    var appearanceDelay: Double = 0.16
    let onSelectWeek: (Int) -> Void
    let onStepMonth: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var chartHasLoaded = false

    private var month: ProgressMonthSummary { model.month }

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
        .overlayPreferenceValue(WeekAnchorKey.self) { anchors in
            GeometryReader { proxy in
                Color.clear
                    .onAppear { record(anchors, in: proxy) }
                    .onChange(of: proxy.size) { _, _ in record(anchors, in: proxy) }
                    .onChange(of: anchors.count) { _, _ in record(anchors, in: proxy) }
                    // A new month can have the same number of weeks as the
                    // one before it, so the count alone is not enough to
                    // know the columns moved.
                    .onChange(of: month.monthStart) { _, _ in record(anchors, in: proxy) }
            }
            .allowsHitTesting(false)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16)
        // A horizontal flick moves the month, which is lighter than a picker
        // for a control most people will use once or twice.
        .gesture(monthSwipe)
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

    private var header: some View {
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
                summaryCluster
            } else {
                monthStepper
            }
        }
    }

    private var summaryCluster: some View {
        HStack(spacing: 10) {
            ProgressCompletionRing(
                fraction: month.completionFraction,
                valueText: month.fractionText,
                captionText: month.fractionCaption,
                diameter: 72,
                hasAppeared: chartHasLoaded,
                reduceMotion: reduceMotion
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(month.percentText)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.ink)

                Text(month.percentCaption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = month.planNote {
                    Text(note)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary.opacity(0.85))
                        .padding(.top, 1)
                }
            }
            .frame(width: 78, alignment: .leading)
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
            weekRow
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
        .frame(height: ProgressCardMetrics.chartHeight + 34)
        .padding(.top, 14)
    }

    private var weekRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(month.weeks) { week in
                MonthlyWeekStack(
                    week: week,
                    unitHeight: unitHeight,
                    isSelected: model.selectedWeek == week.index,
                    isDimmed: model.isWeekExpanded && model.selectedWeek != week.index,
                    hasLoaded: chartHasLoaded,
                    reduceMotion: reduceMotion,
                    // Left to right, so the month reads in the direction it
                    // was lived.
                    riseDelay: Double(week.index) * 0.05
                ) {
                    onSelectWeek(week.index)
                }
            }
        }
        .padding(.top, 20)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: model.selectedWeek)
    }

    /// One session slot's height, chosen so the tallest week fills the area.
    private var unitHeight: CGFloat {
        let tallest = max(month.maxSlots, 1)
        let raw = ProgressCardMetrics.chartHeight / CGFloat(tallest)
        return min(ProgressCardMetrics.maxUnitHeight, max(ProgressCardMetrics.minUnitHeight, raw))
    }

    // MARK: Measurement

    /// Resolves the published anchors into plain rects.
    ///
    /// Written from a layout callback into a plain reference type on purpose:
    /// storing this in observable state would invalidate the view that just
    /// measured it and loop. Nothing reads it during `body`.
    private func record(_ anchors: [Int: Anchor<CGRect>], in proxy: GeometryProxy) {
        frames.container = proxy.size
        for (index, anchor) in anchors {
            frames.rects[index] = proxy[anchor]
        }
    }

    // MARK: Month navigation

    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                onStepMonth(value.translation.width < 0 ? 1 : -1)
            }
    }
}

// MARK: - One week column

/// A single week, drawn as a stack of physical cards.
///
/// The count sits above the stack and the real date range below it, so the bar
/// itself never has to carry a label.
struct MonthlyWeekStack: View {
    let week: ProgressWeekSummary
    let unitHeight: CGFloat
    let isSelected: Bool
    let isDimmed: Bool
    let hasLoaded: Bool
    let reduceMotion: Bool
    let riseDelay: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                countLabel

                stackArea
                    .frame(height: ProgressCardMetrics.chartHeight, alignment: .bottom)
                    .padding(.top, 4)

                Text(week.rangeLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.45 : 1)
        .scaleEffect(isSelected && !reduceMotion ? 1.03 : 1, anchor: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var countLabel: some View {
        Text(week.stackCountLabel ?? " ")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Theme.ink : Theme.inkSecondary)
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
            // Publishes the frame the expanded card grows out of.
            .anchorPreference(key: WeekAnchorKey.self, value: .bounds) {
                [week.index: $0]
            }
        } else {
            // Nothing planned: a baseline keeps the month's rhythm without
            // drawing a bar that would imply a failure.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ProgressPalette.track)
                .frame(height: 6)
                .anchorPreference(key: WeekAnchorKey.self, value: .bounds) {
                    [week.index: $0]
                }
        }
    }
}

// MARK: - Morph geometry

/// Where each week column sits, so the expanded card can grow out of the exact
/// bar the user tapped.
///
/// `matchedGeometryEffect` is the obvious tool here, but with `.position` it
/// pins the expanded card to the bar's centre for as long as both exist —
/// which parks a full-width card halfway up the chart instead of letting it
/// settle. Measuring the source frame keeps the spatial link and still lets
/// the card land where the layout wants it.
struct WeekAnchorKey: PreferenceKey {
    nonisolated static let defaultValue: [Int: Anchor<CGRect>] = [:]

    nonisolated static func reduce(
        value: inout [Int: Anchor<CGRect>],
        nextValue: () -> [Int: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

/// The last measured position of each week column.
///
/// Deliberately a plain class rather than observable state: it is written
/// during layout, and anything that invalidated the view from there would
/// loop. Nothing reads it during `body` — only the tap handler does, to work
/// out which direction the card should grow from.
final class WeekFrameStore {
    var rects: [Int: CGRect] = [:]
    var container: CGSize = .zero

    /// The bar's centre as a unit point inside the container, which is what a
    /// scale transition needs as its anchor.
    func unitAnchor(forWeek index: Int) -> UnitPoint {
        guard let rect = rects[index], container.width > 0, container.height > 0 else {
            return .center
        }
        return UnitPoint(
            x: min(max(rect.midX / container.width, 0), 1),
            y: min(max(rect.midY / container.height, 0), 1)
        )
    }
}
