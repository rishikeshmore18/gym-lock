import Foundation

/// The bounded set of days the calendar strip currently has in memory.
///
/// The strip is meant to feel endless, which is not the same as being endless.
/// It holds a window around today and grows it as the user approaches an edge,
/// so scrolling never hits a wall, while the number of `Date` values stays
/// small, fixed, and predictable.
struct CalendarWindow: Equatable {
    /// Ascending, each one the start of its day.
    private(set) var days: [Date]

    let today: Date

    private let calendar: Calendar
    private var firstOffset: Int
    private var lastOffset: Int

    /// How far the window may ever reach. Five years in either direction is far
    /// past the point where scrolling is a deliberate act rather than a swipe.
    private static let horizon = 1825
    /// How many days to add when an edge is approached.
    private static let chunk = 90
    /// How close to an edge the user must get before more days are added. Wide
    /// enough that the growth always happens off-screen.
    private static let threshold = 24

    init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        firstOffset = -60
        lastOffset = 60
        days = Self.build(from: firstOffset, to: lastOffset, today: today, calendar: calendar)
    }

    /// The day the strip should sit at when home first opens.
    ///
    /// Today lands in the centre-to-right of the visible week: a few days of
    /// recent history are readable at a glance without the user having to
    /// scroll to find where they actually are.
    func defaultLeadingDay(visibleDays: Int = 7) -> Date {
        let lead = max(1, visibleDays - 2)
        return calendar.date(byAdding: .day, value: -lead, to: today) ?? today
    }

    func date(byAdding days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    func offset(of date: Date) -> Int? {
        calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day
    }

    /// Grows the window if `date` is close to either end.
    ///
    /// Returns whether anything changed, so callers can skip a pointless
    /// rebuild. Existing days keep their exact values, so a scroll position
    /// bound to one of them survives the growth.
    @discardableResult
    mutating func extend(reaching date: Date) -> Bool {
        guard let offset = offset(of: date) else { return false }

        var changed = false

        if offset - firstOffset < Self.threshold, firstOffset > -Self.horizon {
            firstOffset = max(-Self.horizon, firstOffset - Self.chunk)
            changed = true
        }

        if lastOffset - offset < Self.threshold, lastOffset < Self.horizon {
            lastOffset = min(Self.horizon, lastOffset + Self.chunk)
            changed = true
        }

        guard changed else { return false }
        days = Self.build(from: firstOffset, to: lastOffset, today: today, calendar: calendar)
        return true
    }

    private static func build(
        from first: Int,
        to last: Int,
        today: Date,
        calendar: Calendar
    ) -> [Date] {
        (first...last).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
}
