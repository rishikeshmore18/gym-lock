import SwiftUI

/// Sets the window that gets the user from bed to moving.
///
/// Shown only to people who actually train in the morning. Someone who lifts
/// after work has no reason to be walked through a bedtime picker, and asking
/// them anyway is how a focused product turns into a questionnaire.
///
/// The circular dial is borrowed in *interaction* from sleep apps, not in
/// appearance: the canvas stays warm off-white, the arc is GymLock coral, and
/// the only deep blue on screen is inside the small celestial illustration.
struct SleepWakeRhythmView: View {
    /// Called with the finished rhythm.
    let onUse: (MorningRhythm) -> Void
    /// Present only when the screen can reasonably be skipped.
    var onSkip: (() -> Void)?

    @Environment(AppStore.self) private var store

    @State private var rhythm: MorningRhythm = .default
    @State private var editing: TimeField?
    @State private var hasLoaded = false

    private enum TimeField: String, Identifiable {
        case bedtime
        case wake

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bedtime: "bedtime"
            case .wake: "wake up"
            }
        }
    }

    var body: some View {
        MorningScreen(
            trailingTitle: onSkip == nil ? nil : "Skip",
            trailingAction: onSkip
        ) {
            VStack(alignment: .leading, spacing: 26) {
                heading
                dialBlock
                timeCards
                durations
                windowSummary
                guardrailNotice
            }
        } footer: {
            MorningPrimaryButton(
                title: "use this rhythm",
                systemImage: "checkmark",
                isEnabled: rhythm.isWithinGuardrails
            ) {
                commit()
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            rhythm = store.plan.rhythm
        }
        .sheet(item: $editing) { field in
            TimePickerSheet(
                title: field.title,
                time: field == .bedtime ? $rhythm.bedtime : $rhythm.wakeTime
            )
        }
    }

    // MARK: - Sections

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("your sleep → gym rhythm")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            Text("set the window that gets you from bed to moving.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dialBlock: some View {
        RhythmDial(bedtime: $rhythm.bedtime, wakeTime: $rhythm.wakeTime)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var timeCards: some View {
        HStack(spacing: 12) {
            timeCard(
                field: .bedtime,
                icon: "moon.fill",
                iconTint: Theme.night,
                label: "bedtime",
                time: rhythm.bedtime
            )

            timeCard(
                field: .wake,
                icon: "sun.max.fill",
                iconTint: Theme.accentWarm,
                label: "wake up",
                time: rhythm.wakeTime
            )
        }
    }

    /// Tapping a card opens the precise wheel.
    ///
    /// The dial and the card are two routes to the same value on purpose: the
    /// drag is quick and approximate, the wheel is exact, and different people
    /// reach for different ones.
    private func timeCard(
        field: TimeField,
        icon: String,
        iconTint: Color,
        label: String,
        time: TimeOfDay
    ) -> some View {
        Button {
            Haptics.tap()
            editing = field
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(iconTint)
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer(minLength: 0)
                }

                Text(time.displayString)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
        .accessibilityLabel("\(label), \(time.displayString). Double tap to change.")
    }

    private var durations: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("before the gym")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)

            HStack(alignment: .top, spacing: 12) {
                MinuteDial(
                    title: "get ready",
                    subtitle: "time to get yourself out the door",
                    systemImage: "tshirt.fill",
                    minutes: $rhythm.getReadyMinutes,
                    range: MorningRhythm.getReadyRange
                )

                MinuteDial(
                    title: "travel",
                    subtitle: "time to get to the gym",
                    systemImage: "car.fill",
                    minutes: $rhythm.travelMinutes,
                    range: MorningRhythm.travelRange
                )
            }

            // The presets sit full width rather than under each dial: seven
            // chips in half a screen would be smaller than a fingertip.
            VStack(spacing: 8) {
                PresetChips(
                    label: "get ready",
                    values: MorningRhythm.getReadyPresets,
                    selection: $rhythm.getReadyMinutes
                )
                PresetChips(
                    label: "travel",
                    values: MorningRhythm.travelPresets,
                    selection: $rhythm.travelMinutes
                )
            }
        }
    }

    /// The payoff: the whole morning as three times in a row.
    private var windowSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("your GymLock window")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(rhythm.windowMinutes)")
                    .font(.system(size: 54, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text("min")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)

                Spacer(minLength: 8)

                CelestialRhythmView(
                    phase: CelestialRhythmView.phase(for: rhythm.wakeTime),
                    size: 62,
                    showsStars: false
                )
            }

            HStack(spacing: 0) {
                milestone(time: rhythm.wakeTime, label: "wake", isEmphasised: false)
                milestoneArrow
                milestone(time: rhythm.leaveTime, label: "leave", isEmphasised: false)
                milestoneArrow
                milestone(time: rhythm.gymByTime, label: "gym", isEmphasised: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.accentWash, Theme.accentWash.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
        }
    }

    private func milestone(time: TimeOfDay, label: String, isEmphasised: Bool) -> some View {
        VStack(spacing: 3) {
            Text(time.displayString)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isEmphasised ? Theme.accent : Theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var milestoneArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.accent.opacity(0.5))
            .offset(y: -7)
    }

    /// The guardrails, stated as what they are: product constraints about how
    /// GymLock works, not claims about sleep science.
    @ViewBuilder
    private var guardrailNotice: some View {
        if rhythm.exceedsAbsoluteMaximum {
            notice(
                title: "GymLock works best when your alarm leads directly into your gym trip.",
                detail: "Choose a window within 2 hours."
            )
        } else if rhythm.isBelowMinimum {
            notice(
                title: "That window is very tight.",
                detail: "Give yourself at least \(MorningRhythm.minimumWindow) minutes between the alarm and the gym."
            )
        } else if rhythm.exceedsNormalMaximum {
            notice(
                title: "That's a long run-up.",
                detail: "It'll still work — just know the clock starts the moment you commit.",
                isWarning: false
            )
        }
    }

    private func notice(title: String, detail: String, isWarning: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isWarning ? Theme.accent : Theme.inkTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isWarning ? Theme.accent.opacity(0.08) : Theme.surfaceMuted),
            in: .rect(cornerRadius: 18)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(Theme.settle, value: rhythm.windowMinutes)
    }

    // MARK: - Actions

    private func commit() {
        var finished = rhythm
        finished.hasBeenSet = true
        onUse(finished)
    }
}

// MARK: - Preset chips

/// A row of suggested durations. Selecting one is a shortcut, never a
/// requirement — the dial and stepper still reach every value in between.
struct PresetChips: View {
    let label: String
    let values: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 62, alignment: .leading)

            ForEach(values, id: \.self) { value in
                let isSelected = selection == value

                Button {
                    guard selection != value else { return }
                    withAnimation(Theme.stateChange) { selection = value }
                    Haptics.selection()
                } label: {
                    Text("\(value)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .white : Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            isSelected ? Theme.accent : Theme.surfaceMuted,
                            in: .rect(cornerRadius: 9)
                        )
                }
                .accessibilityLabel("\(label), \(value) minutes")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Time picker sheet

/// The precise editor, built on the same wheel used throughout onboarding so
/// setting a time never feels like a different app.
struct TimePickerSheet: View {
    let title: String
    @Binding var time: TimeOfDay

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                TimeWheel(time: $time, accessibilityTitle: title)
                    .padding(.horizontal, Theme.pageMargin)

                Spacer(minLength: 0)

                Button("done") {
                    Haptics.tap()
                    dismiss()
                }
                .buttonStyle(PrimaryCTAStyle(isEnabled: true))
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 20)
            }
            .background(Theme.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }
}
