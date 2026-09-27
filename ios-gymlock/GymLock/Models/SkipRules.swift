import Foundation

// MARK: - The one skip screen

/// One of the three doors on the skip screen (FLOW, Flow 4).
nonisolated enum SkipScreenOption: Hashable {
    case reschedule
    case homeWorkout
    case skip
}

/// What the skip screen shows, worked out once in a pure function so the
/// heading and the order of the doors can be pinned by a test.
nonisolated struct SkipScreenPlan: Hashable {
    /// "make it up. this keeps your streak." or "no problem. you need N more
    /// this week."
    var heading: String
    /// How many more workouts the week needs. Shown inside the heading.
    var moreNeeded: Int
    /// The doors, in the order they appear.
    var options: [SkipScreenOption]
    /// "your planned days left are enough." when reschedule is hidden but the
    /// week is still reachable. Nil otherwise.
    var rescheduleNote: String?
}

/// The skip screen's question: can they still reach 3 this week? Counted
/// workouts so far, plus the planned chances left after today — remaining gym
/// days and pending reschedules. Today does not count; it is the day being
/// skipped.
nonisolated enum SkipRules {
    /// Workouts counted this week (Monday to Sunday), not counting the day
    /// being skipped.
    static func countedThisWeek(log: MomentumLog, day: Date, calendar: Calendar) -> Int {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let weekStart = StreakEngine.weekStart(containing: day, weekCalendar: weekCalendar) else {
            return 0
        }
        return StreakEngine.sessionDays(in: log, weekStarting: weekStart, calendar: calendar)
            .filter { !calendar.isDate($0, inSameDayAs: day) }
            .count
    }

    /// Planned chances left after the day being skipped: each remaining gym
    /// day this week with nothing counted yet, plus every pending reschedule
    /// still to come this week. A gym day that already counted is not a
    /// chance any more; it is already in the count.
    static func chancesRemaining(
        log: MomentumLog,
        plan: MorningPlan,
        day: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let weekStart = StreakEngine.weekStart(containing: day, weekCalendar: weekCalendar),
              let weekEnd = weekCalendar.dateInterval(of: .weekOfYear, for: day)?.end
        else { return 0 }

        let counted = Set(StreakEngine.sessionDays(in: log, weekStarting: weekStart, calendar: calendar))

        var chances = 0
        var cursor = calendar.startOfDay(for: day)
        while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next < weekEnd {
            cursor = next
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: next)) else { continue }
            if plan.gymDays.contains(weekday), !counted.contains(next) { chances += 1 }
        }

        // Pending reschedules, this week only. Nothing carries into next week.
        for alarm in plan.oneOffAlarms
        where alarm.kind == .reschedule
            && alarm.isActive(at: now)
            && alarm.fireDate > now
            && alarm.fireDate < weekEnd {
            chances += 1
        }

        return chances
    }

    /// The screen for a day being skipped. When the week is still reachable,
    /// skip comes first and nothing is made of it. When it is not, reschedule
    /// comes first, recommended. Reschedule is hidden when there is nowhere
    /// to move the workout to (no free days, or Sunday).
    static func screen(
        log: MomentumLog,
        plan: MorningPlan,
        day: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SkipScreenPlan {
        let goal = StreakPolicy.defaultWeeklyGoal
        let counted = countedThisWeek(log: log, day: day, calendar: calendar)
        let chances = chancesRemaining(log: log, plan: plan, day: day, now: now, calendar: calendar)
        let needed = max(0, goal - counted)
        let reachable = counted + chances >= goal
        let choices = ReschedulePlanner.choices(plan: plan, day: day, now: now, calendar: calendar)

        if reachable {
            var options: [SkipScreenOption] = [.skip]
            if choices.isEmpty {
                // Nowhere to move it to, and the planned days left cover it.
                return SkipScreenPlan(
                    heading: "no problem. you need \(needed) more this week.",
                    moreNeeded: needed,
                    options: options + [.homeWorkout],
                    rescheduleNote: "your planned days left are enough."
                )
            }
            options += [.reschedule, .homeWorkout]
            return SkipScreenPlan(
                heading: "no problem. you need \(needed) more this week.",
                moreNeeded: needed,
                options: options,
                rescheduleNote: nil
            )
        }

        if choices.isEmpty {
            // Sunday, or no free days: the week cannot be reached by moving
            // days around. The home workout and the skip are all that is left.
            return SkipScreenPlan(
                heading: "make it up. this keeps your streak.",
                moreNeeded: needed,
                options: [.homeWorkout, .skip],
                rescheduleNote: nil
            )
        }

        return SkipScreenPlan(
            heading: "make it up. this keeps your streak.",
            moreNeeded: needed,
            options: [.reschedule, .homeWorkout, .skip],
            rescheduleNote: nil
        )
    }
}

// MARK: - Reschedule

/// Where a missed workout can be moved to: "later today", then each day left
/// this week (through Sunday) that is neither an already planned gym day nor
/// already rescheduled to. Nothing on Sunday.
nonisolated enum ReschedulePlanner {
    struct Choice: Hashable {
        /// The start of the day the alarm rings on (today for "later today").
        var day: Date
        var label: String
        var isLaterToday: Bool
    }

    /// The smallest gap between the tap and a later-today alarm.
    static let minimumLead: TimeInterval = 15 * 60

    /// The default alarm time: their usual lock-alarm time for their mode.
    /// Wake & Go uses the wake time, Go Later the time-to-go time.
    static func defaultTime(plan: MorningPlan, on day: Date, calendar: Calendar = .current) -> TimeOfDay {
        plan.rhythm(at: day, calendar: calendar).lockAlarmTime
    }

    /// The days that already carry a pending reschedule.
    static func rescheduledDays(plan: MorningPlan, now: Date, calendar: Calendar = .current) -> Set<Date> {
        Set(
            plan.oneOffAlarms
                .filter { $0.kind == .reschedule && $0.isActive(at: now) }
                .map { calendar.startOfDay(for: $0.fireDate) }
        )
    }

    /// "later today" (only when a time before sleep hours is still left),
    /// then the free days left this week.
    static func choices(
        plan: MorningPlan,
        day: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Choice] {
        let skipDay = calendar.startOfDay(for: day)
        var result: [Choice] = []

        // "later today" only exists for a day being skipped today, and only
        // while a usable time is still left before bedtime.
        if calendar.isDate(skipDay, inSameDayAs: now) {
            let soon = TimeOfDay(from: now.addingTimeInterval(minimumLead))
            if isTimeAvailable(soon, on: skipDay, plan: plan, now: now, calendar: calendar) {
                result.append(Choice(day: skipDay, label: "later today", isLaterToday: true))
            }
        }

        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let weekEnd = weekCalendar.dateInterval(of: .weekOfYear, for: skipDay)?.end else {
            return result
        }

        let taken = rescheduledDays(plan: plan, now: now, calendar: calendar)
        var cursor = skipDay
        while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next < weekEnd {
            cursor = next
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: next)) else { continue }
            if plan.gymDays.contains(weekday) { continue }
            if taken.contains(next) { continue }
            result.append(Choice(day: next, label: weekday.shortLabel, isLaterToday: false))
        }

        return result
    }

    /// Whether an alarm at `time` on `day` can run as a gym day: not inside
    /// sleep hours, and the whole visit fits before bedtime.
    static func isTimeAvailable(
        _ time: TimeOfDay,
        on day: Date,
        plan: MorningPlan,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let alarm = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) else {
            return false
        }
        guard alarm > now else { return false }

        let rhythm = plan.rhythm(at: day, calendar: calendar)
        let visitStart = alarm.addingTimeInterval(Double(rhythm.windowMinutes) * 60)
        let visitEnd = visitStart.addingTimeInterval(Double(rhythm.gymSessionMinutes) * 60)
        return !RunningLate.overlapsSleep(
            start: visitStart,
            end: visitEnd,
            rhythm: rhythm,
            pending: plan.pendingBedtime,
            calendar: calendar
        )
    }
}

// MARK: - Home workout

/// The home workout rules (FLOW, Flow 4): 20 or 30 minutes, at most 3 counted
/// a calendar month, and it only counts once Apple Health confirms it or a
/// camera progress photo lands.
nonisolated enum HomeWorkoutRules {
    static let monthlyLimit = 3
    static let options = [20, 30]
    static let defaultMinutes = 20
    static let capMessage = "3 of 3 home workouts used. back on the 1st."
    static let notFoundMessage = "no workout in Apple Health? add a progress photo to count it."

    /// The Health check for a home workout: the gym's rules (20+ minutes, not
    /// typed by hand, starting no earlier than 15 minutes before the timer
    /// started), plus the workout must have started the same day.
    static func healthQualifies(
        _ workout: DetectedWorkout,
        timerStart: Date,
        calendar: Calendar
    ) -> Bool {
        WorkoutRules.healthQualifies(workout, arrivedAt: timerStart)
            && calendar.isDate(workout.startedAt, inSameDayAs: timerStart)
    }

    /// Counted home workouts in the calendar month containing `now`. An
    /// attempt that was never verified does not use up the cap.
    static func usedThisMonth(log: MomentumLog, now: Date, calendar: Calendar = .current) -> Int {
        log.outcomes.filter { outcome in
            guard outcome.kind == .homeWorkout, outcome.counts else { return false }
            return calendar.isDate(outcome.countingDay(calendar: calendar), equalTo: now, toGranularity: .month)
        }.count
    }

    static func atCap(log: MomentumLog, now: Date, calendar: Calendar = .current) -> Bool {
        usedThisMonth(log: log, now: now, calendar: calendar) >= monthlyLimit
    }
}
