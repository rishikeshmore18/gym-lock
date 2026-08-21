import Foundation

/// Everything Home needs about the user's journey, derived in one place from
/// real stored history.
///
/// Nothing in here is invented. A brand-new user gets a start marker, week one
/// marked as up next, a streak of zero and no missed weeks — which is the
/// truth, and reads far better than a mountain pretending to hold progress that
/// was never earned.
struct JourneySnapshot {
    let spec: MountainWorldSpec
    let pins: [WeekPin]
    let streak: Int
    let missedWeeks: Int
    let nextCheckInDate: Date?
    let hasSchedule: Bool
    let plannedPerWeek: Int
    let verifiedThisWeek: Int
    let hasVerifiedToday: Bool

    /// Weekday name of the next photo check-in, e.g. "Sunday".
    var nextCheckInLabel: String? {
        guard let nextCheckInDate else { return nil }
        return nextCheckInDate.formatted(.dateTime.weekday(.wide))
    }

    static func make(from store: AppStore, calendar: Calendar = .current) -> JourneySnapshot {
        let journey = store.journey
        let planned = max(store.schedule.trainingDays.count, 1)
        let hasStarted = journey.startDate != nil
        let currentWeek = hasStarted ? journey.currentWeekIndex : 0
        let focusExpedition = currentWeek / JourneyProgress.weeksPerExpedition

        // Show the mountain being climbed, up to two completed peaks behind it
        // as history, and nothing ahead — the next expedition only appears once
        // this one is summited.
        let oldest = max(0, focusExpedition - 2)
        let expeditions = Array(oldest...focusExpedition)

        // Weeks are only drawn for the peaks that exist, and only one week past
        // the current one, so an empty journey is not a mountain of ghosts.
        var pins: [WeekPin] = []
        let lastWeekToShow = (focusExpedition + 1) * JourneyProgress.weeksPerExpedition - 1
        let firstWeekToShow = oldest * JourneyProgress.weeksPerExpedition

        for week in firstWeekToShow...max(firstWeekToShow, lastWeekToShow) {
            let state: CheckpointState = hasStarted
                ? journey.state(forWeek: week, planned: planned, calendar: calendar)
                : (week == 0 ? .current : .upcoming)

            // Before the user has started, only week one is worth naming.
            if !hasStarted && week > 0 { continue }

            let verified = hasStarted ? journey.verifiedCount(inWeek: week, calendar: calendar) : 0

            pins.append(WeekPin(
                id: week,
                expedition: week / JourneyProgress.weeksPerExpedition,
                indexInExpedition: week % JourneyProgress.weeksPerExpedition,
                state: state,
                verified: verified,
                planned: planned,
                hasPhoto: journey.weekPhotos[week] != nil
            ))
        }

        // Day 0 sits at the base of the mountain being climbed, always.
        pins.insert(
            WeekPin(
                id: -1,
                expedition: focusExpedition,
                indexInExpedition: -1,
                state: .start,
                verified: 0,
                planned: planned,
                hasPhoto: store.profile.day0Media?.kind == .photo
            ),
            at: 0
        )

        let verifiedThisWeek = hasStarted
            ? journey.verifiedCount(inWeek: currentWeek, calendar: calendar)
            : 0

        // The marker advances with verified sessions, never with elapsed time —
        // opening the app on Friday does not move anyone up the mountain.
        let weekInExpedition = currentWeek % JourneyProgress.weeksPerExpedition
        let withinWeek = min(Float(verifiedThisWeek) / Float(planned), 1)
        let position = hasStarted
            ? (Float(weekInExpedition) + withinWeek) / Float(JourneyProgress.weeksPerExpedition)
            : 0

        let spec = MountainWorldSpec(
            expeditions: expeditions,
            focusExpedition: focusExpedition,
            pins: pins,
            currentPosition: position,
            hasStarted: hasStarted
        )

        return JourneySnapshot(
            spec: spec,
            pins: pins,
            streak: journey.streak(trainingDays: store.schedule.trainingDays, calendar: calendar),
            missedWeeks: journey.missedWeekCount(calendar: calendar),
            nextCheckInDate: journey.endOfWeek(currentWeek, calendar: calendar),
            hasSchedule: !store.schedule.trainingDays.isEmpty,
            plannedPerWeek: planned,
            verifiedThisWeek: verifiedThisWeek,
            hasVerifiedToday: journey.hasVerifiedToday
        )
    }
}

/// What GymLock is doing for the user right now.
///
/// Home does not redesign itself for each of these — only the contextual line
/// under the mountain header changes.
enum DayStatus: Equatable {
    /// Nothing scheduled at all.
    case noSchedule
    /// A future session, with its date.
    case scheduled(Date)
    /// The alarm window has arrived.
    case timeToGo
    /// The user said they were going.
    case lockedIn
    /// Today's session is logged.
    case verified
    /// A rest day.
    case restDay

    var title: String {
        switch self {
        case .noSchedule: "No GymLock scheduled"
        case .scheduled: "Next GymLock"
        case .timeToGo: "It's time."
        case .lockedIn: "You're locked in."
        case .verified: "Done."
        case .restDay: "Rest day"
        }
    }

    var detail: String {
        switch self {
        case .noSchedule: "Set schedule"
        case .scheduled(let date): date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .timeToGo: "Apps lock now"
        case .lockedIn: "Get to the gym"
        case .verified: "Apps unlocked"
        case .restDay: "Recover properly"
        }
    }

    var icon: String {
        switch self {
        case .noSchedule: "calendar.badge.plus"
        case .scheduled: "clock.fill"
        case .timeToGo: "bell.fill"
        case .lockedIn: "lock.fill"
        case .verified: "checkmark.seal.fill"
        case .restDay: "moon.zzz.fill"
        }
    }

    /// Green is reserved for verified system states, exactly as specified.
    var isPositive: Bool { self == .verified }

    var isUrgent: Bool {
        switch self {
        case .timeToGo, .lockedIn: true
        default: false
        }
    }

    /// Derives today's state from the schedule, the clock and what the user has
    /// actually logged.
    static func current(store: AppStore, now: Date = Date(), calendar: Calendar = .current) -> DayStatus {
        guard !store.schedule.trainingDays.isEmpty else { return .noSchedule }
        if store.journey.hasVerifiedToday { return .verified }

        guard store.isTrainingDayToday else {
            if let next = store.nextSessionDate(from: now, calendar: calendar) {
                return .scheduled(next)
            }
            return .restDay
        }

        let alarm = store.profile.alarmTime
        let alarmToday = calendar.date(
            bySettingHour: alarm.hour,
            minute: alarm.minute,
            second: 0,
            of: now
        ) ?? now

        if now >= alarmToday {
            return store.hasCommittedToday ? .lockedIn : .timeToGo
        }

        if let next = store.nextSessionDate(from: now, calendar: calendar) {
            return .scheduled(next)
        }
        return .restDay
    }
}
