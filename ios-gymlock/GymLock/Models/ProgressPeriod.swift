import Foundation

// MARK: - Day status

/// What one day inside a displayed period turned out to be.
///
/// This is a *presentation* type, derived from `MomentumLog` and the user's
/// plan. Those remain the only sources of truth — nothing here is persisted and
/// nothing here is estimated.
///
/// There is no "failed" case, and `missed` is only ever produced by a recorded
/// `.missed` outcome. A planned day that passed with nothing written down is
/// `unresolved`, because no record is not evidence of a failure: the ledger may
/// simply not have been running yet.
enum ProgressDayStatus: String, Hashable, Codable {
    /// Confirmed arrival at the gym.
    case gymVerified
    /// The 25-minute home fallback. Keeps the commitment; is not a gym visit.
    case quickWorkoutVerified
    /// A session came due and was recorded as missed.
    case missed
    /// Skipped on purpose, rescheduled, or a technical failure. Neither
    /// credited nor punished, so it stays out of the completion fraction.
    case excused
    /// A planned day in the past with nothing recorded.
    case unresolved
    /// A planned day still ahead, including today before it resolves.
    case upcoming
    /// Not a training day.
    case rest

    /// Both kinds of completion count towards the commitment.
    var countsAsCompleted: Bool {
        self == .gymVerified || self == .quickWorkoutVerified
    }

    /// Whether the user actually had the opportunity and it resolved.
    ///
    /// This is the denominator of the headline percentage, which is why a
    /// future session can never drag it down.
    var isDue: Bool { countsAsCompleted || self == .missed }
}

/// One day as the charts need it.
struct ProgressDay: Identifiable, Hashable {
    /// Start of day in the display calendar.
    let date: Date
    let status: ProgressDayStatus
    /// Whether the user's plan calls for training on this weekday.
    let isPlanned: Bool
    let isToday: Bool
    /// Abbreviated weekday, e.g. "Mon".
    let weekdayLabel: String
    /// Short date, e.g. "Sep 7".
    let dateLabel: String

    var id: Date { date }

    var accessibilityText: String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        switch status {
        case .gymVerified: return "\(day). Verified gym session."
        case .quickWorkoutVerified: return "\(day). Verified 25-minute workout."
        case .missed: return "\(day). Planned session missed."
        case .excused: return "\(day). Planned session set aside."
        case .unresolved: return "\(day). Planned, nothing recorded."
        case .upcoming: return "\(day). Planned session upcoming."
        case .rest: return "\(day). Rest day."
        }
    }
}

// MARK: - Tally

/// The counts behind one period, and the arithmetic the UI is allowed to show.
///
/// Weeks and months are measured against the **weekly goal** (`WeeklyGoals`),
/// the same number Home and the streak use. The day-level counts stay for the
/// rolling-window share stats (`ProgressAnalytics.tally(in:)`).
struct ProgressTally: Hashable {
    var verifiedGym = 0
    var quickWorkout = 0
    /// Days recorded as missed. On a week or month tally, the goal shortfall
    /// drawn as missed: the whole shortfall once a week has ended, only the
    /// recorded misses while it is live.
    var missed = 0
    var excused = 0
    var unresolved = 0
    var upcoming = 0
    /// Cards in the bar. For a week, the goal, grown if the user did more.
    var slots = 0
    /// Sum of the weekly goals. Zero on a day-level tally.
    var goal = 0
    /// Workouts that count towards the goal, capped per week at its goal so
    /// an extra session in one week can't hide a short week.
    var credited = 0
    /// Weeks with a goal, and how many of them reached it.
    var weeksWithGoal = 0
    var weeksKept = 0

    /// A quick workout counts here. It never counts as a gym visit.
    var completed: Int { verifiedGym + quickWorkout }

    /// Day-level: sessions that resolved. Used by the rolling share stats.
    var due: Int { completed + missed }

    /// Day-level completion. `nil` when nothing was due — never 0%.
    var completionRate: Double? {
        guard due > 0 else { return nil }
        return Double(completed) / Double(due)
    }

    var hasPlan: Bool { slots > 0 || goal > 0 }

    /// Cards with no outcome drawn on them: still to come.
    var ghost: Int { max(0, slots - completed - missed) }

    static func + (lhs: ProgressTally, rhs: ProgressTally) -> ProgressTally {
        ProgressTally(
            verifiedGym: lhs.verifiedGym + rhs.verifiedGym,
            quickWorkout: lhs.quickWorkout + rhs.quickWorkout,
            missed: lhs.missed + rhs.missed,
            excused: lhs.excused + rhs.excused,
            unresolved: lhs.unresolved + rhs.unresolved,
            upcoming: lhs.upcoming + rhs.upcoming,
            slots: lhs.slots + rhs.slots,
            goal: lhs.goal + rhs.goal,
            credited: lhs.credited + rhs.credited,
            weeksWithGoal: lhs.weeksWithGoal + rhs.weeksWithGoal,
            weeksKept: lhs.weeksKept + rhs.weeksKept
        )
    }
}

// MARK: - Shared headline copy

/// How a week or month presents its numbers against the goal.
///
/// "3/5" means 3 workouts of a goal of 5, the same fraction the Momentum card
/// on Home shows. The ring and percentage use `credited`, so a month is 100%
/// only when every week reached its goal.
protocol ProgressPeriodPresentation {
    var tally: ProgressTally { get }
    /// True when the period contains today or lies in the future.
    var isLive: Bool { get }
    /// "weekly goal" or "month goal".
    var goalNoun: String { get }
    /// One quiet line under the percentage: "2 to go", "1 of 4 weeks kept".
    var planNote: String? { get }
}

extension ProgressPeriodPresentation {
    /// Denominator of the headline fraction: the goal.
    var headlineTotal: Int { tally.goal }

    /// 0...1, or `nil` when there is no goal.
    var completionFraction: Double? {
        guard tally.goal > 0 else { return nil }
        return min(1, Double(tally.credited) / Double(tally.goal))
    }

    /// "3/5".
    var fractionText: String {
        guard tally.hasPlan else { return "—" }
        guard tally.goal > 0 else { return "\(tally.completed)" }
        return "\(tally.completed)/\(tally.goal)"
    }

    var fractionCaption: String {
        tally.hasPlan ? "workouts" : "no plan"
    }

    /// "60%", or an em dash when there is no goal.
    var percentText: String {
        guard let fraction = completionFraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    var percentCaption: String {
        guard tally.hasPlan, tally.goal > 0 else { return "nothing planned" }
        return "of \(goalNoun)"
    }
}

// MARK: - Week

/// One Monday-to-Sunday week, the same week the streak judges.
struct ProgressWeekSummary: Identifiable, Hashable, ProgressPeriodPresentation {
    /// Position in the month. Stable identity for the expand transition.
    let index: Int
    /// Monday.
    let start: Date
    /// Sunday, inclusive.
    let end: Date
    let days: [ProgressDay]
    let tally: ProgressTally
    /// Contains today or lies ahead.
    let isLive: Bool
    /// Contains today.
    let isCurrent: Bool
    /// "Nov 9–15", or "Nov 30–Dec 6" across a month boundary.
    let rangeLabel: String

    var id: Int { index }
    var goalNoun: String { "weekly goal" }

    var goal: Int { tally.goal }
    var remaining: Int { max(0, goal - tally.completed) }
    var isKept: Bool { goal > 0 && tally.completed >= goal }

    /// "3/5" above the bar.
    var stackCountLabel: String? {
        guard goal > 0 || tally.completed > 0 else { return nil }
        return goal > 0 ? "\(tally.completed)/\(goal)" : "\(tally.completed)"
    }

    /// The line under the percentage.
    var planNote: String? {
        guard goal > 0 else { return nil }
        if isKept { return "goal met" }
        return isLive ? "\(remaining) to go" : "\(remaining) short"
    }

    var accessibilityText: String {
        guard tally.hasPlan else {
            return "\(rangeLabel). No sessions planned."
        }

        var parts = ["\(rangeLabel).", "\(tally.completed) of \(goal) workouts."]
        if tally.verifiedGym > 0 {
            parts.append("\(tally.verifiedGym) gym \(tally.verifiedGym == 1 ? "workout" : "workouts").")
        }
        if tally.quickWorkout > 0 {
            parts.append("\(tally.quickWorkout) quick \(tally.quickWorkout == 1 ? "workout" : "workouts").")
        }
        if isKept {
            parts.append("Goal met.")
        } else if isLive {
            parts.append("\(remaining) to go.")
        } else {
            parts.append("\(remaining) short of the goal.")
        }
        return parts.joined(separator: " ")
    }

    /// Subtitle for the week level: what the week was made of.
    var breakdownLabel: String {
        guard tally.hasPlan else { return "No sessions planned" }

        var parts: [String] = []
        if tally.verifiedGym > 0 { parts.append("\(tally.verifiedGym) gym") }
        if tally.quickWorkout > 0 { parts.append("\(tally.quickWorkout) quick 25") }
        if tally.missed > 0 { parts.append("\(tally.missed) missed") }

        guard !parts.isEmpty else {
            return "Goal: \(goal) \(goal == 1 ? "workout" : "workouts")"
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Month

/// One month of follow-through, as the card needs it.
///
/// A month holds the whole weeks whose Thursday falls in it (ISO 8601), so
/// every week is counted in exactly one month and judged as a whole week,
/// exactly like the streak. No week is split across two months.
struct ProgressMonthSummary: Hashable, ProgressPeriodPresentation {
    /// First day of the month.
    let monthStart: Date
    let isCurrentMonth: Bool
    let isLive: Bool
    let weeks: [ProgressWeekSummary]
    let tally: ProgressTally
    /// "This Month", or the month's own name when looking back.
    let titleLabel: String
    /// "November 2026".
    let subtitleLabel: String

    var goalNoun: String { "month goal" }

    /// "1 of 4 weeks kept".
    var planNote: String? {
        guard tally.weeksWithGoal > 0 else { return nil }
        return "\(tally.weeksKept) of \(tally.weeksWithGoal) weeks kept"
    }

    /// Tallest bar in the chart, used to normalise the others.
    var maxSlots: Int { weeks.map(\.tally.slots).max() ?? 0 }

    var hasAnyWeeks: Bool { !weeks.isEmpty }

    /// Shown in place of the chart when there is genuinely nothing to draw.
    var emptyStateText: String? {
        tally.hasPlan ? nil : "No sessions planned yet"
    }

    func week(at index: Int) -> ProgressWeekSummary? {
        weeks.first { $0.index == index }
    }

    static func empty(monthStart: Date, isCurrentMonth: Bool) -> ProgressMonthSummary {
        ProgressMonthSummary(
            monthStart: monthStart,
            isCurrentMonth: isCurrentMonth,
            isLive: isCurrentMonth,
            weeks: [],
            tally: ProgressTally(),
            titleLabel: isCurrentMonth ? "This Month" : monthStart.formatted(.dateTime.month(.wide)),
            subtitleLabel: monthStart.formatted(.dateTime.month(.wide).year())
        )
    }
}

// MARK: - Training days

extension MorningPlan {
    /// The weekdays the user actually trains on.
    ///
    /// The plan's enabled alarm slots are the truth; the schedule is only a
    /// fallback for someone who has not built a plan yet. Same rule the
    /// momentum week uses, kept in one place.
    func effectiveTrainingDays(fallback schedule: GymSchedule) -> Set<Weekday> {
        let fromSlots = enabledSlots.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }
        return fromSlots.isEmpty ? schedule.trainingDays : fromSlots
    }
}

// MARK: - Analytics

/// Derives the Progress charts from the records the app already keeps.
///
/// Pure functions over `MomentumLog`, the plan and `WeeklyGoals`: no storage
/// of its own, no second history system.
struct ProgressAnalytics {
    /// Weeks are Monday-first regardless of locale, matching the schedule
    /// selector the user configured and the momentum week on Home.
    static func displayCalendar(_ calendar: Calendar = .current) -> Calendar {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        return weekCalendar
    }

    /// The month a date's week belongs to: the month of that week's Thursday.
    static func monthStart(forWeekContaining date: Date, calendar: Calendar = .current) -> Date {
        let weekCalendar = displayCalendar(calendar)
        let weekStart = StreakEngine.weekStart(containing: date, weekCalendar: weekCalendar) ?? date
        let thursday = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
        return calendar.dateInterval(of: .month, for: thursday)?.start ?? calendar.startOfDay(for: date)
    }

    /// Builds the month containing `date`.
    static func monthSummary(
        containing date: Date,
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        goals: WeeklyGoals,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgressMonthSummary {
        let weekCalendar = displayCalendar(calendar)
        let today = calendar.startOfDay(for: now)

        guard let month = calendar.dateInterval(of: .month, for: date),
              let liveWeekStart = StreakEngine.weekStart(containing: today, weekCalendar: weekCalendar)
        else {
            return .empty(monthStart: calendar.startOfDay(for: date), isCurrentMonth: false)
        }

        let isCurrentMonth = calendar.isDate(
            monthStart(forWeekContaining: today, calendar: calendar),
            inSameDayAs: month.start
        )
        let trainingDays = plan.effectiveTrainingDays(fallback: schedule)
        let outcomesByDay = Dictionary(grouping: log.outcomes) {
            $0.countingDay(calendar: calendar)
        }

        var weeks: [ProgressWeekSummary] = []
        var cursor = StreakEngine.weekStart(containing: month.start, weekCalendar: weekCalendar) ?? month.start
        var index = 0

        while cursor < month.end {
            guard let next = weekCalendar.date(byAdding: .day, value: 7, to: cursor),
                  next > cursor
            else { break }

            let thursday = calendar.date(byAdding: .day, value: 3, to: cursor) ?? cursor
            if thursday >= month.start, thursday < month.end {
                weeks.append(
                    buildWeek(
                        index: index,
                        start: cursor,
                        endExclusive: next,
                        goal: goals.goal(forWeekStarting: cursor, liveWeekStart: liveWeekStart, calendar: calendar),
                        trainingDays: trainingDays,
                        outcomesByDay: outcomesByDay,
                        today: today,
                        calendar: calendar
                    )
                )
                index += 1
            }
            cursor = next
        }

        let total = weeks.reduce(into: ProgressTally()) { $0 = $0 + $1.tally }

        return ProgressMonthSummary(
            monthStart: month.start,
            isCurrentMonth: isCurrentMonth,
            isLive: weeks.contains(where: \.isLive),
            weeks: weeks,
            tally: total,
            titleLabel: isCurrentMonth ? "This Month" : month.start.formatted(.dateTime.month(.wide)),
            subtitleLabel: month.start.formatted(.dateTime.month(.wide).year())
        )
    }

    /// The months worth offering: back as far as the record goes, and one
    /// month ahead when a plan exists to fill it.
    static func monthBounds(
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (earliest: Date, latest: Date) {
        let today = calendar.startOfDay(for: now)
        let thisMonth = monthStart(forWeekContaining: today, calendar: calendar)

        let earliestRecord = log.outcomes.map { $0.countingDay(calendar: calendar) }.min()
        let earliest = earliestRecord
            .map { monthStart(forWeekContaining: $0, calendar: calendar) }
            .map { min($0, thisMonth) } ?? thisMonth

        let hasPlan = !plan.effectiveTrainingDays(fallback: schedule).isEmpty
        let latest = hasPlan
            ? (calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth)
            : thisMonth

        return (earliest, latest)
    }

    /// Tallies an arbitrary span of days, day by day.
    ///
    /// Used by the share frames' rolling "showed up" figure, which is about
    /// days rather than weeks, so it carries no goal.
    static func tally(
        in interval: DateInterval,
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgressTally {
        let outcomesByDay = Dictionary(grouping: log.outcomes) {
            $0.countingDay(calendar: calendar)
        }
        return buildDays(
            start: interval.start,
            endExclusive: interval.end,
            trainingDays: plan.effectiveTrainingDays(fallback: schedule),
            outcomesByDay: outcomesByDay,
            today: calendar.startOfDay(for: now),
            calendar: calendar
        ).tally
    }

    // MARK: Week

    private static func buildWeek(
        index: Int,
        start: Date,
        endExclusive: Date,
        goal: Int,
        trainingDays: Set<Weekday>,
        outcomesByDay: [Date: [SessionOutcome]],
        today: Date,
        calendar: Calendar
    ) -> ProgressWeekSummary {
        let isFinished = endExclusive <= today
        let isCurrent = !isFinished && start <= today

        // Which weekdays a finished week planned isn't recorded (only its
        // goal is), so its quiet days are drawn as quiet, not as planned.
        let built = buildDays(
            start: start,
            endExclusive: endExclusive,
            trainingDays: isFinished ? [] : trainingDays,
            outcomesByDay: outcomesByDay,
            today: today,
            calendar: calendar
        )

        let days = built.tally
        let completed = days.completed
        let shortfall = max(0, goal - completed)

        var tally = days
        tally.goal = goal
        tally.credited = min(completed, goal)
        tally.slots = max(goal, completed)
        // A finished week short of its goal missed the difference. A live
        // week shows only the misses already recorded; the rest are still
        // possible. A future week has missed nothing.
        tally.missed = isFinished ? shortfall : (isCurrent ? min(days.missed, shortfall) : 0)
        tally.weeksWithGoal = goal > 0 ? 1 : 0
        tally.weeksKept = goal > 0 && completed >= goal ? 1 : 0

        return ProgressWeekSummary(
            index: index,
            start: calendar.startOfDay(for: start),
            end: built.lastDay,
            days: built.days,
            tally: tally,
            isLive: !isFinished,
            isCurrent: isCurrent,
            rangeLabel: rangeLabel(start: start, end: built.lastDay, calendar: calendar)
        )
    }

    private static func buildDays(
        start: Date,
        endExclusive: Date,
        trainingDays: Set<Weekday>,
        outcomesByDay: [Date: [SessionOutcome]],
        today: Date,
        calendar: Calendar
    ) -> (days: [ProgressDay], tally: ProgressTally, lastDay: Date) {
        var days: [ProgressDay] = []
        var tally = ProgressTally()

        var day = calendar.startOfDay(for: start)
        var lastDay = day

        // Stepped with Calendar rather than 24-hour arithmetic so daylight
        // saving and timezone changes cannot shift a day.
        while day < endExclusive {
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))
            let isPlanned = weekday.map { trainingDays.contains($0) } ?? false
            let status = self.status(
                day: day,
                isPlanned: isPlanned,
                today: today,
                outcomes: outcomesByDay[day]
            )

            switch status {
            case .gymVerified: tally.verifiedGym += 1
            case .quickWorkoutVerified: tally.quickWorkout += 1
            case .missed: tally.missed += 1
            case .excused: tally.excused += 1
            case .unresolved: tally.unresolved += 1
            case .upcoming: tally.upcoming += 1
            case .rest: break
            }

            if isPlanned || status.countsAsCompleted {
                tally.slots += 1
            }

            days.append(
                ProgressDay(
                    date: day,
                    status: status,
                    isPlanned: isPlanned,
                    isToday: day == today,
                    weekdayLabel: day.formatted(.dateTime.weekday(.abbreviated)),
                    dateLabel: day.formatted(.dateTime.month(.abbreviated).day())
                )
            )

            lastDay = day
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }

        return (days, tally, lastDay)
    }

    /// The one place a day's outcome is interpreted, by the streak's rule:
    /// a day counts when an outcome on it `counts` (FLOW, Flows 3 and 4).
    /// Several outcomes on one day resolve to a single status.
    private static func status(
        day: Date,
        isPlanned: Bool,
        today: Date,
        outcomes: [SessionOutcome]?
    ) -> ProgressDayStatus {
        if let outcomes, !outcomes.isEmpty {
            if outcomes.contains(where: \.isVerifiedWorkout) { return .gymVerified }
            if outcomes.contains(where: { $0.kind == .homeWorkout && $0.counts }) { return .quickWorkoutVerified }
            if outcomes.contains(where: { $0.kind == .missed }) { return .missed }
            if isPlanned, day >= today { return .upcoming }
            return .excused
        }

        if !isPlanned { return .rest }
        if day >= today { return .upcoming }
        return .unresolved
    }

    /// "Nov 9–15", or "Nov 30–Dec 6" across months.
    private static func rangeLabel(start: Date, end: Date, calendar: Calendar) -> String {
        let startLabel = start.formatted(.dateTime.month(.abbreviated).day())
        guard !calendar.isDate(start, inSameDayAs: end) else { return startLabel }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(startLabel)–\(calendar.component(.day, from: end))"
        }
        return "\(startLabel)–\(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
