import Foundation

// MARK: - Weekday neighbours

extension Weekday {
    /// The day before, wrapping Monday back to Sunday.
    ///
    /// Computed from the calendar's own numbering (Sunday = 1 … Saturday = 7)
    /// rather than from `allCases`, whose Monday-first order is for display
    /// and would put the wrap in the wrong place.
    var previous: Weekday {
        Weekday(rawValue: rawValue == 1 ? 7 : rawValue - 1) ?? self
    }

    /// The day after, wrapping Sunday forward to Monday.
    var next: Weekday {
        Weekday(rawValue: rawValue == 7 ? 1 : rawValue + 1) ?? self
    }

    /// Lowercase full name, for sentences in chrome.
    var spokenName: String {
        switch self {
        case .monday: "monday"
        case .tuesday: "tuesday"
        case .wednesday: "wednesday"
        case .thursday: "thursday"
        case .friday: "friday"
        case .saturday: "saturday"
        case .sunday: "sunday"
        }
    }
}

// MARK: - Sleep schedule rules

/// Which days the sleep schedule runs on, and which of them a gym morning
/// makes non-negotiable.
///
/// A sleep day is the calendar day the user **wakes** on. Selecting Monday
/// with 23:00 to 07:00 means the Night Lock runs Sunday 23:00 to Monday
/// 07:00; with 00:30 to 08:30 it runs Monday 00:30 to Monday 08:30. The same
/// day decides Monday's plain wake alarm. Everything below follows from that
/// one definition.
///
/// Two sets are kept apart on purpose. What the user chose is stored; what
/// the gym schedule requires is derived every time it is asked for. Merging
/// them into storage would mean a day forced on by Tuesday's gym day stays
/// on after Tuesday is removed, which is a choice the user never made.
enum SleepSchedule {
    /// True when the night runs past midnight, so it starts the day before
    /// the morning it leads into.
    ///
    /// Strictly greater: bedtime equal to wake time is not an overnight
    /// dependency, it is a degenerate schedule, and it forces nothing.
    static func crossesMidnight(bedtime: TimeOfDay, wake: TimeOfDay) -> Bool {
        bedtime.minutesFromMidnight > wake.minutesFromMidnight
    }

    /// The days that must stay on: the gym days themselves.
    ///
    /// A sleep day is the morning you wake on, so a Monday gym morning needs
    /// Monday on, whatever the bedtime. Night Lock then starts the evening
    /// before on its own (FLOW, "Which days").
    static func requiredDays(gymDays: Set<Weekday>) -> Set<Weekday> {
        gymDays
    }

    /// What is actually in force: the user's own days plus the required ones.
    static func effectiveDays(chosen: Set<Weekday>, required: Set<Weekday>) -> Set<Weekday> {
        chosen.union(required)
    }

    /// The result of tapping a sleep day.
    enum Toggle: Equatable {
        /// The user's own set, after the tap.
        case updated(Set<Weekday>)
        /// Refused: this day is a gym day.
        case required(day: Weekday)
    }

    /// Resolves a tap on a sleep-schedule circle.
    ///
    /// A required day is refused whether or not the user also chose it,
    /// because either way the circle cannot turn off. A day that is on only
    /// by the user's choice comes off; a day that is off goes on.
    static func toggle(
        _ day: Weekday,
        chosen: Set<Weekday>,
        gymDays: Set<Weekday>
    ) -> Toggle {
        if requiredDays(gymDays: gymDays).contains(day) {
            return .required(day: day)
        }

        var updated = chosen
        if updated.contains(day) {
            updated.remove(day)
        } else {
            updated.insert(day)
        }
        return .updated(updated)
    }

    /// The quiet line shown when a required day is tapped.
    static func requiredMessage(day: Weekday) -> String {
        "\(day.spokenName) is a gym day, so \(day.spokenName) stays active."
    }

    // MARK: Migration to wake days

    /// Moves days saved under the old meaning (the day a night starts) to the
    /// new one (the day you wake). Runs once, guarded by
    /// `sleepDaysAreWakeDays`, so it can never shift twice.
    ///
    /// An overnight schedule wakes the day after it starts, so each old day
    /// moves to `.next`. A schedule that starts after midnight already starts
    /// and ends on the same day, so it keeps its weekday. Returns whether the
    /// plan changed.
    @discardableResult
    static func migrateToWakeDays(_ plan: inout MorningPlan) -> Bool {
        guard !plan.sleepDaysAreWakeDays else { return false }
        plan.sleepDaysAreWakeDays = true
        if crossesMidnight(bedtime: plan.rhythm.bedtime, wake: plan.rhythm.wakeTime) {
            plan.sleepScheduleDays = Set(plan.sleepScheduleDays.map(\.next))
        }
        return true
    }
}

// MARK: - Sleep rules: pending bedtime, the lock window, legacy wake times

/// Pure rules for when a bedtime takes effect, what the night lock runs on,
/// and which existing users had a gym alarm stored as their wake time.
///
/// A night is found by the morning it ends on. Wake time is one fixed time of
/// day, so "the night that ends at Wednesday 07:00" means one thing whatever
/// the bedtime is, including a bedtime that moves across midnight. That
/// morning's weekday is also the sleep schedule's day for the night.
enum SleepRules {
    /// When tonight ends: the first wake time after `now`.
    ///
    /// Inside tonight's window that is the end of the window. Before bedtime
    /// it is tomorrow morning. A new bedtime starts with the night after this.
    static func tonightEnds(after now: Date, wake: TimeOfDay, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let moment = calendar.date(bySettingHour: wake.hour, minute: wake.minute, second: 0, of: day),
                  moment > now
            else { continue }
            return moment
        }
        return now.addingTimeInterval(86_400)
    }

    /// The bedtime for the night that ends at `nightEnd`.
    ///
    /// Tonight (ending at `pending.startsAt`) and any earlier night keep the
    /// current bedtime. Every night after it uses the pending one.
    static func bedtime(
        forNightEnding nightEnd: Date,
        current: TimeOfDay,
        pending: PendingBedtime?,
        calendar: Calendar
    ) -> TimeOfDay {
        guard let pending else { return current }
        // Compared by morning, not by minute: one night ends per morning, so
        // a wake time edited later cannot slide tonight past the boundary.
        let nightMorning = calendar.startOfDay(for: nightEnd)
        let tonightMorning = calendar.startOfDay(for: pending.startsAt)
        return nightMorning > tonightMorning ? pending.bedtime : current
    }

    /// Whether a pending bedtime can be folded into the plan: tonight is over,
    /// so every night still to come uses it.
    static func isDue(_ pending: PendingBedtime, at now: Date) -> Bool {
        now >= pending.startsAt
    }

    /// One night: when it starts and ends, and the weekday it belongs to,
    /// which is the day it ends on (the day you wake).
    struct Night: Equatable {
        let start: Date
        let end: Date
        let weekday: Weekday
    }

    /// The night that ends on the morning of `day`, or nil for a degenerate
    /// schedule (bedtime equal to wake time).
    static func night(
        endingOnMorningOf day: Date,
        rhythm: MorningRhythm,
        pending: PendingBedtime?,
        calendar: Calendar
    ) -> Night? {
        let wake = rhythm.wakeTime
        guard let end = calendar.date(bySettingHour: wake.hour, minute: wake.minute, second: 0, of: day) else {
            return nil
        }
        let bed = bedtime(forNightEnding: end, current: rhythm.bedtime, pending: pending, calendar: calendar)
        guard bed.minutesFromMidnight != wake.minutesFromMidnight else { return nil }

        // An overnight schedule starts the day before the morning it ends on.
        let startDayOffset = SleepSchedule.crossesMidnight(bedtime: bed, wake: wake) ? -1 : 0
        guard let startDay = calendar.date(byAdding: .day, value: startDayOffset, to: calendar.startOfDay(for: day)),
              let start = calendar.date(bySettingHour: bed.hour, minute: bed.minute, second: 0, of: startDay),
              // Keyed by the wake day, never the start day.
              let weekday = Weekday(rawValue: calendar.component(.weekday, from: end))
        else { return nil }
        return Night(start: start, end: end, weekday: weekday)
    }

    /// The night-lock window holding at `now`, only on nights that end on a
    /// sleep-schedule day (the day you wake). Always on: there is no switch
    /// (FLOW, "The Night Lock").
    static func lockWindow(
        at now: Date,
        rhythm: MorningRhythm,
        pending: PendingBedtime?,
        wakeDays: Set<Weekday>,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        // A night is shorter than a day and ends at a wake time, so the one
        // holding `now` ends this morning or tomorrow morning.
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let night = night(endingOnMorningOf: day, rhythm: rhythm, pending: pending, calendar: calendar),
                  wakeDays.contains(night.weekday),
                  now >= night.start, now < night.end
            else { continue }
            return (night.start, night.end)
        }
        return nil
    }

    /// The next moment a night ending on a sleep-schedule day starts, after
    /// `now`.
    static func nextLockStart(
        after now: Date,
        rhythm: MorningRhythm,
        pending: PendingBedtime?,
        wakeDays: Set<Weekday>,
        calendar: Calendar
    ) -> Date? {
        guard !wakeDays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0...9 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let night = night(endingOnMorningOf: day, rhythm: rhythm, pending: pending, calendar: calendar),
                  wakeDays.contains(night.weekday),
                  night.start > now
            else { continue }
            return night.start
        }
        return nil
    }

    /// Whether an existing plan's wake time was really its gym alarm.
    ///
    /// Seeding used to copy the gym alarm into the wake time, so anyone who
    /// trains after work, in the evening or "something else", or whose wake
    /// time is 11:00 or later, was given a gym time as a wake time.
    static func wakeTimeWasGymAlarm(failureWindow: FailureWindow?, wakeTime: TimeOfDay) -> Bool {
        switch failureWindow {
        case .afterWork, .evening, .other: return true
        default: return wakeTime.hour >= 11
        }
    }

    /// The repair for such a plan: the gym stays where it is, wake time goes
    /// to 07:00 until the user answers. Alarm times are not touched here.
    static func repairedRhythm(_ rhythm: MorningRhythm) -> MorningRhythm {
        var repaired = rhythm
        repaired.gymTime = rhythm.gymByTime
        repaired.wakeTime = OnboardingProfile.defaultWakeTime
        return repaired
    }

    /// Runs the wake-time check once on a plan saved before it existed.
    ///
    /// Returns whether the plan was repaired. Plans with no alarm yet were
    /// never seeded the old way, so they only get marked as checked.
    @discardableResult
    static func migrateLegacyWakeTime(_ plan: inout MorningPlan, failureWindow: FailureWindow?) -> Bool {
        guard !plan.hasCheckedWakeTime else { return false }
        plan.hasCheckedWakeTime = true
        guard !plan.slots.isEmpty,
              wakeTimeWasGymAlarm(failureWindow: failureWindow, wakeTime: plan.rhythm.wakeTime)
        else { return false }
        plan.rhythm = repairedRhythm(plan.rhythm)
        plan.needsWakeTimeAnswer = true
        return true
    }
}

// MARK: - Changing the sleep schedule

extension MorningPlan {
    /// Applies a new sleep schedule. Wake time and everything else apply at
    /// once; a new bedtime starts from tomorrow night (FLOW, the night lock
    /// edge cases).
    ///
    /// `immediately` is for the very first bedtime, set during onboarding and
    /// setup, which applies at once.
    mutating func applyRhythmChange(
        _ updated: MorningRhythm,
        now: Date,
        calendar: Calendar,
        immediately: Bool = false
    ) {
        applyDuePendingBedtime(now: now)

        guard !immediately else {
            rhythm = updated
            pendingBedtime = nil
            return
        }

        let newBedtime = updated.bedtime
        var next = updated
        next.bedtime = rhythm.bedtime
        rhythm = next

        if newBedtime == rhythm.bedtime {
            pendingBedtime = nil
        } else {
            pendingBedtime = PendingBedtime(
                bedtime: newBedtime,
                startsAt: SleepRules.tonightEnds(after: now, wake: rhythm.wakeTime, calendar: calendar)
            )
        }
    }

    /// Folds a pending bedtime in once tonight is over. Returns whether it did.
    @discardableResult
    mutating func applyDuePendingBedtime(now: Date) -> Bool {
        guard let pendingBedtime, SleepRules.isDue(pendingBedtime, at: now) else { return false }
        rhythm.bedtime = pendingBedtime.bedtime
        self.pendingBedtime = nil
        return true
    }

    /// The night-lock window holding at `now`, if any.
    func nightLockWindow(at now: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        SleepRules.lockWindow(
            at: now,
            rhythm: rhythm,
            pending: pendingBedtime,
            wakeDays: effectiveSleepDays(),
            calendar: calendar
        )
    }

    /// When the next night lock starts, for the wind-down notification.
    func nextNightLockStart(after now: Date, calendar: Calendar) -> Date? {
        SleepRules.nextLockStart(
            after: now,
            rhythm: rhythm,
            pending: pendingBedtime,
            wakeDays: effectiveSleepDays(),
            calendar: calendar
        )
    }
}

// MARK: - The plan's view of it

extension MorningPlan {
    /// The one alarm the Alarm screen shows and edits.
    var primaryAlarmSlot: AlarmSlot? {
        enabledSlots.first ?? slots.first
    }

    /// The gym days the Alarm screen shows. `AlarmSlot.days` is the only
    /// store of them; this is a read, never a copy.
    var gymDays: Set<Weekday> {
        primaryAlarmSlot?.days ?? []
    }

    /// Sleep days the gym schedule requires: the gym days themselves. The
    /// bedtime never moves them, because a sleep day is the day you wake.
    func requiredSleepDays() -> Set<Weekday> {
        SleepSchedule.requiredDays(gymDays: gymDays)
    }

    /// Wake days the sleep schedule is actually in force on. These decide the
    /// Night Lock (the night ending that morning) and the plain wake alarms.
    func effectiveSleepDays() -> Set<Weekday> {
        SleepSchedule.effectiveDays(
            chosen: sleepScheduleDays,
            required: requiredSleepDays()
        )
    }

    /// What has to be pushed to the system after a day edit. `resyncAlarms`
    /// rebuilds the OS alarms (gym and plain wake); `reconcileWindDown`
    /// brings the Night Lock in line.
    struct DayEditEffects: OptionSet, Hashable {
        let rawValue: Int
        static let resyncAlarms = DayEditEffects(rawValue: 1 << 0)
        static let reconcileWindDown = DayEditEffects(rawValue: 1 << 1)
    }

    /// The result of tapping a gym day.
    enum GymDayToggle: Equatable {
        /// The day went on or off.
        case updated
        /// Refused: taking it off would leave fewer than
        /// `StreakPolicy.minimumGymDays`. Show
        /// `StreakPolicy.minimumGymDaysMessage`.
        case belowMinimum
    }

    /// Turns a gym day on or off on the primary alarm.
    ///
    /// Adding a day is always allowed. Removing one that would leave fewer
    /// than 3 is refused and changes nothing, including for an existing user
    /// who is already below 3 (FLOW, "Which days").
    ///
    /// Picking a day on an alarm that was switched off turns it back on, since
    /// choosing a day to train is not an ambiguous act. With no alarm at all,
    /// the first tap creates one at `newAlarmTime`.
    ///
    /// Wind-down is reconciled too, because gym days decide which sleep days
    /// are required.
    mutating func toggleGymDay(
        _ day: Weekday,
        newAlarmTime: TimeOfDay
    ) -> (outcome: GymDayToggle, effects: DayEditEffects) {
        guard let slot = primaryAlarmSlot,
              let index = slots.firstIndex(where: { $0.id == slot.id })
        else {
            slots.append(AlarmSlot(days: [day], alarmTime: newAlarmTime))
            return (.updated, [.resyncAlarms, .reconcileWindDown])
        }

        if slots[index].days.contains(day) {
            guard slots[index].days.count > StreakPolicy.minimumGymDays else {
                return (.belowMinimum, [])
            }
            slots[index].days.remove(day)
        } else {
            slots[index].days.insert(day)
            slots[index].isEnabled = true
        }
        return (.updated, [.resyncAlarms, .reconcileWindDown])
    }

    /// Turns a sleep day on or off, refusing a gym day.
    ///
    /// Only the user's own choice is ever written; required days are never
    /// stored. A sleep day also decides that morning's plain wake alarm, so
    /// the alarms are resynced along with the Night Lock.
    mutating func toggleSleepDay(
        _ day: Weekday
    ) -> (outcome: SleepSchedule.Toggle, effects: DayEditEffects) {
        let outcome = SleepSchedule.toggle(
            day,
            chosen: sleepScheduleDays,
            gymDays: gymDays
        )
        switch outcome {
        case .updated(let days):
            sleepScheduleDays = days
            return (outcome, [.resyncAlarms, .reconcileWindDown])
        case .required:
            return (outcome, [])
        }
    }
}
