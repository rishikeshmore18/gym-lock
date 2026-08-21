import Foundation

/// What a weekly checkpoint on the mountain represents.
enum CheckpointState: String, Codable, Hashable, Sendable {
    /// Day 0 — the base of the first mountain.
    case start
    /// Every planned session that week was verified.
    case completed
    /// Some but not all sessions were verified.
    case partial
    /// A planned week that came and went with nothing verified.
    case missed
    /// The week the user is living in right now.
    case current
    /// Still ahead.
    case upcoming

    /// Spoken description used by VoiceOver, so progress is never conveyed by
    /// colour alone.
    var spokenSuffix: String {
        switch self {
        case .start: "the start of your journey"
        case .completed: "completed"
        case .partial: "partly completed"
        case .missed: "missed"
        case .current: "up next"
        case .upcoming: "upcoming"
        }
    }
}

/// A single day the user verified a session, stored as `yyyyMMdd`.
///
/// An integer key keeps the persisted payload tiny and makes set membership
/// checks trivial, while still being human-readable in the defaults plist.
typealias DayStamp = Int

extension DayStamp {
    static func stamp(for date: Date, calendar: Calendar = .current) -> DayStamp {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 2000) * 10_000 + (parts.month ?? 1) * 100 + (parts.day ?? 1)
    }
}

/// The user's real history on the mountain.
///
/// This type deliberately stores only two things the user actually did: the day
/// they started, and the days they verified a session. Everything the home
/// screen displays — weeks completed, weeks missed, the streak, the position of
/// the current marker — is derived from those facts. Nothing is ever written
/// here because the user merely opened the app.
struct JourneyProgress: Codable, Hashable {
    /// A mountain covers a twelve-week expedition; after that the journey
    /// continues onto the next peak rather than crowding one summit with an
    /// unbounded number of labels.
    static let weeksPerExpedition = 12

    /// The day onboarding was completed. Nil until the user activates.
    var startDate: Date?
    /// Days with a verified session.
    var verifiedDays: Set<DayStamp>
    /// Week index → file name in Documents of that week's progress photo.
    var weekPhotos: [Int: String]

    static let empty = JourneyProgress(startDate: nil, verifiedDays: [], weekPhotos: [:])

    // MARK: - Calendar helpers

    /// The journey's weeks are measured from the start date rather than from
    /// calendar weeks, so "week 1" always means the user's first seven days.
    func weekIndex(for date: Date, calendar: Calendar = .current) -> Int {
        guard let startDate else { return 0 }
        let startDay = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startDay, to: day).day ?? 0
        return max(0, days / 7)
    }

    var currentWeekIndex: Int { weekIndex(for: Date()) }

    /// First and last day of a given journey week.
    func dateRange(forWeek index: Int, calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let startDate else { return nil }
        let startDay = calendar.startOfDay(for: startDate)
        guard let from = calendar.date(byAdding: .day, value: index * 7, to: startDay),
              let to = calendar.date(byAdding: .day, value: 6, to: from)
        else { return nil }
        return from...to
    }

    /// The day the current week closes — which is also the next photo check-in.
    func endOfWeek(_ index: Int, calendar: Calendar = .current) -> Date? {
        dateRange(forWeek: index, calendar: calendar)?.upperBound
    }

    // MARK: - Derived progress

    /// Verified sessions inside a journey week.
    func verifiedCount(inWeek index: Int, calendar: Calendar = .current) -> Int {
        guard let range = dateRange(forWeek: index, calendar: calendar) else { return 0 }
        var day = range.lowerBound
        var count = 0
        while day <= range.upperBound {
            if verifiedDays.contains(DayStamp.stamp(for: day, calendar: calendar)) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    /// How a week should render, given how many sessions were planned for it.
    func state(forWeek index: Int, planned: Int, calendar: Calendar = .current) -> CheckpointState {
        let current = currentWeekIndex
        if index > current { return .upcoming }
        if index == current { return .current }

        let verified = verifiedCount(inWeek: index, calendar: calendar)
        if verified == 0 { return .missed }
        if verified >= max(planned, 1) { return .completed }
        return .partial
    }

    /// Past weeks where nothing at all was verified.
    func missedWeekCount(calendar: Calendar = .current) -> Int {
        guard startDate != nil else { return 0 }
        let current = currentWeekIndex
        guard current > 0 else { return 0 }
        return (0..<current).reduce(into: 0) { total, index in
            if verifiedCount(inWeek: index, calendar: calendar) == 0 { total += 1 }
        }
    }

    /// Consecutive *training* days that were verified, counted backwards.
    ///
    /// Rest days do not break a streak and do not extend it — only the days the
    /// user actually planned to train are counted. Today is only judged once it
    /// has been verified, so an unfinished training day never reads as a break.
    func streak(trainingDays: Set<Weekday>, calendar: Calendar = .current) -> Int {
        guard !trainingDays.isEmpty, startDate != nil else { return 0 }

        var streak = 0
        var day = calendar.startOfDay(for: Date())
        let earliest = calendar.startOfDay(for: startDate ?? Date())
        var isToday = true

        // A year of look-back is far more than any streak this app will show,
        // and keeps a corrupt start date from spinning here forever.
        for _ in 0..<366 {
            guard day >= earliest else { break }

            let weekdayNumber = calendar.component(.weekday, from: day)
            if let weekday = Weekday(rawValue: weekdayNumber), trainingDays.contains(weekday) {
                if verifiedDays.contains(DayStamp.stamp(for: day, calendar: calendar)) {
                    streak += 1
                } else if !isToday {
                    break
                }
            }

            isToday = false
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return streak
    }

    var hasVerifiedToday: Bool {
        verifiedDays.contains(DayStamp.stamp(for: Date()))
    }

    /// Total verified sessions, used by the progress tab.
    var totalVerified: Int { verifiedDays.count }

    // MARK: - Expeditions

    /// Which mountain the user is climbing right now.
    var currentExpedition: Int { currentWeekIndex / Self.weeksPerExpedition }

    /// Week index relative to the current mountain's base.
    var weekWithinExpedition: Int { currentWeekIndex % Self.weeksPerExpedition }

    // MARK: - Mutation

    mutating func markVerified(_ date: Date = Date(), calendar: Calendar = .current) {
        verifiedDays.insert(DayStamp.stamp(for: date, calendar: calendar))
    }

    mutating func clearVerified(_ date: Date = Date(), calendar: Calendar = .current) {
        verifiedDays.remove(DayStamp.stamp(for: date, calendar: calendar))
    }
}
