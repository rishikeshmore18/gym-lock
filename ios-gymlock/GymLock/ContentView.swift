import SwiftUI

/// Routes between the onboarding journey, the morning setup, and home.
///
/// A live morning takes over everything. Whatever the user was doing, the alarm
/// firing means the only thing on screen is the decision — which is the entire
/// point of an app that promises to interrupt.
struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    private var isMorningLive: Binding<Bool> {
        Binding(
            get: { coordinator.isSessionLive },
            set: { isPresented in
                guard !isPresented else { return }
                coordinator.endSession()
            }
        )
    }

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
                // The new home is the default destination, for people finishing
                // onboarding and for everyone who already has. The previous home
                // is still here, unchanged, on its own tab.
                RootTabView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.settle, value: store.stage)
        .preferredColorScheme(.light)
        // Driven entirely by the session state: the flow dismisses itself when
        // the coordinator ends the morning, and there is no separate
        // presentation flag able to disagree with it.
        .fullScreenCover(isPresented: isMorningLive) {
            MorningFlowView()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .environment(GymSessionCoordinator(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .environment(AlarmSoundPlayer())
}
