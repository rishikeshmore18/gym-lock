import Foundation
import Testing
@testable import GymLock

/// How the context's fields are derived from the record.
@MainActor
struct ShareContextBuilderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        // Sunday-first locale, to prove the week counts stay Monday-first.
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }

    /// Wednesday 16 September 2026, 07:00 New York.
    private var wednesday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 7)) ?? Date()
    }

    private func day(_ offset: Int, hour: Int = 7) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: wednesday) ?? wednesday
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    // MARK: Receipt

    @Test("Receipt from a complete morning, with and without a workout")
    func receiptComplete() {
        let id = UUID()
        let events: [SessionEvent] = [
            SessionEvent(sessionID: id, kind: .alarmFired, at: day(0, hour: 6)),
            SessionEvent(sessionID: id, kind: .committed, at: day(0, hour: 6).addingTimeInterval(60)),
            SessionEvent(sessionID: id, kind: .departed, at: day(0, hour: 6).addingTimeInterval(29 * 60)),
            SessionEvent(sessionID: id, kind: .gymArrivalVerified, at: day(0, hour: 6).addingTimeInterval(47 * 60)),
        ]
        let receipt = ShareContextBuilder.receipt(from: events)
        #expect(receipt != nil)
        #expect(receipt?.alarmToGymMinutes == 47)
        #expect(receipt?.workout == nil)

        let withWorkout = events + [
            SessionEvent(sessionID: id, kind: .workoutDetected, at: day(0, hour: 8)),
        ]
        #expect(ShareContextBuilder.receipt(from: withWorkout)?.workout != nil)
    }

    @Test("A missing departure hides the receipt")
    func receiptMissingDeparture() {
        let events: [SessionEvent] = [
            SessionEvent(kind: .alarmFired, at: day(0, hour: 6)),
            SessionEvent(kind: .gymArrivalVerified, at: day(0, hour: 7)),
        ]
        #expect(ShareContextBuilder.receipt(from: events) == nil)
    }

    // MARK: Comeback

    @Test("Comeback: a return after a miss, days apart")
    func comebackDetection() {
        let log = MomentumLog(outcomes: [
            SessionOutcome(date: day(-2), kind: .missed),
            SessionOutcome(date: day(0), kind: .showedUp),
        ])
        let comeback = ShareContextBuilder.comeback(on: day(0), log: log, calendar: calendar)
        #expect(comeback != nil)
        #expect(comeback.map { calendar.isDate($0.missedDay, inSameDayAs: day(-2)) } == true)

        // A kept day before the return is not a comeback.
        let steady = MomentumLog(outcomes: [
            SessionOutcome(date: day(-2), kind: .showedUp),
            SessionOutcome(date: day(0), kind: .showedUp),
        ])
        #expect(ShareContextBuilder.comeback(on: day(0), log: steady, calendar: calendar) == nil)

        // A technical failure followed by a home workout the same day is not a miss.
        let saved = MomentumLog(outcomes: [
            SessionOutcome(date: day(-1, hour: 7), kind: .technicalFailure),
            SessionOutcome(date: day(-1, hour: 19), kind: .homeWorkout),
            SessionOutcome(date: day(0), kind: .showedUp),
        ])
        #expect(ShareContextBuilder.comeback(on: day(0), log: saved, calendar: calendar) == nil)
    }

    // MARK: Journey

    @Test("Journey completion is nil when nothing was due")
    func journeyNilWhenNothingDue() {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: [.monday], alarmTime: TimeOfDay(hour: 6, minute: 0))]
        let tally = ProgressAnalytics.tally(
            in: DateInterval(start: day(-27), end: day(1)),
            log: .empty,
            plan: plan,
            schedule: .default,
            now: day(0),
            calendar: calendar
        )
        #expect(tally.due == 0)
        #expect(tally.completionRate == nil)
    }

    @Test("Tally reuses the chart's rules: quick workouts complete, excused stays out")
    func tallyRules() {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: [.monday, .wednesday, .friday], alarmTime: TimeOfDay(hour: 6, minute: 0))]
        let log = MomentumLog(outcomes: [
            SessionOutcome(date: day(-9), kind: .showedUp),      // Mon
            SessionOutcome(date: day(-7), kind: .homeWorkout),   // Wed
            SessionOutcome(date: day(-5), kind: .missed),        // Fri
            SessionOutcome(date: day(-2), kind: .easySkip),      // Mon
        ])
        let tally = ProgressAnalytics.tally(
            in: DateInterval(start: day(-10), end: day(-1)),
            log: log, plan: plan, schedule: .default, now: day(0), calendar: calendar
        )
        #expect(tally.completed == 2)
        #expect(tally.missed == 1)
        #expect(tally.excused == 1)
        #expect(tally.due == 3)
    }

    // MARK: Week counts

    @Test("Week counts are Monday-first even in a Sunday-first locale")
    func mondayFirstWeeks() {
        // Sunday 13 Sep and Monday 14 Sep: a Sunday-first calendar would put
        // both in the week of the 16th; Monday-first puts Sunday in the
        // previous week.
        let sunday = day(-3)
        let monday = day(-2)
        let log = MomentumLog(outcomes: [
            SessionOutcome(date: sunday, kind: .showedUp),
            SessionOutcome(date: monday, kind: .showedUp),
            SessionOutcome(date: day(0), kind: .showedUp),
        ])
        let weekStart = StreakEngine.weekStart(
            containing: wednesday,
            weekCalendar: ProgressAnalytics.displayCalendar(calendar)
        ) ?? wednesday
        #expect(calendar.isDate(weekStart, inSameDayAs: monday))
        let days = StreakEngine.sessionDays(in: log, weekStarting: weekStart, calendar: calendar)
        #expect(days.count == 2)
    }

    // MARK: Milestones

    @Test("Visit milestone only on the day the count was reached")
    func visitMilestone() {
        var outcomes: [SessionOutcome] = []
        for offset in (1...10).reversed() {
            outcomes.append(SessionOutcome(date: day(-offset), kind: .showedUp))
        }
        let log = MomentumLog(outcomes: outcomes)
        let streak = StreakSnapshot.empty

        let tenth = Milestone.crossed(on: day(-1), log: log, streak: streak, sessionDaysThisWeek: [], comeback: nil, calendar: calendar)
        #expect(tenth?.kind == .verifiedVisits(10))

        let ninth = Milestone.crossed(on: day(-2), log: log, streak: streak, sessionDaysThisWeek: [], comeback: nil, calendar: calendar)
        #expect(ninth == nil)
    }

    @Test("Streak milestone requires the goal reached on the reference day")
    func streakMilestone() {
        let streak = StreakSnapshot(
            weeks: 4, weeklyGoal: 3, thisWeekSessionDays: 3, isThisWeekKept: true,
            freezesAvailable: 1, lastCompletedWeekWasFrozen: false, isLiveWeekPreArmed: false, liveWeekStart: day(-2)
        )
        let sessionDays = [day(-2), day(-1), day(0)].map { calendar.startOfDay(for: $0) }
        let onGoalDay = Milestone.crossed(on: day(0), log: .empty, streak: streak, sessionDaysThisWeek: sessionDays, comeback: nil, calendar: calendar)
        #expect(onGoalDay?.kind == .streakWeeks(4))
        #expect(onGoalDay?.title == "FIRST MONTH")

        let dayBefore = Milestone.crossed(on: day(-1), log: .empty, streak: streak, sessionDaysThisWeek: sessionDays, comeback: nil, calendar: calendar)
        #expect(dayBefore == nil)
    }

    @Test("First comeback is a milestone once only")
    func firstComebackOnce() {
        let first = MomentumLog(outcomes: [
            SessionOutcome(date: day(-2), kind: .missed),
            SessionOutcome(date: day(0), kind: .showedUp),
        ])
        #expect(Milestone.isFirstComeback(before: day(0), log: first, calendar: calendar))

        let second = MomentumLog(outcomes: [
            SessionOutcome(date: day(-9), kind: .missed),
            SessionOutcome(date: day(-7), kind: .showedUp),
            SessionOutcome(date: day(-2), kind: .missed),
            SessionOutcome(date: day(0), kind: .showedUp),
        ])
        #expect(!Milestone.isFirstComeback(before: day(0), log: second, calendar: calendar))
    }
}
