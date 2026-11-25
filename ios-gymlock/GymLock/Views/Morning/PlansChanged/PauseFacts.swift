//
//  PauseFacts.swift
//  GymLock · the "plans changed" pause
//
//  Everything the pause shows, read once from the real app state when the screen opens. Nothing here
//  is a placeholder: a value the app does not have is nil (or empty) and the copy drops it.
//
//  Field by field (same definitions the rest of the app uses):
//    context            .windowOpen on the wake page sheet, .windowClosed when the gym window ran out
//    gymBy              session.deadline ?? session.arrivalTarget, formatted like the hero card
//    graceMinutes       GymSession.graceMinutes ("still going" after the window closed)
//    visitsBefore       gym visits before today (WakeFactsProvider.gymVisitDay − 1): the 66 counts these
//    streakWeeks        store.streak.weeks (the StreakChip number)
//    weekDone           SkipRules.countedThisWeek (today excluded), what the skip screen reads
//    weekGoal           store.weeklyGoal(forWeekContaining:)
//    chancesAfterToday  SkipRules.chancesRemaining (planned days after today + pending reschedules)
//    lastSkipped        the most recent resolved outcome before today was a skip or a miss
//    reason             the first of OnboardingProfile.orderedFailureReasons the pause has words for
//    homeLeft           HomeWorkoutRules.monthlyLimit − usedThisMonth
//    homeMinutes        HomeWorkoutRules.defaultMinutes
//    day0               OnboardingProfile.day0Media, only if its file is still on disk
//    alarmLabel         when the alarm rang (session.alarmFiredAt), else the slot's alarm time
//    week               this week, Monday first, one state per day
//

import Foundation

struct PauseWeekDay: Hashable {
    enum State: Hashable {
        /// A counted workout day.
        case done
        /// The session's day.
        case today
        /// A gym day or a pending reschedule still to come.
        case planned
        /// A planned day before today that did not count.
        case missed
        /// Nothing planned.
        case rest
    }
    /// One lowercase letter: m t w t f s s.
    let letter: String
    let state: State
}

struct PauseFacts: Hashable {
    enum Context: Hashable {
        case windowOpen
        case windowClosed
    }

    var context: Context
    var gymBy: String?
    var nowLabel: String
    var graceMinutes: Int
    var visitsBefore: Int
    var streakWeeks: Int
    var weekDone: Int
    var weekGoal: Int
    var chancesAfterToday: Int
    var lastSkipped: Bool
    var reason: FailureReason?
    var homeLeft: Int
    var homeMinutes: Int
    var day0: Day0Media?
    var alarmLabel: String?
    var week: [PauseWeekDay]
    var dateLabel: String

    /// Skipping today leaves the week's goal out of reach (the skip screen's "make it up" branch).
    var weekAtRisk: Bool { weekDone + chancesAfterToday < weekGoal }

    /// The worst moment to skip: it breaks a running streak, or it would be the second skip in a row.
    /// This is when the pause plays the user's own day 0 page instead of their card style.
    var isCritical: Bool { (streakWeeks > 0 && weekAtRisk) || lastSkipped }

    /// Today's visit number, 1-based.
    var visitNumber: Int { visitsBefore + 1 }
}

@MainActor
enum PauseFactsProvider {
    static func facts(
        store: AppStore,
        coordinator: GymSessionCoordinator,
        session: GymSession,
        context: PauseFacts.Context,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PauseFacts {
        let displayCal = HeroMomentResolver.displayCalendar()
        let day = calendar.startOfDay(for: session.day)
        let log = store.log
        let plan = store.plan

        let gymDate = session.deadline ?? session.arrivalTarget
        let visitDay = WakeFactsProvider.gymVisitDay(store: store, today: day, cal: displayCal)

        let profile = store.profile
        let day0: Day0Media? = profile.day0Media.flatMap { (media: Day0Media) -> Day0Media? in
            guard let url = media.fileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
            return media
        }

        let alarmLabel: String? = session.alarmFiredAt.map(Date.formattedClock) ?? session.alarmTime.displayString

        return PauseFacts(
            context: context,
            gymBy: gymDate.map(Date.formattedClock),
            nowLabel: Date.formattedClock(now),
            graceMinutes: GymSession.graceMinutes,
            visitsBefore: max(0, visitDay - 1),
            streakWeeks: store.streak.weeks,
            weekDone: SkipRules.countedThisWeek(log: log, day: day, calendar: calendar),
            weekGoal: store.weeklyGoal(forWeekContaining: day, calendar: calendar),
            chancesAfterToday: SkipRules.chancesRemaining(log: log, plan: plan, day: day, now: now, calendar: calendar),
            lastSkipped: lastSkipped(log: log, before: day, calendar: calendar),
            reason: profile.orderedFailureReasons.first { PauseScript.quoteLine(for: $0) != nil },
            homeLeft: max(0, HomeWorkoutRules.monthlyLimit - HomeWorkoutRules.usedThisMonth(log: log, now: now, calendar: calendar)),
            homeMinutes: HomeWorkoutRules.defaultMinutes,
            day0: day0,
            alarmLabel: alarmLabel,
            week: week(log: log, plan: plan, day: day, now: now, calendar: calendar),
            dateLabel: day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).lowercased()
        )
    }

    /// The most recent resolved day before today: true when it was a skip or a miss. Days that only
    /// recorded a reschedule or a technical failure say nothing either way and are passed over.
    static func lastSkipped(log: MomentumLog, before day: Date, calendar: Calendar) -> Bool {
        let earlier = log.outcomes
            .filter { $0.countingDay(calendar: calendar) < day }
            .filter { $0.kind != .rescheduled && $0.kind != .technicalFailure }
            .sorted { $0.date < $1.date }
        guard let last = earlier.last else { return false }
        if last.counts { return false }
        switch last.kind {
        case .skipped, .missed, .easySkip, .dayOff: return true
        default: return false
        }
    }

    /// This week, Monday first (ProgressAnalytics.displayCalendar), one state per day.
    static func week(log: MomentumLog, plan: MorningPlan, day: Date, now: Date, calendar: Calendar) -> [PauseWeekDay] {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let start = StreakEngine.weekStart(containing: day, weekCalendar: weekCalendar) else { return [] }
        let counted = Set(StreakEngine.sessionDays(in: log, weekStarting: start, calendar: calendar))
        let rescheduled = Set(
            plan.oneOffAlarms
                .filter { $0.kind == .reschedule && $0.isActive(at: now) && $0.fireDate > now }
                .map { calendar.startOfDay(for: $0.fireDate) }
        )
        let letters = ["m", "t", "w", "t", "f", "s", "s"]
        return (0..<7).compactMap { (offset: Int) -> PauseWeekDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let d = calendar.startOfDay(for: date)
            let isGymDay = Weekday(rawValue: calendar.component(.weekday, from: d)).map { plan.gymDays.contains($0) } ?? false
            let state: PauseWeekDay.State
            if counted.contains(d) {
                state = .done
            } else if calendar.isDate(d, inSameDayAs: day) {
                state = .today
            } else if d > day, isGymDay || rescheduled.contains(d) {
                state = .planned
            } else if d < day, isGymDay {
                state = .missed
            } else {
                state = .rest
            }
            return PauseWeekDay(letter: letters[offset], state: state)
        }
    }
}
