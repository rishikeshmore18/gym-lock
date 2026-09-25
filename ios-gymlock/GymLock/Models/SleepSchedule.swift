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

    /// The nights that must stay on because a gym morning follows them.
    ///
    /// Only an overnight schedule has a "night before". A 1 AM to 8 AM night
    /// starts on the gym day itself, so nothing on the previous day is forced.
    static func requiredNights(
        gymDays: Set<Weekday>,
        bedtime: TimeOfDay,
        wake: TimeOfDay
    ) -> Set<Weekday> {
        guard crossesMidnight(bedtime: bedtime, wake: wake) else { return [] }
        return Set(gymDays.map(\.previous))
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
            return .required(night: night, gymDay: night.next)
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

    /// Turns a gym day on or off on the primary alarm.
    ///
    /// Picking a day on an alarm that was switched off turns it back on, since
    /// choosing a day to train is not an ambiguous act. An alarm left with no
    /// days is kept rather than deleted, so its sound and its place in the
    /// plan survive to be used again. With no alarm at all, the first tap
    /// creates one at `newAlarmTime`.
    ///
    /// Wind-down is reconciled too, because gym days decide which nights are
    /// required.
    mutating func toggleGymDay(_ day: Weekday, newAlarmTime: TimeOfDay) -> DayEditEffects {
        guard let slot = primaryAlarmSlot,
              let index = slots.firstIndex(where: { $0.id == slot.id })
        else {
            slots.append(AlarmSlot(days: [day], alarmTime: newAlarmTime))
            return [.resyncGymAlarms, .reconcileWindDown]
        }

        if slots[index].days.contains(day) {
            slots[index].days.remove(day)
        } else {
            slots[index].days.insert(day)
            slots[index].isEnabled = true
        }
        return [.resyncGymAlarms, .reconcileWindDown]
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
