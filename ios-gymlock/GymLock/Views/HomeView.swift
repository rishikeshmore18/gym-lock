import SwiftUI

/// The post-onboarding home. Shows the two locks the user committed to and
/// today's state, so the commitment made in onboarding stays visible.
struct HomeView: View {
    @Environment(AppStore.self) private var store

    @State private var isShowingSchedule = false

    private var isTrainingDayToday: Bool {
        let weekdayNumber = Calendar.current.component(.weekday, from: Date())
        guard let today = Weekday(rawValue: weekdayNumber) else { return false }
        return store.schedule.trainingDays.contains(today)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        greeting
                            .padding(.bottom, 4)

                        statusCard
                        locksCard
                        consistencyCard
                        principleCard
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSchedule = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Edit your locks")
                }
            }
            .sheet(isPresented: $isShowingSchedule) {
                ScheduleEditSheet()
            }
        }
        .tint(Theme.accent)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("hi, \(store.greetingName).")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(
                isTrainingDayToday
                    ? "today is a training day."
                    : "no training scheduled today. rest properly."
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, 8)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: isTrainingDayToday ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        isTrainingDayToday ? Theme.accent : Theme.inkTertiary,
                        in: .circle
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(isTrainingDayToday ? "apps locked" : "apps unlocked")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(
                        isTrainingDayToday
                            ? "verify the gym to unlock"
                            : "nothing to verify today"
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                }

                Spacer()
            }

            if isTrainingDayToday {
                Divider().overlay(Theme.border)

                VStack(alignment: .leading, spacing: 12) {
                    verificationRow(
                        icon: "location.fill",
                        title: "location",
                        detail: "confirms you were at the gym"
                    )
                    verificationRow(
                        icon: "heart.fill",
                        title: "Apple Health",
                        detail: "confirms a workout was logged"
                    )
                }
            }
        }
        .padding(20)
        .warmCard()
    }

    private func verificationRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accent.opacity(0.11), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()

            Text("pending")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    private var locksCard: some View {
        VStack(spacing: 0) {
            lockRow(
                icon: "dumbbell.fill",
                title: "gym time",
                value: store.schedule.gymTime.displayString,
                subtitle: store.schedule.daysSummary
            )

            Divider().overlay(Theme.border).padding(.vertical, 16)

            lockRow(
                icon: "moon.fill",
                title: "bedtime",
                value: store.schedule.bedtime.displayString,
                subtitle: "apps lock again at night"
            )
        }
        .padding(20)
        .warmCard()
    }

    private func lockRow(icon: String, title: String, value: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.11), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()

            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
    }

    /// Consistency, framed as history rather than as a streak to protect.
    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            IllustrationView(illustration: .calendarMarking, cornerRadius: 18)
                .frame(maxHeight: 168)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text("your history")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("every verified session gets marked here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
        }
        .padding(20)
        .warmCard()
    }

    private var principleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("no guilt. no streak-shaming.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("miss a day and GymLock makes coming back easier, not heavier.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: Theme.cardRadius))
    }
}

/// Lets the user revisit the two locks after onboarding.
private struct ScheduleEditSheet: View {
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
