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
struct MorningRhythm: Codable, Hashable {
    var bedtime: TimeOfDay
    var wakeTime: TimeOfDay
    var getReadyMinutes: Int
    var travelMinutes: Int
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

    static let getReadyRange = 5...60
    static let travelRange = 0...60

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

    /// When they should be at the gym.
    var gymByTime: TimeOfDay { wakeTime.offset(byMinutes: windowMinutes) }

    var exceedsAbsoluteMaximum: Bool { windowMinutes > Self.absoluteMaximumWindow }
    var exceedsNormalMaximum: Bool { windowMinutes > Self.normalMaximumWindow }
    var isBelowMinimum: Bool { windowMinutes < Self.minimumWindow }

    /// True when the window is usable as-is.
    var isWithinGuardrails: Bool { !exceedsAbsoluteMaximum && !isBelowMinimum }
}

// MARK: - Night lock

/// The optional evening lock, kept deliberately separate from the rhythm so that
/// a user who has tuned it by hand does not silently lose that when they change
/// their bedtime.
struct NightLockWindow: Codable, Hashable {
    var isEnabled: Bool
    /// When true the window simply mirrors bedtime → wake time.
    var followsRhythm: Bool
    var customStart: TimeOfDay
    var customEnd: TimeOfDay

    static let `default` = NightLockWindow(
        isEnabled: false,
        followsRhythm: true,
        customStart: TimeOfDay(hour: 23, minute: 0),
        customEnd: TimeOfDay(hour: 6, minute: 30)
    )

    func start(in rhythm: MorningRhythm) -> TimeOfDay {
        followsRhythm ? rhythm.bedtime : customStart
    }

    func end(in rhythm: MorningRhythm) -> TimeOfDay {
        followsRhythm ? rhythm.wakeTime : customEnd
    }

    func summary(in rhythm: MorningRhythm) -> String {
        "\(start(in: rhythm).displayString) → \(end(in: rhythm).displayString)"
    }
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
struct MorningPlan: Codable, Hashable {
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

    static let `default` = MorningPlan(
        rhythm: .default,
        nightLock: .default,
        slots: [],
        missionsEnabled: true,
        recentMissions: [],
        hasBeenReviewed: false
    )

    // MARK: Derived

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

    /// The slot that will ring next, and the date it will ring on.
    func nextOccurrence(after date: Date = Date(), calendar: Calendar = .current) -> (slot: AlarmSlot, fireDate: Date)? {
        enabledSlots
            .compactMap { slot -> (AlarmSlot, Date)? in
                guard let next = slot.alarmTime.nextDate(after: date, on: slot.days, calendar: calendar) else {
                    return nil
                }
                return (slot, next)
            }
            .min { $0.1 < $1.1 }
            .map { (slot: $0.0, fireDate: $0.1) }
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

        plan.nightLock.isEnabled = profile.wantsNightLock
        plan.nightLock.followsRhythm = true

        // The bedtime the user already gave us is a real answer; the wake time
        // is only a starting position derived from when they train.
        plan.rhythm.bedtime = profile.bedtime
        plan.rhythm.wakeTime = profile.alarmTime

        return plan
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
