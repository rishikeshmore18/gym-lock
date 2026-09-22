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
    /// What the finger is holding on the dial, so the header and the line
    /// under the dial can speak to that while the drag is live.
    @State private var dialGrab: DayDialModel.Grab?
    /// The dial edits this, not the plan. Nothing reaches the schedule or the
    /// OS until the tick is tapped and the user says which alarm to change.
    @State private var draft: MorningRhythm?
    @State private var isChoosingScope = false

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
                .safeAreaInset(edge: .top) { header }
            }
            // The header is drawn here rather than put in a toolbar on
            // purpose. A `ToolbarItem` styles its own content on iOS 26, which
            // strips the glass off anything inside it and repaints the glyph
            // with the screen tint — the buttons end up as bare coral ticks.
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.accent)
        .task {
            store.seedPlanIfNeeded()
            if rhythmOnOpen == nil { rhythmOnOpen = store.plan.rhythm }
            coordinator.expireNextAlarmOverrideIfNeeded()
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

    // MARK: - Header

    /// Back on the left, the title in the middle, the tick on the right, the
    /// way Apple lays out a full-screen editor. Content scrolls underneath,
    /// which is what gives the glass something to refract.
    private var header: some View {
        ZStack {
            Text("alarm")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 0) {
                GlassCircleButton(symbol: "chevron.left", label: "Back") {
                    // Leaving with an unsaved dial change throws the draft
                    // away, as Apple's X does. The tick is how you keep it.
                    draft = nil
                    dismiss()
                }
                Spacer(minLength: 0)
                commitButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Commit

    /// The tick, and the question it asks.
    ///
    /// The button is always in the hierarchy and only scales out of sight, so
    /// the dialog it presents always has a live anchor to attach to.
    ///
    /// The question is a `confirmationDialog`, which is the same control
    /// Apple's Clock uses for exactly this choice. It was briefly a popover
    /// hanging off the tick: on an iPhone the tick sits hard against the
    /// trailing edge, and a fixed-width panel anchored there has nowhere to go
    /// but off the screen, which is precisely what happened. The system dialog
    /// places itself, so it cannot be clipped, and it grows properly with
    /// Dynamic Type instead of overflowing a hand-set width.
    private var commitButton: some View {
        GlassCircleButton(symbol: "checkmark", label: "Save change", role: .prominent) {
            isChoosingScope = true
        }
        .scaleEffect(hasDraftChanges ? 1 : 0.35)
        .opacity(hasDraftChanges ? 1 : 0)
        .allowsHitTesting(hasDraftChanges)
        .accessibilityHidden(!hasDraftChanges)
        .animation(.bouncy(duration: 0.42, extraBounce: 0.32), value: hasDraftChanges)
        .confirmationDialog(
            "apply this change to every training day?",
            isPresented: $isChoosingScope,
            titleVisibility: .visible
        ) {
            Button("change this schedule") { commitDraft(scope: .schedule) }
            Button("change next alarm only") { commitDraft(scope: .nextOnly) }
            Button("cancel", role: .cancel) {}
        }
    }

    // MARK: - Dial

    /// What the dial shows: the unsaved draft while one exists, the plan
    /// otherwise.
    private var shown: MorningRhythm { draft ?? rhythm }

    private var hasDraftChanges: Bool {
        guard let draft else { return false }
        return draft != rhythm
    }

    private var dialBinding: Binding<MorningRhythm> {
        Binding(
            get: { draft ?? store.plan.rhythm },
            set: { draft = $0 }
        )
    }

    /// The dial card, after Apple's Change Wake Up screen: the two times on
    /// top, the dial filling the card, one sentence about the result below.
    /// The card takes most of the screen because the dial is the screen.
    private var dialCard: some View {
        VStack(spacing: 0) {
            dialHeader
                .padding(.horizontal, 18)
                .padding(.top, 22)

            GeometryReader { geometry in
                DayDial(
                    rhythm: dialBinding,
                    size: geometry.size.width,
                    onGrabChange: { grab in
                        withAnimation(Theme.stateChange) { dialGrab = grab }
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)

            dialFooter
                .padding(.horizontal, 18)
                .padding(.bottom, overrideLine == nil ? 24 : 14)

            if let overrideLine {
                overrideRow(overrideLine)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity)
        .warmCard(radius: Theme.cardRadius)
        .animation(Theme.stateChange, value: overrideLine)
    }

    /// A one-off change in force, said plainly, with the way out next to it.
    private var overrideLine: String? {
        guard let override = plan.activeOverride() else { return nil }
        let day = Calendar.current.isDateInTomorrow(override.fireDate)
            ? "tomorrow"
            : override.fireDate.formatted(.dateTime.weekday(.wide)).lowercased()
        return "next alarm only: \(override.rhythm.wakeTime.displayString) \(day). the week stays as it was."
    }

    private func overrideRow(_ line: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                store.plan.nextAlarmOverride = nil
                resyncAlarms()
            } label: {
                Text("undo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 12))
    }

    /// The two big numbers above the dial, and what they are about.
    ///
    /// At rest, and while the night is being dragged, they are bedtime and
    /// wake up, exactly as Apple lays it out. While the gym bar is held they
    /// become that bar's own two ends — arrive and done — because those are
    /// the numbers the finger is actually changing, and a header that kept
    /// reporting sleep during a gym drag would be showing two numbers that
    /// never move.
    private var dialHeader: some View {
        let pair = headerPair
        return HStack(alignment: .top) {
            headerTime(
                icon: pair.leading.icon,
                label: pair.leading.label,
                time: pair.leading.time,
                note: pair.leading.note,
                isLive: pair.leading.isLive,
                tint: pair.tint
            )
            Spacer()
            headerTime(
                icon: pair.trailing.icon,
                label: pair.trailing.label,
                time: pair.trailing.time,
                note: pair.trailing.note,
                isLive: pair.trailing.isLive,
                tint: pair.tint,
                alignment: .trailing
            )
        }
        .animation(Theme.stateChange, value: pair.leading.label)
    }

    private struct HeaderSlot {
        let icon: String
        let label: String
        let time: TimeOfDay
        let note: String
        let isLive: Bool
    }

    /// Which pair of times the header is reporting, and in which colour.
    /// Coral while the gym bar is held, because on this screen coral is the
    /// gym and nothing else.
    private var headerPair: (leading: HeaderSlot, trailing: HeaderSlot, tint: Color) {
        if dialGrab?.isGym == true {
            return (
                HeaderSlot(
                    icon: "figure.strengthtraining.traditional",
                    label: "gym",
                    time: shown.gymByTime,
                    note: "arrive",
                    isLive: dialGrab == .gymStart || dialGrab == .gymBody
                ),
                HeaderSlot(
                    icon: "checkmark.circle.fill",
                    label: "done",
                    time: shown.gymDoneTime,
                    note: DayDialModel.durationText(minutes: shown.gymSessionMinutes),
                    isLive: dialGrab == .gymEnd || dialGrab == .gymBody
                ),
                Theme.accent
            )
        }

        return (
            HeaderSlot(
                icon: "bed.double.fill",
                label: "bedtime",
                time: shown.bedtime,
                note: "tonight",
                isLive: dialGrab == .bedtime || dialGrab == .sleepBody
            ),
            HeaderSlot(
                icon: "alarm.fill",
                label: "wake up",
                time: shown.wakeTime,
                note: "tomorrow",
                isLive: dialGrab == .wake || dialGrab == .sleepBody
            ),
            Theme.ink
        )
    }

    private func headerTime(
        icon: String,
        label: String,
        time: TimeOfDay,
        note: String,
        isLive: Bool,
        tint: Color = Theme.ink,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.inkSecondary)

            Text(time.displayString)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .scaleEffect(isLive ? 1.06 : 1, anchor: alignment == .leading ? .leading : .trailing)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isLive)
                .animation(.spring(response: 0.3, dampingFraction: 1), value: time)

            Text(note)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The result, in one line, changing with the finger. Holding the gym end
    /// talks about the gym; anything else talks about the night.
    private var dialFooter: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(footerHeadline)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dialGrab?.isGym == true ? Theme.accent : Theme.ink)
                    .contentTransition(.numericText())
            }
            .animation(.spring(response: 0.3, dampingFraction: 1), value: footerHeadline)

            Text(footerLine)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(Theme.stateChange, value: footerLine)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var footerHeadline: String {
        switch dialGrab {
        case .gymStart, .gymBody:
            return "\(DayDialModel.durationText(minutes: shown.gapToGymMinutes)) to the gym"
        case .gymEnd:
            return "\(DayDialModel.durationText(minutes: shown.gymSessionMinutes)) at the gym"
        default:
            return "\(DayDialModel.durationText(minutes: shown.sleepMinutes)) of sleep"
        }
    }

    /// Guardrails live inline, never in an alert. Otherwise the line says
    /// what the schedule actually does.
    private var footerLine: String {
        if let guardrail = guardrailLine { return guardrail }
        switch dialGrab {
        case .gymStart, .gymBody:
            return "gym by \(shown.gymByTime.displayString). apps lock when the alarm rings."
        case .gymEnd:
            return "done by \(shown.gymDoneTime.displayString)."
        default:
            let sleep = shown.sleepMinutes
            if sleep < 6 * 60 { return "that's a short night. the alarm won't care." }
            if sleep >= 7 * 60 { return "this schedule gives you a full night." }
            return "a bit under seven hours. workable."
        }
    }

    /// Guardrails live inline, never in an alert.
    ///
    /// The gym bar itself has no ceiling any more, so this no longer refuses a
    /// late workout. What it does instead is say the true thing about what the
    /// lock actually covers, because the block is still a run-up and stops
    /// well short of an afternoon session.
    private var guardrailLine: String? {
        if shown.gapToGymMinutes > MorningRhythm.absoluteMaximumWindow {
            return "the lock covers the first 2 hours after the alarm."
        }
        if shown.exceedsNormalMaximum {
            return "that's a long window. still fine."
        }
        if shown.isBelowMinimum {
            return "that's under 10 minutes. you'll be rushing."
        }
        return nil
    }

    /// Only a morning slot is coupled to the sleep rhythm; an evening alarm is
    /// set from its own editor and never silently rewritten by the dial.
    private var primaryMorningSlotIndex: Int? {
        guard let primary = primarySlot, primary.daypart.usesSleepRhythm else { return nil }
        return store.plan.slots.firstIndex { $0.id == primary.id }
    }

    private enum CommitScope { case nextOnly, schedule }

    /// The tick was tapped and the user said which alarm to change. This is
    /// the one place a dial change reaches the plan, the night lock and the
    /// OS.
    private func commitDraft(scope: CommitScope) {
        guard let draft else { return }
        Haptics.commit()

        switch scope {
        case .schedule:
            let previous = rhythmOnOpen ?? store.plan.rhythm
            var updated = draft
            updated.hasBeenSet = true
            store.plan.rhythm = updated
            // The alarm going off and getting up are one event, so the dial
            // writes the alarm too and the user is never asked twice.
            if let index = primaryMorningSlotIndex {
                store.plan.slots[index].alarmTime = updated.wakeTime
            }
            // A schedule change makes any lingering one-off meaningless.
            store.plan.nextAlarmOverride = nil

            if let prompt = RhythmChangeProposer.prompt(for: updated, since: previous, plan: plan) {
                nightLockPrompt = prompt
            } else {
                store.applyRhythmToNightLock()
                rhythmOnOpen = updated
            }

        case .nextOnly:
            guard let slot = primarySlot else { break }
            // The next training day, at the new wake time. If today's alarm
            // has already gone the next one is tomorrow or later.
            if let fireDate = draft.wakeTime.nextDate(after: Date(), on: slot.days) {
                store.plan.nextAlarmOverride = NextAlarmOverride(
                    slotID: slot.id,
                    fireDate: fireDate,
                    rhythm: draft
                )
            }
        }

        self.draft = nil
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

    /// Saves an edited alarm, and moves wake time with it.
    ///
    /// The alarm going off and getting up are the same event, so being asked
    /// for both was asking the same question twice — and the two could end up
    /// disagreeing, with the dial drawing one time and the alarm ringing at
    /// another. Setting either now sets both. Only a morning alarm is coupled;
    /// an evening session has nothing to do with the sleep rhythm.
    private func apply(_ updated: AlarmSlot) {
        if let index = store.plan.slots.firstIndex(where: { $0.id == updated.id }) {
            store.plan.slots[index] = updated
        } else {
            store.plan.slots.append(updated)
        }

        if updated.isEnabled, updated.daypart.usesSleepRhythm, updated.id == primarySlot?.id {
            let previous = rhythmOnOpen ?? store.plan.rhythm
            // An unsaved dial edit is the newer intent, so the new alarm time
            // is folded into it rather than throwing it away.
            if draft != nil {
                draft?.setWakeTime(updated.alarmTime)
            } else {
                store.plan.rhythm.setWakeTime(updated.alarmTime)
                store.plan.rhythm.hasBeenSet = true
                if let prompt = RhythmChangeProposer.prompt(for: store.plan.rhythm, since: previous, plan: store.plan) {
                    nightLockPrompt = prompt
                } else {
                    store.applyRhythmToNightLock()
                    rhythmOnOpen = store.plan.rhythm
                }
            }
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
                        set: {
                            store.plan.nightLock.isEnabled = $0
                            Haptics.tap()
                            // Switching it on while inside the window should
                            // take hold now, not on the next foreground.
                            coordinator.reconcileWindDown()
                        }
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

            // What actually happens with the chosen track, which is not the
            // same as what the system alarm rings with.
            Text(ringerExplanation)
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

    /// Honest about the split between the two sounds.
    ///
    /// With AlarmKit the system rings first with its own tone and the chosen
    /// track starts once the app is open, because custom sounds are broken on
    /// iOS 26.0. Saying otherwise would be a lie the user finds out about at
    /// 6:30 in the morning.
    private var ringerExplanation: String {
        switch coordinator.alarmCapability {
        case .systemAlarm:
            "your track plays once you open the app, and keeps going until you answer."
        case .notification:
            "your track plays through the notification, then again in the app."
        }
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
