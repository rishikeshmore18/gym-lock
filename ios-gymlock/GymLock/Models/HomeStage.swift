import Foundation

/// One rendered frame of home's card section, derived entirely from real state.
///
/// Everything in here is a pure function of the session, the ledger, the plan
/// and the clock — nothing is invented to fill a slot, and a state that cannot
/// be backed by data simply does not appear (see the guards on the chart and
/// the month metrics). The views downstream are dumb on purpose: they draw
/// whatever this says.
struct HomeCardModel: Equatable {
    var hero: HeroStage
    var protection: ProtectionCard
    var next: NextCard
    var path: PathCard
    /// The accumulated-proof layer below the cards. Defaulted so every stage
    /// can be constructed without restating it; `derive` fills it in once.
    var momentum: MomentumField = .empty

    /// 0–4, how far through today's commitment the user is. Observed by home so
    /// a step forward can earn its haptic exactly once.
    var pathStep: Int { path.completedSteps }
}

// MARK: - Hero stages

/// Every shape the hero card can take.
///
/// The associated values carry only what the copy needs — the visuals each
/// stage uses are decided by the view, per the visual mapping.
enum HeroStage: Equatable {
    /// Setup not finished: checklist hero.
    case setupIncomplete(items: [ChecklistItem])
    /// Nothing has happened yet: tomorrow's commitment.
    case firstDay(alarm: TimeOfDay)
    /// Late evening: rest now, next alarm queued.
    case night(bedtime: TimeOfDay, nextAlarm: TimeOfDay?)
    /// Next alarm inside two hours: live countdown.
    case countdown(secondsRemaining: Int, windowSeconds: Int)
    /// Committed, getting ready.
    case committed(step: Int, total: Int)
    /// Out the door.
    case departed(step: Int, total: Int, nearGym: Bool)
    /// Confirmed at the gym.
    case arrived(step: Int, total: Int)
    /// The day resolved as a win.
    case verified(step: Int, total: Int, streak: Int)
    /// Today was a miss: new start.
    case missed
    /// Coming back after a miss, today is the chance.
    case comeback
    /// Today is not a training day.
    case restDay(nextDay: String, nextTime: String?)
    /// In-week progress: N of M sessions.
    case weekProgress(done: Int, of: Int, useDots: Bool)
    /// Multi-week insight: best weekday.
    case pattern(weekdayLabels: [String], values: [Int], bestIndex: Int)
    /// A month closed: two headline metrics.
    case monthComplete(sessions: Int, consistency: Int)
    /// A new month began: the record so far and this month's goal.
    case startMonth(totalSessions: Int, goal: Int)
    /// Mid-month progress with a linear bar.
    case midMonth(done: Int, of: Int, percent: Int)
    /// Late month: the streak has become an identity.
    case latePattern(momentumWeeks: Int)
}

/// One row of the setup checklist.
struct ChecklistItem: Equatable, Identifiable {
    let id: String
    let label: String
    let isDone: Bool
}

// MARK: - Mini card states

/// Card 1 — what the lock is doing. Role fixed, content evolving.
struct ProtectionCard: Equatable {
    enum Mood: Equatable {
        /// Shield actively applied.
        case shielding
        /// Earned back by arrival.
        case released
        /// Armed and waiting for the alarm.
        case ready
        /// Nothing selected yet.
        case unset
    }

    var mood: Mood
    var appCount: Int
    /// Short supporting line, e.g. "until verification".
    var detail: String
}

/// Card 2 — what happens next.
struct NextCard: Equatable {
    var eyebrow: String
    /// The dominant line: a time, a word, a day.
    var value: String
    /// Optional second line under the value.
    var detail: String?
    var showsArrow: Bool
}

/// Card 3 — the four-step path.
struct PathCard: Equatable {
    var completedSteps: Int
    var totalSteps: Int = 4
    /// Rest days and similar states show a phrase instead of dots.
    var placeholder: String?
}

// MARK: - Derivation

enum HomeCardDeriver {
    /// Builds the full home model: the card section, then the record below it,
    /// then a pass that stops two cards saying the same thing.
    static func derive(
        store: AppStore,
        coordinator: GymSessionCoordinator,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HomeCardModel {
        var model = cardSection(
            store: store,
            coordinator: coordinator,
            now: now,
            calendar: calendar
        )

        model.momentum = MomentumField.build(
            log: store.log,
            plan: store.plan,
            schedule: store.schedule,
            now: now,
            calendar: calendar
        )

        return deduplicated(model, store: store, now: now, calendar: calendar)
    }

    /// Builds the four cards from live state.
    ///
    /// Precedence runs from most specific to most general: a morning in
    /// progress beats today's outcome, which beats a comeback, which beats the
    /// aggregates. Anything the data cannot support falls through to an honest
    /// simpler state.
    private static func cardSection(
        store: AppStore,
        coordinator: GymSessionCoordinator,
        now: Date,
        calendar: Calendar
    ) -> HomeCardModel {
        let session = coordinator.session
        let isSameDay = session.map { calendar.isDate($0.day, inSameDayAs: now) } ?? false

        // 1. A morning in progress owns the hero.
        if let session, isSameDay, session.state.isLive || session.state == .completed {
            return model(for: session, store: store, coordinator: coordinator, now: now, calendar: calendar)
        }

        // 2. How today resolved, if it did.
        if let outcome = store.log.outcome(on: now, calendar: calendar) {
            switch outcome.kind {
            case .showedUp, .homeWorkout:
                return resolvedModel(
                    streak: store.streak.weeks,
                    store: store, coordinator: coordinator, now: now, calendar: calendar
                )
            case .missed:
                return HomeCardModel(
                    hero: .missed,
                    protection: protection(store, coordinator: coordinator, session: nil),
                    next: nextIdle(store, now: now, calendar: calendar),
                    path: PathCard(completedSteps: 0, placeholder: "Today reset — tomorrow is ready")
                )
            default:
                break
            }
        }

        // 3. Coming back from a miss.
        if isComebackDay(store: store, now: now, calendar: calendar) {
            return HomeCardModel(
                hero: .comeback,
                protection: protection(store, coordinator: coordinator, session: nil),
                next: nextIdle(store, now: now, calendar: calendar),
                path: PathCard(completedSteps: 0, placeholder: nil)
            )
        }

        // 4. Setup still open. This outranks every alarm state below it: a
        // commitment the system cannot actually enforce is not the thing to be
        // showing someone.
        let setup = setupChecklist(store: store, coordinator: coordinator)
        if !setup.allSatisfied {
            return HomeCardModel(
                hero: .setupIncomplete(items: setup.items),
                protection: protection(store, coordinator: coordinator, session: nil),
                next: nextIdle(store, now: now, calendar: calendar),
                path: PathCard(completedSteps: 0, placeholder: "Finish setup to begin")
            )
        }

        // 5. Night.
        let hour = calendar.component(.hour, from: now)
        if hour >= 21 || hour < 4 {
            let nextAlarm = store.plan.nextOccurrence(after: now, calendar: calendar)?.slot.alarmTime
            return HomeCardModel(
                hero: .night(bedtime: store.plan.rhythm.bedtime, nextAlarm: nextAlarm),
                protection: protection(store, coordinator: coordinator, session: nil),
                next: nextIdle(store, now: now, calendar: calendar),
                path: PathCard(completedSteps: 0, placeholder: "Tomorrow is ready")
            )
        }

        // 6. Countdown to the alarm.
        if let countdown = countdownStage(store: store, now: now, calendar: calendar) {
            return HomeCardModel(
                hero: countdown,
                protection: protection(store, coordinator: coordinator, session: nil),
                next: nextIdle(store, now: now, calendar: calendar),
                path: PathCard(completedSteps: 0, placeholder: nil)
            )
        }

        // 7. The very first days.
        if store.log.outcomes.isEmpty {
            let alarm = store.plan.enabledSlots.first?.alarmTime ?? store.schedule.gymTime
            return HomeCardModel(
                hero: .firstDay(alarm: alarm),
                protection: protection(store, coordinator: coordinator, session: nil),
                next: nextIdle(store, now: now, calendar: calendar),
                path: PathCard(completedSteps: 0, placeholder: nil)
            )
        }

        // 8. The record, once there is one.
        if let aggregate = aggregateStage(store: store, coordinator: coordinator, now: now, calendar: calendar) {
            return aggregate
        }

        // 9. Rest of a training week with nothing yet to count.
        return restDayModel(store: store, coordinator: coordinator, now: now, calendar: calendar)
    }

    // MARK: Live session

    private static func model(
        for session: GymSession,
        store: AppStore,
        coordinator: GymSessionCoordinator,
        now: Date,
        calendar: Calendar
    ) -> HomeCardModel {
        let total = 4
        let streak = store.streak.weeks

        let hero: HeroStage
        let pathSteps: Int

        switch session.state {
        case .alarmFired, .awaitingDecision, .snoozed, .activationMission, .preparing:
            hero = .committed(step: 1, total: total)
            pathSteps = 1
        case .quickWorkoutOffered, .quickWorkoutActive:
            hero = .committed(step: 1, total: total)
            pathSteps = 1
        case .departed:
            hero = .departed(step: 2, total: total, nearGym: false)
            pathSteps = 2
        case .approachingGym:
            hero = .departed(step: 2, total: total, nearGym: true)
            pathSteps = 2
        case .arrived:
            hero = .arrived(step: 3, total: total)
            pathSteps = 3
        case .homeWorkoutVerified:
            hero = .verified(step: 4, total: total, streak: streak)
            pathSteps = 4
        case .completed:
            hero = .verified(step: 4, total: total, streak: streak)
            pathSteps = 4
        case .windowExpired, .missed:
            hero = .missed
            pathSteps = 0
        case .cantToday, .rescheduled:
            hero = .restDay(
                nextDay: nextTrainingDayLabel(store: store, now: now, calendar: calendar) ?? "next session",
                nextTime: store.plan.enabledSlots.first?.alarmTime.displayString
            )
            pathSteps = 0
        default:
            hero = .committed(step: 1, total: total)
            pathSteps = 0
        }

        return HomeCardModel(
            hero: hero,
            protection: protection(store, coordinator: coordinator, session: session),
            next: nextDuringSession(session, store: store),
            path: PathCard(completedSteps: pathSteps, placeholder: nil)
        )
    }

    /// Today's win, after the morning has settled.
    private static func resolvedModel(
        streak: Int,
        store: AppStore,
        coordinator: GymSessionCoordinator,
        now: Date,
        calendar: Calendar
    ) -> HomeCardModel {
        HomeCardModel(
            hero: .verified(step: 4, total: 4, streak: streak),
            protection: protection(store, coordinator: coordinator, session: nil),
            next: nextIdle(store, now: now, calendar: calendar),
            path: PathCard(completedSteps: 4, placeholder: nil)
        )
    }

    // MARK: Pieces

    private static func protection(
        _ store: AppStore,
        coordinator: GymSessionCoordinator,
        session: GymSession?
    ) -> ProtectionCard {
        let count = coordinator.shield.selectionCount

        guard count > 0 else {
            return ProtectionCard(mood: .unset, appCount: 0, detail: "choose apps in setup")
        }

        if coordinator.shield.isShielded {
            return ProtectionCard(mood: .shielding, appCount: count, detail: "until verification")
        }

        if session?.gymArrivalVerified == true || session?.state == .completed {
            return ProtectionCard(mood: .released, appCount: count, detail: "until next session")
        }

        return ProtectionCard(mood: .ready, appCount: count, detail: "armed for the alarm")
    }

    private static func nextDuringSession(_ session: GymSession, store: AppStore) -> NextCard {
        switch session.state {
        case .alarmFired, .awaitingDecision, .snoozed, .activationMission, .preparing, .quickWorkoutOffered, .quickWorkoutActive:
            let leave = session.leaveMoment.map { Date.formattedClock($0) }
                ?? store.plan.rhythm.leaveTime.displayString
            return NextCard(eyebrow: "LEAVE", value: leave, detail: nil, showsArrow: true)
        case .departed, .approachingGym:
            return NextCard(eyebrow: "NEXT", value: "Gym", detail: nil, showsArrow: true)
        case .arrived:
            return NextCard(eyebrow: "NOW", value: "Train", detail: nil, showsArrow: false)
        default:
            return NextCard(eyebrow: "NEXT", value: "Recover", detail: nil, showsArrow: false)
        }
    }

    private static func nextIdle(_ store: AppStore, now: Date, calendar: Calendar) -> NextCard {
        guard let occurrence = store.plan.nextOccurrence(after: now, calendar: calendar) else {
            return NextCard(eyebrow: "NEXT", value: "Set alarm", detail: nil, showsArrow: true)
        }

        let day = calendar.isDateInToday(occurrence.fireDate)
            ? "Today"
            : calendar.isDateInTomorrow(occurrence.fireDate)
                ? "Tomorrow"
                : calendar.weekdaySymbols[calendar.component(.weekday, from: occurrence.fireDate) - 1]

        return NextCard(
            eyebrow: "NEXT",
            value: occurrence.slot.alarmTime.displayString,
            detail: day,
            showsArrow: true
        )
    }

    // MARK: Conditions

    private static func setupChecklist(
        store: AppStore,
        coordinator: GymSessionCoordinator
    ) -> (items: [ChecklistItem], allSatisfied: Bool) {
        let items: [ChecklistItem] = [
            ChecklistItem(
                id: "apps",
                label: "Apps locked",
                // Having visited the setup screen is not the same as having
                // something selected. Only a live selection counts, or home
                // would promise a lock the shield cannot apply — which is how
                // the hero ended up announcing a commitment while the
                // Protection card still said "choose apps in setup".
                isDone: store.hasConfiguredBlockedApps && coordinator.shield.selectionCount > 0
            ),
            ChecklistItem(
                id: "alarm",
                label: "Alarm ready",
                isDone: store.plan.hasBeenReviewed && !store.plan.enabledSlots.isEmpty
            ),
            ChecklistItem(
                id: "gym",
                label: "Gym selected",
                isDone: store.isAutomaticArrivalReady
            ),
        ]
        return (items, items.allSatisfy(\.isDone))
    }

    private static func isComebackDay(store: AppStore, now: Date, calendar: Calendar) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
        guard let outcome = store.log.outcome(on: yesterday, calendar: calendar) else { return false }
        return outcome.kind == .missed || outcome.kind == .technicalFailure
    }

    private static func countdownStage(store: AppStore, now: Date, calendar: Calendar) -> HeroStage? {
        guard let occurrence = store.plan.nextOccurrence(after: now, calendar: calendar) else { return nil }

        let seconds = Int(occurrence.fireDate.timeIntervalSince(now))
        let leadIn = 2 * 60 * 60
        guard seconds > 0, seconds <= leadIn else { return nil }

        return .countdown(secondsRemaining: seconds, windowSeconds: leadIn)
    }

    // MARK: Duplication

    /// Stops the Next card repeating the number the hero already owns.
    ///
    /// The four cards only work if each answers a different question. Once the
    /// hero has claimed the next alarm time, Next moves on to the moment after
    /// it — the time the user actually has to be at the gym — which is new
    /// information rather than the same clock printed twice.
    private static func deduplicated(
        _ model: HomeCardModel,
        store: AppStore,
        now: Date,
        calendar: Calendar
    ) -> HomeCardModel {
        guard let claim = heroClaim(model.hero, store: store, now: now, calendar: calendar),
              model.next.value.caseInsensitiveCompare(claim) == .orderedSame,
              let alternative = nextDeadline(store, now: now, calendar: calendar),
              alternative.value.caseInsensitiveCompare(claim) != .orderedSame
        else { return model }

        var updated = model
        updated.next = alternative
        return updated
    }

    /// The value the hero is already displaying, when it is the kind of value a
    /// mini card could collide with.
    private static func heroClaim(
        _ hero: HeroStage,
        store: AppStore,
        now: Date,
        calendar: Calendar
    ) -> String? {
        switch hero {
        case .firstDay(let alarm):
            return alarm.displayString
        case .night(_, let nextAlarm):
            return nextAlarm?.displayString
        case .countdown:
            return store.plan.nextOccurrence(after: now, calendar: calendar)?
                .slot.alarmTime.displayString
        case .restDay(_, let nextTime):
            return nextTime
        default:
            return nil
        }
    }

    /// "Gym by" — when the user said they would be at the gym, and how long
    /// after the alarm that is.
    ///
    /// Derived from the gap drawn on the dial rather than from the lock
    /// window. The two used to be the same number; now that the gym bar can be
    /// placed anywhere in the day they are not, and this card is about the
    /// plan, not about how long apps stay blocked.
    private static func nextDeadline(
        _ store: AppStore,
        now: Date,
        calendar: Calendar
    ) -> NextCard? {
        guard let occurrence = store.plan.nextOccurrence(after: now, calendar: calendar) else {
            return nil
        }

        let gap = store.plan.rhythm.gapToGymMinutes
        guard gap > 0 else { return nil }

        return NextCard(
            eyebrow: "GYM BY",
            value: occurrence.slot.gymByTime(window: gap).displayString,
            detail: "\(DayDialModel.durationText(minutes: gap)) after the alarm",
            showsArrow: true
        )
    }

    // MARK: Aggregates

    private static func aggregateStage(store: AppStore, coordinator: GymSessionCoordinator, now: Date, calendar: Calendar) -> HomeCardModel? {
        if let month = monthStage(store: store, coordinator: coordinator, now: now, calendar: calendar) {
            return month
        }
        if let pattern = patternStage(store: store, coordinator: coordinator, now: now, calendar: calendar) {
            return pattern
        }
        return weekStage(store: store, coordinator: coordinator, now: now, calendar: calendar)
    }

    private static func weekStage(store: AppStore, coordinator: GymSessionCoordinator, now: Date, calendar: Calendar) -> HomeCardModel? {
        let perWeek = store.plan.enabledSlots.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }.count
        guard perWeek > 0 else { return nil }

        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        let done = store.log.outcomes.filter {
            week.contains($0.date) && $0.kind.preservesMomentum
        }.count

        guard done > 0 else { return nil }

        // First week of use reads as steps; afterwards as a bar.
        let firstOutcome = store.log.outcomes.map(\.date).min() ?? now
        let daysSinceFirst = max(0, calendar.dateComponents([.day], from: firstOutcome, to: now).day ?? 0)
        let useDots = daysSinceFirst < 7

        let path = useDots
            ? PathCard(completedSteps: min(done, 4), placeholder: nil)
            : PathCard(completedSteps: 0, placeholder: nil)

        return HomeCardModel(
            hero: .weekProgress(done: done, of: perWeek, useDots: useDots),
            protection: protection(store, coordinator: coordinator, session: nil),
            next: nextIdle(store, now: now, calendar: calendar),
            path: path
        )
    }

    /// Multi-week weekday histogram. Only shown once there is a genuine pattern
    /// to see — several sessions across more than one week — never faked.
    private static func patternStage(store: AppStore, coordinator: GymSessionCoordinator, now: Date, calendar: Calendar) -> HomeCardModel? {
        let visits = store.log.outcomes.filter { $0.kind.isVerifiedGymVisit }
        guard visits.count >= 6 else { return nil }

        var weeks = Set<Int>()
        var byWeekday = [Int](repeating: 0, count: 7)
        for visit in visits {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: visit.date) else { continue }
            weeks.insert(week.start.hashValue)
            let weekday = calendar.component(.weekday, from: visit.date) - 1 // Sun-first index
            byWeekday[weekday] += 1
        }
        guard weeks.count >= 3 else { return nil }

        // Monday-first reorder: M T W T F S S.
        let mondayFirst = Array(byWeekday[1...6]) + [byWeekday[0]]
        let labels = Array(calendar.veryShortWeekdaySymbols[1...6]) + [calendar.veryShortWeekdaySymbols[0]]
        let best = mondayFirst.indices.max { mondayFirst[$0] < mondayFirst[$1] } ?? 0
        guard mondayFirst[best] > 0 else { return nil }

        return HomeCardModel(
            hero: .pattern(weekdayLabels: labels, values: mondayFirst, bestIndex: best),
            protection: protection(store, coordinator: coordinator, session: nil),
            next: nextIdle(store, now: now, calendar: calendar),
            path: PathCard(completedSteps: 0, placeholder: nil)
        )
    }

    private static func monthStage(store: AppStore, coordinator: GymSessionCoordinator, now: Date, calendar: Calendar) -> HomeCardModel? {
        let dayOfMonth = calendar.component(.day, from: now)
        let perWeek = store.plan.enabledSlots.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }.count

        func verified(in interval: DateInterval) -> Int {
            store.log.outcomes.filter { interval.contains($0.date) && $0.kind.isVerifiedGymVisit }.count
        }

        // A month that just turned: show the closed month.
        if dayOfMonth <= 3,
           let current = calendar.dateInterval(of: .month, for: now),
           let lastStart = calendar.date(byAdding: .month, value: -1, to: current.start),
           let last = calendar.dateInterval(of: .month, for: lastStart) {

            let lastVerified = verified(in: last)
            let lastPlanned = max(perWeek * 4, 1)
            let pct = min(100, Int((Double(lastVerified) / Double(lastPlanned) * 100).rounded()))

            if lastVerified >= 8 {
                return monthModel(
                    store: store, coordinator: coordinator,
                    hero: .monthComplete(sessions: lastVerified, consistency: pct),
                    now: now, calendar: calendar
                )
            }
            if store.log.totalVerifiedGymVisits >= 8 {
                return monthModel(
                    store: store, coordinator: coordinator,
                    hero: .startMonth(
                        totalSessions: store.log.totalVerifiedGymVisits,
                        goal: max(perWeek * 4, 4)
                    ),
                    now: now, calendar: calendar
                )
            }
        }

        // Mid-month: real progress with a bar.
        if dayOfMonth >= 4, dayOfMonth <= 19 {
            guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }
            let done = verified(in: month)
            let planned = max(perWeek * 4, 1)
            guard done >= 2 else { return nil }

            let pct = min(100, Int((Double(done) / Double(planned) * 100).rounded()))
            return monthModel(
                store: store, coordinator: coordinator,
                hero: .midMonth(done: done, of: planned, percent: pct),
                now: now, calendar: calendar
            )
        }

        // Late month: identity, backed by a real streak. Four kept weeks is
        // the first point a pattern is a pattern rather than a good month.
        if dayOfMonth >= 20 {
            let streak = store.streak.weeks
            guard streak >= 4 else { return nil }
            return monthModel(
                store: store, coordinator: coordinator,
                hero: .latePattern(momentumWeeks: streak),
                now: now, calendar: calendar
            )
        }

        return nil
    }

    private static func monthModel(
        store: AppStore,
        coordinator: GymSessionCoordinator,
        hero: HeroStage,
        now: Date,
        calendar: Calendar
    ) -> HomeCardModel {
        HomeCardModel(
            hero: hero,
            protection: protection(store, coordinator: coordinator, session: nil),
            next: nextIdle(store, now: now, calendar: calendar),
            path: PathCard(completedSteps: 0, placeholder: "Pattern holding")
        )
    }

    private static func restDayModel(store: AppStore, coordinator: GymSessionCoordinator, now: Date, calendar: Calendar) -> HomeCardModel {
        HomeCardModel(
            hero: .restDay(
                nextDay: nextTrainingDayLabel(store: store, now: now, calendar: calendar) ?? "next session",
                nextTime: store.plan.enabledSlots.first?.alarmTime.displayString
            ),
            protection: protection(store, coordinator: coordinator, session: nil),
            next: nextIdle(store, now: now, calendar: calendar),
            path: PathCard(completedSteps: 0, placeholder: "Next session ready")
        )
    }

    private static func nextTrainingDayLabel(
        store: AppStore,
        now: Date,
        calendar: Calendar
    ) -> String? {
        let training = store.schedule.trainingDays
        guard !training.isEmpty else { return nil }

        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
                  training.contains(weekday)
            else { continue }
            return calendar.isDateInTomorrow(day) ? "Tomorrow" : weekday.shortLabel
        }
        return nil
    }
}

// MARK: - Helpers

extension Date {
    /// Short clock string such as "6:58 AM".
    static func formattedClock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
