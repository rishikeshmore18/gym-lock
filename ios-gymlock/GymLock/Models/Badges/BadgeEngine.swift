import Foundation

// MARK: - State

/// How far a locked badge has come, in the unit its rule counts.
struct BadgeProgress: Hashable {
    enum Unit: Hashable {
        /// Kept weeks in a row: the live streak.
        case weeksInARow
        /// Distinct counted workout days.
        case workoutDays
        /// Verified gym workouts.
        case gymWorkouts
        /// Kept weeks in a row with no freeze between them.
        case cleanWeeks
    }

    let current: Int
    let target: Int
    let unit: Unit

    var remaining: Int { max(0, target - current) }
    var fraction: Double { target > 0 ? min(1, Double(current) / Double(target)) : 0 }
}

/// What a badge is right now. Never stored: rebuilt from the record, with the
/// one exception `BadgeStore` makes so an earned badge cannot be lost when
/// the ledger trims its oldest outcomes.
enum BadgeState: Hashable {
    /// Earned. The date is the day the record proves it happened, or nil when
    /// it was earned on history the ledger no longer holds.
    case earned(on: Date?)
    /// Not yet. Progress only where the rule has a count to show.
    case locked(BadgeProgress?)

    var isEarned: Bool {
        if case .earned = self { return true }
        return false
    }

    var unlockedOn: Date? {
        if case let .earned(date) = self { return date }
        return nil
    }

    var progress: BadgeProgress? {
        if case let .locked(progress) = self { return progress }
        return nil
    }
}

// MARK: - Facts

/// Everything the badges need, read once from the ledger and the streak.
///
/// Every number here has exactly one source: session days and weeks are
/// `StreakEngine`'s, "counts" is `SessionOutcome.counts`, and a verified gym
/// workout is `SessionOutcome.isVerifiedWorkout`. Scheduled, skipped, missed
/// and unproven days never appear, because none of them count.
struct BadgeFacts: Hashable {
    /// One week as `StreakEngine` ruled on it.
    struct Week: Hashable {
        let start: Date
        let goal: Int
        /// Session days, oldest first.
        let sessionDays: [Date]
        let isKept: Bool
        /// Protected by a freeze: neither counted nor broken.
        let isFrozen: Bool
        /// The streak at the end of this week (for the live week, right now).
        let streakThrough: Int
        let isLive: Bool

        /// The day the goal was met: the session day that kept the week.
        var keptOn: Date? {
            guard isKept, goal > 0, sessionDays.count >= goal else { return nil }
            return sessionDays[goal - 1]
        }

        /// A completed week that was neither kept nor frozen.
        var isBroken: Bool { !isLive && !isKept && !isFrozen }
    }

    /// Oldest first, ending with the live week.
    var weeks: [Week] = []
    /// The live streak, exactly as the Progress tile shows it.
    var currentStreak = 0
    /// Distinct days with a counted workout, oldest first.
    var workoutDays: [Date] = []
    /// Days with a counted home workout (Quick 20).
    var homeWorkoutDays: Set<Date> = []
    /// The counting day of every verified gym workout, oldest first.
    var gymWorkoutDays: [Date] = []
    var firstHomeWorkout: Date?
    var firstHealthProof: Date?
    var firstEarlyStart: Date?
    var firstLateFinish: Date?
    var firstReturnAfterGap: Date?

    static let empty = BadgeFacts()

    // MARK: Derived

    var bestStreak: Int {
        max(currentStreak, weeks.map(\.streakThrough).max() ?? 0)
    }

    /// The day the streak first reached `weeks`.
    func streakReached(_ target: Int) -> Date? {
        weeks.first { $0.streakThrough >= target }?.keptOn
    }

    /// The first kept week after a completed week broke a running streak.
    var comebackDay: Date? {
        var previous = 0
        var awaitingReturn = false
        for week in weeks {
            if week.isKept, awaitingReturn { return week.keptOn }
            if week.isBroken, previous > 0 { awaitingReturn = true }
            previous = week.streakThrough
        }
        return nil
    }

    /// The first kept week straight after a frozen one.
    var recoveryDay: Date? {
        for (before, week) in zip(weeks, weeks.dropFirst()) where before.isFrozen && week.isKept {
            return week.keptOn
        }
        return nil
    }

    /// The first session day beyond a week's goal.
    var overachieverDay: Date? {
        for week in weeks where week.goal > 0 && week.sessionDays.count > week.goal {
            return week.sessionDays[week.goal]
        }
        return nil
    }

    /// The first kept week whose goal was met by a home workout.
    var homeSaverDay: Date? {
        for week in weeks {
            if let day = week.keptOn, homeWorkoutDays.contains(day) { return day }
        }
        return nil
    }

    /// Kept weeks in a row with no freeze between them: the best run, the
    /// run still alive, and the day a run first reached `target`.
    func cleanRun(target: Int) -> (best: Int, current: Int, reachedOn: Date?) {
        var run = 0
        var best = 0
        var reachedOn: Date?
        for week in weeks {
            if week.isKept {
                run += 1
                if run == target, reachedOn == nil { reachedOn = week.keptOn }
            } else if !week.isLive {
                run = 0
            }
            best = max(best, run)
        }
        return (best, run, reachedOn)
    }
}

// MARK: - Engine

/// Reads the ledger into `BadgeFacts`. Pure: `now` and `calendar` are passed
/// in so every rule can be pinned by a test.
enum BadgeEngine {
    /// A workout started before this hour is an early one.
    static let earlyStartHour = 7
    /// A workout finished at or after this hour is a late one.
    static let lateFinishHour = 21
    /// Days between two workout days that make a return: 14 empty days.
    static let returnGapDays = 15
    /// No history is replayed further back than this.
    private static let maximumWeeks = 520

    static func facts(
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        vault: StreakVault,
        now: Date,
        calendar: Calendar = .current
    ) -> BadgeFacts {
        var facts = BadgeFacts()
        let counted = log.outcomes.filter(\.counts)
        func day(_ outcome: SessionOutcome) -> Date { outcome.countingDay(calendar: calendar) }

        facts.workoutDays = Set(counted.map(day)).sorted()
        let home = counted.filter { $0.kind == .homeWorkout }
        facts.homeWorkoutDays = Set(home.map(day))
        facts.firstHomeWorkout = home.map(day).min()
        facts.gymWorkoutDays = counted.filter(\.isVerifiedWorkout).map(day).sorted()
        facts.firstHealthProof = counted.filter { $0.proof == .health }.map(day).min()
        facts.firstEarlyStart = counted.filter { isEarlyStart($0, calendar: calendar) }.map(day).min()
        facts.firstLateFinish = counted.filter { isLateFinish($0, calendar: calendar) }.map(day).min()
        for (previous, next) in zip(facts.workoutDays, facts.workoutDays.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: next).day ?? 0
            if gap >= returnGapDays {
                facts.firstReturnAfterGap = next
                break
            }
        }

        facts.weeks = weeks(log: log, plan: plan, schedule: schedule, vault: vault, now: now, calendar: calendar)
        facts.currentStreak = facts.weeks.last?.streakThrough ?? 0
        return facts
    }

    /// Gym: the arrival time, which is when the workout started. Home: the
    /// time it was finished, so it started earlier still. Either way only on
    /// the day it counts on, so a Sunday-night alarm's 00:20 visit is not a
    /// sunrise.
    static func isEarlyStart(_ outcome: SessionOutcome, calendar: Calendar) -> Bool {
        guard outcome.counts,
              calendar.isDate(outcome.date, inSameDayAs: outcome.countingDay(calendar: calendar))
        else { return false }
        return calendar.component(.hour, from: outcome.date) < earlyStartHour
    }

    /// Gym: arrived late, so finished later still. Home: the finish itself.
    static func isLateFinish(_ outcome: SessionOutcome, calendar: Calendar) -> Bool {
        guard outcome.counts,
              calendar.isDate(outcome.date, inSameDayAs: outcome.countingDay(calendar: calendar))
        else { return false }
        return calendar.component(.hour, from: outcome.date) >= lateFinishHour
    }

    /// Every week from the first outcome to the live one, as `StreakEngine`
    /// ruled on it.
    ///
    /// The engine only reports the streak as of `now`, so each completed week
    /// is read by evaluating as of the Monday after it, on a throwaway copy of
    /// the vault. The vault has already ruled on every completed week, so the
    /// replay spends no freezes and re-judges nothing: it uses the goals and
    /// freezes that were saved at the time. A week is kept exactly when the
    /// streak rose across it.
    private static func weeks(
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule,
        vault: StreakVault,
        now: Date,
        calendar: Calendar
    ) -> [BadgeFacts.Week] {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        var base = vault
        let live = StreakEngine.evaluate(
            log: log, plan: plan, schedule: schedule, vault: &base, now: now, calendar: calendar
        )

        var result: [BadgeFacts.Week] = []
        var previous = 0

        if let earliest = log.outcomes.map({ $0.countingDay(calendar: calendar) }).min(),
           var cursor = StreakEngine.weekStart(containing: earliest, weekCalendar: weekCalendar) {
            while cursor < live.liveWeekStart, result.count < maximumWeeks {
                guard let next = weekCalendar.date(byAdding: .weekOfYear, value: 1, to: cursor),
                      let nextStart = StreakEngine.weekStart(containing: next, weekCalendar: weekCalendar),
                      nextStart > cursor
                else { break }

                var replay = base
                let snapshot = StreakEngine.evaluate(
                    log: log, plan: plan, schedule: schedule, vault: &replay, now: nextStart, calendar: calendar
                )
                let through = snapshot.weeks - (snapshot.isThisWeekKept ? 1 : 0)
                let isKept = through == previous + 1
                result.append(BadgeFacts.Week(
                    start: cursor,
                    goal: base.savedGoal(forWeekStarting: cursor, calendar: calendar) ?? live.weeklyGoal,
                    sessionDays: StreakEngine.sessionDays(in: log, weekStarting: cursor, calendar: calendar),
                    isKept: isKept,
                    isFrozen: !isKept && base.isFrozen(weekStarting: cursor, calendar: calendar),
                    streakThrough: through,
                    isLive: false
                ))
                previous = through
                cursor = nextStart
            }
        }

        result.append(BadgeFacts.Week(
            start: live.liveWeekStart,
            goal: live.weeklyGoal,
            sessionDays: StreakEngine.sessionDays(in: log, weekStarting: live.liveWeekStart, calendar: calendar),
            isKept: live.isThisWeekKept,
            isFrozen: false,
            streakThrough: live.weeks,
            isLive: true
        ))
        return result
    }
}

// MARK: - Rules

/// Turns the facts into each badge's state. The thresholds are the catalog's,
/// so the art, the rule text and the check can never disagree.
enum BadgeRules {
    static let gymRegularTarget = 25
    static let cleanRunTarget = 8

    static func states(for facts: BadgeFacts) -> [String: BadgeState] {
        var states: [String: BadgeState] = [:]
        for badge in BadgeCatalog.all {
            states[badge.id] = state(for: badge, facts: facts)
        }
        return states
    }

    static func state(for badge: BadgeDefinition, facts: BadgeFacts) -> BadgeState {
        switch badge.group {
        case .streak:
            let target = badge.number ?? 0
            if facts.bestStreak >= target {
                return .earned(on: facts.streakReached(target))
            }
            return .locked(progress(facts.currentStreak, target, .weeksInARow))

        case .days:
            let target = badge.number ?? 0
            let days = facts.workoutDays
            if target > 0, days.count >= target {
                return .earned(on: days[target - 1])
            }
            return .locked(progress(days.count, target, .workoutDays))

        case .achievement:
            return achievement(badge.id, facts: facts)
        }
    }

    private static func achievement(_ id: String, facts: BadgeFacts) -> BadgeState {
        func once(_ date: Date?) -> BadgeState { date.map { .earned(on: $0) } ?? .locked(nil) }

        switch id {
        case "first-proof": return once(facts.gymWorkoutDays.first)
        case "home-hero": return once(facts.firstHomeWorkout)
        case "health-synced": return once(facts.firstHealthProof)
        case "comeback": return once(facts.comebackDay)
        case "second-wind": return once(facts.firstReturnAfterGap)
        case "overachiever": return once(facts.overachieverDay)
        case "recovery": return once(facts.recoveryDay)
        case "sunrise": return once(facts.firstEarlyStart)
        case "night-owl": return once(facts.firstLateFinish)
        case "home-saver": return once(facts.homeSaverDay)
        case "gym-regular":
            let gym = facts.gymWorkoutDays
            if gym.count >= gymRegularTarget { return .earned(on: gym[gymRegularTarget - 1]) }
            return .locked(progress(gym.count, gymRegularTarget, .gymWorkouts))
        case "clean-run":
            let run = facts.cleanRun(target: cleanRunTarget)
            if run.best >= cleanRunTarget { return .earned(on: run.reachedOn) }
            return .locked(progress(run.current, cleanRunTarget, .cleanWeeks))
        default:
            return .locked(nil)
        }
    }

    private static func progress(_ current: Int, _ target: Int, _ unit: BadgeProgress.Unit) -> BadgeProgress {
        BadgeProgress(current: min(current, target), target: target, unit: unit)
    }
}
