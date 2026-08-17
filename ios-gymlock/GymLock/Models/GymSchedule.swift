import Foundation

/// A day of the week, ordered Monday-first to match the schedule selector.
enum Weekday: Int, CaseIterable, Identifiable, Codable, Hashable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    /// Single-to-three letter label used in the compact day selector.
    var shortLabel: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }
}

/// A time of day stored independently of any calendar date.
struct TimeOfDay: Codable, Hashable {
    var hour: Int
    var minute: Int

    static let defaultGymTime = TimeOfDay(hour: 7, minute: 0)
    static let defaultBedtime = TimeOfDay(hour: 22, minute: 30)

    /// Converts to a `Date` today so SwiftUI's `DatePicker` can bind to it.
    var asDateToday: Date {
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59),
            second: 0,
            of: Date()
        ) ?? Date()
    }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(from date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? 7
        minute = parts.minute ?? 0
    }

    /// Locale-aware display string, e.g. "7:00 AM".
    var displayString: String {
        asDateToday.formatted(date: .omitted, time: .shortened)
    }
}

/// The user's two locks: when they train and when they sleep.
struct GymSchedule: Codable, Hashable {
    var trainingDays: Set<Weekday>
    var gymTime: TimeOfDay
    var bedtime: TimeOfDay

    static let `default` = GymSchedule(
        trainingDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
        gymTime: .defaultGymTime,
        bedtime: .defaultBedtime
    )

    /// A schedule is only usable once at least one training day is picked.
    var isValid: Bool { !trainingDays.isEmpty }

    /// Human summary such as "5 days a week".
    var daysSummary: String {
        let count = trainingDays.count
        if count == 7 { return "every day" }
        return count == 1 ? "1 day a week" : "\(count) days a week"
    }
}
