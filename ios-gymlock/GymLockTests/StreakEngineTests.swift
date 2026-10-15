import Foundation
import Testing
@testable import GymLock

/// The streak rules, pinned.
///
/// Every test builds its own ledger against a fixed Monday and a fixed
/// timezone, so a week boundary means exactly one thing regardless of where
/// the test machine sits.
@MainActor
struct StreakEngineTests {
    /// Berlin: a non-UTC zone with daylight saving, so Sunday 23:59 and Monday
    /// 00:00 local are genuinely different weeks and a UTC-based calculation
    /// would get them wrong.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Monday 7 September 2026, 00:00 Berlin.
    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 0, minute: 0)) ?? Date()
    }

    private func day(_ offset: Int, hour: Int = 7) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    /// A three-day plan.
    private var plan: MorningPlan {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: [.monday, .wednesday, .friday], alarmTime: TimeOfDay(hour: 6, minute: 30))]
        return plan
    }

    /// Explicit days: `spreadTrainingDays` now never returns fewer than 3.
    private func planWith(days: Int) -> MorningPlan {
        var plan = MorningPlan.default
        let picked = Set(Weekday.allCases.prefix(days))
        plan.slots = [AlarmSlot(days: picked, alarmTime: TimeOfDay(hour: 6, minute: 30))]
        return plan
    }

    /// `weeksAgo` kept weeks, each with three showed-up days.
    private func log(keptWeeksBefore weeks: Int, extra: [(Int, SessionOutcomeKind)] = []) -> MomentumLog {
        var outcomes: [SessionOutcome] = []
        for week in 1...max(weeks, 1) where weeks > 0 {
            for weekday in [0, 2, 4] {
                outcomes.append(SessionOutcome(date: day(-7 * week + weekday), kind: .showedUp))
            }
        }
        for (offset, kind) in extra {
            outcomes.append(SessionOutcome(date: day(offset), kind: kind))
        }
        return MomentumLog(outcomes: outcomes)
    }

    private func evaluate(
        _ log: MomentumLog,
        plan: MorningPlan? = nil,
        vault: inout StreakVault,
        now: Date? = nil
    ) -> StreakSnapshot {
        StreakEngine.evaluate(
            log: log,
            plan: plan ?? self.plan,
            schedule: .default,
            vault: &vault,
            now: now ?? day(2, hour: 12),
            calendar: calendar
        )
    }

    // MARK: Kept / unkept / live

    @Test("Kept weeks count; the live week only once it is kept")
    func keptAndLive() {
        var vault = StreakVault.empty
        // Two kept weeks, then Monday and Tuesday of the live week.
        let ledger = log(keptWeeksBefore: 2, extra: [(0, .showedUp), (1, .homeWorkout)])
        let snapshot = evaluate(ledger, vault: &vault)

        #expect(snapshot.weeks == 2)
        #expect(snapshot.thisWeekSessionDays == 2)
        #expect(snapshot.isThisWeekKept == false)

        var vault2 = StreakVault.empty
        let kept = log(keptWeeksBefore: 2, extra: [(0, .showedUp), (1, .homeWorkout), (2, .showedUp)])
        #expect(evaluate(kept, vault: &vault2).weeks == 3)
    }

    @Test("Several outcomes on one day count once")
    func oneDayCountsOnce() {
        var vault = StreakVault.empty
        let ledger = MomentumLog(outcomes: [
            SessionOutcome(date: day(0, hour: 7), kind: .showedUp),
            SessionOutcome(date: day(0, hour: 18), kind: .homeWorkout),
            SessionOutcome(date: day(0, hour: 20), kind: .showedUp),
        ])
        #expect(evaluate(ledger, vault: &vault).thisWeekSessionDays == 1)
    }

    @Test("An unkept completed week with no freeze breaks the streak")
    func unkeptBreaks() {
        var vault = StreakVault.empty
        vault.lastEvaluatedWeekStart = day(-14) // Not migrating.
        // Kept week two weeks ago, one session last week, live week kept.
        var outcomes: [SessionOutcome] = []
        for weekday in [0, 2, 4] { outcomes.append(SessionOutcome(date: day(-14 + weekday), kind: .showedUp)) }
        outcomes.append(SessionOutcome(date: day(-7), kind: .showedUp))
        for weekday in [0, 1, 2] { outcomes.append(SessionOutcome(date: day(weekday), kind: .showedUp)) }

        let snapshot = evaluate(MomentumLog(outcomes: outcomes), vault: &vault)
        #expect(snapshot.weeks == 1)
    }

    @Test("The live week can never break the streak")
    func liveWeekNeverBreaks() {
        var vault = StreakVault.empty
        let ledger = log(keptWeeksBefore: 3, extra: [(0, .missed)])
        #expect(evaluate(ledger, vault: &vault).weeks == 3)
    }

    // MARK: The weekly goal is the plan (FLOW, item 19a)

    /// Counted days in the live week, Monday onward, one per kind given.
    private func liveWeek(_ kinds: [SessionOutcomeKind]) -> MomentumLog {
        MomentumLog(outcomes: kinds.enumerated().map { offset, kind in
            SessionOutcome(date: day(offset), kind: kind)
        })
    }

    /// A vault already past the 3-day minimum's start, so every week is
    /// judged by the plan rule rather than backfilled by the legacy one.
    private var planRuleVault: StreakVault {
        var vault = StreakVault.empty
        vault.threeDayRuleStart = day(-700, hour: 0)
        return vault
    }

    @Test("The weekly goal is the number of planned days, floored at 3")
    func goalIsThePlan() {
        #expect(StreakPolicy.weeklyGoal(plannedDays: 3) == 3)
        #expect(StreakPolicy.weeklyGoal(plannedDays: 4) == 4)
        #expect(StreakPolicy.weeklyGoal(plannedDays: 5) == 5)
        #expect(StreakPolicy.weeklyGoal(plannedDays: 7) == 7)
        // The floor is validation, not a goal: a legacy 2-day plan needs 3.
        #expect(StreakPolicy.weeklyGoal(plannedDays: 2) == 3)
        #expect(StreakPolicy.weeklyGoal(plannedDays: 0) == 3)
    }

    @Test("A 3-day plan is kept at 3, not at 2")
    func threeDayPlan() {
        var vault = planRuleVault
        let two = evaluate(liveWeek([.showedUp, .showedUp]), plan: planWith(days: 3), vault: &vault, now: day(6, hour: 12))
        #expect(two.weeklyGoal == 3)
        #expect(two.thisWeekSessionDays == 2)
        #expect(!two.isThisWeekKept)

        let three = evaluate(liveWeek([.showedUp, .showedUp, .showedUp]), plan: planWith(days: 3), vault: &vault, now: day(6, hour: 12))
        #expect(three.isThisWeekKept)
        #expect(three.weeks == 1)
    }

    @Test("A 4-day plan is not kept at 3; the 4th counted day keeps it")
    func fourDayPlan() {
        var vault = planRuleVault
        let three = evaluate(liveWeek([.showedUp, .showedUp, .showedUp]), plan: planWith(days: 4), vault: &vault, now: day(6, hour: 12))
        #expect(three.weeklyGoal == 4)
        #expect(three.thisWeekSessionDays == 3)
        #expect(!three.isThisWeekKept)
        #expect(three.weeks == 0)

        let four = evaluate(liveWeek([.showedUp, .showedUp, .showedUp, .showedUp]), plan: planWith(days: 4), vault: &vault, now: day(6, hour: 12))
        #expect(four.isThisWeekKept)
        #expect(four.weeks == 1)
    }

    @Test("A 5-day plan needs 5")
    func fiveDayPlan() {
        var vault = planRuleVault
        let four = evaluate(liveWeek(Array(repeating: .showedUp, count: 4)), plan: planWith(days: 5), vault: &vault, now: day(6, hour: 12))
        #expect(four.weeklyGoal == 5)
        #expect(!four.isThisWeekKept)

        let five = evaluate(liveWeek(Array(repeating: .showedUp, count: 5)), plan: planWith(days: 5), vault: &vault, now: day(6, hour: 12))
        #expect(five.isThisWeekKept)
    }

    @Test("A 7-day plan needs 7")
    func sevenDayPlan() {
        var vault = planRuleVault
        let six = evaluate(liveWeek(Array(repeating: .showedUp, count: 6)), plan: planWith(days: 7), vault: &vault, now: day(6, hour: 12))
        #expect(six.weeklyGoal == 7)
        #expect(!six.isThisWeekKept)

        let seven = evaluate(liveWeek(Array(repeating: .showedUp, count: 7)), plan: planWith(days: 7), vault: &vault, now: day(6, hour: 12))
        #expect(seven.isThisWeekKept)
        #expect(seven.weeks == 1)
    }

    @Test("Home workouts count toward the plan's goal, each day once")
    func homeWorkoutsCountTowardTheGoal() {
        var vault = planRuleVault
        // 4-day plan: one gym workout and two verified home workouts.
        let three = evaluate(liveWeek([.showedUp, .homeWorkout, .homeWorkout]), plan: planWith(days: 4), vault: &vault, now: day(6, hour: 12))
        #expect(three.thisWeekSessionDays == 3)
        #expect(three.weeklyGoal == 4)
        #expect(!three.isThisWeekKept)

        let four = evaluate(liveWeek([.showedUp, .homeWorkout, .homeWorkout, .homeWorkout]), plan: planWith(days: 4), vault: &vault, now: day(6, hour: 12))
        #expect(four.thisWeekSessionDays == 4)
        #expect(four.isThisWeekKept)
    }

    @Test("A gym arrival without a finished workout does not count")
    func unprovenArrivalDoesNotCount() {
        var vault = planRuleVault
        let ledger = MomentumLog(outcomes: [
            SessionOutcome(date: day(0), kind: .showedUp),
            SessionOutcome(date: day(1), kind: .showedUp),
            SessionOutcome(date: day(2), kind: .showedUp, proof: .unproven),
        ])
        let snapshot = evaluate(ledger, plan: planWith(days: 3), vault: &vault, now: day(6, hour: 12))
        #expect(snapshot.thisWeekSessionDays == 2)
        #expect(!snapshot.isThisWeekKept)
    }

    @Test("Weeks before the 3-day minimum keep the legacy goal, clamped to the plan")
    func legacyGoalClamping() {
        #expect(StreakPolicy.legacyWeeklyGoal(plannedDays: 2) == 2)
        #expect(StreakPolicy.legacyWeeklyGoal(plannedDays: 5) == 3)
        #expect(StreakPolicy.legacyWeeklyGoal(plannedDays: 0) == 1)

        // An existing user: history exists, so the live week keeps its old
        // goal and the plan rule starts next Monday.
        var vault = StreakVault.empty
        let twoDays = MomentumLog(outcomes: [
            SessionOutcome(date: day(-7), kind: .showedUp),
            SessionOutcome(date: day(-4), kind: .showedUp),
        ])
        let snapshot = evaluate(twoDays, plan: planWith(days: 2), vault: &vault)
        #expect(snapshot.weeklyGoal == 2)
        #expect(snapshot.weeks == 1)
    }

    // MARK: Freezes

    @Test("Freezes are spent oldest-first across a gap")
    func freezeOrderAcrossGap() {
        var vault = StreakVault.empty
        vault.freezesAvailable = 2
        // Kept weeks span -49...-28 and were already ruled on; the empty
        // weeks -21, -14 and -7 are new.
        vault.lastEvaluatedWeekStart = day(-28)

        var outcomes: [SessionOutcome] = []
        for week in 4...7 {
            for weekday in [0, 2, 4] {
                outcomes.append(SessionOutcome(date: day(-7 * week + weekday), kind: .showedUp))
            }
        }

        let snapshot = evaluate(MomentumLog(outcomes: outcomes), vault: &vault)

        #expect(vault.freezesAvailable == 0)
        #expect(vault.isFrozen(weekStarting: day(-21), calendar: calendar))
        #expect(vault.isFrozen(weekStarting: day(-14), calendar: calendar))
        #expect(!vault.isFrozen(weekStarting: day(-7), calendar: calendar))
        // Two frozen weeks neither count nor break; the third breaks.
        #expect(snapshot.weeks == 0)
    }

    @Test("A frozen week neither counts nor breaks")
    func frozenWeekIsNeutral() {
        var vault = StreakVault.empty
        vault.freezesAvailable = 1
        vault.lastEvaluatedWeekStart = day(-14)

        // Kept two weeks ago, nothing last week, kept live week.
        var outcomes: [SessionOutcome] = []
        for weekday in [0, 2, 4] { outcomes.append(SessionOutcome(date: day(-14 + weekday), kind: .showedUp)) }
        for weekday in [0, 1, 2] { outcomes.append(SessionOutcome(date: day(weekday), kind: .showedUp)) }

        let snapshot = evaluate(MomentumLog(outcomes: outcomes), vault: &vault)
        #expect(snapshot.weeks == 2)
        #expect(snapshot.lastCompletedWeekWasFrozen)
        #expect(vault.freezesAvailable == 0)
    }

    @Test("Kept weeks no longer earn freezes (FLOW, Flow 5: the calendar does)")
    func keptWeeksEarnNothing() {
        var vault = StreakVault.empty
        vault.lastEvaluatedWeekStart = day(-63) // Not migrating; everything after is new.

        var outcomes: [SessionOutcome] = []
        for week in 1...8 {
            for weekday in [0, 2, 4] {
                outcomes.append(SessionOutcome(date: day(-7 * week + weekday), kind: .showedUp))
            }
        }
        let snapshot = evaluate(MomentumLog(outcomes: outcomes), vault: &vault)
        #expect(snapshot.weeks == 8)
        #expect(vault.freezesAvailable == 0)
    }

    @Test("A pre-armed live week that is kept refunds the freeze")
    func preArmRefund() {
        var vault = StreakVault.empty
        vault.freezesAvailable = 0
        vault.preArmedWeekStart = monday
        vault.lastEvaluatedWeekStart = day(-7)

        let unkept = log(keptWeeksBefore: 1, extra: [(0, .showedUp)])
        let before = evaluate(unkept, vault: &vault)
        #expect(before.isLiveWeekPreArmed)
        #expect(vault.freezesAvailable == 0)

        let kept = log(keptWeeksBefore: 1, extra: [(0, .showedUp), (1, .showedUp), (2, .showedUp)])
        let after = evaluate(kept, vault: &vault)
        #expect(after.isLiveWeekPreArmed == false)
        #expect(vault.freezesAvailable == 1)
        #expect(after.weeks == 2)
    }

    @Test("A pre-armed week that ends unkept becomes a frozen week")
    func preArmProtects() {
        var vault = StreakVault.empty
        vault.preArmedWeekStart = day(-7)
        vault.lastEvaluatedWeekStart = day(-14)

        // Kept two weeks ago, one session last week (armed), live week kept.
        var outcomes: [SessionOutcome] = []
        for weekday in [0, 2, 4] { outcomes.append(SessionOutcome(date: day(-14 + weekday), kind: .showedUp)) }
        outcomes.append(SessionOutcome(date: day(-7), kind: .showedUp))
        for weekday in [0, 1, 2] { outcomes.append(SessionOutcome(date: day(weekday), kind: .showedUp)) }

        let snapshot = evaluate(MomentumLog(outcomes: outcomes), vault: &vault)
        #expect(vault.isFrozen(weekStarting: day(-7), calendar: calendar))
        #expect(vault.preArmedWeekStart == nil)
        #expect(snapshot.weeks == 2)
    }

    // MARK: Migration

    @Test("First evaluation keeps the freezes held and grants nothing from history")
    func migrationKeepsHeld() {
        var four = StreakVault.empty
        _ = evaluate(log(keptWeeksBefore: 4), vault: &four)
        #expect(four.freezesAvailable == 0)
        #expect(four.needsMigration == false)

        var holding = StreakVault.empty
        holding.freezesAvailable = 2
        _ = evaluate(log(keptWeeksBefore: 8), vault: &holding)
        #expect(holding.freezesAvailable == 2)
    }

    // MARK: Boundaries

    @Test("Sunday 23:59 and Monday 00:00 fall in different weeks")
    func weekBoundary() {
        let sundayLate = calendar.date(byAdding: .minute, value: -1, to: monday) ?? monday
        let ledger = MomentumLog(outcomes: [
            SessionOutcome(date: sundayLate, kind: .showedUp),
            SessionOutcome(date: monday, kind: .showedUp),
        ])

        let lastWeek = StreakEngine.weekStart(containing: sundayLate, weekCalendar: ProgressAnalytics.displayCalendar(calendar))
        let thisWeek = StreakEngine.weekStart(containing: monday, weekCalendar: ProgressAnalytics.displayCalendar(calendar))
        #expect(lastWeek != thisWeek)

        let previous = StreakEngine.sessionDays(in: ledger, weekStarting: lastWeek ?? monday, calendar: calendar)
        let current = StreakEngine.sessionDays(in: ledger, weekStarting: monday, calendar: calendar)
        #expect(previous.count == 1)
        #expect(current.count == 1)
    }

    @Test("A week containing the DST change is still one week of seven days")
    func daylightSavingWeek() {
        // Clocks go back in Berlin on 25 October 2026.
        let dstMonday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)) ?? Date()
        var outcomes: [SessionOutcome] = []
        for offset in [0, 3, 6] {
            let date = calendar.date(byAdding: .day, value: offset, to: dstMonday) ?? dstMonday
            outcomes.append(SessionOutcome(date: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: date) ?? date, kind: .showedUp))
        }
        var vault = StreakVault.empty
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: dstMonday) ?? dstMonday
        let snapshot = StreakEngine.evaluate(
            log: MomentumLog(outcomes: outcomes),
            plan: plan,
            schedule: .default,
            vault: &vault,
            now: calendar.date(byAdding: .hour, value: 12, to: nextMonday) ?? nextMonday,
            calendar: calendar
        )
        #expect(snapshot.weeks == 1)
    }
}
