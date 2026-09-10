import Foundation

/// What one day contributed to the week.
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
    /// A training day still ahead, including today before it resolves.
    case planned
    /// A training day that has passed with nothing recorded. Drawn as an open
    /// ring, never as a miss: no record is not evidence of a failure.
    case unresolved
    /// Not a training day. Drawn as a whisper so the week keeps its rhythm
    /// without implying anything was expected.
    case rest
}

/// One column of the week.
struct MomentumDay: Equatable, Identifiable {
    var id: Int { column }
    /// 0 = Monday.
    var column: Int
    /// Three-letter header, e.g. "Mon".
    var label: String
    var mark: MomentumMark
    var isToday: Bool
}

/// The current week's record.
///
/// This is the proof layer of home. It answers a different question from the
/// cards above it — not "what do I do now" but "am I actually doing this" — and
/// it is built entirely from recorded outcomes and the user's own schedule.
/// Nothing here is estimated, and no day is ever drawn as a miss unless a miss
/// was recorded.
struct MomentumField: Equatable {
    /// Exactly seven days, Monday-first.
    var days: [MomentumDay]
    /// Verified gym visits inside this week.
    var verifiedCount: Int
    /// Home sessions inside this week, reported separately and never folded
    /// into the headline number.
    var preservedCount: Int
    /// Sessions the user planned for this week — the denominator.
    var targetCount: Int
    /// False when no training days are configured, which is the one case where
    /// there is no honest fraction to show.
    var hasSchedule: Bool

    static let empty = MomentumField(
        days: [],
        verifiedCount: 0,
        preservedCount: 0,
        targetCount: 0,
        hasSchedule: false
    )

    // MARK: Derived copy

    /// The headline metric: gym visits against sessions planned this week.
    var summaryValue: String {
        guard hasSchedule, targetCount > 0 else { return "—" }
        return "\(verifiedCount)/\(targetCount)"
    }

    var caption: String {
        hasSchedule && targetCount > 0 ? "THIS WEEK" : "NO DAYS SET"
    }

    /// Home sessions get their own line rather than inflating the fraction.
    var homeNote: String? {
        guard preservedCount > 0 else { return nil }
        return preservedCount == 1 ? "+1 at home" : "+\(preservedCount) at home"
    }

    var accessibilityText: String {
        guard hasSchedule, targetCount > 0 else {
            return "Momentum. No training days set yet."
        }
        var text = "Momentum. \(verifiedCount) of \(targetCount) planned gym sessions this week."
        if preservedCount > 0 {
            text += " Plus \(preservedCount) kept at home."
        }
        return text
    }

    // MARK: Building

    /// Builds the current week from the ledger and the user's plan.
    ///
    /// The week is Monday-first regardless of locale so the field lines up with
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

        guard let week = mondayFirst.dateInterval(of: .weekOfYear, for: today) else {
            return .empty
        }

        // The plan is the source of truth for training days; the schedule is
        // only a fallback for users who have not built a plan yet.
        var trainingDays = plan.enabledSlots.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }
        if trainingDays.isEmpty { trainingDays = schedule.trainingDays }

        let byDay = Dictionary(grouping: log.outcomes) { calendar.startOfDay(for: $0.date) }

        var days: [MomentumDay] = []
        var verified = 0
        var preserved = 0

        for column in 0..<7 {
            guard let day = mondayFirst.date(byAdding: .day, value: column, to: week.start) else {
                continue
            }

            let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))
            let isTrainingDay = weekday.map { trainingDays.contains($0) } ?? false
            let isToday = calendar.isDate(day, inSameDayAs: today)

            let mark: MomentumMark
            if let outcomes = byDay[day], !outcomes.isEmpty {
                mark = dominantMark(outcomes)
                if mark == .verified { verified += 1 }
                if mark == .preserved { preserved += 1 }
            } else if !isTrainingDay {
                mark = .rest
            } else if day >= today {
                mark = .planned
            } else {
                // A past training day with nothing recorded. Either the ledger
                // had not begun or the morning was never resolved — neither is
                // evidence of a miss, so it stays open rather than broken.
                mark = .unresolved
            }

            days.append(
                MomentumDay(
                    column: column,
                    label: weekday?.shortLabel ?? "",
                    mark: mark,
                    isToday: isToday
                )
            )
        }

        return MomentumField(
            days: days,
            verifiedCount: verified,
            preservedCount: preserved,
            // A gym visit on an unplanned day still counts, so the denominator
            // grows to hold it rather than the fraction going above one.
            targetCount: max(trainingDays.count, verified),
            hasSchedule: !trainingDays.isEmpty
        )
    }

    /// The best thing a single day can honestly be said to have been.
    private static func dominantMark(_ outcomes: [SessionOutcome]) -> MomentumMark {
        if outcomes.contains(where: { $0.kind == .showedUp }) { return .verified }
        if outcomes.contains(where: { $0.kind == .homeWorkout }) { return .preserved }
        if outcomes.contains(where: { $0.kind == .missed }) { return .missed }
        return .excused
    }
}
