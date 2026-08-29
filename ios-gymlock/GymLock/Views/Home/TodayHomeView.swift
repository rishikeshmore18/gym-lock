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

    /// Geometry for the morph, in global space. `chipFrame` is the visible
    /// capsule, not its touch target.
    @State private var rootFrame: CGRect = .zero
    @State private var chipFrame: CGRect = .zero

    /// One value driving every squeeze the bubble makes: the press, the release
    /// rebound, and the absorb when the card comes home. Shared by the capsule
    /// in the header and by the surface expanding out of it, so the two can
    /// never disagree about how compressed the bubble currently is.
    @State private var bubbleScale: CGFloat = 1
    @State private var bubbleSettle: Task<Void, Never>?

    /// Nudge above true centre. A card sitting on the exact midpoint reads as
    /// slightly low, because the eye weights the top of a screen more heavily.
    private static let opticalCentreLift: CGFloat = 18

    /// How dark home goes behind the card. Home is still clearly there, but it
    /// has stopped competing: the flame and the number are the only things with
    /// any brightness left.
    private static let scrimOpacity: Double = 0.40

    /// The press, and the rebound past resting that follows it. High damping on
    /// the way back — a soft bubble, not a toy.
    private static let bubblePress: Animation = .easeOut(duration: 0.13)
    private static let bubbleRelease: Animation = .spring(response: 0.17, dampingFraction: 0.62)
    private static let bubbleReturn: Animation = .spring(response: 0.24, dampingFraction: 0.9)

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
        .onChange(of: intro.absorbPulse) { _, _ in absorbCard() }
        .onChange(of: leadingDay) { _, day in
            guard let day else { return }
            window.extend(reaching: day)
        }
        .onChange(of: store.log) { _, _ in rebuildIndex() }
        .onChange(of: store.events) { _, _ in rebuildIndex() }
        .onChange(of: store.schedule.trainingDays) { _, _ in rebuildIndex() }
        .onDisappear {
            bubbleSettle?.cancel()
            bubbleScale = 1
        }
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
    /// hands over to the morph, and the logo would visibly drift. The reserved
    /// copy is also what gets measured: it is never scaled, so the geometry the
    /// card animates to stays still while the bubble is being squeezed.
    private var streakSlot: some View {
        ZStack {
            StreakChip(streak: streak, onCapsuleFrame: { chipFrame = $0 })
                .hidden()

            StreakChip(
                streak: streak,
                onTap: { intro.open(reduceMotion: reduceMotion) },
                onPressChange: bubblePressChanged
            )
            // Handed over the instant the morph takes its place, with no fade
            // in either direction: the morph draws the identical capsule at the
            // identical position, so the swap has nothing to show.
            .opacity(isChipHidden ? 0 : 1)
            .disabled(intro.isMounted)
            .scaleEffect(bubbleScale)
        }
    }

    /// Under Reduce Motion the card does not travel, so the capsule stays where
    /// it is rather than disappearing for no visible reason.
    private var isChipHidden: Bool { intro.isMounted && !reduceMotion }

    // MARK: - Streak presentation

    /// The dimmed home, and the capsule on its way to becoming the card.
    ///
    /// Mounted only while the streak is out, so there is no scrim and no Lottie
    /// player left in the hierarchy the rest of the time.
    ///
    /// Four layers, all pinned to the same travelling rectangle: the surface,
    /// which is the bubble itself growing; the capsule's own contents, which
    /// fade out as it opens; and the card's contents, which fade in. Nothing
    /// here appears or disappears independently of the surface — that is the
    /// whole point.
    @ViewBuilder
    private var streakOverlay: some View {
        if intro.isMounted {
            ZStack {
                scrim
                surface
                capsuleContents
                cardContents
            }
        }
    }

    /// A flat colour rather than a blur of the whole screen. It costs one
    /// composited layer instead of a full-screen effect recomputing every frame
    /// while the calendar is alive underneath, and at this opacity a blur would
    /// not read any differently.
    ///
    /// Animated by the same transaction that moves the card, so the room dims
    /// exactly as fast as the card arrives.
    private var scrim: some View {
        Color.black
            .opacity(intro.isExpanded ? Self.scrimOpacity : 0)
            .ignoresSafeArea()
            .onTapGesture { intro.close(reduceMotion: reduceMotion) }
            // Only a card the user opened is dismissible by tapping away from
            // it. During the automatic entrance this layer is invisible to
            // touches, so home stays usable straight through it.
            .allowsHitTesting(intro.isInteractive)
    }

    /// The bubble, at whatever size it currently is.
    ///
    /// This single view is the capsule at one end and the card at the other.
    /// Its frame and its corner radius interpolate together, so the capsule
    /// visibly grows and squares off into a card rather than being swapped for
    /// one.
    private var surface: some View {
        RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
            .fill(Theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            // No shadow at capsule size: the capsule draws its own, and two
            // would show as a smudge at the moment of handover.
            .shadow(
                color: .black.opacity(intro.isExpanded ? 0.18 : 0),
                radius: intro.isExpanded ? 40 : 6,
                y: intro.isExpanded ? 18 : 2
            )
            .frame(width: surfaceRect.width, height: surfaceRect.height)
            // Swallows taps so a tap on the card never reaches the scrim.
            .contentShape(.rect)
            .onTapGesture { }
            .allowsHitTesting(intro.isInteractive)
            .scaleEffect(bubbleScale)
            .position(x: surfaceRect.midX, y: surfaceRect.midY)
    }

    /// The flame icon and number the capsule shows at rest, drawn inside the
    /// growing surface.
    ///
    /// Without this the surface would be an empty white capsule for the first
    /// frames of the expansion, which is the one moment the illusion has to
    /// hold. It is also what the surface is showing when it lands, so the
    /// header's real capsule can be handed back without a crossfade.
    private var capsuleContents: some View {
        StreakChip(streak: streak)
            .opacity(intro.isExpanded || reduceMotion ? 0 : 1)
            .animation(capsuleFade, value: intro.isExpanded)
            .scaleEffect(capsuleScale * bubbleScale)
            .position(x: surfaceRect.midX, y: surfaceRect.midY)
            .allowsHitTesting(false)
    }

    private var cardContents: some View {
        StreakCardContent(
            streak: streak,
            metrics: metrics,
            isAnimated: !reduceMotion,
            showsClose: intro.showsCloseButton,
            onClose: { intro.close(reduceMotion: reduceMotion) }
        )
        .opacity(intro.isExpanded ? 1 : 0)
        .animation(contentFade, value: intro.isExpanded)
        // Scaled rather than laid out at each size: the flame is a rendered
        // composition, and re-laying it out on every frame of the travel is the
        // one thing here that would actually cost frames.
        .scaleEffect(contentScale * bubbleScale)
        .position(x: surfaceRect.midX, y: surfaceRect.midY)
        // Only the close button takes touches; everything else falls through to
        // the surface underneath.
        .allowsHitTesting(intro.isInteractive)
    }

    // MARK: - Morph geometry

    /// The capsule, in this view's coordinates.
    private var localChipRect: CGRect {
        CGRect(
            x: chipFrame.minX - rootFrame.minX,
            y: chipFrame.minY - rootFrame.minY,
            width: chipFrame.width,
            height: chipFrame.height
        )
    }

    private var expandedRect: CGRect {
        CGRect(
            x: (rootFrame.width - metrics.size.width) / 2,
            y: (rootFrame.height - metrics.size.height) / 2 - Self.opticalCentreLift,
            width: metrics.size.width,
            height: metrics.size.height
        )
    }

    /// Where the surface is right now.
    ///
    /// Under Reduce Motion there is no journey across the screen: the card
    /// arrives where it will stay, a fraction under size, and grows into place.
    private var surfaceRect: CGRect {
        guard !intro.isExpanded, isMeasured else { return expandedRect }
        guard !reduceMotion else {
            return expandedRect.insetBy(
                dx: expandedRect.width * 0.03,
                dy: expandedRect.height * 0.03
            )
        }
        return localChipRect
    }

    private var surfaceRadius: CGFloat {
        guard !intro.isExpanded, isMeasured, !reduceMotion else { return metrics.cornerRadius }
        return localChipRect.height / 2
    }

    private var contentScale: CGFloat {
        max(surfaceRect.width / metrics.size.width, 0.01)
    }

    /// The capsule's contents grow a little with the surface so they read as
    /// attached to it, but they are gone long before the scale would matter.
    private var capsuleScale: CGFloat {
        guard isMeasured, localChipRect.width > 0 else { return 1 }
        return min(max(surfaceRect.width / localChipRect.width, 1), 1.6)
    }

    private var contentFade: Animation {
        intro.isExpanded
            ? .easeOut(duration: 0.26).delay(0.14)
            : .easeIn(duration: 0.16)
    }

    /// Out quickly as the bubble opens; back only once the card is nearly home,
    /// so there is never a moment showing two streaks at once.
    private var capsuleFade: Animation {
        let timing = reduceMotion
            ? StreakIntroController.Timing.reducedMotion
            : StreakIntroController.Timing.standard

        return intro.isExpanded
            ? .easeIn(duration: 0.12)
            : .easeOut(duration: 0.16).delay(Double(timing.collapseTravel) / 1000 * 0.45)
    }

    // MARK: - Bubble physics

    /// Compress on the way down, rebound a little past resting on the way up.
    ///
    /// The rebound is what makes the card look like it was released rather than
    /// launched: the bubble is already springing back as the surface begins to
    /// grow out of it.
    private func bubblePressChanged(_ isPressed: Bool) {
        bubbleSettle?.cancel()

        guard !isPressed else {
            Haptics.tap()
            withAnimation(Self.bubblePress) { bubbleScale = 0.92 }
            return
        }

        withAnimation(Self.bubbleRelease) { bubbleScale = 1.02 }
        bubbleSettle = Task {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(Self.bubbleReturn) { bubbleScale = 1 }
        }
    }

    /// The capsule opening to take the card back, then closing around it.
    ///
    /// Runs across the handover on purpose — it starts while the morph is still
    /// mounted and finishes on the real capsule, and because both are driven by
    /// the same value the swap in the middle is invisible.
    private func absorbCard() {
        bubbleSettle?.cancel()
        withAnimation(.easeOut(duration: 0.09)) { bubbleScale = 1.05 }

        bubbleSettle = Task {
            try? await Task.sleep(for: .milliseconds(95))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.08)) { bubbleScale = 0.98 }

            try? await Task.sleep(for: .milliseconds(85))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) { bubbleScale = 1 }
        }
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
