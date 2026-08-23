import SwiftUI

/// The two configuration screens, shown once after activation.
///
/// They live here rather than inside the onboarding pager on purpose. The story
/// half of onboarding is a continuous argument, and dropping a bedtime dial into
/// the middle of it would break the momentum that argument depends on. These are
/// setup, so they run after the user has already said yes — right before the
/// first morning alarm is finalised.
///
/// The sleep screen is skipped entirely for someone who only trains in the
/// evening. They go straight to the plan, where the same window is expressed as
/// prepare and travel with no mention of bedtime.
struct MorningSetupFlowView: View {
    let onFinish: () -> Void

    @Environment(AppStore.self) private var store
    @State private var step: Step = .rhythm

    private enum Step {
        case rhythm
        case plan
    }

    var body: some View {
        ZStack {
            switch step {
            case .rhythm:
                SleepWakeRhythmView(
                    onUse: { rhythm in
                        store.plan.rhythm = rhythm
                        store.applyRhythmToNightLock()
                        advance()
                    },
                    onSkip: { advance() }
                )
                .transition(.opacity)

            case .plan:
                MorningAlarmPlanView(onSave: onFinish)
                    .transition(.opacity)
            }
        }
        .animation(Theme.settle, value: step)
        .task { start() }
    }

    /// Decides where to begin.
    private func start() {
        store.seedPlanIfNeeded()
        step = store.plan.hasMorningSessions ? .rhythm : .plan
    }

    private func advance() {
        withAnimation(Theme.settle) { step = .plan }
    }
}
