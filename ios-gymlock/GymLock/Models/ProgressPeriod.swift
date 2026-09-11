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
    /// The 20-minute home fallback. Keeps the commitment; is not a gym visit.
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
        case .quickWorkoutVerified: return "\(day). Verified 20-minute workout."
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
struct ProgressTally: Hashable {
    var verifiedGym = 0
    var quickWorkout = 0
    var missed = 0
    var excused = 0
    var unresolved = 0
    var upcoming = 0
    /// Session slots in the period: every planned day, plus any day the user
    /// trained without having planned it, so a fraction can never exceed one.
    var slots = 0

    /// A quick workout counts here. It never counts as a gym visit.
    var completed: Int { verifiedGym + quickWorkout }

    /// Sessions the user genuinely had the chance to complete, and which
    /// resolved. Excludes upcoming (not yet due), unresolved (never recorded)
    /// and excused (deliberately set aside).
    var due: Int { completed + missed }

    /// Completion against what was due. `nil` when nothing was due, which is
    /// the one case where there is no honest percentage — never 0%.
    var completionRate: Double? {
        guard due > 0 else { return nil }
        return Double(completed) / Double(due)
    }

    var hasPlan: Bool { slots > 0 }

    /// Slots with no outcome drawn on them: upcoming, unresolved and excused.
    var ghost: Int { max(0, slots - completed - missed) }

    static func + (lhs: ProgressTally, rhs: ProgressTally) -> ProgressTally {
        ProgressTally(
            verifiedGym: lhs.verifiedGym + rhs.verifiedGym,
            quickWorkout: lhs.quickWorkout + rhs.quickWorkout,
            missed: lhs.missed + rhs.missed,
            excused: lhs.excused + rhs.excused,
            unresolved: lhs.unresolved + rhs.unresolved,
            upcoming: lhs.upcoming + rhs.upcoming,
            slots: lhs.slots + rhs.slots
        )
    }
}

// MARK: - Shared headline copy

/// How a period presents its own numbers.
///
/// Live and finished periods are measured differently, and this is where that
/// rule lives so no view has to reimplement it:
///
/// - A **finished** period is `completed / slots` — everything that was planned
///   had its chance.
/// - A **live** period is `completed / due`, so the sessions still ahead are
///   visible in the chart without dragging the percentage down.
protocol ProgressPeriodPresentation {
    var tally: ProgressTally { get }
    /// True when the period contains today or lies in the future.
    var isLive: Bool { get }
}

extension ProgressPeriodPresentation {
    /// Denominator of the headline fraction.
    var headlineTotal: Int {
        isLive ? max(tally.due, tally.completed) : tally.slots
    }

    /// 0...1, or `nil` when nothing has been due yet.
    var completionFraction: Double? {
        guard headlineTotal > 0 else { return nil }
        return min(1, Double(tally.completed) / Double(headlineTotal))
    }

    /// "9/12", or the plan size when nothing is due yet.
    var fractionText: String {
        guard tally.hasPlan else { return "—" }
        guard headlineTotal > 0 else { return "\(tally.slots)" }
        return "\(tally.completed)/\(headlineTotal)"
    }

    /// Caption under the fraction inside the ring.
    var fractionCaption: String {
        guard tally.hasPlan else { return "no plan" }
        return headlineTotal > 0 ? "workouts" : "planned"
    }

    /// "75%", or an em dash when there is no honest percentage.
    var percentText: String {
        guard let fraction = completionFraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    var percentCaption: String {
        guard tally.hasPlan else { return "nothing planned" }
        guard completionFraction != nil else { return "nothing due yet" }
        return isLive ? "of sessions due" : "completion"
    }

    /// The wider plan, shown only when it differs from the headline
    /// denominator — so a live period can say "3 of 4 due" without hiding that
    /// twelve were planned.
    var planNote: String? {
        guard isLive, tally.hasPlan, tally.slots > headlineTotal else { return nil }
        return "\(tally.slots) planned in total"
    }
}

// MARK: - Week

/// One week group inside a month, clipped to that month.
///
/// The clipping is deliberate: the bar is labelled with real dates ("Sep 1–6"),
/// so it may only ever contain days that belong to the month on screen.
struct ProgressWeekSummary: Identifiable, Hashable, ProgressPeriodPresentation {
    /// Position in the month. Stable identity for the expand transition.
    let index: Int
    /// First day shown, clipped to the month.
    let start: Date
    /// Last day shown, inclusive.
    let end: Date
    let days: [ProgressDay]
    let tally: ProgressTally
    let isLive: Bool
    /// "Sep 1–6".
    let rangeLabel: String

    var id: Int { index }

    /// Compact label above the bar, e.g. "3/3".
    var stackCountLabel: String? {
        guard tally.hasPlan, headlineTotal > 0 else { return nil }
        return "\(tally.completed)/\(headlineTotal)"
    }

    var accessibilityText: String {
        guard tally.hasPlan else {
            return "\(rangeLabel). No sessions planned."
        }

        var parts = ["\(rangeLabel).", "\(tally.slots) planned."]
        if tally.verifiedGym > 0 {
            parts.append("\(tally.verifiedGym) gym \(tally.verifiedGym == 1 ? "workout" : "workouts").")
        }
        if tally.quickWorkout > 0 {
            parts.append("\(tally.quickWorkout) quick \(tally.quickWorkout == 1 ? "workout" : "workouts").")
        }
        if tally.missed > 0 {
            parts.append("\(tally.missed) missed.")
        }
        if tally.upcoming > 0 {
            parts.append("\(tally.upcoming) upcoming.")
        }
        if let fraction = completionFraction {
            parts.append("\(Int((fraction * 100).rounded())) percent completed.")
        }
        return parts.joined(separator: " ")
    }

    /// Headline under the date in the expanded card.
    var detailHeadline: String {
        guard tally.hasPlan else { return "No sessions planned" }
        guard headlineTotal > 0 else {
            return "\(tally.slots) planned"
        }
        let suffix = isLive ? "due completed" : "completed"
        return "\(tally.completed) of \(headlineTotal) \(suffix) · \(percentText)"
    }
}

// MARK: - Month

/// One month of follow-through, as the card needs it.
struct ProgressMonthSummary: Hashable, ProgressPeriodPresentation {
    /// First day of the month.
    let monthStart: Date
    let isCurrentMonth: Bool
    let isLive: Bool
    let weeks: [ProgressWeekSummary]
    let tally: ProgressTally
    /// "This Month", or the month's own name when looking back.
    let titleLabel: String
    /// "September 2026".
    let subtitleLabel: String

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
/// Pure functions over `MomentumLog` and `MorningPlan`: no storage of its own,
/// no second history system, no Health queries, no timers. Cheap enough to run
/// on demand — one pass over a bounded outcome list plus at most 42 days.
struct ProgressAnalytics {
    /// Weeks are Monday-first regardless of locale, matching the schedule
    /// selector the user configured and the momentum week on Home.
    static func displayCalendar(_ calendar: Calendar = .current) -> Calendar {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        return weekCalendar
    }

    /// Builds the month containing `date`.
    static func monthSummary(
        containing date: Date,
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgressMonthSummary {
        let weekCalendar = displayCalendar(calendar)
        let today = calendar.startOfDay(for: now)

        guard let month = calendar.dateInterval(of: .month, for: date) else {
            return .empty(monthStart: calendar.startOfDay(for: date), isCurrentMonth: false)
        }

        let isCurrentMonth = calendar.isDate(month.start, equalTo: today, toGranularity: .month)
        let trainingDays = plan.effectiveTrainingDays(fallback: schedule)

        // Grouped once for the whole month rather than scanned per day.
        let outcomesByDay = Dictionary(grouping: log.outcomes) {
            calendar.startOfDay(for: $0.date)
        }

        var weeks: [ProgressWeekSummary] = []
        var cursor = weekCalendar.dateInterval(of: .weekOfYear, for: month.start)?.start ?? month.start
        var index = 0

        while cursor < month.end {
            guard let weekEnd = weekCalendar.date(byAdding: .day, value: 7, to: cursor),
                  weekEnd > cursor
            else { break }

            let clippedStart = max(cursor, month.start)
            let clippedEnd = min(weekEnd, month.end)

            if clippedStart < clippedEnd {
                weeks.append(
                    buildWeek(
                        index: index,
                        start: clippedStart,
                        endExclusive: clippedEnd,
                        trainingDays: trainingDays,
                        outcomesByDay: outcomesByDay,
                        today: today,
                        calendar: calendar
                    )
                )
                index += 1
            }

            cursor = weekEnd
        }

        let total = weeks.reduce(into: ProgressTally()) { $0 = $0 + $1.tally }

        return ProgressMonthSummary(
            monthStart: month.start,
            isCurrentMonth: isCurrentMonth,
            isLive: month.end > today,
            weeks: weeks,
            tally: total,
            titleLabel: isCurrentMonth ? "This Month" : month.start.formatted(.dateTime.month(.wide)),
            subtitleLabel: month.start.formatted(.dateTime.month(.wide).year())
        )
    }

    /// The months worth offering.
    ///
    /// Back as far as the record goes, and at most one month ahead — and only
    /// when a plan exists to fill it. Endless empty future months are not
    /// navigation, they are noise.
    static func monthBounds(
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (earliest: Date, latest: Date) {
        let today = calendar.startOfDay(for: now)
        let thisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today

        let earliestRecord = log.outcomes.map(\.date).min()
        let earliest = earliestRecord
            .flatMap { calendar.dateInterval(of: .month, for: $0)?.start }
            .map { min($0, thisMonth) } ?? thisMonth

        let hasPlan = !plan.effectiveTrainingDays(fallback: schedule).isEmpty
        let latest = hasPlan
            ? (calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth)
            : thisMonth

        return (earliest, latest)
    }

    // MARK: Week

    private static func buildWeek(
        index: Int,
        start: Date,
        endExclusive: Date,
        trainingDays: Set<Weekday>,
        outcomesByDay: [Date: [SessionOutcome]],
        today: Date,
        calendar: Calendar
    ) -> ProgressWeekSummary {
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

            // Every planned day is a slot. A session the user completed on a
            // day they had not planned earns its own slot, so the fraction
            // grows rather than exceeding one.
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

        return ProgressWeekSummary(
            index: index,
            start: calendar.startOfDay(for: start),
            end: lastDay,
            days: days,
            tally: tally,
            isLive: endExclusive > today,
            rangeLabel: rangeLabel(start: start, end: lastDay, calendar: calendar)
        )
    }

    /// The one place a day's outcome is interpreted.
    ///
    /// Mirrors the ledger's own rules. Several outcomes on one day resolve to a
    /// single status — one commitment resolves once, so a day can never count
    /// twice no matter how many Health workouts land on it.
    private static func status(
        day: Date,
        isPlanned: Bool,
        today: Date,
        outcomes: [SessionOutcome]?
    ) -> ProgressDayStatus {
        if let outcomes, !outcomes.isEmpty {
            if outcomes.contains(where: { $0.kind == .showedUp }) { return .gymVerified }
            if outcomes.contains(where: { $0.kind == .homeWorkout }) { return .quickWorkoutVerified }
            if outcomes.contains(where: { $0.kind == .missed }) { return .missed }
            return .excused
        }

        if !isPlanned { return .rest }
        // Today has not run out of time yet, and tomorrow certainly has not.
        if day >= today { return .upcoming }
        return .unresolved
    }

    /// "Sep 1–6", or "Sep 1" for a single day. Always inside one month.
    private static func rangeLabel(start: Date, end: Date, calendar: Calendar) -> String {
        let startLabel = start.formatted(.dateTime.month(.abbreviated).day())
        guard !calendar.isDate(start, inSameDayAs: end) else { return startLabel }
        return "\(startLabel)–\(calendar.component(.day, from: end))"
    }
}
