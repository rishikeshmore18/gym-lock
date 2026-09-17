import Foundation

/// What actually happened on a planned session.
///
/// The distinction between `showedUp` and `homeWorkout` is the whole point of
/// this type: one of them is a gym visit and one of them is not, and the app is
/// not allowed to blur that even though both protect momentum.
enum SessionOutcomeKind: String, Codable, Hashable {
    /// Confirmed physical arrival at the configured gym.
    ///
    /// Named for exactly what it means. It is not a claim that the user
    /// exercised — GymLock cannot know that and does not pretend to. It means
    /// they got themselves there, which is the behaviour the product exists to
    /// change.
    case showedUp
    case homeWorkout
    case easySkip
    case dayOff
    case rescheduled
    case missed
    /// Detection failed for technical reasons. Recorded so it can be
    /// investigated, but it neither credits nor punishes the user.
    case technicalFailure

    /// Whether this keeps the momentum streak alive.
    ///
    /// A technical failure does not preserve momentum, but it is also not a
    /// miss: it sits outside the streak rather than breaking it.
    var preservesMomentum: Bool {
        switch self {
        case .showedUp, .homeWorkout: true
        case .easySkip, .dayOff, .rescheduled, .missed, .technicalFailure: false
        }
    }

    /// Whether this counts as a visit to the gym.
    var isVerifiedGymVisit: Bool { self == .showedUp }

    /// Whether it draws down the easy-skip allowance.
    var usesSkipAllowance: Bool {
        switch self {
        case .easySkip, .dayOff: true
        default: false
        }
    }
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

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: SessionOutcomeKind,
        minutes: Int? = nil,
        sessionID: UUID? = nil,
        workoutDetected: Bool = false
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.minutes = minutes
        self.sessionID = sessionID
        self.workoutDetected = workoutDetected
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

    /// Verified gym visits inside the current calendar month.
    var verifiedGymVisitsThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        return outcomes.filter {
            $0.kind.isVerifiedGymVisit && calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count
    }

    var totalVerifiedGymVisits: Int {
        outcomes.filter(\.kind.isVerifiedGymVisit).count
    }

    /// The outcome recorded on a given day, if the morning already resolved.
    func outcome(on day: Date = Date(), calendar: Calendar = .current) -> SessionOutcome? {
        outcomes.last { calendar.isDate($0.date, inSameDayAs: day) }
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
                calendar.isDate($0.date, inSameDayAs: day) && $0.kind.preservesMomentum
            }
        }
    }

    // MARK: Easy skips

    /// Skips used in the trailing 28 days.
    func skipsUsedInLast28Days(now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-28 * 24 * 3600)
        return outcomes.filter { $0.date >= cutoff && $0.kind.usesSkipAllowance }.count
    }

    /// How many no-questions-asked skips the user gets in a rolling 28 days.
    ///
    /// Roughly a fifth of what they planned, floored at one and capped at three.
    /// This is a product rule about how much friction to add, not a claim about
    /// physiology, and nothing in the UI presents it as one.
    static func easySkipAllowance(plannedSessionsIn28Days planned: Int) -> Int {
        min(3, max(1, Int((Double(planned) * 0.20).rounded(.down))))
    }

    /// Whether the user still has an easy skip left.
    func hasEasySkipRemaining(plannedSessionsIn28Days planned: Int, now: Date = Date()) -> Bool {
        skipsUsedInLast28Days(now: now) < Self.easySkipAllowance(plannedSessionsIn28Days: planned)
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
