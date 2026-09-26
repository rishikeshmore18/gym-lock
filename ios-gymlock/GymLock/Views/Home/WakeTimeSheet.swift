import SwiftUI

// PLACEHOLDER UI: designed in Step 3
/// Asks an existing user whose stored wake time was really their gym alarm
/// when they actually wake up. Their wake time sits at 07:00 until they
/// answer; swiping away asks again on the next open.
struct WakeTimeSheet: View {
    let onAnswered: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var wake: TimeOfDay = OnboardingProfile.defaultWakeTime

    private var meetsSleepMinimum: Bool {
        MorningRhythm.meetsSleepMinimum(bedtime: store.plan.scheduledRhythm.bedtime, wake: wake)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("when do you wake up?")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 28)

            TimeWheel(time: $wake, accessibilityTitle: "Wake time")
                .frame(height: 150)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .warmCard(radius: 18)

            if !meetsSleepMinimum {
                Text(MorningRhythm.sleepMinimumMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 0)

            MorningPrimaryButton(title: "save", systemImage: "checkmark", isEnabled: meetsSleepMinimum) {
                store.answerWakeTime(wake)
                onAnswered()
                dismiss()
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.pageMargin)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { wake = store.plan.rhythm.wakeTime }
    }
}
