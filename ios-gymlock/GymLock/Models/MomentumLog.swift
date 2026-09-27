import Foundation

/// What actually happened on a planned session.
///
/// The distinction between `showedUp` and `homeWorkout` is the whole point of
/// this type: one of them is a gym visit and one of them is not, and the app is
/// not allowed to blur that even though both protect momentum.
enum SessionOutcomeKind: String, Codable, Hashable {
    /// Arrived at the gym. On its own this is a gym visit and does not count;
    /// it counts once the workout is done (`SessionOutcome.proof`).
    case showedUp
    /// The 20-minute workout at home. Counts once Apple Health confirms it or
    /// a camera progress photo lands (`SessionOutcome.proof`); records saved
    /// before the check existed decode as `legacy` and keep counting.
    case homeWorkout
    case easySkip
    case dayOff
    case skipped
    case rescheduled
    case missed
    /// Detection failed for technical reasons. Recorded so it can be
    /// investigated, but it neither credits nor punishes the user.
    case technicalFailure

    /*
     * The 28-day easy-skip allowance is gone (FLOW, Flow 4). `.easySkip` and
     * `.dayOff` stay only so records saved by older builds still decode; new
     * skips are all recorded as `.skipped`.
     */
}

/// One recorded outcome.
struct SessionOutcome: Codable, Hashable, Identifiable {
    var id: UUID
    var date: Date
    var kind: SessionOutcomeKind
    /// Minutes, for a home workout.
    var minutes: Int?
    /// Which session produced this, so a late Health workout can find it again.
    var sessionID: UUID?
    /// Set when Apple Health independently recorded a workout.
    ///
    /// Strictly additive: its absence is never shown as a failure, because most
    /// people lifting weights are not wearing a watch that logs it.
    var workoutDetected: Bool
    /// The day this outcome counts on: the start of the alarm's day for
    /// anything recorded from a session. A Sunday 23:30 alarm with the visit
    /// at 00:20 counts on Sunday. Nil on records saved before this existed,
    /// which count on the day they were recorded, exactly as before.
    var countsOn: Date?
    /// Why it counts. A gym arrival starts `unproven` and counts once the
    /// workout is done. Records saved before this existed decode as `legacy`
    /// (arrivals and home workouts), so every past week keeps its result.
    var proof: WorkoutProof

    /// `proof` left out means `legacy` for arrivals and home workouts, which
    /// is what every record built before this change meant. The session code
    /// passes `unproven` for a new arrival.
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: SessionOutcomeKind,
        minutes: Int? = nil,
        sessionID: UUID? = nil,
        workoutDetected: Bool = false,
        countsOn: Date? = nil,
        proof: WorkoutProof? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.minutes = minutes
        self.sessionID = sessionID
        self.workoutDetected = workoutDetected
        self.countsOn = countsOn
        self.proof = proof ?? Self.legacyProof(for: kind)
    }

    private static func legacyProof(for kind: SessionOutcomeKind) -> WorkoutProof {
        kind == .showedUp || kind == .homeWorkout ? .legacy : .unproven
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, kind, minutes, sessionID, workoutDetected, countsOn, proof
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        kind = try container.decode(SessionOutcomeKind.self, forKey: .kind)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        workoutDetected = try container.decodeIfPresent(Bool.self, forKey: .workoutDetected) ?? false
        countsOn = try container.decodeIfPresent(Date.self, forKey: .countsOn)
        proof = (try? container.decodeIfPresent(WorkoutProof.self, forKey: .proof)) ?? Self.legacyProof(for: kind)
    }

    /// The one answer to "does this count?" (FLOW, Flow 3 and Flow 4). A gym
    /// arrival counts once the workout is done; a home workout counts once it
    /// is verified.
    var counts: Bool {
        switch kind {
        case .showedUp, .homeWorkout: proof != .unproven
        case .easySkip, .dayOff, .skipped, .rescheduled, .missed, .technicalFailure: false
        }
    }

    /// "Verified": a gym workout that was done. A GPS arrival alone is only
    /// a gym visit.
    var isVerifiedWorkout: Bool { kind == .showedUp && counts }

    /// An arrival whose workout isn't done (yet).
    var isGymVisitOnly: Bool { kind == .showedUp && !counts }

    /// The one definition of which day this outcome counts on.
    ///
    /// Every place that puts an outcome on a day (the streak, the week count,
    /// Progress, the calendar, the share frames) asks this and nothing else.
    func countingDay(calendar: Calendar) -> Date {
        calendar.startOfDay(for: countsOn ?? date)
    }
}

/// The honest ledger.
///
/// Two numbers are tracked separately and never conflated:
///
/// - **Momentum streak** — kept weeks in a row, derived from this ledger by
///   `StreakEngine`. A home fallback keeps it.
/// - **Verified gym visits** — only real, verified trips to the gym.
///
/// Calling the first one a "gym streak" while a living-room workout maintains it
/// would be a lie the user would eventually catch, and the whole product rests
/// on them believing the numbers.
///
/// The streak itself is deliberately *not* a property here. It depends on the
/// plan and on banked freezes as well as on these outcomes, so it lives on
/// `AppStore.streak`, where all three meet.
struct MomentumLog: Codable, Hashable {
    var outcomes: [SessionOutcome]

    static let empty = MomentumLog(outcomes: [])

    // MARK: Recording

    mutating func record(_ outcome: SessionOutcome) {
        outcomes.append(outcome)
        // Bounded: this drives streaks and a rolling 28-day window, so a year of
        // history is already far more than anything reads.
        if outcomes.count > 400 {
            outcomes.removeFirst(outcomes.count - 400)
        }
    }

    // MARK: Momentum

    /// Verified gym workouts inside the current calendar month.
    var verifiedGymVisitsThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        return outcomes.filter {
            $0.isVerifiedWorkout
                && calendar.isDate($0.countingDay(calendar: calendar), equalTo: now, toGranularity: .month)
        }.count
    }

    var totalVerifiedGymVisits: Int {
        outcomes.filter(\.isVerifiedWorkout).count
    }

    /// Marks a recorded gym visit counted, with its proof. Returns whether
    /// anything changed.
    @discardableResult
    mutating func markCounted(outcomeID: UUID, proof: WorkoutProof) -> Bool {
        guard let index = outcomes.lastIndex(where: { $0.id == outcomeID }),
              outcomes[index].proof == .unproven
        else { return false }
        outcomes[index].proof = proof
        if proof == .health { outcomes[index].workoutDetected = true }
        return true
    }

    /// Notes that Apple Health saw a qualifying workout for this outcome.
    @discardableResult
    mutating func markWorkoutDetected(outcomeID: UUID) -> Bool {
        guard let index = outcomes.lastIndex(where: { $0.id == outcomeID }),
              !outcomes[index].workoutDetected
        else { return false }
        outcomes[index].workoutDetected = true
        return true
    }

    /// The outcome that stands for a given day. A counted one wins over a
    /// gym visit that didn't count, so a second visit can't hide the first.
    func outcome(on day: Date = Date(), calendar: Calendar = .current) -> SessionOutcome? {
        let onDay = outcomes.filter { calendar.isDate($0.countingDay(calendar: calendar), inSameDayAs: day) }
        return onDay.last(where: \.counts) ?? onDay.last
    }

    /// The last outcome *written* on a given calendar day, whatever day it
    /// counts on. For finding a record again (a late Health workout), never
    /// for counting.
    func outcome(recordedOn moment: Date, calendar: Calendar = .current) -> SessionOutcome? {
        outcomes.last { calendar.isDate($0.date, inSameDayAs: moment) }
    }

    /// Attaches a detected workout to an already-recorded outcome.
    ///
    /// Health writes a workout when it *ends*, which can be an hour after the
    /// user walked into the gym and long after the outcome was recorded. This is
    /// how that arrives late without creating a duplicate visit.
    ///
    /// Returns whether anything changed, so callers can avoid a pointless write.
    @discardableResult
    mutating func attachWorkout(toSession sessionID: UUID) -> Bool {
        guard let index = outcomes.lastIndex(where: { $0.sessionID == sessionID }) else {
            return false
        }
        guard !outcomes[index].workoutDetected else { return false }
        outcomes[index].workoutDetected = true
        return true
    }

    /// Momentum-preserving days over the last fortnight, for the sparkline.
    func recentMomentum(days: Int = 14) -> [Bool] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<days).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return false
            }
            return outcomes.contains {
                calendar.isDate($0.countingDay(calendar: calendar), inSameDayAs: day) && $0.counts
            }
        }
    }

}

// MARK: - Departure messages

/// The single positive message sent when the user actually leaves.
///
/// One message, once. The commitment has already been made by this point, and
/// anything that keeps buzzing afterwards is nagging someone who is already
/// doing the thing.
enum DepartureMessage {
    static let pool: [(title: String, body: String)] = [
        ("LET'S GO 🔥", "You're moving. Gym next."),
        ("First decision won.", "Keep moving."),
        ("Momentum started.", "Just get there."),
        ("You're out the door.", "Finish the trip."),
        ("That's the hard part done.", "The rest is just travel."),
    ]

    /// Picks a message that is not the one used last time.
    static func next(after previous: Int?) -> (index: Int, title: String, body: String) {
        let candidates = pool.indices.filter { $0 != previous }
        let index = candidates.randomElement() ?? 0
        let message = pool[index]
        return (index, message.title, message.body)
    }
}
