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
    /// The spotlight a workout-done notification opens (FLOW, Flow 3). Owned
    /// by the tab shell; this screen only travels to the card and reports
    /// where it sits.
    let spotlight: ProgressSpotlightModel

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var period = ProgressPeriodModel()
    /// One store for the whole app, created at launch, so the gym flow can
    /// see a photo being saved here (FLOW, Flow 3, "I'm here").
    @Environment(ProgressPhotoStore.self) private var photos
    /// The share being edited, if any. Presented from the tab so the cover
    /// outlives the card that raised it.
    @State private var shareOrigin: ShareOrigin?
    @Namespace private var shareTransition

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
        // No NavigationStack: this tab pushes nothing, and four live stacks
        // inside the tab shell stopped insetting their scroll views, which is
        // what put the large "Progress" title on top of the first card. The
        // header now belongs to the screen and collapses as the page scrolls.
        ScrollViewReader { proxy in
            page
                // On a cold launch the travel waits for the launch cover, so
                // it is seen, and so the page has finished its first layout.
                .task(id: SpotlightTravel(
                    request: spotlight.requestCount,
                    isCovered: LaunchCover.shared.isHoldingApp
                )) { travelToPhotos(with: proxy) }
        }
        .tint(Theme.accent)
        .storyEditor(origin: $shareOrigin, photos: photos, transitionNamespace: shareTransition)
        .task(id: refreshKey) { refresh() }
        // The Day 0 photograph the user took during onboarding is their real
        // before-picture; the stack starts from it rather than asking for the
        // same thing a second time. Runs once — the store keeps its own flag.
        .task { await photos.adoptDayZeroIfNeeded(store.profile.day0Media) }
    }

    private var page: some View {
        FloatingTitleScreen(title: "Progress") {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ProgressStatCard(
                        title: "Week Streak",
                        count: store.streak.weeks,
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
                // Dimmed under the spotlight, so out of VoiceOver's reach too.
                .accessibilityHidden(spotlight.isActive)

                ProgressPeriodCard(
                    model: period,
                    onSelectWeek: selectWeek,
                    onCollapseWeek: collapseWeek,
                    onStepMonth: stepMonth,
                    onStepWeek: stepWeek
                )
                .accessibilityHidden(spotlight.isActive)

                ProgressPhotosCard(
                    store: photos,
                    onShare: { shareOrigin = $0 },
                    transitionNamespace: shareTransition
                )
                .id(ProgressSpotlightModel.cardID)
                // Cheap when the spotlight is down: the model only keeps the
                // value, and nothing redraws.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    spotlight.cardMoved(to: $0)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Spotlight

    private struct SpotlightTravel: Equatable {
        let request: Int
        let isCovered: Bool
    }

    /// Brings the real Progress Photos card a little below the middle of the
    /// screen, leaving dark room above it for the line. The scroll view clamps
    /// at its end, which keeps the card clear of the tab bar.
    private func travelToPhotos(with proxy: ScrollViewProxy) {
        guard spotlight.phase == .scrolling, !LaunchCover.shared.isHoldingApp else { return }
        let anchor = UnitPoint(x: 0.5, y: 0.6)
        if reduceMotion {
            proxy.scrollTo(ProgressSpotlightModel.cardID, anchor: anchor)
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                proxy.scrollTo(ProgressSpotlightModel.cardID, anchor: anchor)
            }
        }
        spotlight.scrollStarted(animated: !reduceMotion)
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
    ProgressTabView(spotlight: ProgressSpotlightModel())
        .environment(AppStore())
        .environment(ProgressPhotoStore())
}
