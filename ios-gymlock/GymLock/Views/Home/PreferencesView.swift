import SwiftUI

/// Preferences, reached from Profile.
///
/// One setting for now: Time to Gym. It is the same stored value the Alarm
/// screen and the day dial edit, written through `MorningPlan.setTimeToGym`,
/// so there is one number and one rule wherever it is changed.
struct PreferencesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        TimeToGymEditor()
                    } label: {
                        LabeledContent("Time to Gym") {
                            Text("\(store.plan.rhythm.currentTimeToGymMinutes) min")
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .accessibilityHint("Opens the time to gym picker")
                } header: {
                    Text("Gym Routine")
                } footer: {
                    Text("Includes getting ready and traveling.")
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// The Time to Gym picker: Apple's wheel in 5-minute steps, plus the presets.
private struct TimeToGymEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    @State private var alarmSync: Task<Void, Never>?

    private static let values = Array(
        stride(
            from: MorningRhythm.timeToGymRange.lowerBound,
            through: MorningRhythm.timeToGymRange.upperBound,
            by: MorningRhythm.timeToGymStep
        )
    )

    private var rhythm: MorningRhythm { store.plan.rhythm }

    var body: some View {
        List {
            Section {
                Picker("Time to Gym", selection: minutesBinding) {
                    ForEach(Self.values, id: \.self) { minutes in
                        Text("\(minutes) min")
                            .monospacedDigit()
                            .tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            } footer: {
                Text("Includes getting ready and traveling.")
            }
            .listRowBackground(Theme.surface)

            Section {
                PresetChips(
                    label: "presets",
                    values: MorningRhythm.timeToGymPresets,
                    selection: minutesBinding
                )
                .padding(.vertical, 4)
            }
            .listRowBackground(Theme.surface)

            if store.plan.hasMorningSessions || !store.plan.enabledSlots.isEmpty {
                Section {
                    LabeledContent(
                        rhythm.flowMode == .wakeAndGo ? "alarm" : "time to go",
                        value: rhythm.lockAlarmTime.displayString
                    )
                    LabeledContent("at gym by", value: rhythm.gymByTime.displayString)
                } footer: {
                    Text(rhythm.flowMode == .wakeAndGo
                        ? "your gym time moves with it."
                        : "your gym time stays put. the time to go alarm moves.")
                }
                .monospacedDigit()
                .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Time to Gym")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { store.plan.rhythm.currentTimeToGymMinutes },
            set: { minutes in
                guard minutes != store.plan.rhythm.currentTimeToGymMinutes else { return }
                Haptics.selection()
                var plan = store.plan
                plan.setTimeToGym(minutes)
                store.plan = plan
                // The alarm the OS holds follows, but not once per detent of
                // a spin. Same path as the Alarm screen.
                alarmSync?.cancel()
                alarmSync = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    await coordinator.syncAlarms()
                }
            }
        )
    }
}

#Preview("Preferences") {
    PreferencesView()
        .environment(AppStore())
}
