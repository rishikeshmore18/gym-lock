import SwiftUI

/// The Alarm screen: the day dial, the alarm, the sound, the wind-down lock,
/// the gym lock, and how it all actually rings.
///
/// Structure follows Apple's Clock app; looks follow GymLock's tokens. One
/// coral accent per screen, and here it belongs to the gym arc on the dial —
/// so the toggles, chevrons and sound row are ink and grey.
///
/// One alarm is a settled product decision: no list, no add button. If more
/// than one slot ever exists, the first enabled one is shown and the rest are
/// left untouched.
struct AlarmSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(AlarmSoundPlayer.self) private var soundPlayer: AlarmSoundPlayer?
    @Environment(\.dismiss) private var dismiss

    /// The rhythm as it was when this screen opened, so a dial change can be
    /// checked against the night lock at the right moment.
    @State private var rhythmOnOpen: MorningRhythm?
    @State private var nightLockPrompt: RhythmChangeProposer.Prompt?
    @State private var editingSlot: AlarmSlot?
    @State private var isPickingSound = false
    @State private var isEditingWindDown = false
    @State private var alarmAuth: AlarmAuthorization = .notDetermined

    #if DEBUG
    @State private var isShowingSimulator = false
    #endif

    private var plan: MorningPlan { store.plan }
    private var rhythm: MorningRhythm { plan.rhythm }

    /// The one alarm that will actually ring.
    private var primarySlot: AlarmSlot? {
        plan.enabledSlots.first ?? plan.slots.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        dialCard
                        alarmCard
                        soundCard
                        windDownCard
                        gymLockCard
                        howItRingsCard
                        MissionToggleCard(tint: Theme.ink)

                        #if DEBUG
                        simulatorRow
                        #endif
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("back")
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                    .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .tint(Theme.accent)
        .task {
            store.seedPlanIfNeeded()
            if rhythmOnOpen == nil { rhythmOnOpen = store.plan.rhythm }
            alarmAuth = await coordinator.alarmAuthorization()
        }
        .onDisappear {
            soundPlayer?.stop()
            resyncAlarms()
        }
        .sheet(item: $editingSlot) { slot in
            AlarmSlotEditor(slot: slot) { updated in
                apply(updated)
            } onDelete: {
                store.plan.slots.removeAll { $0.id == slot.id }
                resyncAlarms()
            }
        }
        .sheet(isPresented: $isPickingSound) {
            AlarmSoundPickerSheet()
        }
        .sheet(isPresented: $isEditingWindDown) {
            WindDownEditorSheet()
        }
        #if DEBUG
        .sheet(isPresented: $isShowingSimulator) {
            DebugMorningPanel()
        }
        #endif
        .nightLockPromptAlert($nightLockPrompt, store: store) {
            rhythmOnOpen = store.plan.rhythm
        }
    }

    // MARK: - Dial

    private var dialCard: some View {
        VStack(spacing: 12) {
            DayDial(
                bedtime: bedtimeBinding,
                wakeTime: wakeBinding,
                travelMinutes: travelBinding,
                getReadyMinutes: rhythm.getReadyMinutes,
                onSettle: commitRhythmAfterDial
            )

            if let line = guardrailLine {
                Text(line)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .warmCard(radius: Theme.cardRadius)
        .animation(Theme.stateChange, value: guardrailLine)
    }

    /// Guardrails live inline, never in an alert. The absolute ceiling cannot
    /// be reached from the dial alone, but it is still the first thing to say
    /// if get-ready and travel ever stack up to it.
    private var guardrailLine: String? {
        if rhythm.exceedsAbsoluteMaximum {
            return "over 2 hours isn't a lock, it's a calendar."
        }
        if rhythm.exceedsNormalMaximum {
            return "that's a long window. still fine."
        }
        if rhythm.isBelowMinimum {
            return "that's under 10 minutes. you'll be rushing."
        }
        return nil
    }

    /// Moving the sun moves the wake time, and on this screen the wake time
    /// and the alarm time are the same thing: the primary morning slot's time
    /// follows the handle live.
    private var wakeBinding: Binding<TimeOfDay> {
        Binding(
            get: { store.plan.rhythm.wakeTime },
            set: { new in
                store.plan.rhythm.wakeTime = new
                if let index = primaryMorningSlotIndex {
                    store.plan.slots[index].alarmTime = new
                }
                store.applyRhythmToNightLock()
            }
        )
    }

    private var bedtimeBinding: Binding<TimeOfDay> {
        Binding(
            get: { store.plan.rhythm.bedtime },
            set: { new in
                store.plan.rhythm.bedtime = new
                store.applyRhythmToNightLock()
            }
        )
    }

    private var travelBinding: Binding<Int> {
        Binding(
            get: { store.plan.rhythm.travelMinutes },
            set: { store.plan.rhythm.travelMinutes = $0 }
        )
    }

    /// Only a morning slot is coupled to the sleep rhythm; an evening alarm is
    /// set from its own editor and never silently rewritten by the dial.
    private var primaryMorningSlotIndex: Int? {
        guard let primary = primarySlot, primary.daypart.usesSleepRhythm else { return nil }
        return store.plan.slots.firstIndex { $0.id == primary.id }
    }

    /// A dial gesture just ended. The rhythm is already live from the drag;
    /// the only question left is whether it moved under a hand-tuned night
    /// lock, and that is asked exactly once, on settle.
    private func commitRhythmAfterDial() {
        let current = store.plan.rhythm
        let previous = rhythmOnOpen ?? current

        if let prompt = RhythmChangeProposer.prompt(for: current, since: previous, plan: plan) {
            nightLockPrompt = prompt
        } else {
            store.applyRhythmToNightLock()
            rhythmOnOpen = current
        }
        resyncAlarms()
    }

    // MARK: - Alarm card

    private var alarmCard: some View {
        Button {
            Haptics.tap()
            openAlarmEditor()
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    cardLabel("alarm")

                    if let slot = primarySlot {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(slot.alarmTime.displayString)
                                .font(.system(size: 28, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(slot.isEnabled ? Theme.ink : Theme.inkTertiary)

                            if !slot.isEnabled {
                                Text("off")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Theme.inkTertiary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.surfaceMuted, in: .capsule)
                            }
                        }
                        .contentTransition(.numericText())

                        Text(slot.daysSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                    } else {
                        Text("no alarm set. nothing will lock.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)

                        Text("tap to set one")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                Spacer(minLength: 8)

                if primarySlot != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }

    /// A deleted alarm must never be a dead end. Tapping the empty card opens
    /// the same editor over a fresh draft; nothing is saved unless the user
    /// saves it.
    private func openAlarmEditor() {
        if let slot = primarySlot {
            editingSlot = slot
        } else {
            editingSlot = AlarmSlot(
                days: store.schedule.trainingDays,
                alarmTime: rhythm.wakeTime
            )
        }
    }

    private func apply(_ updated: AlarmSlot) {
        if let index = store.plan.slots.firstIndex(where: { $0.id == updated.id }) {
            store.plan.slots[index] = updated
        } else {
            store.plan.slots.append(updated)
        }
        resyncAlarms()
    }

    // MARK: - Sound card

    private var canPreviewBundled: Bool {
        store.profile.alarmSound != .ownSong
    }

    private var isPreviewing: Bool {
        soundPlayer?.playing == store.profile.alarmSound
    }

    private var soundCard: some View {
        HStack(spacing: 14) {
            if canPreviewBundled {
                Button {
                    Haptics.tap()
                    soundPlayer?.toggle(store.profile.alarmSound)
                } label: {
                    Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 42, height: 42)
                        .background(Theme.surfaceMuted, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPreviewing ? "Stop preview" : "Preview sound")
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 42, height: 42)
                    .background(Theme.surfaceMuted, in: .circle)
            }

            Button {
                Haptics.tap()
                isPickingSound = true
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        cardLabel("sound")
                        Text(store.profile.alarmSoundLabel)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(store.profile.alarmSound.subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if isPreviewing {
                        MiniWaveform(level: soundPlayer?.level ?? 0, tint: Theme.inkTertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    // MARK: - Wind-down card

    private var windDownCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.night)
                    .frame(width: 38, height: 38)
                    .background(Theme.night.opacity(0.10), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    cardLabel("wind-down lock")
                    Text(plan.nightLock.summary(in: rhythm))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text(plan.nightLock.followsRhythm ? "follows your sleep times" : "custom window")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer(minLength: 8)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { plan.nightLock.isEnabled },
                        set: { store.plan.nightLock.isEnabled = $0; Haptics.tap() }
                    )
                )
                .labelsHidden()
                .tint(Theme.ink)
            }

            Button {
                Haptics.tap()
                isEditingWindDown = true
            } label: {
                HStack {
                    Text("edit window")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Gym lock card

    private var gymLockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardLabel("gym lock")

            Text("locks when the alarm rings. unlocks when you reach the gym.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            gymLockStatus
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    @ViewBuilder
    private var gymLockStatus: some View {
        let shield = coordinator.shield

        switch shield.authorization {
        case .approved where shield.capability == .familyControls:
            NavigationLink {
                BlockedAppsPush()
            } label: {
                HStack {
                    Text(appsLine(for: shield.selectionCount))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

        case .notDetermined:
            VStack(alignment: .leading, spacing: 8) {
                Text("screen time permission not asked yet.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)

                Button {
                    Task { await shield.requestAuthorization() }
                } label: {
                    Text("allow blocking")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

        case .denied, .revoked:
            // The one place a second coral element earns its place on this
            // screen: something is broken and the user needs to see it.
            Button {
                openSystemSettings()
            } label: {
                HStack {
                    Text("blocking is off in Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

        default:
            Text("demo build: the flow runs, nothing is actually blocked.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// No zero dressed up as a choice. An empty selection says what is true.
    private func appsLine(for count: Int) -> String {
        guard count > 0 else { return "no apps chosen yet" }
        return count == 1 ? "1 app blocked" : "\(count) apps blocked"
    }

    // MARK: - How it rings card

    private var howItRingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardLabel("how it rings")

            Text(coordinator.alarmCapability.headline)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text(coordinator.alarmCapability.explanation)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch alarmAuth {
        case .authorized:
            Text("permission granted")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)

        case .notDetermined:
            Button {
                Task {
                    alarmAuth = await coordinator.requestAlarmAuthorization()
                }
            } label: {
                Text("allow alarms")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surfaceMuted, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

        case .denied:
            // The difference between the product working and not, so it is
            // loud and it leads somewhere.
            Button {
                openSystemSettings()
            } label: {
                HStack {
                    Text("alarm is off in Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var simulatorRow: some View {
        Button {
            Haptics.tap()
            isShowingSimulator = true
        } label: {
            HStack {
                cardLabel("debug")
                Spacer()
                Text("morning simulator")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }
    #endif

    // MARK: - Shared

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Alarm edits must reach the OS, and `replaceAll` is idempotent, so
    /// re-syncing after every change converges rather than duplicating.
    private func resyncAlarms() {
        Task { await coordinator.syncAlarms() }
    }
}

// MARK: - Push destination

/// Wraps the blocked-apps setup for a navigation push, so its done button pops
/// back to the alarm screen instead of reaching for a cover it does not own.
private struct BlockedAppsPush: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BlockedAppsSetupView(onDone: { dismiss() })
    }
}

#Preview("Alarm settings") {
    AlarmSettingsView()
        .environment(AppStore())
        .environment(GymSessionCoordinator())
        .environment(AlarmSoundPlayer())
}
