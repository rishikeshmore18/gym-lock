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

        // Alarm rules (FLOW items 5 to 9).
        case wakeAndGoGymDay
        case goLaterGymDay
        case plainWakeAlarmRings
        case ignoreAlarmUntilDeadline
        case runningLate30
        case runningLateNearBedtime
        case runningLateTwice
        case phoneWasOffOnGymDay

        // At the gym (FLOW items 3, 10, 11, 13, 14, 20).
        case arriveStay20
        case arriveLeaveAt12
        case stepOutThreeMinutes
        case healthWorkout22
        case handTypedWorkout
        case unplannedVisit
        case visitInSleepHours
        case imHereCameraPhoto
        case tapWorkoutDoneNotification

        // Skips, reschedules and home workouts (FLOW items 15, 16, 17).
        case exampleA
        case exampleB
        case exampleC
        case exampleD
        case use3HomeWorkouts
        case homeWorkoutNoHealthPhoto
        case cancelAReschedule
        case skipOnSunday

        // Freezes and streak at risk (FLOW items 21, 22).
        case jumpTwoMonthsAfterJoining
        case jumpToJuly1
        case newYearFreezesExpire
        case planFreezeThisWeek
        case atRiskThursday
        case atRiskSunday
        case atRiskHomeWorkoutsUsedUp

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
            case .quickWorkoutComplete:
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
            case .wakeAndGoGymDay, .goLaterGymDay, .plainWakeAlarmRings,
                 .ignoreAlarmUntilDeadline, .runningLate30, .runningLateNearBedtime,
                 .runningLateTwice, .phoneWasOffOnGymDay:
                "alarm rules"
            case .arriveStay20, .arriveLeaveAt12, .stepOutThreeMinutes, .healthWorkout22,
                 .handTypedWorkout, .unplannedVisit, .visitInSleepHours,
                 .imHereCameraPhoto, .tapWorkoutDoneNotification:
                "at the gym"
            case .exampleA, .exampleB, .exampleC, .exampleD,
                 .use3HomeWorkouts, .homeWorkoutNoHealthPhoto,
                 .cancelAReschedule, .skipOnSunday:
                "skips"
            case .jumpTwoMonthsAfterJoining, .jumpToJuly1, .newYearFreezesExpire,
                 .planFreezeThisWeek, .atRiskThursday, .atRiskSunday, .atRiskHomeWorkoutsUsedUp:
                "freezes and at risk"
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
            case .wakeAndGoGymDay: "wake & go gym day"
            case .goLaterGymDay: "go later gym day (time to go 17:30)"
            case .plainWakeAlarmRings: "plain wake alarm rings (no lock)"
            case .ignoreAlarmUntilDeadline: "ignore alarm until deadline"
            case .runningLate30: "running late +30"
            case .runningLateNearBedtime: "running late near bedtime"
            case .runningLateTwice: "running late twice"
            case .phoneWasOffOnGymDay: "phone was off on a gym day"
            case .arriveStay20: "arrive, stay 20 min"
            case .arriveLeaveAt12: "arrive, leave at 12 min"
            case .stepOutThreeMinutes: "step out for 3 min"
            case .healthWorkout22: "Health workout 22 min"
            case .handTypedWorkout: "hand-typed workout"
            case .unplannedVisit: "unplanned Saturday visit"
            case .visitInSleepHours: "visit at 23:30 in sleep hours"
            case .imHereCameraPhoto: "I'm here + camera photo"
            case .tapWorkoutDoneNotification: "tap the workout-done notification"
            case .exampleA: "Example A: mon done, wed slept through"
            case .exampleB: "Example B: mon to fri, tue can't today"
            case .exampleC: "Example C: bad week, reschedule twice"
            case .exampleD: "Example D: no watch, home workout"
            case .use3HomeWorkouts: "use 3 home workouts this month"
            case .homeWorkoutNoHealthPhoto: "home workout, no Health, add photo"
            case .cancelAReschedule: "cancel a reschedule"
            case .skipOnSunday: "skip on Sunday"
            case .jumpTwoMonthsAfterJoining: "jump to 2 months after joining"
            case .jumpToJuly1: "jump to July 1"
            case .newYearFreezesExpire: "new year: freezes expire"
            case .planFreezeThisWeek: "plan a freeze this week"
            case .atRiskThursday: "at risk on Thursday"
            case .atRiskSunday: "at risk on Sunday"
            case .atRiskHomeWorkoutsUsedUp: "at risk, home workouts used up"
            case .ringerStart: "ringer: start"
            case .ringerEscalated: "ringer: jump to full volume"
            case .ringerStop: "ringer: stop"
            case .ringerCeiling: "ringer: 10-minute ceiling"
            case .customSongMissing: "custom song deleted (fallback rings)"
            case .customSongProtected: "custom song protected (no asset)"
            }
        }

        static var sections: [String] {
            ["freezes and at risk", "skips", "at the gym", "alarm rules", "sleep and night lock", "week rules", "notification taps", "doors", "locks", "sound", "flow", "screen time", "arrival", "health", "fallbacks"]
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
            // Snooze belongs to Wake & Go, not to the clock.
            current.flowMode = .wakeAndGo
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
            current.flowMode = .goLater
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

        // MARK: Alarm rules
        //
        // The result line in the panel says what each rule decided.

        case .wakeAndGoGymDay:
            // Wake 06:30, gym 07:05: a 35 minute gap, so the wake-up alarm
            // is the gym alarm and it snoozes once.
            debugSetAlarmRhythm(wake: TimeOfDay(hour: 6, minute: 30), gym: TimeOfDay(hour: 7, minute: 5), getReady: 20, travel: 15)
            let today = debugToday()
            let summary = debugAlarmSummary(on: today)
            endSession()
            debugStore?.debugSeedGym()
            beginSession(for: debugStore?.plan.enabledSlots.first)
            let snooze = session.map { SessionVoice(session: $0).allowsSnooze } ?? false
            Self.debugAlarmRulesResult =
                "\(debugStore?.plan.rhythm.flowMode.label ?? "none") · \(summary) · snooze \(snooze ? "yes" : "NO") · running late \(runningLateOptions.isEmpty ? "no" : "SHOWN")"
            Task { await syncAlarms() }

        case .goLaterGymDay:
            // Flow 2: wake 07:00, gym 18:00, 10 + 20 minutes, so the time to
            // go is 17:30. No snooze on that alarm; running late instead.
            debugSetAlarmRhythm(wake: TimeOfDay(hour: 7, minute: 0), gym: TimeOfDay(hour: 18, minute: 0), getReady: 10, travel: 20)
            let summary = debugAlarmSummary(on: debugToday())
            endSession()
            debugStore?.debugSeedGym()
            beginSession(for: debugStore?.plan.enabledSlots.first)
            let snooze = session.map { SessionVoice(session: $0).allowsSnooze } ?? false
            Self.debugAlarmRulesResult =
                "\(debugStore?.plan.rhythm.flowMode.label ?? "none") · time to go \(debugStore?.plan.rhythm.timeToGo.clockString ?? "none") · \(summary) · snooze \(snooze ? "SHOWN" : "no")"
            Task { await syncAlarms() }

        case .plainWakeAlarmRings:
            // The plain wake alarm, through every door: the notification
            // router, the AlarmKit observer's id check and the intent guard.
            endSession()
            debugClearResolvedSlots()
            AlarmHandoff.clear()
            let wakeID = WakeAlarmID.weekly
            let weekday = Calendar.current.component(.weekday, from: Date())
            let identifier = "\(GymAlarmRequest.wakeIdentifierPrefix)\(wakeID.uuidString).\(weekday)"
            let wrote = debugTap(identifier)
            let observerStarts = WakeAlarmID.startsSession(alarmID: wakeID)
            resumeSessionIfDue()
            Self.debugAlarmRulesResult =
                "route \(NotificationRoute(identifier: identifier, categoryIdentifier: "")) · handoff \(wrote ? "WRITTEN" : "none") · observer \(observerStarts ? "STARTS" : "ignores") · session \(session?.state.rawValue ?? "none") · apps \(shield.isShielded ? "locked" : "unlocked")"

        case .ignoreAlarmUntilDeadline:
            // An alarm that rang long enough ago that its lock deadline has
            // passed, never answered. It must end as missed.
            debugEnsureShieldSelection()
            endSession()
            debugStore?.debugSeedGym()
            debugClearResolvedSlots()
            let window = debugStore?.plan.windowMinutes ?? 35
            let rang = Date().addingTimeInterval(-Double(window + 91) * 60)
            beginSession(for: debugStore?.plan.enabledSlots.first, at: rang)
            let wasLocked = shield.isShielded
            let deadline = session.map { TimeOfDay(from: $0.effectiveLockDeadline).clockString } ?? "none"
            endIgnoredSessionIfNeeded()
            let last = debugStore?.log.outcomes.last?.kind.rawValue ?? "none"
            let resolved = !debugResolvedSlotKeys.isEmpty
            Self.debugAlarmRulesResult =
                "deadline \(deadline) · \(last) · apps \(wasLocked ? "were locked, now " : "")\(shield.isShielded ? "LOCKED" : "unlocked") · slot \(resolved ? "resolved" : "NOT resolved") · notice sent"

        case .runningLate30:
            debugStartGoLaterNow(bedtimeInMinutes: 8 * 60)
            let before = session.map { TimeOfDay(from: $0.effectiveLockDeadline).clockString } ?? "none"
            runningLate(by: 30)
            let after = session.map { TimeOfDay(from: $0.effectiveLockDeadline).clockString } ?? "none"
            let ring = session?.runningLateUntil.map { TimeOfDay(from: $0).clockString } ?? "none"
            let oneOff = debugStore?.plan.oneOffAlarms.contains { $0.kind == .runningLate } ?? false
            Self.debugAlarmRulesResult =
                "\(session?.state.rawValue ?? "none") · rings \(ring) · alarm \(oneOff ? "set" : "MISSING") · apps \(shield.isShielded ? "locked" : "UNLOCKED") · deadline \(before) to \(after)"

        case .runningLateNearBedtime:
            // Bedtime two hours away, a 30 minute trip and a 60 minute visit:
            // +15 and +30 still end by bedtime, +60 would not.
            debugStartGoLaterNow(bedtimeInMinutes: 120)
            let options = runningLateOptions.map { "+\($0)" }.joined(separator: " ")
            Self.debugAlarmRulesResult =
                "bedtime \(debugStore?.plan.rhythm.bedtime.clockString ?? "none") · offered \(options.isEmpty ? "none" : options) · +60 \(runningLateOptions.contains(60) ? "SHOWN" : "hidden")"

        case .runningLateTwice:
            debugStartGoLaterNow(bedtimeInMinutes: 8 * 60)
            runningLate(by: 15)
            // The alarm rings again, then a second try.
            if var current = session {
                current.runningLateUntil = Date().addingTimeInterval(-1)
                debugReplace(current)
            }
            resolveElapsedRunningLate()
            let optionsAfter = runningLateOptions
            runningLate(by: 15)
            Self.debugAlarmRulesResult =
                "after the first: \(optionsAfter.isEmpty ? "button gone" : "STILL OFFERED") · second try: \(session?.state.rawValue ?? "none")"

        case .phoneWasOffOnGymDay:
            // Today is a gym day whose alarm never rang and whose lock would
            // already have lifted. The skip screen is offered once and
            // nothing is recorded.
            guard let store = debugStore else { return }
            endSession()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let ring = Date().addingTimeInterval(-3 * 3600)
            debugSetAlarmRhythm(wake: TimeOfDay(from: ring), gym: TimeOfDay(from: ring.addingTimeInterval(35 * 60)), getReady: 20, travel: 15)
            store.log.outcomes.removeAll { $0.countingDay(calendar: calendar) == today }
            store.events.events.removeAll { $0.kind == .alarmFired && calendar.isDate($0.at, inSameDayAs: today) }
            debugResetMissedDayCheck(since: today)
            let outcomesBefore = store.log.outcomes.count
            let first = offerMissedGymDayIfNeeded()
            let screen = route == .cantToday ? "skip screen" : "NO SCREEN"
            endSession()
            let second = offerMissedGymDayIfNeeded()
            endSession()
            let recorded = store.log.outcomes.count - outcomesBefore
            Self.debugAlarmRulesResult =
                "first open: \(first.map { _ in screen } ?? "NOT OFFERED") · second open: \(second == nil ? "nothing" : "OFFERED AGAIN") · recorded \(recorded)"

        // MARK: At the gym
        //
        // Each step backdates an arrival and runs the real settling, so the
        // result line says what the rules decided. All of them add to your
        // real log.

        case .arriveStay20:
            let visit = debugFreshVisit(minutesAgo: 21)
            debugReportVisit(visit.id, prefix: "21 min, no exit")

        case .arriveLeaveAt12:
            let visit = debugFreshVisit(minutesAgo: 20)
            noteGymExit(at: visit.arrivedAt.addingTimeInterval(12 * 60))
            debugReportVisit(visit.id, prefix: "left at 12 min")

        case .stepOutThreeMinutes:
            let visit = debugFreshVisit(minutesAgo: 25)
            noteGymExit(at: visit.arrivedAt.addingTimeInterval(10 * 60))
            noteGymEntry(at: visit.arrivedAt.addingTimeInterval(13 * 60))
            debugReportVisit(visit.id, prefix: "out 10 to 13 min")

        case .healthWorkout22:
            // 8 minutes at the gym, not enough on its own, plus a 22 minute
            // watch workout that started at the gym.
            let visit = debugFreshVisit(minutesAgo: 30)
            noteGymExit(at: visit.arrivedAt.addingTimeInterval(8 * 60))
            debugEmitWorkout(start: visit.arrivedAt.addingTimeInterval(2 * 60), minutes: 22, handTyped: false)
            debugReportVisit(visit.id, prefix: "8 min + 22 min in Health")

        case .handTypedWorkout:
            let visit = debugFreshVisit(minutesAgo: 30)
            noteGymExit(at: visit.arrivedAt.addingTimeInterval(8 * 60))
            debugEmitWorkout(start: visit.arrivedAt.addingTimeInterval(2 * 60), minutes: 45, handTyped: true)
            debugReportVisit(visit.id, prefix: "8 min + 45 min typed by hand")

        case .unplannedVisit:
            // A visit with no alarm running, the way the permanent gym area
            // reports it. Counts on the arrival day, planned or not.
            endSession()
            visits.debugClear()
            let arrived = Date().addingTimeInterval(-21 * 60)
            guard let visit = recordUnscheduledVisit(fromStateCheck: false, at: arrived) else {
                Self.debugGymResult = "NOT RECORDED"
                return
            }
            evaluateVisits()
            let weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: arrived))
            let planned = weekday.map { debugStore?.plan.gymDays.contains($0) ?? false } ?? false
            debugReportVisit(visit.id, prefix: "no alarm · \(weekday?.shortLabel ?? "?") \(planned ? "planned" : "unplanned")")

        case .visitInSleepHours:
            // A sleep window open right now, then a visit inside it.
            endSession()
            visits.debugClear()
            debugEnsureShieldSelection()
            debugSetWindDownWindow(startMinutesAgo: 30, endMinutesFromNow: 8 * 60)
            debugReconcileWindDown()
            let visit = debugBeginVisit(
                arrivedAt: Date().addingTimeInterval(-21 * 60),
                countsOn: Calendar.current.startOfDay(for: Date())
            )
            evaluateVisits()
            let lock = shield.owner == .windDown && shield.isShielded ? "night lock on" : "NIGHT LOCK OFF"
            debugReportVisit(visit.id, prefix: lock)

        case .imHereCameraPhoto:
            endSession()
            visits.debugClear()
            let tapped = Date().addingTimeInterval(-5 * 60)
            let visit = debugBeginVisit(
                arrivedAt: tapped,
                countsOn: Calendar.current.startOfDay(for: tapped),
                timeCounts: false,
                manualAt: tapped
            )
            evaluateVisits(extraPhotos: [debugPhoto(source: .library)])
            let afterLibrary = visits.visits.first { $0.id == visit.id }?.isCounted == true
            evaluateVisits(extraPhotos: [debugPhoto(source: .camera)])
            debugReportVisit(visit.id, prefix: "library photo \(afterLibrary ? "COUNTED" : "ignored")")

        case .tapWorkoutDoneNotification:
            // Through the delegate's real routing, then the same check a
            // foreground runs. It must land on Progress and never start a
            // session.
            AlarmHandoff.clear()
            let day = Calendar.current.startOfDay(for: Date())
            let wrote = debugTap(NotificationRoute.ID.workoutDone(day: day, visitID: UUID()))
            openPendingSkipScreenIfNeeded()
            Self.debugGymResult =
                "handoff \(wrote ? "WRITTEN" : "none") · tab \(requestedTab == .progress ? "progress" : "NOT PROGRESS") · spotlight \(pendingSpotlightDay == nil ? "NOT SET" : "pending") · session \(session?.state.rawValue ?? "none")"

        // MARK: Skips
        //
        // Each example sets the week up in one tap and opens the skip screen
        // for the day in the FLOW example. They wipe this week's log entries,
        // so they write to your real log.

        case .exampleA:
            debugSetupWeek(days: [.monday, .wednesday, .friday], outcomes: [(0, .showedUp)])
            debugOpenSkipScreen(dayOffset: 2)
            debugReportSkipScreen("A: mon done, wed slept")

        case .exampleB:
            debugSetupWeek(
                days: [.monday, .tuesday, .wednesday, .thursday, .friday],
                outcomes: [(0, .showedUp)]
            )
            debugOpenSkipScreen(dayOffset: 1)
            debugReportSkipScreen("B: mon done, tue can't today")

        case .exampleC:
            debugSetupWeek(
                days: [.monday, .tuesday, .wednesday, .thursday, .friday],
                outcomes: [(0, .skipped), (1, .skipped)]
            )
            debugOpenSkipScreen(dayOffset: 2)
            debugReportSkipScreen("C: mon tue skipped, wed slept")

        case .exampleD:
            debugSetupWeek(days: [.monday, .wednesday, .friday], outcomes: [(0, .showedUp)])
            debugOpenSkipScreen(dayOffset: 2)
            debugReportSkipScreen("D: no watch, home workout")

        case .use3HomeWorkouts:
            guard let store = debugStore else { return }
            store.debugUseHomeWorkouts(3)
            let used = HomeWorkoutRules.usedThisMonth(log: store.log, now: Date())
            Self.debugSkipsResult =
                "\(used) of \(HomeWorkoutRules.monthlyLimit) used · picker \(used >= HomeWorkoutRules.monthlyLimit ? "GREYED OUT" : "open")"

        case .homeWorkoutNoHealthPhoto:
            // The full home-workout path: no Health workout, then a camera
            // photo taken after the timer. The photo is what counts it.
            guard let store = debugStore else { return }
            endSession()
            store.debugSeedGym()
            simulate(.alarmFired)
            beginCantToday()
            resolveCantToday(.homeWorkout)
            startQuickWorkout(minutes: 20)
            if var current = session {
                current.quickWorkoutStartedAt = Date().addingTimeInterval(-25 * 60)
                current.quickWorkoutDeadline = current.quickWorkoutStartedAt.map { $0.addingTimeInterval(20 * 60) }
                debugReplace(current)
            }
            finishQuickWorkout(completed: true)
            let stateBefore = session?.state.rawValue ?? "none"
            evaluateVisits(extraPhotos: [debugPhoto(source: .camera)])
            let outcome = store.log.outcomes.last
            Self.debugSkipsResult =
                "after timer: \(stateBefore) · after photo: \(outcome?.counts == true ? "counts (\(outcome?.proof.rawValue ?? "?"))" : "DOES NOT COUNT")"

        case .cancelAReschedule:
            guard let store = debugStore else { return }
            endSession()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            openSkipScreen(for: today)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let time = ReschedulePlanner.defaultTime(plan: store.plan, on: tomorrow)
            guard ReschedulePlanner.isTimeAvailable(time, on: tomorrow, plan: store.plan, now: Date()) else {
                Self.debugSkipsResult = "no usable time tomorrow; run earlier in the day"
                return
            }
            reschedule(to: tomorrow, at: time)
            guard let alarm = store.plan.oneOffAlarms.last(where: { $0.kind == .reschedule }) else {
                Self.debugSkipsResult = "RESCHEDULE NOT SET"
                return
            }
            cancelReschedule(alarm.id)
            let outcome = store.log.outcomes.last
            let gone = !store.plan.oneOffAlarms.contains { $0.id == alarm.id }
            Self.debugSkipsResult =
                "alarm \(gone ? "gone" : "STILL THERE") · outcome \(outcome?.kind.rawValue ?? "none") · counts \(outcome?.counts == true ? "YES" : "no")"

        case .skipOnSunday:
            debugSetupWeek(days: [.monday, .wednesday, .friday], outcomes: [])
            debugOpenSkipScreen(dayOffset: 6)
            debugReportSkipScreen("sunday")

        // MARK: Freezes and at risk

        case .jumpTwoMonthsAfterJoining:
            guard let store = debugStore else { return }
            let calendar = Calendar.current
            let joined = store.joinedAt
            let year = calendar.component(.year, from: joined)
            guard let grant = FreezeCalendar.grants(inYear: year, joined: joined, calendar: calendar).first,
                  grant.ordinal == 1,
                  calendar.date(byAdding: .month, value: 2, to: calendar.startOfDay(for: joined)) == grant.date
            else {
                Self.debugFreezeResult = "joined \(joined.formatted(date: .abbreviated, time: .omitted)): 2 months lands next year · no freeze this year · first is Mar 1"
                return
            }
            let held = store.debugRunFreezeCalendar(
                from: grant.date.addingTimeInterval(-60),
                to: grant.date.addingTimeInterval(12 * 3600),
                holding: 0
            )
            Self.debugFreezeResult = debugGrantReading(grant, held: held)

        case .jumpToJuly1:
            guard let store = debugStore else { return }
            let calendar = Calendar.current
            let joined = store.joinedAt
            let year = max(calendar.component(.year, from: Date()), calendar.component(.year, from: joined) + 1)
            guard let grant = FreezeCalendar.grants(inYear: year, joined: joined, calendar: calendar).last else {
                Self.debugFreezeResult = "NO JULY 1 GRANT"
                return
            }
            // Mar 1 already granted, as it would be by July.
            let held = store.debugRunFreezeCalendar(
                from: grant.date.addingTimeInterval(-60),
                to: grant.date.addingTimeInterval(12 * 3600),
                holding: 1
            )
            Self.debugFreezeResult = debugGrantReading(grant, held: held)

        case .newYearFreezesExpire:
            guard let store = debugStore else { return }
            let calendar = Calendar.current
            let year = calendar.component(.year, from: Date())
            guard let dec31 = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 12)),
                  let jan1 = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1, hour: 0, minute: 1))
            else { return }
            let held = store.debugRunFreezeCalendar(from: dec31, to: jan1, holding: 2)
            Self.debugFreezeResult = "held 2 on Dec 31 · Jan 1: \(held) held (expect 0)"

        case .planFreezeThisWeek:
            guard let store = debugStore else { return }
            endSession()
            let days = store.plan.gymDays.isEmpty ? Set<Weekday>([.monday, .wednesday, .friday]) : store.plan.gymDays
            debugSetupWeek(days: days, outcomes: [])
            store.debugEnsureFreeze()
            guard store.armFreezeForThisWeek() else {
                Self.debugFreezeResult = "COULD NOT PLAN A FREEZE"
                return
            }
            let now = Date()
            let alarms = AlarmPlan.alarms(for: store.plan, now: now, calendar: .current, pausedUntil: store.frozenWeekEnd)
            let end = store.frozenWeekEnd ?? now
            let gymThisWeek = alarms.filter { $0.kind.locks && ($0.fireDate.map { $0 < end } ?? true) }.count
            let gymMonday = alarms.filter { $0.kind.locks && ($0.fireDate.map { $0 >= end } ?? false) }.count
            let wake = alarms.contains { $0.kind == .plainWake }
            let night = store.plan.nextNightLockStart(after: now, calendar: .current) != nil
            Self.debugFreezeResult =
                "gym alarms this week: \(gymThisWeek) (expect 0) · back from Monday: \(gymMonday) · wake alarms \(wake ? "on" : "off") · night lock \(night ? "on" : "OFF") · freezes left \(store.streak.freezesAvailable)"

        case .atRiskThursday:
            debugReportAtRisk(counted: [0], simulatedDay: 3, homeWorkoutsUsed: nil)

        case .atRiskSunday:
            debugReportAtRisk(counted: [0, 2], simulatedDay: 6, homeWorkoutsUsed: nil)

        case .atRiskHomeWorkoutsUsedUp:
            debugReportAtRisk(counted: [0], simulatedDay: 3, homeWorkoutsUsed: HomeWorkoutRules.monthlyLimit)

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

    // MARK: - At the gym helpers

    /// The last at-the-gym result, shown in the panel.
    static var debugGymResult = "none"

    /// A visit that arrived `minutesAgo`, with time at the gym counting.
    private func debugFreshVisit(minutesAgo: Int) -> GymVisit {
        endSession()
        visits.debugClear()
        let arrived = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        let visit = debugBeginVisit(arrivedAt: arrived, countsOn: Calendar.current.startOfDay(for: arrived))
        evaluateVisits()
        return visit
    }

    private func debugEmitWorkout(start: Date, minutes: Int, handTyped: Bool) {
        let workout = DetectedWorkout(
            activityName: "Strength Training",
            startedAt: start,
            endedAt: start.addingTimeInterval(Double(minutes) * 60),
            source: handTyped ? "Health" : "Apple Watch",
            wasUserEntered: handTyped
        )
        visits.add([workout], now: Date())
        evaluateVisits()
    }

    /// A photo that only lives in memory, for the proof check.
    private func debugPhoto(source: ProgressPhotoSource) -> ProgressPhoto {
        ProgressPhoto(
            id: UUID(),
            createdAt: Date(),
            fileName: "debug.jpg",
            thumbnailName: "debug-thumb.jpg",
            source: source
        )
    }

    private func debugReportVisit(_ id: UUID, prefix: String) {
        guard let visit = visits.visits.first(where: { $0.id == id }) else {
            Self.debugGymResult = "\(prefix) · visit gone"
            return
        }
        let counted = visit.proof.map { "counts (\($0.rawValue))" } ?? "does NOT count"
        var notice = "no notice"
        if let line = visit.doneLine, let at = visit.doneFireAt {
            notice = "\"\(line)\" at \(TimeOfDay(from: at).clockString)"
        } else if visit.shortFireAt != nil {
            notice = "\"\(WorkoutDoneLine.shortVisit(minutes: visit.minutesBeforeLeaving))\""
        }
        Self.debugGymResult = "\(prefix) · \(counted) · \(notice)"
    }

    // MARK: - Skips helpers

    /// The last skips result, shown in the panel.
    static var debugSkipsResult = "none"

    /// A clean week for the examples: the given gym days, no one-offs, and
    /// nothing counted this week except the outcomes listed as
    /// `(dayOffsetFromMonday, kind)`.
    private func debugSetupWeek(days: Set<Weekday>, outcomes: [(Int, SessionOutcomeKind)]) {
        guard let store = debugStore else { return }
        store.seedPlanIfNeeded()
        store.debugSetGymDays(days)
        var plan = store.plan
        plan.oneOffAlarms = []
        store.plan = plan

        let calendar = Calendar.current
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let monday = StreakEngine.weekStart(containing: Date(), weekCalendar: weekCalendar) else { return }
        store.log.outcomes.removeAll {
            StreakEngine.weekStart(containing: $0.countingDay(calendar: calendar), weekCalendar: weekCalendar) == monday
        }
        for (offset, kind) in outcomes {
            let day = monday.addingTimeInterval(Double(offset) * 24 * 3600)
            store.log.record(SessionOutcome(date: day, kind: kind, countsOn: day))
        }
        store.refreshStreak()
    }

    /// Opens the skip screen for a day of this week, `dayOffset` days from
    /// its Monday.
    private func debugOpenSkipScreen(dayOffset: Int) {
        guard debugStore != nil else { return }
        let calendar = Calendar.current
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let monday = StreakEngine.weekStart(containing: Date(), weekCalendar: weekCalendar) else { return }
        endSession()
        openSkipScreen(for: monday.addingTimeInterval(Double(dayOffset) * 24 * 3600))
    }

    private func debugReportSkipScreen(_ prefix: String) {
        let plan = skipScreen
        let first = plan.options.first.map { option in
            switch option {
            case .reschedule: "reschedule"
            case .homeWorkout: "home workout"
            case .skip: "skip"
            }
        } ?? "none"
        let labels = rescheduleChoices.map(\.label).joined(separator: " ")
        Self.debugSkipsResult =
            "\(prefix) · \"\(plan.heading)\" · first: \(first) · choices: \(labels.isEmpty ? "none" : labels)"
    }

    // MARK: - Freezes and at risk helpers

    /// The last freezes-and-at-risk result, shown in the panel.
    static var debugFreezeResult = "none"

    private func debugGrantReading(_ grant: FreezeCalendar.Grant, held: Int) -> String {
        guard let store = debugStore else { return "none" }
        let fire = NoticeTime.fireDate(on: grant.date, plan: store.plan, calendar: .current)
        let when = fire.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "?"
        return "\(grant.date.formatted(date: .abbreviated, time: .omitted)): \(held) held · notice \"\(grant.line)\" at \(when)"
    }

    /// A kept week last week (so the streak is at least 1), Mon/Wed/Fri gym
    /// days, `counted` days of this week done, then the banner and next
    /// notice as they would read at 09:00 on `simulatedDay` (0 = Monday).
    private func debugReportAtRisk(counted: [Int], simulatedDay: Int, homeWorkoutsUsed: Int?) {
        guard let store = debugStore else { return }
        endSession()
        debugSetupWeek(days: [.monday, .wednesday, .friday], outcomes: counted.map { ($0, .showedUp) })

        let calendar = Calendar.current
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let monday = StreakEngine.weekStart(containing: Date(), weekCalendar: weekCalendar) else { return }
        for offset in [-7, -5, -3] {
            let day = monday.addingTimeInterval(Double(offset) * 24 * 3600)
            store.log.record(SessionOutcome(date: day.addingTimeInterval(7 * 3600), kind: .showedUp, countsOn: day, proof: .photo))
        }
        store.refreshStreak()

        let dayStart = monday.addingTimeInterval(Double(simulatedDay) * 24 * 3600)
        let at = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        let used = homeWorkoutsUsed ?? HomeWorkoutRules.usedThisMonth(log: store.log, now: at, calendar: calendar)
        let banner = StreakRisk.banner(
            log: store.log,
            plan: store.plan,
            streakWeeks: max(store.streak.weeks, 1),
            weeklyGoal: store.streak.weeklyGoal,
            isWeekFrozen: store.streak.isLiveWeekPreArmed,
            freezesHeld: store.streak.freezesAvailable,
            homeWorkoutsUsed: used,
            sawMakeUpToday: false,
            todayInProgress: false,
            now: at,
            calendar: calendar
        )
        let notice = StreakRisk.nextNotice(
            log: store.log,
            plan: store.plan,
            streakWeeks: max(store.streak.weeks, 1),
            weeklyGoal: store.streak.weeklyGoal,
            isWeekFrozen: store.streak.isLiveWeekPreArmed,
            freezesHeld: store.streak.freezesAvailable,
            sawMakeUpToday: false,
            alreadySentToday: false,
            todayInProgress: false,
            now: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart) ?? at,
            calendar: calendar
        )
        guard let banner else {
            Self.debugFreezeResult = "QUIET (not at risk)"
            return
        }
        let buttons = banner.showsHomeWorkout
            ? "[\(StreakRiskBanner.rescheduleLabel)] [\(banner.homeWorkoutLabel)]"
            : "[\(StreakRiskBanner.rescheduleLabel)] only"
        let freeze = banner.freezeLine.map { " \"\($0)\"" } ?? ""
        let when = notice.map { TimeOfDay(from: $0.fireDate).clockString } ?? "none"
        Self.debugFreezeResult = "\"\(banner.line)\"\(freeze) · \(buttons) · notice at \(when)"
    }

    // MARK: - Alarm rules helpers

    /// The last alarm-rules result, shown in the panel.
    static var debugAlarmRulesResult = "none"

    private func debugToday() -> Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: Date())) ?? .monday
    }

    /// Sets the rhythm straight onto the plan and makes sure today is a gym
    /// day, so the step runs whatever day it is.
    private func debugSetAlarmRhythm(wake: TimeOfDay, gym: TimeOfDay, getReady: Int, travel: Int) {
        guard let store = debugStore else { return }
        store.seedPlanIfNeeded()
        var plan = store.plan
        plan.rhythm.wakeTime = wake
        plan.rhythm.gymTime = gym
        plan.rhythm.getReadyMinutes = getReady
        plan.rhythm.travelMinutes = travel
        plan.oneOffAlarms = []
        if plan.slots.isEmpty {
            plan.slots = [AlarmSlot(days: [.monday, .wednesday, .friday], alarmTime: wake)]
        }
        if let index = plan.slots.firstIndex(where: { $0.id == plan.primaryAlarmSlot?.id }) {
            plan.slots[index].isEnabled = true
            plan.slots[index].days.insert(debugToday())
            plan.slots[index].alarmTime = plan.rhythm.lockAlarmTime
        }
        store.plan = plan
    }

    /// What rings today and on the first day that is not a gym day.
    private func debugAlarmSummary(on today: Weekday) -> String {
        guard let store = debugStore else { return "none" }
        let alarms = AlarmPlan.alarms(for: store.plan, now: Date(), calendar: .current)
        func ringing(on day: Weekday) -> String {
            let list = alarms.filter { $0.weekdays.contains(day) && $0.fireDate == nil }
            return list.map { "\($0.kind.rawValue) \($0.time.clockString)" }.joined(separator: " + ")
        }
        let gymDays = store.plan.gymDays
        let restDay = Weekday.allCases.first { !gymDays.contains($0) }
        let rest = restDay.map { "\($0.shortLabel): \(ringing(on: $0))" } ?? "no rest day"
        return "today: \(ringing(on: today)) · \(rest)"
    }

    /// A Go Later session that rang just now, with bedtime `bedtimeInMinutes`
    /// away and a 30 minute trip plus a 60 minute visit.
    private func debugStartGoLaterNow(bedtimeInMinutes: Int) {
        guard let store = debugStore else { return }
        debugEnsureShieldSelection()
        endSession()
        store.debugSeedGym()
        debugClearResolvedSlots()
        let now = Date()
        let bedtime = TimeOfDay(from: now.addingTimeInterval(Double(bedtimeInMinutes) * 60))
        var plan = store.plan
        plan.rhythm.bedtime = bedtime
        plan.rhythm.wakeTime = bedtime.offset(byMinutes: 8 * 60)
        plan.rhythm.gymTime = TimeOfDay(from: now.addingTimeInterval(30 * 60))
        plan.rhythm.getReadyMinutes = 10
        plan.rhythm.travelMinutes = 20
        plan.rhythm.gymSessionMinutes = 60
        plan.pendingBedtime = nil
        plan.oneOffAlarms = []
        store.plan = plan
        beginSession(for: store.plan.enabledSlots.first, at: now)
        // Go Later whatever the gap happens to be at this hour.
        if var current = session {
            current.flowMode = .goLater
            debugReplace(current)
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
