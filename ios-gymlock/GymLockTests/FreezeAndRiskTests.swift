import Foundation
import Testing
@testable import GymLock

/// `docs/FLOW.md`, "Everything to Change" items 21 and 22: freezes on a
/// calendar, a planned freeze pausing the gym alarms, and streak at risk.
@MainActor
struct FreezeAndRiskTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    /// Mon/Wed/Fri, wake 06:30, bed 23:00, gym by 07:05: Wake & Go.
    private func plan(days: Set<Weekday> = [.monday, .wednesday, .friday]) -> MorningPlan {
        var plan = MorningPlan.default
        plan.rhythm = MorningRhythm.default
        plan.rhythm.hasBeenSet = true
        plan.slots = [AlarmSlot(days: days, alarmTime: t(6, 30))]
        plan.hasBeenReviewed = true
        return plan
    }

    private func vault(held: Int, clock: Date) -> StreakVault {
        var vault = StreakVault.empty
        vault.freezesAvailable = held
        vault.freezeClock = clock
        vault.freezeYear = calendar.component(.year, from: clock)
        return vault
    }

    // MARK: - Grant schedule

    @Test func joinedMarch10GetsMay10AndSep10ThenMarch1AndJuly1() {
        let joined = date(2025, 3, 10, 9)
        let first = FreezeCalendar.grants(inYear: 2025, joined: joined, calendar: calendar)
        #expect(first.map(\.date) == [date(2025, 5, 10), date(2025, 9, 10)])
        #expect(first.map(\.ordinal) == [1, 2])
        #expect(first.map(\.line) == ["you earned a freeze.", "you earned your 2nd freeze."])

        let next = FreezeCalendar.grants(inYear: 2026, joined: joined, calendar: calendar)
        #expect(next.map(\.date) == [date(2026, 3, 1), date(2026, 7, 1)])
        #expect(FreezeCalendar.grants(inYear: 2024, joined: joined, calendar: calendar).isEmpty)
    }

    @Test func joinedNovember20GetsNothingThatYearThenMarch1() {
        let joined = date(2025, 11, 20, 9)
        #expect(FreezeCalendar.grants(inYear: 2025, joined: joined, calendar: calendar).isEmpty)
        #expect(FreezeCalendar.grants(inYear: 2026, joined: joined, calendar: calendar).map(\.date)
            == [date(2026, 3, 1), date(2026, 7, 1)])
    }

    @Test func joinedSeptember10GetsNovember10OnlyThenMarch1AndJuly1() {
        let joined = date(2025, 9, 10, 9)
        let first = FreezeCalendar.grants(inYear: 2025, joined: joined, calendar: calendar)
        #expect(first.map(\.date) == [date(2025, 11, 10)])
        #expect(first.map(\.ordinal) == [1])
        #expect(FreezeCalendar.grants(inYear: 2026, joined: joined, calendar: calendar).map(\.date)
            == [date(2026, 3, 1), date(2026, 7, 1)])
    }

    /// FLOW, "Example over a year (joined Mar 10)", month by month, with the
    /// two freezes spent in June and October as the example spends them.
    @Test func theYearExampleComesOutExactly() {
        let joined = date(2025, 3, 10, 9)
        var v = vault(held: 0, clock: joined)

        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 5, 9, 23), calendar: calendar)
        #expect(v.freezesAvailable == 0)
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 5, 10, 12), calendar: calendar)
        #expect(v.freezesAvailable == 1) // May 10

        v.freezesAvailable -= 1 // June sick week
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 9, 10, 12), calendar: calendar)
        #expect(v.freezesAvailable == 1) // Sep 10

        v.freezesAvailable -= 1 // October
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 11, 30), calendar: calendar)
        #expect(v.freezesAvailable == 0) // November: nothing to save the streak

        FreezeCalendar.settle(&v, joined: joined, upTo: date(2026, 1, 1, 12), calendar: calendar)
        #expect(v.freezesAvailable == 0) // Jan 1
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2026, 3, 1, 12), calendar: calendar)
        #expect(v.freezesAvailable == 1) // Mar 1
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2026, 7, 1, 12), calendar: calendar)
        #expect(v.freezesAvailable == 2) // Jul 1
    }

    /// The same year through the streak engine itself: grants land before
    /// the week they can save, and November resets the streak.
    @Test func theYearExampleThroughTheEngine() {
        let joined = date(2025, 3, 10, 9)
        let june = date(2025, 6, 9)
        let october = date(2025, 10, 6)
        let november = date(2025, 11, 10)
        let liveMonday = date(2026, 6, 29)
        let now = date(2026, 7, 2, 12)

        var outcomes: [SessionOutcome] = []
        var monday = date(2025, 3, 10)
        while monday < liveMonday {
            let workoutDays: [Int]
            switch monday {
            case june, november: workoutDays = [0]
            case october: workoutDays = [0, 2]
            default: workoutDays = [0, 2, 4]
            }
            for offset in workoutDays {
                let day = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
                let at = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day
                outcomes.append(SessionOutcome(date: at, kind: .showedUp))
            }
            monday = calendar.date(byAdding: .day, value: 7, to: monday) ?? liveMonday
        }
        for offset in [0, 2] {
            let day = calendar.date(byAdding: .day, value: offset, to: liveMonday) ?? liveMonday
            outcomes.append(SessionOutcome(date: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day, kind: .showedUp))
        }

        var v = vault(held: 0, clock: joined)
        let snapshot = StreakEngine.evaluate(
            log: MomentumLog(outcomes: outcomes),
            plan: plan(),
            schedule: .default,
            vault: &v,
            now: now,
            joined: joined,
            calendar: calendar
        )

        #expect(v.isFrozen(weekStarting: june, calendar: calendar))
        #expect(v.isFrozen(weekStarting: october, calendar: calendar))
        #expect(!v.isFrozen(weekStarting: november, calendar: calendar))
        #expect(v.freezesAvailable == 2) // Mar 1 and Jul 1, 2026

        let restart = date(2025, 11, 17)
        let lastCompleted = date(2026, 6, 22)
        let days = calendar.dateComponents([.day], from: restart, to: lastCompleted).day ?? 0
        #expect(snapshot.weeks == days / 7 + 1)
    }

    @Test func unusedFreezesExpireOnDecember31() {
        let joined = date(2024, 3, 10)
        var v = vault(held: 2, clock: date(2025, 12, 31, 12))
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2026, 1, 1, 0, 1), calendar: calendar)
        #expect(v.freezesAvailable == 0)
        #expect(v.freezeYear == 2026)
    }

    @Test func neverMoreThanTwo() {
        let joined = date(2024, 3, 10)
        var v = vault(held: 2, clock: date(2025, 2, 1))
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 12, 1), calendar: calendar)
        #expect(v.freezesAvailable == 2)
    }

    @Test func aRelaunchNeverGrantsTwice() {
        let joined = date(2025, 3, 10, 9)
        var v = vault(held: 0, clock: joined)
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 5, 10, 12), calendar: calendar)
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 5, 10, 12), calendar: calendar)
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 5, 10, 8), calendar: calendar)
        FreezeCalendar.settle(&v, joined: joined, upTo: date(2025, 5, 10, 18), calendar: calendar)
        #expect(v.freezesAvailable == 1)
    }

    @Test func anExistingUserKeepsTheFreezesTheyHold() {
        var holding = StreakVault.empty
        holding.freezesAvailable = 2
        FreezeCalendar.settle(&holding, joined: date(2024, 1, 5), upTo: date(2026, 9, 27, 12), calendar: calendar)
        #expect(holding.freezesAvailable == 2)
        #expect(holding.freezeClock == date(2026, 9, 27, 12))

        // Nothing from the past is granted on the first run.
        var none = StreakVault.empty
        FreezeCalendar.settle(&none, joined: date(2024, 1, 5), upTo: date(2026, 9, 27, 12), calendar: calendar)
        #expect(none.freezesAvailable == 0)

        // A corrupt count is held to the maximum.
        var tooMany = StreakVault.empty
        tooMany.freezesAvailable = 5
        FreezeCalendar.settle(&tooMany, joined: date(2024, 1, 5), upTo: date(2026, 9, 27, 12), calendar: calendar)
        #expect(tooMany.freezesAvailable == 2)
    }

    @Test func anOldVaultDecodes() throws {
        var old = StreakVault.empty
        old.freezesAvailable = 1
        old.lastEvaluatedWeekStart = date(2026, 9, 14)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "freezeClock")
        json.removeValue(forKey: "freezeYear")
        json.removeValue(forKey: "weekGoals")
        json.removeValue(forKey: "threeDayRuleStart")
        let decoded = try JSONDecoder().decode(StreakVault.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.freezesAvailable == 1)
        #expect(decoded.freezeClock == nil)
        #expect(decoded.freezeYear == nil)

        // A vault written without the old 4-week counter decodes too.
        json.removeValue(forKey: "kept4Counter")
        let bare = try JSONDecoder().decode(StreakVault.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(bare.kept4Counter == 0)

        // And the new fields round-trip.
        var fresh = StreakVault.empty
        fresh.freezeClock = date(2026, 9, 27)
        fresh.freezeYear = 2026
        let round = try JSONDecoder().decode(StreakVault.self, from: JSONEncoder().encode(fresh))
        #expect(round == fresh)
    }

    // MARK: - Notice time and grant notifications

    @Test func grantNoticesAreScheduledAt10OnTheGrantDate() {
        let joined = date(2025, 3, 10, 9)
        let notices = FreezeNotice.upcoming(joined: joined, plan: plan(), now: date(2025, 4, 1), calendar: calendar)
        #expect(notices.first?.fireDate == date(2025, 5, 10, 10))
        #expect(notices.first?.body == "you earned a freeze.")
        #expect(notices.dropFirst().first?.fireDate == date(2025, 9, 10, 10))
        #expect(notices.dropFirst().first?.body == "you earned your 2nd freeze.")
        #expect(notices.first?.id == "gymlock.freeze.2025-05-10")
        // Next year's are scheduled ahead too.
        #expect(notices.contains { $0.fireDate == date(2026, 3, 1, 10) })
        // Nothing already past.
        let later = FreezeNotice.upcoming(joined: joined, plan: plan(), now: date(2025, 5, 10, 11), calendar: calendar)
        #expect(later.first?.fireDate == date(2025, 9, 10, 10))
    }

    @Test func tenInsideTheSleepWindowMovesTo30MinutesAfterWake() {
        var late = plan()
        late.rhythm.bedtime = t(3)
        late.rhythm.wakeTime = t(11)
        #expect(NoticeTime.fireDate(on: date(2025, 5, 10), plan: late, calendar: calendar) == date(2025, 5, 10, 11, 30))

        var afterMidnight = plan()
        afterMidnight.rhythm.bedtime = t(1)
        afterMidnight.rhythm.wakeTime = t(10, 15)
        #expect(NoticeTime.fireDate(on: date(2025, 5, 10), plan: afterMidnight, calendar: calendar) == date(2025, 5, 10, 10, 45))

        #expect(NoticeTime.fireDate(on: date(2025, 5, 10), plan: plan(), calendar: calendar) == date(2025, 5, 10, 10))

        let joined = date(2025, 3, 10, 9)
        let notices = FreezeNotice.upcoming(joined: joined, plan: late, now: date(2025, 4, 1), calendar: calendar)
        #expect(notices.first?.fireDate == date(2025, 5, 10, 11, 30))
    }

    // MARK: - A frozen week pauses the gym alarms

    @Test func aFrozenWeekRemovesGymAlarmsAndReschedulesAndRestoresThemOnMonday() {
        var p = plan()
        let slotID = p.slots[0].id
        let now = date(2026, 9, 29, 12) // Tuesday
        let monday = date(2026, 10, 5)
        // A reschedule on Thursday this week, and one next Saturday.
        p.oneOffAlarms = [
            OneOffAlarm(kind: .reschedule, slotID: slotID, fireDate: date(2026, 10, 1, 7), originDay: date(2026, 9, 28)),
            OneOffAlarm(kind: .reschedule, slotID: slotID, fireDate: date(2026, 10, 10, 9), originDay: date(2026, 10, 9)),
        ]

        let normal = AlarmPlan.alarms(for: p, now: now, calendar: calendar)
        #expect(normal.contains { $0.kind.locks && $0.fireDate == nil })

        let paused = AlarmPlan.alarms(for: p, now: now, calendar: calendar, pausedUntil: monday)
        // Nothing locks before Monday: no weekly gym alarm, no reschedule.
        #expect(!paused.contains { $0.kind.locks && ($0.fireDate.map { $0 < monday } ?? true) })
        // Plain wake alarms keep going, and Thursday gets its back.
        let wake = paused.first { $0.kind == .plainWake && $0.fireDate == nil }
        #expect(wake?.weekdays.contains(.thursday) == true)
        #expect(wake?.weekdays.contains(.tuesday) == true)
        // Next week's gym days come back as dated alarms, plus next week's reschedule.
        let back = paused.filter { $0.kind.locks }.compactMap(\.fireDate).sorted()
        #expect(back == [date(2026, 10, 5, 6, 30), date(2026, 10, 7, 6, 30), date(2026, 10, 9, 6, 30), date(2026, 10, 10, 9)])
        // A Monday alarm starts a normal morning on the slot.
        let mondayAlarm = paused.first { $0.fireDate == date(2026, 10, 5, 6, 30) }
        #expect(p.slot(forAlarmID: mondayAlarm?.id)?.id == slotID)
        #expect(p.oneOffSlotIDs[mondayAlarm?.id ?? UUID()] == slotID)

        // The night lock is not an alarm and is untouched by the pause.
        #expect(p.nextNightLockStart(after: now, calendar: calendar) != nil)

        // On Monday the weekly alarms are back.
        let afterward = AlarmPlan.alarms(for: p, now: date(2026, 10, 5, 0, 1), calendar: calendar)
        #expect(afterward.contains { $0.kind == .gym && $0.fireDate == nil && $0.weekdays == [.monday, .wednesday, .friday] })
    }

    @Test func aPauseAlreadyOverChangesNothing() {
        let p = plan()
        let now = date(2026, 10, 5, 8)
        #expect(AlarmPlan.alarms(for: p, now: now, calendar: calendar, pausedUntil: date(2026, 10, 5))
            == AlarmPlan.alarms(for: p, now: now, calendar: calendar))
    }

    // MARK: - Streak at risk (week of Mon 21 Sep 2026)

    private func workouts(_ days: [Int], homeOn extra: [Date] = []) -> MomentumLog {
        var outcomes = days.map { offset -> SessionOutcome in
            let at = date(2026, 9, 21 + offset, 7)
            return SessionOutcome(date: at, kind: .showedUp, countsOn: calendar.startOfDay(for: at), proof: .photo)
        }
        outcomes += extra.map { SessionOutcome(date: $0, kind: .homeWorkout, minutes: 20, countsOn: calendar.startOfDay(for: $0), proof: .photo) }
        return MomentumLog(outcomes: outcomes)
    }

    private func banner(
        _ log: MomentumLog,
        plan p: MorningPlan? = nil,
        at now: Date,
        streak: Int = 6,
        frozen: Bool = false,
        freezes: Int = 0,
        sawMakeUp: Bool = false
    ) -> StreakRiskBanner? {
        StreakRisk.banner(
            log: log,
            plan: p ?? plan(),
            streakWeeks: streak,
            weeklyGoal: 3,
            isWeekFrozen: frozen,
            freezesHeld: freezes,
            homeWorkoutsUsed: HomeWorkoutRules.usedThisMonth(log: log, now: now, calendar: calendar),
            sawMakeUpToday: sawMakeUp,
            todayInProgress: false,
            now: now,
            calendar: calendar
        )
    }

    private func notice(
        _ log: MomentumLog,
        plan p: MorningPlan? = nil,
        at now: Date,
        streak: Int = 6,
        frozen: Bool = false,
        freezes: Int = 0,
        sawMakeUp: Bool = false,
        sentToday: Bool = false
    ) -> StreakRisk.Notice? {
        StreakRisk.nextNotice(
            log: log,
            plan: p ?? plan(),
            streakWeeks: streak,
            weeklyGoal: 3,
            isWeekFrozen: frozen,
            freezesHeld: freezes,
            sawMakeUpToday: sawMakeUp,
            alreadySentToday: sentToday,
            todayInProgress: false,
            now: now,
            calendar: calendar
        )
    }

    @Test func enoughChancesStaysQuiet() {
        // Tuesday, Monday done: Wed and Fri left for the 2 needed.
        let log = workouts([0])
        let tuesday = date(2026, 9, 22, 9)
        #expect(banner(log, at: tuesday) == nil)
        // Nothing today. The prediction only lands on Wednesday 10:00, for
        // the case Wednesday's alarm passes with nothing counted; a counted
        // workout recomputes and withdraws it.
        let n = notice(log, at: tuesday)
        #expect(n?.fireDate == date(2026, 9, 23, 10))

        // With two counted, one needed and Wed + Fri ahead: quiet until
        // Friday's alarm has passed.
        #expect(notice(workouts([0, 1]), at: tuesday)?.fireDate == date(2026, 9, 25, 10))
    }

    @Test func todaysAlarmCountsUntilItRings() {
        let log = workouts([0])
        // Wednesday 05:00: Wed and Fri still ahead.
        #expect(banner(log, at: date(2026, 9, 23, 5)) == nil)
        // Wednesday 09:00, nothing counted today: only Friday left.
        #expect(banner(log, at: date(2026, 9, 23, 9))?.line == "2 workouts keep your 6-week streak.")
    }

    @Test func notEnoughShowsTheBannerAndSchedulesTheNotification() {
        let log = workouts([0])
        let thursday = date(2026, 9, 24, 8)
        let b = banner(log, at: thursday, freezes: 1)
        #expect(b?.line == "2 workouts keep your 6-week streak.")
        #expect(b?.freezeLine == "otherwise a freeze gets used.")
        #expect(b?.showsHomeWorkout == true)
        #expect(b?.homeWorkoutLabel == "home workout · 3 left this month")

        let n = notice(log, at: thursday, freezes: 1)
        #expect(n?.fireDate == date(2026, 9, 24, 10))
        #expect(n?.body == "2 workouts keep your 6-week streak. otherwise a freeze gets used.")

        // One workout short: the singular.
        let one = banner(workouts([0, 2]), at: date(2026, 9, 26, 9))
        #expect(one?.line == "1 workout keeps your 6-week streak.")
        #expect(one?.freezeLine == nil)
    }

    @Test func sundayWording() {
        let b = banner(workouts([0, 2]), at: date(2026, 9, 27, 9), streak: 6)
        #expect(b?.line == "last day. 1 workout keeps your 6-week streak.")
        let n = notice(workouts([0, 2]), at: date(2026, 9, 27, 8))
        #expect(n?.body == "last day. 1 workout keeps your 6-week streak.")
    }

    @Test func homeWorkoutsUsedUpShowsOnlyReschedule() {
        let used = [date(2026, 9, 2, 18), date(2026, 9, 9, 18), date(2026, 9, 16, 18)]
        let b = banner(workouts([0], homeOn: used), at: date(2026, 9, 24, 9))
        #expect(b != nil)
        #expect(b?.showsHomeWorkout == false)

        let two = banner(workouts([0], homeOn: [used[0]]), at: date(2026, 9, 24, 9))
        #expect(two?.homeWorkoutLabel == "home workout · 2 left this month")
    }

    @Test func aFrozenWeekStaysQuiet() {
        let log = workouts([0])
        #expect(banner(log, at: date(2026, 9, 24, 9), frozen: true) == nil)
        #expect(notice(log, at: date(2026, 9, 24, 8), frozen: true) == nil)
    }

    @Test func noStreakStaysQuiet() {
        let log = workouts([0])
        #expect(banner(log, at: date(2026, 9, 24, 9), streak: 0) == nil)
        #expect(notice(log, at: date(2026, 9, 24, 8), streak: 0) == nil)
    }

    @Test func sawMakeItUpTodayMeansNoNotificationToday() {
        let log = workouts([0])
        let thursday = date(2026, 9, 24, 8)
        #expect(banner(log, at: thursday, sawMakeUp: true) == nil)
        let n = notice(log, at: thursday, sawMakeUp: true)
        #expect(n.map { !calendar.isDate($0.fireDate, inSameDayAs: thursday) } ?? true)
    }

    @Test func atMostOneADay() {
        let log = workouts([0])
        let thursdayNoon = date(2026, 9, 24, 12)
        let n = notice(log, at: thursdayNoon, sentToday: true)
        #expect(n?.fireDate == date(2026, 9, 25, 10))
    }

    @Test func itStopsOnceTheWeekIsSafe() {
        var p = plan()
        let thursday = date(2026, 9, 24, 8)
        #expect(notice(workouts([0]), plan: p, at: thursday) != nil)

        // A reschedule on Saturday gives Friday + Saturday for the 2 needed.
        p.oneOffAlarms = [OneOffAlarm(kind: .reschedule, slotID: p.slots[0].id, fireDate: date(2026, 9, 26, 9), originDay: date(2026, 9, 23))]
        #expect(banner(workouts([0]), plan: p, at: thursday) == nil)
        // Not today any more; only after Friday's alarm, if Friday is missed.
        #expect(notice(workouts([0]), plan: p, at: thursday)?.fireDate == date(2026, 9, 25, 10))
        // Friday counted as well: nothing today; only after Saturday's
        // reschedule, if that is missed.
        #expect(notice(workouts([0, 4]), plan: p, at: date(2026, 9, 25, 12))?.fireDate == date(2026, 9, 26, 10))
        // Saturday counted too: the week is kept and nothing is scheduled.
        #expect(notice(workouts([0, 4, 5]), plan: p, at: date(2026, 9, 26, 12)) == nil)

        // Or the week is simply kept.
        #expect(notice(workouts([0, 1, 3]), at: thursday) == nil)
    }

    // MARK: - Notification routes

    @Test func atRiskAndFreezeNotificationsOpenHomeAndNeverStartASession() throws {
        let risk = NotificationRoute(identifier: NotificationRoute.ID.streakAtRisk, categoryIdentifier: "")
        let freeze = NotificationRoute(identifier: "gymlock.freeze.2026-03-01", categoryIdentifier: "")
        #expect(risk == .streakAtRisk)
        #expect(freeze == .freezeEarned)
        #expect(risk.handoff(forAction: "com.apple.UNNotificationDefaultActionIdentifier", at: Date()) == nil)
        #expect(freeze.handoff(forAction: "com.apple.UNNotificationDefaultActionIdentifier", at: Date()) == nil)

        for route in [risk, freeze] {
            let decoded = try JSONDecoder().decode(NotificationRoute.self, from: JSONEncoder().encode(route))
            #expect(decoded == route)
        }
    }

    @Test func noNewCopyUsesAnEmDash() {
        let lines = [
            FreezeCalendar.earnedLine, FreezeCalendar.secondEarnedLine,
            StreakRiskBanner.rescheduleLabel, StreakRiskBanner.freezeLineText,
            StreakRisk.line(needed: 1, streakWeeks: 6, isSunday: true),
        ]
        #expect(lines.allSatisfy { !$0.contains("\u{2014}") })
    }
}
