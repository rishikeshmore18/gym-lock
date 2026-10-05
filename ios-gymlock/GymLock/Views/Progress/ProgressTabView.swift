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
    /// by the tab shell; this screen travels to the card and dims every
    /// section but it, in place.
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
        // The landing: once per request, because the model only ever moves
        // to .focused once per request.
        .onChange(of: spotlight.phase) { _, phase in
            if phase == .focused { Haptics.selection() }
        }
        // The card's own actions surfacing are taps on the card too: an
        // import starting or the Story editor opening closes the spotlight
        // even if a system control kept the tap to itself.
        .onChange(of: photos.isImporting) { _, isImporting in
            if isImporting { dismissSpotlight() }
        }
        .onChange(of: shareOrigin != nil) { _, isSharing in
            if isSharing { dismissSpotlight() }
        }
        .tint(Theme.accent)
        .storyEditor(origin: $shareOrigin, photos: photos, transitionNamespace: shareTransition)
        .task(id: refreshKey) { refresh() }
        // The Day 0 photograph the user took during onboarding is their real
        // before-picture; the stack starts from it rather than asking for the
        // same thing a second time. Runs once — the store keeps its own flag.
        .task { await photos.adoptDayZeroIfNeeded(store.profile.day0Media) }
    }

    /// Each section dims itself in its own shape while the spotlight is up;
    /// the photos card does so only until it lands. Every spotlight piece is
    /// an overlay, a background or a visual effect, so none of it adds size
    /// and the page lays out exactly as a normal visit does.
    private var page: some View {
        FloatingTitleScreen(title: "Progress", isSpotlightDimmed: spotlight.isActive) {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ProgressStatCard(
                        title: "Week Streak",
                        count: store.streak.weeks,
                        appearanceDelay: 0
                    ) {
                        FlameEmblem()
                    }
                    .spotlightDimmed(spotlight.isActive, cornerRadius: statCardRadius)

                    ProgressStatCard(
                        title: "Badges Earned",
                        count: 0,
                        digitStyle: .dark,
                        appearanceDelay: 0.08
                    ) {
                        BadgeEmblem()
                    }
                    .spotlightDimmed(spotlight.isActive, cornerRadius: statCardRadius)
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
                .spotlightDimmed(spotlight.isActive, cornerRadius: ProgressCardMetrics.cornerRadius)
                .accessibilityHidden(spotlight.isActive)

                ProgressPhotosCard(
                    store: photos,
                    onShare: { shareOrigin = $0 },
                    transitionNamespace: shareTransition
                )
                // A small lift once lit. Black and faint: depth, not glow.
                .shadow(
                    color: .black.opacity(spotlight.phase == .focused ? 0.09 : 0),
                    radius: 17,
                    y: 7
                )
                // Behind the real card, so the card itself hides the line
                // until it has risen clear of the top edge.
                .background(alignment: .top) {
                    if spotlight.phase == .focused {
                        ProgressSpotlightHeadline(
                            reduceMotion: reduceMotion,
                            onDismiss: dismissSpotlight
                        )
                        .transition(
                            .asymmetric(
                                insertion: reduceMotion ? .opacity : .identity,
                                removal: .opacity
                            )
                        )
                    }
                }
                .spotlightDimmed(
                    spotlight.phase == .scrolling,
                    cornerRadius: ProgressCardMetrics.cornerRadius
                )
                .id(ProgressSpotlightModel.cardID)
            }
            .padding(.horizontal, 20)
        }
        // Any tap anywhere on the page closes the spotlight: the dark canvas,
        // the title, a dimmed card (whose dark layer has taken the touch from
        // its controls), or the lit photos card. Watched alongside every
        // other gesture, never instead of one, so on the lit card Add Photo
        // and the photos act on that same tap and a drag of the stack stays
        // a drag. Switched off entirely when the spotlight is down.
        .contentShape(.rect)
        .simultaneousGesture(
            TapGesture().onEnded { dismissSpotlight() },
            including: spotlight.isActive ? .all : .subviews
        )
    }

    // MARK: Spotlight

    private struct SpotlightTravel: Equatable {
        let request: Int
        let isCovered: Bool
    }

    /// Scrolls the least distance that shows the whole real card.
    ///
    /// No anchor on purpose. The card is the last thing on the page, so any
    /// anchor that asks for it higher than the page can scroll is a target
    /// past the end of the content. "Wholly visible" is always reachable,
    /// respects the tab bar's inset, and leaves the dark room above the card
    /// for the line. The model lands the card when the travel has run.
    private func travelToPhotos(with proxy: ScrollViewProxy) {
        guard !LaunchCover.shared.isHoldingApp,
              spotlight.startTravel(animated: !reduceMotion)
        else { return }
        Haptics.prepareSelection()
        Haptics.soft()
        if reduceMotion {
            proxy.scrollTo(ProgressSpotlightModel.cardID)
        } else {
            withAnimation(ProgressSpotlightModel.travelAnimation) {
                proxy.scrollTo(ProgressSpotlightModel.cardID)
            }
        }
    }

    private func dismissSpotlight() {
        guard spotlight.isActive else { return }
        withAnimation(ProgressSpotlightModel.dismissAnimation) { spotlight.dismiss() }
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
