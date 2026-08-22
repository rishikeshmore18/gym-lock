import SwiftUI

/// The commitment screen reached from "let's lock it in": the user sets the two
/// locks that the whole product depends on.
struct ScheduleSetupView: View {
    @Environment(AppStore.self) private var store

    @State private var gymTime = Date()
    @State private var bedtime = Date()
    @State private var contentShown = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    IllustrationView(illustration: .curlBench, cornerRadius: 26)
                        .frame(maxHeight: 190)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)

                    gymCard
                        .padding(.top, 22)

                    bedtimeCard
                        .padding(.top, 16)

                    Text("we'll lock your distracting apps until you show up, and again at night.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 24)
                .opacity(contentShown ? 1 : 0)
                .offset(y: contentShown ? 0 : 14)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                footer
            }
        }
        .onAppear {
            gymTime = store.schedule.gymTime.asDateToday
            bedtime = store.schedule.bedtime.asDateToday
            withAnimation(Theme.settle) { contentShown = true }
        }
        .onChange(of: gymTime) { _, newValue in
            store.schedule.gymTime = TimeOfDay(from: newValue)
        }
        .onChange(of: bedtime) { _, newValue in
            store.schedule.bedtime = TimeOfDay(from: newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccentedText(
                full: "set your two locks.",
                highlighted: ["two locks."],
                size: 32
            )
            Text("these are the only two rules.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, 12)
    }

    private var gymCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardTitle(icon: "dumbbell.fill", title: "gym time")

            VStack(alignment: .leading, spacing: 10) {
                Text("which days?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)

                dayChips
            }

            Divider().overlay(Theme.border)

            HStack {
                Text("alarm")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                DatePicker("", selection: $gymTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
        }
        .padding(20)
        .warmCard()
    }

    private var dayChips: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let isOn = store.schedule.trainingDays.contains(day)
                Button {
                    Haptics.tap()
                    store.toggleTrainingDay(day)
                } label: {
                    Text(String(day.shortLabel.prefix(1)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOn ? .white : Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            isOn ? Theme.accent : Theme.surfaceMuted,
                            in: .rect(cornerRadius: 12)
                        )
                }
                .buttonStyle(.plain)
                .animation(Theme.stateChange, value: isOn)
                .accessibilityLabel(day.shortLabel)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }

    private var bedtimeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardTitle(icon: "moon.fill", title: "bedtime")

            HStack {
                Text("lock again until")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
        }
        .padding(20)
        .warmCard()
    }

    private func cardTitle(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.11), in: .circle)

            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.commit()
                store.stage = .home
            } label: {
                Text("lock it in")
            }
            .buttonStyle(PrimaryCTAStyle(isEnabled: store.schedule.isValid))
            .disabled(!store.schedule.isValid)

            Text(
                store.schedule.isValid
                    ? "you can adjust this anytime."
                    : "pick at least one training day."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(store.schedule.isValid ? Theme.inkTertiary : Theme.accent)
            .padding(.top, 12)
            .animation(Theme.stateChange, value: store.schedule.isValid)
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Theme.canvas)
    }
}
