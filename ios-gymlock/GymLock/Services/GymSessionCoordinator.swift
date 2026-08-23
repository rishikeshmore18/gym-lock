import Foundation
import Observation

/// Which screen the morning flow should be showing.
///
/// Derived from `GymSession.state` rather than stored, so there is exactly one
/// thing to get right and the UI can never disagree with the session.
enum MorningRoute: Equatable {
    case decision
    case mission
    case countdown
    case departed
    case plansChanged
    case quickWorkoutPicker
    case quickWorkoutActive
    case momentumSaved
    case cantToday
    case gymSuccess
}

/// Runs the morning.
///
/// Everything that can happen between an alarm going off and the day being
/// resolved passes through here: committing, missions, the countdown, departure,
/// extensions, expiry, fallbacks, and the honest recording of what actually
/// occurred.
///
/// Two properties are worth calling out.
///
/// **The countdown is a deadline, not a timer.** The session stores an absolute
/// `Date`, and every reading is `deadline - now`. Kill the app, reboot the
/// phone, fly through a timezone: reopening recomputes the truth instead of
/// starting again at 35:00.
///
/// **Nothing here enforces app blocking.** That is FamilyControls' job and it is
/// deliberately not built yet. The state machine is shaped so it can be added
/// without rework — `.preparing` is where a shield would be applied and
/// `.gymWorkoutVerified` is where it would lift — but no screen claims blocking
/// is happening today.
@Observable
@MainActor
final class GymSessionCoordinator {
    private enum Key {
        static let session = "gymlock.activeSession"
    }

    /// The morning in progress, if there is one.
    private(set) var session: GymSession?
    /// Set when the user has left and the confirmation screen has not been seen.
    private(set) var isShowingDepartureMoment = false
    /// Set at 75% of the preparation window, once.
    private(set) var isShowingPreparationNudge = false

    private let defaults: UserDefaults
    private let notifier: MorningNotifier
    private let location: SessionLocationMonitor
    private let alarms: any AlarmScheduling

    private var ticker: Task<Void, Never>?

    /// Injected so the coordinator can read the plan and write outcomes without
    /// owning a second copy of either.
    private weak var store: AppStore?

    /// Collaborators are optional rather than defaulted inline: both are
    /// `@MainActor` types, and a default argument is evaluated in a nonisolated
    /// context where they cannot be constructed.
    init(
        defaults: UserDefaults = .standard,
        notifier: MorningNotifier? = nil,
        location: SessionLocationMonitor? = nil,
        alarms: (any AlarmScheduling)? = nil
    ) {
        self.defaults = defaults
        self.notifier = notifier ?? MorningNotifier()
        self.location = location ?? SessionLocationMonitor()
        self.alarms = alarms ?? AlarmSchedulerFactory.make()
    }

    // MARK: - Wiring

    func attach(to store: AppStore) {
        self.store = store
        restore()
    }

    var alarmCapability: AlarmDeliveryCapability { alarms.capability }

    var locationMonitor: SessionLocationMonitor { location }

    // MARK: - Derived

    var isSessionLive: Bool { session?.state.isLive ?? false }

    /// The screen the flow should present.
    var route: MorningRoute? {
        guard let session, session.state.isLive else { return nil }

        switch session.state {
        case .alarmFired, .awaitingDecision:
            return .decision
        case .activationMission:
            return .mission
        case .preparing, .approachingGym, .arrivedPendingWorkout:
            return isShowingDepartureMoment ? .departed : .countdown
        case .departed:
            return isShowingDepartureMoment ? .departed : .countdown
        case .windowExpired:
            return .plansChanged
        case .quickWorkoutOffered:
            return .quickWorkoutPicker
        case .quickWorkoutActive:
            return .quickWorkoutActive
        case .homeWorkoutVerified:
            return .momentumSaved
        case .gymWorkoutVerified:
            return .gymSuccess
        case .cantToday:
            return .cantToday
        default:
            return nil
        }
    }

    /// Whether the window has run out while the user was still getting ready.
    var hasExpiredUnresolved: Bool {
        guard let session else { return false }
        return session.state == .windowExpired
    }

    // MARK: - Scheduling alarms

    /// Pushes the current plan to the OS.
    ///
    /// A whole-set replace, so editing a slot cannot leave the old alarm behind
    /// and re-running this on every launch converges rather than accumulating.
    func syncAlarms() async {
        guard let store else { return }
        let plan = store.plan
        let profile = store.profile

        let requests = plan.enabledSlots.map { slot in
            GymAlarmRequest(
                slotID: slot.id,
                time: slot.alarmTime,
                weekdays: slot.days,
                title: "Gym time",
                message: "You planned this.",
                soundResource: profile.alarmSound.resourceName
            )
        }

        await alarms.replaceAll(with: requests)
    }

    func alarmAuthorization() async -> AlarmAuthorization {
        await alarms.authorizationStatus()
    }

    @discardableResult
    func requestAlarmAuthorization() async -> AlarmAuthorization {
        await alarms.requestAuthorization()
    }

    // MARK: - Starting a morning

    /// Called when an alarm fires, or when the user opens the app during a
    /// window that has already begun.
    func beginSession(for slot: AlarmSlot?, at date: Date = Date()) {
        guard let store else { return }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        // Two sessions in one day are legitimate, but the *same* session
        // reopening is not a new one.
        if let existing = session, existing.state.isLive, existing.slotID == slot?.id {
            return
        }

        let plan = store.plan
        let alarmTime = slot?.alarmTime ?? plan.rhythm.wakeTime
        let daypart = SessionDaypart(alarmTime)

        var new = GymSession(
            day: day,
            slotID: slot?.id,
            alarmTime: alarmTime,
            isMorningSession: daypart.usesSleepRhythm,
            getReadyMinutes: plan.rhythm.getReadyMinutes,
            travelMinutes: plan.rhythm.travelMinutes,
            state: .alarmFired
        )
        new.alarmFiredAt = date

        session = new
        persist()
        startTicking()
    }

    /// Lets a user who woke up before the alarm start anyway.
    ///
    /// The window is measured from the moment they commit, not from the alarm
    /// they beat, so being early is rewarded with a calmer morning rather than
    /// with a countdown that has already partly elapsed.
    func startEarly() {
        guard let store else { return }
        let next = store.plan.nextOccurrence()
        beginSession(for: next?.slot)
    }

    /// Whether "start early" is worth offering: a session is planned today and
    /// none is already running.
    var canStartEarly: Bool {
        guard session == nil, let store else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard let today = Weekday(rawValue: weekday) else { return false }
        return store.plan.enabledSlots.contains { $0.days.contains(today) }
    }

    // MARK: - The decision

    /// "I'm going."
    ///
    /// The single most important transition in the app. From this instant the
    /// alarm stops escalating: the commitment has been made, and continuing to
    /// shout at someone who already agreed is how trust gets spent.
    func commitToGoing() {
        guard var current = session else { return }

        current.committedAt = Date()
        current.state = .activationMission

        // A temporary anchor, captured now and deleted when the session ends.
        // Never labelled or stored as a home address.
        if let anchor = location.beginSession(onDeparture: { [weak self] in
            Task { @MainActor in self?.markDeparted(detected: true) }
        }) {
            current.anchor = anchor
        }

        session = current

        if store?.plan.missionsEnabled == true {
            assignMission()
        } else {
            beginPreparation()
        }

        persist()
        startTicking()
    }

    /// Pushes today's session later without abandoning it.
    ///
    /// Genuinely a move, not a dismissal: a one-off reminder is placed at the
    /// new time and the recurring alarms are left alone, so tomorrow is
    /// unaffected. The user gets one of these per session — it is offered from
    /// the decision screen only, before any commitment has been made.
    func moveTodaysTime(by minutes: Int) {
        guard var current = session else { return }

        let newTime = Date().addingTimeInterval(Double(minutes) * 60)
        current.state = .rescheduled
        session = current

        Task { [notifier] in
            await notifier.scheduleMovedSession(at: newTime)
        }

        store?.log.record(SessionOutcome(kind: .rescheduled))
        // The notification above is scheduled before the session is torn down,
        // and `endSession` only clears the session-scoped reminders it owns.
        endSession(clearingAnchor: true, keepingReminders: true)
    }

    // MARK: - Missions

    /// Capabilities the device can currently verify with.
    func availableCapabilities(
        camera: Bool,
        motion: Bool,
        speech: Bool
    ) -> Set<MissionCapability> {
        var set: Set<MissionCapability> = []
        if camera { set.insert(.camera) }
        if motion { set.insert(.motion) }
        if speech { set.insert(.speech) }
        return set
    }

    /// Chooses a mission the device can actually verify, avoiding a repeat.
    func assignMission(capabilities: Set<MissionCapability>? = nil) {
        guard var current = session, let store else { return }

        // Before permissions have been probed, assume motion — the fallback
        // mission needs nothing but the pedometer, and the screen re-rolls once
        // it knows more.
        let usable = capabilities ?? [.motion]
        let previous = store.plan.recentMissions.last

        let chosen = ActivationMissionType.next(
            available: usable,
            excluding: previous,
            allowingOwnershipMissions: store.usesGymBag
        ) ?? ActivationMissionType.universalFallback

        current.mission = chosen
        current.missionStartedAt = Date()
        current.mirrorPhraseIndex = Int.random(in: 0..<ActivationMissionType.mirrorPhrases.count)
        current.state = .activationMission
        session = current

        store.rememberMission(chosen)
        persist()
    }

    /// "Another mission." Always available, so nobody is ever trapped.
    func rerollMission(capabilities: Set<MissionCapability>) {
        guard var updated = session else { return }

        let candidates = ActivationMissionType.candidates(
            available: capabilities,
            excluding: updated.mission,
            allowingOwnershipMissions: store?.usesGymBag ?? false
        )

        let chosen = candidates.randomElement() ?? ActivationMissionType.universalFallback
        updated.mission = chosen
        updated.missionStartedAt = Date()
        updated.mirrorPhraseIndex = Int.random(in: 0..<ActivationMissionType.mirrorPhrases.count)
        session = updated

        store?.rememberMission(chosen)
        persist()
        Haptics.tap()
    }

    /// Lets the user pick a specific mission from the list.
    func chooseMission(_ mission: ActivationMissionType) {
        guard var current = session else { return }
        current.mission = mission
        current.missionStartedAt = Date()
        session = current
        store?.rememberMission(mission)
        persist()
        Haptics.tap()
    }

    func completeMission() {
        guard var current = session else { return }
        current.missionCompletedAt = Date()
        session = current
        Haptics.commit()
        beginPreparation()
    }

    /// Skips the mission entirely. Available from the mission screen so an
    /// accessibility need, a broken sensor, or a bad morning cannot block a
    /// user who has already committed.
    func skipMission() {
        beginPreparation()
    }

    // MARK: - Preparation

    /// Opens the window and sets the one true deadline.
    func beginPreparation() {
        guard var current = session else { return }

        let now = Date()
        current.state = .preparing
        if current.committedAt == nil { current.committedAt = now }
        current.deadline = now.addingTimeInterval(Double(current.windowMinutes) * 60)
        session = current

        persist()
        startTicking()

        let gymBy = TimeOfDay(from: current.deadline ?? now).displayString
        Task { [notifier] in
            await notifier.scheduleDeadlineReminder(at: current.deadline ?? now, gymBy: gymBy)
        }
    }

    /// The single permitted extension.
    func extendWindow(by minutes: Int = GymSession.defaultExtensionMinutes) {
        guard var current = session, current.canExtend else { return }

        let granted = min(minutes, GymSession.maximumExtensionMinutes)
        current.extensionMinutesUsed = granted
        current.deadline = (current.deadline ?? Date()).addingTimeInterval(Double(granted) * 60)
        session = current

        isShowingPreparationNudge = false
        persist()
        Haptics.tap()

        let gymBy = TimeOfDay(from: current.deadline ?? Date()).displayString
        Task { [notifier] in
            await notifier.scheduleDeadlineReminder(at: current.deadline ?? Date(), gymBy: gymBy)
        }
    }

    func dismissPreparationNudge() {
        isShowingPreparationNudge = false
    }

    // MARK: - Departure

    /// Marks the user as having left, either detected or self-declared.
    ///
    /// Exactly one positive notification, and no alarm ever again for this
    /// session.
    func markDeparted(detected: Bool) {
        guard var current = session, current.departedAt == nil else { return }

        current.departedAt = Date()
        current.state = .departed
        session = current

        isShowingPreparationNudge = false
        isShowingDepartureMoment = true
        Haptics.tap()

        let previous = store?.lastDepartureMessageIndex
        Task { [notifier] in
            let used = await notifier.sendDeparture(previousIndex: previous)
            await MainActor.run {
                self.store?.lastDepartureMessageIndex = used
                if var updated = self.session {
                    updated.departureMessageIndex = used
                    self.session = updated
                    self.persist()
                }
            }
        }

        // The anchor has done its job; it is not kept a moment longer.
        location.endSession()
        if var updated = session {
            updated.anchor = nil
            session = updated
        }

        persist()
    }

    func acknowledgeDeparture() {
        isShowingDepartureMoment = false
    }

    // MARK: - Expiry

    /// The window ran out.
    ///
    /// This opens "plans changed?", not the fallback picker. Someone whose timer
    /// expired ninety seconds from the gym should not be handed a home workout
    /// as their first option.
    func handleExpiry() {
        guard var current = session else { return }
        guard current.state == .preparing || current.state == .departed else { return }

        current.state = .windowExpired
        session = current
        isShowingPreparationNudge = false
        persist()

        Task { [notifier] in await notifier.cancelDeadlineReminder() }
    }

    /// "Still going" on the expired screen: a short grace period, not a restart.
    ///
    /// Restarting the full window would make the deadline decorative. The grace
    /// is fixed and does not consume the user's one extension, because it is a
    /// different thing — an acknowledgement that they are nearly there.
    func grantGrace() {
        guard var current = session else { return }
        current.state = current.departedAt == nil ? .preparing : .departed
        current.deadline = Date().addingTimeInterval(Double(GymSession.graceMinutes) * 60)
        session = current
        persist()
        Haptics.tap()
    }

    // MARK: - Quick workout

    func offerQuickWorkout() {
        guard var current = session else { return }
        current.state = .quickWorkoutOffered
        session = current
        persist()
    }

    /// Backing out of the fallback picker returns the user where they came
    /// from, rather than dumping everyone on the same screen.
    func leaveQuickWorkoutPicker() {
        guard var current = session else { return }
        current.state = current.deadline.map { $0 <= Date() } == true
            ? .windowExpired
            : .cantToday
        session = current
        persist()
    }

    func startQuickWorkout(minutes: Int) {
        guard var current = session else { return }
        let now = Date()
        current.state = .quickWorkoutActive
        current.quickWorkoutMinutes = minutes
        current.quickWorkoutStartedAt = now
        current.quickWorkoutDeadline = now.addingTimeInterval(Double(minutes) * 60)
        session = current
        persist()
        Haptics.medium()

        location.endSession()
    }

    /// Finishes a home workout.
    ///
    /// `wasCompleted` is honest: a user who stops early is recorded as not
    /// having finished, and their momentum is not credited.
    func finishQuickWorkout(completed wasCompleted: Bool) {
        guard var current = session else { return }

        if wasCompleted {
            current.state = .homeWorkoutVerified
            session = current
            store?.log.record(
                SessionOutcome(kind: .homeWorkout, minutes: current.quickWorkoutMinutes)
            )
            Haptics.commit()
            persist()
        } else {
            current.state = .missed
            session = current
            store?.log.record(SessionOutcome(kind: .missed))
            endSession(clearingAnchor: true)
        }
    }

    // MARK: - Can't today

    func beginCantToday() {
        guard var current = session else { return }
        current.state = .cantToday
        session = current
        persist()
    }

    /// Whether the user still has a no-questions-asked skip.
    var hasEasySkipRemaining: Bool {
        guard let store else { return true }
        return store.log.hasEasySkipRemaining(
            plannedSessionsIn28Days: store.plan.plannedSessionsPer28Days
        )
    }

    var easySkipAllowance: Int {
        guard let store else { return 1 }
        return MomentumLog.easySkipAllowance(
            plannedSessionsIn28Days: store.plan.plannedSessionsPer28Days
        )
    }

    var easySkipsUsed: Int { store?.log.skipsUsedInLast28Days() ?? 0 }

    func resolveCantToday(_ resolution: CantTodayResolution) {
        guard var current = session else { return }
        current.cantTodayResolution = resolution

        switch resolution {
        case .quickWorkout:
            current.state = .quickWorkoutOffered
            session = current
            persist()

        case .rescheduledWithin24h:
            current.state = .rescheduled
            session = current
            store?.log.record(SessionOutcome(kind: .rescheduled))
            scheduleComebackIfEnabled()
            endSession(clearingAnchor: true)

        case .tookTheDayOff:
            current.state = .completed
            session = current
            let kind: SessionOutcomeKind = hasEasySkipRemaining ? .easySkip : .dayOff
            store?.log.record(SessionOutcome(kind: kind))
            scheduleComebackIfEnabled()
            endSession(clearingAnchor: true)
        }
    }

    /// Comeback Mode prepares the next realistic opportunity. It never
    /// references what was missed and never asks for anything to be made up.
    private func scheduleComebackIfEnabled() {
        guard let store, store.profile.comebackModeEnabled else { return }
        guard let next = store.plan.nextOccurrence() else { return }

        Task { [notifier] in
            await notifier.scheduleComeback(at: next.fireDate)
        }
    }

    // MARK: - Gym verification

    /// Reserved for the real location and workout verification.
    ///
    /// Nothing calls these with invented data. They exist so the state machine
    /// already has the shape the gym flow will need.
    func recordGymArrival() {
        guard var current = session else { return }
        current.locationVerified = true
        current.state = .arrivedPendingWorkout
        session = current
        persist()
    }

    func recordGymWorkout() {
        guard var current = session else { return }
        current.workoutVerified = true
        current.state = .gymWorkoutVerified
        session = current
        store?.log.record(SessionOutcome(kind: .gymVerified))
        Haptics.commit()
        persist()
    }

    // MARK: - Finishing

    /// Closes out the morning and clears every session-scoped resource.
    func endSession(clearingAnchor: Bool = true, keepingReminders: Bool = false) {
        ticker?.cancel()
        ticker = nil

        if clearingAnchor { location.endSession() }

        isShowingDepartureMoment = false
        isShowingPreparationNudge = false
        session = nil
        defaults.removeObject(forKey: Key.session)

        guard !keepingReminders else { return }
        Task { [notifier] in await notifier.cancelSessionNotifications() }
    }

    /// Dismisses a result screen once the user has read it.
    func acknowledgeResult() {
        endSession(clearingAnchor: true)
    }

    // MARK: - Persistence

    private func persist() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Key.session)
    }

    /// Rebuilds an interrupted morning.
    ///
    /// Because the deadline is absolute, this is genuinely a restore rather than
    /// a restart: a session whose window quietly ran out while the app was
    /// closed reopens on the "plans changed?" screen, not on a fresh countdown.
    private func restore() {
        guard let data = defaults.data(forKey: Key.session),
              let stored = try? JSONDecoder().decode(GymSession.self, from: data)
        else { return }

        // Anything from a previous day is stale. Waking up to yesterday's
        // half-finished countdown would be worse than no memory at all.
        guard Calendar.current.isDateInToday(stored.day) else {
            defaults.removeObject(forKey: Key.session)
            return
        }

        guard stored.state.isLive else {
            defaults.removeObject(forKey: Key.session)
            return
        }

        session = stored

        if let anchor = stored.anchor, stored.departedAt == nil {
            location.resume(from: anchor) { [weak self] in
                Task { @MainActor in self?.markDeparted(detected: true) }
            }
        }

        if stored.hasExpired, stored.state == .preparing || stored.state == .departed {
            handleExpiry()
        }

        startTicking()
    }

    // MARK: - Ticking

    /// A one-second loop that only watches for the two moments the flow has to
    /// react to on its own: the 75% nudge and the deadline.
    ///
    /// The countdown text is not driven from here — that is a `TimelineView`
    /// reading the deadline directly, which stays correct even if this task is
    /// suspended in the background.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await MainActor.run { self.tick() }
            }
        }
    }

    private func tick() {
        guard var current = session else {
            ticker?.cancel()
            ticker = nil
            return
        }

        guard current.state == .preparing || current.state == .departed else { return }

        if current.hasExpired {
            handleExpiry()
            return
        }

        // The nudge only makes sense for someone who has not left yet.
        guard current.departedAt == nil, !current.hasShownPreparationNudge else { return }

        if current.elapsedFraction() >= GymSession.nudgeFraction {
            current.hasShownPreparationNudge = true
            session = current
            isShowingPreparationNudge = true
            persist()
        }
    }
}

// MARK: - Debug simulation

#if DEBUG
extension GymSessionCoordinator {
    /// Drives the flow to any point without waiting for a real morning.
    ///
    /// Compiled out of release builds entirely, so there is no path by which a
    /// shipping user can reach a simulated state.
    enum DebugStep: String, CaseIterable, Identifiable {
        case alarmFired
        case imGoing
        case missionComplete
        case departed
        case countdownAt75
        case countdownExpired
        case cantTodayWithinAllowance
        case cantTodayOverAllowance
        case homeWorkoutCompleted
        case gymArrival
        case gymWorkoutCompleted

        var id: String { rawValue }

        var label: String {
            switch self {
            case .alarmFired: "alarm fired"
            case .imGoing: "tapped I'm going"
            case .missionComplete: "mission complete"
            case .departed: "departed"
            case .countdownAt75: "countdown at 75%"
            case .countdownExpired: "countdown expired"
            case .cantTodayWithinAllowance: "can't today (within allowance)"
            case .cantTodayOverAllowance: "can't today (over allowance)"
            case .homeWorkoutCompleted: "home workout completed"
            case .gymArrival: "gym arrival"
            case .gymWorkoutCompleted: "gym workout completed"
            }
        }
    }

    func simulate(_ step: DebugStep) {
        switch step {
        case .alarmFired:
            endSession()
            beginSession(for: store?.plan.enabledSlots.first)

        case .imGoing:
            if session == nil { beginSession(for: store?.plan.enabledSlots.first) }
            commitToGoing()

        case .missionComplete:
            if session == nil { simulate(.imGoing) }
            completeMission()

        case .departed:
            if session == nil { simulate(.missionComplete) }
            if session?.state == .activationMission { beginPreparation() }
            markDeparted(detected: false)

        case .countdownAt75:
            if session?.state != .preparing { simulate(.missionComplete) }
            guard var current = session, let committed = current.committedAt else { return }
            let total = Double(current.windowMinutes) * 60
            current.deadline = committed.addingTimeInterval(total)
            // Rewind the start so the clock reads three-quarters gone.
            current.committedAt = Date().addingTimeInterval(-total * GymSession.nudgeFraction)
            current.deadline = Date().addingTimeInterval(total * (1 - GymSession.nudgeFraction))
            current.hasShownPreparationNudge = false
            session = current
            isShowingPreparationNudge = true

        case .countdownExpired:
            if session?.state != .preparing { simulate(.missionComplete) }
            guard var current = session else { return }
            current.deadline = Date().addingTimeInterval(-1)
            current.state = .preparing
            session = current
            handleExpiry()

        case .cantTodayWithinAllowance:
            store?.debugClearSkips()
            if session == nil { beginSession(for: store?.plan.enabledSlots.first) }
            beginCantToday()

        case .cantTodayOverAllowance:
            store?.debugExhaustSkips(count: easySkipAllowance)
            if session == nil { beginSession(for: store?.plan.enabledSlots.first) }
            beginCantToday()

        case .homeWorkoutCompleted:
            if session == nil { beginSession(for: store?.plan.enabledSlots.first) }
            startQuickWorkout(minutes: 20)
            finishQuickWorkout(completed: true)

        case .gymArrival:
            if session == nil { simulate(.departed) }
            recordGymArrival()

        case .gymWorkoutCompleted:
            if session == nil { simulate(.gymArrival) }
            recordGymWorkout()
        }
    }
}
#endif
