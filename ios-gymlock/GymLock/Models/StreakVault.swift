import Foundation

/// The rules of the streak, in one place.
///
/// Every number here is a product decision rather than a measurement, and
/// keeping them together is what stops the card, the share frames and the
/// tests each quietly assuming a different goal.
nonisolated enum StreakPolicy {
    /// The most freezes a user can hold at once.
    static let maximumFreezes = 2
    /// Nobody can plan fewer gym days than this. A validation floor, not a
    /// goal: the goal is the plan itself (`weeklyGoal(plannedDays:)`).
    static let minimumGymDays = 3
    /// The note shown when a gym day can't come off (FLOW, "Which nights").
    static let minimumGymDaysMessage = "3 gym days is the minimum."
    /// The goal rule the vault was last evaluated under (FLOW, item 19a):
    /// 1 = the goal is the plan, and the live week follows plan changes at
    /// once. Bump when the rule changes again.
    static let currentGoalRule = 1

    /// The one weekly goal (FLOW, item 19a): the number of workout days
    /// planned for the week. Valid plans hold 3 to 7 days, so this normally
    /// equals the plan; the floor only catches a legacy plan still below 3.
    static func weeklyGoal(plannedDays: Int) -> Int {
        max(minimumGymDays, plannedDays)
    }

    /// The rule weeks were judged by before the 3-day minimum existed: three,
    /// but never more than the plan, floored at one.
    ///
    /// Only used to backfill the goal of weeks that started before
    /// `StreakVault.threeDayRuleStart`, so no existing user sees a past week
    /// change. Never used for a week on or after it.
    static func legacyWeeklyGoal(plannedDays: Int) -> Int {
        max(1, min(minimumGymDays, plannedDays))
    }

    /// The goal a week gets the first time the engine sees it.
    ///
    /// On or after the rule start it is the plan (`weeklyGoal(plannedDays:)`).
    /// Before it, the legacy rule with the plan as it is when the goal is
    /// saved, so history is never re-judged.
    static func goal(
        forWeekStarting weekStart: Date,
        ruleStart: Date,
        plannedDays: Int,
        calendar: Calendar
    ) -> Int {
        let isCovered = calendar.compare(weekStart, to: ruleStart, toGranularity: .day) != .orderedAscending
        return isCovered ? weeklyGoal(plannedDays: plannedDays) : legacyWeeklyGoal(plannedDays: plannedDays)
    }

    /// Whether an existing user should be asked to add a gym day on open.
    ///
    /// Only for 1 or 2 days, the case FLOW names. Zero means no alarm at all,
    /// which is a different situation.
    static func asksToAddGymDay(plannedGymDays: Int) -> Bool {
        (1..<minimumGymDays).contains(plannedGymDays)
    }
}

/// What the streak remembers between evaluations.
///
/// The streak *count* is never stored — it is re-derived from the ledger every
/// time, so it cannot drift from the outcomes that justify it. Only the things
/// that cannot be re-derived live here: which weeks were protected by a
/// freeze, how many freezes are banked, and how far the evaluation has got.
nonisolated struct StreakVault: Codable, Hashable {
    var freezesAvailable: Int
    /// Start-of-week dates of every week a freeze protected.
    var frozenWeekStarts: Set<Date>
    /// The live week the user chose to protect in advance, if any.
    var preArmedWeekStart: Date?
    /// The most recent *completed* week the vault has already ruled on.
    ///
    /// Freezes are only ever spent on weeks newer than this. Without it a
    /// relaunch would walk the whole history again and spend today's freezes
    /// on a bad week from three months ago.
    var lastEvaluatedWeekStart: Date?
    /// Left over from when a freeze was earned every 4 kept weeks. Nothing
    /// reads or earns from it any more; it stays so old vaults round-trip.
    var kept4Counter: Int
    /// Each week's goal, keyed by the week's Monday. The live week's entry is
    /// re-saved from the plan on every evaluation, so it always matches the
    /// gym days on the alarm screen; once the week has ended its entry is the
    /// only thing it is judged by, so a plan change can never rewrite it.
    var weekGoals: [Date: Int] = [:]
    /// Monday of the first week the 3-day minimum applied to. Set once and
    /// never moved: next Monday for a user who already had history when that
    /// rule arrived, their first week for everyone else. Only decides which
    /// weeks are backfilled by the legacy rule; nothing newer reads it.
    var threeDayRuleStart: Date?
    /// Which goal rule the vault was last evaluated under
    /// (`StreakPolicy.currentGoalRule`). Nil on vaults saved under the fixed-3
    /// rule. Informational: the live week is brought in line with the plan on
    /// every evaluation regardless.
    var goalRule: Int?
    /// How far the freeze calendar has been settled (FLOW, Flow 5): every
    /// grant and every Dec 31 expiry up to this moment has been applied, and
    /// none after it. Nil on vaults saved before the calendar existed; the
    /// first evaluation sets it to "now", so nothing from the past is granted
    /// and the freezes already held are kept.
    var freezeClock: Date?
    /// The calendar year the freezes held belong to. They expire when the
    /// year ends.
    var freezeYear: Int?

    enum CodingKeys: String, CodingKey {
        case freezesAvailable, frozenWeekStarts, preArmedWeekStart
        case lastEvaluatedWeekStart, kept4Counter, weekGoals, threeDayRuleStart
        case freezeClock, freezeYear, goalRule
    }

    static let empty = StreakVault(
        freezesAvailable: 0,
        frozenWeekStarts: [],
        preArmedWeekStart: nil,
        lastEvaluatedWeekStart: nil,
        kept4Counter: 0
    )

    /// True until the first evaluation on the week-based logic has run.
    var needsMigration: Bool { lastEvaluatedWeekStart == nil }

    /// Whether a week is protected, tolerant of the stored date and the
    /// computed one differing by a timezone's worth of seconds.
    func isFrozen(weekStarting start: Date, calendar: Calendar) -> Bool {
        frozenWeekStarts.contains { calendar.isDate($0, inSameDayAs: start) }
    }

    func isPreArmed(weekStarting start: Date, calendar: Calendar) -> Bool {
        guard let preArmedWeekStart else { return false }
        return calendar.isDate(preArmedWeekStart, inSameDayAs: start)
    }

    /// The saved goal for a week, tolerant of the stored key and the computed
    /// Monday differing by a timezone's worth of seconds.
    func savedGoal(forWeekStarting start: Date, calendar: Calendar) -> Int? {
        if let exact = weekGoals[start] { return exact }
        return weekGoals.first { calendar.isDate($0.key, inSameDayAs: start) }?.value
    }
}

extension StreakVault {
    /// Vaults saved before week goals existed decode with none saved and no
    /// rule start, which the engine treats as the first run after the update.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        freezesAvailable = try container.decode(Int.self, forKey: .freezesAvailable)
        frozenWeekStarts = try container.decode(Set<Date>.self, forKey: .frozenWeekStarts)
        preArmedWeekStart = try container.decodeIfPresent(Date.self, forKey: .preArmedWeekStart)
        lastEvaluatedWeekStart = try container.decodeIfPresent(Date.self, forKey: .lastEvaluatedWeekStart)
        kept4Counter = try container.decodeIfPresent(Int.self, forKey: .kept4Counter) ?? 0
        weekGoals = try container.decodeIfPresent([Date: Int].self, forKey: .weekGoals) ?? [:]
        threeDayRuleStart = try container.decodeIfPresent(Date.self, forKey: .threeDayRuleStart)
        freezeClock = try container.decodeIfPresent(Date.self, forKey: .freezeClock)
        freezeYear = try container.decodeIfPresent(Int.self, forKey: .freezeYear)
        goalRule = try container.decodeIfPresent(Int.self, forKey: .goalRule)
    }
}

/// The streak as the interface shows it. Derived on every evaluation, never
/// persisted.
nonisolated struct StreakSnapshot: Hashable {
    /// Kept weeks in a row, including the live week once it is kept. The one
    /// number shown everywhere.
    var weeks: Int
    /// The live week's goal: the days planned for it, saved when it started.
    /// The same number the Momentum card, the skip screen and the at-risk
    /// check use.
    var weeklyGoal: Int
    /// Distinct days this week with a momentum-preserving outcome.
    var thisWeekSessionDays: Int
    var isThisWeekKept: Bool
    var freezesAvailable: Int
    /// Whether the week that just finished was saved by a freeze, for the
    /// one quiet line that says so.
    var lastCompletedWeekWasFrozen: Bool
    var isLiveWeekPreArmed: Bool
    /// Monday of the week containing `now`, in the display calendar.
    var liveWeekStart: Date

    static let empty = StreakSnapshot(
        weeks: 0,
        weeklyGoal: StreakPolicy.minimumGymDays,
        thisWeekSessionDays: 0,
        isThisWeekKept: false,
        freezesAvailable: 0,
        lastCompletedWeekWasFrozen: false,
        isLiveWeekPreArmed: false,
        liveWeekStart: .distantPast
    )

    /// Whether the user can spend a freeze on the current week.
    ///
    /// Only while the week is still at risk: a kept week needs no protecting,
    /// and a week already armed cannot be armed twice.
    var canArmFreeze: Bool {
        freezesAvailable > 0 && !isThisWeekKept && !isLiveWeekPreArmed
    }

    /// "6 weeks", "1 week".
    var weeksLabel: String {
        "\(weeks) \(weeks == 1 ? "week" : "weeks")"
    }

    /// "2 of 3 this week".
    var thisWeekLabel: String {
        "\(thisWeekSessionDays) of \(weeklyGoal) this week"
    }
}
