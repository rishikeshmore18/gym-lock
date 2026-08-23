import Foundation

/// What actually happened on a planned session.
///
/// The distinction between `gymVerified` and `homeWorkout` is the whole point of
/// this type: one of them is a gym visit and one of them is not, and the app is
/// not allowed to blur that even though both protect momentum.
enum SessionOutcomeKind: String, Codable, Hashable {
    case gymVerified
    case homeWorkout
    case easySkip
    case dayOff
    case rescheduled
    case missed

    /// Whether this keeps the momentum streak alive.
    var preservesMomentum: Bool {
        switch self {
        case .gymVerified, .homeWorkout: true
        case .easySkip, .dayOff, .rescheduled, .missed: false
        }
    }

    /// Whether this counts as an actual, verified visit to a gym.
    var isVerifiedGymVisit: Bool { self == .gymVerified }

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

    init(id: UUID = UUID(), date: Date = Date(), kind: SessionOutcomeKind, minutes: Int? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.minutes = minutes
    }
}

/// The honest ledger.
///
/// Two numbers are tracked separately and never conflated:
///
/// - **Momentum streak** — consecutive days on which the user did something they
///   agreed counts. A home fallback keeps it.
/// - **Verified gym visits** — only real, verified trips to the gym.
///
/// Calling the first one a "gym streak" while a living-room workout maintains it
/// would be a lie the user would eventually catch, and the whole product rests
/// on them believing the numbers.
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

    /// Consecutive days, counting back from the most recent recorded day, on
    /// which momentum was preserved.
    ///
    /// Rest days do not break it: only a *recorded* day that failed to preserve
    /// momentum does. Someone training three times a week is not on a broken
    /// streak for not training on Tuesday.
    var momentumStreak: Int {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: outcomes) { calendar.startOfDay(for: $0.date) }
        let days = byDay.keys.sorted(by: >)

        var streak = 0
        for day in days {
            let dayOutcomes = byDay[day] ?? []
            guard dayOutcomes.contains(where: { $0.kind.preservesMomentum }) else { break }
            streak += 1
        }
        return streak
    }

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
