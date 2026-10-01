import SwiftUI

/// Routes between the onboarding journey, the morning setup, and home.
///
/// A live morning takes over everything. Whatever the user was doing, the alarm
/// firing means the only thing on screen is the decision — which is the entire
/// point of an app that promises to interrupt.
struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.scenePhase) private var scenePhase

    /// Once per process. Read directly rather than through the environment so
    /// it exists from the very first frame, before anything is injected.
    private var launchCover: LaunchCover { .shared }

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
            app
                // Mounted and preparing from the first frame, but kept from
                // VoiceOver until the cover lifts.
                .accessibilityHidden(launchCover.isHoldingApp)

            if launchCover.isVisible {
                GymLockLaunchIntroView(phase: launchCover.phase)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.light)
        // Driven entirely by the session state: the flow dismisses itself when
        // the coordinator ends the morning, and there is no separate
        // presentation flag able to disagree with it.
        .fullScreenCover(isPresented: isMorningLive) {
            MorningFlowView()
        }
        // Someone answering an alarm never waits on branding.
        .onChange(of: coordinator.isSessionLive, initial: true) { _, isLive in
            if isLive { launchCover.yieldToMorning() }
        }
        // Left mid-intro: come back to the app, never to a replay.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { launchCover.finishImmediately() }
        }
        .task {
            // Home reports its own readiness once it has settled. The other
            // stages are ready as soon as they are mounted.
            if store.stage != .home { launchCover.contentIsReady() }
        }
    }

    private var app: some View {
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
    }
}

#Preview {
    ContentView()
        .environment(AppStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .environment(GymSessionCoordinator(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .environment(AlarmSoundPlayer())
}
