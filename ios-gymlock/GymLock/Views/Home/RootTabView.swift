import SwiftUI

/// The top-level navigation shell.
///
/// The destinations are stacked and kept alive rather than swapped, which is
/// what stops the calendar losing its scroll position and the streak entrance
/// replaying every time the user comes back to Home. The bar is installed as a
/// bottom safe area inset, so every scroll view inside every tab still ends
/// above it and content scrolls underneath the glass.
struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: RootTab = .home
    @State private var intro = StreakIntroController()
    @State private var isRunningSetup = false
    @State private var isAskingToAddGymDay = false
    @State private var isAskingForWakeTime = false
    @State private var tabBarMinY: CGFloat = .infinity
    /// The Progress spotlight. Owned here so it is armed in the same update
    /// that selects Progress, and so the tab bar can dim with the page.
    @State private var spotlight = ProgressSpotlightModel()
    /// Bumped on every notification-driven tab request, so screens that
    /// present over the shell can step aside and let the destination show.
    @State private var tabRequestCount = 0
    /// The done flow or a standalone rank-up, waiting out its delay (spec §4.1).
    @State private var celebrationTask: Task<Void, Never>?
    /// A notification tap is bringing the flow up: 300 ms, then the spotlight after the collapse.
    @State private var isFlowFromNotification = false
    @AppStorage(HeroCardStyle.storageKey) private var cardStyleRaw = HeroCardStyle.ridge.rawValue

    private var launchCover: LaunchCover { .shared }
    private var queue: CelebrationQueue { .shared }

    var body: some View {
        ZStack {
            destination(.home) {
                TodayHomeView(intro: intro, coordinator: coordinator, isVisible: selection == .home)
            }

            destination(.progress) {
                ProgressTabView(spotlight: spotlight)
            }

            destination(.community) {
                CommunityView()
            }

            destination(.profile) {
                ProfileView(tabRequestCount: tabRequestCount)
            }
        }
        // The hero stops under anything that covers it (spec §5, step 11).
        .environment(\.heroMotionPaused, isHeroCovered)
        .environment(\.rootTabBarMinY, tabBarMinY)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RootTabBar(selection: $selection, dots: tabDots)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                    tabBarMinY = $0
                }
                // Dimmed with the page under the spotlight. Faded rather than
                // covered, so the glass shapes darken without a dark box
                // around them; the bar sits on the already dark canvas.
                .opacity(spotlight.isActive ? SpotlightDim.chromeOpacity : 1)
                // In the bar's own bounds: while the spotlight is up a tap
                // here only closes it, and never switches tab.
                .overlay {
                    if spotlight.isActive {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture(perform: dismissSpotlight)
                            .accessibilityHidden(true)
                    }
                }
                // Kept from VoiceOver too, so the dimmed bar cannot be reached.
                .accessibilityHidden(spotlight.isActive)
        }
        // The done flow sits above the tabs and the bar, so it can collapse into the card.
        .overlay { DoneFlowHost(queue: queue) }
        // Standalone rank-ups (rule 4): in their own layer, so they finish without flying to a slot
        // on a tab nobody is looking at.
        .overlay {
            Color.clear
                .allowsHitTesting(false)
                .badgeRankUp(standaloneBinding) { queue.standaloneLanded($0) }
        }
        // Black rather than coral: on this screen coral means a skipped day,
        // and a coral tab would be competing with that.
        .tint(Theme.ink)
        .onChange(of: selection) { _, tab in
            // Leaving home resets the streak to compact at once. There is no
            // point animating a collapse onto a screen nobody is looking at,
            // and it guarantees the next tab never inherits a dimmed backdrop,
            // a running flame, or a close button floating over it.
            // Arriving on home is the moment a celebration that was earned
            // elsewhere (a notification that landed on Progress) gets its turn.
            if tab != .home {
                intro.normalizeImmediately()
            } else {
                presentEarnedCelebrationIfNeeded()
            }
        }
        // Every way the gate can open: Home showing, a sheet or the morning gone, the cover lifted.
        .onChange(of: isCelebrationGateOpen) { _, open in
            if open {
                scheduleCelebration(flowDelay: isFlowFromNotification ? 0.3 : 0.7)
            } else {
                celebrationTask?.cancel()
            }
        }
        // A proof landing while Home is already on screen: 1300 ms (spec §4.1).
        .onChange(of: queue.hasPendingFlow) { old, new in
            guard new, !old else { return }
            scheduleCelebration(flowDelay: isCelebrationGateOpen ? 1.3 : 0.7)
        }
        .onChange(of: store.log) { _, _ in
            queue.sync(store: store, coordinator: coordinator)
        }
        .onChange(of: queue.flowEndCount) { _, _ in flowEnded() }
        // A notification tap asked for a tab (the workout-done line lands on
        // Progress with its spotlight). The spotlight is armed before the tab
        // changes, in the same update, so the first frame of Progress anyone
        // sees is already dimmed. Initial, so a cold launch that asked before
        // this view existed is still honoured.
        .onChange(of: coordinator.requestedTab, initial: true) { _, tab in
            guard let tab else { return }
            // The workout-done notification with a flow waiting: Home first, the flow 300 ms later,
            // and the Progress spotlight once it collapses (spec §4.1 N).
            queue.sync(store: store, coordinator: coordinator)
            if tab == .progress, queue.hasPendingFlow, queue.presentation == nil {
                queue.spotlightAfterFlow = coordinator.takePendingSpotlightDay()
                spotlight.dismiss()
                isFlowFromNotification = true
                selection = .home
                tabRequestCount += 1
                coordinator.consumeRequestedTab()
                scheduleCelebration(flowDelay: 0.3)
                return
            }
            if !spotlight.accept(requestedTab: tab, from: coordinator), tab != .progress {
                spotlight.dismiss()
            }
            selection = tab
            tabRequestCount += 1
            coordinator.consumeRequestedTab()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // A week may have ended while the app was away; rule on it
                // before the streak is read anywhere on this screen.
                store.refreshStreak()
                askForWakeTimeIfNeeded()
                askToAddGymDayIfNeeded()
                // Under the launch cover the celebration waits; home starts it
                // itself once the cover lifts.
                intro.sceneBecameActive(
                    streak: store.streak,
                    reduceMotion: reduceMotion,
                    isHomeVisible: isHomeVisible
                )
                HeroHapticPlayer.shared.setBlocked("background", false)
                queue.sync(store: store, coordinator: coordinator)
                // The return plays the launch cover first; a flow stays frozen until it lifts.
                Task { @MainActor in
                    await Task.yield()
                    if !launchCover.isHoldingApp { resumeQueueIfReturning() }
                }
            } else {
                intro.sceneLeftForeground()
                HeroHapticPlayer.shared.setBlocked("background", true)
                if phase == .background {
                    celebrationTask?.cancel()
                    queue.sceneLeftForeground()
                }
            }
        }
        .onChange(of: launchCover.isHoldingApp) { _, isHolding in
            if !isHolding {
                resumeQueueIfReturning()
                presentLaunchPrompts()
                presentEarnedCelebrationIfNeeded()
            }
        }
        .sheet(isPresented: $isAskingToAddGymDay) {
            AddGymDaySheet(
                onChange: { effects in
                    if effects.contains(.resyncAlarms) {
                        Task { await coordinator.syncAlarms() }
                    }
                    if effects.contains(.reconcileWindDown) { coordinator.reconcileWindDown() }
                },
                onDismiss: { isAskingToAddGymDay = false }
            )
        }
        .sheet(isPresented: $isAskingForWakeTime) {
            WakeTimeSheet(onAnswered: {
                coordinator.reconcileWindDown()
            })
        }
        .fullScreenCover(isPresented: $isRunningSetup) {
            MorningSetupFlowView {
                isRunningSetup = false
                intro.resume(streak: store.streak, reduceMotion: reduceMotion, isHomeVisible: isHomeVisible)
                Task {
                    await coordinator.requestAlarmAuthorization()
                    await coordinator.syncAlarms()
                }
            }
        }
        .task {
            // A cold generator is late enough to be felt on the first tick.
            Haptics.prepareSelection()
            Haptics.preparePress()

            // The two morning setup screens run once, immediately after
            // activation, before the first alarm is finalised. This lives at
            // the shell rather than inside a tab so it still runs when the new
            // home is the screen the user lands on.
            store.seedPlanIfNeeded()
            // Suspended at once, so the entrance cannot slip in between the
            // launch cover lifting and the setup flow covering home.
            if !store.plan.hasBeenReviewed { intro.isSuspended = true }
            presentLaunchPrompts()

            // A cold launch is a new foreground session (spec §3.2 rule 1).
            queue.sync(store: store, coordinator: coordinator)
            queue.sceneBecameActive()
            scheduleCelebration(flowDelay: 0.7)
        }
    }

    // MARK: - Celebrations (02-experience-spec §3.2, §4.1)

    private var cardStyle: HeroCardStyle { HeroCardStyle(rawValue: cardStyleRaw) ?? .ridge }

    /// Home is the screen, nothing covers it and nothing else is happening.
    private var isCelebrationGateOpen: Bool {
        selection == .home
            && scenePhase == .active
            && !coordinator.isSessionLive
            && !launchCover.isHoldingApp
            && !isRunningSetup
            && !isAskingToAddGymDay
            && !isAskingForWakeTime
            && !spotlight.isActive
            && !intro.isMounted
    }

    /// Anything over the hero: the flow, a rank-up, a sheet, the setup, the streak card.
    private var isHeroCovered: Bool {
        queue.isCelebrating || isAskingToAddGymDay || isAskingForWakeTime || isRunningSetup || intro.isMounted || spotlight.isActive
    }

    private var tabDots: Set<RootTab> {
        var dots: Set<RootTab> = []
        if queue.showsHomeDot { dots.insert(.home) }
        if queue.showsProgressDot { dots.insert(.progress) }
        return dots
    }

    private var standaloneBinding: Binding<BadgeRankUpRequest?> {
        Binding(get: { queue.standalone }, set: { queue.standalone = $0 })
    }

    /// The flow after `flowDelay`, or a standalone rank-up 1.6 s after Home appears. Re-checks the
    /// gate when the wait ends; the 120 ms after a dismissal is inside every delay.
    private func scheduleCelebration(flowDelay: Double) {
        celebrationTask?.cancel()
        guard isCelebrationGateOpen, queue.presentation == nil, queue.standalone == nil else { return }
        if queue.hasPendingFlow {
            celebrationTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(flowDelay))
                guard !Task.isCancelled, isCelebrationGateOpen else { return }
                if queue.presentFlow(store: store, coordinator: coordinator, style: cardStyle) {
                    intro.normalizeImmediately()
                }
            }
        } else if queue.standaloneCandidate() != nil {
            celebrationTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled, isCelebrationGateOpen else { return }
                queue.presentStandalone()
            }
        }
    }

    /// Back from the background (only once the launch cover has lifted).
    private func resumeQueueIfReturning() {
        guard queue.data.backgroundedAt != nil else { return }
        queue.sceneBecameActive()
        scheduleCelebration(flowDelay: 0.7)
    }

    /// Completed, closed or discarded: the spotlight the notification asked for, else the streak
    /// intro's turn (the flow already showed a kept week, so that one is marked celebrated).
    private func flowEnded() {
        isFlowFromNotification = false
        if store.streak.isThisWeekKept {
            intro.markCelebrated(weekStarting: store.streak.liveWeekStart)
        }
        if let day = queue.spotlightAfterFlow {
            queue.spotlightAfterFlow = nil
            spotlight.arm(day: day)
            selection = .progress
        } else {
            intro.resume(streak: store.streak, reduceMotion: reduceMotion, isHomeVisible: isHomeVisible)
        }
    }

    /// Home is on screen and not behind the launch cover.
    private var isHomeVisible: Bool { selection == .home && !launchCover.isHoldingApp }

    /// Asks for the earned celebration; a no-op unless a kept week is still
    /// owed one and Home is the screen the user is looking at.
    private func presentEarnedCelebrationIfNeeded() {
        intro.presentEarnedCelebrationIfNeeded(
            streak: store.streak,
            reduceMotion: reduceMotion,
            isHomeVisible: isHomeVisible
        )
    }

    private func dismissSpotlight() {
        guard spotlight.isActive else { return }
        withAnimation(ProgressSpotlightModel.dismissAnimation) { spotlight.dismiss() }
    }

    /// The setup flow, or the two questions for existing users. Held until the
    /// launch cover lifts, so nothing slides up over the logo.
    private func presentLaunchPrompts() {
        guard !launchCover.isHoldingApp else { return }
        guard !store.plan.hasBeenReviewed else {
            askForWakeTimeIfNeeded()
            askToAddGymDayIfNeeded()
            return
        }
        guard !isRunningSetup else { return }
        intro.isSuspended = true
        isRunningSetup = true
    }

    /// Existing users with 1 or 2 gym days are asked on every open until
    /// they have 3. Never on top of the setup flow or a live morning.
    private func askToAddGymDayIfNeeded() {
        guard store.shouldAskToAddGymDay, !isRunningSetup, !coordinator.isSessionLive,
              !isAskingForWakeTime, !launchCover.isHoldingApp
        else { return }
        isAskingToAddGymDay = true
    }

    /// Existing users whose wake time was really their gym alarm are asked
    /// "when do you wake up?" on every open until they answer. Asked before
    /// the add-a-day sheet, so only one sheet is ever up.
    private func askForWakeTimeIfNeeded() {
        guard store.shouldAskForWakeTime, !isRunningSetup, !coordinator.isSessionLive,
              !isAskingToAddGymDay, !launchCover.isHoldingApp
        else { return }
        isAskingForWakeTime = true
    }

    /// One destination, permanently mounted and hidden when it is not current.
    ///
    /// Hidden by opacity rather than removed so tab state survives, and made
    /// inert to touches and to VoiceOver so an off-screen tab can never be
    /// tapped or read out through the one on top of it.
    @ViewBuilder
    private func destination(_ tab: RootTab, @ViewBuilder content: () -> some View) -> some View {
        let isCurrent = selection == tab

        content()
            .opacity(isCurrent ? 1 : 0)
            // Its own short crossfade, overriding the bar's spring: a screen
            // whose opacity bounced would read as a flicker. The bar springs,
            // the screen behind it simply changes.
            .animation(.easeInOut(duration: 0.2), value: isCurrent)
            .allowsHitTesting(isCurrent)
            .accessibilityHidden(!isCurrent)
            .zIndex(isCurrent ? 1 : 0)
    }
}
