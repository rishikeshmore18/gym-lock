#if DEBUG
import Foundation

/// Jumps the morning to any state without waiting for a real 6:30 AM, a real
/// gym, or a real Apple Watch.
///
/// The whole file is inside `#if DEBUG`, so none of it — not the enum, not the
/// methods, not the panel that calls them — exists in a shipped binary. There is
/// no runtime flag to get wrong and no way a production user reaches a simulated
/// arrival.
extension GymSessionCoordinator {
    enum DebugStep: String, CaseIterable, Identifiable {
        // The flow
        case alarmFired
        case snoozedMorning
        case snoozeElapsed
        case alarmFiredEvening
        case imGoing
        case missionComplete
        case departed
        case countdownAt75
        case countdownExpired

        // Screen Time
        case familyControlsAuthorized
        case familyControlsDenied
        case shieldApplied
        case shieldRemoved
        case technicalRelease

        // Arrival
        case gymRegionEntered
        case badGPSAccuracy
        case goodGPSAccuracy
        case driveBy
        case gymDwellConfirmed
        case arrivalTrouble

        // Health
        case healthWorkoutDetected
        case noHealthWorkout
        case healthDenied

        // Fallbacks
        case quickWorkoutComplete
        case cantTodayWithinAllowance
        case cantTodayOverAllowance

        // The three doors: every way a real morning can actually begin.
        case alarmKitButtonTapped
        case alarmKitSnoozeTapped
        case notificationActionImUp
        case notificationActionSnooze
        case notificationTapped
        case notificationDismissed
        case coldLaunchFromAlarm
        case foregroundDuringWindow
        case foregroundAfterWindow
        case foregroundAfterResolved
        case alarmFiredWhileAppOpen

        // The two locks: how the evening and the morning share one shield.
        case windDownLockStart
        case windDownLockEnd
        case windDownHandoverToGym
        case windDownWhileSessionLive

        var id: String { rawValue }

        var section: String {
            switch self {
            case .alarmFired, .snoozedMorning, .snoozeElapsed, .alarmFiredEvening,
                 .imGoing, .missionComplete, .departed,
                 .countdownAt75, .countdownExpired:
                "flow"
            case .familyControlsAuthorized, .familyControlsDenied,
                 .shieldApplied, .shieldRemoved, .technicalRelease:
                "screen time"
            case .gymRegionEntered, .badGPSAccuracy, .goodGPSAccuracy,
                 .driveBy, .gymDwellConfirmed, .arrivalTrouble:
                "arrival"
            case .healthWorkoutDetected, .noHealthWorkout, .healthDenied:
                "health"
            case .quickWorkoutComplete, .cantTodayWithinAllowance, .cantTodayOverAllowance:
                "fallbacks"
            case .alarmKitButtonTapped, .alarmKitSnoozeTapped,
                 .notificationActionImUp, .notificationActionSnooze,
                 .notificationTapped, .notificationDismissed,
                 .coldLaunchFromAlarm, .foregroundDuringWindow,
                 .foregroundAfterWindow, .foregroundAfterResolved,
                 .alarmFiredWhileAppOpen:
                "doors"
            case .windDownLockStart, .windDownLockEnd,
                 .windDownHandoverToGym, .windDownWhileSessionLive:
                "locks"
            }
        }

        var label: String {
            switch self {
            case .alarmFired: "alarm fired"
            case .snoozedMorning: "tapped 5 more min"
            case .snoozeElapsed: "snooze ran out"
            case .alarmFiredEvening: "alarm fired (evening)"
            case .imGoing: "tapped I'm going"
            case .missionComplete: "mission complete"
            case .departed: "departed"
            case .countdownAt75: "countdown at 75%"
            case .countdownExpired: "countdown expired"
            case .familyControlsAuthorized: "FamilyControls authorized"
            case .familyControlsDenied: "FamilyControls denied"
            case .shieldApplied: "shield applied"
            case .shieldRemoved: "shield removed"
            case .technicalRelease: "technical release (failsafe)"
            case .gymRegionEntered: "gym region entered"
            case .badGPSAccuracy: "bad GPS accuracy"
            case .goodGPSAccuracy: "good GPS accuracy"
            case .driveBy: "drive-by (no unlock)"
            case .gymDwellConfirmed: "gym dwell confirmed"
            case .arrivalTrouble: "arrival couldn't be confirmed"
            case .healthWorkoutDetected: "HealthKit workout detected"
            case .noHealthWorkout: "no HealthKit workout"
            case .healthDenied: "HealthKit denied"
            case .quickWorkoutComplete: "quick workout complete"
            case .cantTodayWithinAllowance: "can't today (within allowance)"
            case .cantTodayOverAllowance: "can't today (over allowance)"
            case .alarmKitButtonTapped: "AlarmKit: tapped I'm up"
            case .alarmKitSnoozeTapped: "AlarmKit: tapped 5 more min"
            case .notificationActionImUp: "notification: I'm up"
            case .notificationActionSnooze: "notification: 5 more min"
            case .notificationTapped: "notification: tapped the banner"
            case .notificationDismissed: "notification: swiped away"
            case .coldLaunchFromAlarm: "cold launch from alarm"
            case .foregroundDuringWindow: "opened app during window"
            case .foregroundAfterWindow: "opened app after window (none)"
            case .foregroundAfterResolved: "opened app after resolving (none)"
            case .alarmFiredWhileAppOpen: "alarm fired while app open"
            case .windDownLockStart: "wind-down: lock now"
            case .windDownLockEnd: "wind-down: window ends"
            case .windDownHandoverToGym: "wind-down: handover to gym"
            case .windDownWhileSessionLive: "wind-down while session live"
            }
        }

        static var sections: [String] {
            ["doors", "locks", "flow", "screen time", "arrival", "health", "fallbacks"]
        }
    }

    func simulate(_ step: DebugStep) {
        switch step {
        // MARK: Flow

        case .alarmFired:
            endSession()
            debugStore?.debugSeedGym()
            beginSession(for: debugStore?.plan.enabledSlots.first)

        case .snoozedMorning:
            // Forced to a morning time first: the snooze does not exist at any
            // other hour, so simulating it from an evening slot would silently
            // do nothing and look like a bug.
            simulate(.alarmFired)
            guard var current = session else { return }
            current.alarmTime = TimeOfDay(hour: 6, minute: 30)
            current.isMorningSession = true
            debugReplace(current)
            snooze()

        case .snoozeElapsed:
            if session?.state != .snoozed { simulate(.snoozedMorning) }
            guard var current = session else { return }
            current.snoozeExpiresAt = Date().addingTimeInterval(-1)
            debugReplace(current)
            resolveElapsedSnooze()

        case .alarmFiredEvening:
            // The other half of the copy: same flow, no snooze, different
            // wording from the alarm screen right through to "can't today".
            simulate(.alarmFired)
            guard var current = session else { return }
            current.alarmTime = TimeOfDay(hour: 18, minute: 0)
            current.isMorningSession = false
            debugReplace(current)

        case .imGoing:
            if session == nil { simulate(.alarmFired) }
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
            guard var current = session else { return }
            let total = Double(current.windowMinutes) * 60
            current.committedAt = Date().addingTimeInterval(-total * GymSession.nudgeFraction)
            current.deadline = Date().addingTimeInterval(total * (1 - GymSession.nudgeFraction))
            current.hasShownPreparationNudge = false
            debugReplace(current)
            debugShowNudge()

        case .countdownExpired:
            if session?.state != .preparing { simulate(.missionComplete) }
            guard var current = session else { return }
            current.deadline = Date().addingTimeInterval(-1)
            current.state = .preparing
            debugReplace(current)
            handleExpiry()

        // MARK: Screen Time

        case .familyControlsAuthorized:
            shield.debugSetAuthorization(.approved)
            if let demo = shield as? DemoShieldService, !demo.hasSelection {
                demo.setDemoSelection(count: 5)
            }
            debugStore?.hasConfiguredBlockedApps = true

        case .familyControlsDenied:
            shield.debugSetAuthorization(.denied)

        case .shieldApplied:
            if session == nil { simulate(.alarmFired) }
            guard let current = session else { return }
            shield.apply(
                until: ShieldPolicy.deadline(forWindowMinutes: current.windowMinutes),
                sessionID: current.id
            )
            debugStore?.record(.shieldApplied, sessionID: current.id)

        case .shieldRemoved:
            shield.release()
            debugStore?.record(.shieldRemoved, sessionID: session?.id)

        case .technicalRelease:
            // Backdates the ledger so the real failsafe path runs, rather than
            // just calling release and pretending.
            if !shield.isShielded { simulate(.shieldApplied) }
            (shield as? DemoShieldService)?.debugExpireFailsafe()
            #if canImport(FamilyControls)
            if #available(iOS 16.0, *) {
                (shield as? FamilyControlsShieldService)?.debugExpireFailsafe()
            }
            #endif
            debugEnforceFailsafe()

        // MARK: Arrival

        case .gymRegionEntered:
            if session?.state != .departed { simulate(.departed) }
            arrival.debugSimulateRegionEntry()
            debugNoteCandidate()

        case .badGPSAccuracy:
            arrival.debugSetAccuracy(480)

        case .goodGPSAccuracy:
            arrival.debugSetAccuracy(12)

        case .driveBy:
            // Enters the region and leaves before the dwell completes. The
            // correct outcome is that nothing unlocks.
            if session?.state != .departed { simulate(.departed) }
            arrival.debugSimulateDriveBy()
            debugCancelCandidate()

        case .gymDwellConfirmed:
            if session == nil { simulate(.departed) }
            confirmArrival()

        case .arrivalTrouble:
            if session?.state != .approachingGym { simulate(.gymRegionEntered) }
            arrival.debugSimulateTrouble()
            reportArrivalTroubleManually()

        // MARK: Health

        case .healthWorkoutDetected:
            health.debugSetAvailability(.authorized)
            health.debugEmitWorkout()

        case .noHealthWorkout:
            guard var current = session else { return }
            current.workoutDetected = false
            current.detectedWorkout = nil
            debugReplace(current)

        case .healthDenied:
            health.debugSetAvailability(.denied)

        // MARK: Fallbacks

        case .quickWorkoutComplete:
            if session == nil { simulate(.alarmFired) }
            startQuickWorkout(minutes: 20)
            finishQuickWorkout(completed: true)

        case .cantTodayWithinAllowance:
            debugStore?.debugClearSkips()
            if session == nil { simulate(.alarmFired) }
            beginCantToday()

        case .cantTodayOverAllowance:
            debugStore?.debugExhaustSkips(count: easySkipAllowance)
            if session == nil { simulate(.alarmFired) }
            beginCantToday()

        // MARK: The three doors
        //
        // Each of these runs the real path rather than a shortcut around it:
        // they write the same handoff the intent or the notification delegate
        // writes, then let `resumeSessionIfDue()` do the rest. A simulator that
        // takes a different route through the state machine tests nothing worth
        // knowing.

        case .alarmKitButtonTapped, .notificationActionImUp, .notificationTapped:
            beginFromDoor(wantsSnooze: false)

        case .alarmKitSnoozeTapped, .notificationActionSnooze:
            beginFromDoor(wantsSnooze: true)

        case .notificationDismissed:
            // Swiping an alarm away is not permission to skip the gym, so the
            // session still starts and the lock still goes on.
            beginFromDoor(wantsSnooze: false)

        case .coldLaunchFromAlarm:
            // No scene phase change happens on a cold launch, so this proves
            // `attach(to:)` alone is enough to pick the note up.
            endSession()
            debugStore?.debugSeedGym()
            debugClearResolvedSlots()
            debugWriteHandoff(wantsSnooze: false)
            if let store = debugStore { attach(to: store) }

        case .foregroundDuringWindow:
            // No handoff at all: the clock alone has to notice.
            debugPrepareClockOnly(minutesAgo: 5)
            resumeSessionIfDue()

        case .foregroundAfterWindow:
            // Past the window plus the grace. The correct outcome is that
            // nothing happens: nobody gets ambushed at lunchtime.
            let window = debugStore?.plan.windowMinutes ?? 35
            debugPrepareClockOnly(minutesAgo: window + SessionResume.resumeGrace + 5)
            resumeSessionIfDue()

        case .foregroundAfterResolved:
            debugPrepareClockOnly(minutesAgo: 5, clearingResolved: false)
            debugMarkFirstSlotResolved()
            resumeSessionIfDue()

        case .alarmFiredWhileAppOpen:
            // The app is frontmost, so there is no scene phase change to lean
            // on: the posted notification is what has to carry it.
            endSession()
            debugStore?.debugSeedGym()
            debugClearResolvedSlots()
            debugWriteHandoff(wantsSnooze: false)
            NotificationCenter.default.post(name: .gymLockAlarmHandoffAvailable, object: nil)

        // MARK: The two locks
        //
        // Each of these walks the real reconcile path rather than poking the
        // shield directly, so what the panel shows is what a foreground would
        // actually do.

        case .windDownLockStart:
            // A window that is open right now, then the same foreground
            // catch-up a real evening takes.
            debugEnsureShieldSelection()
            debugSetWindDownWindow(startMinutesAgo: 30, endMinutesFromNow: 30)
            debugReconcileWindDown()

        case .windDownLockEnd:
            // First make sure the lock is genuinely on, then move the window
            // so it has just ended: the reconcile must lift the shield by the
            // clock, with nothing else happening.
            if shield.owner != .windDown { simulate(.windDownLockStart) }
            guard shield.isShielded else { return }
            debugSetWindDownWindow(startMinutesAgo: 120, endMinutesFromNow: -1)
            debugReconcileWindDown()

        case .windDownHandoverToGym:
            // The alarm fires while the night lock is still holding the
            // shield. The gym lock must take ownership in the same call, so
            // the shield is never off: both readings being true is the proof.
            if shield.owner != .windDown { simulate(.windDownLockStart) }
            guard shield.isShielded else { return }
            let wasShieldedBeforeHandover = shield.isShielded
            simulate(.alarmFired)
            debugStore?.record(
                .shieldApplied,
                sessionID: session?.id,
                detail: wasShieldedBeforeHandover && shield.isShielded
                    ? "handover: shield never off, owner now \(shield.owner?.rawValue ?? "none")"
                    : "handover gap: wind-down shield was off"
            )

        case .windDownWhileSessionLive:
            // A session owns the shield and the wind-down window opens around
            // it. The correct outcome is that nothing changes: the night
            // controller sees a .gymSession owner and stops claiming.
            if session == nil { simulate(.alarmFired) }
            guard session != nil else { return }
            let ownerBefore = shield.owner
            debugSetWindDownWindow(startMinutesAgo: 30, endMinutesFromNow: 30)
            debugReconcileWindDown()
            debugStore?.record(
                .shieldApplied,
                sessionID: session?.id,
                detail: shield.owner == .gymSession && ownerBefore == .gymSession
                    ? "wind-down ignored the session's shield"
                    : "owner changed while session live: \(ownerBefore?.rawValue ?? "none") to \(shield.owner?.rawValue ?? "none")"
            )
        }
    }

    // MARK: - Lock helpers

    /// The shield backends refuse to apply anything without a selection, so
    /// every lock step makes sure there is one first.
    private func debugEnsureShieldSelection() {
        if let demo = shield as? DemoShieldService, !demo.hasSelection {
            demo.setDemoSelection(count: 5)
        }
        shield.debugSetAuthorization(.approved)
        debugStore?.hasConfiguredBlockedApps = true
    }

    /// Sets a hand-tuned wind-down window that opened `startMinutesAgo` and
    /// closes `endMinutesFromNow` from now, whatever the clock says.
    private func debugSetWindDownWindow(startMinutesAgo: Int, endMinutesFromNow: Int) {
        guard let store = debugStore else { return }

        var plan = store.plan
        plan.nightLock.isEnabled = true
        plan.nightLock.followsRhythm = false
        plan.nightLock.customStart = TimeOfDay(
            from: Date().addingTimeInterval(-Double(startMinutesAgo) * 60)
        )
        plan.nightLock.customEnd = TimeOfDay(
            from: Date().addingTimeInterval(Double(endMinutesFromNow) * 60)
        )
        store.plan = plan
    }

    // MARK: - Door helpers

    /// Writes exactly what the intent and the notification delegate write.
    private func debugWriteHandoff(wantsSnooze: Bool) {
        AlarmHandoff.write(
            .init(
                slotID: debugStore?.plan.enabledSlots.first?.id,
                firedAt: Date(),
                wantsSnooze: wantsSnooze
            )
        )
    }

    private func beginFromDoor(wantsSnooze: Bool) {
        endSession()
        debugStore?.debugSeedGym()
        debugClearResolvedSlots()

        // Forced to a morning time, because the snooze does not exist at any
        // other hour and simulating it from an evening slot would silently do
        // nothing and look like a bug.
        if wantsSnooze { debugSetFirstSlotTime(TimeOfDay(hour: 6, minute: 30)) }

        debugWriteHandoff(wantsSnooze: wantsSnooze)
        resumeSessionIfDue()
    }

    /// Clears every note and moves the first slot to a time that already passed
    /// today, so the clock-based check has something real to find.
    private func debugPrepareClockOnly(minutesAgo: Int, clearingResolved: Bool = true) {
        endSession()
        debugStore?.debugSeedGym()
        if clearingResolved { debugClearResolvedSlots() }
        AlarmHandoff.clear()

        let firedAt = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        let parts = Calendar.current.dateComponents([.hour, .minute, .weekday], from: firedAt)
        debugSetFirstSlotTime(
            TimeOfDay(hour: parts.hour ?? 6, minute: parts.minute ?? 30),
            addingWeekday: parts.weekday.flatMap(Weekday.init(rawValue:))
        )
    }

    private func debugSetFirstSlotTime(_ time: TimeOfDay, addingWeekday weekday: Weekday? = nil) {
        guard let store = debugStore else { return }

        var plan = store.plan
        guard let index = plan.slots.firstIndex(where: { $0.isEnabled }) else { return }

        plan.slots[index].alarmTime = time
        if let weekday { plan.slots[index].days.insert(weekday) }
        store.plan = plan
    }

    /// Marks today's first slot as already settled, the way a real "can't
    /// today" would have.
    private func debugMarkFirstSlotResolved() {
        guard let store = debugStore, let slot = store.plan.enabledSlots.first else { return }

        var resolved = GymSession(
            day: Calendar.current.startOfDay(for: Date()),
            slotID: slot.id,
            alarmTime: slot.alarmTime,
            isMorningSession: slot.daypart.usesSleepRhythm,
            getReadyMinutes: store.plan.rhythm.getReadyMinutes,
            travelMinutes: store.plan.rhythm.travelMinutes
        )
        resolved.state = .cantToday
        debugMarkResolved(resolved)
    }
}
#endif
