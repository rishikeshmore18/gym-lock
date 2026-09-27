import Foundation

// MARK: - Step 0: which flow

/// Which flow a gym day runs (`docs/FLOW.md`, "Step 0").
///
/// Decided by the gap between waking and the gym, never by the clock: a gap of
/// 2 hours or less is Wake & Go (the wake-up alarm is the gym alarm), anything
/// longer is Go Later (a separate "time to go" alarm).
nonisolated enum GymFlowMode: String, Codable, Hashable, CaseIterable {
    case wakeAndGo
    case goLater

    var label: String {
        switch self {
        case .wakeAndGo: "wake & go"
        case .goLater: "go later"
        }
    }
}

extension MorningRhythm {
    /// Step 0 for this rhythm. The ceiling is the existing 2-hour window.
    var flowMode: GymFlowMode {
        gapToGymMinutes <= Self.absoluteMaximumWindow ? .wakeAndGo : .goLater
    }

    /// When the "time to go" alarm rings: gym time minus get ready and travel.
    /// Gym 18:00, 10 + 20 min gives 17:30 (FLOW, Flow 2).
    var timeToGo: TimeOfDay {
        gymByTime.offset(byMinutes: -windowMinutes)
    }

    /// When the alarm that locks the apps rings: wake time in Wake & Go, the
    /// "time to go" time in Go Later.
    var lockAlarmTime: TimeOfDay {
        flowMode == .wakeAndGo ? wakeTime : timeToGo
    }
}

// MARK: - Alarm kinds

/// What an alarm does when it rings.
nonisolated enum AlarmKind: String, Codable, Hashable {
    /// Wake & Go: the wake-up alarm is the gym alarm. Locks, starts a
    /// session, one snooze.
    case gym
    /// Go Later: locks and starts a session. No snooze; running late instead.
    case timeToGo
    /// A plain wake-up. No lock, no session, no handoff.
    case plainWake

    /// Whether ringing this alarm locks the apps and starts a session.
    var locks: Bool { self != .plainWake }
}

/// Stable ids for plain wake alarms, recognisable from the id alone.
///
/// AlarmKit reports alerting alarms by id only, so the observer has to tell a
/// plain wake alarm apart without any other context. These ids are UUID
/// version 8 with a fixed "WAKE" prefix; `UUID()` only ever makes version 4,
/// so a slot or one-off id can never be mistaken for one.
nonisolated enum WakeAlarmID {
    /// The weekly plain wake alarm.
    static let weekly = derive(from: UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)))

    /// The plain wake id that belongs to another alarm id. Deterministic, so
    /// every sync replaces the same alarm instead of adding one.
    static func derive(from source: UUID) -> UUID {
        var bytes = source.uuid
        bytes.0 = 0x57
        bytes.1 = 0x41
        bytes.2 = 0x4B
        bytes.3 = 0x45
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        return UUID(uuid: bytes)
    }

    static func isWake(_ id: UUID) -> Bool {
        let bytes = id.uuid
        return bytes.0 == 0x57 && bytes.1 == 0x41 && bytes.2 == 0x4B && bytes.3 == 0x45
            && (bytes.6 & 0xF0) == 0x80
    }

    /// Whether an alarm that started alerting may start a session. The
    /// AlarmKit observer asks this before writing a handoff.
    static func startsSession(alarmID: UUID) -> Bool {
        !isWake(alarmID)
    }
}

// MARK: - One-off alarms

/// One alarm that rings once, at an exact moment.
///
/// Replaces the single "change next alarm only" override. Old saved plans
/// decode their `nextAlarmOverride` into this with `kind == .nextAlarmChange`.
struct OneOffAlarm: Codable, Hashable, Identifiable {
    nonisolated enum Kind: String, Codable, Hashable {
        /// "Change next alarm only" on the Alarm screen.
        case nextAlarmChange
        /// "Running late": the same session rings again later.
        case runningLate
        /// A reschedule, added with the skip screen (FLOW, Flow 4).
        case reschedule

        /// Whether this alarm stands in for that day's weekly ring.
        var replacesWeeklyRing: Bool { self != .runningLate }
    }

    /// The alarm's own id. The alarm backends key alarms by id, so the
    /// slot's weekly alarm keeps its own.
    var id: UUID
    var kind: Kind
    /// The slot this alarm belongs to.
    var slotID: UUID?
    /// The exact moment it rings.
    var fireDate: Date
    /// The rhythm in force for that one day (a next-alarm change only).
    var rhythm: MorningRhythm?
    /// The day the workout was moved from, for a reschedule. Cancelling turns
    /// the reschedule into a skip on that day (FLOW, Flow 4). Nil on older
    /// one-offs and on every other kind.
    var originDay: Date?

    init(
        id: UUID = UUID(),
        kind: Kind = .nextAlarmChange,
        slotID: UUID?,
        fireDate: Date,
        rhythm: MorningRhythm? = nil,
        originDay: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.slotID = slotID
        self.fireDate = fireDate
        self.rhythm = rhythm
        self.originDay = originDay
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, slotID, fireDate, rhythm, originDay
    }

    /// A legacy `NextAlarmOverride` has no `kind`, so it is a next-alarm change.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? .nextAlarmChange
        slotID = try container.decodeIfPresent(UUID.self, forKey: .slotID)
        fireDate = try container.decode(Date.self, forKey: .fireDate)
        rhythm = try container.decodeIfPresent(MorningRhythm.self, forKey: .rhythm)
        originDay = try container.decodeIfPresent(Date.self, forKey: .originDay)
    }

    /// Kept long enough for the day to be resumed, then dropped so the weekly
    /// alarm comes back.
    func isActive(at now: Date) -> Bool {
        let window = kind == .nextAlarmChange ? (rhythm?.windowMinutes ?? 0) : 0
        return now < fireDate.addingTimeInterval(Double(window + 30) * 60)
    }

    func weekday(calendar: Calendar = .current) -> Weekday? {
        Weekday(rawValue: calendar.component(.weekday, from: fireDate))
    }
}

// MARK: - Which alarms ring

/// One alarm the OS should hold, before sound and wording are attached.
struct PlannedAlarm: Hashable {
    var id: UUID
    var kind: AlarmKind
    var time: TimeOfDay
    var weekdays: Set<Weekday>
    var fireDate: Date?
    var allowsSnooze: Bool
}

/// Which alarms ring (FLOW, Flow 1 and Flow 2, and the plan in Step 2 of the
/// alarm rules).
///
/// - Wake & Go: the gym alarm at wake time on gym days; the plain wake alarm
///   at the same time on the other days.
/// - Go Later: the "time to go" alarm on gym days, and the plain wake alarm
///   at wake time on every day.
///
/// Exactly one lock alarm per gym day. Pure: the coordinator adds the sound
/// and sends the result to the OS.
enum AlarmPlan {
    static func alarms(for plan: MorningPlan, now: Date, calendar: Calendar) -> [PlannedAlarm] {
        let weekly = plan.rhythm
        let mode = weekly.flowMode
        let primaryID = plan.primaryAlarmSlot?.id

        var alarms: [PlannedAlarm] = plan.enabledSlots.map { slot in
            PlannedAlarm(
                id: slot.id,
                kind: mode == .wakeAndGo ? .gym : .timeToGo,
                // The main alarm follows the rhythm. Any older extra slot
                // keeps the time it was given.
                time: slot.id == primaryID ? weekly.lockAlarmTime : slot.alarmTime,
                weekdays: slot.days,
                fireDate: nil,
                allowsSnooze: plan.snoozeEnabled && mode == .wakeAndGo
            )
        }

        let gymDays = plan.enabledSlots.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }
        var wakeDays = mode == .wakeAndGo
            ? Set(Weekday.allCases).subtracting(gymDays)
            : Set(Weekday.allCases)
        var oneOffs: [PlannedAlarm] = []

        for oneOff in plan.oneOffAlarms where oneOff.isActive(at: now) && oneOff.fireDate > now {
            guard let slotID = oneOff.slotID,
                  plan.slots.contains(where: { $0.id == slotID && $0.isEnabled }),
                  let day = oneOff.weekday(calendar: calendar)
            else { continue }

            let rhythm = oneOff.rhythm ?? weekly
            // Running late only exists in Go Later.
            let oneOffMode: GymFlowMode = oneOff.kind == .runningLate ? .goLater : rhythm.flowMode

            if oneOff.kind.replacesWeeklyRing {
                if let index = alarms.firstIndex(where: { $0.id == slotID }) {
                    alarms[index].weekdays.remove(day)
                    if alarms[index].weekdays.isEmpty { alarms.remove(at: index) }
                }
                // That day's wake-up follows the one-off's own rhythm.
                wakeDays.remove(day)
                if plan.plainWakeAlarmEnabled, oneOffMode == .goLater,
                   let wakeDate = calendar.date(
                       bySettingHour: rhythm.wakeTime.hour,
                       minute: rhythm.wakeTime.minute,
                       second: 0,
                       of: oneOff.fireDate
                   ),
                   wakeDate > now {
                    oneOffs.append(
                        PlannedAlarm(
                            id: WakeAlarmID.derive(from: oneOff.id),
                            kind: .plainWake,
                            time: rhythm.wakeTime,
                            weekdays: [day],
                            fireDate: wakeDate,
                            allowsSnooze: plan.snoozeEnabled
                        )
                    )
                }
            }

            oneOffs.append(
                PlannedAlarm(
                    id: oneOff.id,
                    kind: oneOffMode == .wakeAndGo ? .gym : .timeToGo,
                    time: TimeOfDay(from: oneOff.fireDate),
                    weekdays: [day],
                    fireDate: oneOff.fireDate,
                    allowsSnooze: plan.snoozeEnabled && oneOffMode == .wakeAndGo
                )
            )
        }

        // Only once there is a plan: nobody in onboarding gets a wake alarm.
        if plan.plainWakeAlarmEnabled, !plan.enabledSlots.isEmpty, !wakeDays.isEmpty {
            alarms.append(
                PlannedAlarm(
                    id: WakeAlarmID.weekly,
                    kind: .plainWake,
                    time: weekly.wakeTime,
                    weekdays: wakeDays,
                    fireDate: nil,
                    allowsSnooze: plan.snoozeEnabled
                )
            )
        }

        return alarms + oneOffs
    }

    /// The next date a lock alarm on `rhythm` rings on one of `days`, after
    /// `now`. Used by "change next alarm only".
    static func nextLockFireDate(
        rhythm: MorningRhythm,
        days: Set<Weekday>,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        let time = rhythm.lockAlarmTime
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
                  days.contains(weekday),
                  let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                  date > now
            else { continue }
            return date
        }
        return nil
    }
}

// MARK: - The session's own rules

extension GymSession {
    /// The mode this session's alarm ran in. Sessions saved before the mode
    /// was stored fall back to what they did then.
    var resolvedFlowMode: GymFlowMode {
        flowMode ?? (SessionDaypart(alarmTime).usesSleepRhythm ? .wakeAndGo : .goLater)
    }

    /// When the lock lifts if the user never commits: the alarm plus the
    /// window plus 90 minutes, at most 4 hours (`ShieldPolicy`). The 08:35 in
    /// Flow 1 and the 19:30 in Flow 2.
    var effectiveLockDeadline: Date {
        lockDeadline ?? ShieldPolicy.deadline(forWindowMinutes: windowMinutes, from: alarmFiredAt ?? day)
    }
}

/// What to do with a session that is still live when it may not be wanted.
enum LeftoverSession: Equatable {
    /// Still the real session.
    case keep
    /// Never committed and past the lock deadline: the alarm was ignored.
    case endAsMissed
    /// From an earlier day and past its lock deadline: dropped, nothing
    /// recorded, the way a relaunch always treated stale sessions.
    case discard

    static func action(for session: GymSession, now: Date, calendar: Calendar) -> LeftoverSession {
        guard session.state.isLive else { return .keep }
        let deadline = session.effectiveLockDeadline
        guard now >= deadline else { return .keep }
        if !session.state.hasCommitted { return .endAsMissed }
        if !calendar.isDate(session.day, inSameDayAs: now) { return .discard }
        return .keep
    }
}

/// The "pick a day" notification after an ignored alarm (FLOW, Flow 1 and 2).
enum MissedNotice {
    static func message(forAlarmAt time: TimeOfDay) -> String {
        if time.hour < 11 { return "missed this morning. pick a day to make it up." }
        if time.hour >= 16 { return "missed tonight. pick a day to make it up." }
        return "missed today. pick a day to make it up."
    }

    /// One per day, so the tap knows which day to open.
    static func identifier(forDay day: Date, calendar: Calendar = .current) -> String {
        NotificationRoute.ID.missedPrefix + SessionResume.dayKey(for: day, calendar: calendar)
    }

    /// Scheduled when the alarm rings, and only stands while the session is
    /// still waiting for an answer. Committing or resolving cancels it.
    static func stands(for state: GymSessionState) -> Bool {
        state.isLive && !state.hasCommitted
    }
}

// MARK: - Running late

/// "Running late" (FLOW, Flow 2): Go Later only, once per session, +15 / +30
/// / +60 from the tap. The apps stay locked and a real alarm rings then.
enum RunningLate {
    static let choices = [15, 30, 60]

    /// The choices still on offer. Empty once used, outside Go Later, or
    /// outside the decision. Any choice whose visit would run into sleep
    /// hours is hidden.
    static func options(
        for session: GymSession,
        rhythm: MorningRhythm,
        pending: PendingBedtime?,
        now: Date,
        calendar: Calendar
    ) -> [Int] {
        guard session.resolvedFlowMode == .goLater,
              session.runningLateUsedAt == nil,
              session.state == .alarmFired || session.state == .awaitingDecision
        else { return [] }

        return choices.filter { minutes in
            let ring = now.addingTimeInterval(Double(minutes) * 60)
            let visitStart = ring.addingTimeInterval(Double(session.windowMinutes) * 60)
            let visitEnd = visitStart.addingTimeInterval(Double(rhythm.gymSessionMinutes) * 60)
            return !overlapsSleep(start: visitStart, end: visitEnd, rhythm: rhythm, pending: pending, calendar: calendar)
        }
    }

    /// Whether `start..<end` touches any night of the sleep schedule's hours.
    static func overlapsSleep(
        start: Date,
        end: Date,
        rhythm: MorningRhythm,
        pending: PendingBedtime?,
        calendar: Calendar
    ) -> Bool {
        let first = calendar.startOfDay(for: start)
        for offset in -1...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first),
                  let night = SleepRules.night(endingOnMorningOf: day, rhythm: rhythm, pending: pending, calendar: calendar)
            else { continue }
            if start < night.end && end > night.start { return true }
        }
        return false
    }

    /// The session after choosing `minutes`: waiting for the new ring, with
    /// the lock deadline moved to go with it.
    static func apply(_ minutes: Int, to session: GymSession, now: Date) -> GymSession {
        var updated = session
        let ring = now.addingTimeInterval(Double(minutes) * 60)
        updated.runningLateUsedAt = now
        updated.runningLateUntil = ring
        updated.state = .runningLate
        updated.lockDeadline = ShieldPolicy.deadline(forWindowMinutes: session.windowMinutes, from: ring)
        return updated
    }

    static func hasElapsed(_ session: GymSession, at now: Date) -> Bool {
        guard session.state == .runningLate else { return false }
        return session.runningLateUntil.map { now >= $0 } ?? true
    }
}

// MARK: - Phone off, alarm never rang

/// A planned gym day this week that passed with nothing at all: no session,
/// no outcome (FLOW, Flow 1 edge cases). Nothing is recorded; the skip
/// screen is offered once so a reschedule is on the table.
enum MissedDayCheck {
    /// The earliest such day, or nil.
    ///
    /// - Parameters:
    ///   - handledDays: Start-of-day dates that already have an outcome, a
    ///     session, or were offered before.
    ///   - notBefore: Days before this (the install) are never offered.
    static func unhandledGymDay(
        now: Date,
        plan: MorningPlan,
        handledDays: Set<Date>,
        notBefore: Date,
        calendar: Calendar
    ) -> Date? {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        guard let weekStart = weekCalendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }

        let gymDays = plan.enabledSlots.reduce(into: Set<Weekday>()) { $0.formUnion($1.days) }
        let floor = calendar.startOfDay(for: notBefore)
        let handled = Set(handledDays.map { calendar.startOfDay(for: $0) })

        var day = calendar.startOfDay(for: weekStart)
        while day <= now {
            if let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
               gymDays.contains(weekday),
               day >= floor,
               !handled.contains(day) {
                let rhythm = plan.rhythm(at: day, calendar: calendar)
                let time = rhythm.lockAlarmTime
                if let ring = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                   now >= ShieldPolicy.deadline(forWindowMinutes: rhythm.windowMinutes, from: ring) {
                    return day
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
    }
}
