import Foundation

/// When freezes arrive and when they expire (FLOW, Flow 5).
///
/// - The year someone joins: #1 at join date + 2 months, #2 at join date +
///   6 months, each only if it lands inside that same calendar year.
/// - Every later year: #1 on March 1, #2 on July 1.
/// - Unused freezes expire on December 31; the new year starts at 0.
/// - A grant happens on its date whatever the streak is. Never more than 2.
///
/// Pure, with `calendar` passed in, so the FLOW example can be pinned month
/// by month.
nonisolated enum FreezeCalendar {
    static let earnedLine = "you earned a freeze."
    static let secondEarnedLine = "you earned your 2nd freeze."

    /// One freeze arriving.
    struct Grant: Hashable {
        /// The start of the day it arrives on.
        var date: Date
        /// 1 or 2: which freeze of its calendar year this is.
        var ordinal: Int

        /// The notification sent for it.
        var line: String {
            ordinal == 1 ? FreezeCalendar.earnedLine : FreezeCalendar.secondEarnedLine
        }
    }

    /// The grants of one calendar year, oldest first.
    static func grants(inYear year: Int, joined: Date, calendar: Calendar) -> [Grant] {
        let joinDay = calendar.startOfDay(for: joined)
        let joinYear = calendar.component(.year, from: joinDay)
        guard year >= joinYear else { return [] }

        let dates: [Date]
        if year == joinYear {
            dates = [2, 6]
                .compactMap { calendar.date(byAdding: .month, value: $0, to: joinDay) }
                .map { calendar.startOfDay(for: $0) }
                .filter { calendar.component(.year, from: $0) == year }
        } else {
            dates = [3, 7].compactMap { calendar.date(from: DateComponents(year: year, month: $0, day: 1)) }
        }
        return dates.enumerated().map { Grant(date: $0.element, ordinal: $0.offset + 1) }
    }

    /// Every grant from the start of `from`'s year through the end of the next
    /// one, oldest first. Enough to schedule every notice ahead of time.
    static func grants(around from: Date, joined: Date, calendar: Calendar) -> [Grant] {
        let year = calendar.component(.year, from: from)
        return (year...(year + 1)).flatMap { grants(inYear: $0, joined: joined, calendar: calendar) }
    }

    /// Applies every grant and every Dec 31 expiry between the vault's clock
    /// and `moment`, in order, then moves the clock to `moment`.
    ///
    /// The first time it runs on a vault (no clock yet) it only starts the
    /// clock: an existing user keeps the freezes they hold (at most 2), and
    /// nothing from before today is granted. Running it again for the same
    /// moment, or an earlier one, changes nothing, so a relaunch can never
    /// grant twice.
    static func settle(_ vault: inout StreakVault, joined: Date, upTo moment: Date, calendar: Calendar) {
        guard let clock = vault.freezeClock else {
            vault.freezeClock = moment
            vault.freezeYear = calendar.component(.year, from: moment)
            vault.freezesAvailable = min(max(vault.freezesAvailable, 0), StreakPolicy.maximumFreezes)
            return
        }
        guard moment > clock else { return }

        let firstYear = calendar.component(.year, from: clock)
        let lastYear = calendar.component(.year, from: moment)
        var held = vault.freezesAvailable

        for year in firstYear...max(firstYear, lastYear) {
            // Jan 1 of a later year: last year's freezes expired on Dec 31.
            if year > firstYear { held = 0 }
            for grant in grants(inYear: year, joined: joined, calendar: calendar)
            where grant.date > clock && grant.date <= moment {
                held = min(held + 1, StreakPolicy.maximumFreezes)
            }
        }

        vault.freezesAvailable = held
        vault.freezeClock = moment
        vault.freezeYear = lastYear
    }
}
