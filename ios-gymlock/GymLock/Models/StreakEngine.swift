import Foundation

/// Turns the ledger into the streak, one week at a time.
///
/// A pure function over `MomentumLog` and the plan, with `now` and `calendar`
/// passed in so every rule below can be pinned by a test. The streak count is
/// never stored: it is rebuilt from the outcomes on every evaluation, so it can
/// never disagree with the record that justifies it. The only state that
/// survives between runs is the `StreakVault` — which weeks a freeze protected,
/// how many are banked, and how far the evaluation has reached — because none
/// of that can be recovered from the outcomes alone.
///
/// Weeks are Monday-first via `ProgressAnalytics.displayCalendar`, the same
/// week the Progress chart and the schedule selector use. There is no second
/// definition of a week anywhere in the app.
enum StreakEngine {
    /// Evaluates the streak up to `now`, spending and awarding freezes for any
    /// weeks that have completed since the vault last ruled on one.
    ///
    /// Completed weeks are walked oldest to newest so a freeze is spent on the
    /// first unkept week it can save, not the last: three weeks away with two
    /// freezes banked leaves two frozen and one broken, in that order.
    static func evaluate(
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        vault: inout StreakVault,
        now: Date,
        calendar: Calendar = .current
    ) -> StreakSnapshot {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let liveWeekStart = weekStart(containing: now, weekCalendar: weekCalendar) else {
            return .empty
        }

        let goal = StreakPolicy.weeklyGoal(
            plannedDays: plan.effectiveTrainingDays(fallback: schedule).count
        )
        let sessionDays = sessionDaysByWeek(log, calendar: calendar, weekCalendar: weekCalendar)

        // The first launch on the week-based logic has nothing to spend and
        // must not award from history either — the migration grant below is
        // the only freeze the past is allowed to produce.
        let isMigrating = vault.needsMigration
        let previouslyEvaluated = vault.lastEvaluatedWeekStart

        var streak = 0

        if let earliest = log.outcomes.map(\.date).min(),
           var cursor = weekStart(containing: earliest, weekCalendar: weekCalendar) {
            while cursor < liveWeekStart {
                let sessions = sessionDays[cursor] ?? 0
                let isKept = sessions >= goal
                let isNew = isMigrating || previouslyEvaluated.map { cursor > $0 } ?? true

                if isKept {
                    streak += 1

                    if isNew {
                        // A week the user protected in advance and then kept
                        // anyway: they never needed the freeze, so it goes back.
                        if vault.isPreArmed(weekStarting: cursor, calendar: calendar) {
                            vault.preArmedWeekStart = nil
                            vault.freezesAvailable = min(vault.freezesAvailable + 1, StreakPolicy.maximumFreezes)
                        }
                        if !isMigrating, streak % StreakPolicy.weeksPerFreeze == 0 {
                            vault.freezesAvailable = min(vault.freezesAvailable + 1, StreakPolicy.maximumFreezes)
                        }
                    }
                } else if vault.isFrozen(weekStarting: cursor, calendar: calendar) {
                    // Protected earlier. Neither counts nor breaks.
                } else if isNew, vault.isPreArmed(weekStarting: cursor, calendar: calendar) {
                    // Paid for when it was armed; it simply becomes a frozen week.
                    vault.preArmedWeekStart = nil
                    vault.frozenWeekStarts.insert(cursor)
                } else if isNew, vault.freezesAvailable > 0 {
                    vault.freezesAvailable -= 1
                    vault.frozenWeekStarts.insert(cursor)
                } else {
                    streak = 0
                }

                guard let next = weekCalendar.date(byAdding: .weekOfYear, value: 1, to: cursor),
                      let nextStart = weekStart(containing: next, weekCalendar: weekCalendar),
                      nextStart > cursor
                else { break }
                cursor = nextStart
            }
        }

        // The live week counts only once it is kept, and can never break.
        let thisWeekSessions = sessionDays[liveWeekStart] ?? 0
        let isThisWeekKept = thisWeekSessions >= goal
        let weeks = isThisWeekKept ? streak + 1 : streak

        // A pre-armed live week that is kept has its freeze refunded at once.
        // Kept cannot be undone by anything the user does, and waiting for the
        // week to end would show them one freeze fewer than they really have.
        if isThisWeekKept, vault.isPreArmed(weekStarting: liveWeekStart, calendar: calendar) {
            vault.preArmedWeekStart = nil
            vault.freezesAvailable = min(vault.freezesAvailable + 1, StreakPolicy.maximumFreezes)
        }

        // A pre-arm that is neither the live week nor was met by the walk
        // above is stale state from somewhere odd. Clear it rather than let it
        // silently protect a week years from now.
        if let armed = vault.preArmedWeekStart,
           !calendar.isDate(armed, inSameDayAs: liveWeekStart) {
            vault.preArmedWeekStart = nil
        }

        if isMigrating {
            vault.freezesAvailable = weeks >= StreakPolicy.weeksPerFreeze ? 1 : 0
        }

        // Kept in step with the derived count rather than incremented on its
        // own, so a changed plan cannot leave it pointing at a streak that no
        // longer exists.
        vault.kept4Counter = streak % StreakPolicy.weeksPerFreeze

        let previousWeekStart = weekCalendar.date(byAdding: .weekOfYear, value: -1, to: liveWeekStart)
            .flatMap { weekStart(containing: $0, weekCalendar: weekCalendar) }
        vault.lastEvaluatedWeekStart = previousWeekStart ?? liveWeekStart

        let lastCompletedWeekWasFrozen = previousWeekStart
            .map { vault.isFrozen(weekStarting: $0, calendar: calendar) } ?? false

        return StreakSnapshot(
            weeks: weeks,
            weeklyGoal: goal,
            thisWeekSessionDays: thisWeekSessions,
            isThisWeekKept: isThisWeekKept,
            freezesAvailable: vault.freezesAvailable,
            lastCompletedWeekWasFrozen: lastCompletedWeekWasFrozen,
            isLiveWeekPreArmed: vault.isPreArmed(weekStarting: liveWeekStart, calendar: calendar),
            liveWeekStart: liveWeekStart
        )
    }

    // MARK: - Shared definitions

    /// Monday 00:00 of the week containing `date`, in the display calendar.
    static func weekStart(containing date: Date, weekCalendar: Calendar) -> Date? {
        weekCalendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    /// The distinct days in one week on which momentum was preserved, oldest
    /// first.
    ///
    /// This is the single definition of a "session day": several outcomes on
    /// one day count once, and only outcomes that preserve momentum count at
    /// all. The share frames read it too, so a streak number and the "3 of 3"
    /// beside it can never be counting different things.
    static func sessionDays(
        in log: MomentumLog,
        weekStarting start: Date,
        calendar: Calendar
    ) -> [Date] {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        var days: Set<Date> = []

        for outcome in log.outcomes where outcome.kind.preservesMomentum {
            let day = calendar.startOfDay(for: outcome.date)
            guard let week = weekStart(containing: day, weekCalendar: weekCalendar),
                  calendar.isDate(week, inSameDayAs: start)
            else { continue }
            days.insert(day)
        }

        return days.sorted()
    }

    /// Session-day counts keyed by week start.
    private static func sessionDaysByWeek(
        _ log: MomentumLog,
        calendar: Calendar,
        weekCalendar: Calendar
    ) -> [Date: Int] {
        var daysSeen: Set<Date> = []
        var counts: [Date: Int] = [:]

        for outcome in log.outcomes where outcome.kind.preservesMomentum {
            let day = calendar.startOfDay(for: outcome.date)
            guard daysSeen.insert(day).inserted,
                  let week = weekStart(containing: day, weekCalendar: weekCalendar)
            else { continue }
            counts[week, default: 0] += 1
        }

        return counts
    }
}
