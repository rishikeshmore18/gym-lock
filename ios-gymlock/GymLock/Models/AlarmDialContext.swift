import Foundation

/// Which half of the dial the Alarm screen is talking about.
///
/// Kept apart from the live grab on purpose. The grab is what the finger is
/// holding *now* and goes back to nil the moment it lifts; this is what the
/// user last touched, and it stays put until they touch the other arc. The
/// header, the line under the dial and the day card all read this, so
/// letting go of the gym bar no longer flips the screen back to sleep.
///
/// Screen-local by design. Nothing here is persisted: every visit to the
/// Alarm screen opens on the night, as it always has.
enum AlarmDialContext: Equatable {
    case sleep
    case gym

    /// The dial opens showing bedtime and wake up.
    static let initial: AlarmDialContext = .sleep

    /// The context after the dial reports a grab. A nil grab is the finger
    /// lifting, which changes nothing.
    func updated(with grab: DayDialModel.Grab?) -> AlarmDialContext {
        guard let grab else { return self }
        return grab.isGym ? .gym : .sleep
    }

    /// The two labels above the big numbers.
    var headerLabels: (leading: String, trailing: String) {
        switch self {
        case .sleep: ("bedtime", "wake up")
        case .gym: ("gym", "done")
        }
    }

    /// The day card's title.
    var dayCardTitle: String {
        switch self {
        case .sleep: "sleep schedule"
        case .gym: "gym days"
        }
    }

    /// The day card's summary for `count` selected days. For sleep this is
    /// the effective count, required nights included.
    func daySummary(count: Int) -> String {
        switch self {
        case .gym:
            switch count {
            case 0: "nothing will ring"
            case 1: "1 day a week"
            case 7: "every day"
            default: "\(count) days a week"
            }
        case .sleep:
            switch count {
            case 0: "no sleep schedule"
            case 1: "1 night a week"
            case 7: "every night"
            default: "\(count) nights a week"
            }
        }
    }
}
