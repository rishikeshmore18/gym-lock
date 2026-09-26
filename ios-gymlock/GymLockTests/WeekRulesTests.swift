import Foundation
import Testing
@testable import GymLock

/// `docs/FLOW.md` items 18, 19, the first half of 20 and the 3-day half of 4.
///
/// Same fixtures as `StreakEngineTests`: Berlin, Monday 7 September 2026.
@MainActor
struct WeekRulesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Monday 7 September 2026, 00:00 Berlin.
    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)) ?? Date()
    }

    private func day(_ offset: Int, hour: Int = 7, minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private func plan(_ days: Set<Weekday>) -> MorningPlan {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: days, alarmTime: TimeOfDay(hour: 6, minute: 30))]
        return plan
    }

    private let twoDays: Set<Weekday> = [.monday, .thursday]
    private let threeDays: Set<Weekday> = [.monday, .wednesday, .friday]
    private let fiveDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    private func evaluate(
        _ log: MomentumLog,
        days: Set<Weekday>,
        vault: inout StreakVault,
        now: Date
    ) -> StreakSnapshot {
        StreakEngine.evaluate(
            log: log,
            plan: plan(days),
            schedule: .default,
            vault: &vault,
            now: now,
            calendar: calendar
        )
    }

    /// `weeks` completed weeks before the live one, each with Mon and Thu.
    private func twoDayWeeks(_ weeks: Int, live: [Int] = []) -> MomentumLog {
        var outcomes: [SessionOutcome] = []
        for week in 1...weeks {
            for weekday in [0, 3] {
                outcomes.append(SessionOutcome(date: day(-7 * week + weekday), kind: .showedUp))
            }
        }
        for offset in live {
            outcomes.append(SessionOutcome(date: day(offset), kind: .showedUp))
        }
        return MomentumLog(outcomes: outcomes)
    }

    // MARK: - The goal is saved when the week starts

    @Test func changingThePlanMidWeekNeverChangesTheLiveOrPastWeeks() {
        // An existing user on 2 days: past weeks and the live week are legacy.
        let log = twoDayWeeks(2, live: [0])
        var vault = StreakVault.empty

        let first = evaluate(log, days: twoDays, vault: &vault, now: day(2, hour: 12))
        #expect(first.weeklyGoal == 2)
        #expect(first.weeks == 2)

        // 2 -> 3, 3 -> 5, 5 -> 3, all mid-week.
        for days in [threeDays, fiveDays, threeDays] {
            let snapshot = evaluate(log, days: days, vault: &vault, now: day(3, hour: 12))
            #expect(snapshot.weeklyGoal == 2)
            #expect(snapshot.weeks == 2)
            #expect(vault.savedGoal(forWeekStarting: day(-7, hour: 0), calendar: calendar) == 2)
            #expect(vault.savedGoal(forWeekStarting: day(-14, hour: 0), calendar: calendar) == 2)
        }
    }

    @Test func raisingThePlanNoLongerResetsTheStreak() {
        // The old bug: 2-day weeks re-judged against a 3-day plan broke.
        let log = twoDayWeeks(4)
        var vault = StreakVault.empty
        #expect(evaluate(log, days: twoDays, vault: &vault, now: day(2, hour: 12)).weeks == 4)

        let raised = evaluate(log, days: threeDays, vault: &vault, now: day(2, hour: 12))
        #expect(raised.weeks == 4)
    }

    @Test func aWeekCoveredByTheRuleIsThreeWhateverThePlan() {
        var vault = StreakVault.empty
        vault.threeDayRuleStart = day(-7, hour: 0)
        let snapshot = evaluate(twoDayWeeks(1), days: twoDays, vault: &vault, now: day(2, hour: 12))
        #expect(snapshot.weeklyGoal == 3)
        // Last week had 2 of 3 and no freeze: not kept.
        #expect(snapshot.weeks == 0)
    }

    // MARK: - Backfill

    @Test func backfillGivesTheSameStreakAsTheOldRule() {
        // Old rule for a 2-day plan: min(3, 2) = 2 per week. Five weeks of
        // Mon + Thu were five kept weeks, and still are.
        let log = twoDayWeeks(5, live: [0, 3])
        var vault = StreakVault.empty

        let snapshot = evaluate(log, days: twoDays, vault: &vault, now: day(4, hour: 12))
        #expect(snapshot.weeks == 6) // five past + the live week, kept at 2
        #expect(vault.weekGoals.count == 6)
        #expect(vault.weekGoals.values.allSatisfy { $0 == 2 })
    }

    @Test func backfillUsesThePlanAsItIsNow() {
        let log = twoDayWeeks(3)
        var vault = StreakVault.empty
        _ = evaluate(log, days: fiveDays, vault: &vault, now: day(2, hour: 12))
        // Legacy with 5 planned days is 3, which 2-day weeks never met.
        #expect(vault.weekGoals.values.allSatisfy { $0 == 3 })
    }

    // MARK: - When the rule starts

    @Test func anExistingUserKeepsTheirWeekAndGetsThreeFromNextMonday() {
        let log = twoDayWeeks(1, live: [0, 3])
        var vault = StreakVault.empty

        let thisWeek = evaluate(log, days: twoDays, vault: &vault, now: day(3, hour: 12))
        #expect(thisWeek.weeklyGoal == 2)
        #expect(thisWeek.isThisWeekKept)
        #expect(vault.threeDayRuleStart == day(7, hour: 0))

        let nextWeek = evaluate(log, days: twoDays, vault: &vault, now: day(8, hour: 12))
        #expect(nextWeek.weeklyGoal == 3)
        // The transition week is still judged by 2, so it stays kept.
        #expect(nextWeek.weeks == 2)
    }

    @Test func aNewUserGetsThreeFromTheirFirstWeek() {
        var vault = StreakVault.empty
        let snapshot = evaluate(.empty, days: twoDays, vault: &vault, now: day(2, hour: 12))
        #expect(snapshot.weeklyGoal == 3)
        #expect(vault.threeDayRuleStart == monday)
    }

    @Test func theRuleStartNeverMoves() {
        var vault = StreakVault.empty
        _ = evaluate(twoDayWeeks(1), days: twoDays, vault: &vault, now: day(2, hour: 12))
        let start = vault.threeDayRuleStart

        _ = evaluate(twoDayWeeks(1), days: twoDays, vault: &vault, now: day(30, hour: 12))
        _ = evaluate(.empty, days: threeDays, vault: &vault, now: day(60, hour: 12))
        #expect(vault.threeDayRuleStart == start)
    }

    // MARK: - Nobody plans fewer than 3

    @Test func removingTheThirdGymDayIsRefused() {
        var plan = plan(threeDays)
        let before = plan
        let result = plan.toggleGymDay(.monday, newAlarmTime: TimeOfDay(hour: 6, minute: 30))
        #expect(result.outcome == .belowMinimum)
        #expect(result.effects.isEmpty)
        #expect(plan == before)
    }

    @Test func threeToFourAndFourToThreeAreAllowed() {
        var plan = plan(threeDays)
        let seven = TimeOfDay(hour: 7, minute: 0)

        let added = plan.toggleGymDay(.saturday, newAlarmTime: seven)
        #expect(added.outcome == .updated)
        #expect(plan.gymDays.count == 4)

        let removed = plan.toggleGymDay(.saturday, newAlarmTime: seven)
        #expect(removed.outcome == .updated)
        #expect(plan.gymDays == threeDays)
    }

    @Test func aUserAlreadyBelowThreeCanOnlyAdd() {
        var plan = plan(twoDays)
        let seven = TimeOfDay(hour: 7, minute: 0)
        #expect(plan.toggleGymDay(.monday, newAlarmTime: seven).outcome == .belowMinimum)
        #expect(plan.toggleGymDay(.saturday, newAlarmTime: seven).outcome == .updated)
        #expect(plan.gymDays.count == 3)
    }

    @Test func theMinimumNoteIsTheFlowLine() {
        #expect(StreakPolicy.minimumGymDaysMessage == "3 gym days is the minimum.")
        #expect(!StreakPolicy.minimumGymDaysMessage.contains("\u{2014}"))
    }

    @Test func spreadingNeverGoesBelowThree() {
        #expect(AppStore.spreadTrainingDays(count: 1).count == 3)
        #expect(AppStore.spreadTrainingDays(count: 2).count == 3)
        #expect(AppStore.spreadTrainingDays(count: 3).count == 3)
        #expect(AppStore.spreadTrainingDays(count: 7) == Set(Weekday.allCases))
    }

    @Test func onlyOneOrTwoGymDaysAsksForAnother() {
        #expect(!StreakPolicy.asksToAddGymDay(plannedGymDays: 0))
        #expect(StreakPolicy.asksToAddGymDay(plannedGymDays: 1))
        #expect(StreakPolicy.asksToAddGymDay(plannedGymDays: 2))
        #expect(!StreakPolicy.asksToAddGymDay(plannedGymDays: 3))
    }

    // MARK: - Counting on the alarm's day

    @Test func aVisitAfterMidnightCountsOnTheAlarmsSunday() {
        let sunday = day(-1, hour: 0)
        let visit = SessionOutcome(
            date: day(0, hour: 0, minute: 20),
            kind: .showedUp,
            countsOn: sunday
        )
        #expect(visit.countingDay(calendar: calendar) == sunday)

        let log = MomentumLog(outcomes: [visit])
        let lastWeek = StreakEngine.sessionDays(in: log, weekStarting: day(-7, hour: 0), calendar: calendar)
        let thisWeek = StreakEngine.sessionDays(in: log, weekStarting: monday, calendar: calendar)
        #expect(lastWeek == [sunday])
        #expect(thisWeek.isEmpty)
        #expect(log.outcome(on: sunday, calendar: calendar)?.id == visit.id)
        #expect(log.outcome(on: monday, calendar: calendar) == nil)
    }

    @Test func anOldRecordCountsOnTheDayItWasWritten() {
        let old = SessionOutcome(date: day(0, hour: 0, minute: 20), kind: .showedUp)
        #expect(old.countingDay(calendar: calendar) == monday)
    }

    @Test func anUnplannedDayStillCounts() {
        // Saturday isn't on a Mon/Wed/Fri plan; it counts anyway.
        let log = MomentumLog(outcomes: [
            SessionOutcome(date: day(0), kind: .showedUp),
            SessionOutcome(date: day(2), kind: .showedUp),
            SessionOutcome(date: day(5), kind: .showedUp),
        ])
        var vault = StreakVault.empty
        let snapshot = evaluate(log, days: threeDays, vault: &vault, now: day(5, hour: 12))
        #expect(snapshot.thisWeekSessionDays == 3)
        #expect(snapshot.isThisWeekKept)
    }

    // MARK: - Old data

    @Test func anOldVaultAndLogDecodeAndGiveTheSameStreak() throws {
        var oldVault = StreakVault.empty
        oldVault.freezesAvailable = 1
        oldVault.lastEvaluatedWeekStart = day(-14, hour: 0)
        let log = twoDayWeeks(3, live: [0])

        // Strip the new fields, as a vault and log saved before this update.
        var vaultJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(oldVault)) as? [String: Any]
        )
        vaultJSON.removeValue(forKey: "weekGoals")
        vaultJSON.removeValue(forKey: "threeDayRuleStart")
        let vaultData = try JSONSerialization.data(withJSONObject: vaultJSON)

        var logJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(log)) as? [String: Any]
        )
        let outcomes = try #require(logJSON["outcomes"] as? [[String: Any]])
        logJSON["outcomes"] = outcomes.map { outcome -> [String: Any] in
            var stripped = outcome
            stripped.removeValue(forKey: "countsOn")
            return stripped
        }
        let logData = try JSONSerialization.data(withJSONObject: logJSON)

        var decodedVault = try JSONDecoder().decode(StreakVault.self, from: vaultData)
        let decodedLog = try JSONDecoder().decode(MomentumLog.self, from: logData)

        #expect(decodedVault.weekGoals.isEmpty)
        #expect(decodedVault.threeDayRuleStart == nil)
        #expect(decodedVault.freezesAvailable == 1)
        #expect(decodedLog.outcomes.allSatisfy { $0.countsOn == nil })

        // Same streak as a vault that never lost its fields.
        var reference = oldVault
        let expected = evaluate(log, days: twoDays, vault: &reference, now: day(2, hour: 12))
        let actual = evaluate(decodedLog, days: twoDays, vault: &decodedVault, now: day(2, hour: 12))
        #expect(actual == expected)
        #expect(actual.weeks == 3)
    }

    @Test func newFieldsSurviveARoundTrip() throws {
        var vault = StreakVault.empty
        vault.threeDayRuleStart = monday
        vault.weekGoals = [monday: 3, day(-7, hour: 0): 2]
        let decoded = try JSONDecoder().decode(StreakVault.self, from: JSONEncoder().encode(vault))
        #expect(decoded == vault)

        let outcome = SessionOutcome(date: day(0, hour: 0, minute: 20), kind: .showedUp, countsOn: day(-1, hour: 0))
        let decodedOutcome = try JSONDecoder().decode(SessionOutcome.self, from: JSONEncoder().encode(outcome))
        #expect(decodedOutcome == outcome)
    }
}
