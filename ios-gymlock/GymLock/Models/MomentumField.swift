import Foundation

/// What one day contributed to the record.
///
/// The distinction between `verified` and `preserved` is deliberate and is never
/// blurred: one of them is a trip to the gym, the other is a home session that
/// kept momentum alive. Both are worth drawing; only one of them counts as
/// showing up.
enum MomentumMark: Equatable {
    /// Confirmed arrival at the gym.
    case verified
    /// Momentum kept without a gym visit.
    case preserved
    /// A session came due and did not happen.
    case missed
    /// Skipped or rescheduled on purpose, or a technical failure. Neither
    /// credited nor punished.
    case excused
    /// A training day still ahead.
    case planned
    /// Not a training day, or before the record began. Drawn as a whisper so
    /// the field keeps its rhythm without implying anything happened.
    case blank
}

/// Four weeks of the user's record, as marks.
///
/// This is the accumulated-proof layer of home. It answers a different question
/// from the cards above it — not "what do I do now" but "am I becoming someone
/// who shows up" — and it is built entirely from recorded outcomes. A day with
/// nothing recorded stays blank: an unrecorded day is not evidence of a miss,
/// and the app never draws one as if it were.
struct MomentumField: Equatable {
    /// Four weeks, oldest first, each exactly seven days Monday-first.
    var weeks: [[MomentumMark]]
    /// Single-letter column headers, Monday-first.
    var weekdayLabels: [String]
    /// Where today sits in the field, so it can be marked without being counted
    /// as anything yet.
    var todayRow: Int
    var todayColumn: Int

    var verifiedCount: Int
    var preservedCount: Int
    /// Days in the window that actually resolved, one way or another.
    var dueCount: Int
    var hasHistory: Bool
    /// Shown in place of the metric until there is a record to show.
    var emptyMessage: String

    static let empty = MomentumField(
        weeks: [],
        weekdayLabels: [],
        todayRow: 0,
        todayColumn: 0,
        verifiedCount: 0,
        preservedCount: 0,
        dueCount: 0,
        hasHistory: false,
        emptyMessage: "Your record starts with your first session."
    )

    // MARK: Derived copy

    /// The headline metric, or nil while there is nothing honest to count.
    var summaryValue: String? {
        guard hasHistory, dueCount > 0 else { return nil }
        return "\(verifiedCount) / \(dueCount)"
    }

    var summaryLabel: String { "showed up" }

    /// Home sessions, reported separately rather than folded into the metric.
    var preservedNote: String? {
        guard preservedCount > 0 else { return nil }
        return preservedCount == 1 ? "+1 kept at home" : "+\(preservedCount) kept at home"
    }

    // MARK: Building

    /// Builds the trailing four weeks from the ledger.
    ///
    /// Weeks are Monday-first regardless of locale so the field lines up with
    /// the schedule selector the user configured.
    static func build(
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MomentumField {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2

        let today = calendar.startOfDay(for: now)

        guard let thisWeek = mondayFirst.dateInterval(of: .weekOfYear, for: today),
              let start = mondayFirst.date(byAdding: .day, value: -21, to: thisWeek.start)
        else { return .empty }

        var trainingDays = plan.enabledSlots.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }
        if trainingDays.isEmpty { trainingDays = schedule.trainingDays }

        let byDay = Dictionary(grouping: log.outcomes) { calendar.startOfDay(for: $0.date) }

        var weeks: [[MomentumMark]] = []
        var todayRow = 3
        var todayColumn = 0
        var verified = 0
        var preserved = 0
        var due = 0

        for week in 0..<4 {
            var row: [MomentumMark] = []

            for column in 0..<7 {
                guard let day = mondayFirst.date(
                    byAdding: .day,
                    value: week * 7 + column,
                    to: start
                ) else {
                    row.append(.blank)
                    continue
                }

                if calendar.isDate(day, inSameDayAs: today) {
                    todayRow = week
                    todayColumn = column
                }

                let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))
                let isTrainingDay = weekday.map { trainingDays.contains($0) } ?? false

                if let outcomes = byDay[day], !outcomes.isEmpty {
                    let mark = dominantMark(outcomes)
                    row.append(mark)
                    due += 1
                    if mark == .verified { verified += 1 }
                    if mark == .preserved { preserved += 1 }
                } else if day >= today {
                    row.append(isTrainingDay ? .planned : .blank)
                } else {
                    // A past day with nothing recorded. Either the ledger had
                    // not begun or the session was never resolved — neither is
                    // evidence of a miss, so it stays blank.
                    row.append(.blank)
                }
            }

            weeks.append(row)
        }

        return MomentumField(
            weeks: weeks,
            weekdayLabels: Weekday.allCases.map { String($0.shortLabel.prefix(1)) },
            todayRow: todayRow,
            todayColumn: todayColumn,
            verifiedCount: verified,
            preservedCount: preserved,
            dueCount: due,
            hasHistory: !log.outcomes.isEmpty,
            emptyMessage: startMessage(plan: plan, now: now, calendar: calendar)
        )
    }

    /// The best thing a single day can be said to have been.
    private static func dominantMark(_ outcomes: [SessionOutcome]) -> MomentumMark {
        if outcomes.contains(where: { $0.kind == .showedUp }) { return .verified }
        if outcomes.contains(where: { $0.kind == .homeWorkout }) { return .preserved }
        if outcomes.contains(where: { $0.kind == .missed }) { return .missed }
        return .excused
    }

    private static func startMessage(
        plan: MorningPlan,
        now: Date,
        calendar: Calendar
    ) -> String {
        guard let next = plan.nextOccurrence(after: now, calendar: calendar) else {
            return "Your record starts with your first session."
        }
        if calendar.isDateInToday(next.fireDate) { return "Your record starts today." }
        if calendar.isDateInTomorrow(next.fireDate) { return "Your record starts tomorrow." }

        let index = calendar.component(.weekday, from: next.fireDate) - 1
        guard calendar.weekdaySymbols.indices.contains(index) else {
            return "Your record starts with your first session."
        }
        return "Your record starts \(calendar.weekdaySymbols[index])."
    }
}
