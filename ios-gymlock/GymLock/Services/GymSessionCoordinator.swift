import Foundation
import Observation
import UIKit

/// Which screen the morning flow should be showing.
///
/// Derived from `GymSession.state` rather than stored, so there is exactly one
/// thing to get right and the UI can never disagree with the session.
enum MorningRoute: Equatable {
    case decision
    case mission
    case countdown
    case departed
    case confirmingArrival
    case arrivalTrouble
    case plansChanged
    case quickWorkoutPicker
    case quickWorkoutActive
    case momentumSaved
    case cantToday
    case gymSuccess
}

/// Runs the morning, from the alarm to whatever actually happened.
///
/// The shape of this type follows the product's central claim: **make the
/// decision hard to avoid, then get out of the way.** Up to the point the user
/// says "I'm going" the app is deliberately in their face. After the activation
/// mission it becomes almost entirely passive — geofence, dwell, unlock — and
/// the user should be able to complete a whole gym session without touching
/// GymLock again.
///
/// Three properties are worth calling out.
///
/// **The countdown is a deadline, not a timer.** The session stores an absolute
/// `Date`, and every reading is `deadline - now`. Kill the app, reboot the
/// phone, fly through a timezone: reopening recomputes the truth.
///
/// **Arrival unlocks; a workout does not gate anything.** A user with no watch
/// and no tracker has exactly the same experience as one with both. Requiring
/// `HKWorkout` before returning somebody's apps would punish them for their
/// choice of hardware.
///
/// **Apps always come back.** Every lock carries a deadline, the shield service
/// keeps its own independent ledger, and the failsafe runs on every foreground.
/// There is no path through this class that can leave a phone shielded forever.
@Observable
@MainActor
final class GymSessionCoordinator {
    private enum Key {
        static let session = "gymlock.activeSession"
        /// Slots already resolved today, as `"<slotID>|<yyyy-MM-dd>"`.
        ///
        /// Without this, someone who says "can't today" at 6:35 and reopens the
        /// app at 6:50 has their apps locked again by the clock check. That is
        /// the single worst bug this feature could ship with.
        static let resolvedSlots = "gymlock.alarm.resolvedSlots"
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

    let shield: any AppShielding
    let arrival: GymArrivalMonitor
    let health: HealthWorkoutObserver

    private var ticker: Task<Void, Never>?
    /// The long-lived observers, held somewhere that can clean itself up.
    private let observers = AlarmObserverBag()
    /// The evening lock. Independent of the session: it holds the shield by
    /// the clock, and only ever inside its own window.
    let windDown = WindDownController()
    /// The sound the user wakes up to, once the app is frontmost.
    let ringer = AlarmRinger()

    /// Injected so the coordinator can read the plan and write outcomes without
    /// owning a second copy of either.
    private weak var store: AppStore?

    /// Collaborators are optional rather than defaulted inline: they are
    /// `@MainActor` types, and a default argument is evaluated in a nonisolated
    /// context where they cannot be constructed.
    init(
        defaults: UserDefaults = .standard,
        notifier: MorningNotifier? = nil,
        location: SessionLocationMonitor? = nil,
        alarms: (any AlarmScheduling)? = nil,
        shield: (any AppShielding)? = nil,
        arrival: GymArrivalMonitor? = nil,
        health: HealthWorkoutObserver? = nil
    ) {
        self.defaults = defaults
        self.notifier = notifier ?? MorningNotifier()
        self.location = location ?? SessionLocationMonitor()
        self.alarms = alarms ?? AlarmSchedulerFactory.make()
        self.shield = shield ?? AppShieldingFactory.make(defaults: defaults)
        self.arrival = arrival ?? GymArrivalMonitor()
        self.health = health ?? HealthWorkoutObserver(defaults: defaults)
    }

    // MARK: - Wiring

    func attach(to store: AppStore) {
        self.store = store

        shield.refreshAuthorization()
        arrival.refreshAvailability()
        health.refreshAvailability()

        // Before anything else: if a shield outlived its deadline while the app
        // was closed, lift it now.
        enforceShieldFailsafe()

        restore()
        armArrivalIfPossible()
        startHealthObservation()
        observeAlarmFiring()
        observeHandoffNotifications()

        // A cold launch from an alarm tap has no scene-phase change to wait
        // for: the app is already active by the time this runs.
        resumeSessionIfDue()
        reconcileWindDown()
    }

    /// The second belt on door one.
    ///
    /// The stop intent is the fast path and usually wins. This catches the
    /// cases it cannot see, most importantly a dismissal from the Lock Screen
    /// that never runs an intent at all.
    private func observeAlarmFiring() {
        #if canImport(AlarmKit)
        guard !observers.hasAlarmObserver, #available(iOS 26.0, *),
              let scheduler = alarms as? AlarmKitAlarmScheduler
        else { return }

        observers.hold(alarm: scheduler.observeAlarmUpdates { id in
            // Writing rather than starting directly: this arrives off the main
            // actor, and the handoff's one-shot take is what stops the intent
            // and this observer from starting two sessions for one alarm.
            AlarmHandoff.write(.init(slotID: id, firedAt: Date(), wantsSnooze: false))
            Task { @MainActor [weak self] in self?.resumeSessionIfDue() }
        })
        #endif
    }

    /// An intent running while the app is already frontmost produces no scene
    /// phase change, so the note would sit there until the next backgrounding.
    private func observeHandoffNotifications() {
        guard !observers.hasHandoffObserver else { return }

        observers.hold(handoff: NotificationCenter.default.addObserver(
            forName: .gymLockAlarmHandoffAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeSessionIfDue() }
        })
    }

    var alarmCapability: AlarmDeliveryCapability { alarms.capability }
    var shieldCapability: ShieldCapability { shield.capability }
    var locationMonitor: SessionLocationMonitor { location }

    /// Called on every foreground.
    ///
    /// Three cheap, idempotent checks that between them recover from anything
    /// that happened while the app was not running.
    func applicationDidBecomeActive() {
        enforceShieldFailsafe()
        reconcileShieldWithSession()
        // A snooze that ran out while the app was backgrounded must resolve the
        // moment the user looks at the phone. Without this, someone who taps
        // "5 more min" and puts the phone down could come back to a screen
        // still promising an alarm that already passed.
        resolveElapsedSnooze()
        // Door three: the user ignored the alarm and simply opened the app.
        resumeSessionIfDue()
        // Door four, in effect: the evening lock catches up with the clock.
        reconcileWindDown()
        Task { await health.fetchNewWorkouts() }
    }

    // MARK: - Starting the morning from outside the app

    /// Starts or resumes the morning when the app comes back to life.
    ///
    /// Three inputs, in priority order: a note left by the alarm's own button, a
    /// note left by a notification response, and, if neither exists, the plain
    /// question of whether the clock is inside a window that should already have
    /// begun.
    func resumeSessionIfDue(at now: Date = Date()) {
        guard let store else { return }

        let isLive = session?.state.isLive ?? false
        let resolution = SessionResume.resolve(
            now: now,
            isSessionLive: isLive,
            liveSlotID: isLive ? session?.slotID : nil,
            liveSessionDay: isLive ? session?.day : nil,
            handoff: AlarmHandoff.peek(now: now),
            slots: store.plan.slots,
            windowMinutes: store.plan.windowMinutes,
            resolvedKeys: resolvedSlotKeys,
            alarmSlotIDs: store.plan.nextAlarmOverride.map { [$0.id: $0.slotID] } ?? [:]
        )

        // Cleared when acted on, and when it is a note for a day already
        // settled or for the morning already running. A note for a different
        // slot during a live session is left to wait.
        if resolution.clearsHandoff {
            AlarmHandoff.clear()
        }

        guard let decision = resolution.decision else { return }

        // A one-off alarm carries its own id; the plan maps it back to its slot.
        let slot = store.plan.slot(forAlarmID: decision.slotID)

        // `startAt` rather than `now`: the deadline is measured from when the
        // alarm actually rang, so ignoring it for ten minutes does not quietly
        // buy ten more minutes.
        beginSession(for: slot, at: decision.startAt)

        if decision.wantsSnooze {
            snooze()
        }
    }

    // MARK: - Wind-down

    /// Brings the evening lock in line with the clock and its notification
    /// with the plan.
    ///
    /// Called on attach and on every foreground, and after any edit to the
    /// wind-down window, because a user setting the window at 11:15 while
    /// standing inside it should see the lock go on without a relaunch.
    func reconcileWindDown(now: Date = Date()) {
        guard let store else { return }
        windDown.reconcile(now: now, plan: store.plan, shield: shield)
        syncWindDownNotification(plan: store.plan)
    }

    /// One heads-up at the window's start, cancelled the moment the lock is
    /// off. It exists because the lock engages on the next run of the app, and
    /// the notification is what gives the evening a next run.
    private func syncWindDownNotification(plan: MorningPlan) {
        let notifier = self.notifier
        guard plan.nightLock.isEnabled else {
            Task { await notifier.cancelWindDownStart() }
            return
        }

        // Only a night the sleep schedule is in force on, keyed by the day
        // the window starts. `nextDate(on:)` reads an empty set as "any
        // day", so no nights at all is handled here as no notification.
        let nights = plan.effectiveSleepDays()
        let start = nights.isEmpty
            ? nil
            : plan.nightLock.start(in: plan.rhythm).nextDate(after: Date(), on: nights)
        Task {
            if let start {
                await notifier.scheduleWindDownStart(at: start)
            } else {
                await notifier.cancelWindDownStart()
            }
        }
    }

    // MARK: - Resolved slots

    private var resolvedSlotKeys: Set<String> {
        Set(defaults.stringArray(forKey: Key.resolvedSlots) ?? [])
    }

    /// Remembers that this slot is finished for today.
    ///
    /// Only today's keys are kept, so the list cannot grow without bound and a
    /// key from last Tuesday can never suppress this Tuesday's alarm.
    private func markSlotResolved(_ session: GymSession, at now: Date = Date()) {
        let todayKey = SessionResume.dayKey(for: now)
        let key = SessionResume.resolvedKey(slotID: session.slotID, day: now)

        var kept = resolvedSlotKeys.filter { $0.hasSuffix("|\(todayKey)") }
        kept.insert(key)
        defaults.set(Array(kept), forKey: Key.resolvedSlots)
    }

    // MARK: - Derived

    var isSessionLive: Bool { session?.state.isLive ?? false }

    /// The screen the flow should present.
    var route: MorningRoute? {
        guard let session, session.state.isLive else { return nil }

        switch session.state {
        // A running snooze stays on the decision screen. The screen itself
        // knows it is counting down, which keeps the five minutes and the
        // decision in one place rather than inventing a screen the user has to
        // be moved off again.
        case .alarmFired, .awaitingDecision, .snoozed:
            return .decision
        case .activationMission:
            return .mission
        case .preparing:
            return isShowingDepartureMoment ? .departed : .countdown
        case .departed:
            return isShowingDepartureMoment ? .departed : .countdown
        case .approachingGym:
            return .confirmingArrival
        case .arrived:
            return .gymSuccess
        case .arrivalTrouble:
            return .arrivalTrouble
        case .windowExpired:
            return .plansChanged
        case .quickWorkoutOffered:
            return .quickWorkoutPicker
        case .quickWorkoutActive:
            return .quickWorkoutActive
        case .homeWorkoutVerified:
            return .momentumSaved
        case .cantToday:
            return .cantToday
        default:
            return nil
        }
    }

    var hasExpiredUnresolved: Bool {
        session?.state == .windowExpired
    }

    // MARK: - Shield

    /// Applies the shield for the active session.
    ///
    /// Called at the start of a morning and re-asserted on foreground. Safe to
    /// call repeatedly: the shield service overwrites rather than stacks.
    private func applyShield(for session: GymSession) {
        guard shield.hasSelection else { return }

        let deadline = ShieldPolicy.deadline(forWindowMinutes: session.windowMinutes)

        // The handover. If the wind-down lock currently owns the shield, this
        // call takes ownership in one step: the shield is re-applied with the
        // session's own deadline and the owner flips to `.gymSession` with no
        // release in between, so there is never a second where the blocked
        // apps are free between the night and the morning.
        shield.apply(until: deadline, sessionID: session.id, owner: .gymSession)

        if var updated = self.session {
            updated.shieldFailsafeDeadline = deadline
            self.session = updated
            persist()
        }

        store?.record(.shieldApplied, sessionID: session.id)
    }

    /// Lifts the shield because the user earned it or resolved the day.
    ///
    /// Only the gym session's own shield answers to the session. A wind-down
    /// shield belongs to the night and is released by the clock, never by
    /// something the morning did.
    private func releaseShield(sessionID: UUID?) {
        guard shield.isShielded else { return }
        guard shield.owner == .gymSession || shield.owner == nil else { return }
        shield.release()
        store?.record(.shieldRemoved, sessionID: sessionID)
    }

    /// The hard safety net.
    ///
    /// Runs on launch and on every foreground. If a lock has outlived its
    /// deadline for any reason — a crash, corrupted state, a callback that never
    /// arrived — the apps come back and the release is recorded as technical.
    /// No gym visit is credited, and nothing punishes the user for it.
    private func enforceShieldFailsafe() {
        guard shield.enforceFailsafe(now: Date()) else { return }

        store?.record(.technicalRelease, detail: "failsafe deadline reached")

        guard var current = session else { return }
        current.wasTechnicallyReleased = true
        session = current
        persist()
    }

    /// Makes the shield match the session after time has passed unobserved.
    ///
    /// Both directions matter. A morning that started while the app was closed
    /// needs its shield applied; a session that ended needs it gone.
    private func reconcileShieldWithSession() {
        guard let current = session, current.state.isLive else {
            if shield.isShielded {
                if shield.owner == .windDown {
                    // The night lock answers for itself, against its own
                    // window, not against the session.
                    reconcileWindDown()
                } else {
                    releaseShield(sessionID: nil)
                }
            }
            return
        }

        if current.state.wantsShield {
            if !shield.isShielded { applyShield(for: current) }
        } else if shield.isShielded {
            releaseShield(sessionID: current.id)
        }
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

        let soundFile = notificationSoundFileName(for: profile)
        var requests = plan.enabledSlots.map { slot in
            GymAlarmRequest(
                slotID: slot.id,
                time: slot.alarmTime,
                weekdays: slot.days,
                title: "Gym time",
                message: "You planned this.",
                soundResource: profile.alarmSound.resourceName,
                // The notification backend needs the caf, not the mp3: the
                // system sound facility cannot decode mp3 and silently plays
                // its own default instead.
                soundFileName: soundFile,
                // The alert is built by the system long before the app runs, so
                // the morning-only snooze rule has to be decided here.
                allowsSnooze: plan.snoozeEnabled && slot.daypart.usesSleepRhythm,
                snoozeMinutes: plan.snoozeMinutes
            )
        }

        // "Change next alarm only": one extra alarm at the one-off time, and
        // the weekly alarm skips that day so the two never both ring.
        if let override = plan.activeOverride(), override.fireDate > Date(),
           let slot = plan.slots.first(where: { $0.id == override.slotID }), slot.isEnabled,
           let day = override.weekday() {
            if let index = requests.firstIndex(where: { $0.slotID == slot.id }) {
                requests[index].weekdays.remove(day)
                if requests[index].weekdays.isEmpty { requests.remove(at: index) }
            }
            requests.append(
                GymAlarmRequest(
                    slotID: override.id,
                    time: TimeOfDay(from: override.fireDate),
                    weekdays: [day],
                    title: "Gym time",
                    message: "You planned this.",
                    soundResource: profile.alarmSound.resourceName,
                    soundFileName: soundFile,
                    allowsSnooze: plan.snoozeEnabled
                        && SessionDaypart(TimeOfDay(from: override.fireDate)).usesSleepRhythm,
                    snoozeMinutes: plan.snoozeMinutes,
                    fireDate: override.fireDate
                )
            )
        }

        // The notification's snooze button carries the chosen length, so its
        // label is re-registered whenever the plan is pushed to the OS.
        AlarmNotificationDelegate.registerCategories(
            snoozeMinutes: plan.snoozeMinutes,
            snoozeEnabled: plan.snoozeEnabled
        )

        await alarms.replaceAll(with: requests)
    }

    /// Drops a one-off alarm once its morning is over, so the weekly alarm
    /// for that day comes back on the next sync.
    func expireNextAlarmOverrideIfNeeded(now: Date = Date()) {
        guard let store, let override = store.plan.nextAlarmOverride,
              !override.isActive(at: now)
        else { return }
        store.plan.nextAlarmOverride = nil
        Task { await syncAlarms() }
    }

    /// Which file a notification should name, following the same fallback
    /// chain the ringer uses so both agree on what "your alarm sound" means.
    private func notificationSoundFileName(for profile: OnboardingProfile) -> String? {
        if profile.alarmSound == .ownSong {
            // The trimmer exports a caf sibling into Library/Sounds precisely
            // so the notification has something legal to play.
            if let custom = profile.customAlarmSoundFile {
                let caf = (custom as NSString).deletingPathExtension + ".caf"
                if AlarmTrackResolver.customSongExists(named: caf) { return caf }
            }
            return (profile.previousBundledSound ?? AlarmTrackResolver.guaranteed)
                .notificationFileName
        }
        return profile.alarmSound.notificationFileName
    }

    func alarmAuthorization() async -> AlarmAuthorization {
        await alarms.authorizationStatus()
    }

    @discardableResult
    func requestAlarmAuthorization() async -> AlarmAuthorization {
        await alarms.requestAuthorization()
    }

    // MARK: - Arrival wiring

    /// Registers the gym geofence.
    ///
    /// Armed permanently rather than per session: region monitoring survives
    /// termination and reboot, and that persistence is exactly what lets arrival
    /// be noticed without the user opening anything.
    func armArrivalIfPossible() {
        guard let gym = store?.primaryGym else { return }
        arrival.refreshAvailability()
        guard arrival.canDetectArrival else { return }
        arrival.arm(for: gym)
    }

    private func beginWatchingForArrival() {
        guard let gym = store?.primaryGym, arrival.canDetectArrival else { return }

        arrival.beginWatching(
            gym: gym,
            onCandidate: { [weak self] in
                Task { @MainActor in self?.noteArrivalCandidate() }
            },
            onArrival: { [weak self] in
                Task { @MainActor in self?.confirmArrival() }
            },
            onTrouble: { [weak self] _ in
                Task { @MainActor in self?.reportArrivalTrouble() }
            }
        )
    }

    /// The phone entered the gym region. Not success yet.
    private func noteArrivalCandidate() {
        guard var current = session, current.state.isLive else { return }
        guard current.arrivalCandidateAt == nil else { return }
        guard current.state == .preparing || current.state == .departed else { return }

        current.arrivalCandidateAt = Date()
        current.state = .approachingGym
        session = current
        persist()

        store?.record(.gymArrivalCandidate, sessionID: current.id)
    }

    /// Confirmed. This is the moment the whole product exists to reach.
    ///
    /// Everything happens without the user touching anything: the visit is
    /// recorded, the apps come back, and one notification says so. No "tap to
    /// unlock", no reopening GymLock, no proving anything further.
    func confirmArrival() {
        guard var current = session, current.state.isLive else { return }
        guard !current.gymArrivalVerified else { return }

        let now = Date()
        current.arrivedAt = now
        current.gymArrivalVerified = true
        current.hadArrivalTrouble = false
        current.state = .arrived
        session = current

        // Showing up is the outcome. A workout, if Health ever reports one,
        // attaches to this same record later rather than creating a second one.
        store?.log.record(
            SessionOutcome(date: now, kind: .showedUp, sessionID: current.id)
        )
        store?.record(.gymArrivalVerified, sessionID: current.id)

        releaseShield(sessionID: current.id)
        location.endSession()

        Haptics.commit()
        persist()

        Task { [notifier] in
            await notifier.cancelDeadlineReminder()
            await notifier.sendArrival()
        }

        // A workout may already be sitting in Health from an earlier arrival
        // this morning; check once rather than waiting for the observer.
        Task { await matchWorkoutForCurrentSession() }
    }

    /// Detection failed for technical reasons.
    ///
    /// Deliberately its own state, and deliberately never recorded as a missed
    /// workout. The user may well be standing in their gym; the phone simply
    /// could not prove it.
    private func reportArrivalTrouble() {
        guard var current = session, current.state.isLive else { return }
        guard current.state == .approachingGym || current.state == .departed else { return }

        current.hadArrivalTrouble = true
        current.state = .arrivalTrouble
        session = current
        persist()

        store?.record(.technicalFailure, sessionID: current.id, detail: "arrival not confirmed")
    }

    /// Lets the user jump to the trouble screen from the confirming state.
    ///
    /// Someone standing in their gym watching "confirming arrival…" should not
    /// have to wait out the full timeout before being offered a way through.
    func reportArrivalTroubleManually() {
        guard var current = session, current.state == .approachingGym else { return }
        current.hadArrivalTrouble = true
        current.state = .arrivalTrouble
        session = current
        persist()
        store?.record(.technicalFailure, sessionID: current.id, detail: "user asked for help")
    }

    /// The user says they are at the gym after automatic detection failed.
    ///
    /// Only reachable from the trouble screen. Someone locked out of their apps
    /// while standing in their gym must have a way forward that does not depend
    /// on satellite reception.
    func confirmArrivalManually() {
        arrival.acceptManualConfirmation()
        confirmArrival()
    }

    /// Gives up on confirming and releases the apps without crediting a visit.
    func releaseAfterArrivalTrouble() {
        guard let current = session else { return }

        releaseShield(sessionID: current.id)
        store?.log.record(
            SessionOutcome(date: Date(), kind: .technicalFailure, sessionID: current.id)
        )
        store?.record(.technicalRelease, sessionID: current.id, detail: "user released")

        var updated = current
        updated.wasTechnicallyReleased = true
        session = updated
        persist()

        endSession(clearingAnchor: true)
    }

    /// Retries confirmation from the trouble screen.
    func retryArrival() {
        guard var current = session else { return }
        current.state = .departed
        current.arrivalCandidateAt = nil
        current.hadArrivalTrouble = false
        session = current
        persist()

        beginWatchingForArrival()
    }

    // MARK: - Health

    private func startHealthObservation() {
        guard health.isUsable else { return }

        health.startObserving { [weak self] workout in
            Task { @MainActor in self?.attach(workout) }
        }
    }

    func requestHealthAuthorization() async {
        _ = await health.requestAuthorization()
        startHealthObservation()
        await matchWorkoutForCurrentSession()
    }

    /// Attaches a newly seen workout to whichever session it belongs to.
    ///
    /// A workout is written when it *ends*, so this routinely runs an hour or
    /// more after the user arrived. It never creates a session — it only enriches
    /// one that already exists.
    private func attach(_ workout: DetectedWorkout) {
        guard let store else { return }

        // The live session first, then today's completed one. Nothing older is
        // considered: a workout from three days ago is not evidence about today.
        if var current = session,
           let window = current.workoutMatchWindow,
           window.contains(workout.startedAt) || window.contains(workout.endedAt) {
            guard !current.workoutDetected else { return }

            current.workoutDetected = true
            current.detectedWorkout = workout
            session = current
            persist()

            store.log.attachWorkout(toSession: current.id)
            store.record(.workoutDetected, sessionID: current.id, detail: workout.summary)
            return
        }

        // A session that already closed this morning.
        guard let todays = store.log.outcome(on: workout.startedAt),
              !todays.workoutDetected,
              let sessionID = todays.sessionID
        else { return }

        store.log.attachWorkout(toSession: sessionID)
        store.record(.workoutDetected, sessionID: sessionID, detail: workout.summary)
    }

    /// Looks for a workout matching the live session, on demand.
    private func matchWorkoutForCurrentSession() async {
        guard health.isUsable,
              let current = session,
              let window = current.workoutMatchWindow,
              !current.workoutDetected
        else { return }

        let found = await health.workouts(in: window)
        guard let first = found.first else { return }
        attach(first)
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
        // The rhythm for *this* morning: a one-off change if the user made
        // one for today, the weekly schedule otherwise.
        let rhythm = plan.rhythm(at: date, calendar: calendar)
        let isOverrideMorning = plan.activeOverride(at: date).map {
            calendar.isDate(date, inSameDayAs: $0.fireDate) && $0.slotID == slot?.id
        } ?? false
        let alarmTime = isOverrideMorning ? rhythm.wakeTime : (slot?.alarmTime ?? plan.rhythm.wakeTime)
        let daypart = SessionDaypart(alarmTime)

        var new = GymSession(
            day: day,
            slotID: slot?.id,
            alarmTime: alarmTime,
            isMorningSession: daypart.usesSleepRhythm,
            getReadyMinutes: rhythm.getReadyMinutes,
            travelMinutes: rhythm.travelMinutes,
            state: .alarmFired
        )
        new.alarmFiredAt = date
        new.snoozeOffered = plan.snoozeEnabled
        new.snoozeLengthMinutes = plan.snoozeMinutes

        session = new
        store.record(.alarmFired, sessionID: new.id)

        // The shield goes on here, not after "I'm going". The product exists
        // precisely for the moment another app wins the argument, and that
        // moment is the thirty seconds after the alarm.
        applyShield(for: new)

        // The chosen track, which is a separate thing from whatever the system
        // alarm just rang with.
        startRingingIfFrontmost()

        persist()
        startTicking()
    }

    /// Plays the user's own track, but only with a screen in front of them.
    ///
    /// AlarmKit rings with the system sound because custom sounds are broken on
    /// iOS 26.0, and the stop intent is what brings the app forward. That makes
    /// this the moment the real track starts. Starting it from a background
    /// launch would burn battery playing to nobody.
    private func startRingingIfFrontmost() {
        guard let store else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        ringer.haptic = store.plan.alarmHaptic
        ringer.start(for: store.profile)
    }

    /// Lets a user who woke up before the alarm start anyway.
    func startEarly() {
        guard let store else { return }
        let next = store.plan.nextOccurrence()
        beginSession(for: next?.slot)
    }

    /// Whether "start early" is worth offering.
    var canStartEarly: Bool {
        guard session == nil, let store else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard let today = Weekday(rawValue: weekday) else { return false }
        return store.plan.enabledSlots.contains { $0.days.contains(today) }
    }

    // MARK: - The decision

    /// "I'm going."
    ///
    /// The alarm stops escalating here. The shield is already on and stays
    /// exactly as it is — tapping this must not make the phone *more* punishing,
    /// because the user just did the thing the app wanted.
    func commitToGoing() {
        guard var current = session else { return }

        // The user is up and has decided. Nothing about this moment should
        // still be shouting at them.
        ringer.stop()

        current.committedAt = Date()
        current.snoozeExpiresAt = nil
        current.state = .activationMission

        // A snooze re-fire arriving after the user is already up would be the
        // app waking someone who is standing in their kitchen.
        Task { [notifier] in await notifier.cancelSnoozeRefire() }

        // A temporary anchor, captured now and deleted when the session ends.
        // Never labelled or stored as a home address.
        if let anchor = location.beginSession(onDeparture: { [weak self] in
            Task { @MainActor in self?.markDeparted(detected: true) }
        }) {
            current.anchor = anchor
        }

        session = current
        store?.record(.committed, sessionID: current.id)

        if store?.plan.missionsEnabled == true {
            assignMission()
        } else {
            beginPreparation()
        }

        persist()
        startTicking()
    }

    // MARK: - Snooze

    /// The one snooze.
    ///
    /// Deliberately not a general-purpose delay. The apps stay locked, the
    /// session stays live, and the button is not offered again for the rest of
    /// this session — `snoozeUsedAt` being set is the whole rule, so there is
    /// no counter to display and nobody gets told off for using it once.
    ///
    /// Morning only: someone whose alarm rings after work is already awake, and
    /// a snooze there would be a procrastination button at exactly the moment
    /// the product exists to remove procrastination.
    func snooze() {
        guard var current = session else { return }
        guard SessionVoice(session: current).allowsSnooze else { return }
        guard current.state == .alarmFired || current.state == .awaitingDecision else { return }

        // Silence now, and ring again when the snooze runs out.
        ringer.stop()

        let now = Date()
        current.snoozeUsedAt = now
        current.snoozeExpiresAt = now.addingTimeInterval(Double(current.snoozeDurationMinutes) * 60)
        current.state = .snoozed
        session = current

        store?.record(.snoozed, sessionID: current.id)
        Haptics.soft()
        persist()

        // Two belts. The ticker resolves it while the app is open; the
        // notification covers the far more likely case of a phone going back
        // face-down on the nightstand.
        startTicking()
        Task { [notifier] in
            await notifier.scheduleSnoozeRefire(
                at: current.snoozeExpiresAt ?? now,
                minutes: current.snoozeDurationMinutes
            )
        }
    }

    /// Brings the alarm back after the snooze has run out.
    ///
    /// Idempotent: a re-fire that arrives after the user already resolved the
    /// day is dropped, because `state` is no longer `.snoozed`.
    func resolveElapsedSnooze(at now: Date = Date()) {
        guard var current = session, current.snoozeHasElapsed(at: now) else { return }

        current.state = .awaitingDecision
        current.snoozeExpiresAt = nil
        session = current
        persist()

        // The shield never came off, so there is nothing to re-apply — only the
        // decision to put back in front of the user.
        Haptics.medium()

        // The whole point of a snooze is that the alarm comes back.
        startRingingIfFrontmost()
    }

    /// Pushes today's session later without abandoning it.
    func moveTodaysTime(by minutes: Int) {
        guard var current = session else { return }

        let newTime = Date().addingTimeInterval(Double(minutes) * 60)
        current.state = .rescheduled
        session = current

        // The shield follows the decision: moving the session moves the lock
        // rather than leaving the user blocked for a commitment that is no
        // longer live.
        releaseShield(sessionID: current.id)

        Task { [notifier] in
            await notifier.scheduleMovedSession(at: newTime)
        }

        store?.log.record(SessionOutcome(kind: .rescheduled, sessionID: current.id))
        store?.record(.rescheduled, sessionID: current.id)
        endSession(clearingAnchor: true, keepingReminders: true)
    }

    // MARK: - Missions

    func availableCapabilities(camera: Bool, motion: Bool, speech: Bool) -> Set<MissionCapability> {
        var set: Set<MissionCapability> = []
        if camera { set.insert(.camera) }
        if motion { set.insert(.motion) }
        if speech { set.insert(.speech) }
        return set
    }

    /// Chooses a mission the device can actually verify, avoiding a repeat.
    func assignMission(capabilities: Set<MissionCapability>? = nil) {
        guard var current = session, let store else { return }

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
        store?.record(.missionCompleted, sessionID: current.id, detail: current.mission?.rawValue)
        Haptics.commit()
        beginPreparation()
    }

    func skipMission() {
        beginPreparation()
    }

    // MARK: - Preparation

    /// Opens the window and sets the one true deadline.
    ///
    /// This is also where GymLock goes quiet. From here to the gym the only
    /// things that should happen without the user asking are one departure
    /// notification, one deadline reminder, and the automatic unlock on arrival.
    func beginPreparation() {
        guard var current = session else { return }

        let now = Date()
        current.state = .preparing
        if current.committedAt == nil { current.committedAt = now }
        current.deadline = now.addingTimeInterval(Double(current.windowMinutes) * 60)
        session = current

        persist()
        startTicking()
        beginWatchingForArrival()

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
    func markDeparted(detected: Bool) {
        guard var current = session, current.departedAt == nil else { return }

        current.departedAt = Date()
        current.state = .departed
        session = current

        isShowingPreparationNudge = false
        isShowingDepartureMoment = true
        Haptics.tap()

        store?.record(.departed, sessionID: current.id)

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
        beginWatchingForArrival()
    }

    func acknowledgeDeparture() {
        isShowingDepartureMoment = false
    }

    // MARK: - Expiry

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

    func leaveQuickWorkoutPicker() {
        guard var current = session else { return }
        current.state = current.deadline.map { $0 <= Date() } == true
            ? .windowExpired
            : .cantToday
        session = current
        persist()
    }

    /// Starts the home fallback.
    ///
    /// The shield stays on for the duration. The user chose a workout instead of
    /// the gym, not instead of the commitment.
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
        reconcileShieldWithSession()
    }

    /// Finishes a home workout.
    func finishQuickWorkout(completed wasCompleted: Bool) {
        guard var current = session else { return }

        if wasCompleted {
            current.state = .homeWorkoutVerified
            session = current

            store?.log.record(
                SessionOutcome(
                    kind: .homeWorkout,
                    minutes: current.quickWorkoutMinutes,
                    sessionID: current.id,
                    workoutDetected: current.workoutDetected
                )
            )
            store?.record(.quickWorkoutCompleted, sessionID: current.id)

            releaseShield(sessionID: current.id)
            Haptics.commit()
            persist()

            Task { await matchWorkoutForCurrentSession() }
        } else {
            current.state = .missed
            session = current
            store?.log.record(SessionOutcome(kind: .missed, sessionID: current.id))
            store?.record(.missed, sessionID: current.id)
            releaseShield(sessionID: current.id)
            endSession(clearingAnchor: true)
        }
    }

    // MARK: - Can't today

    func beginCantToday() {
        guard var current = session else { return }
        current.state = .cantToday
        session = current
        store?.record(.cantToday, sessionID: current.id)
        markSlotResolved(current)
        persist()
    }

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

    /// The shield follows the resolution, always. Nobody gets trapped because
    /// they legitimately could not go.
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
            releaseShield(sessionID: current.id)
            store?.log.record(SessionOutcome(kind: .rescheduled, sessionID: current.id))
            scheduleComebackIfEnabled()
            endSession(clearingAnchor: true)

        case .tookTheDayOff:
            current.state = .completed
            session = current
            releaseShield(sessionID: current.id)
            let kind: SessionOutcomeKind = hasEasySkipRemaining ? .easySkip : .dayOff
            store?.log.record(SessionOutcome(kind: kind, sessionID: current.id))
            scheduleComebackIfEnabled()
            endSession(clearingAnchor: true)
        }
    }

    private func scheduleComebackIfEnabled() {
        guard let store, store.profile.comebackModeEnabled else { return }
        guard let next = store.plan.nextOccurrence() else { return }

        Task { [notifier] in
            await notifier.scheduleComeback(at: next.fireDate)
        }
    }

    // MARK: - Finishing

    /// Closes out the morning and clears every session-scoped resource.
    func endSession(clearingAnchor: Bool = true, keepingReminders: Bool = false) {
        ticker?.cancel()
        ticker = nil

        // No morning ends with the alarm still going.
        ringer.stop()

        // Before the session is thrown away: remember that this slot is done
        // for today, so the clock check cannot resurrect it ten minutes later.
        if let current = session, current.state.isResolved {
            markSlotResolved(current)
        }

        if clearingAnchor { location.endSession() }

        // Belt and braces: no session may end with a shield still standing.
        if shield.isShielded { releaseShield(sessionID: session?.id) }

        isShowingDepartureMoment = false
        isShowingPreparationNudge = false
        session = nil
        defaults.removeObject(forKey: Key.session)

        // The geofence stays armed for the next morning; only the per-session
        // callbacks are torn down.
        armArrivalIfPossible()

        guard !keepingReminders else { return }
        Task { [notifier] in await notifier.cancelSessionNotifications() }
    }

    func acknowledgeResult() {
        endSession(clearingAnchor: true)
    }

    // MARK: - Persistence

    private func persist() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Key.session)
    }

    /// Rebuilds an interrupted morning.
    private func restore() {
        guard let data = defaults.data(forKey: Key.session),
              let stored = try? JSONDecoder().decode(GymSession.self, from: data)
        else { return }

        // Anything from a previous day is stale, and a stale session must never
        // keep a shield alive.
        guard Calendar.current.isDateInToday(stored.day), stored.state.isLive else {
            defaults.removeObject(forKey: Key.session)
            if shield.isShielded { releaseShield(sessionID: stored.id) }
            return
        }

        session = stored

        if let anchor = stored.anchor, stored.departedAt == nil {
            location.resume(from: anchor) { [weak self] in
                Task { @MainActor in self?.markDeparted(detected: true) }
            }
        }

        // A dwell interrupted by a relaunch picks up where it was rather than
        // starting its two minutes again.
        if stored.state == .approachingGym, let candidateAt = stored.arrivalCandidateAt {
            beginWatchingForArrival()
            arrival.resumeConfirming(since: candidateAt)
        } else if stored.state == .preparing || stored.state == .departed {
            beginWatchingForArrival()
        }

        if stored.hasExpired, stored.state == .preparing || stored.state == .departed {
            handleExpiry()
        }

        // A snooze survives termination: the expiry is an absolute date, so a
        // relaunch either resumes the remaining seconds or resolves it at once.
        resolveElapsedSnooze()

        reconcileShieldWithSession()
        startTicking()
    }

    // MARK: - Ticking

    /// A one-second loop watching only the moments the flow must react to on its
    /// own: the 75% nudge, the deadline, and the shield failsafe.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var sinceFailsafeCheck = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }

                sinceFailsafeCheck += 1
                let shouldCheckFailsafe = sinceFailsafeCheck >= 60
                if shouldCheckFailsafe { sinceFailsafeCheck = 0 }

                await MainActor.run {
                    self.tick()
                    if shouldCheckFailsafe { self.enforceShieldFailsafe() }
                }
            }
        }
    }

    private func tick() {
        guard var current = session else {
            ticker?.cancel()
            ticker = nil
            return
        }

        if current.state == .snoozed {
            resolveElapsedSnooze()
            return
        }

        guard current.state == .preparing || current.state == .departed else { return }

        if current.hasExpired {
            handleExpiry()
            return
        }

        guard current.departedAt == nil, !current.hasShownPreparationNudge else { return }

        if current.elapsedFraction() >= GymSession.nudgeFraction {
            current.hasShownPreparationNudge = true
            session = current
            isShowingPreparationNudge = true
            persist()
        }
    }

    // MARK: - Debug access

    #if DEBUG
    /// Narrow windows onto private state for the simulator, which lives in a
    /// separate file and so cannot reach `private` members directly.
    ///
    /// Each one is a thin passthrough to the real path rather than a shortcut
    /// around it — a simulator that takes a different route through the state
    /// machine tests nothing worth knowing.
    var debugStore: AppStore? { store }

    func debugReplace(_ updated: GymSession) {
        session = updated
        persist()
    }

    func debugShowNudge() {
        isShowingPreparationNudge = true
    }

    func debugNoteCandidate() {
        noteArrivalCandidate()
    }

    /// Undoes a candidate without confirming it — the drive-by outcome.
    func debugCancelCandidate() {
        guard var current = session, current.state == .approachingGym else { return }
        current.state = current.departedAt == nil ? .preparing : .departed
        current.arrivalCandidateAt = nil
        session = current
        persist()
    }

    func debugEnforceFailsafe() {
        enforceShieldFailsafe()
    }

    var debugResolvedSlotKeys: Set<String> { resolvedSlotKeys }

    func debugMarkResolved(_ session: GymSession, at now: Date = Date()) {
        markSlotResolved(session, at: now)
    }

    func debugClearResolvedSlots() {
        defaults.removeObject(forKey: Key.resolvedSlots)
    }

    func debugReconcileWindDown() {
        reconcileWindDown()
    }
    #endif
}
