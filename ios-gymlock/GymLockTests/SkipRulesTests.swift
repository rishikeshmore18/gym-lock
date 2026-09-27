import Foundation
import Testing
@testable import GymLock

/// `docs/FLOW.md`, Flow 4 and its edge cases: the one skip screen, real
/// reschedules, and the home workout's rules.
@MainActor
struct SkipRulesTests {
    private let calendar = Calendar.current

    /// Monday of the current week, so every fixture stays inside one week.
    private var monday: Date {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        return StreakEngine.weekStart(containing: Date(), weekCalendar: weekCalendar) ?? Date()
    }

    /// `offset` days from Monday: 0 Monday, 6 Sunday.
    private func day(_ offset: Int) -> Date {
        monday.addingTimeInterval(Double(offset) * 24 * 3600)
    }

    /// Tomorrow morning, so alarm times are always in the future whatever the
    /// clock says when the tests run.
    private var tomorrow: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    /// The FLOW examples' rhythm: sleep 23:00 to 06:30, gym 30 minutes after
    /// the alarm (10 + 20), so Wake & Go and the 06:30 lock alarm.
    private func makePlan(days: Set<Weekday>) -> MorningPlan {
        var plan = MorningPlan.default
        plan.rhythm.bedtime = TimeOfDay(hour: 23, minute: 0)
        plan.rhythm.wakeTime = TimeOfDay(hour: 6, minute: 30)
        plan.rhythm.gymTime = TimeOfDay(hour: 7, minute: 30)
        plan.rhythm.getReadyMinutes = 10
        plan.rhythm.travelMinutes = 20
        plan.rhythm.hasBeenSet = true
        plan.pendingBedtime = nil
        plan.slots = [AlarmSlot(days: days, alarmTime: plan.rhythm.lockAlarmTime)]
        plan.oneOffAlarms = []
        return plan
    }

    private func makeLog(_ outcomes: (offset: Int, kind: SessionOutcomeKind)...) -> MomentumLog {
        var log = MomentumLog.empty
        for outcome in outcomes {
            let date = day(outcome.offset)
            log.record(SessionOutcome(date: date, kind: outcome.kind, countsOn: date))
        }
        return log
    }

    // MARK: - Example A (FLOW, Flow 4)

    @Test func exampleAWeekNotReachableReschedulesFirst() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])
        let log = makeLog((0, .showedUp))
        let screen = SkipRules.screen(log: log, plan: plan, day: day(2), now: Date(), calendar: calendar)

        #expect(screen.heading == "make it up. this keeps your streak.")
        #expect(screen.options == [.reschedule, .homeWorkout, .skip])
    }

    @Test func exampleAChoicesIncludeThuSatSunButNotFri() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])
        let log = makeLog((0, .showedUp))
        let choices = ReschedulePlanner.choices(plan: plan, day: day(2), now: monday, calendar: calendar)
        let labels = choices.filter { !$0.isLaterToday }.map(\.label)

        #expect(labels.contains(Weekday.thursday.shortLabel))
        #expect(labels.contains(Weekday.saturday.shortLabel))
        #expect(labels.contains(Weekday.sunday.shortLabel))
        #expect(!labels.contains(Weekday.friday.shortLabel))
    }

    @Test func exampleAThuAndFriDoneIsThree() {
        let log = makeLog((0, .showedUp), (3, .showedUp), (4, .showedUp))
        #expect(StreakEngine.sessionDays(in: log, weekStarting: monday, calendar: calendar).count == 3)
    }

    // MARK: - Example B (FLOW, Flow 4)

    @Test func exampleBWeekReachableSkipFirst() {
        let plan = makePlan(days: [.monday, .tuesday, .wednesday, .thursday, .friday])
        let log = makeLog((0, .showedUp))
        let screen = SkipRules.screen(log: log, plan: plan, day: day(1), now: Date(), calendar: calendar)

        #expect(screen.heading == "no problem. you need 2 more this week.")
        #expect(screen.options.first == .skip)
    }

    @Test func exampleBHomeWorkoutWithA22MinuteHealthWorkoutCounts() {
        let timerStart = day(2).addingTimeInterval(18 * 3600)
        let workout = DetectedWorkout(
            activityName: "Strength Training",
            startedAt: timerStart.addingTimeInterval(5 * 60),
            endedAt: timerStart.addingTimeInterval(27 * 60),
            source: "Apple Watch",
            wasUserEntered: false
        )
        #expect(HomeWorkoutRules.healthQualifies(workout, timerStart: timerStart, calendar: calendar))

        var log = makeLog((0, .showedUp))
        log.record(
            SessionOutcome(date: timerStart, kind: .homeWorkout, minutes: 20, countsOn: day(2), proof: .health)
        )
        #expect(StreakEngine.sessionDays(in: log, weekStarting: monday, calendar: calendar).count == 2)
    }

    // MARK: - Example C (FLOW, Flow 4)

    @Test func exampleCBadWeekReschedulesToAFreeDay() {
        let plan = makePlan(days: [.monday, .tuesday, .wednesday, .thursday, .friday])
        let log = makeLog((0, .skipped), (1, .skipped))

        let screen = SkipRules.screen(log: log, plan: plan, day: day(2), now: monday, calendar: calendar)
        #expect(screen.heading == "make it up. this keeps your streak.")
        #expect(screen.options.first == .reschedule)

        let labels = ReschedulePlanner.choices(plan: plan, day: day(2), now: monday, calendar: calendar).map(\.label)
        #expect(labels.contains(Weekday.saturday.shortLabel))
        #expect(labels.contains(Weekday.sunday.shortLabel))
    }

    @Test func exampleCMissedRescheduleIsOfferedAgainOnSunday() {
        let plan = makePlan(days: [.monday, .tuesday, .wednesday, .thursday, .friday])
        // Thursday and Friday done, Saturday's reschedule missed.
        let log = makeLog((0, .skipped), (1, .skipped), (3, .showedUp), (4, .showedUp))

        let choices = ReschedulePlanner.choices(plan: plan, day: day(5), now: monday, calendar: calendar)
        #expect(choices.map(\.label).contains(Weekday.sunday.shortLabel))
    }

    @Test func exampleCSundayDoneIsThree() {
        let log = makeLog((0, .skipped), (1, .skipped), (3, .showedUp), (4, .showedUp), (6, .showedUp))
        #expect(StreakEngine.sessionDays(in: log, weekStarting: monday, calendar: calendar).count == 3)
    }

    // MARK: - Sunday and free days (edge cases)

    @Test func sundayHasNoRescheduleChoices() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])
        // `now` is Monday, so "later today" can never appear for a Sunday.
        let choices = ReschedulePlanner.choices(plan: plan, day: day(6), now: monday, calendar: calendar)
        #expect(choices.isEmpty)
    }

    @Test func sundayHidesRescheduleAndOffersTheRest() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])
        let screen = SkipRules.screen(log: makeLog(), plan: plan, day: day(6), now: monday, calendar: calendar)
        #expect(screen.options == [.homeWorkout, .skip])
    }

    @Test func noFreeDaysButWeekReachableHidesRescheduleWithTheNote() {
        // 7 planned days leaves no free day, and one workout means the week
        // is already reachable with the planned days left.
        let plan = makePlan(days: Set(Weekday.allCases))
        let log = makeLog((0, .showedUp))
        let screen = SkipRules.screen(log: log, plan: plan, day: day(1), now: monday, calendar: calendar)

        #expect(!screen.options.contains(.reschedule))
        #expect(screen.rescheduleNote == "your planned days left are enough.")
    }

    // MARK: - Reschedule times

    @Test func timesInsideSleepHoursCannotBePicked() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])

        #expect(!ReschedulePlanner.isTimeAvailable(
            TimeOfDay(hour: 23, minute: 30), on: tomorrow, plan: plan, now: Date(), calendar: calendar
        ))
        #expect(ReschedulePlanner.isTimeAvailable(
            TimeOfDay(hour: 12, minute: 0), on: tomorrow, plan: plan, now: Date(), calendar: calendar
        ))
    }

    @Test func theVisitMustFitBeforeBedtime() {
        var plan = makePlan(days: [.monday, .wednesday, .friday])
        // 30 minute window + 60 minute visit: 22:00 rings, 22:30 to 23:30
        // runs into the 23:00 bedtime.
        #expect(!ReschedulePlanner.isTimeAvailable(
            TimeOfDay(hour: 22, minute: 0), on: tomorrow, plan: plan, now: Date(), calendar: calendar
        ))
        // A shorter visit fits.
        plan.rhythm.gymSessionMinutes = 15
        #expect(ReschedulePlanner.isTimeAvailable(
            TimeOfDay(hour: 22, minute: 0), on: tomorrow, plan: plan, now: Date(), calendar: calendar
        ))
    }

    @Test func laterTodayIsHiddenNearBedtime() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])
        let today = calendar.startOfDay(for: Date())
        let lateEvening = today.addingTimeInterval(22 * 3600 + 10 * 60)

        let choices = ReschedulePlanner.choices(plan: plan, day: lateEvening, now: lateEvening, calendar: calendar)
        #expect(!choices.contains { $0.isLaterToday })
    }

    @Test func laterTodayShowsWhenTimeIsLeft() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])
        let today = calendar.startOfDay(for: Date())
        let morning = today.addingTimeInterval(10 * 3600)

        let choices = ReschedulePlanner.choices(plan: plan, day: morning, now: morning, calendar: calendar)
        #expect(choices.contains { $0.isLaterToday })
    }

    @Test func choicesNeverLeaveThisWeek() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let choices = ReschedulePlanner.choices(plan: plan, day: day(2), now: Date(), calendar: calendar)
        #expect(choices.allSatisfy { $0.day < nextMonday })
    }

    // MARK: - Reschedules are real alarms (through the coordinator)

    private func makeCoordinator() -> (GymSessionCoordinator, AppStore) {
        let suite = "skip-rules-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = AppStore(defaults: defaults)
        store.plan = makePlan(days: [.monday, .wednesday, .friday])
        let coordinator = GymSessionCoordinator(defaults: defaults, shield: DemoShieldService(defaults: defaults))
        coordinator.bindStoreOnly(store)
        return (coordinator, store)
    }

    @Test func aRescheduleSetsARealOneOffAlarmAndUnlocksNow() throws {
        let (coordinator, store) = makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }

        let origin = calendar.startOfDay(for: Date())
        coordinator.openSkipScreen(for: origin)
        coordinator.reschedule(to: tomorrow, at: TimeOfDay(hour: 6, minute: 30))

        let alarm = try #require(store.plan.oneOffAlarms.first { $0.kind == .reschedule })
        #expect(calendar.isDate(alarm.originDay ?? Date(), inSameDayAs: origin))

        let alarms = AlarmPlan.alarms(for: store.plan, now: Date(), calendar: calendar)
        let rescheduledDay = calendar.component(.weekday, from: tomorrow)
        #expect(alarms.contains {
            $0.kind == .gym && $0.weekdays.contains(Weekday(rawValue: rescheduledDay) ?? .monday) && $0.fireDate != nil
        })
        // The rescheduled alarm replaces the plain wake alarm that day.
        #expect(!alarms.contains { $0.kind == .plainWake && $0.weekdays.contains(Weekday(rawValue: rescheduledDay) ?? .monday) })

        // Apps unlock now, and the day is given up as a reschedule.
        #expect(coordinator.session == nil)
        let outcome = store.log.outcomes.last
        #expect(outcome?.kind == .rescheduled)
        #expect(outcome?.counts == false)
        #expect(calendar.isDate(outcome?.countingDay(calendar: calendar) ?? Date(), inSameDayAs: origin))
    }

    @Test func aRescheduleMissedThenDoneKeepsTheComebackLineTrue() {
        // can't today on Wednesday, reschedule, done: the last day before the
        // workout was given up, so "you came back" is true.
        let log = makeLog((2, .rescheduled))
        #expect(WorkoutDoneLine.isComeback(log: log, day: day(3), calendar: calendar))
    }

    @Test func cancellingARescheduleBecomesASkip() throws {
        let (coordinator, store) = makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }

        let origin = calendar.startOfDay(for: Date())
        coordinator.openSkipScreen(for: origin)
        coordinator.reschedule(to: tomorrow, at: TimeOfDay(hour: 6, minute: 30))
        let alarm = try #require(store.plan.oneOffAlarms.first(where: { $0.kind == .reschedule }))

        coordinator.cancelReschedule(alarm.id)

        #expect(!store.plan.oneOffAlarms.contains { $0.id == alarm.id })
        let outcome = store.log.outcomes.last
        #expect(outcome?.kind == .skipped)
        #expect(outcome?.counts == false)
        #expect(calendar.isDate(outcome?.countingDay(calendar: calendar) ?? Date(), inSameDayAs: origin))
    }

    @Test func pendingReschedulesShowOnTheAlarmScreen() {
        let (coordinator, store) = makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }

        #expect(coordinator.pendingReschedules.isEmpty)
        coordinator.openSkipScreen(for: calendar.startOfDay(for: Date()))
        coordinator.reschedule(to: tomorrow, at: TimeOfDay(hour: 6, minute: 30))
        #expect(coordinator.pendingReschedules.count == 1)
        #expect(coordinator.skipScreen.rescheduleNote == nil)
    }

    // MARK: - Home workout

    @Test func homeWorkoutOptionsAreTwentyAndThirty() {
        #expect(HomeWorkoutRules.options == [20, 30])
        #expect(HomeWorkoutRules.defaultMinutes == 20)
    }

    @Test func theFourthHomeWorkoutInAMonthIsGreyed() {
        var log = MomentumLog.empty
        // Three counted home workouts this month, at three different hours of
        // one day, so the fixture cannot drift across a month boundary.
        for hour in [9, 12, 18] {
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
            log.record(SessionOutcome(date: date, kind: .homeWorkout, minutes: 20, countsOn: date, proof: .photo))
        }
        #expect(HomeWorkoutRules.usedThisMonth(log: log, now: Date(), calendar: calendar) == 3)
        #expect(HomeWorkoutRules.atCap(log: log, now: Date(), calendar: calendar))
        #expect(HomeWorkoutRules.capMessage == "3 of 3 home workouts used. back on the 1st.")
    }

    @Test func theCapResetsOnTheFirst() {
        var log = MomentumLog.empty
        // Three counted home workouts, all in the previous calendar month:
        // the first of last month, at three different hours.
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()) else { return }
        let firstOfLastMonth = max(
            calendar.dateInterval(of: .month, for: lastMonth)?.start ?? lastMonth,
            min(lastMonth, calendar.date(byAdding: .day, value: -28, to: Date()) ?? lastMonth)
        )
        for hour in [9, 12, 18] {
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: firstOfLastMonth) ?? lastMonth
            log.record(SessionOutcome(date: date, kind: .homeWorkout, minutes: 20, countsOn: date, proof: .photo))
        }
        #expect(HomeWorkoutRules.usedThisMonth(log: log, now: Date(), calendar: calendar) == 0)
        #expect(!HomeWorkoutRules.atCap(log: log, now: Date(), calendar: calendar))
    }

    @Test func unverifiedAttemptsDoNotUseUpTheCap() {
        var log = MomentumLog.empty
        for hour in [9, 12, 18] {
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
            log.record(SessionOutcome(date: date, kind: .homeWorkout, minutes: 20, countsOn: date, proof: .unproven))
        }
        #expect(!HomeWorkoutRules.atCap(log: log, now: Date(), calendar: calendar))
    }

    @Test func startingAHomeWorkoutIsRefusedAtTheCap() {
        let (coordinator, store) = makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }
        store.debugUseHomeWorkouts(3)

        coordinator.openSkipScreen(for: calendar.startOfDay(for: Date()))
        coordinator.resolveCantToday(.homeWorkout)
        coordinator.startQuickWorkout(minutes: 20)

        #expect(coordinator.session?.quickWorkoutMinutes == nil)
    }

    @Test func theHomeWorkoutHealthCheckRunsSameDayOnly() {
        let timerStart = day(2).addingTimeInterval(22 * 3600)
        func workout(startingAfterMinutes: Double, length: Double, handTyped: Bool = false) -> DetectedWorkout {
            let start = timerStart.addingTimeInterval(startingAfterMinutes * 60)
            return DetectedWorkout(
                activityName: "Strength Training",
                startedAt: start,
                endedAt: start.addingTimeInterval(length * 60),
                source: "Apple Watch",
                wasUserEntered: handTyped
            )
        }

        #expect(HomeWorkoutRules.healthQualifies(workout(startingAfterMinutes: 5, length: 22), timerStart: timerStart, calendar: calendar))
        // Same rules as the gym: 19 minutes is not enough, hand-typed ignored,
        // and 15 minutes before the timer is allowed.
        #expect(!HomeWorkoutRules.healthQualifies(workout(startingAfterMinutes: 5, length: 19), timerStart: timerStart, calendar: calendar))
        #expect(!HomeWorkoutRules.healthQualifies(workout(startingAfterMinutes: 5, length: 30, handTyped: true), timerStart: timerStart, calendar: calendar))
        #expect(HomeWorkoutRules.healthQualifies(workout(startingAfterMinutes: -15, length: 30), timerStart: timerStart, calendar: calendar))
        // Within the 5 hour window, but the next day: not the same day.
        #expect(!HomeWorkoutRules.healthQualifies(workout(startingAfterMinutes: 8 * 60, length: 30), timerStart: timerStart, calendar: calendar))
    }

    @Test func thePhotoRuleIsCameraAfterTheTimerSameDay() {
        let timerStart = day(2).addingTimeInterval(18 * 3600)
        func photo(_ source: ProgressPhotoSource, _ created: Date) -> ProgressPhoto {
            ProgressPhoto(id: UUID(), createdAt: created, fileName: "p.jpg", thumbnailName: "t.jpg", source: source)
        }

        // Camera after the timer counts.
        #expect(PhotoProof.qualifies(photo(.camera, timerStart.addingTimeInterval(10 * 60)), takenAfter: timerStart, calendar: calendar))
        // Library never counts.
        #expect(!PhotoProof.qualifies(photo(.library, timerStart.addingTimeInterval(10 * 60)), takenAfter: timerStart, calendar: calendar))
        // Taken before the timer doesn't.
        #expect(!PhotoProof.qualifies(photo(.camera, timerStart.addingTimeInterval(-60)), takenAfter: timerStart, calendar: calendar))
        // The next day doesn't.
        #expect(!PhotoProof.qualifies(photo(.camera, timerStart.addingTimeInterval(24 * 3600)), takenAfter: timerStart, calendar: calendar))
    }

    @Test func aHomeWorkoutCountsOnlyOnceProven() {
        let unproven = SessionOutcome(kind: .homeWorkout, minutes: 20, proof: .unproven)
        #expect(!unproven.counts)

        let health = SessionOutcome(kind: .homeWorkout, minutes: 20, proof: .health)
        #expect(health.counts)

        let photo = SessionOutcome(kind: .homeWorkout, minutes: 20, proof: .photo)
        #expect(photo.counts)

        #expect(HomeWorkoutRules.notFoundMessage == "no workout in Apple Health? add a progress photo to count it.")
    }

    @Test func aHomeWorkoutFollowedByACameraPhotoCountsThroughTheTracker() {
        let (coordinator, store) = makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }

        let timerStart = Date().addingTimeInterval(-25 * 60)
        let outcome = SessionOutcome(kind: .homeWorkout, minutes: 20, countsOn: calendar.startOfDay(for: Date()), proof: .unproven)
        store.log.record(outcome)
        let visit = GymVisit(
            outcomeID: outcome.id,
            sessionID: nil,
            countsOn: calendar.startOfDay(for: Date()),
            arrivedAt: timerStart,
            timeCounts: false,
            manualAt: timerStart,
            isHome: true
        )
        coordinator.visits.begin(visit)

        // No proof yet.
        coordinator.evaluateVisits()
        #expect(coordinator.visits.visits.first?.isCounted != true)

        // A camera photo taken after the timer counts it.
        let photo = ProgressPhoto(
            id: UUID(),
            createdAt: Date(),
            fileName: "p.jpg",
            thumbnailName: "t.jpg",
            source: .camera
        )
        coordinator.evaluateVisits(extraPhotos: [photo])
        #expect(coordinator.visits.visits.first?.proof == .photo)
        #expect(store.log.outcomes.first?.counts == true)
    }

    @Test func aHomeWorkoutDoesNotBlockOrTakeAnUnscheduledGymVisit() {
        let (coordinator, store) = makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }

        let timerStart = Date().addingTimeInterval(-90 * 60)
        let outcome = SessionOutcome(kind: .homeWorkout, minutes: 20, countsOn: calendar.startOfDay(for: Date()), proof: .unproven)
        store.log.record(outcome)
        coordinator.visits.begin(
            GymVisit(
                outcomeID: outcome.id,
                sessionID: nil,
                countsOn: calendar.startOfDay(for: Date()),
                arrivedAt: timerStart,
                timeCounts: false,
                manualAt: timerStart,
                isHome: true
            )
        )

        // The open home workout doesn't stop a real gym visit, and a region
        // exit never lands on it.
        let visit = coordinator.recordUnscheduledVisit(fromStateCheck: false)
        #expect(visit != nil)
        #expect(visit?.isHome == false)
    }

    // MARK: - Old data still loads

    @Test func oldSkipKindsDecodeAndDoNotCount() throws {
        let json = #"""
        {"outcomes": [
          {"id":"11111111-1111-1111-1111-111111111111","date":800000000,"kind":"easySkip","workoutDetected":false},
          {"id":"22222222-2222-2222-2222-222222222222","date":800003600,"kind":"dayOff","workoutDetected":false}
        ]}
        """#
        let log = try JSONDecoder().decode(MomentumLog.self, from: Data(json.utf8))
        #expect(log.outcomes.count == 2)
        #expect(log.outcomes.allSatisfy { !$0.counts })
        #expect(log.outcomes.map(\.kind) == [.easySkip, .dayOff])
    }

    @Test func newSkipsDecodeAndDoNotCount() throws {
        let json = #"{"id":"33333333-3333-3333-3333-333333333333","date":800000000,"kind":"skipped","workoutDetected":false}"#
        let outcome = try JSONDecoder().decode(SessionOutcome.self, from: Data(json.utf8))
        #expect(outcome.kind == .skipped)
        #expect(!outcome.counts)
    }

    @Test func anOldHomeWorkoutDecodesAsLegacyAndKeepsCounting() throws {
        let json = #"{"id":"44444444-4444-4444-4444-444444444444","date":800000000,"kind":"homeWorkout","workoutDetected":false}"#
        let outcome = try JSONDecoder().decode(SessionOutcome.self, from: Data(json.utf8))
        #expect(outcome.counts)
        #expect(outcome.proof == .legacy)
    }

    @Test func anOldHomeWorkoutProofIsNeededForTheStreak() {
        let legacy = SessionOutcome(kind: .homeWorkout, minutes: 15)
        #expect(legacy.counts)
        #expect(legacy.proof == .legacy)
    }

    @Test func oldResolutionsDecodeIntoTheNewOnes() throws {
        let within24h = try JSONDecoder().decode(CantTodayResolution.self, from: Data(#""rescheduledWithin24h""#.utf8))
        #expect(within24h == .skip)

        let quick = try JSONDecoder().decode(CantTodayResolution.self, from: Data(#""quickWorkout""#.utf8))
        #expect(quick == .homeWorkout)

        let off = try JSONDecoder().decode(CantTodayResolution.self, from: Data(#""tookTheDayOff""#.utf8))
        #expect(off == .skip)
    }

    @Test func anOldOneOffAlarmDecodesWithoutAnOriginDay() throws {
        let json = #"{"id":"55555555-5555-5555-5555-555555555555","kind":"nextAlarmChange","slotID":null,"fireDate":800000000}"#
        let alarm = try JSONDecoder().decode(OneOffAlarm.self, from: Data(json.utf8))
        #expect(alarm.originDay == nil)
        #expect(alarm.kind == .nextAlarmChange)
    }

    @Test func anOldVisitDecodesWithoutIsHome() throws {
        let json = #"""
        {"id":"66666666-6666-6666-6666-666666666666","outcomeID":"77777777-7777-7777-7777-777777777777",
         "sessionID":null,"countsOn":800000000,"arrivedAt":800000000,"timeCounts":true}
        """#
        let visit = try JSONDecoder().decode(GymVisit.self, from: Data(json.utf8))
        #expect(!visit.isHome)
    }

    @Test func aSkippedDayKeepsTheComebackLineTrue() {
        let log = makeLog((2, .skipped))
        #expect(WorkoutDoneLine.isComeback(log: log, day: day(3), calendar: calendar))
    }

    @Test func aSkipIsNotAChanceOrACount() {
        let plan = makePlan(days: [.monday, .wednesday, .friday])
        let log = makeLog((0, .skipped))
        // The skipped Monday is gone: 1 counted (no, it doesn't count) and
        // only Wednesday and Friday remain as chances.
        #expect(SkipRules.countedThisWeek(log: log, day: day(1), calendar: calendar) == 0)
        #expect(SkipRules.chancesRemaining(log: log, plan: plan, day: day(1), now: Date(), calendar: calendar) == 2)
    }
}
