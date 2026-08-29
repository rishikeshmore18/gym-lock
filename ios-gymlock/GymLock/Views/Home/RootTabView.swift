import SwiftUI

/// The four destinations of the main app.
enum RootTab: Hashable {
    case home
    case progress
    case profile
    case home2
}

/// The top-level navigation shell.
///
/// Uses the system `TabView` rather than a hand-drawn bar. On iOS 26 that is
/// already the floating Liquid Glass tab bar, correct down to the selected
/// highlight, and it gets safe areas, Reduce Transparency, Dynamic Type and
/// VoiceOver right without any of it being reimplemented here. It also keeps
/// each tab alive, which is what stops the calendar losing its scroll position
/// and the streak entrance replaying every time the user comes back.
struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: RootTab = .home
    @State private var intro = StreakIntroController()
    @State private var isRunningSetup = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: RootTab.home) {
                TodayHomeView(intro: intro)
            }

            Tab("Progress", systemImage: "chart.bar.fill", value: RootTab.progress) {
                ProgressPlaceholderView()
            }

            Tab("Profile", systemImage: "person.fill", value: RootTab.profile) {
                ProfilePlaceholderView()
            }

            // The existing home, untouched, reached through its own tab.
            Tab("Home 2", systemImage: "square.grid.2x2.fill", value: RootTab.home2) {
                HomeView()
            }
        }
        // Black rather than coral: on this screen coral means a skipped day,
        // and a coral tab would be competing with that.
        .tint(Theme.ink)
        .onChange(of: selection) { _, tab in
            // Leaving home ends the entrance cleanly rather than letting it
            // finish against a screen nobody is looking at.
            if tab != .home { intro.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                intro.sceneBecameActive(
                    streak: store.log.momentumStreak,
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
                intro.resume(streak: store.log.momentumStreak, reduceMotion: reduceMotion)
                Task {
                    await coordinator.requestAlarmAuthorization()
                    await coordinator.syncAlarms()
                }
            }
        }
        .task {
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
}
