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

    var body: some View {
        ZStack {
            destination(.home) {
                TodayHomeView(intro: intro, coordinator: coordinator)
            }

            destination(.progress) {
                ProgressTabView()
            }

            destination(.community) {
                CommunityView()
            }

            destination(.profile) {
                ProfileView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RootTabBar(selection: $selection)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // A week may have ended while the app was away; rule on it
                // before the streak is read anywhere on this screen.
                store.refreshStreak()
                intro.sceneBecameActive(
                    streak: store.streak.weeks,
                    reduceMotion: reduceMotion,
                    isHomeVisible: selection == .home
                )
            } else {
                intro.sceneLeftForeground()
            }
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
            guard !store.plan.hasBeenReviewed else { return }
            intro.isSuspended = true
            isRunningSetup = true
        }
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
