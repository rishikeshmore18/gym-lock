import SwiftUI

/// Routes between the onboarding journey, the commitment screen, and home.
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            switch store.stage {
            case .onboarding:
                OnboardingFlowView()
                    .transition(.opacity)
            case .scheduleSetup:
                ScheduleSetupView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .home:
                HomeView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.settle, value: store.stage)
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
        .environment(AppStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}
