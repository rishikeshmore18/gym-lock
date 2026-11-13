import Foundation

/// The weekly goal of any week, past, live or future (FLOW, item 19a).
///
/// The one place a screen asks "what was this week's goal?". It reads the
/// goals the streak engine saved, so Progress, Home and the streak can never
/// judge the same week by different numbers:
///
/// - A **finished** week keeps the goal it was saved with. A plan change
///   never rewrites history: a week planned at 3 stays 3 after moving to 5.
/// - The **live** week and every **future** week follow the plan as it is
///   right now, so a change on the alarm screen shows up everywhere at once.
/// - Weeks before the user joined have no goal.
struct WeeklyGoals: Hashable {
    /// Goals the engine saved, keyed by Monday.
    var saved: [Date: Int]
    /// First week the 3-day minimum covered (`StreakVault.threeDayRuleStart`).
    var ruleStart: Date?
    /// Workout days in the plan right now.
    var plannedDays: Int
    /// Monday of the week the user joined, if known.
    var firstWeekStart: Date?

    init(saved: [Date: Int], ruleStart: Date?, plannedDays: Int, firstWeekStart: Date?) {
        self.saved = saved
        self.ruleStart = ruleStart
        self.plannedDays = plannedDays
        self.firstWeekStart = firstWeekStart
    }

    init(
        vault: StreakVault,
        plan: MorningPlan,
        schedule: GymSchedule,
        joinedAt: Date?,
        calendar: Calendar = .current
    ) {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        self.init(
            saved: vault.weekGoals,
            ruleStart: vault.threeDayRuleStart,
            plannedDays: plan.effectiveTrainingDays(fallback: schedule).count,
            firstWeekStart: joinedAt.flatMap { StreakEngine.weekStart(containing: $0, weekCalendar: weekCalendar) }
        )
    }

    /// The goal of the Monday-first week starting `week`.
    func goal(forWeekStarting week: Date, liveWeekStart: Date, calendar: Calendar) -> Int {
        let isLiveOrLater = week >= liveWeekStart || calendar.isDate(week, inSameDayAs: liveWeekStart)

        if !isLiveOrLater, let stored = savedGoal(forWeekStarting: week, calendar: calendar) {
            return stored
        }
        if let firstWeekStart, week < firstWeekStart, !calendar.isDate(week, inSameDayAs: firstWeekStart) {
            return 0
        }
        guard plannedDays > 0 else { return 0 }
        return StreakPolicy.goal(
            forWeekStarting: week,
            ruleStart: ruleStart ?? liveWeekStart,
            plannedDays: plannedDays,
            calendar: calendar
        )
    }

    private func savedGoal(forWeekStarting start: Date, calendar: Calendar) -> Int? {
        if let exact = saved[start] { return exact }
        return saved.first { calendar.isDate($0.key, inSameDayAs: start) }?.value
    }
}
