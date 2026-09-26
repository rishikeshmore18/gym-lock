import Foundation
import Testing
@testable import GymLock

/// `docs/FLOW.md`, "Everything to Change" items 5 to 9: the flow is chosen by
/// the gap, which alarms ring, ignored alarms end, running late, the plain
/// wake alarm.
@MainActor
struct AlarmRulesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }()

    /// 2026-09-28 is a Monday.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func rhythm(wake: TimeOfDay, gym: TimeOfDay?, getReady: Int = 20, travel: Int = 15) -> MorningRhythm {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = t(23)
        rhythm.wakeTime = wake
        rhythm.gymTime = gym
        rhythm.getReadyMinutes = getReady
        rhythm.travelMinutes = travel
        rhythm.hasBeenSet = true
        return rhythm
    }

    private func plan(_ rhythm: MorningRhythm, days: Set<Weekday> = [.monday, .wednesday, .friday]) -> MorningPlan {
        var plan = MorningPlan.default
        plan.rhythm = rhythm
        // Stored time deliberately stale: the ring follows the rhythm.
        plan.slots = [AlarmSlot(days: days, alarmTime: t(12))]
        plan.hasBeenReviewed = true
        return plan
    }

    /// Flow 1: wake 06:30, 20 + 15 min, gym by 07:05.
    private var wakeAndGo: MorningRhythm { rhythm(wake: t(6, 30), gym: nil) }
    /// Flow 2: wake 07:00, gym 18:00, 10 + 20 min.
    private var goLater: MorningRhythm { rhythm(wake: t(7), gym: t(18), getReady: 10, travel: 20) }

    // MARK: - Step 0

    @Test func aGapOfTwoHoursIsWakeAndGo() {
        #expect(rhythm(wake: t(7), gym: t(9)).flowMode == .wakeAndGo)
    }

    @Test func aGapOfTwoHoursAndOneMinuteIsGoLater() {
        #expect(rhythm(wake: t(7), gym: t(9, 1)).flowMode == .goLater)
    }

    @Test func theClockDoesNotDecide() {
        // An 11:30 wake with a noon gym is Wake & Go; a 05:00 wake with a
        // 09:00 gym is Go Later.
        #expect(rhythm(wake: t(11, 30), gym: t(12)).flowMode == .wakeAndGo)
        #expect(rhythm(wake: t(5), gym: t(9)).flowMode == .goLater)
    }

    @Test func aOneOffChangeFlipsTheModeForThatDayOnly() {
        var plan = plan(goLater, days: Set(Weekday.allCases))
        let tuesday = date(day: 29, 6, 30)
        plan.nextAlarmOverride = OneOffAlarm(slotID: plan.slots[0].id, fireDate: tuesday, rhythm: wakeAndGo)

        #expect(plan.flowMode(at: tuesday, calendar: calendar) == .wakeAndGo)
        #expect(plan.flowMode(at: date(day: 30, 6, 30), calendar: calendar) == .goLater)
        #expect(plan.flowMode(at: date(day: 28, 6, 30), calendar: calendar) == .goLater)
    }

    // MARK: - Which alarms ring

    @Test func timeToGoIsGymMinusGetReadyAndTravel() {
        #expect(goLater.timeToGo == t(17, 30))
        #expect(goLater.lockAlarmTime == t(17, 30))
        #expect(wakeAndGo.lockAlarmTime == t(6, 30))
    }

    @Test func wakeAndGoRingsTheGymAlarmAtWakeTimeWithSnooze() {
        let alarms = AlarmPlan.alarms(for: plan(wakeAndGo), now: date(day: 27, 12), calendar: calendar)
        let gym = alarms.filter { $0.kind == .gym }
        #expect(gym.count == 1)
        #expect(gym.first?.time == t(6, 30))
        #expect(gym.first?.weekdays == [.monday, .wednesday, .friday])
        #expect(gym.first?.allowsSnooze == true)
        #expect(!alarms.contains { $0.kind == .timeToGo })
    }

    @Test func wakeAndGoPutsThePlainAlarmOnTheOtherDaysAtTheSameTime() {
        let alarms = AlarmPlan.alarms(for: plan(wakeAndGo), now: date(day: 27, 12), calendar: calendar)
        let wake = alarms.filter { $0.kind == .plainWake }
        #expect(wake.count == 1)
        #expect(wake.first?.time == t(6, 30))
        #expect(wake.first?.weekdays == [.tuesday, .thursday, .saturday, .sunday])
        #expect(wake.first?.id == WakeAlarmID.weekly)
    }

    @Test func goLaterRingsTimeToGoWithoutSnoozeAndThePlainAlarmEveryDay() {
        let alarms = AlarmPlan.alarms(for: plan(goLater), now: date(day: 27, 12), calendar: calendar)
        let go = alarms.filter { $0.kind == .timeToGo }
        #expect(go.count == 1)
        #expect(go.first?.time == t(17, 30))
        #expect(go.first?.allowsSnooze == false)
        #expect(!alarms.contains { $0.kind == .gym })

        let wake = alarms.filter { $0.kind == .plainWake }
        #expect(wake.first?.time == t(7))
        #expect(wake.first?.weekdays == Set(Weekday.allCases))
    }

    @Test func switchingThePlainAlarmOffLeavesOnlyTheLockAlarm() {
        for rhythm in [wakeAndGo, goLater] {
            var plan = plan(rhythm)
            plan.plainWakeAlarmEnabled = false
            let alarms = AlarmPlan.alarms(for: plan, now: date(day: 27, 12), calendar: calendar)
            #expect(!alarms.contains { $0.kind == .plainWake })
            #expect(alarms.count == 1)
        }
    }

    @Test func exactlyOneLockAlarmPerGymDayAndNoneOnOtherDays() {
        for rhythm in [wakeAndGo, goLater] {
            let plan = plan(rhythm)
            let alarms = AlarmPlan.alarms(for: plan, now: date(day: 27, 12), calendar: calendar)
            for day in Weekday.allCases {
                let locks = alarms.filter { $0.kind.locks && $0.weekdays.contains(day) }.count
                #expect(locks == (plan.gymDays.contains(day) ? 1 : 0), "\(day) in \(rhythm.flowMode)")
            }
        }
    }

    @Test func aOneOffStandsInForItsDayAndStillLeavesOneLockAlarm() {
        var plan = plan(goLater, days: [.monday, .tuesday, .thursday])
        let tuesday = date(day: 29, 6, 30)
        plan.nextAlarmOverride = OneOffAlarm(slotID: plan.slots[0].id, fireDate: tuesday, rhythm: wakeAndGo)

        let alarms = AlarmPlan.alarms(for: plan, now: date(day: 28, 20), calendar: calendar)
        let tuesdayLocks = alarms.filter { $0.kind.locks && $0.weekdays.contains(.tuesday) }
        #expect(tuesdayLocks.count == 1)
        #expect(tuesdayLocks.first?.kind == .gym)
        #expect(tuesdayLocks.first?.fireDate == tuesday)
        // Wake & Go that day: the gym alarm is the wake-up, so no plain one.
        #expect(!alarms.contains { $0.kind == .plainWake && $0.weekdays.contains(.tuesday) })
    }

    @Test func theMainAlarmTimeFollowsTheRhythmNotTheStoredTime() {
        #expect(plan(goLater).enabledSlots.first?.alarmTime == t(17, 30))
        #expect(plan(wakeAndGo).enabledSlots.first?.alarmTime == t(6, 30))
    }

    @Test func noWakeAlarmBeforeThereIsAPlan() {
        var plan = MorningPlan.default
        plan.rhythm = wakeAndGo
        #expect(AlarmPlan.alarms(for: plan, now: date(day: 27, 12), calendar: calendar).isEmpty)
    }

    // MARK: - The plain wake alarm never starts a session

    @Test func plainWakeIdsAreRecognisedAndSlotIdsAreNot() {
        #expect(!WakeAlarmID.startsSession(alarmID: WakeAlarmID.weekly))
        #expect(!WakeAlarmID.startsSession(alarmID: WakeAlarmID.derive(from: UUID())))
        for _ in 0..<200 {
            #expect(WakeAlarmID.startsSession(alarmID: UUID()))
        }
    }

    @Test func aDerivedWakeIdIsStable() {
        let source = UUID()
        #expect(WakeAlarmID.derive(from: source) == WakeAlarmID.derive(from: source))
    }

    @Test func thePlainWakeNotificationUsesItsOwnPrefix() {
        let request = GymAlarmRequest(
            slotID: WakeAlarmID.weekly,
            time: t(7),
            weekdays: [.tuesday],
            title: "Wake up",
            message: "Good morning.",
            kind: .plainWake
        )
        let id = request.notificationIdentifier(for: .tuesday)
        #expect(id.hasPrefix(GymAlarmRequest.wakeIdentifierPrefix))
        #expect(!id.hasPrefix(GymAlarmRequest.identifierPrefix))
    }

    @Test func onlyWakeAndGoOffersASnooze() {
        #expect(SessionVoice(daypart: .evening, flowMode: .wakeAndGo).allowsSnooze)
        #expect(!SessionVoice(daypart: .morning, flowMode: .goLater).allowsSnooze)
    }

    // MARK: - An ignored alarm ends

    private func session(rangAt rang: Date, rhythm: MorningRhythm) -> GymSession {
        var session = GymSession(
            day: calendar.startOfDay(for: rang),
            slotID: UUID(),
            alarmTime: TimeOfDay(from: rang),
            isMorningSession: true,
            getReadyMinutes: rhythm.getReadyMinutes,
            travelMinutes: rhythm.travelMinutes
        )
        session.alarmFiredAt = rang
        session.flowMode = rhythm.flowMode
        session.lockDeadline = ShieldPolicy.deadline(forWindowMinutes: session.windowMinutes, from: rang)
        return session
    }

    @Test func flowOneLocksUntil0835AndThenTheAlarmIsMissed() {
        let ignored = session(rangAt: date(day: 28, 6, 30), rhythm: wakeAndGo)
        #expect(ignored.effectiveLockDeadline == date(day: 28, 8, 35))
        #expect(LeftoverSession.action(for: ignored, now: date(day: 28, 8, 34), calendar: calendar) == .keep)
        #expect(LeftoverSession.action(for: ignored, now: date(day: 28, 8, 35), calendar: calendar) == .endAsMissed)
    }

    @Test func flowTwoLocksUntil1930() {
        let ignored = session(rangAt: date(day: 28, 17, 30), rhythm: goLater)
        #expect(ignored.effectiveLockDeadline == date(day: 28, 19, 30))
    }

    @Test func aSnoozedSessionSleptThroughIsAlsoMissed() {
        var snoozed = session(rangAt: date(day: 28, 6, 30), rhythm: wakeAndGo)
        snoozed.state = .snoozed
        #expect(LeftoverSession.action(for: snoozed, now: date(day: 28, 8, 35), calendar: calendar) == .endAsMissed)
    }

    @Test func aCommittedSessionIsNeverEndedAsMissed() {
        var going = session(rangAt: date(day: 28, 6, 30), rhythm: wakeAndGo)
        going.state = .departed
        #expect(LeftoverSession.action(for: going, now: date(day: 28, 9), calendar: calendar) == .keep)
        // From yesterday it is dropped, never recorded.
        #expect(LeftoverSession.action(for: going, now: date(day: 29, 6), calendar: calendar) == .discard)
    }

    @Test func theNoticeStandsOnlyUntilTheUserAnswers() {
        #expect(MissedNotice.stands(for: .alarmFired))
        #expect(MissedNotice.stands(for: .snoozed))
        #expect(MissedNotice.stands(for: .runningLate))
        #expect(!MissedNotice.stands(for: .activationMission))
        #expect(!MissedNotice.stands(for: .cantToday))
        #expect(!MissedNotice.stands(for: .arrived))
    }

    @Test func theNoticeCopyFollowsTheAlarmTime() {
        #expect(MissedNotice.message(forAlarmAt: t(6, 30)) == "missed this morning. pick a day to make it up.")
        #expect(MissedNotice.message(forAlarmAt: t(12, 30)) == "missed today. pick a day to make it up.")
        #expect(MissedNotice.message(forAlarmAt: t(17, 30)) == "missed tonight. pick a day to make it up.")
        #expect(MissedNotice.message(forAlarmAt: t(10, 59)).contains("this morning"))
        #expect(MissedNotice.message(forAlarmAt: t(16)).contains("tonight"))
        for hour in [6, 12, 17] {
            #expect(!MissedNotice.message(forAlarmAt: t(hour)).contains("\u{2014}"))
        }
    }

    // MARK: - Ignored alarm, through the coordinator

    private func makeCoordinator(rhythm: MorningRhythm) -> (GymSessionCoordinator, AppStore, DemoShieldService) {
        let suite = "alarm-rules-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = AppStore(defaults: defaults)
        store.plan = plan(rhythm, days: Set(Weekday.allCases))
        let shield = DemoShieldService(defaults: defaults)
        shield.setDemoSelection(count: 3)
        let coordinator = GymSessionCoordinator(defaults: defaults, shield: shield)
        coordinator.bindStoreOnly(store)
        return (coordinator, store, shield)
    }

    @Test func anIgnoredAlarmEndsMissedUnlockedAndResolved() throws {
        let (coordinator, store, shield) = makeCoordinator(rhythm: wakeAndGo)
        let rang = Date().addingTimeInterval(-10 * 60)
        coordinator.beginSession(for: store.plan.enabledSlots.first, at: rang)
        let live = try #require(coordinator.session)
        #expect(shield.isShielded)
        #expect(live.lockDeadline == ShieldPolicy.deadline(forWindowMinutes: 35, from: rang))

        coordinator.endIgnoredSessionIfNeeded(now: live.effectiveLockDeadline.addingTimeInterval(-1))
        #expect(coordinator.session != nil)

        coordinator.endIgnoredSessionIfNeeded(now: live.effectiveLockDeadline)
        #expect(coordinator.session == nil)
        #expect(!shield.isShielded)
        let outcome = try #require(store.log.outcomes.last)
        #expect(outcome.kind == .missed)
        #expect(outcome.countingDay(calendar: .current) == Calendar.current.startOfDay(for: rang))
        #expect(coordinator.debugResolvedSlotKeys.contains(
            SessionResume.resolvedKey(slotID: live.slotID, day: live.day)
        ))
    }

    @Test func yesterdaysIgnoredSessionDoesNotBlockTodaysAlarm() throws {
        let (coordinator, store, _) = makeCoordinator(rhythm: wakeAndGo)
        let slot = store.plan.enabledSlots.first
        let yesterday = Date().addingTimeInterval(-24 * 3600)
        coordinator.beginSession(for: slot, at: yesterday)
        #expect(coordinator.session?.state == .alarmFired)

        coordinator.beginSession(for: slot, at: Date())
        let today = try #require(coordinator.session)
        #expect(Calendar.current.isDateInToday(today.day))
        #expect(today.state == .alarmFired)
        let missed = try #require(store.log.outcomes.last)
        #expect(missed.kind == .missed)
        #expect(Calendar.current.isDate(missed.countingDay(calendar: .current), inSameDayAs: yesterday))
        coordinator.endSession()
    }

    @Test func committingClosesTheMissedPath() throws {
        let (coordinator, store, _) = makeCoordinator(rhythm: wakeAndGo)
        coordinator.beginSession(for: store.plan.enabledSlots.first, at: Date())
        coordinator.commitToGoing()
        let live = try #require(coordinator.session)
        #expect(!MissedNotice.stands(for: live.state))
        coordinator.endIgnoredSessionIfNeeded(now: live.effectiveLockDeadline.addingTimeInterval(60))
        #expect(coordinator.session != nil)
        #expect(!store.log.outcomes.contains { $0.kind == .missed })
        coordinator.endSession()
    }

    // MARK: - Running late

    /// A Go Later session that rang at 19:45 with bedtime 22:00: a 30 min
    /// trip and a 60 min visit.
    private func lateSession() -> (GymSession, MorningRhythm, Date) {
        var rhythm = goLater
        rhythm.bedtime = t(22)
        rhythm.wakeTime = t(6)
        rhythm.gymSessionMinutes = 60
        let now = date(day: 28, 19, 45)
        var session = session(rangAt: now, rhythm: rhythm)
        session.flowMode = .goLater
        return (session, rhythm, now)
    }

    @Test func runningLateHidesTheChoicesThatRunIntoSleep() {
        let (session, rhythm, now) = lateSession()
        let options = RunningLate.options(for: session, rhythm: rhythm, pending: nil, now: now, calendar: calendar)
        // +60 rings 20:45, visit 21:15 to 22:15: into bedtime.
        #expect(options == [15, 30])
    }

    @Test func runningLateOffersAllThreeWithTimeToSpare() {
        var (session, rhythm, _) = lateSession()
        rhythm.bedtime = t(23, 30)
        session.state = .awaitingDecision
        let options = RunningLate.options(for: session, rhythm: rhythm, pending: nil, now: date(day: 28, 17, 30), calendar: calendar)
        #expect(options == [15, 30, 60])
    }

    @Test func runningLateIsOncePerSession() {
        let (session, rhythm, now) = lateSession()
        var late = RunningLate.apply(15, to: session, now: now)
        #expect(RunningLate.options(for: late, rhythm: rhythm, pending: nil, now: now, calendar: calendar).isEmpty)

        // The alarm rings again and the decision is back: still gone.
        late.state = .awaitingDecision
        late.runningLateUntil = nil
        #expect(RunningLate.options(for: late, rhythm: rhythm, pending: nil, now: now, calendar: calendar).isEmpty)
    }

    @Test func runningLateKeepsTheLockAndMovesTheDeadline() {
        let (session, _, now) = lateSession()
        let late = RunningLate.apply(30, to: session, now: now)
        #expect(late.state == .runningLate)
        #expect(late.state.wantsShield)
        #expect(!late.state.hasCommitted)
        #expect(late.runningLateUntil == date(day: 28, 20, 15))
        #expect(late.effectiveLockDeadline == ShieldPolicy.deadline(forWindowMinutes: 30, from: date(day: 28, 20, 15)))
        #expect(late.effectiveLockDeadline > session.effectiveLockDeadline)
        #expect(!RunningLate.hasElapsed(late, at: date(day: 28, 20, 14)))
        #expect(RunningLate.hasElapsed(late, at: date(day: 28, 20, 15)))
    }

    @Test func wakeAndGoHasNoRunningLate() {
        var session = session(rangAt: date(day: 28, 6, 30), rhythm: wakeAndGo)
        session.flowMode = .wakeAndGo
        #expect(RunningLate.options(for: session, rhythm: wakeAndGo, pending: nil, now: date(day: 28, 6, 31), calendar: calendar).isEmpty)
    }

    @Test func theRunningLateAlarmDoesNotReplaceTheWeeklyRing() {
        var plan = plan(goLater)
        let ring = date(day: 28, 18)
        plan.oneOffAlarms = [OneOffAlarm(kind: .runningLate, slotID: plan.slots[0].id, fireDate: ring)]
        let alarms = AlarmPlan.alarms(for: plan, now: date(day: 28, 17, 40), calendar: calendar)
        let oneOff = alarms.first { $0.fireDate == ring }
        #expect(oneOff?.kind == .timeToGo)
        #expect(oneOff?.allowsSnooze == false)
        #expect(alarms.contains { $0.fireDate == nil && $0.kind == .timeToGo && $0.weekdays.contains(.monday) })
    }

    // MARK: - Phone off, alarm never rang

    @Test func aPassedGymDayWithNothingIsOffered() {
        let plan = plan(wakeAndGo)
        let found = MissedDayCheck.unhandledGymDay(
            now: date(day: 28, 9), plan: plan, handledDays: [], notBefore: date(day: 1, 0), calendar: calendar
        )
        #expect(found == date(day: 28, 0))
    }

    @Test func notBeforeTheLockWouldHaveLifted() {
        let found = MissedDayCheck.unhandledGymDay(
            now: date(day: 28, 8, 34), plan: plan(wakeAndGo), handledDays: [], notBefore: date(day: 1, 0), calendar: calendar
        )
        #expect(found == nil)
    }

    @Test func aDayWithAnOutcomeOrAlreadyOfferedIsNotOffered() {
        let found = MissedDayCheck.unhandledGymDay(
            now: date(day: 28, 9), plan: plan(wakeAndGo), handledDays: [date(day: 28, 0)],
            notBefore: date(day: 1, 0), calendar: calendar
        )
        #expect(found == nil)
    }

    @Test func daysBeforeTheCheckExistedAreNeverOffered() {
        let found = MissedDayCheck.unhandledGymDay(
            now: date(day: 30, 23), plan: plan(wakeAndGo), handledDays: [],
            notBefore: date(day: 30, 12), calendar: calendar
        )
        // Wednesday itself is still offered; Monday is before the floor.
        #expect(found == date(day: 30, 0))
    }

    @Test func thePhoneOffDayIsOfferedOnceAndNothingIsRecorded() throws {
        let (coordinator, store, _) = makeCoordinator(rhythm: rhythm(wake: t(9), gym: nil))
        store.stage = .home
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let before = store.log.outcomes.count

        let first = coordinator.offerMissedGymDayIfNeeded(now: noon)
        #expect(first == Calendar.current.startOfDay(for: noon))
        #expect(coordinator.route == .cantToday)
        #expect(coordinator.session?.isMakeUpOffer == true)
        coordinator.endSession()

        #expect(coordinator.offerMissedGymDayIfNeeded(now: noon) == nil)
        #expect(store.log.outcomes.count == before)
    }

    // MARK: - Old saved data

    @Test func anOldPlanWithASingleOverrideDecodesIntoTheList() throws {
        let slot = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF") ?? UUID()
        let overrideID = UUID(uuidString: "7F9619FF-8B86-D011-B42D-00C04FC964FF") ?? UUID()
        let json = """
        {"rhythm":{"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":6,"minute":30},"getReadyMinutes":20,"travelMinutes":15,"hasBeenSet":true},
         "nightLock":{"isEnabled":true,"followsRhythm":true,"customStart":{"hour":23,"minute":0},"customEnd":{"hour":6,"minute":30}},
         "slots":[{"id":"\(slot.uuidString)","days":[2,4,6],"alarmTime":{"hour":6,"minute":30},"isEnabled":true}],
         "missionsEnabled":true,"recentMissions":[],"hasBeenReviewed":true,
         "nextAlarmOverride":{"id":"\(overrideID.uuidString)","slotID":"\(slot.uuidString)","fireDate":812000000,
           "rhythm":{"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":5,"minute":45},"getReadyMinutes":20,"travelMinutes":15,"hasBeenSet":true}}}
        """
        let plan = try JSONDecoder().decode(MorningPlan.self, from: Data(json.utf8))
        #expect(plan.oneOffAlarms.count == 1)
        #expect(plan.oneOffAlarms.first?.kind == .nextAlarmChange)
        #expect(plan.oneOffAlarms.first?.id == overrideID)
        #expect(plan.nextAlarmOverride?.rhythm?.wakeTime == t(5, 45))
        #expect(plan.plainWakeAlarmEnabled)
    }

    @Test func anOldPlanWithNoOverrideDecodesEmpty() throws {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: [.monday], alarmTime: t(6, 30))]
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any]
        )
        object.removeValue(forKey: "oneOffAlarms")
        object.removeValue(forKey: "plainWakeAlarmEnabled")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MorningPlan.self, from: data)
        #expect(decoded.oneOffAlarms.isEmpty)
        #expect(decoded.plainWakeAlarmEnabled)
    }

    @Test func oneOffAlarmsRoundTrip() throws {
        var plan = plan(goLater)
        plan.plainWakeAlarmEnabled = false
        plan.oneOffAlarms = [
            OneOffAlarm(kind: .runningLate, slotID: plan.slots[0].id, fireDate: date(day: 28, 18)),
            OneOffAlarm(kind: .nextAlarmChange, slotID: plan.slots[0].id, fireDate: date(day: 29, 6), rhythm: wakeAndGo),
        ]
        let decoded = try JSONDecoder().decode(MorningPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded == plan)
    }

    @Test func anOldSessionDecodesAndFallsBackToTheClock() throws {
        var old = session(rangAt: date(day: 28, 17, 30), rhythm: goLater)
        // Set directly: the helper reads the time in the device's zone, not
        // the test calendar's.
        old.alarmTime = t(17, 30)
        old.flowMode = nil
        old.lockDeadline = nil
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any]
        )
        for key in ["flowMode", "lockDeadline", "runningLateUsedAt", "runningLateUntil", "isMakeUpOffer"] {
            object.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(
            GymSession.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.resolvedFlowMode == .goLater)
        #expect(decoded.effectiveLockDeadline == date(day: 28, 19, 30))
        #expect(decoded.runningLateUsedAt == nil)
    }
}
