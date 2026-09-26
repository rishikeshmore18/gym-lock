import Foundation

// MARK: - Daypart

/// Which part of the day a session sits in.
///
/// This is the single switch that decides whether a user is asked to configure
/// sleep at all. Someone who trains after work should never be walked through a
/// bedtime picker, and someone with a mixed week should only see it applied to
/// the mornings.
enum SessionDaypart: String, Codable, Hashable, CaseIterable {
    case morning
    case midday
    case evening

    init(_ time: TimeOfDay) {
        switch time.hour {
        case 0..<11: self = .morning
        case 11..<16: self = .midday
        default: self = .evening
        }
    }

    /// Only a morning session is coupled to the sleep rhythm.
    var usesSleepRhythm: Bool { self == .morning }

    var label: String {
        switch self {
        case .morning: "morning"
        case .midday: "midday"
        case .evening: "evening"
        }
    }
}

// MARK: - Rhythm

/// The sleep-to-gym window: when the user goes to bed, when they get up, and how
/// long it takes them to actually be at the gym afterwards.
///
/// Every duration here is wall-clock minutes rather than a stored `Date`, so the
/// values survive timezone changes and daylight-saving transitions untouched —
/// 6:30 AM stays 6:30 AM wherever the user wakes up.
struct MorningRhythm: Hashable {
    var bedtime: TimeOfDay
    var wakeTime: TimeOfDay
    var getReadyMinutes: Int
    var travelMinutes: Int
    /// How long the user plans to be at the gym once they arrive. Drawn as
    /// the coral bar on the day dial; nothing locks or unlocks on it.
    var gymSessionMinutes: Int = 60
    /// When the user plans to be at the gym.
    ///
    /// Stored, not derived, and that is the whole point: the coral bar on the
    /// dial is its own value, so it can be dragged anywhere in the day without
    /// dragging the night along behind it. `nil` means "wherever the window
    /// puts it", which is how every plan saved before the bar became
    /// independent keeps reading correctly.
    var gymTime: TimeOfDay? = nil
    /// False until the user has actually been through the rhythm screen, so the
    /// app can tell a real answer from a default.
    var hasBeenSet: Bool

    // MARK: Product guardrails

    /// Below this the window is too short to be a plan rather than a panic.
    static let minimumWindow = 10
    /// The comfortable upper end. Past this we warn but still allow.
    static let normalMaximumWindow = 90
    /// The hard ceiling. GymLock's whole premise is that the alarm leads
    /// directly into the trip; beyond two hours it is a calendar, not a lock.
    static let absoluteMaximumWindow = 120

    /// The shortest sleep schedule anyone can set (FLOW, the night lock edge
    /// cases). Every place sleep can be set checks this one number.
    static let minimumSleepMinutes = 5 * 60
    /// Shown wherever a sleep schedule under the minimum is refused.
    static let sleepMinimumMessage = "the sleep schedule must be at least 5 hours."

    /// The smallest gap the app keeps between the alarm and the gym, so the
    /// two never land on top of each other. The dial enforces the same number
    /// while dragging.
    static let minimumGymLead = 10
    /// Past this the gym bar is not "later today" any more, it is before the
    /// alarm read the long way round, and the plan needs repairing.
    static let maximumSaneGapMinutes = 12 * 60

    static let getReadyRange = 5...60
    /// Wide enough that get-ready plus travel can reach the absolute window
    /// ceiling; the ceiling itself is enforced by `absoluteMaximumWindow`.
    static let travelRange = 0...115
    /// A workout shorter than this is a warm-up; longer than this is a day out.
    static let sessionRange = 15...240

    static let getReadyPresets = [10, 15, 20, 30, 45]
    static let travelPresets = [5, 10, 15, 20, 30, 45, 60]

    static let `default` = MorningRhythm(
        bedtime: TimeOfDay(hour: 23, minute: 0),
        wakeTime: TimeOfDay(hour: 6, minute: 30),
        getReadyMinutes: 20,
        travelMinutes: 15,
        hasBeenSet: false
    )

    // MARK: Derived

    /// Total minutes from the alarm going off to standing in the gym.
    var windowMinutes: Int { getReadyMinutes + travelMinutes }

    /// Minutes of sleep, wrapping correctly across midnight.
    ///
    /// 11:00 PM to 6:30 AM is 7 h 30 m, not a negative number.
    var sleepMinutes: Int {
        let raw = wakeTime.minutesFromMidnight - bedtime.minutesFromMidnight
        return (raw + 24 * 60) % (24 * 60)
    }

    var sleepHoursPart: Int { sleepMinutes / 60 }
    var sleepMinutesPart: Int { sleepMinutes % 60 }

    /// When the user should be walking out of the door.
    var leaveTime: TimeOfDay { wakeTime.offset(byMinutes: getReadyMinutes) }

    /// When they should be at the gym: the bar they placed, or the end of the
    /// window if they have never moved it.
    var gymByTime: TimeOfDay { gymTime ?? wakeTime.offset(byMinutes: windowMinutes) }

    /// When the planned workout ends.
    var gymDoneTime: TimeOfDay { gymByTime.offset(byMinutes: gymSessionMinutes) }

    /// Minutes from the alarm to the gym bar. This is the gap on the dial, and
    /// it is not the same thing as the lock window: the gap can be any length,
    /// while the window that actually blocks apps stays bounded.
    var gapToGymMinutes: Int { wakeTime.minutes(until: gymByTime) }

    // MARK: Editing

    /// Moves the alarm, keeping the gym plan coherent.
    ///
    /// Bedtime stays put and the night gets longer or shorter, which is what
    /// Apple's Clock does and what the wake handle on the dial does.
    ///
    /// The placed gym bar normally stays exactly where it is, because the two
    /// are independent decisions. The one exception is a repair: if the new
    /// alarm lands on or past the bar, the gap would silently read as most of
    /// a day, so the visit comes along and keeps the gap it had. A bar that
    /// was never placed follows the window on its own and needs nothing.
    mutating func setWakeTime(_ newValue: TimeOfDay) {
        guard newValue != wakeTime else { return }
        let previousGap = gapToGymMinutes
        wakeTime = newValue
        guard gymTime != nil else { return }
        let gap = gapToGymMinutes
        guard gap < Self.minimumGymLead || gap > Self.maximumSaneGapMinutes else { return }
        gymTime = newValue.offset(byMinutes: previousGap)
    }

    var exceedsAbsoluteMaximum: Bool { windowMinutes > Self.absoluteMaximumWindow }
    var exceedsNormalMaximum: Bool { windowMinutes > Self.normalMaximumWindow }
    var isBelowMinimum: Bool { windowMinutes < Self.minimumWindow }
    /// Whether the night is at least 5 hours.
    var meetsSleepMinimum: Bool { sleepMinutes >= Self.minimumSleepMinutes }

    /// The same check for two loose times, for the onboarding wheels.
    static func meetsSleepMinimum(bedtime: TimeOfDay, wake: TimeOfDay) -> Bool {
        bedtime.minutes(until: wake) >= minimumSleepMinutes
    }

    /// True when the window is usable as-is.
    var isWithinGuardrails: Bool { !exceedsAbsoluteMaximum && !isBelowMinimum }
}

extension MorningRhythm: Codable {
    private enum CodingKeys: String, CodingKey {
        case bedtime, wakeTime, getReadyMinutes, travelMinutes, gymSessionMinutes, gymTime, hasBeenSet
    }

    /// Plans saved before the workout length existed decode with the default,
    /// so nobody's stored schedule is thrown away by the upgrade.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bedtime = try container.decode(TimeOfDay.self, forKey: .bedtime)
        wakeTime = try container.decode(TimeOfDay.self, forKey: .wakeTime)
        getReadyMinutes = try container.decode(Int.self, forKey: .getReadyMinutes)
        travelMinutes = try container.decode(Int.self, forKey: .travelMinutes)
        gymSessionMinutes = try container.decodeIfPresent(Int.self, forKey: .gymSessionMinutes) ?? 60
        gymTime = try container.decodeIfPresent(TimeOfDay.self, forKey: .gymTime)
        hasBeenSet = try container.decode(Bool.self, forKey: .hasBeenSet)
    }
}

// MARK: - Next alarm only

/// A one-time change to the very next alarm, leaving the weekly schedule as
/// it was: Apple's "Change Next Alarm Only".
///
/// Carries its own id because the alarm backends key alarms by id and the
/// slot's weekly alarm must keep its own. Once the morning it describes is
/// over the override is dropped and the schedule resumes untouched.
struct NextAlarmOverride: Codable, Hashable, Identifiable {
    var id: UUID
    /// The slot whose next ring this replaces.
    var slotID: UUID
    /// The exact moment the one-off alarm rings.
    var fireDate: Date
    /// The rhythm in force for that one morning.
    var rhythm: MorningRhythm

    init(id: UUID = UUID(), slotID: UUID, fireDate: Date, rhythm: MorningRhythm) {
        self.id = id
        self.slotID = slotID
        self.fireDate = fireDate
        self.rhythm = rhythm
    }

    /// The override outlives its ring long enough for the morning to be
    /// resumed, then expires so the weekly alarm for that day comes back.
    func isActive(at now: Date) -> Bool {
        let closesAt = fireDate.addingTimeInterval(Double(rhythm.windowMinutes + 30) * 60)
        return now < closesAt
    }

    func weekday(calendar: Calendar = .current) -> Weekday? {
        Weekday(rawValue: calendar.component(.weekday, from: fireDate))
    }
}

// MARK: - Night lock (legacy settings)

/// What older builds stored for the night lock: an on/off switch and a custom
/// window.
///
/// Read so old plans still decode, then ignored. The night lock is always on
/// and always runs from bedtime to wake time on the sleep schedule's nights
/// (FLOW, "The Night Lock"). Nothing in the app reads these fields.
struct NightLockWindow: Codable, Hashable {
    var isEnabled: Bool
    var followsRhythm: Bool
    var customStart: TimeOfDay
    var customEnd: TimeOfDay

    static let `default` = NightLockWindow(
        isEnabled: true,
        followsRhythm: true,
        customStart: TimeOfDay(hour: 23, minute: 0),
        customEnd: TimeOfDay(hour: 6, minute: 30)
    )
}

// MARK: - Pending bedtime

/// A bedtime change waiting for its first night.
///
/// A new bedtime starts from tomorrow night, so moving it at 22:55 can't dodge
/// tonight's lock (FLOW, the night lock edge cases).
struct PendingBedtime: Codable, Hashable {
    var bedtime: TimeOfDay
    /// When tonight ends: the wake time after the night in progress, or the
    /// next one if none is. A night that starts before this keeps the old
    /// bedtime; a night that starts at or after it uses the new one.
    var startsAt: Date
}

// MARK: - Alarm slots

/// One recurring alarm: a time and the days it rings on.
///
/// The slot is defined by when the alarm *fires*, not by when the session
/// starts, because that is the only value the operating system can act on. The
/// gym-by time is derived from it by adding the window.
struct AlarmSlot: Codable, Hashable, Identifiable {
    var id: UUID
    var days: Set<Weekday>
    var alarmTime: TimeOfDay
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        days: Set<Weekday>,
        alarmTime: TimeOfDay,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.days = days
        self.alarmTime = alarmTime
        self.isEnabled = isEnabled
    }

    var daypart: SessionDaypart { SessionDaypart(alarmTime) }

    /// Days in Monday-first order, for display.
    var orderedDays: [Weekday] {
        Weekday.allCases.filter { days.contains($0) }
    }

    var daysSummary: String {
        if days.count == 7 { return "every day" }
        if days.isEmpty { return "no days" }
        return orderedDays.map(\.shortLabel).joined(separator: " · ")
    }

    func gymByTime(window: Int) -> TimeOfDay {
        alarmTime.offset(byMinutes: window)
    }
}

// MARK: - The plan

/// Everything about *when* GymLock acts, held in one place alongside the
/// onboarding profile rather than duplicating it.
///
/// The profile records what the user told us about themselves; this records the
/// schedule they are actually running. Both live on `AppStore`.
struct MorningPlan: Hashable {
    var rhythm: MorningRhythm
    var nightLock: NightLockWindow
    var slots: [AlarmSlot]
    /// Activation missions can be switched off entirely from settings.
    var missionsEnabled: Bool
    /// Missions the user has been given recently, newest last. Used only to
    /// avoid handing out the same one twice in a row.
    var recentMissions: [ActivationMissionType]
    /// Set once the plan has been reviewed on the Morning Alarm Plan screen.
    var hasBeenReviewed: Bool
    /// A one-off change to the next alarm, if the user asked for one.
    var nextAlarmOverride: NextAlarmOverride? = nil
    /// Whether the morning alarm offers its single snooze at all.
    var snoozeEnabled: Bool = true
    /// How long that snooze lasts. Five until the user says otherwise, which
    /// is what the snooze has always been.
    var snoozeMinutes: Int = 5
    /// The vibration that rides with the track while it rings in the app.
    var alarmHaptic: AlarmHaptic = .synchronized
    /// Which screen the user wakes up to. Stored now, read by the ringing
    /// screen once the two styles exist.
    var alarmScreenStyle: AlarmScreenStyle = .sunrise
    /// The nights the user chose for the sleep schedule, keyed by the day the
    /// night starts on. Only the user's own choice: nights a gym morning
    /// requires are derived, never written here. See `SleepSchedule`.
    var sleepScheduleDays: Set<Weekday> = Set(Weekday.allCases)
    /// A bedtime change that starts on a later night. See `SleepRules`.
    var pendingBedtime: PendingBedtime? = nil
    /// Set for an existing user whose wake time was really their gym alarm,
    /// until they answer "when do you wake up?".
    var needsWakeTimeAnswer: Bool = false
    /// Whether the wake-time check for existing users has run. True for any
    /// plan built by this version; false on plans saved before it.
    var hasCheckedWakeTime: Bool = true

    /// The snooze lengths on offer. Fifteen is the ceiling: past that it is
    /// not a snooze, it is going back to sleep.
    static let snoozeRange: ClosedRange<Int> = 1...15

    static let `default` = MorningPlan(
        rhythm: .default,
        nightLock: .default,
        slots: [],
        missionsEnabled: true,
        recentMissions: [],
        hasBeenReviewed: false
    )

    // MARK: Derived

    /// The override, but only while it still means something.
    func activeOverride(at now: Date = Date()) -> NextAlarmOverride? {
        guard let nextAlarmOverride, nextAlarmOverride.isActive(at: now),
              slots.contains(where: { $0.id == nextAlarmOverride.slotID })
        else { return nil }
        return nextAlarmOverride
    }

    /// The rhythm that governs a morning starting at `date`: the one-off if
    /// this is the morning it was made for, the schedule otherwise.
    func rhythm(at date: Date = Date(), calendar: Calendar = .current) -> MorningRhythm {
        guard let override = activeOverride(at: date),
              calendar.isDate(date, inSameDayAs: override.fireDate)
        else { return rhythm }
        return override.rhythm
    }

    /// The slot an alarm id stands for. A one-off alarm carries its own id,
    /// so this is how the morning it starts finds its way back to the slot.
    func slot(forAlarmID id: UUID?) -> AlarmSlot? {
        guard let id else { return nil }
        if let slot = slots.first(where: { $0.id == id }) { return slot }
        guard let override = nextAlarmOverride, override.id == id else { return nil }
        return slots.first { $0.id == override.slotID }
    }

    var enabledSlots: [AlarmSlot] {
        slots.filter { $0.isEnabled && !$0.days.isEmpty }
    }

    /// True when at least one enabled alarm rings in the morning, which is the
    /// only condition under which the sleep rhythm is worth configuring.
    var hasMorningSessions: Bool {
        enabledSlots.contains { $0.daypart.usesSleepRhythm }
    }

    /// Whether the sleep rhythm screen should be shown at all.
    var needsSleepRhythm: Bool {
        hasMorningSessions && !rhythm.hasBeenSet
    }

    var windowMinutes: Int { rhythm.windowMinutes }

    /// The sleep schedule the user has set: the rhythm with any pending
    /// bedtime already in place. What the Alarm screen shows and edits.
    /// Tonight's lock still runs on `rhythm` until the pending one is due.
    var scheduledRhythm: MorningRhythm {
        var scheduled = rhythm
        if let pendingBedtime { scheduled.bedtime = pendingBedtime.bedtime }
        return scheduled
    }

    /// The slot that will ring next, and the date it will ring on.
    ///
    /// A one-off override stands in for its slot's ring on that day: the slot
    /// comes back with the override's alarm time so every screen that reads
    /// "next alarm" agrees with what will actually ring.
    func nextOccurrence(after date: Date = Date(), calendar: Calendar = .current) -> (slot: AlarmSlot, fireDate: Date)? {
        let override = activeOverride(at: date)

        var candidates = enabledSlots.compactMap { slot -> (AlarmSlot, Date)? in
            var days = slot.days
            if let override, override.slotID == slot.id, let day = override.weekday(calendar: calendar) {
                // The weekly ring on the override's day is replaced, not added to.
                days.remove(day)
            }
            guard !days.isEmpty,
                  let next = slot.alarmTime.nextDate(after: date, on: days, calendar: calendar)
            else { return nil }
            return (slot, next)
        }

        if let override, override.fireDate > date,
           var slot = slots.first(where: { $0.id == override.slotID }), slot.isEnabled {
            slot.alarmTime = TimeOfDay(from: override.fireDate)
            candidates.append((slot, override.fireDate))
        }

        return candidates
            .min { $0.1 < $1.1 }
            .map { (slot: $0.0, fireDate: $0.1) }
    }

    /// The rhythm the next alarm will run on.
    func nextRhythm(after date: Date = Date(), calendar: Calendar = .current) -> MorningRhythm {
        guard let next = nextOccurrence(after: date, calendar: calendar) else { return rhythm }
        return rhythm(at: next.fireDate, calendar: calendar)
    }

    /// Sessions planned in a rolling 28-day period, used for the skip
    /// allowance. Derived from the schedule rather than logged history so a new
    /// user is not punished for having no past.
    var plannedSessionsPer28Days: Int {
        let perWeek = enabledSlots.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }.count
        return perWeek * 4
    }

    /// Builds a starting plan out of what onboarding already learned, so the
    /// user is never asked the same question twice.
    static func seeded(from profile: OnboardingProfile, schedule: GymSchedule) -> MorningPlan {
        var plan = MorningPlan.default

        let days = schedule.trainingDays.isEmpty
            ? AppStore.spreadTrainingDays(count: profile.targetWorkoutsPerWeek)
            : schedule.trainingDays

        plan.slots = [AlarmSlot(days: days, alarmTime: profile.alarmTime)]

        // Both sleep times are real answers from onboarding. The gym time is
        // when they said their plan falls apart, which is when they train.
        // Wake time is never derived from the gym time.
        plan.rhythm.bedtime = profile.bedtime
        plan.rhythm.wakeTime = profile.answeredWakeTime
        plan.rhythm.gymTime = profile.failureTime

        return plan
    }
}

extension MorningPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case rhythm, nightLock, slots, missionsEnabled, recentMissions, hasBeenReviewed, nextAlarmOverride
        case snoozeEnabled, snoozeMinutes, alarmHaptic
        case alarmScreenStyle
        case sleepScheduleDays
        case pendingBedtime, needsWakeTimeAnswer, hasCheckedWakeTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rhythm = try container.decode(MorningRhythm.self, forKey: .rhythm)
        nightLock = try container.decode(NightLockWindow.self, forKey: .nightLock)
        slots = try container.decode([AlarmSlot].self, forKey: .slots)
        missionsEnabled = try container.decode(Bool.self, forKey: .missionsEnabled)
        recentMissions = try container.decode([ActivationMissionType].self, forKey: .recentMissions)
        hasBeenReviewed = try container.decode(Bool.self, forKey: .hasBeenReviewed)
        nextAlarmOverride = try container.decodeIfPresent(NextAlarmOverride.self, forKey: .nextAlarmOverride)
        // Plans saved before these options existed decode to exactly what
        // the alarm already did: a five minute snooze and the original pulse.
        snoozeEnabled = try container.decodeIfPresent(Bool.self, forKey: .snoozeEnabled) ?? true
        let minutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 5
        snoozeMinutes = min(max(minutes, Self.snoozeRange.lowerBound), Self.snoozeRange.upperBound)
        alarmHaptic = try container.decodeIfPresent(AlarmHaptic.self, forKey: .alarmHaptic) ?? .synchronized
        // Missing on plans saved before the choice existed. `try?` as well,
        // so a style this build does not know cannot throw away the plan.
        alarmScreenStyle = (try? container.decodeIfPresent(AlarmScreenStyle.self, forKey: .alarmScreenStyle)) ?? .sunrise
        // Before the sleep schedule had days it ran every night, so a plan
        // without the key keeps doing exactly that.
        sleepScheduleDays = (try? container.decodeIfPresent(Set<Weekday>.self, forKey: .sleepScheduleDays))
            ?? Set(Weekday.allCases)
        pendingBedtime = try? container.decodeIfPresent(PendingBedtime.self, forKey: .pendingBedtime)
        needsWakeTimeAnswer = (try? container.decodeIfPresent(Bool.self, forKey: .needsWakeTimeAnswer)) ?? false
        // Missing means the plan predates the check, so it still has to run.
        hasCheckedWakeTime = (try? container.decodeIfPresent(Bool.self, forKey: .hasCheckedWakeTime)) ?? false
    }
}

// MARK: - Time helpers

extension TimeOfDay {
    var minutesFromMidnight: Int { hour * 60 + minute }

    /// Whole minutes from this time forward to `other`, wrapping past midnight.
    func minutes(until other: TimeOfDay) -> Int {
        (other.minutesFromMidnight - minutesFromMidnight + 24 * 60) % (24 * 60)
    }

    /// The next calendar date this time occurs on one of `days`.
    ///
    /// Built on `Calendar.nextDate`, which resolves daylight-saving transitions
    /// correctly — a 6:30 AM alarm stays at 6:30 AM local time through the
    /// clocks changing rather than drifting by an hour.
    func nextDate(
        after date: Date = Date(),
        on days: Set<Weekday>? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        guard let days, !days.isEmpty else {
            return calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute),
                matchingPolicy: .nextTimePreservingSmallerComponents
            )
        }

        return days.compactMap { day in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute, weekday: day.rawValue),
                matchingPolicy: .nextTimePreservingSmallerComponents
            )
        }
        .min()
    }
}
