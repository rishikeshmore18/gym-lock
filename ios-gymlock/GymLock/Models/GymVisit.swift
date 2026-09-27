import Foundation

// MARK: - Proof

/// Why a gym visit counts (FLOW, Flow 3). `unproven` is a gym visit that has
/// not been shown to be a workout yet: it unlocked the apps and nothing more.
nonisolated enum WorkoutProof: String, Codable, Hashable {
    /// Arrived, workout not done (yet). Does not count.
    case unproven
    /// Recorded before workouts had to be done. Keeps counting, so no past
    /// week changes.
    case legacy
    /// An Apple Health workout of 20+ minutes, started at the gym, not typed
    /// in by hand.
    case health
    /// 20 minutes at the gym.
    case timeAtGym
    /// "I'm here" plus a camera progress photo taken after it.
    case photo
}

// MARK: - The rules

/// When a workout is done (FLOW, Flow 3). Pure, so every number can be pinned
/// in a test.
nonisolated enum WorkoutRules {
    /// Minutes that make a workout: in Apple Health, or at the gym.
    static let minimumMinutes = 20
    /// A Health workout may start at most this long before arrival.
    static let healthEarliestBeforeArrival: TimeInterval = 15 * 60
    /// Apple Health is checked for this long after arrival.
    static let healthWindowAfterArrival: TimeInterval = 5 * 3600
    /// Trips outside shorter than this don't reset the clock.
    static let shortTripGrace: TimeInterval = 5 * 60
    /// The workout-done notification, at the latest, after arrival.
    static let doneNoticeAfterArrival: TimeInterval = 30 * 60

    static var minimumInterval: TimeInterval { TimeInterval(minimumMinutes * 60) }

    /// Whether a Health workout proves the workout for an arrival at
    /// `arrivedAt`: 20+ minutes, started between 15 minutes before and 5
    /// hours after, and not typed in by hand.
    static func healthQualifies(_ workout: DetectedWorkout, arrivedAt: Date) -> Bool {
        guard !workout.wasUserEntered else { return false }
        guard workout.endedAt.timeIntervalSince(workout.startedAt) >= minimumInterval else { return false }
        return workout.startedAt >= arrivedAt.addingTimeInterval(-healthEarliestBeforeArrival)
            && workout.startedAt <= arrivedAt.addingTimeInterval(healthWindowAfterArrival)
    }

    /// The proof for a visit right now, if any. Either proof is enough, and
    /// neither cancels the other.
    static func proof(
        for visit: GymVisit,
        now: Date,
        workouts: [DetectedWorkout],
        photos: [ProgressPhoto],
        calendar: Calendar
    ) -> WorkoutProof? {
        if visit.presenceQualifies(now: now) { return .timeAtGym }
        if workouts.contains(where: {
            guard healthQualifies($0, arrivedAt: visit.healthAnchor) else { return false }
            // A home workout checks Health on the same day only (FLOW, Flow 4).
            return !visit.isHome || calendar.isDate($0.startedAt, inSameDayAs: visit.healthAnchor)
        }) { return .health }
        if let manualAt = visit.manualAt,
           photos.contains(where: { PhotoProof.qualifies($0, takenAfter: manualAt, calendar: calendar) }) {
            return .photo
        }
        return nil
    }
}

/// A camera progress photo taken after a moment, the same day. Library and
/// file photos never count. Reused by home workouts.
nonisolated enum PhotoProof {
    static func qualifies(_ photo: ProgressPhoto, takenAfter start: Date, calendar: Calendar) -> Bool {
        photo.source == .camera
            && photo.createdAt >= start
            && calendar.isDate(photo.createdAt, inSameDayAs: start)
    }
}

// MARK: - A visit

/// One visit to the gym, from arrival until it is settled.
///
/// Separate from the alarm session on purpose: a visit can happen with no
/// alarm at all, and it outlives the session (the apps unlock on arrival, but
/// the workout is only done 20 minutes later, and Apple Health can confirm it
/// for 5 hours).
///
/// iOS won't run the app on a timer, so everything here is worked out from
/// region events and the clock whenever the app next runs.
nonisolated struct GymVisit: Codable, Hashable, Identifiable {
    var id: UUID
    /// The outcome in the log that this visit marks counted.
    var outcomeID: UUID
    /// The alarm session this visit belongs to, if any.
    var sessionID: UUID?
    /// The day it counts on: the alarm day, or the arrival day.
    var countsOn: Date
    var arrivedAt: Date
    /// Whether time at the gym can prove the workout. False when the phone
    /// was already inside at the start, on "I'm here", and when home sits
    /// inside the gym area and the app never saw them leave home.
    var timeCounts: Bool
    /// When "I'm here" was tapped (GPS couldn't confirm).
    var manualAt: Date?
    /// Tonight's bedtime, formatted, when the visit started inside the sleep
    /// window. Nil otherwise. Picks the "cost you sleep" line.
    var sleepBedtime: String?
    /// An exit not yet 5 minutes old. Cleared on re-entry.
    var pendingExitAt: Date?
    /// When they really left (an exit with no re-entry within 5 minutes).
    var leftAt: Date?
    var proof: WorkoutProof?
    var countedAt: Date?
    /// When the workout-done notification is (or was) set to fire.
    var doneFireAt: Date?
    var doneLine: String?
    /// The last line before this visit's, so it can be put back if this
    /// visit's notification is cancelled.
    var previousLastLine: String?
    /// When the "you left after" notification is (or was) set to fire.
    var shortFireAt: Date?
    /// A home workout, not a gym visit: no presence, no exits, and the Health
    /// check runs on the timer's day only. Decoded as false for visits saved
    /// before home workouts were followed.
    var isHome: Bool

    init(
        id: UUID = UUID(),
        outcomeID: UUID,
        sessionID: UUID?,
        countsOn: Date,
        arrivedAt: Date,
        timeCounts: Bool,
        manualAt: Date? = nil,
        sleepBedtime: String? = nil,
        isHome: Bool = false
    ) {
        self.id = id
        self.outcomeID = outcomeID
        self.sessionID = sessionID
        self.countsOn = countsOn
        self.arrivedAt = arrivedAt
        self.timeCounts = timeCounts
        self.manualAt = manualAt
        self.sleepBedtime = sleepBedtime
        self.isHome = isHome
    }

    private enum CodingKeys: String, CodingKey {
        case id, outcomeID, sessionID, countsOn, arrivedAt, timeCounts, manualAt, sleepBedtime
        case pendingExitAt, leftAt, proof, countedAt, doneFireAt, doneLine, previousLastLine, shortFireAt
        case isHome
    }

    /// `isHome` is missing on visits saved before home workouts were followed,
    /// and reads as false.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        outcomeID = try container.decode(UUID.self, forKey: .outcomeID)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        countsOn = try container.decode(Date.self, forKey: .countsOn)
        arrivedAt = try container.decode(Date.self, forKey: .arrivedAt)
        timeCounts = try container.decode(Bool.self, forKey: .timeCounts)
        manualAt = try container.decodeIfPresent(Date.self, forKey: .manualAt)
        sleepBedtime = try container.decodeIfPresent(String.self, forKey: .sleepBedtime)
        pendingExitAt = try container.decodeIfPresent(Date.self, forKey: .pendingExitAt)
        leftAt = try container.decodeIfPresent(Date.self, forKey: .leftAt)
        proof = try container.decodeIfPresent(WorkoutProof.self, forKey: .proof)
        countedAt = try container.decodeIfPresent(Date.self, forKey: .countedAt)
        doneFireAt = try container.decodeIfPresent(Date.self, forKey: .doneFireAt)
        doneLine = try container.decodeIfPresent(String.self, forKey: .doneLine)
        previousLastLine = try container.decodeIfPresent(String.self, forKey: .previousLastLine)
        shortFireAt = try container.decodeIfPresent(Date.self, forKey: .shortFireAt)
        isHome = (try? container.decodeIfPresent(Bool.self, forKey: .isHome)) ?? false
    }

    var isCounted: Bool { countedAt != nil }
    var isInSleepHours: Bool { sleepBedtime != nil }

    /// Where the Health window is measured from.
    var healthAnchor: Date { manualAt ?? arrivedAt }

    /// Turns an exit into a real departure once 5 minutes pass without a
    /// re-entry.
    mutating func settleExit(now: Date) {
        guard leftAt == nil, let exit = pendingExitAt,
              now.timeIntervalSince(exit) >= WorkoutRules.shortTripGrace
        else { return }
        leftAt = exit
        pendingExitAt = nil
    }

    /// The end of the time at the gym so far. A pending exit counts as the
    /// end until they come back, so nothing is counted on a guess.
    func presenceEnd(now: Date) -> Date {
        leftAt ?? pendingExitAt ?? now
    }

    func minutesAtGym(now: Date) -> Int {
        Int(max(0, presenceEnd(now: now).timeIntervalSince(arrivedAt)) / 60)
    }

    /// 20 minutes at the gym, when time can be measured at all.
    func presenceQualifies(now: Date) -> Bool {
        timeCounts && presenceEnd(now: now).timeIntervalSince(arrivedAt) >= WorkoutRules.minimumInterval
    }

    /// The last moment anything can still make this visit count.
    func closesAt(calendar: Calendar) -> Date {
        let health = healthAnchor.addingTimeInterval(WorkoutRules.healthWindowAfterArrival)
        guard manualAt != nil,
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: healthAnchor))
        else { return health }
        // "I'm here" can still be proved with a photo that day.
        return max(health, endOfDay)
    }

    func isFinished(now: Date, calendar: Calendar) -> Bool {
        (isCounted && leftAt != nil) || now >= closesAt(calendar: calendar)
    }

    /// When the workout-done notification should fire: at 30 minutes or when
    /// they leave, whichever is first, and only if the workout counts. Nil
    /// when it won't count (as far as is known now).
    func doneNoticeDate() -> Date? {
        let exit = leftAt ?? pendingExitAt
        let stayedLongEnough = exit.map { $0.timeIntervalSince(arrivedAt) >= WorkoutRules.minimumInterval } ?? true
        guard isCounted || (timeCounts && stayedLongEnough) else { return nil }

        var date = arrivedAt.addingTimeInterval(WorkoutRules.doneNoticeAfterArrival)
        // Leaving is only known 5 minutes after the exit.
        if let exit { date = min(date, exit.addingTimeInterval(WorkoutRules.shortTripGrace)) }
        // Health or a photo can prove it later than that: then it goes then.
        if let countedAt, proof == .health || proof == .photo { date = max(date, countedAt) }
        return date
    }

    /// When "you left after N min" should fire, or nil.
    func shortNoticeDate() -> Date? {
        guard !isCounted, timeCounts, let exit = leftAt ?? pendingExitAt,
              exit.timeIntervalSince(arrivedAt) < WorkoutRules.minimumInterval
        else { return nil }
        return exit.addingTimeInterval(WorkoutRules.shortTripGrace)
    }

    /// Minutes at the gym before leaving, for the "you left after" line.
    var minutesBeforeLeaving: Int {
        guard let exit = leftAt ?? pendingExitAt else { return 0 }
        return max(1, Int(exit.timeIntervalSince(arrivedAt) / 60))
    }
}

// MARK: - The notification lines

/// The lines at the gym (FLOW, Flow 3 and the night lock).
nonisolated enum WorkoutDoneLine {
    static let arrival = "you're in. 20 minutes and today counts."
    static let cameBack = "you came back. that's the hardest one."

    /// The count line, with the real number of workouts this week.
    static func countLine(_ count: Int) -> String {
        let goal = StreakPolicy.minimumGymDays
        if count < goal { return "\(count) of \(goal) this week. share your progress." }
        if count == goal { return "that's \(goal). this one keeps your streak." }
        return "\(count) this week. that's a bonus day."
    }

    static func sleepLine(bedtime: String) -> String {
        "workout counted. it cost you sleep though. aim to be home by \(bedtime)."
    }

    static func shortVisit(minutes: Int) -> String {
        "you left after \(minutes) min. 20 minutes makes it count."
    }

    /// The line to send. The comeback line comes first when it is true;
    /// the same line is never sent twice in a row when another true one
    /// exists.
    static func pick(countThisWeek: Int, cameBack isComeback: Bool, last: String?) -> String {
        let candidates = (isComeback ? [cameBack] : []) + [countLine(countThisWeek)]
        return candidates.first { $0 != last } ?? candidates[0]
    }

    /// Whether this is the first counted workout after a missed or skipped
    /// planned day: the last day before `day` with anything recorded was a
    /// miss or a skip, and nothing that day counted.
    static func isComeback(log: MomentumLog, day: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        let earlier = Dictionary(grouping: log.outcomes.filter { $0.countingDay(calendar: calendar) < start }) {
            $0.countingDay(calendar: calendar)
        }
        guard let lastDay = earlier.keys.max(), let outcomes = earlier[lastDay] else { return false }
        guard !outcomes.contains(where: \.counts) else { return false }
        // A skip counts in every shape it has ever had, and so does a
        // reschedule: the day was given up either way.
        return outcomes.contains { [.missed, .easySkip, .dayOff, .skipped, .rescheduled].contains($0.kind) }
    }

    /// Workouts counted this week (Monday to Sunday), each day once.
    static func countThisWeek(log: MomentumLog, day: Date, calendar: Calendar) -> Int {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let start = StreakEngine.weekStart(containing: day, weekCalendar: weekCalendar) else { return 0 }
        return StreakEngine.sessionDays(in: log, weekStarting: start, calendar: calendar).count
    }
}
