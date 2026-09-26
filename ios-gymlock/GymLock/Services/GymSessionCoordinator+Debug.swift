#if DEBUG
import Foundation
import UserNotifications

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

        // Notification taps: only alarms may start a session (FLOW item 12).
        case tapArrivalAfterGym
        case tapDepartureMidSession
        case tapWindDownAtNight
        case tapAlarmNotification

        // Week rules: 3 is the minimum (FLOW items 18, 19, 20, 4).
        case legacyUserTwoGymDays
        case changePlanMidWeek
        case sundayLateAlarmVisitAfterMidnight
        case tryRemoveGymDayAtThree

        // Sleep and night lock (FLOW items 1, 2, 4).
        case legacyEveningUser
        case changeBedtimeTonight
        case bedtimeAfterMidnightGymMonday
        case oldPlanNightLockOff

        // Sound: the ringer and the fallback chain.
        case ringerStart
        case ringerEscalated
        case ringerStop
        case ringerCeiling
        case customSongMissing
        case customSongProtected

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
            case .tapArrivalAfterGym, .tapDepartureMidSession,
                 .tapWindDownAtNight, .tapAlarmNotification:
                "notification taps"
            case .legacyUserTwoGymDays, .changePlanMidWeek,
                 .sundayLateAlarmVisitAfterMidnight, .tryRemoveGymDayAtThree:
                "week rules"
            case .legacyEveningUser, .changeBedtimeTonight,
                 .bedtimeAfterMidnightGymMonday, .oldPlanNightLockOff:
                "sleep and night lock"
            case .ringerStart, .ringerEscalated, .ringerStop,
                 .ringerCeiling, .customSongMissing, .customSongProtected:
                "sound"
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
            case .tapArrivalAfterGym: "tap arrival notification after the gym"
            case .tapDepartureMidSession: "tap departure notification mid-session, then finish the session"
            case .tapWindDownAtNight: "tap wind-down notification at night"
            case .tapAlarmNotification: "tap alarm notification"
            case .legacyUserTwoGymDays: "legacy user with 2 gym days (then reopen the app)"
            case .changePlanMidWeek: "change plan mid-week"
            case .sundayLateAlarmVisitAfterMidnight: "Sunday 23:30 alarm, visit at 00:20"
            case .tryRemoveGymDayAtThree: "try to remove a gym day at 3"
            case .legacyEveningUser: "legacy evening user (then reopen the app)"
            case .changeBedtimeTonight: "change bedtime tonight"
            case .bedtimeAfterMidnightGymMonday: "bedtime 00:30, gym Monday"
            case .oldPlanNightLockOff: "old plan with night lock off"
            case .ringerStart: "ringer: start"
            case .ringerEscalated: "ringer: jump to full volume"
            case .ringerStop: "ringer: stop"
            case .ringerCeiling: "ringer: 10-minute ceiling"
            case .customSongMissing: "custom song deleted (fallback rings)"
            case .customSongProtected: "custom song protected (no asset)"
            }
        }

        static var sections: [String] {
            ["sleep and night lock", "week rules", "notification taps", "doors", "locks", "sound", "flow", "screen time", "arrival", "health", "fallbacks"]
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

        // MARK: Notification taps
        //
        // Each tap goes through the delegate's real routing, then the same
        // resume check a foreground runs. The result line in the panel says
        // whether a handoff was written and what the session is doing.

        case .tapArrivalAfterGym:
            // At the gym, apps unlocked. Tap "you're here" while the arrival
            // is still on screen, then again after the morning is closed.
            simulate(.gymDwellConfirmed)
            let wroteWhileLive = debugTap(NotificationRoute.ID.arrival)
            resumeSessionIfDue()
            endSession()
            let wroteAfter = debugTap(NotificationRoute.ID.arrival)
            resumeSessionIfDue()
            debugReportTap("arrival", wroteHandoff: wroteWhileLive || wroteAfter)

        case .tapDepartureMidSession:
            simulate(.departed)
            let wrote = debugTap(NotificationRoute.ID.departure)
            resumeSessionIfDue()
            // Finish the morning: arrive and close it. The old bug started a
            // second session right here.
            confirmArrival()
            endSession()
            resumeSessionIfDue()
            debugReportTap("departure", wroteHandoff: wrote)

        case .tapWindDownAtNight:
            endSession()
            AlarmHandoff.clear()
            let wrote = debugTap(NotificationRoute.ID.windDown)
            resumeSessionIfDue()
            debugReportTap("wind-down", wroteHandoff: wrote)

        case .tapAlarmNotification:
            endSession()
            debugStore?.debugSeedGym()
            debugClearResolvedSlots()
            AlarmHandoff.clear()
            let slotID = debugStore?.plan.enabledSlots.first?.id ?? UUID()
            let weekday = Calendar.current.component(.weekday, from: Date())
            let wrote = debugTap(
                "\(GymAlarmRequest.identifierPrefix)\(slotID.uuidString).\(weekday)",
                category: NotificationAlarmScheduler.categoryIdentifier
            )
            resumeSessionIfDue()
            debugReportTap("alarm", wroteHandoff: wrote)

        // MARK: Week rules
        //
        // The result line in the panel says what each rule decided.

        case .legacyUserTwoGymDays:
            // The sheet is asked for on the next open, as FLOW says, so
            // background the app and come back to see it.
            guard let store = debugStore else { return }
            store.debugMakeLegacyUserWithTwoGymDays()
            let start = store.streakVault.threeDayRuleStart?
                .formatted(date: .abbreviated, time: .omitted) ?? "none"
            Self.debugWeekRulesResult =
                "2 gym days · goal \(store.streak.weeklyGoal) this week · 3 from \(start) · reopen the app"

        case .changePlanMidWeek:
            guard let store = debugStore else { return }
            store.refreshStreak()
            let before = store.streak.weeklyGoal
            var seen: [Int] = []
            for days in [
                Set<Weekday>([.monday, .wednesday, .friday]),
                [.monday, .tuesday, .wednesday, .thursday, .friday],
                [.monday, .wednesday, .friday],
            ] {
                store.debugSetGymDays(days)
                seen.append(store.streak.weeklyGoal)
            }
            let held = seen.allSatisfy { $0 == before }
            Self.debugWeekRulesResult =
                "goal \(before) before · \(seen.map(String.init).joined(separator: ", ")) after 3/5/3 days · \(held ? "unchanged" : "CHANGED")"

        case .sundayLateAlarmVisitAfterMidnight:
            // The real path: a session whose alarm rang last Sunday at 23:30,
            // then the arrival confirmed now. The outcome must count on the
            // alarm's Sunday, not on the day it was written.
            guard let store = debugStore else { return }
            let calendar = Calendar.current
            let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
            guard let thisMonday = StreakEngine.weekStart(containing: Date(), weekCalendar: weekCalendar),
                  let lastSunday = calendar.date(byAdding: .day, value: -1, to: thisMonday),
                  let alarm = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: lastSunday)
            else { return }

            endSession()
            debugStore?.debugSeedGym()
            beginSession(for: store.plan.enabledSlots.first, at: alarm)
            confirmArrival()
            endSession()

            let counted = store.log.outcomes.last.map { $0.countingDay(calendar: calendar) }
            let label = counted?.formatted(.dateTime.weekday(.abbreviated).day().month()) ?? "none"
            let inLastWeek = counted.map { $0 < thisMonday } ?? false
            Self.debugWeekRulesResult =
                "counts on \(label) · \(inLastWeek ? "in Sunday's week" : "WRONG WEEK")"

        case .tryRemoveGymDayAtThree:
            guard let store = debugStore else { return }
            store.debugSetGymDays([.monday, .wednesday, .friday])
            let result = store.plan.toggleGymDay(.monday, newAlarmTime: store.plan.rhythm.wakeTime)
            let note = result.outcome == .belowMinimum ? StreakPolicy.minimumGymDaysMessage : "NOT refused"
            Self.debugWeekRulesResult =
                "\(note) · \(store.plan.gymDays.count) days · monday \(store.plan.gymDays.contains(.monday) ? "on" : "off")"

        // MARK: Sleep and night lock
        //
        // The result line in the panel says what each rule decided.

        case .legacyEveningUser:
            // A plan saved before the fix: an after-work user whose gym alarm
            // was copied into their wake time. The "when do you wake up?"
            // sheet is asked for on the next open, so background and reopen.
            guard let store = debugStore else { return }
            store.profile.failureWindow = .afterWork
            var plan = store.plan
            let evening = TimeOfDay(hour: 17, minute: 15)
            if let index = plan.slots.firstIndex(where: { $0.id == plan.primaryAlarmSlot?.id }) {
                plan.slots[index].alarmTime = evening
            } else {
                plan.slots = [AlarmSlot(days: [.monday, .wednesday, .friday], alarmTime: evening)]
            }
            plan.rhythm.wakeTime = evening
            plan.rhythm.gymTime = nil
            plan.hasCheckedWakeTime = false
            plan.needsWakeTimeAnswer = false
            plan.hasBeenReviewed = true
            store.plan = plan
            let gymBefore = store.plan.rhythm.gymByTime
            store.migrateLegacyWakeTimeIfNeeded()
            let after = store.plan
            Self.debugSleepResult =
                "wake \(after.rhythm.wakeTime.clockString) · gym \(after.rhythm.gymByTime.clockString) (was \(gymBefore.clockString)) · alarm \(after.primaryAlarmSlot?.alarmTime.clockString ?? "none") · ask \(after.needsWakeTimeAnswer ? "yes, reopen the app" : "NO")"

        case .changeBedtimeTonight:
            // Sleep 23:00 to 07:00, then bedtime moved to 03:00 right now.
            // Tonight's lock and wind-down must still start at 23:00.
            guard let store = debugStore else { return }
            var plan = store.plan
            plan.rhythm.bedtime = TimeOfDay(hour: 23, minute: 0)
            plan.rhythm.wakeTime = TimeOfDay(hour: 7, minute: 0)
            plan.pendingBedtime = nil
            plan.sleepScheduleDays = Set(Weekday.allCases)
            store.plan = plan

            var dodge = store.plan.scheduledRhythm
            dodge.bedtime = TimeOfDay(hour: 3, minute: 0)
            store.commitRhythm(dodge)
            reconcileWindDown()

            let now = Date()
            let tonight = store.plan.nightLockWindow(at: now, calendar: .current)?.start
                ?? store.plan.nextNightLockStart(after: now, calendar: .current)
            let tonightLabel = tonight.map { TimeOfDay(from: $0).clockString } ?? "none"
            let pending = store.plan.pendingBedtime?.bedtime.clockString ?? "none"
            Self.debugSleepResult =
                "tonight locks at \(tonightLabel) · \(pending) starts tomorrow night"

        case .bedtimeAfterMidnightGymMonday:
            // Sleep 00:30 to 08:30, gym Mon/Wed/Fri, every night switched off.
            // Monday's own night (Monday 00:30) must still lock.
            guard let store = debugStore else { return }
            store.debugSetGymDays([.monday, .wednesday, .friday])
            var plan = store.plan
            plan.rhythm.bedtime = TimeOfDay(hour: 0, minute: 30)
            plan.rhythm.wakeTime = TimeOfDay(hour: 8, minute: 30)
            plan.pendingBedtime = nil
            plan.sleepScheduleDays = []
            store.plan = plan

            let calendar = Calendar.current
            let required = store.plan.requiredSleepNights()
            let nextMondayOne = calendar.nextDate(
                after: Date(),
                matching: DateComponents(hour: 1, minute: 0, weekday: Weekday.monday.rawValue),
                matchingPolicy: .nextTime
            )
            let locks = nextMondayOne.map { store.plan.nightLockWindow(at: $0, calendar: calendar) != nil } ?? false
            let names = Weekday.allCases.filter { required.contains($0) }.map(\.shortLabel).joined(separator: " ")
            Self.debugSleepResult =
                "protected: \(names.isEmpty ? "none" : names) · Monday 01:00 \(locks ? "locked" : "NOT locked")"

        case .oldPlanNightLockOff:
            // The old switch set to off, with a night open right now. The
            // lock must hold anyway: the switch is read and ignored.
            guard let store = debugStore else { return }
            debugEnsureShieldSelection()
            debugSetWindDownWindow(startMinutesAgo: 30, endMinutesFromNow: 30)
            store.plan.nightLock.isEnabled = false
            debugReconcileWindDown()
            Self.debugSleepResult =
                "old switch off · night lock \(windDown.isActive ? "on" : "OFF") · apps \(shield.isShielded ? "locked" : "unlocked")"

        // MARK: Sound

        case .ringerStart:
            guard let store = debugStore else { return }
            ringer.start(for: store.profile)

        case .ringerEscalated:
            if !ringer.isRinging { simulate(.ringerStart) }
            ringer.escalateToFull()

        case .ringerStop:
            ringer.stop()

        case .ringerCeiling:
            // The real ceiling is ten minutes away, so this runs what the
            // timer runs rather than waiting for it.
            if !ringer.isRinging { simulate(.ringerStart) }
            ringer.stop()
            debugStore?.record(
                .technicalRelease,
                detail: "ringer ceiling reached after \(Int(AlarmRinger.maximumRingDuration / 60)) min"
            )

        case .customSongMissing:
            // Deletes the exported clip and rings anyway: the fallback chain
            // must produce a sound, never silence.
            guard let store = debugStore else { return }
            ringer.stop()
            store.profile.alarmSound = .ownSong
            if store.profile.customAlarmSoundFile == nil {
                store.profile.customAlarmSoundFile = SongTrimService.clipFileName
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await SongTrimService.deleteExportedClip()
                self.ringer.start(for: store.profile)
                store.record(
                    .technicalRelease,
                    detail: self.ringer.isPlayingFallback
                        ? "custom song missing, fell back to \(self.ringer.playingSound?.label ?? "none")"
                        : "custom song missing and nothing rang"
                )
            }

        case .customSongProtected:
            // What a DRM-protected Apple Music track looks like: a chosen
            // song with no file behind it. The picker refuses these up front,
            // and this proves the ringer survives one slipping through.
            guard let store = debugStore else { return }
            ringer.stop()
            store.profile.alarmSound = .ownSong
            store.profile.customAlarmSoundFile = nil
            store.profile.ownSongFileName = nil
            ringer.start(for: store.profile)
            store.record(
                .technicalRelease,
                detail: "protected track: rang \(ringer.playingSound?.label ?? "nothing")"
            )
        }
    }

    // MARK: - Sleep and night lock helpers

    /// The last sleep-and-night-lock result, shown in the panel.
    static var debugSleepResult = "none"

    // MARK: - Week rules helpers

    /// The last week-rules result, shown in the panel.
    static var debugWeekRulesResult = "none"

    // MARK: - Notification tap helpers

    /// The last notification-tap result, shown in the panel.
    static var debugNotificationTapResult = "none"

    /// Taps the body of a notification through the delegate's real routing.
    /// Returns whether a handoff was written.
    private func debugTap(_ identifier: String, category: String = "") -> Bool {
        AlarmHandoff.clear()
        AlarmNotificationDelegate.handle(
            identifier: identifier,
            categoryIdentifier: category,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )
        return AlarmHandoff.peek() != nil
    }

    private func debugReportTap(_ name: String, wroteHandoff: Bool) {
        let state = session?.state.rawValue ?? "none"
        let locked = shield.isShielded ? "locked" : "unlocked"
        Self.debugNotificationTapResult =
            "\(name): handoff \(wroteHandoff ? "written" : "none") · session \(state) · apps \(locked)"
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

    /// Moves the sleep schedule so the night opened `startMinutesAgo` and
    /// ends `endMinutesFromNow` from now, on every night, whatever the clock
    /// says. The lock has no window of its own any more: it is bedtime to
    /// wake time, so the debug step moves those directly (skipping the
    /// tomorrow-night rule on purpose).
    private func debugSetWindDownWindow(startMinutesAgo: Int, endMinutesFromNow: Int) {
        guard let store = debugStore else { return }

        var plan = store.plan
        plan.rhythm.bedtime = TimeOfDay(from: Date().addingTimeInterval(-Double(startMinutesAgo) * 60))
        plan.rhythm.wakeTime = TimeOfDay(from: Date().addingTimeInterval(Double(endMinutesFromNow) * 60))
        plan.pendingBedtime = nil
        plan.sleepScheduleDays = Set(Weekday.allCases)
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
