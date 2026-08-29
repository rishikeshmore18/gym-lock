import SwiftUI

/// The primary home screen.
///
/// Deliberately sparse. Someone who already feels behind on the gym does not
/// need a dashboard telling them so — they need to see where they are, glance
/// at recent effort, and be able to come back tomorrow. Everything below the
/// calendar is intentional whitespace.
struct TodayHomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Owned by the tab shell so it survives tab switches.
    let intro: StreakIntroController

    @State private var window = CalendarWindow()
    @State private var index = DayStatusIndex.empty
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var leadingDay: Date?
    @State private var hasSettled = false

    /// Geometry for the morph, in global space.
    @State private var rootFrame: CGRect = .zero
    @State private var chipFrame: CGRect = .zero

    /// Nudge above true centre. A card sitting on the exact midpoint reads as
    /// slightly low, because the eye weights the top of a screen more heavily.
    private static let opticalCentreLift: CGFloat = 18

    /// How dark home goes behind the card. Enough to pull the eye to the
    /// streak, light enough that home is still clearly there behind it.
    private static let scrimOpacity: Double = 0.24

    private var streak: Int { store.log.momentumStreak }

    private var isMeasured: Bool { rootFrame.width > 0 && chipFrame.width > 0 }

    private var metrics: StreakCardMetrics { .fit(rootFrame.size) }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.top, 6)

                CalendarStripView(
                    window: window,
                    index: index,
                    selectedDay: selectedDay,
                    leadingDay: $leadingDay,
                    onSelect: select
                )
                .padding(.top, 20)

                // Deliberately empty. The rest of home is coming section by
                // section, and an empty screen is better than a padded one.
                Spacer(minLength: 0)
            }
            .opacity(hasSettled ? 1 : 0)
        }
        .overlay { streakOverlay }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rootFrame = $0 }
        .task {
            rebuildIndex()
            if leadingDay == nil {
                leadingDay = window.defaultLeadingDay(visibleDays: CalendarStripView.defaultVisibleDays)
            }
            withAnimation(.easeOut(duration: 0.28)) { hasSettled = true }

            // Parse the flame before anything needs to move, so the expansion
            // never waits on a file read. After the fade-in is started, not
            // before it — home appearing must not depend on this finishing.
            await FlameAsset.prepare()
        }
        .onChange(of: isMeasured, initial: true) { _, measured in
            guard measured else { return }
            intro.play(streak: streak, reduceMotion: reduceMotion)
        }
        .onChange(of: leadingDay) { _, day in
            guard let day else { return }
            window.extend(reaching: day)
        }
        .onChange(of: store.log) { _, _ in rebuildIndex() }
        .onChange(of: store.events) { _, _ in rebuildIndex() }
        .onChange(of: store.schedule.trainingDays) { _, _ in rebuildIndex() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            Image("GymLockLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 42, height: 42)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)

            Text("GymLock")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            streakSlot
        }
    }

    /// The chip, plus an invisible copy holding the space open.
    ///
    /// Without the reserved copy the header would reflow the moment the chip
    /// fades out for the morph, and the logo would visibly drift.
    private var streakSlot: some View {
        ZStack {
            StreakChip(streak: streak)
                .hidden()

            StreakChip(streak: streak) {
                intro.open(reduceMotion: reduceMotion)
            }
            .opacity(intro.isMounted ? 0 : 1)
            // The card is standing in for the chip while it is out; a second
            // tappable copy underneath it would be a target the user cannot see.
            .disabled(intro.isMounted)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                chipFrame = $0
            }
            // Handed over as the card leaves, taken back as it lands — never a
            // crossfade in the middle of the journey, which would show two
            // streaks at once.
            .animation(chipFade, value: intro.isMounted)
        }
    }

    private var chipFade: Animation {
        guard !intro.isMounted else { return .easeOut(duration: 0.12) }

        // Timed to land as the card arrives, so the chip is taken back at the
        // end of the journey rather than appearing beside a card still in
        // flight.
        let timing = reduceMotion
            ? StreakIntroController.Timing.reducedMotion
            : StreakIntroController.Timing.standard
        return .easeIn(duration: 0.18).delay(Double(timing.collapseTravel) / 1000 * 0.55)
    }

    // MARK: - Streak presentation

    /// The dimmed home and the card sitting on top of it.
    ///
    /// Mounted only while the streak is out, so there is no scrim and no Lottie
    /// player left in the hierarchy the rest of the time.
    @ViewBuilder
    private var streakOverlay: some View {
        if intro.isMounted {
            ZStack {
                scrim
                card
            }
        }
    }

    /// A flat colour rather than a blur of the whole screen. It costs one
    /// composited layer instead of a full-screen effect recomputing every frame
    /// while the calendar is alive underneath, and at this opacity a blur would
    /// not read any differently.
    private var scrim: some View {
        Color.black
            .opacity(intro.isExpanded ? Self.scrimOpacity : 0)
            .ignoresSafeArea()
            // Only a card the user opened is dismissible by tapping away from
            // it. During the automatic entrance this layer is invisible to
            // touches, so home stays usable straight through it.
            .allowsHitTesting(intro.isInteractive)
            .onTapGesture { intro.close(reduceMotion: reduceMotion) }
            .animation(motion, value: intro.isExpanded)
    }

    /// The card, transformed so it grows out of the chip and returns into it.
    ///
    /// The transform is computed from the two measured frames rather than left
    /// to a matched-geometry effect, because this has to be exact in both
    /// directions and cancellable at any point without stranding the card
    /// somewhere between the two. Scale and offset are used rather than an
    /// animated frame so the travel stays a GPU transform and never relayouts
    /// the Lottie mid-flight.
    private var card: some View {
        StreakIntroCard(
            streak: streak,
            metrics: metrics,
            cornerRadius: intro.isExpanded ? metrics.cornerRadius : collapsedRadius,
            isAnimated: !reduceMotion,
            showsClose: intro.showsCloseButton,
            onClose: { intro.close(reduceMotion: reduceMotion) }
        )
        .shadow(
            color: .black.opacity(intro.isExpanded ? 0.16 : 0.04),
            radius: intro.isExpanded ? 38 : 10,
            y: intro.isExpanded ? 16 : 4
        )
        .scaleEffect(intro.isExpanded ? 1 : collapsedScale, anchor: .center)
        .offset(collapsedOffset)
        .animation(motion, value: intro.isExpanded)
        .opacity(intro.isExpanded ? 1 : 0)
        // Quick in, and late out — the card holds full opacity for most of the
        // journey home so it reads as absorbed into the capsule rather than
        // faded out somewhere next to it.
        .animation(cardFade, value: intro.isExpanded)
        // Swallows taps so they never reach the scrim behind it.
        .onTapGesture { }
        .allowsHitTesting(intro.isInteractive)
    }

    private var motion: Animation {
        if reduceMotion {
            return intro.isExpanded
                ? StreakIntroController.reducedExpand
                : StreakIntroController.reducedCollapse
        }
        return intro.isExpanded ? StreakIntroController.expand : StreakIntroController.collapse
    }

    private var cardFade: Animation {
        intro.isExpanded
            ? .easeOut(duration: 0.18)
            : .easeIn(duration: 0.22).delay(0.26)
    }

    /// How small the card is when it is sitting inside the chip.
    ///
    /// Under Reduce Motion it barely shrinks: the card appears at the centre
    /// and stays there, so there is no long diagonal journey to follow.
    private var collapsedScale: CGFloat {
        guard isMeasured else { return 1 }
        guard !reduceMotion else { return 0.94 }
        return chipFrame.width / metrics.size.width
    }

    /// The card's own corner radius while collapsed.
    ///
    /// Scaled up by the inverse of `collapsedScale`, because `scaleEffect`
    /// shrinks the rendered corners too — without this the card would arrive at
    /// the chip looking like a tiny rounded rectangle instead of a capsule.
    private var collapsedRadius: CGFloat {
        guard isMeasured, !reduceMotion, collapsedScale > 0 else { return metrics.cornerRadius }
        return (chipFrame.height / 2) / collapsedScale
    }

    /// Where the card sits when collapsed: exactly over the chip.
    private var collapsedOffset: CGSize {
        guard !reduceMotion, !intro.isExpanded, isMeasured else { return .zero }

        let cardCentre = CGPoint(x: rootFrame.midX, y: rootFrame.midY - Self.opticalCentreLift)
        return CGSize(
            width: chipFrame.midX - cardCentre.x,
            height: chipFrame.midY - cardCentre.y
        )
    }

    // MARK: - Actions

    private func select(_ day: Date) {
        guard day != selectedDay else { return }
        Haptics.selection()
        selectedDay = day
        bringIntoComfortableView(day)
    }

    /// Nudges the strip only when the tapped day is sitting on an edge.
    ///
    /// Re-centring on every tap would fight the user: they can see where they
    /// tapped, and moving it under their finger reads as the app disagreeing
    /// with them.
    private func bringIntoComfortableView(_ day: Date) {
        guard let leadingDay,
              let leadingOffset = window.offset(of: leadingDay),
              let dayOffset = window.offset(of: day)
        else { return }

        let position = dayOffset - leadingOffset
        let lastVisible = CalendarStripView.defaultVisibleDays - 1
        guard position <= 0 || position >= lastVisible else { return }

        let target = window.date(byAdding: -(lastVisible / 2), to: day)
        withAnimation(.easeInOut(duration: 0.3)) {
            self.leadingDay = target
        }
    }

    private func rebuildIndex() {
        index = DayStatusIndex(
            log: store.log,
            events: store.events,
            trainingDays: store.schedule.trainingDays
        )
    }
}
