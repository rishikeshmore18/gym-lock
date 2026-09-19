import Foundation

/// Assembles a `ShareContext` from the records the app already keeps.
///
/// Runs once, when the editor opens. Every field is read from `AppStore`
/// (ledger, events, plan, streak) or `ProgressPhotoStore` (photos, install
/// date). No Health queries, no timers, nothing recomputed on a swipe. If a
/// field cannot be supported by the record it is nil, and the frame that would
/// have drawn it is not offered.
enum ShareContextBuilder {
    /// How far back the Journey frame's completion looks.
    static let journeyWindowDays = 28

    static func build(
        origin: ShareOrigin,
        store: AppStore,
        photos: ProgressPhotoStore?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ShareContext {
        let referenceDay = origin.referenceDay
        let log = store.log
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        let installDate = photos?.installDate ?? AppInstallDate.resolve()

        let outcome = log.outcome(on: referenceDay, calendar: calendar)
        let events = sessionEvents(for: outcome, on: referenceDay, in: store.events, calendar: calendar)
        let receipt = receipt(from: events)
        let arrivedAt = events.first { $0.kind == .gymArrivalVerified }?.at

        let weekStart = StreakEngine.weekStart(containing: referenceDay, weekCalendar: weekCalendar)
            ?? calendar.startOfDay(for: referenceDay)
        let sessionDays = StreakEngine.sessionDays(in: log, weekStarting: weekStart, calendar: calendar)
        let verifiedThisWeek = distinctDays(in: log, weekStarting: weekStart, calendar: calendar) {
            $0.kind.isVerifiedGymVisit
        }
        let quick20ThisWeek = distinctDays(in: log, weekStarting: weekStart, calendar: calendar) {
            $0.kind == .homeWorkout
        }

        // Counted up to the end of the reference day, so an old photo quotes
        // the total as it stood then rather than the total today.
        let dayStart = calendar.startOfDay(for: referenceDay)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? referenceDay
        let verifiedTotal = log.outcomes.filter { $0.kind.isVerifiedGymVisit && $0.date < dayEnd }.count

        let comeback = comeback(on: referenceDay, log: log, calendar: calendar)
        let journey = journey(
            referenceDay: referenceDay,
            sharedPhoto: origin.photo,
            store: store,
            photos: photos,
            installDate: installDate,
            now: now,
            calendar: calendar
        )
        let milestone = Milestone.crossed(
            on: referenceDay,
            log: log,
            streak: store.streak,
            sessionDaysThisWeek: sessionDays,
            comeback: comeback,
            calendar: calendar
        )

        let history = history(log: log, events: store.events, weeklyGoal: store.streak.weeklyGoal, calendar: calendar)

        return ShareContext(
            referenceDay: referenceDay,
            photo: origin.photo,
            streak: store.streak,
            outcome: outcome,
            receipt: receipt,
            arrivedAt: arrivedAt,
            verifiedVisitsTotal: verifiedTotal,
            verifiedVisitsThisWeek: verifiedThisWeek,
            quick20ThisWeek: quick20ThisWeek,
            sessionDaysThisWeek: sessionDays.count,
            journey: journey,
            comeback: comeback,
            milestone: milestone,
            installDate: installDate,
            history: history
        )
    }

    // MARK: History

    /// Everything the record has ever contained, for the lock rules.
    static func history(
        log: MomentumLog,
        events: SessionEventLog,
        weeklyGoal: Int,
        calendar: Calendar
    ) -> FrameHistory {
        let verified = log.outcomes.filter(\.kind.isVerifiedGymVisit).count
        return FrameHistory(
            hasVerifiedVisit: verified > 0,
            hasReceipt: hasEverHadReceipt(events: events, calendar: calendar),
            hasKeptWeek: hasEverKeptWeek(log: log, weeklyGoal: weeklyGoal, calendar: calendar),
            hasHomeWorkout: log.outcomes.contains { $0.kind == .homeWorkout },
            verifiedVisitsEver: verified
        )
    }

    /// Whether any morning, grouped by session where one is recorded and by
    /// day otherwise, passes the same `receipt(from:)` test the frame uses.
    static func hasEverHadReceipt(events: SessionEventLog, calendar: Calendar) -> Bool {
        var bySession: [UUID: [SessionEvent]] = [:]
        var byDay: [Date: [SessionEvent]] = [:]
        for event in events.events {
            if let id = event.sessionID {
                bySession[id, default: []].append(event)
            } else {
                byDay[calendar.startOfDay(for: event.at), default: []].append(event)
            }
        }
        let groups = Array(bySession.values) + Array(byDay.values)
        return groups.contains { receipt(from: $0.sorted { $0.at < $1.at }) != nil }
    }

    /// Whether any completed or live week has met the goal. Uses the same
    /// session-day definition as the streak, so a week the streak would have
    /// kept is exactly a week this counts.
    static func hasEverKeptWeek(log: MomentumLog, weeklyGoal: Int, calendar: Calendar) -> Bool {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        var daysByWeek: [Date: Set<Date>] = [:]
        for outcome in log.outcomes where outcome.kind.preservesMomentum {
            let day = calendar.startOfDay(for: outcome.date)
            guard let week = StreakEngine.weekStart(containing: day, weekCalendar: weekCalendar) else { continue }
            daysByWeek[week, default: []].insert(day)
        }
        return daysByWeek.values.contains { $0.count >= weeklyGoal }
    }

    // MARK: Receipt

    /// The events belonging to the morning that produced the outcome.
    ///
    /// By session when the outcome remembers one; by day otherwise, for
    /// outcomes recorded before session IDs were attached.
    static func sessionEvents(
        for outcome: SessionOutcome?,
        on day: Date,
        in events: SessionEventLog,
        calendar: Calendar
    ) -> [SessionEvent] {
        if let id = outcome?.sessionID {
            let matched = events.events.filter { $0.sessionID == id }
            if !matched.isEmpty { return matched.sorted { $0.at < $1.at } }
        }
        return events.events(on: day, calendar: calendar).sorted { $0.at < $1.at }
    }

    /// The four rows, or nothing.
    ///
    /// Alarm, left and arrived are all required and must be in order. A
    /// morning where departure went undetected — the user opened the app
    /// already outside — has no honest "LEFT" row, so it has no receipt.
    static func receipt(from events: [SessionEvent]) -> ReceiptTimeline? {
        guard let alarm = events.first(where: { $0.kind == .alarmFired })?.at,
              let left = events.first(where: { $0.kind == .departed && $0.at >= alarm })?.at,
              let arrived = events.first(where: { $0.kind == .gymArrivalVerified && $0.at >= left })?.at
        else { return nil }

        let workout = events.first { $0.kind == .workoutDetected && $0.at >= arrived }?.at
        return ReceiptTimeline(alarm: alarm, left: left, arrived: arrived, workout: workout)
    }

    // MARK: Week counts

    private static func distinctDays(
        in log: MomentumLog,
        weekStarting start: Date,
        calendar: Calendar,
        where predicate: (SessionOutcome) -> Bool
    ) -> Int {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        var days: Set<Date> = []
        for outcome in log.outcomes where predicate(outcome) {
            let day = calendar.startOfDay(for: outcome.date)
            guard let week = StreakEngine.weekStart(containing: day, weekCalendar: weekCalendar),
                  calendar.isDate(week, inSameDayAs: start)
            else { continue }
            days.insert(day)
        }
        return days.count
    }

    // MARK: Comeback

    /// A return: momentum preserved on the reference day, and the most recent
    /// earlier day with any record was a miss.
    ///
    /// Generalises `HomeCardDeriver.isComebackDay`, which only looks at
    /// yesterday: a Monday miss followed by a Wednesday return is still a
    /// comeback, and the frame says so with both days named.
    static func comeback(on referenceDay: Date, log: MomentumLog, calendar: Calendar) -> ComebackInfo? {
        guard preservesMomentum(on: referenceDay, log: log, calendar: calendar) else { return nil }
        let reference = calendar.startOfDay(for: referenceDay)
        guard let previous = outcomeDays(in: log, calendar: calendar).last(where: { $0 < reference }),
              isMiss(on: previous, log: log, calendar: calendar)
        else { return nil }
        return ComebackInfo(missedDay: previous, returnDay: reference)
    }

    /// Distinct days with any outcome, oldest first.
    static func outcomeDays(in log: MomentumLog, calendar: Calendar) -> [Date] {
        Set(log.outcomes.map { calendar.startOfDay(for: $0.date) }).sorted()
    }

    static func preservesMomentum(on day: Date, log: MomentumLog, calendar: Calendar) -> Bool {
        log.outcomes.contains { calendar.isDate($0.date, inSameDayAs: day) && $0.kind.preservesMomentum }
    }

    /// A day counts as a miss only if it was recorded as one and nothing on
    /// that day preserved momentum — a technical failure followed by a home
    /// workout the same evening is not a miss.
    static func isMiss(on day: Date, log: MomentumLog, calendar: Calendar) -> Bool {
        let outcomes = log.outcomes.filter { calendar.isDate($0.date, inSameDayAs: day) }
        guard !outcomes.contains(where: \.kind.preservesMomentum) else { return false }
        return outcomes.contains { $0.kind == .missed || $0.kind == .technicalFailure }
    }

    // MARK: Journey

    private static func journey(
        referenceDay: Date,
        sharedPhoto: ProgressPhoto?,
        store: AppStore,
        photos: ProgressPhotoStore?,
        installDate: Date,
        now: Date,
        calendar: Calendar
    ) -> JourneySnapshot? {
        let install = calendar.startOfDay(for: installDate)
        let reference = calendar.startOfDay(for: referenceDay)
        let elapsed = calendar.dateComponents([.day], from: install, to: reference).day ?? 0
        let dayNumber = elapsed + 1

        guard let windowEnd = calendar.date(byAdding: .day, value: 1, to: reference),
              let windowStart = calendar.date(byAdding: .day, value: -(journeyWindowDays - 1), to: reference)
        else { return nil }

        let tally = ProgressAnalytics.tally(
            in: DateInterval(start: windowStart, end: windowEnd),
            log: store.log,
            plan: store.plan,
            schedule: store.schedule,
            now: now,
            calendar: calendar
        )

        let verified = store.log.outcomes.filter { $0.kind.isVerifiedGymVisit && $0.date < windowEnd }.count

        // The before-picture is only worth an inset when it is not the very
        // photo being shared.
        var dayZero = photos?.dayZeroPhoto
        if let candidate = dayZero, candidate.id == sharedPhoto?.id { dayZero = nil }

        return JourneySnapshot(
            dayNumber: dayNumber,
            verifiedVisits: verified,
            completion: tally.completionRate,
            due: tally.due,
            dayZeroPhoto: dayZero
        )
    }
}
