import SwiftUI

/// The Progress tab.
///
/// It opens with two stat tiles — the streak and the badges — before anything
/// else, because progress on this screen is first a feeling ("am I actually
/// doing this") and only then a chart. Every number here comes from the record:
/// the streak is the ledger's, and badges stay at zero until a badge system
/// exists. Nothing is estimated to make the page look fuller.
///
/// Below them sits the period card, which answers the follow-up question — "am
/// I doing what I planned" — and expands in place when a week is tapped.
struct ProgressTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var period = ProgressPeriodModel()
    /// Measured week-column frames, used to grow the expanded card out of the
    /// bar the user actually tapped.
    @State private var frames = WeekFrameStore()
    /// The bar's centre, captured at the moment of the tap so the open and the
    /// close both pivot around the same point.
    @State private var growthAnchor: UnitPoint = .center

    /// The open/close spring. Responsive and slightly physical, with enough
    /// damping that the card settles instead of wobbling.
    private var morphAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.22)
            : .spring(response: 0.45, dampingFraction: 0.86)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                scrollContent

                if period.isWeekExpanded {
                    scrim
                }

                if let week = period.selectedWeekSummary {
                    WeeklyProgressCard(week: week) {
                        collapse()
                    }
                    .padding(.horizontal, 20)
                    .transition(expansion)
                    .zIndex(2)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(Theme.accent)
        .task(id: refreshKey) { refresh() }
    }

    // MARK: Content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ProgressStatCard(
                        title: "Day Streak",
                        count: store.log.momentumStreak,
                        appearanceDelay: 0
                    ) {
                        FlameEmblem()
                    }

                    ProgressStatCard(
                        title: "Badges Earned",
                        count: 0,
                        digitStyle: .dark,
                        appearanceDelay: 0.08
                    ) {
                        BadgeEmblem()
                    }
                }

                ProgressPeriodCard(
                    model: period,
                    frames: frames,
                    onSelectWeek: expand,
                    onStepMonth: stepMonth
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        // The month underneath stays readable but stops being touchable while
        // a week is open, so a tap lands on the scrim and closes it.
        .disabled(period.isWeekExpanded)
        .zIndex(0)
    }

    /// Enough dimming to push the page back without hiding it.
    private var scrim: some View {
        Rectangle()
            .fill(.black.opacity(0.14))
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture(perform: collapse)
            .zIndex(1)
            .accessibilityLabel("Close week")
            .accessibilityAddTraits(.isButton)
    }

    /// The card grows out of the tapped column and shrinks back into it.
    ///
    /// Scaling from the bar's own centre is what makes the motion read as
    /// spatial: the surface appears to rise out of that exact stack rather
    /// than fading in from the middle of the screen.
    private var expansion: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.78, anchor: growthAnchor).combined(with: .opacity)
    }

    // MARK: Actions

    private func expand(_ index: Int) {
        guard !period.isWeekExpanded else { return }
        // Captured before the state change so the transition already knows
        // where to grow from on its first frame.
        growthAnchor = frames.unitAnchor(forWeek: index)
        withAnimation(morphAnimation) {
            guard period.selectWeek(index) else { return }
            Haptics.selection()
        }
    }

    private func collapse() {
        withAnimation(morphAnimation) {
            guard period.collapseWeek() else { return }
            Haptics.tap(intensity: 0.55)
        }
    }

    private func stepMonth(_ step: Int) {
        let moved = period.step(
            by: step,
            log: store.log,
            plan: store.plan,
            schedule: store.schedule
        )
        guard moved else { return }
        Haptics.selection()
    }

    // MARK: Data

    /// Recomputes only when something the chart actually depends on changes —
    /// no timer, no polling.
    private var refreshKey: Int {
        var hasher = Hasher()
        hasher.combine(store.log)
        hasher.combine(store.plan)
        hasher.combine(store.schedule)
        return hasher.finalize()
    }

    private func refresh() {
        period.refresh(log: store.log, plan: store.plan, schedule: store.schedule)
    }
}

#Preview("Progress") {
    ProgressTabView()
        .environment(AppStore())
}
