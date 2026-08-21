import SwiftUI

/// Routes between the onboarding journey and the main app shell.
///
/// Onboarding is only ever shown to a user who has not finished it. Once
/// `onboardingCompleted` is written, every later launch opens straight into the
/// app — the twenty-nine screens are a one-time build, not a daily toll.
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            if store.onboardingCompleted {
                HomeShell()
                    .transition(.opacity)
            } else {
                switch store.stage {
                case .onboarding:
                    OnboardingFlowView()
                        .transition(.opacity)
                case .scheduleSetup:
                    ScheduleSetupView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                case .home:
                    HomeShell()
                        .transition(.opacity)
                }
            }
        }
        .animation(Theme.settle, value: store.stage)
        .animation(Theme.settle, value: store.onboardingCompleted)
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
        .environment(AppStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}
