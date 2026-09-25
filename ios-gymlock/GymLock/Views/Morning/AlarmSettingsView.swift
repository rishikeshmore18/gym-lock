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
    /// Whether the snooze length wheel is open inside the options card.
    @State private var isEditingSnooze = false
    /// Debounces pushing a new snooze length to the OS while the wheel spins.
    @State private var snoozeSync: Task<Void, Never>?
    @State private var isEditingWindDown = false
    @State private var alarmAuth: AlarmAuthorization = .notDetermined
    /// What the finger is holding on the dial, so the header and the line
    /// under the dial can speak to that while the drag is live.
    @State private var dialGrab: DayDialModel.Grab?
    /// Which arc the user last touched. Unlike `dialGrab` this survives the
    /// finger lifting, so the header, the line under the dial and the day
    /// card keep talking about the gym after a gym drag. Screen-local only.
    @State private var dialContext: AlarmDialContext = .initial
    /// The quiet line under the day circles after a required night is tapped.
    @State private var requiredNightNote: String?
    @State private var noteDismissal: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The dial edits this, not the plan. Nothing reaches the schedule or the
    /// OS until the tick is tapped and the user says which alarm to change.
    @State private var draft: MorningRhythm?
    @State private var isChoosingScope = false
    /// Drives the title's collapse, exactly as on the Progress tab.
    @State private var scrollOffset: CGFloat = 0

    /// Height the header row reserves at the top of the content.
    ///
    /// A fixed number, not a measured one, and that is the whole point. The
    /// header holds the collapsing title, whose size is driven by the scroll
    /// offset; feeding a measurement of that row back into the scroll view's
    /// insets is what froze this screen, so the room it needs is stated once
    /// here instead. 44pt button + 2 top + 4 bottom, rounded up for air.
    private static let headerBand: CGFloat = 52

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
                        // The room the fixed header row occupies. The header is
                        // drawn in an overlay rather than as a safe-area inset
                        // of this scroll view, so this is what keeps the first
                        // card clear of it. See `header`.
                        Color.clear.frame(height: Self.headerBand)

                        dialCard
                        repeatCard
                        alarmOptionsCard
                        windDownCard
                        gymLockCard
                        howItRingsCard

                        #if DEBUG
                        simulatorRow
                        #endif
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
                .overlay(alignment: .top) { header }
            }
            .navigationDestination(for: AlarmOptionRoute.self) { route in
                switch route {
                case .sound: AlarmSoundListView()
                case .haptics: AlarmHapticsListView()
                case .song: SongTrimmerView(presentation: .pushed)
                case .alarmScreen: AlarmScreenPickerView(stored: store.plan.alarmScreenStyle)
                }
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

    /// Back on the left, the tick on the right, the title between them — and
    /// that title behaves exactly as the Progress tab's does: large at rest,
    /// shrinking into a floating glass pill as the page scrolls under it.
    ///
    /// The title is a layer of its own inside the row rather than a third
    /// item in the `HStack`, for two reasons. It stays dead centre on the
    /// screen no matter how wide either button is or whether the tick is
    /// currently scaled out of sight; and because it starts centred it has no
    /// sideways journey to make, so the collapse is purely a shrink in place
    /// with the glass arriving around it. That is what makes it read as the
    /// page title turning into the bubble, rather than sliding off somewhere.
    ///
    /// There is no hairline under this row. The pill appearing is already the
    /// signal that content has gone underneath, so a rule as well would be
    /// the same thing said twice, and it cut across the dial card at exactly
    /// the moment the card slid beneath it.
    private var header: some View {
        ZStack {
            CollapsingTitle(
                title: "Alarm",
                collapse: CollapsingTitleMetrics.collapse(forOffset: scrollOffset),
                overscroll: CollapsingTitleMetrics.overscroll(forOffset: scrollOffset),
                // Unused for a centred title: it holds the centre line through
                // the stack's own alignment rather than by measurement.
                containerWidth: 0,
                start: .centred,
                expandedSize: 30
            )

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
        .padding(.top, 2)
        .padding(.bottom, 4)
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
                        let context = dialContext.updated(with: grab)
                        if context != dialContext { clearRequiredNightNote() }
                        withAnimation(Theme.stateChange) {
                            dialGrab = grab
                            dialContext = context
                        }
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
    /// In the sleep context they are bedtime and wake up, exactly as Apple
    /// lays it out. Once the gym bar has been touched they become that bar's
    /// own two ends, arrive and done, and stay that way after the finger
    /// lifts until the night is touched again. Which pair shows follows
    /// `dialContext`; which number is live follows `dialGrab`.
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
    /// Coral in the gym context, because on this screen coral is the gym and
    /// nothing else.
    private var headerPair: (leading: HeaderSlot, trailing: HeaderSlot, tint: Color) {
        if dialContext == .gym {
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

    /// The result, in one line, changing with the finger. While a drag is
    /// live it speaks to exactly what is held; at rest it summarises the
    /// context the user last touched.
    private var dialFooter: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(footerHeadline)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dialContext == .gym ? Theme.accent : Theme.ink)
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
        case .bedtime, .wake, .sleepBody:
            return "\(DayDialModel.durationText(minutes: shown.sleepMinutes)) of sleep"
        case nil:
            switch dialContext {
            case .gym:
                return "\(DayDialModel.durationText(minutes: shown.gymSessionMinutes)) at the gym"
            case .sleep:
                return "\(DayDialModel.durationText(minutes: shown.sleepMinutes)) of sleep"
            }
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
        case nil where dialContext == .gym:
            return "gym at \(shown.gymByTime.displayString) · done by \(shown.gymDoneTime.displayString)"
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

    // MARK: - Repeat card

    /// Which days this alarm runs on, and nothing else.
    ///
    /// This replaced a card that showed the alarm time with a chevron into an
    /// editor holding a time wheel and these same day buttons. Now that the
    /// dial above sets the alarm, that card was reporting a number the user
    /// had just set two inches higher, and its editor asked for it a third
    /// time. The time is gone; only the part the dial cannot express is left.
    ///
    /// Apple's own Repeat row is the model, down to the row of day circles.
    /// There is no "never" option: an alarm repeating on nothing is not a
    /// value to choose, it is an alarm that will not ring, and the card says
    /// exactly that when it happens instead of offering it as a setting.
    ///
    /// One card, two meanings. It follows `dialContext`: gym days after the
    /// gym bar was touched, the sleep schedule after the night was. Only the
    /// title, the summary and the filled circles change; the card itself
    /// stays exactly where and what it is, so it reads as the same row
    /// changing meaning under the dial rather than a new thing arriving.
    private var repeatCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: switchDialContext) {
                    Text(dialContext.dayCardTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.opacity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(dialContext == .sleep ? "shows gym days" : "shows sleep schedule")

                Spacer(minLength: 8)

                Text(dayCardSummary)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .animation(Theme.stateChange, value: dialContext)
            .animation(Theme.stateChange, value: dayCardSummary)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    dayCircle(day)
                }
            }

            if let requiredNightNote {
                Text(requiredNightNote)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .offset(y: -4))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22)
        .animation(.easeOut(duration: 0.18), value: requiredNightNote)
        .accessibilityElement(children: .contain)
        .onDisappear { noteDismissal?.cancel() }
    }

    /// Tapping the card title flips the screen to the other arc, exactly as
    /// touching that arc on the dial would.
    private func switchDialContext() {
        clearRequiredNightNote()
        Haptics.selection()
        withAnimation(Theme.stateChange) {
            dialContext = dialContext == .sleep ? .gym : .sleep
        }
    }

    /// Nights the gym days require, measured against what the dial is
    /// showing. An unsaved draft that stops crossing midnight frees them at
    /// once, and cancelling the draft brings them back, with nothing stored.
    private var requiredNights: Set<Weekday> {
        plan.requiredSleepNights(for: shown)
    }

    /// The circles that read as filled in the current context.
    private var dayCardDays: Set<Weekday> {
        switch dialContext {
        case .gym: plan.gymDays
        case .sleep: plan.effectiveSleepDays(for: shown)
        }
    }

    /// The truth about what this schedule does, not a value to pick. Listing
    /// the days here would only repeat the circles underneath, so the slot
    /// says the one thing the circles cannot say on their own.
    private var dayCardSummary: String {
        dialContext.daySummary(count: dayCardDays.count)
    }

    private func dayCircle(_ day: Weekday) -> some View {
        let isOn = dayCardDays.contains(day)
        let isRequired = dialContext == .sleep && requiredNights.contains(day)

        return Button {
            switch dialContext {
            case .gym: toggleGymDay(day)
            case .sleep: toggleSleepNight(day)
            }
        } label: {
            Text(String(day.shortLabel.prefix(1)))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isOn ? Color.white : Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isOn ? Theme.ink : Theme.surfaceMuted, in: .circle)
                .scaleEffect(isOn ? 1 : 0.94)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dialContext == .sleep ? "\(day.spokenName) night" : day.shortLabel)
        .accessibilityHint(isRequired ? "needed before \(day.next.spokenName)'s gym day" : "")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Turns a training day on or off on the one alarm. The rules live on
    /// the plan; the view only pushes what they say changed.
    private func toggleGymDay(_ day: Weekday) {
        Haptics.selection()
        let effects = store.plan.toggleGymDay(day, newAlarmTime: shown.wakeTime)
        apply(effects)
    }

    /// Turns a sleep night on or off, or says quietly why it cannot.
    private func toggleSleepNight(_ night: Weekday) {
        let result = store.plan.toggleSleepNight(night, rhythm: shown)
        switch result.outcome {
        case .updated:
            Haptics.selection()
            clearRequiredNightNote()
        case let .required(night, gymDay):
            // A tap that explains rather than selects.
            Haptics.soft()
            showRequiredNightNote(SleepSchedule.requiredMessage(night: night, gymDay: gymDay))
        }
        apply(result.effects)
    }

    /// Gym days rebuild the OS alarms; sleep nights only touch wind-down.
    private func apply(_ effects: MorningPlan.DayEditEffects) {
        if effects.contains(.resyncGymAlarms) { resyncAlarms() }
        if effects.contains(.reconcileWindDown) { coordinator.reconcileWindDown() }
    }

    /// Shows the note for a couple of seconds, restarting the clock if
    /// another required night is tapped meanwhile, and reads it aloud.
    private func showRequiredNightNote(_ message: String) {
        requiredNightNote = message
        AccessibilityNotification.Announcement(message).post()
        noteDismissal?.cancel()
        noteDismissal = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            requiredNightNote = nil
        }
    }

    private func clearRequiredNightNote() {
        noteDismissal?.cancel()
        noteDismissal = nil
        requiredNightNote = nil
    }

    // MARK: - Alarm options card

    /// Sound, snooze and persistent mode, grouped after Apple's Edit Alarm
    /// and dressed exactly like the repeat card above it: the same glass,
    /// radius, padding and hairlines, so the two read as one family.
    ///
    /// The snooze length opens *inside* the card, as Apple's does. The card
    /// grows around the wheel on a critically damped spring rather than
    /// presenting a sheet, because the choice is small and the context (the
    /// toggle just above it) should stay in view while it is made.
    ///
    /// No coral here: on this screen the single accent belongs to the gym
    /// arc on the dial, so the open duration reads in ink weight instead.
    private var alarmOptionsCard: some View {
        AlarmGroupCard {
            NavigationLink(value: AlarmOptionRoute.sound) {
                AlarmValueRow(title: "sound", value: store.profile.alarmSoundLabel)
            }
            .buttonStyle(AlarmRowButtonStyle())

            AlarmRowDivider()

            snoozeToggleRow

            if plan.snoozeEnabled {
                AlarmRowDivider()
                    .transition(.opacity)

                snoozeDurationRow
                    .transition(.opacity.combined(with: .move(edge: .top)))

                if isEditingSnooze {
                    snoozeWheel
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }

            AlarmRowDivider()

            persistentModeRow

            AlarmRowDivider()

            NavigationLink(value: AlarmOptionRoute.alarmScreen) {
                AlarmValueRow(title: "alarm screen", value: plan.alarmScreenStyle.label)
            }
            .buttonStyle(AlarmRowButtonStyle())
        }
        .animation(Self.cardSpring, value: plan.snoozeEnabled)
        .animation(Self.cardSpring, value: isEditingSnooze)
    }

    /// Critically damped: the card grows and settles with no overshoot, and
    /// a second tap mid-flight retargets from wherever it is.
    private static let cardSpring: Animation = .spring(response: 0.36, dampingFraction: 1)

    private var snoozeToggleRow: some View {
        Toggle(isOn: Binding(
            get: { plan.snoozeEnabled },
            set: { isOn in
                Haptics.tap()
                store.plan.snoozeEnabled = isOn
                if !isOn { isEditingSnooze = false }
                resyncAlarms()
            }
        )) {
            Text("snooze")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .tint(Theme.ink)
        .frame(minHeight: 50)
    }

    private var snoozeDurationRow: some View {
        Button {
            Haptics.tap()
            isEditingSnooze.toggle()
        } label: {
            AlarmValueRow(
                title: "snooze duration",
                value: "\(plan.snoozeMinutes) min",
                showsChevron: false,
                valueIsActive: isEditingSnooze
            )
            .animation(.spring(response: 0.3, dampingFraction: 1), value: plan.snoozeMinutes)
        }
        .buttonStyle(AlarmRowButtonStyle())
        .accessibilityHint(isEditingSnooze ? "Hides the minutes" : "Shows the minutes")
    }

    /// Apple's own wheel, so the roll, the momentum, the detents and the
    /// ticks are the system's rather than an imitation of them.
    private var snoozeWheel: some View {
        Picker("snooze duration", selection: snoozeMinutesBinding) {
            ForEach(Array(MorningPlan.snoozeRange), id: \.self) { minutes in
                Text("\(minutes) min")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .tag(minutes)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipped()
        .padding(.bottom, 6)
    }

    private var snoozeMinutesBinding: Binding<Int> {
        Binding(
            get: { plan.snoozeMinutes },
            set: { minutes in
                store.plan.snoozeMinutes = minutes
                // The system alarm's snooze button names the minutes, so the
                // OS needs the new length, but not once per detent of a spin.
                snoozeSync?.cancel()
                snoozeSync = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    await coordinator.syncAlarms()
                }
            }
        )
    }

    /// Activation missions, renamed for what they feel like from the bed:
    /// the alarm does not simply let you go. Same switch, same behaviour.
    private var persistentModeRow: some View {
        Toggle(isOn: Binding(
            get: { plan.missionsEnabled },
            set: { isOn in
                Haptics.tap()
                store.plan.missionsEnabled = isOn
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("persistent mode")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("prove you're up with one quick task.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.ink)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
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
