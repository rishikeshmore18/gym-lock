import SwiftUI

/// One overview of the next morning: when the alarm rings, what happens after
/// it, and what the user will hear.
///
/// This is configuration, not another questionnaire. Every value on it has
/// already been answered somewhere — in onboarding, or on the rhythm screen —
/// and this screen exists to show the user the assembled result and let them
/// correct it, not to ask again.
struct MorningAlarmPlanView: View {
    let onSave: () -> Void
    var onBack: (() -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(AlarmSoundPlayer.self) private var soundPlayer: AlarmSoundPlayer?

    @State private var editingSlot: AlarmSlot?
    @State private var isPickingSound = false
    @State private var isEditingRhythm = false

    private var plan: MorningPlan { store.plan }
    /// The sleep schedule as set, including a bedtime that starts tomorrow night.
    private var rhythm: MorningRhythm { plan.scheduledRhythm }

    /// The alarm that will actually ring next.
    private var next: (slot: AlarmSlot, fireDate: Date)? {
        plan.nextOccurrence()
    }

    var body: some View {
        MorningScreen(
            trailingTitle: onBack == nil ? nil : "Back",
            trailingAction: onBack
        ) {
            VStack(alignment: .leading, spacing: 24) {
                heading
                celestialHero
                planCard
                alarmSoundRow
                alarmModeRow
                scheduleSection
                nightLockRow
                MissionToggleCard()
            }
        } footer: {
            MorningPrimaryButton(title: "save morning", systemImage: "checkmark") {
                store.plan.hasBeenReviewed = true
                onSave()
            }
        }
        .task {
            store.seedPlanIfNeeded()
        }
        .sheet(item: $editingSlot) { slot in
            AlarmSlotEditor(slot: slot) { updated in
                apply(updated)
            } onDelete: {
                store.plan.slots.removeAll { $0.id == slot.id }
            }
        }
        .sheet(isPresented: $isPickingSound) {
            AlarmSoundPickerSheet()
        }
        .sheet(isPresented: $isEditingRhythm) {
            SleepWakeRhythmView { updated in
                isEditingRhythm = false
                commitRhythm(updated)
            }
            .environment(store)
        }
    }

    // MARK: - Sections

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let next, Calendar.current.isDateInTomorrow(next.fireDate) {
                Text("tomorrow")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.accent)
            }

            Text("your morning")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)
        }
    }

    /// Moon or sun, decided by the clock right now rather than by the plan, so
    /// opening this at 11pm shows night and opening it at 7am shows morning.
    private var celestialHero: some View {
        VStack(spacing: 14) {
            CelestialRhythmView(phase: CelestialRhythmView.phaseNow(), size: 132)

            VStack(spacing: 2) {
                Text("Gym by")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)

                Text(gymByTime.displayString)
                    .font(.system(size: 42, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlanSummaryCard(
                wake: wakeTime,
                getReadyMinutes: rhythm.getReadyMinutes,
                travelMinutes: rhythm.travelMinutes,
                leave: wakeTime.offset(byMinutes: rhythm.getReadyMinutes),
                gymBy: gymByTime
            )

            Button {
                Haptics.tap()
                isEditingRhythm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                    Text(plan.hasMorningSessions ? "adjust sleep & window" : "adjust window")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The track chosen during onboarding, not a second sound system.
    private var alarmSoundRow: some View {
        Button {
            Haptics.tap()
            isPickingSound = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accent.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("alarm sound")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(store.profile.alarmSoundLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                MiniWaveform(level: soundPlayer?.playing == nil ? 0 : (soundPlayer?.level ?? 0))

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }

    /// States how the alarm will actually be delivered on this OS.
    ///
    /// A user whose phone can only give them a notification deserves to know
    /// that before the morning it matters, rather than after.
    private var alarmModeRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Theme.accent.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("alarm mode")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                Text("Committed")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }

            Spacer(minLength: 8)

            Text("persistent")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accent.opacity(0.12), in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("schedule")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Spacer()

                Button {
                    Haptics.tap()
                    let new = AlarmSlot(days: [], alarmTime: TimeOfDay(hour: 6, minute: 30))
                    store.plan.slots.append(new)
                    editingSlot = new
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent.opacity(0.12), in: .circle)
                }
                .accessibilityLabel("Add an alarm")
            }

            if plan.slots.isEmpty {
                emptySchedule
            } else {
                ForEach(plan.slots) { slot in
                    slotRow(slot)
                }
            }
        }
    }

    private var emptySchedule: some View {
        VStack(spacing: 6) {
            Text("no alarms yet.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("add one and GymLock will hold the morning for you.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 18))
    }

    private func slotRow(_ slot: AlarmSlot) -> some View {
        HStack(spacing: 14) {
            Button {
                Haptics.tap()
                editingSlot = slot
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(slot.alarmTime.displayString)
                            .font(.system(size: 26, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(slot.isEnabled ? Theme.ink : Theme.inkTertiary)

                        Text(slot.isEnabled ? "ON" : "OFF")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(slot.isEnabled ? Theme.accent : Theme.inkTertiary)
                    }

                    HStack(spacing: 6) {
                        Text(slot.daysSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)

                        if !slot.daypart.usesSleepRhythm {
                            Text("· \(slot.daypart.label)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Toggle(
                "",
                isOn: Binding(
                    get: { slot.isEnabled },
                    set: { isOn in
                        guard let index = store.plan.slots.firstIndex(where: { $0.id == slot.id })
                        else { return }
                        store.plan.slots[index].isEnabled = isOn
                        Haptics.tap()
                    }
                )
            )
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .warmCard(radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alarm at \(slot.alarmTime.displayString), \(slot.daysSummary)")
    }

    private var nightLockRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.night)
                .frame(width: 38, height: 38)
                .background(Theme.night.opacity(0.10), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("Night Lock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(rhythm.bedtime.displayString) → \(rhythm.wakeTime.displayString)")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    // MARK: - Derived

    private var wakeTime: TimeOfDay {
        next?.slot.alarmTime ?? plan.enabledSlots.first?.alarmTime ?? rhythm.wakeTime
    }

    /// The bar the user placed on the dial, not the lock window. The two used
    /// to be the same number; now that the visit can sit anywhere in the day
    /// they are not, and this screen is about the plan.
    private var gymByTime: TimeOfDay {
        wakeTime.offset(byMinutes: rhythm.gapToGymMinutes)
    }

    // MARK: - Actions

    /// Saves an edited alarm, and moves wake time with it.
    ///
    /// Same rule as the alarm screen: the alarm ringing and getting up are one
    /// event, so setting either sets both and the two can never disagree.
    private func apply(_ updated: AlarmSlot) {
        if let index = store.plan.slots.firstIndex(where: { $0.id == updated.id }) {
            store.plan.slots[index] = updated
        } else {
            store.plan.slots.append(updated)
        }

        guard updated.isEnabled,
              updated.daypart.usesSleepRhythm,
              updated.id == plan.enabledSlots.first?.id,
              updated.alarmTime != store.plan.rhythm.wakeTime
        else { return }

        var rhythm = store.plan.scheduledRhythm
        rhythm.setWakeTime(updated.alarmTime)
        rhythm.hasBeenSet = true
        commitRhythm(rhythm)
    }

    /// Saves a sleep schedule change. While the plan is still being set up
    /// for the first time the bedtime applies at once; after that a new
    /// bedtime starts tomorrow night.
    private func commitRhythm(_ updated: MorningRhythm) {
        store.commitRhythm(updated, immediately: !store.plan.hasBeenReviewed)
    }
}
