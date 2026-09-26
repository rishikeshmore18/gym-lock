import Foundation

// MARK: - Wind-down window maths

/// Pure clock maths for the wind-down lock.
///
/// Kept free of dates-in and booleans-out only: everything a caller needs is
/// "given this start and this end, is `now` inside the window?" The midnight
/// wrap is the whole difficulty. A 23:00 → 06:30 window must be active at
/// 23:30, active again at 02:00, and inactive at exactly 06:30, because the
/// end is the moment the morning's alarm takes over.
enum WindDownLock {
    /// The window that contains `now`, if any, as concrete dates.
    ///
    /// A window whose end is earlier in the day than its start runs past
    /// midnight and finishes on the following day. Both the window that
    /// started yesterday and the one that starts today are checked, so a
    /// 02:00 reading lands in yesterday's window.
    ///
    /// Daylight saving resolves against the wall clock: a 23:00 start stays
    /// 23:00 local on transition nights. For an evening window this can only
    /// move the boundary by an hour once a year, and the foreground catch-up
    /// re-reads the clock on every wake regardless.
    static func window(
        start: TimeOfDay,
        end: TimeOfDay,
        at now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        // A window where start == end is treated as switched off, never as
        // twenty-four hours of lock. The editor cannot produce it, but a
        // hand-tuned wheel can.
        guard start.minutesFromMidnight != end.minutesFromMidnight else { return nil }

        let today = calendar.startOfDay(for: now)

        for dayOffset in [-1, 0] {
            guard let windowDay = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  let startDate = calendar.date(
                    bySettingHour: start.hour, minute: start.minute, second: 0, of: windowDay
                  ),
                  let endDate = calendar.date(
                    bySettingHour: end.hour, minute: end.minute, second: 0, of: windowDay
                  )
            else { continue }

            let actualEnd = endDate < startDate ? endDate.addingTimeInterval(86_400) : endDate

            // The end is exclusive: at wake time the night lock is over,
            // whatever the alarm decides to do next.
            if now >= startDate, now < actualEnd {
                return (startDate, actualEnd)
            }
        }

        return nil
    }

    /// The window containing `now`, but only if the night it belongs to is
    /// switched on.
    ///
    /// A night belongs to the calendar day it **starts** on, so 02:00 on a
    /// Tuesday inside a 23:00 → 07:00 window is Monday's night and is
    /// checked against Monday. `nil` nights means every night, which is how
    /// the lock behaved before the sleep schedule had days.
    static func window(
        start: TimeOfDay,
        end: TimeOfDay,
        at now: Date,
        calendar: Calendar,
        nights: Set<Weekday>?
    ) -> (start: Date, end: Date)? {
        guard let found = window(start: start, end: end, at: now, calendar: calendar) else { return nil }
        guard let nights else { return found }
        guard let startDay = Weekday(rawValue: calendar.component(.weekday, from: found.start)),
              nights.contains(startDay)
        else { return nil }
        return found
    }

    /// True when a window with these bounds is holding right now.
    static func isActive(
        start: TimeOfDay,
        end: TimeOfDay,
        at now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        window(start: start, end: end, at: now, calendar: calendar) != nil
    }
}

