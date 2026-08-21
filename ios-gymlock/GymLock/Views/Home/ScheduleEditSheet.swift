import SwiftUI

/// Lets the user revisit the two locks they committed to during onboarding.
struct ScheduleEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var gymTime = Date()
    @State private var bedtime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("gym time") {
                    DatePicker("alarm", selection: $gymTime, displayedComponents: .hourAndMinute)
                    ForEach(Weekday.allCases) { day in
                        Toggle(
                            day.shortLabel,
                            isOn: Binding(
                                get: { store.schedule.trainingDays.contains(day) },
                                set: { _ in store.toggleTrainingDay(day) }
                            )
                        )
                    }
                }

                Section("bedtime") {
                    DatePicker("lock again until", selection: $bedtime, displayedComponents: .hourAndMinute)
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Your locks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                gymTime = store.schedule.gymTime.asDateToday
                bedtime = store.schedule.bedtime.asDateToday
            }
            .onChange(of: gymTime) { _, newValue in
                store.schedule.gymTime = TimeOfDay(from: newValue)
            }
            .onChange(of: bedtime) { _, newValue in
                store.schedule.bedtime = TimeOfDay(from: newValue)
            }
        }
    }
}
