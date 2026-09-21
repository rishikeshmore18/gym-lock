import Foundation

/// A behavioural event worth remembering.
///
/// This is the raw material for the future activity grid, and it is deliberately
/// a record of *what happened*, not of what the user typed. Nothing here is
/// manually logged: every case is emitted by the system as the morning unfolds.
///
/// Nothing sensitive is stored. No coordinates, no health payloads, no app
/// tokens — see `SessionEvent.detail` for what a detail string is allowed to be.
enum SessionEventKind: String, Codable, Hashable, CaseIterable {
    case planned
    case alarmFired
    case snoozed
    case committed
    case missionCompleted
    case departed
    case gymArrivalCandidate
    case gymArrivalVerified
    case workoutDetected
    case quickWorkoutCompleted
    case rescheduled
    case cantToday
    case missed
    case technicalFailure
    case shieldApplied
    case shieldRemoved
    case technicalRelease

    var label: String {
        switch self {
        case .planned: "planned"
        case .alarmFired: "alarm fired"
        case .snoozed: "snoozed once"
        case .committed: "I'm going"
        case .missionCompleted: "mission completed"
        case .departed: "departed"
        case .gymArrivalCandidate: "near the gym"
        case .gymArrivalVerified: "arrived at the gym"
        case .workoutDetected: "workout detected"
        case .quickWorkoutCompleted: "quick workout completed"
        case .rescheduled: "rescheduled"
        case .cantToday: "can't today"
        case .missed: "missed"
        case .technicalFailure: "couldn't confirm"
        case .shieldApplied: "apps locked"
        case .shieldRemoved: "apps unlocked"
        case .technicalRelease: "safety release"
        }
    }
}

/// One timestamped event.
struct SessionEvent: Codable, Hashable, Identifiable {
    var id: UUID
    var sessionID: UUID?
    var kind: SessionEventKind
    var at: Date
    /// A short, non-sensitive note.
    ///
    /// Allowed: an activity type name, a duration, a reason code. Never a
    /// coordinate, never a health sample, never a FamilyActivity token.
    var detail: String?

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        kind: SessionEventKind,
        at: Date = Date(),
        detail: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.at = at
        self.detail = detail
    }
}

/// A bounded ring of recent events.
struct SessionEventLog: Codable, Hashable {
    var events: [SessionEvent]

    static let empty = SessionEventLog(events: [])

    /// Roughly a year of mornings. Enough for any grid; small enough to encode
    /// on every write without thinking about it.
    private static let limit = 600

    mutating func record(_ event: SessionEvent) {
        events.append(event)
        if events.count > Self.limit {
            events.removeFirst(events.count - Self.limit)
        }
    }

    func events(on day: Date, calendar: Calendar = .current) -> [SessionEvent] {
        events.filter { calendar.isDate($0.at, inSameDayAs: day) }
    }

    func mostRecent(_ kind: SessionEventKind) -> SessionEvent? {
        events.last { $0.kind == kind }
    }
}

// MARK: - Detected workout

/// A summary of a workout Apple Health already recorded.
///
/// Deliberately thin. GymLock is not a workout tracker and has no business
/// keeping heart-rate series or route data — it needs just enough to say
/// "workout detected" and show what kind it was.
struct DetectedWorkout: Codable, Hashable {
    /// Localised activity name, e.g. "Traditional Strength Training".
    var activityName: String
    var startedAt: Date
    var endedAt: Date
    /// Which app or device wrote the sample, e.g. "Apple Watch".
    var source: String

    var durationMinutes: Int {
        max(1, Int(endedAt.timeIntervalSince(startedAt) / 60))
    }

    var summary: String {
        "\(activityName) · \(durationMinutes) min"
    }
}
