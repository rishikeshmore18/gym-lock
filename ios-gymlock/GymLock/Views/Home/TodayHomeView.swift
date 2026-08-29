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

    /// Distance from the top of the screen to the expanded card.
    private static let cardTopInset: CGFloat = 76

    private var streak: Int { store.log.momentumStreak }

    private var isMeasured: Bool { rootFrame.width > 0 && chipFrame.width > 0 }

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

            introOverlay
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rootFrame = $0 }
        .task {
            rebuildIndex()
            if leadingDay == nil {
                leadingDay = window.defaultLeadingDay(visibleDays: CalendarStripView.defaultVisibleDays)
            }
            withAnimation(.easeOut(duration: 0.28)) { hasSettled = true }
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
        HStack(spacing: 10) {
            Image("GymLockLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(.rect(cornerRadius: 9))
                .accessibilityHidden(true)

            Text("GymLock")
                .font(.system(size: 25, weight: .bold))
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

            StreakChip(streak: streak)
                .opacity(intro.isExpanded ? 0 : 1)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    chipFrame = $0
                }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.18),
                   value: intro.isExpanded)
    }

    // MARK: - Streak entrance

    /// The expanded card, positioned so it grows out of the chip and returns
    /// into it.
    ///
    /// The transform is computed from the two measured frames rather than left
    /// to a matched-geometry effect, because this needs to be exact in both
    /// directions and cancellable at any point without stranding the card
    /// somewhere between the two.
    @ViewBuilder
    private var introOverlay: some View {
        if intro.isMounted {
            VStack(spacing: 0) {
                StreakIntroCard(streak: streak, isAnimated: !reduceMotion)
                    .scaleEffect(intro.isExpanded ? 1 : collapsedScale, anchor: .center)
                    .offset(collapsedOffset)
                    .opacity(intro.isExpanded ? 1 : 0)
                    .padding(.top, Self.cardTopInset)

                Spacer(minLength: 0)
            }
            // Never blocks the screen: the user can scroll the calendar or
            // switch tabs straight through it while it plays.
            .allowsHitTesting(false)
        }
    }

    /// How small the card is when it is sitting inside the chip.
    private var collapsedScale: CGFloat {
        guard !reduceMotion, chipFrame.width > 0 else { return 1 }
        return chipFrame.width / StreakIntroCard.size.width
    }

    /// Where the card sits when collapsed: exactly over the chip.
    private var collapsedOffset: CGSize {
        guard !reduceMotion, intro.isExpanded == false, isMeasured else { return .zero }

        let cardCenter = CGPoint(
            x: rootFrame.midX,
            y: rootFrame.minY + Self.cardTopInset + StreakIntroCard.size.height / 2
        )
        return CGSize(
            width: chipFrame.midX - cardCenter.x,
            height: chipFrame.midY - cardCenter.y
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
