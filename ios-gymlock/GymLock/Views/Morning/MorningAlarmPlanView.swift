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
    @State private var nightLockPrompt: NightLockPrompt?
    /// The rhythm as it was when this screen opened, so a change can be
    /// detected and the night lock question asked at the right moment.
    @State private var rhythmOnOpen: MorningRhythm?

    /// Asked when the sleep window moves under a night lock the user has
    /// already tuned.
    private struct NightLockPrompt: Identifiable {
        let id = UUID()
        let proposed: MorningRhythm
    }

    private var plan: MorningPlan { store.plan }
    private var rhythm: MorningRhythm { plan.rhythm }

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
                if plan.nightLock.isEnabled { nightLockRow }
                missionToggle
            }
        } footer: {
            MorningPrimaryButton(title: "save morning", systemImage: "checkmark") {
                store.plan.hasBeenReviewed = true
                onSave()
            }
        }
        .task {
            store.seedPlanIfNeeded()
            if rhythmOnOpen == nil { rhythmOnOpen = store.plan.rhythm }
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
                proposeRhythmChange(updated)
            }
            .environment(store)
        }
        .alert(item: $nightLockPrompt) { prompt in
            Alert(
                title: Text("Update Night Lock too?"),
                message: Text(
                    "Your sleep window moved to \(prompt.proposed.bedtime.displayString) → \(prompt.proposed.wakeTime.displayString)."
                ),
                primaryButton: .default(Text("Update")) {
                    store.plan.rhythm = prompt.proposed
                    store.plan.nightLock.followsRhythm = true
                    store.applyRhythmToNightLock()
                    rhythmOnOpen = prompt.proposed
                },
                secondaryButton: .cancel(Text("Keep existing")) {
                    // The user tuned this by hand; the rhythm change must not
                    // quietly overwrite it.
                    store.plan.rhythm = prompt.proposed
                    store.plan.nightLock.followsRhythm = false
                    rhythmOnOpen = prompt.proposed
                }
            )
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
                Text(plan.nightLock.summary(in: rhythm))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 8)

            if !plan.nightLock.followsRhythm {
                Text("custom")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceMuted, in: .capsule)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    /// Missions can be switched off, and switching them off sticks.
    private var missionToggle: some View {
        Toggle(isOn: Binding(
            get: { plan.missionsEnabled },
            set: { store.plan.missionsEnabled = $0; Haptics.tap() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("activation mission")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("one tiny action after you commit.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .warmCard(radius: 18)
    }

    // MARK: - Derived

    private var wakeTime: TimeOfDay {
        next?.slot.alarmTime ?? plan.enabledSlots.first?.alarmTime ?? rhythm.wakeTime
    }

    private var gymByTime: TimeOfDay {
        wakeTime.offset(byMinutes: rhythm.windowMinutes)
    }

    // MARK: - Actions

    private func apply(_ updated: AlarmSlot) {
        guard let index = store.plan.slots.firstIndex(where: { $0.id == updated.id }) else {
            store.plan.slots.append(updated)
            return
        }
        store.plan.slots[index] = updated
    }

    /// Applies a rhythm change, asking about the night lock only when the answer
    /// is not obvious.
    private func proposeRhythmChange(_ updated: MorningRhythm) {
        let previous = rhythmOnOpen ?? store.plan.rhythm
        let sleepWindowMoved = previous.bedtime != updated.bedtime
            || previous.wakeTime != updated.wakeTime

        // No question needed when the lock is off, or when it is already
        // following the rhythm and will simply keep doing so.
        guard store.plan.nightLock.isEnabled,
              !store.plan.nightLock.followsRhythm,
              sleepWindowMoved
        else {
            store.plan.rhythm = updated
            store.applyRhythmToNightLock()
            rhythmOnOpen = updated
            return
        }

        nightLockPrompt = NightLockPrompt(proposed: updated)
    }
}

// MARK: - Waveform

/// Three bars that move with the preview's actual output level.
struct MiniWaveform: View {
    let level: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { bar in
                // Staggered scaling so the bars do not move as one block.
                let weight = [0.7, 1.0, 0.55][bar]
                let height = 6 + level * 18 * weight

                Capsule()
                    .fill(Theme.accent.opacity(level > 0.02 ? 0.9 : 0.25))
                    .frame(width: 3, height: max(6, height))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

// MARK: - Slot editor

/// Edits one recurring alarm.
private struct AlarmSlotEditor: View {
    let slot: AlarmSlot
    let onSave: (AlarmSlot) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AlarmSlot

    init(slot: AlarmSlot, onSave: @escaping (AlarmSlot) -> Void, onDelete: @escaping () -> Void) {
        self.slot = slot
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: slot)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        TimeWheel(time: $draft.alarmTime, accessibilityTitle: "Alarm time")
                            .padding(.top, 8)

                        dayPicker

                        if !draft.daypart.usesSleepRhythm {
                            eveningNote
                        }

                        Button(role: .destructive) {
                            Haptics.tap()
                            onDelete()
                            dismiss()
                        } label: {
                            Text("delete this alarm")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .tint(Theme.accent)
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                        .foregroundStyle(Theme.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("save") {
                        Haptics.tap()
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("repeats")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    let isOn = draft.days.contains(day)

                    Button {
                        if isOn { draft.days.remove(day) } else { draft.days.insert(day) }
                        Haptics.selection()
                    } label: {
                        Text(String(day.shortLabel.prefix(1)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isOn ? .white : Theme.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                isOn ? Theme.accent : Theme.surfaceMuted,
                                in: .rect(cornerRadius: 12)
                            )
                    }
                    .accessibilityLabel(day.shortLabel)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
        }
    }

    /// A session outside the morning simply does not use the sleep coupling,
    /// and says so rather than silently ignoring it.
    private var eveningNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            Text("this is an \(draft.daypart.label) session, so it uses your prepare and travel window — not your sleep schedule.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Sound picker

/// Reuses the tracks and the import path already built in onboarding.
///
/// Deliberately thin: there is exactly one alarm-audio system in this app, and
/// this is a second door into it rather than a second copy of it.
private struct AlarmSoundPickerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(AlarmSoundPlayer.self) private var player: AlarmSoundPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(AlarmSound.bundled) { sound in
                            row(for: sound)
                        }

                        if store.profile.ownSongFileName != nil {
                            row(for: .ownSong)
                        }
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("alarm sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") {
                        player?.stop()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
            .onDisappear { player?.stop() }
        }
    }

    private func row(for sound: AlarmSound) -> some View {
        let isSelected = store.profile.alarmSound == sound
        let isPlaying = player?.playing == sound

        return Button {
            store.profile.alarmSound = sound
            Haptics.tap()
            player?.toggle(sound)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sound == .ownSong ? (store.profile.ownSongTitle ?? "my own song") : sound.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(sound.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isPlaying {
                    MiniWaveform(level: player?.level ?? 0)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.border)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }
}
