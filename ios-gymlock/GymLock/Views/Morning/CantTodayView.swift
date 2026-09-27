import SwiftUI

/// The one skip screen (FLOW, Flow 4).
///
/// The same screen appears whether they tapped "can't today" or slept through
/// the alarm. The heading and the order of the three doors follow one
/// question: can they still reach 3 this week with the planned days left?
/// There is no skip budget and nothing is taken away.
///
/// PLACEHOLDER UI: designed in Step 3
struct CantTodayView: View {
    let voice: SessionVoice
    let plan: SkipScreenPlan
    let choices: [ReschedulePlanner.Choice]
    let defaultTimeFor: (Date) -> TimeOfDay
    let isTimeAvailable: (Date, TimeOfDay) -> Bool
    let isComebackModeOn: Bool
    let onReschedule: (Date, TimeOfDay) -> Void
    let onHomeWorkout: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void
    /// Opened from the Home banner's "reschedule for today": the picker
    /// comes up straight away.
    var startsOnPicker = false
    var onPickerShown: () -> Void = {}

    @State private var isPickingReschedule = false
    @State private var chosenDay: Date?
    @State private var chosenTime = Date()
    @State private var timeNote: String?

    var body: some View {
        MorningScreen(trailingTitle: "Back", trailingAction: onBack) {
            VStack(spacing: 22) {
                HaloedGlyph(systemName: "heart.fill", size: 82)
                    .frame(height: 158)

                VStack(spacing: 8) {
                    Text(plan.heading)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                options

                if let note = plan.rescheduleNote {
                    Text(note)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isComebackModeOn { comebackNote }
            }
        } footer: {
            EmptyView()
        }
        .onAppear {
            guard startsOnPicker else { return }
            isPickingReschedule = true
            onPickerShown()
        }
        .sheet(isPresented: $isPickingReschedule) {
            rescheduleSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - The three doors

    @ViewBuilder
    private var options: some View {
        VStack(spacing: 12) {
            ForEach(Array(plan.options.enumerated()), id: \.element) { pair in
                switch pair.element {
                case .reschedule:
                    MorningChoiceRow(
                        title: "reschedule",
                        subtitle: "a real alarm on a day you pick",
                        systemImage: "calendar.badge.clock"
                    ) {
                        isPickingReschedule = true
                    }

                case .homeWorkout:
                    MorningChoiceRow(
                        title: "home workout, 20 min",
                        subtitle: "counts with apple health or a photo",
                        systemImage: "house.fill"
                    ) {
                        onHomeWorkout()
                    }

                case .skip:
                    MorningChoiceRow(
                        title: "skip",
                        subtitle: voice.dayOffDetail,
                        systemImage: "moon.zzz.fill"
                    ) {
                        onSkip()
                    }
                }
            }
        }
    }

    // MARK: - Reschedule picker

    private var rescheduleSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // PLACEHOLDER UI: designed in Step 3
                    if let day = chosenDay {
                        VStack(spacing: 10) {
                            DatePicker(
                                "alarm",
                                selection: $chosenTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()

                            if let timeNote {
                                Text(timeNote)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.accentWarm)
                                    .multilineTextAlignment(.center)
                            }

                            MorningPrimaryButton(
                                title: "set alarm",
                                systemImage: "bell.badge.fill",
                                trailingImage: nil
                            ) {
                                confirmReschedule(on: day)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 16))
                    }

                    ForEach(choices, id: \.self) { choice in
                        MorningChoiceRow(
                            title: choice.label,
                            subtitle: defaultTimeFor(choice.day).clockString,
                            systemImage: choice.isLaterToday ? "clock.fill" : "calendar"
                        ) {
                            pick(choice)
                        }
                    }
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { isPickingReschedule = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func pick(_ choice: ReschedulePlanner.Choice) {
        chosenDay = choice.day
        chosenTime = date(defaultTimeFor(choice.day), on: choice.day)
        timeNote = nil
        Haptics.tap()
    }

    private func confirmReschedule(on day: Date) {
        let time = TimeOfDay(from: chosenTime)
        guard isTimeAvailable(day, time) else {
            timeNote = "that time is inside your sleep hours."
            Haptics.soft()
            return
        }
        isPickingReschedule = false
        onReschedule(day, time)
    }

    // MARK: - Helpers

    private func date(_ time: TimeOfDay, on day: Date) -> Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? Date()
    }

    private var comebackNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("comeback mode is on")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("your next realistic session is already set. nothing to make up.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.07), in: .rect(cornerRadius: 16))
    }
}
