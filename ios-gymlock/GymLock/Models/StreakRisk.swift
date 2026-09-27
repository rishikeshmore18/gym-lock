import Foundation

// MARK: - When a heads-up may arrive

/// The time of day the streak-at-risk and freeze notifications use: 10:00,
/// or 30 minutes after wake time when 10:00 falls inside a night of the sleep
/// schedule ("never during sleep hours", FLOW, Flow 6).
enum NoticeTime {
    static let preferredHour = 10
    static let minutesAfterWake = 30

    /// The moment on `day` a notice goes out.
    static func fireDate(on day: Date, plan: MorningPlan, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        guard let ten = calendar.date(bySettingHour: preferredHour, minute: 0, second: 0, of: start) else {
            return nil
        }
        // The night holding 10:00 ends this morning or, for a night that
        // starts before 10:00, tomorrow morning.
        for offset in 0...1 {
            guard let morning = calendar.date(byAdding: .day, value: offset, to: start),
                  let night = SleepRules.night(
                      endingOnMorningOf: morning,
                      rhythm: plan.rhythm,
                      pending: plan.pendingBedtime,
                      calendar: calendar
                  )
            else { continue }
            if ten >= night.start, ten < night.end {
                return night.end.addingTimeInterval(Double(minutesAfterWake) * 60)
            }
        }
        return ten
    }
}

// MARK: - The banner

/// What the Home banner shows while the streak is at risk (FLOW, Flow 6).
struct StreakRiskBanner: Hashable {
    static let rescheduleLabel = "reschedule for today"
    static let freezeLineText = "otherwise a freeze gets used."

    /// "1 workout keeps your 6-week streak.", with "last day. " on Sunday.
    var line: String
    /// "otherwise a freeze gets used." when they hold one.
    var freezeLine: String?
    /// Home workouts still available this calendar month.
    var homeWorkoutsLeft: Int

    /// Only the reschedule button shows once home workouts are used up.
    var showsHomeWorkout: Bool { homeWorkoutsLeft > 0 }

    /// "home workout · 2 left this month".
    var homeWorkoutLabel: String { "home workout · \(homeWorkoutsLeft) left this month" }

    /// The notification carries the same text.
    var notificationBody: String {
        [line, freezeLine].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - The rule

/// Streak at risk (FLOW, Flow 6). All of these must hold:
///
/// - the current streak is at least 1 week;
/// - workouts still needed this week (the week's goal minus counted) are
///   more than the chances left: gym days after today, today if its alarm
///   hasn't rung yet (or a workout is under way), and pending reschedules;
/// - the week isn't covered by a planned freeze;
/// - the "make it up" screen wasn't shown today;
/// - the notification goes out at most once a day.
///
/// Pure, with `now` and `calendar` passed in.
enum StreakRisk {
    /// One scheduled at-risk notification.
    struct Notice: Hashable {
        var fireDate: Date
        var body: String
    }

    /// The banner line with real numbers.
    static func line(needed: Int, streakWeeks: Int, isSunday: Bool) -> String {
        let workouts = needed == 1 ? "1 workout keeps" : "\(needed) workouts keep"
        let core = "\(workouts) your \(streakWeeks)-week streak."
        return isSunday ? "last day. \(core)" : core
    }

    /// Distinct counted workout days in the week containing `moment`.
    static func counted(log: MomentumLog, weekOf moment: Date, calendar: Calendar) -> Int {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let start = StreakEngine.weekStart(containing: moment, weekCalendar: weekCalendar) else { return 0 }
        return StreakEngine.sessionDays(in: log, weekStarting: start, calendar: calendar).count
    }

    /// Chances left this week at `moment`: gym days after today, today if its
    /// lock alarm hasn't rung yet (or a workout is under way), and pending
    /// reschedules still to come this week. A day already counted is not a
    /// chance any more.
    static func chancesLeft(
        log: MomentumLog,
        plan: MorningPlan,
        at moment: Date,
        todayInProgress: Bool,
        calendar: Calendar
    ) -> Int {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let week = weekCalendar.dateInterval(of: .weekOfYear, for: moment) else { return 0 }
        let counted = Set(StreakEngine.sessionDays(in: log, weekStarting: week.start, calendar: calendar))
        let today = calendar.startOfDay(for: moment)

        var chances = 0
        var todayIsAChance = false
        if !counted.contains(today) {
            let isGymDay = Weekday(rawValue: calendar.component(.weekday, from: today))
                .map { plan.gymDays.contains($0) } ?? false
            let ring = plan.rhythm(at: today, calendar: calendar).lockAlarmTime
            let hasRung = calendar.date(bySettingHour: ring.hour, minute: ring.minute, second: 0, of: today)
                .map { $0 <= moment } ?? true
            if todayInProgress || (isGymDay && !hasRung) {
                chances += 1
                todayIsAChance = true
            }
        }

        var cursor = today
        while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next < week.end {
            cursor = next
            if let weekday = Weekday(rawValue: calendar.component(.weekday, from: next)),
               plan.gymDays.contains(weekday) {
                chances += 1
            }
        }

        for alarm in plan.oneOffAlarms
        where alarm.kind == .reschedule
            && alarm.isActive(at: moment)
            && alarm.fireDate > moment
            && alarm.fireDate < week.end {
            let day = calendar.startOfDay(for: alarm.fireDate)
            guard !counted.contains(day) else { continue }
            // A later-today reschedule is the same chance as today itself.
            if day == today, todayIsAChance { continue }
            chances += 1
        }

        return chances
    }

    /// Workouts still needed when the week is at risk at `moment`, or nil.
    static func neededIfAtRisk(
        log: MomentumLog,
        plan: MorningPlan,
        streakWeeks: Int,
        weeklyGoal: Int,
        isWeekFrozen: Bool,
        todayInProgress: Bool,
        at moment: Date,
        calendar: Calendar
    ) -> Int? {
        guard streakWeeks >= 1, !isWeekFrozen else { return nil }
        let needed = max(0, weeklyGoal - counted(log: log, weekOf: moment, calendar: calendar))
        let chances = chancesLeft(log: log, plan: plan, at: moment, todayInProgress: todayInProgress, calendar: calendar)
        return needed > chances ? needed : nil
    }

    /// The Home banner, shown while the week is at risk.
    static func banner(
        log: MomentumLog,
        plan: MorningPlan,
        streakWeeks: Int,
        weeklyGoal: Int,
        isWeekFrozen: Bool,
        freezesHeld: Int,
        homeWorkoutsUsed: Int,
        sawMakeUpToday: Bool,
        todayInProgress: Bool,
        now: Date,
        calendar: Calendar
    ) -> StreakRiskBanner? {
        guard !sawMakeUpToday,
              let needed = neededIfAtRisk(
                  log: log,
                  plan: plan,
                  streakWeeks: streakWeeks,
                  weeklyGoal: weeklyGoal,
                  isWeekFrozen: isWeekFrozen,
                  todayInProgress: todayInProgress,
                  at: now,
                  calendar: calendar
              )
        else { return nil }
        return make(
            needed: needed,
            streakWeeks: streakWeeks,
            isSunday: calendar.component(.weekday, from: now) == Weekday.sunday.rawValue,
            freezesHeld: freezesHeld,
            homeWorkoutsUsed: homeWorkoutsUsed
        )
    }

    /// The next at-risk notification, predicted from what is known now,
    /// because the app can't run at 10:00 to check. Today first (unless it
    /// was already sent today or the "make it up" screen was shown today),
    /// then each later day through Sunday. Nil once the week is safe.
    static func nextNotice(
        log: MomentumLog,
        plan: MorningPlan,
        streakWeeks: Int,
        weeklyGoal: Int,
        isWeekFrozen: Bool,
        freezesHeld: Int,
        sawMakeUpToday: Bool,
        alreadySentToday: Bool,
        todayInProgress: Bool,
        now: Date,
        calendar: Calendar
    ) -> Notice? {
        guard streakWeeks >= 1, !isWeekFrozen else { return nil }
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        guard let week = weekCalendar.dateInterval(of: .weekOfYear, for: now) else { return nil }

        var day = calendar.startOfDay(for: now)
        while day < week.end {
            let isToday = calendar.isDate(day, inSameDayAs: now)
            if !(isToday && (alreadySentToday || sawMakeUpToday)),
               let fire = NoticeTime.fireDate(on: day, plan: plan, calendar: calendar),
               fire > now, fire < week.end,
               let needed = neededIfAtRisk(
                   log: log,
                   plan: plan,
                   streakWeeks: streakWeeks,
                   weeklyGoal: weeklyGoal,
                   isWeekFrozen: isWeekFrozen,
                   todayInProgress: isToday && todayInProgress,
                   at: fire,
                   calendar: calendar
               ) {
                let banner = make(
                    needed: needed,
                    streakWeeks: streakWeeks,
                    isSunday: calendar.component(.weekday, from: fire) == Weekday.sunday.rawValue,
                    freezesHeld: freezesHeld,
                    homeWorkoutsUsed: HomeWorkoutRules.usedThisMonth(log: log, now: fire, calendar: calendar)
                )
                return Notice(fireDate: fire, body: banner.notificationBody)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
    }

    private static func make(
        needed: Int,
        streakWeeks: Int,
        isSunday: Bool,
        freezesHeld: Int,
        homeWorkoutsUsed: Int
    ) -> StreakRiskBanner {
        StreakRiskBanner(
            line: line(needed: needed, streakWeeks: streakWeeks, isSunday: isSunday),
            freezeLine: freezesHeld > 0 ? StreakRiskBanner.freezeLineText : nil,
            homeWorkoutsLeft: max(0, HomeWorkoutRules.monthlyLimit - homeWorkoutsUsed)
        )
    }
}

// MARK: - Freeze notices

/// The "you earned a freeze." notifications, scheduled ahead for each grant
/// date at the notice time (FLOW, Flow 5).
enum FreezeNotice {
    static let identifierPrefix = NotificationRoute.ID.freezePrefix

    struct Planned: Hashable {
        var id: String
        var fireDate: Date
        var body: String
    }

    /// Every grant notice still to come this year and next.
    static func upcoming(joined: Date, plan: MorningPlan, now: Date, calendar: Calendar) -> [Planned] {
        FreezeCalendar.grants(around: now, joined: joined, calendar: calendar).compactMap { grant in
            guard let fire = NoticeTime.fireDate(on: grant.date, plan: plan, calendar: calendar), fire > now else {
                return nil
            }
            return Planned(
                id: identifierPrefix + SessionResume.dayKey(for: grant.date, calendar: calendar),
                fireDate: fire,
                body: grant.line
            )
        }
    }
}

extension SkipScreenPlan {
    /// Whether this is the "make it up" screen, which quiets the at-risk
    /// notification for the day it was shown.
    var isMakeItUp: Bool { heading.hasPrefix("make it up") }
}
