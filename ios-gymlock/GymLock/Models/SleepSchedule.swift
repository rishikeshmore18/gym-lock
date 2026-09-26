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

/// Which nights the sleep schedule runs on, and which of them a gym morning
/// makes non-negotiable.
///
/// A sleep "day" is the calendar day the night **starts** on: 11 PM Monday to
/// 7 AM Tuesday is Monday's night. Everything below follows from that one
/// definition.
///
/// Two sets are kept apart on purpose. What the user chose is stored; what
/// the gym schedule requires is derived every time it is asked for. Merging
/// them into storage would mean a night forced on by Tuesday's gym day stays
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

    /// The nights that must stay on because they end on a gym morning.
    ///
    /// An overnight schedule (23:00 → 07:00) starts the day before the gym
    /// morning, so the nights before gym days are required. A night that
    /// starts after midnight (00:30 → 08:30) starts on the gym day itself, so
    /// the gym days' own nights are required (FLOW, "Which nights").
    static func requiredNights(
        gymDays: Set<Weekday>,
        bedtime: TimeOfDay,
        wake: TimeOfDay
    ) -> Set<Weekday> {
        // Bedtime equal to wake time is a degenerate schedule, not a night.
        guard bedtime.minutesFromMidnight != wake.minutesFromMidnight else { return [] }
        guard crossesMidnight(bedtime: bedtime, wake: wake) else { return gymDays }
        return Set(gymDays.map(\.previous))
    }

    /// The gym morning a required night leads into.
    static func gymDay(protectedBy night: Weekday, bedtime: TimeOfDay, wake: TimeOfDay) -> Weekday {
        crossesMidnight(bedtime: bedtime, wake: wake) ? night.next : night
    }

    /// What is actually in force: the user's own nights plus the required ones.
    static func effectiveNights(chosen: Set<Weekday>, required: Set<Weekday>) -> Set<Weekday> {
        chosen.union(required)
    }

    /// The result of tapping a night.
    enum Toggle: Equatable {
        /// The user's own set, after the tap.
        case updated(Set<Weekday>)
        /// Refused: this night is needed before `gymDay`.
        case required(night: Weekday, gymDay: Weekday)
    }

    /// Resolves a tap on a sleep-night circle.
    ///
    /// A required night is refused whether or not the user also chose it,
    /// because either way the circle cannot turn off. A night that is on only
    /// by the user's choice comes off; a night that is off goes on.
    static func toggle(
        _ night: Weekday,
        chosen: Set<Weekday>,
        gymDays: Set<Weekday>,
        bedtime: TimeOfDay,
        wake: TimeOfDay
    ) -> Toggle {
        let required = requiredNights(gymDays: gymDays, bedtime: bedtime, wake: wake)
        if required.contains(night) {
            return .required(
                night: night,
                gymDay: gymDay(protectedBy: night, bedtime: bedtime, wake: wake)
            )
        }

        var updated = chosen
        if updated.contains(night) {
            updated.remove(night)
        } else {
            updated.insert(night)
        }
        return .updated(updated)
    }

    /// The quiet line shown when a required night is tapped.
    static func requiredMessage(night: Weekday, gymDay: Weekday) -> String {
        "\(gymDay.spokenName) is a gym day. keep \(night.spokenName) night on for rest."
    }
}

// MARK: - Sleep rules: pending bedtime, the lock window, legacy wake times

/// Pure rules for when a bedtime takes effect, what the night lock runs on,
/// and which existing users had a gym alarm stored as their wake time.
///
/// A night is found by the morning it ends on. Wake time is one fixed time of
/// day, so "the night that ends at Wednesday 07:00" means one thing whatever
/// the bedtime is, including a bedtime that moves across midnight. Each night
/// is still keyed to the day it *starts* on for the sleep schedule's circles.
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

    /// One night: when it starts and ends, and the weekday it belongs to.
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
              let weekday = Weekday(rawValue: calendar.component(.weekday, from: startDay))
        else { return nil }
        return Night(start: start, end: end, weekday: weekday)
    }

    /// The night-lock window holding at `now`, only on the sleep schedule's
    /// nights (keyed by the day each night starts on). Always on: there is no
    /// switch (FLOW, "The Night Lock").
    static func lockWindow(
        at now: Date,
        rhythm: MorningRhythm,
        pending: PendingBedtime?,
        nights: Set<Weekday>,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        // A night is shorter than a day and ends at a wake time, so the one
        // holding `now` ends this morning or tomorrow morning.
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let night = night(endingOnMorningOf: day, rhythm: rhythm, pending: pending, calendar: calendar),
                  nights.contains(night.weekday),
                  now >= night.start, now < night.end
            else { continue }
            return (night.start, night.end)
        }
        return nil
    }

    /// The next moment a night on the sleep schedule starts, after `now`.
    static func nextLockStart(
        after now: Date,
        rhythm: MorningRhythm,
        pending: PendingBedtime?,
        nights: Set<Weekday>,
        calendar: Calendar
    ) -> Date? {
        guard !nights.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0...9 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let night = night(endingOnMorningOf: day, rhythm: rhythm, pending: pending, calendar: calendar),
                  nights.contains(night.weekday),
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
            nights: effectiveSleepDays(),
            calendar: calendar
        )
    }

    /// When the next night lock starts, for the wind-down notification.
    func nextNightLockStart(after now: Date, calendar: Calendar) -> Date? {
        SleepRules.nextLockStart(
            after: now,
            rhythm: rhythm,
            pending: pendingBedtime,
            nights: effectiveSleepDays(),
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

    /// Nights the gym schedule requires, against `rhythm` when given (the
    /// dial's unsaved draft) or the committed rhythm otherwise.
    func requiredSleepNights(for rhythm: MorningRhythm? = nil) -> Set<Weekday> {
        let rhythm = rhythm ?? self.rhythm
        return SleepSchedule.requiredNights(
            gymDays: gymDays,
            bedtime: rhythm.bedtime,
            wake: rhythm.wakeTime
        )
    }

    /// Nights the sleep schedule is actually in force on.
    func effectiveSleepDays(for rhythm: MorningRhythm? = nil) -> Set<Weekday> {
        SleepSchedule.effectiveNights(
            chosen: sleepScheduleDays,
            required: requiredSleepNights(for: rhythm)
        )
    }

    /// What has to be pushed to the system after a day edit. Kept separate so
    /// a sleep change never rebuilds the gym alarms it does not affect.
    struct DayEditEffects: OptionSet, Hashable {
        let rawValue: Int
        static let resyncGymAlarms = DayEditEffects(rawValue: 1 << 0)
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
    /// who is already below 3 (FLOW, "Which nights").
    ///
    /// Picking a day on an alarm that was switched off turns it back on, since
    /// choosing a day to train is not an ambiguous act. With no alarm at all,
    /// the first tap creates one at `newAlarmTime`.
    ///
    /// Wind-down is reconciled too, because gym days decide which nights are
    /// required.
    mutating func toggleGymDay(
        _ day: Weekday,
        newAlarmTime: TimeOfDay
    ) -> (outcome: GymDayToggle, effects: DayEditEffects) {
        guard let slot = primaryAlarmSlot,
              let index = slots.firstIndex(where: { $0.id == slot.id })
        else {
            slots.append(AlarmSlot(days: [day], alarmTime: newAlarmTime))
            return (.updated, [.resyncGymAlarms, .reconcileWindDown])
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
        return (.updated, [.resyncGymAlarms, .reconcileWindDown])
    }

    /// Turns a sleep night on or off, refusing a night a gym morning needs.
    ///
    /// `rhythm` is what the dial is showing, so an unsaved draft that stops
    /// crossing midnight frees the nights straight away. Only the user's own
    /// choice is ever written; required nights are never stored.
    mutating func toggleSleepNight(
        _ night: Weekday,
        rhythm: MorningRhythm? = nil
    ) -> (outcome: SleepSchedule.Toggle, effects: DayEditEffects) {
        let rhythm = rhythm ?? self.rhythm
        let outcome = SleepSchedule.toggle(
            night,
            chosen: sleepScheduleDays,
            gymDays: gymDays,
            bedtime: rhythm.bedtime,
            wake: rhythm.wakeTime
        )
        switch outcome {
        case .updated(let nights):
            sleepScheduleDays = nights
            return (outcome, [.reconcileWindDown])
        case .required:
            return (outcome, [])
        }
    }
}
