import SwiftUI

/// The one-time setup that runs after activation.
///
/// Four steps, and deliberately no more. Everything here is something GymLock
/// genuinely cannot work out on its own, and each one is asked exactly once:
///
/// 1. **Sleep rhythm** — skipped entirely for evening-only trainers.
/// 2. **Morning plan** — a review of what onboarding already worked out.
/// 3. **Gym** — the single piece of configuration that makes arrival automatic.
/// 4. **Blocked apps** — Apple's picker, which the app is not allowed to skip.
///
/// After this the user should never be asked to configure anything again. They
/// do not start workouts, pick exercises, confirm arrival, or log durations. The
/// product's whole promise is set up once, then get out of the way.
struct MorningSetupFlowView: View {
    let onFinish: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    @State private var step: Step = .rhythm

    private enum Step {
        case rhythm
        case plan
        case gym
        case blockedApps
    }

    var body: some View {
        ZStack {
            switch step {
            case .rhythm:
                SleepWakeRhythmView(
                    onUse: { rhythm in
                        store.plan.rhythm = rhythm
                        store.applyRhythmToNightLock()
                        advance(from: .rhythm)
                    },
                    onSkip: { advance(from: .rhythm) }
                )
                .transition(.opacity)

            case .plan:
                MorningAlarmPlanView(onSave: { advance(from: .plan) })
                    .transition(.opacity)

            case .gym:
                GymPickerView(
                    onPicked: { gym in
                        store.primaryGym = gym
                        coordinator.armArrivalIfPossible()
                        // Asked here rather than at launch, because this is the
                        // first moment the reason for it is obvious.
                        coordinator.arrival.requestAlways()
                        advance(from: .gym)
                    },
                    onSkip: { advance(from: .gym) }
                )
                .transition(.opacity)

            case .blockedApps:
                BlockedAppsSetupView(
                    onDone: { finish() },
                    onSkip: { finish() }
                )
                .transition(.opacity)
            }
        }
        .animation(Theme.settle, value: step)
        .task { start() }
    }

    // MARK: - Navigation

    private func start() {
        store.seedPlanIfNeeded()
        step = store.plan.hasMorningSessions ? .rhythm : .plan
    }

    private func advance(from current: Step) {
        let next: Step

        switch current {
        case .rhythm:
            next = .plan
        case .plan:
            // Neither of the last two steps is asked twice. Someone who already
            // picked a gym and a blocklist walks straight out of setup.
            if store.primaryGym == nil {
                next = .gym
            } else if !store.hasConfiguredBlockedApps {
                next = .blockedApps
            } else {
                finish()
                return
            }
        case .gym:
            guard !store.hasConfiguredBlockedApps else {
                finish()
                return
            }
            next = .blockedApps
        case .blockedApps:
            finish()
            return
        }

        withAnimation(Theme.settle) { step = next }
    }

    private func finish() {
        Task {
            // Health is requested last and never blocks anything. A user who
            // declines it, or has no watch, gets an identical morning minus one
            // optional tick.
            await coordinator.requestHealthAuthorization()
        }
        onFinish()
    }
}
