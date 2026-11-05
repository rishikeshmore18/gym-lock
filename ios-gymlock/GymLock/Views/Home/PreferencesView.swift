import SwiftUI

/// Preferences, reached from Profile.
///
/// Built from the Alarm screen's own parts (round glass header button, the
/// centred title that collapses into a glass pill, glass grouped cards, the
/// coral value wheel) so it reads as the same surface as Alarm, Sound and
/// Haptics rather than a stock settings list dropped into the app.
///
/// One setting for now: Time to Gym. It is the same stored value the Alarm
/// screen and the day dial edit, written through `MorningPlan.setTimeToGym`,
/// so there is one number and one rule wherever it is changed.
struct PreferencesView: View {
    var body: some View {
        NavigationStack {
            PreferencesHome()
        }
        .tint(Theme.accent)
    }
}

// MARK: - Home

private struct PreferencesHome: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var scrollOffset: CGFloat = 0

    private var rhythm: MorningRhythm { store.plan.rhythm }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Room for the header, which is an overlay rather than a
                    // safe-area inset for the same reason as `AlarmPageHeader`.
                    Color.clear.frame(height: AlarmPageHeader.band + 10)

                    PreferencesEyebrow(text: "GYM ROUTINE")

                    NavigationLink {
                        TimeToGymEditor()
                    } label: {
                        timeToGymRow
                    }
                    .buttonStyle(AlarmGlassCardButtonStyle(verticalPadding: 6))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Time to Gym")
                    .accessibilityValue("\(rhythm.currentTimeToGymMinutes) minutes")
                    .accessibilityHint("Opens the time to gym picker")

                    PreferencesFootnote(text: "Includes getting ready and traveling.")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            .overlay(alignment: .top) {
                AlarmPageHeader(
                    title: "Preferences",
                    scrollOffset: scrollOffset,
                    symbol: "xmark",
                    label: "Close"
                ) {
                    dismiss()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The value on the right, and underneath it what that value means today,
    /// so the row answers "what does this do" before it is opened.
    private var timeToGymRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.surfaceMuted, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Time to Gym")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                if showsPlanLine {
                    Text("\(alarmWord) \(rhythm.lockAlarmTime.displayString) · gym by \(rhythm.gymByTime.displayString)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                }
            }

            Spacer(minLength: 8)

            Text("\(rhythm.currentTimeToGymMinutes) min")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .contentTransition(.numericText())

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(minHeight: 60)
    }

    private var showsPlanLine: Bool {
        store.plan.hasMorningSessions || !store.plan.enabledSlots.isEmpty
    }

    private var alarmWord: String {
        rhythm.flowMode == .wakeAndGo ? "alarm" : "time to go"
    }
}

// MARK: - Time to Gym editor

/// One number, chosen three ways (wheel, presets, VoiceOver adjust), with
/// its consequence shown live underneath: which alarm moves and when you are
/// due at the gym. That consequence is the point of the screen; the number on
/// its own means little.
private struct TimeToGymEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var alarmSync: Task<Void, Never>?

    private static let values = Array(
        stride(
            from: MorningRhythm.timeToGymRange.lowerBound,
            through: MorningRhythm.timeToGymRange.upperBound,
            by: MorningRhythm.timeToGymStep
        )
    )

    private var rhythm: MorningRhythm { store.plan.rhythm }
    private var minutes: Int { rhythm.currentTimeToGymMinutes }

    var body: some View {
        AlarmSubpage(title: "Time to Gym") {
            PreferencesFootnote(text: "Includes getting ready and traveling.")
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            AlarmGroupCard {
                ValueWheel(
                    labels: Self.values.map { "\($0) min" },
                    selection: wheelIndex,
                    rowHeight: 50,
                    reach: 2,
                    activeSize: 40,
                    accessibilityTitle: "Time to Gym"
                )
                .padding(.vertical, 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                AlarmSectionHeader(text: "presets")
                PresetGlassRow(
                    values: MorningRhythm.timeToGymPresets,
                    selection: minutes
                ) { value in
                    Haptics.selection()
                    write(value)
                }
            }
            .padding(.top, 4)

            if store.plan.hasMorningSessions || !store.plan.enabledSlots.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    AlarmSectionHeader(text: "your plan")
                    planCard
                    PreferencesFootnote(text: rhythm.flowMode == .wakeAndGo
                        ? "your gym time moves with it."
                        : "your gym time stays put. the time to go alarm moves.")
                }
                .padding(.top, 4)
            }
        }
        .onDisappear {
            // Leaving mid-debounce must still hand the new time to the OS.
            if alarmSync != nil {
                alarmSync?.cancel()
                alarmSync = nil
                Task { await coordinator.syncAlarms() }
            }
        }
    }

    /// Alarm on the left, arrival on the right, the duration riding the line
    /// between them: the same left-to-right reading as the day dial.
    private var planCard: some View {
        AlarmGroupCard {
            HStack(alignment: .center, spacing: 10) {
                planTime(
                    label: rhythm.flowMode == .wakeAndGo ? "alarm" : "time to go",
                    time: rhythm.lockAlarmTime.displayString,
                    alignment: .leading
                )

                ZStack {
                    Capsule()
                        .fill(Theme.border)
                        .frame(height: 2)
                    Text("\(minutes) min")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.surfaceMuted, in: .capsule)
                        .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
                }
                .frame(maxWidth: .infinity)

                planTime(
                    label: "at gym by",
                    time: rhythm.gymByTime.displayString,
                    alignment: .trailing
                )
            }
            .padding(.vertical, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(rhythm.flowMode == .wakeAndGo ? "Alarm" : "Time to go") \(rhythm.lockAlarmTime.displayString), at gym by \(rhythm.gymByTime.displayString)"
            )
        }
    }

    private func planTime(label: String, time: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            Text(time)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The wheel works in indices and supplies its own ticks.
    private var wheelIndex: Binding<Int> {
        Binding(
            get: { Self.values.firstIndex(of: minutes) ?? 0 },
            set: { index in
                guard Self.values.indices.contains(index) else { return }
                write(Self.values[index])
            }
        )
    }

    private func write(_ value: Int) {
        guard value != minutes else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 1)) {
            var plan = store.plan
            plan.setTimeToGym(value)
            store.plan = plan
        }
        // The alarm the OS holds follows, but not once per detent of a spin.
        // Same path as the Alarm screen.
        alarmSync?.cancel()
        alarmSync = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            alarmSync = nil
            await coordinator.syncAlarms()
        }
    }
}

// MARK: - Presets

/// Glass capsules for the common durations. On iOS 26 they share one
/// `GlassEffectContainer`, so neighbouring chips blend as system glass does,
/// and the chosen one is ink-tinted glass (coral already belongs to the
/// wheel). On iOS 18, and with Reduce Transparency, an ink capsule slides
/// between opaque chips instead.
private struct PresetGlassRow: View {
    let values: [Int]
    let selection: Int
    let choose: (Int) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSpace

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 8) {
                row
            }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { value in
                chip(value)
            }
        }
    }

    @ViewBuilder
    private func chip(_ value: Int) -> some View {
        let isSelected = value == selection
        let label = Text("\(value)")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(.capsule)

        Group {
            if #available(iOS 26.0, *), !reduceTransparency {
                Button { choose(value) } label: { label }
                    .buttonStyle(.plain)
                    .glassEffect(
                        isSelected ? .regular.tint(Theme.ink).interactive() : .regular.interactive(),
                        in: .capsule
                    )
            } else {
                Button { choose(value) } label: {
                    label.background {
                        ZStack {
                            Capsule()
                                .fill(Theme.surface)
                                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
                            if isSelected {
                                Capsule()
                                    .fill(Theme.ink)
                                    .matchedGeometryEffect(id: "preset", in: selectionSpace)
                            }
                        }
                    }
                }
                .buttonStyle(PresetPressStyle())
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.85),
            value: selection
        )
        .accessibilityLabel("\(value) minutes")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct PresetPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.95 : 1)
            .animation(
                pressed
                    ? .spring(response: 0.18, dampingFraction: 0.9)
                    : .spring(response: 0.4, dampingFraction: 0.6),
                value: pressed
            )
    }
}

// MARK: - Small type

/// The spec's one uppercase eyebrow for the group.
private struct PreferencesEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.leading, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct PreferencesFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }
}

#Preview("Preferences") {
    PreferencesView()
        .environment(AppStore())
}
