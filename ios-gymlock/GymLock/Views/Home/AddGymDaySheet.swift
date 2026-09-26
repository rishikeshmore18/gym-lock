import SwiftUI

// PLACEHOLDER UI: designed in Step 3
/// Asks an existing user with 1 or 2 gym days to add one (FLOW, "Existing
/// user with only 1–2 gym days"). Closes by itself once they have 3; "not
/// now" closes it and it asks again on the next open.
struct AddGymDaySheet: View {
    let onChange: (MorningPlan.DayEditEffects) -> Void
    let onDismiss: () -> Void

    @Environment(AppStore.self) private var store

    @State private var note: String?
    @State private var noteDismissal: Task<Void, Never>?

    private var gymDays: Set<Weekday> { store.plan.gymDays }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("add a gym day")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(StreakPolicy.minimumGymDaysMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(Weekday.allCases) { day in
                        dayCircle(day)
                    }
                }

                if let note {
                    Text(note)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .warmCard(radius: 18)

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Text("not now")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onDisappear { noteDismissal?.cancel() }
    }

    private func dayCircle(_ day: Weekday) -> some View {
        let isOn = gymDays.contains(day)

        return Button {
            toggle(day)
        } label: {
            Text(String(day.shortLabel.prefix(1)))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isOn ? Color.white : Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isOn ? Theme.ink : Theme.surfaceMuted, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.shortLabel)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggle(_ day: Weekday) {
        let result = store.plan.toggleGymDay(day, newAlarmTime: store.plan.rhythm.wakeTime)
        switch result.outcome {
        case .updated:
            Haptics.selection()
            note = nil
        case .belowMinimum:
            Haptics.soft()
            showNote(StreakPolicy.minimumGymDaysMessage)
        }
        onChange(result.effects)

        if !StreakPolicy.asksToAddGymDay(plannedGymDays: store.plan.gymDays.count) {
            onDismiss()
        }
    }

    private func showNote(_ message: String) {
        note = message
        AccessibilityNotification.Announcement(message).post()
        noteDismissal?.cancel()
        noteDismissal = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            note = nil
        }
    }
}
