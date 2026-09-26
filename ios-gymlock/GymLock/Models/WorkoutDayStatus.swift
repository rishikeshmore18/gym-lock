import Foundation

/// What a single day on the home calendar is allowed to say.
///
/// This is a *presentation* type. It is derived from the existing record —
/// `MomentumLog` and `SessionEventLog` remain the only sources of truth — and it
/// exists so the calendar has one small vocabulary to render instead of
/// reaching into outcome kinds and event streams from inside a view.
///
/// There is deliberately no "failed" case. A day the user skipped is stated as
/// a fact and nothing more.
enum WorkoutDayStatus: String, Hashable, Codable {
    /// GymLock confirmed the user physically got to their gym.
    case verified
    /// A planned session that was recorded as skipped.
    case skipped
    /// Real effort that did not end in a confirmed gym arrival.
    ///
    /// Covers a home workout, a reschedule, a morning where the user got moving
    /// before something interrupted it, and a technical failure that was never
    /// the user's fault.
    case attempted
    /// Nothing was planned, or nothing was ever recorded.
    case neutral
    /// Hasn't happened yet.
    case future
}

/// One day as the calendar strip needs it.
struct TrainingDay: Identifiable, Hashable {
    /// Start of day, in the current calendar.
    let date: Date
    let status: WorkoutDayStatus
    /// Whether the user's schedule calls for training on this weekday.
    let isPlanned: Bool
    let isToday: Bool

    var id: Date { date }
}

/// Maps the app's real records onto calendar days.
///
/// Built once whenever the underlying record changes rather than per cell: the
/// calendar is lazy but can still ask about a few hundred days over a long
/// scroll, and a linear scan of the outcome list for each of them would be
/// needless work on the main thread.
///
/// Nothing here invents history. A planned day that came and went before
/// GymLock was recording anything stays `neutral` — marking it as a skip would
/// be inventing a failure that no part of the app ever witnessed.
struct DayStatusIndex {
    private let outcomeKinds: [Date: SessionOutcomeKind]
    private let effortDays: Set<Date>
    private let trainingDays: Set<Weekday>
    private let today: Date
    private let calendar: Calendar

    static let empty = DayStatusIndex()

    private init() {
        outcomeKinds = [:]
        effortDays = []
        trainingDays = []
        calendar = .current
        today = Calendar.current.startOfDay(for: Date())
    }

    init(
        log: MomentumLog,
        events: SessionEventLog,
        trainingDays: Set<Weekday>,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.calendar = calendar
        self.trainingDays = trainingDays
        today = calendar.startOfDay(for: now)

        // Later outcomes win, matching `MomentumLog.outcome(on:)`, so the two
        // can never disagree about the same day.
        var kinds: [Date: SessionOutcomeKind] = [:]
        for outcome in log.outcomes {
            kinds[outcome.countingDay(calendar: calendar)] = outcome.kind
        }
        outcomeKinds = kinds

        effortDays = Set(
            events.events
                .filter { Self.showsEffort($0.kind) }
                .map { calendar.startOfDay(for: $0.at) }
        )
    }

    /// Events that mean the user themselves did something.
    ///
    /// `alarmFired` is excluded on purpose: that is GymLock acting, not the
    /// user, and crediting it as effort would be flattering them with their own
    /// alarm clock.
    private static func showsEffort(_ kind: SessionEventKind) -> Bool {
        switch kind {
        case .committed, .missionCompleted, .departed, .gymArrivalCandidate,
             .gymArrivalVerified, .quickWorkoutCompleted:
            true
        default:
            false
        }
    }

    func day(for date: Date) -> TrainingDay {
        let start = calendar.startOfDay(for: date)
        return TrainingDay(
            date: start,
            status: status(for: start),
            isPlanned: isPlannedDay(start),
            isToday: start == today
        )
    }

    private func isPlannedDay(_ start: Date) -> Bool {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: start)) else {
            return false
        }
        return trainingDays.contains(weekday)
    }

    private func status(for start: Date) -> WorkoutDayStatus {
        if start > today { return .future }

        if let kind = outcomeKinds[start] {
            switch kind {
            case .showedUp:
                return .verified
            case .missed, .easySkip:
                return .skipped
            // A home workout is real effort that GymLock could not verify at a
            // gym, and the app has never been willing to blur those two. It
            // keeps the momentum streak; it does not earn the verified mark.
            case .homeWorkout, .rescheduled, .technicalFailure:
                return .attempted
            case .dayOff:
                return .neutral
            }
        }

        return effortDays.contains(start) ? .attempted : .neutral
    }
}
