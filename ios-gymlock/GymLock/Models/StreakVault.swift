import Foundation

/// The rules of the streak, in one place.
///
/// Every number here is a product decision rather than a measurement, and
/// keeping them together is what stops the card, the share frames and the
/// tests each quietly assuming a different goal.
nonisolated enum StreakPolicy {
    /// The most freezes a user can hold at once.
    static let maximumFreezes = 2
    /// Consecutive kept weeks that earn one freeze.
    static let weeksPerFreeze = 4
    /// Workouts a week needs to be kept. Whatever the plan says.
    static let defaultWeeklyGoal = 3
    /// Nobody can plan fewer gym days than this.
    static let minimumGymDays = 3
    /// The note shown when a gym day can't come off (FLOW, "Which nights").
    static let minimumGymDaysMessage = "3 gym days is the minimum."

    /// The rule weeks were judged by before the 3-day minimum: three, but
    /// never more than the plan, floored at one.
    ///
    /// Only used to save the goal of weeks that started before
    /// `StreakVault.threeDayRuleStart`, so no existing user sees a past week
    /// change. Never used for a week on or after it.
    static func legacyWeeklyGoal(plannedDays: Int) -> Int {
        max(1, min(defaultWeeklyGoal, plannedDays))
    }

    /// The goal a week gets the first time the engine sees it.
    ///
    /// On or after the rule start it is always 3. Before it, the legacy rule
    /// with the plan as it is when the goal is saved.
    static func goal(
        forWeekStarting weekStart: Date,
        ruleStart: Date,
        plannedDays: Int,
        calendar: Calendar
    ) -> Int {
        let isCovered = calendar.compare(weekStart, to: ruleStart, toGranularity: .day) != .orderedAscending
        return isCovered ? defaultWeeklyGoal : legacyWeeklyGoal(plannedDays: plannedDays)
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
    /// Consecutive kept weeks since the last freeze was awarded.
    var kept4Counter: Int
    /// Each week's goal, keyed by the week's Monday, saved the first time the
    /// engine sees the week. After that it is the only thing that week is
    /// judged by, so a plan change can never rewrite it.
    var weekGoals: [Date: Int] = [:]
    /// Monday of the first week the 3-day rule applies to. Set once and never
    /// moved: next Monday for a user who already had history when this rule
    /// arrived, their first week for everyone else.
    var threeDayRuleStart: Date?

    enum CodingKeys: String, CodingKey {
        case freezesAvailable, frozenWeekStarts, preArmedWeekStart
        case lastEvaluatedWeekStart, kept4Counter, weekGoals, threeDayRuleStart
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
        kept4Counter = try container.decode(Int.self, forKey: .kept4Counter)
        weekGoals = try container.decodeIfPresent([Date: Int].self, forKey: .weekGoals) ?? [:]
        threeDayRuleStart = try container.decodeIfPresent(Date.self, forKey: .threeDayRuleStart)
    }
}

/// The streak as the interface shows it. Derived on every evaluation, never
/// persisted.
nonisolated struct StreakSnapshot: Hashable {
    /// Kept weeks in a row, including the live week once it is kept. The one
    /// number shown everywhere.
    var weeks: Int
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
        weeklyGoal: StreakPolicy.defaultWeeklyGoal,
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
