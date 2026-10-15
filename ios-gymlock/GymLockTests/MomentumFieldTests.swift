import Foundation
import Testing
@testable import GymLock

/// The Momentum card counts what the streak counts (FLOW, item 19a): distinct
/// workout days, gym or home, against the goal the week was saved with.
///
/// Same fixtures as `StreakEngineTests`: Berlin, Monday 7 September 2026.
@MainActor
struct MomentumFieldTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)) ?? Date()
    }

    private func day(_ offset: Int, hour: Int = 7) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    private func plan(_ days: Set<Weekday>) -> MorningPlan {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: days, alarmTime: TimeOfDay(hour: 6, minute: 30))]
        return plan
    }

    private let threeDays: Set<Weekday> = [.monday, .wednesday, .friday]
    private let fourDays: Set<Weekday> = [.monday, .tuesday, .thursday, .friday]

    /// One outcome per entry, on consecutive days from Monday.
    private func log(_ kinds: [SessionOutcomeKind], proof: WorkoutProof? = nil) -> MomentumLog {
        MomentumLog(outcomes: kinds.enumerated().map { offset, kind in
            SessionOutcome(date: day(offset), kind: kind, proof: proof)
        })
    }

    /// The card and the streak, built from the same ledger and plan.
    private func build(
        _ log: MomentumLog,
        days: Set<Weekday>,
        now: Date? = nil
    ) -> (field: MomentumField, streak: StreakSnapshot) {
        var vault = StreakVault.empty
        vault.threeDayRuleStart = day(-700, hour: 0)
        vault.goalRule = StreakPolicy.currentGoalRule
        let moment = now ?? day(6, hour: 12)
        let streak = StreakEngine.evaluate(
            log: log,
            plan: plan(days),
            schedule: .default,
            vault: &vault,
            now: moment,
            calendar: calendar
        )
        let field = MomentumField.build(
            log: log,
            plan: plan(days),
            schedule: .default,
            weeklyGoal: streak.weeklyGoal,
            now: moment,
            calendar: calendar
        )
        return (field, streak)
    }

    @Test("3-day plan, 1 gym + 2 home: 3/3, three stages, +2 at home")
    func threeDayPlanWithHomeWorkouts() {
        let (field, streak) = build(log([.showedUp, .homeWorkout, .homeWorkout]), days: threeDays)
        #expect(field.countedCount == 3)
        #expect(field.verifiedCount == 1)
        #expect(field.preservedCount == 2)
        #expect(field.targetCount == 3)
        #expect(field.summaryValue == "3/3")
        #expect(field.completedStages == 3)
        #expect(field.homeNote == "+2 at home")
        #expect(streak.isThisWeekKept)
    }

    @Test("4-day plan, 3 counted: 3/4, exactly three of four stages")
    func fourDayPlanThreeCounted() {
        let (field, streak) = build(log([.showedUp, .homeWorkout, .homeWorkout]), days: fourDays)
        #expect(field.summaryValue == "3/4")
        #expect(field.targetCount == 4)
        #expect(field.completedStages == 3)
        #expect(field.homeNote == "+2 at home")
        #expect(!streak.isThisWeekKept)

        let (kept, keptStreak) = build(log([.showedUp, .homeWorkout, .homeWorkout, .showedUp]), days: fourDays)
        #expect(kept.summaryValue == "4/4")
        #expect(kept.completedStages == 4)
        #expect(keptStreak.isThisWeekKept)
    }

    @Test("The card's count is the streak's count, always")
    func cardAndStreakAgree() {
        let ledgers: [MomentumLog] = [
            .empty,
            log([.showedUp]),
            log([.showedUp, .homeWorkout]),
            log([.homeWorkout, .homeWorkout, .homeWorkout]),
            log([.showedUp, .showedUp, .showedUp, .showedUp, .showedUp]),
            log([.showedUp, .missed, .skipped, .homeWorkout]),
        ]
        for ledger in ledgers {
            for days in [threeDays, fourDays] {
                let (field, streak) = build(ledger, days: days)
                #expect(field.countedCount == streak.thisWeekSessionDays)
                #expect(field.targetCount == streak.weeklyGoal)
            }
        }
    }

    @Test("Extra workouts never move the goal: 5 counted on a 4-day plan stays /4")
    func extraWorkoutsAreCappedAtTheGoal() {
        let (field, _) = build(log(Array(repeating: .showedUp, count: 5)), days: fourDays)
        #expect(field.countedCount == 5)
        #expect(field.targetCount == 4)
        #expect(field.summaryValue == "5/4")
        #expect(field.completedStages == 4)
    }

    @Test("Gym and home on the same day is one counted day")
    func sameDayCountsOnce() {
        let ledger = MomentumLog(outcomes: [
            SessionOutcome(date: day(0, hour: 7), kind: .showedUp),
            SessionOutcome(date: day(0, hour: 19), kind: .homeWorkout),
        ])
        let (field, streak) = build(ledger, days: threeDays)
        #expect(field.countedCount == 1)
        #expect(streak.thisWeekSessionDays == 1)
        #expect(field.summaryValue == "1/3")
        // The day reads as a gym day; the home workout is not a second day.
        #expect(field.verifiedCount == 1)
        #expect(field.preservedCount == 0)
        #expect(field.homeNote == nil)
    }

    @Test("A gym arrival without a finished workout lights nothing")
    func unprovenArrivalLightsNothing() {
        let (field, _) = build(log([.showedUp], proof: .unproven), days: threeDays)
        #expect(field.countedCount == 0)
        #expect(field.verifiedCount == 0)
        #expect(field.summaryValue == "0/3")
        #expect(field.completedStages == 0)
    }

    @Test("An unverified home workout neither counts nor shows as at home")
    func unverifiedHomeWorkoutDoesNotCount() {
        let (field, streak) = build(log([.homeWorkout], proof: .unproven), days: threeDays)
        #expect(field.countedCount == 0)
        #expect(field.preservedCount == 0)
        #expect(field.homeNote == nil)
        #expect(streak.thisWeekSessionDays == 0)
    }

    @Test("No training days: no fraction, no stages")
    func noScheduleStaysEmpty() {
        var bare = MorningPlan.default
        bare.slots = []
        var schedule = GymSchedule.default
        schedule.trainingDays = []
        let field = MomentumField.build(
            log: log([.showedUp]),
            plan: bare,
            schedule: schedule,
            weeklyGoal: 3,
            now: day(2),
            calendar: calendar
        )
        #expect(!field.hasSchedule)
        #expect(field.targetCount == 0)
        #expect(field.summaryValue == "—")
        #expect(field.caption == "NO DAYS SET")
    }

    @Test("The accessibility text reads the same numbers")
    func accessibilityText() {
        let (field, _) = build(log([.showedUp, .homeWorkout]), days: fourDays)
        #expect(field.accessibilityText == "Momentum. 2 of 4 workout days this week. 1 of them at home.")
    }
}
