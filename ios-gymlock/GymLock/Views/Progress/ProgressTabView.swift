import SwiftUI

/// The Progress tab.
///
/// It opens with two stat tiles — the streak and the badges — before anything
/// else, because progress on this screen is first a feeling ("am I actually
/// doing this") and only then a chart. Every number here comes from the record:
/// the streak is the ledger's, and badges stay at zero until a badge system
/// exists. Nothing is estimated to make the page look fuller.
///
/// Below them sits the progress chart, which answers the follow-up question —
/// "am I doing what I planned" — and changes resolution between month and week
/// in place, without ever presenting a second surface.
///
/// The photographs come last, and answer the question the numbers cannot: not
/// whether the sessions happened, but whether they changed anything.
struct ProgressTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var period = ProgressPeriodModel()
    /// Owned by the tab so the photos survive the card scrolling out of view.
    @State private var photos = ProgressPhotoStore()

    /// The zoom between the two levels of the chart.
    ///
    /// A single spring drives every part of it — the bars compressing, the
    /// header crossfading and the ring re-reading — so they cannot drift out
    /// of sync with each other.
    private var zoomAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.22)
            : .spring(response: 0.46, dampingFraction: 0.85)
    }

    var body: some View {
        NavigationStack {
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
                        onSelectWeek: selectWeek,
                        onCollapseWeek: collapseWeek,
                        onStepMonth: stepMonth,
                        onStepWeek: stepWeek
                    )

                    ProgressPhotosCard(store: photos)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(Theme.canvas)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(Theme.accent)
        .task(id: refreshKey) { refresh() }
        // The Day 0 photograph the user took during onboarding is their real
        // before-picture; the stack starts from it rather than asking for the
        // same thing a second time. Runs once — the store keeps its own flag.
        .task { await photos.adoptDayZeroIfNeeded(store.profile.day0Media) }
    }

    // MARK: Actions

    private func selectWeek(_ index: Int) {
        withAnimation(zoomAnimation) {
            guard period.selectWeek(index) else { return }
            Haptics.selection()
        }
    }

    private func collapseWeek() {
        withAnimation(zoomAnimation) {
            guard period.collapseWeek() else { return }
            Haptics.tap(intensity: 0.55)
        }
    }

    /// Moves sideways through the weeks of the focused month.
    private func stepWeek(_ step: Int) {
        withAnimation(zoomAnimation) {
            guard period.stepWeek(by: step) else { return }
            Haptics.selection()
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
