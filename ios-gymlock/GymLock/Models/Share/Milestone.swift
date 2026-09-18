import Foundation

/// A threshold crossed on a specific day.
///
/// Computed, never stored, and never manufactured: a milestone exists only if
/// the outcome that reached it is dated the reference day. There is no badge
/// artwork because no badge system exists yet — the Progress tile still says
/// zero — so the frame draws none.
struct Milestone: Hashable {
    enum Kind: Hashable {
        case verifiedVisits(Int)
        case firstKeptWeek
        case streakWeeks(Int)
        case firstComeback
    }

    let kind: Kind

    /// The statement, uppercase, as the frame prints it.
    var title: String {
        switch kind {
        case let .verifiedVisits(count):
            "\(count) VERIFIED \(count == 1 ? "VISIT" : "VISITS")"
        case .firstKeptWeek:
            "FIRST WEEK KEPT"
        case let .streakWeeks(weeks):
            weeks == 4 ? "FIRST MONTH" : "\(weeks) WEEKS STRONG"
        case .firstComeback:
            "FIRST COMEBACK"
        }
    }

    /// The number, when the statement has one to set large.
    var heroNumber: Int? {
        switch kind {
        case let .verifiedVisits(count): count
        case let .streakWeeks(weeks): weeks == 4 ? nil : weeks
        default: nil
        }
    }

    /// The words that follow the number, or the whole statement.
    var label: String {
        switch kind {
        case let .verifiedVisits(count): count == 1 ? "VERIFIED VISIT" : "VERIFIED VISITS"
        case .firstKeptWeek: "FIRST WEEK KEPT"
        case let .streakWeeks(weeks): weeks == 4 ? "FIRST MONTH" : "WEEKS STRONG"
        case .firstComeback: "FIRST COMEBACK"
        }
    }

    static let visitThresholds = [1, 5, 10, 25, 50, 100]
    static let streakThresholds = [4, 8, 12, 26, 52]

    /// The milestone crossed on `referenceDay`, if any. Visits outrank weeks
    /// outrank comebacks when two land on the same day, because the visit
    /// count is the number the user has most directly earned.
    static func crossed(
        on referenceDay: Date,
        log: MomentumLog,
        streak: StreakSnapshot,
        sessionDaysThisWeek: [Date],
        comeback: ComebackInfo?,
        calendar: Calendar
    ) -> Milestone? {
        if let visits = verifiedVisitsMilestone(on: referenceDay, log: log, calendar: calendar) {
            return visits
        }
        if let weeks = streakMilestone(
            on: referenceDay,
            streak: streak,
            sessionDaysThisWeek: sessionDaysThisWeek,
            calendar: calendar
        ) {
            return weeks
        }
        if comeback != nil, isFirstComeback(before: referenceDay, log: log, calendar: calendar) {
            return Milestone(kind: .firstComeback)
        }
        return nil
    }

    /// Whether the verified visit that reached a threshold is dated the
    /// reference day.
    private static func verifiedVisitsMilestone(
        on referenceDay: Date,
        log: MomentumLog,
        calendar: Calendar
    ) -> Milestone? {
        let visits = log.outcomes.filter(\.kind.isVerifiedGymVisit).sorted { $0.date < $1.date }
        for threshold in visitThresholds where visits.count >= threshold {
            let reaching = visits[threshold - 1]
            if calendar.isDate(reaching.date, inSameDayAs: referenceDay) {
                return Milestone(kind: .verifiedVisits(threshold))
            }
        }
        return nil
    }

    /// The live week is kept, the goal was reached on the reference day, and
    /// the streak sits exactly on a threshold (or became 1).
    private static func streakMilestone(
        on referenceDay: Date,
        streak: StreakSnapshot,
        sessionDaysThisWeek: [Date],
        calendar: Calendar
    ) -> Milestone? {
        guard streak.isThisWeekKept,
              sessionDaysThisWeek.count >= streak.weeklyGoal,
              let goalDay = sessionDaysThisWeek.dropFirst(streak.weeklyGoal - 1).first,
              calendar.isDate(goalDay, inSameDayAs: referenceDay)
        else { return nil }

        if streak.weeks == 1 { return Milestone(kind: .firstKeptWeek) }
        if streakThresholds.contains(streak.weeks) {
            return Milestone(kind: .streakWeeks(streak.weeks))
        }
        return nil
    }

    /// Whether no earlier day in the log was itself a comeback.
    static func isFirstComeback(before referenceDay: Date, log: MomentumLog, calendar: Calendar) -> Bool {
        let days = ShareContextBuilder.outcomeDays(in: log, calendar: calendar)
        let reference = calendar.startOfDay(for: referenceDay)
        for (index, day) in days.enumerated() where day < reference && index > 0 {
            let previous = days[index - 1]
            if ShareContextBuilder.preservesMomentum(on: day, log: log, calendar: calendar),
               ShareContextBuilder.isMiss(on: previous, log: log, calendar: calendar) {
                return false
            }
        }
        return true
    }
}
