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
    /// Session days a week needs by default.
    static let defaultWeeklyGoal = 3

    /// Session days a week needs to be kept.
    ///
    /// Three, but never more than the user's own plan: someone who trains
    /// twice a week has agreed to two, and asking three of them would make a
    /// streak impossible by design. Floored at one so a user with no plan yet
    /// can still hold a streak by showing up.
    static func weeklyGoal(plannedDays: Int) -> Int {
        max(1, min(defaultWeeklyGoal, plannedDays))
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
