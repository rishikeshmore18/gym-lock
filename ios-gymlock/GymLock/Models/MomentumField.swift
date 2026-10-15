import Foundation

/// What one day contributed to the week.
///
/// The distinction between `verified` and `preserved` is deliberate and is never
/// blurred: one of them is a trip to the gym, the other is a home session that
/// kept momentum alive. Both count toward the week's goal, exactly as the
/// streak counts them; only one of them is a trip to the gym, and the card
/// says so beside the number.
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
    /// Verified gym workouts inside this week.
    var verifiedCount: Int
    /// Counted home workouts inside this week, named beside the number so
    /// it is always clear where the counted days came from.
    var preservedCount: Int
    /// Distinct counted workout days this week: `StreakEngine.sessionDays`,
    /// the same number the streak judges the week by. Gym or home, each day
    /// once; an arrival without a finished workout is not in it.
    var countedCount: Int
    /// This week's goal, as saved when the week started
    /// (`StreakSnapshot.weeklyGoal`) — the denominator. It never grows to
    /// hold extra workouts; the commitment is what was planned.
    var targetCount: Int
    /// False when no training days are configured, which is the one case where
    /// there is no honest fraction to show.
    var hasSchedule: Bool

    static let empty = MomentumField(
        days: [],
        verifiedCount: 0,
        preservedCount: 0,
        countedCount: 0,
        targetCount: 0,
        hasSchedule: false
    )

    // MARK: Derived copy

    /// Counted stages on the card: never more than the goal. Extra workouts
    /// are not drawn.
    var completedStages: Int {
        min(max(countedCount, 0), max(targetCount, 0))
    }

    /// The headline metric: counted workout days against this week's goal.
    var summaryValue: String {
        guard hasSchedule, targetCount > 0 else { return "—" }
        return "\(countedCount)/\(targetCount)"
    }

    var caption: String {
        hasSchedule && targetCount > 0 ? "THIS WEEK" : "NO DAYS SET"
    }

    /// How many of the counted days were home workouts.
    var homeNote: String? {
        guard preservedCount > 0 else { return nil }
        return preservedCount == 1 ? "+1 at home" : "+\(preservedCount) at home"
    }

    var accessibilityText: String {
        guard hasSchedule, targetCount > 0 else {
            return "Momentum. No training days set yet."
        }
        var text = "Momentum. \(countedCount) of \(targetCount) workout days this week."
        if preservedCount > 0 {
            text += " \(preservedCount) of them at home."
        }
        return text
    }

    // MARK: Building

    /// Builds the current week from the ledger, the user's plan and this
    /// week's saved goal.
    ///
    /// `weeklyGoal` is `StreakSnapshot.weeklyGoal`: the card's denominator is
    /// the streak's, never a second number derived here. The week is
    /// Monday-first regardless of locale so the field lines up with the
    /// schedule selector the user configured.
    static func build(
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        weeklyGoal: Int,
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

        let byDay = Dictionary(grouping: log.outcomes) { $0.countingDay(calendar: calendar) }

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

        // The one definition of a counted day, shared with the streak.
        let counted = StreakEngine.sessionDays(in: log, weekStarting: week.start, calendar: calendar).count

        return MomentumField(
            days: days,
            verifiedCount: verified,
            preservedCount: preserved,
            countedCount: counted,
            targetCount: trainingDays.isEmpty ? 0 : max(weeklyGoal, 1),
            hasSchedule: !trainingDays.isEmpty
        )
    }

    /// The best thing a single day can honestly be said to have been.
    private static func dominantMark(_ outcomes: [SessionOutcome]) -> MomentumMark {
        // Verified means the workout was done; a gym visit alone is not. A
        // home workout is preserved once it counts, by the same rule the
        // streak applies.
        if outcomes.contains(where: \.isVerifiedWorkout) { return .verified }
        if outcomes.contains(where: { $0.kind == .homeWorkout && $0.counts }) { return .preserved }
        if outcomes.contains(where: { $0.kind == .missed }) { return .missed }
        return .excused
    }
}
