import Foundation

/// Where a share was started from.
///
/// Two origins, one presenter. A photo carries its own day; a session carries
/// only the day, and the frames that need a photograph are simply not offered.
enum ShareOrigin: Hashable, Identifiable {
    /// The review screen's Share, or a card in the Progress stack.
    case progressPhoto(ProgressPhoto)
    /// The success screens, before any photo exists for the day.
    case session(day: Date)

    var id: String {
        switch self {
        case let .progressPhoto(photo): "photo-\(photo.id.uuidString)"
        case let .session(day): "session-\(day.timeIntervalSinceReferenceDate)"
        }
    }

    var photo: ProgressPhoto? {
        if case let .progressPhoto(photo) = self { return photo }
        return nil
    }

    /// The day every number on the frame is about.
    var referenceDay: Date {
        switch self {
        case let .progressPhoto(photo): photo.createdAt
        case let .session(day): day
        }
    }
}

/// The morning as a sequence of timestamps, for the Receipt.
///
/// Rebuilt from `SessionEventLog` rather than from the live `GymSession`,
/// which is cleared when the morning ends — by the time the user is choosing a
/// frame in the afternoon, the events are the only record left.
nonisolated struct ReceiptTimeline: Hashable {
    let alarm: Date
    let left: Date
    let arrived: Date
    /// Only when Health independently saw one. Absence is not shown.
    let workout: Date?

    /// Whole minutes from the alarm to standing in the gym.
    var alarmToGymMinutes: Int {
        max(0, Int(arrived.timeIntervalSince(alarm) / 60))
    }
}

/// How far the user is into the programme, for the Journey frame.
nonisolated struct JourneySnapshot: Hashable {
    /// Days since install, counting the install day as Day 1... no: the
    /// install day is Day 0 on the card, so the day after it is Day 1.
    let dayNumber: Int
    let verifiedVisits: Int
    /// Trailing 28 days, `completed / due`. Nil when nothing was due.
    let completion: Double?
    /// Sessions that were due in that window.
    let due: Int
    /// The before-picture, when it is not the photo being shared.
    let dayZeroPhoto: ProgressPhoto?

    var percentText: String? {
        completion.map { "\(Int(($0 * 100).rounded()))% showed up" }
    }
}

/// A return after a miss.
nonisolated struct ComebackInfo: Hashable {
    let missedDay: Date
    let returnDay: Date
}

/// The one data object every frame reads from.
///
/// Built once when the editor opens, from `AppStore` and `ProgressPhotoStore`
/// and nothing else. Every number here traces to a model field; nothing is
/// estimated, and a field the record cannot support is nil, which hides the
/// frame that would have drawn it.
struct ShareContext: Hashable {
    let referenceDay: Date
    let photo: ProgressPhoto?
    let streak: StreakSnapshot
    /// What the ledger says about the reference day.
    let outcome: SessionOutcome?
    let receipt: ReceiptTimeline?
    let verifiedVisitsTotal: Int
    /// Monday-first week containing `referenceDay`.
    let verifiedVisitsThisWeek: Int
    let quick20ThisWeek: Int
    /// Distinct session days in that week, the number the streak counts.
    let sessionDaysThisWeek: Int
    let journey: JourneySnapshot?
    let comeback: ComebackInfo?
    let milestone: Milestone?
    let installDate: Date

    var hasPhoto: Bool { photo != nil }

    /// The morning's arrival time, when the event log has one.
    var arrivalTime: Date? { receipt?.arrived ?? arrivedAt }

    /// Arrival from the event log even when the rest of the receipt is
    /// missing, so Showed Up can print a time without needing a departure.
    let arrivedAt: Date?

    /// Whether the live week is the reference week and the goal is met.
    var isReferenceWeekKept: Bool { sessionDaysThisWeek >= streak.weeklyGoal }

    init(
        referenceDay: Date,
        photo: ProgressPhoto?,
        streak: StreakSnapshot,
        outcome: SessionOutcome?,
        receipt: ReceiptTimeline?,
        arrivedAt: Date?,
        verifiedVisitsTotal: Int,
        verifiedVisitsThisWeek: Int,
        quick20ThisWeek: Int,
        sessionDaysThisWeek: Int,
        journey: JourneySnapshot?,
        comeback: ComebackInfo?,
        milestone: Milestone?,
        installDate: Date
    ) {
        self.referenceDay = referenceDay
        self.photo = photo
        self.streak = streak
        self.outcome = outcome
        self.receipt = receipt
        self.arrivedAt = arrivedAt
        self.verifiedVisitsTotal = verifiedVisitsTotal
        self.verifiedVisitsThisWeek = verifiedVisitsThisWeek
        self.quick20ThisWeek = quick20ThisWeek
        self.sessionDaysThisWeek = sessionDaysThisWeek
        self.journey = journey
        self.comeback = comeback
        self.milestone = milestone
        self.installDate = installDate
    }
}

// MARK: - Copy

extension ShareContext {
    /// "Sep 17" — the date fact several frames fall back to.
    var dateFact: String {
        referenceDay.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Short, locale-aware time such as "7:03 AM".
    static func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Weekday name, wide, e.g. "Wednesday" / "Donnerstag".
    static func weekdayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }
}
