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

    private var launchCover: LaunchCover { .shared }

    var body: some View {
        ZStack {
            destination(.home) {
                TodayHomeView(intro: intro, coordinator: coordinator)
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
        .environment(\.rootTabBarMinY, tabBarMinY)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RootTabBar(selection: $selection)
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
        // Black rather than coral: on this screen coral means a skipped day,
        // and a coral tab would be competing with that.
        .tint(Theme.ink)
        .onChange(of: selection) { _, tab in
            // Leaving home resets the streak to compact at once. There is no
            // point animating a collapse onto a screen nobody is looking at,
            // and it guarantees the next tab never inherits a dimmed backdrop,
            // a running flame, or a close button floating over it.
            if tab != .home { intro.normalizeImmediately() }
        }
        // A notification tap asked for a tab (the workout-done line lands on
        // Progress with its spotlight). The spotlight is armed before the tab
        // changes, in the same update, so the first frame of Progress anyone
        // sees is already dimmed. Initial, so a cold launch that asked before
        // this view existed is still honoured.
        .onChange(of: coordinator.requestedTab, initial: true) { _, tab in
            guard let tab else { return }
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
                // Under the launch cover the entrance waits; home starts it
                // itself once the cover lifts.
                intro.sceneBecameActive(
                    streak: store.streak.weeks,
                    reduceMotion: reduceMotion,
                    isHomeVisible: selection == .home && !launchCover.isHoldingApp
                )
            } else {
                intro.sceneLeftForeground()
            }
        }
        .onChange(of: launchCover.isHoldingApp) { _, isHolding in
            if !isHolding { presentLaunchPrompts() }
        }
        .sheet(isPresented: $isAskingToAddGymDay) {
            AddGymDaySheet(
                onChange: { effects in
                    if effects.contains(.resyncGymAlarms) {
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
                intro.resume(streak: store.streak.weeks, reduceMotion: reduceMotion)
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
        }
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
