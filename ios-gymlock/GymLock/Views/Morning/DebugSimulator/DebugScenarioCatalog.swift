#if DEBUG
import Foundation

/// Every simulator scenario is still one `GymSessionCoordinator.DebugStep`.
/// This file only describes them for the Day Flow Simulator: it never runs
/// anything and never changes what a step does.
typealias SimStep = GymSessionCoordinator.DebugStep

// MARK: - Stages

/// The six parts of a day the simulator filters by. Picking a stage only
/// filters the list; it never runs a scenario.
enum SimStage: String, CaseIterable, Identifiable {
    case sleep, alarm, journey, arrival, workout, progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .alarm: "Alarm"
        case .journey: "Journey"
        case .arrival: "Arrival"
        case .workout: "Workout"
        case .progress: "Progress"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon.zzz"
        case .alarm: "alarm"
        case .journey: "figure.walk"
        case .arrival: "mappin.and.ellipse"
        case .workout: "dumbbell"
        case .progress: "chart.bar"
        }
    }

    /// The 3 to 5 scenarios shown as cards for this stage.
    var presets: [SimStep] {
        switch self {
        case .sleep: [.windDownLockStart, .windDownLockEnd, .changeBedtimeTonight, .bedtimeAfterMidnightGymMonday]
        case .alarm: [.wakeAndGoGymDay, .snoozedMorning, .goLaterGymDay, .ignoreAlarmUntilDeadline, .plainWakeAlarmRings]
        case .journey: [.missionComplete, .departed, .countdownAt75, .runningLate30]
        case .arrival: [.gymRegionEntered, .driveBy, .gymDwellConfirmed, .arrivalTrouble]
        case .workout: [.arriveStay20, .healthWorkout22, .quickWorkoutComplete, .imHereCameraPhoto]
        case .progress: [.exampleA, .cancelAReschedule, .atRiskThursday, .jumpTwoMonthsAfterJoining]
        }
    }
}

// MARK: - Day rule

/// Which day a scenario acts on. The simulator cannot move the device clock,
/// so a scenario either uses today, sets up its own day, or does not care.
enum SimDayRule: Equatable {
    /// Runs against the real clock, so it only makes sense with today selected.
    case today
    /// Sets up the current Monday-to-Sunday week and acts on this weekday.
    case thisWeek(Weekday)
    /// Last Sunday at 23:30, the day before this week's Monday.
    case lastSunday
    /// Checks the coming Monday at 01:00.
    case nextMonday
    /// The join date plus two months.
    case joinedPlusTwoMonths
    /// July 1 of the later of this year and the year after joining.
    case julyFirst
    /// December 31 of this year, rolled into January 1.
    case newYearsEve
    /// The day plays no part.
    case dayless

    /// The weekday the day row locks to, when there is one in this week.
    var lockedWeekday: Weekday? {
        if case let .thisWeek(day) = self { return day }
        return nil
    }

    var isDraftAdjustable: Bool { self == .today }
}

// MARK: - Time

/// What the time dial shows. Read-only: every scenario sets its own time.
enum SimTimeReading: Equatable {
    case fixed(TimeOfDay, note: String)
    /// The plan's lock alarm time.
    case planLockAlarm
    /// A moment this many minutes before now.
    case minutesAgo(Int, note: String)
    /// The plan's window plus this many minutes, before now.
    case afterWindow(extraMinutes: Int, note: String)
    case now(note: String)
    case notUsed
}

// MARK: - Journey

/// Where the distance ring sits after the scenario. Display only: nothing
/// here moves a real location.
enum SimJourney: Int, CaseIterable, Comparable {
    case notDeparted, onTheWay, nearGym, inRegion, confirmed

    static func < (lhs: SimJourney, rhs: SimJourney) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .notDeparted: "Not departed"
        case .onTheWay: "On the way"
        case .nearGym: "Near gym"
        case .inRegion: "In gym region"
        case .confirmed: "Arrival confirmed"
        }
    }

    /// No scenario stops at "near gym", so the ring never lands there.
    static let reachable: [SimJourney] = [.notDeparted, .onTheWay, .inRegion, .confirmed]
}

struct SimJourneyReading: Equatable {
    var state: SimJourney
    var verified: Bool
    var note: String
}

// MARK: - Time at gym

enum SimGymTime: Equatable {
    /// The one scenario whose stay length can be chosen.
    case adjustable
    case fixed(minutes: Int, note: String)
}

enum SimGymDial {
    /// The minimum stay the real proof rules use.
    static var mark: Int { WorkoutRules.minimumMinutes }
    /// The original `.arriveStay20` backdates by 21 minutes.
    static let originalMinutes = 21
    static let steps: [Int] = [0, 12, 19, 20, 21, 22, 30]
    static let range: ClosedRange<Int> = 0...30
}

// MARK: - Conditions

enum SimCondition: String, CaseIterable, Identifiable {
    case screenTime, health
    var id: String { rawValue }
}

enum SimPermissionChoice: String, CaseIterable, Identifiable {
    case asIs, granted, denied
    var id: String { rawValue }

    var title: String {
        switch self {
        case .asIs: "As is"
        case .granted: "Granted"
        case .denied: "Denied"
        }
    }
}

// MARK: - Result channel

/// The result line a scenario writes, read after the run.
enum SimResultChannel: CaseIterable {
    case notificationTaps, weekRules, sleep, alarmRules, gym, skips, freezes

    var title: String {
        switch self {
        case .notificationTaps: "tap result"
        case .weekRules: "week rules result"
        case .sleep: "sleep result"
        case .alarmRules: "alarm rules result"
        case .gym: "at the gym result"
        case .skips: "skips result"
        case .freezes: "freezes and at risk result"
        }
    }

    var value: String {
        get {
            switch self {
            case .notificationTaps: GymSessionCoordinator.debugNotificationTapResult
            case .weekRules: GymSessionCoordinator.debugWeekRulesResult
            case .sleep: GymSessionCoordinator.debugSleepResult
            case .alarmRules: GymSessionCoordinator.debugAlarmRulesResult
            case .gym: GymSessionCoordinator.debugGymResult
            case .skips: GymSessionCoordinator.debugSkipsResult
            case .freezes: GymSessionCoordinator.debugFreezeResult
            }
        }
        nonmutating set {
            switch self {
            case .notificationTaps: GymSessionCoordinator.debugNotificationTapResult = newValue
            case .weekRules: GymSessionCoordinator.debugWeekRulesResult = newValue
            case .sleep: GymSessionCoordinator.debugSleepResult = newValue
            case .alarmRules: GymSessionCoordinator.debugAlarmRulesResult = newValue
            case .gym: GymSessionCoordinator.debugGymResult = newValue
            case .skips: GymSessionCoordinator.debugSkipsResult = newValue
            case .freezes: GymSessionCoordinator.debugFreezeResult = newValue
            }
        }
    }
}

/// Live readings shown next to the result line.
enum SimReading: String, CaseIterable {
    case sessionState, showedUp, workoutDetected, handoff
    case shieldPermission, shieldActive, shieldOwner, windDown
    case gps, location, health
    case ringer, customSong
    case route, homeWorkouts, momentum
}

// MARK: - Scenario

struct SimScenario {
    let step: SimStep
    let summary: String
    let expected: String
    let stage: SimStage
    var day: SimDayRule = .today
    var time: SimTimeReading = .notUsed
    var journey: SimJourneyReading?
    var gymTime: SimGymTime?
    var conditions: Set<SimCondition> = []
    /// A note shown instead of a control, for conditions the scenario fixes.
    var fixedNotes: [String] = []
    var writesRealData = false

    var title: String { step.label }
    var section: String { step.section }
    var staysOpen: Bool { SimCatalog.staysOpen.contains(step) }
    var playsAfterClose: Bool { SimCatalog.playsAfterClose.contains(step) }
    var resultChannel: SimResultChannel? { SimCatalog.channel(for: step) }
}

enum SimCatalog {
    /// The original section shown as its own visible entry.
    static let calendarSection = "freezes and at risk"
    static let calendarTitle = "Calendar, Streaks & Freezes"
    static let calendarSteps: [SimStep] = [
        .jumpTwoMonthsAfterJoining, .jumpToJuly1, .newYearFreezesExpire,
        .planFreezeThisWeek, .atRiskThursday, .atRiskSunday, .atRiskHomeWorkoutsUsedUp,
    ]

    static func sectionTitle(_ section: String) -> String {
        section == calendarSection ? calendarTitle : section.prefix(1).uppercased() + section.dropFirst()
    }

    /// Copied from the original panel: these are judged by their readings,
    /// so the simulator stays open and shows a result.
    static let staysOpen: Set<SimStep> = [
        .familyControlsAuthorized, .familyControlsDenied,
        .badGPSAccuracy, .goodGPSAccuracy,
        .healthDenied, .noHealthWorkout, .driveBy,
        .foregroundAfterWindow, .foregroundAfterResolved,
        .windDownLockStart, .windDownLockEnd, .windDownWhileSessionLive,
        .tapArrivalAfterGym, .tapDepartureMidSession, .tapWindDownAtNight,
        .legacyUserTwoGymDays, .changePlanMidWeek,
        .sundayLateAlarmVisitAfterMidnight, .tryRemoveGymDayAtThree,
        .legacyEveningUser, .changeBedtimeTonight,
        .bedtimeAfterMidnightGymMonday, .oldPlanNightLockOff,
        .wakeAndGoGymDay, .goLaterGymDay, .plainWakeAlarmRings,
        .ignoreAlarmUntilDeadline, .runningLateNearBedtime,
        .runningLateTwice, .phoneWasOffOnGymDay,
        .arriveStay20, .arriveLeaveAt12, .stepOutThreeMinutes, .healthWorkout22,
        .handTypedWorkout, .unplannedVisit, .visitInSleepHours, .imHereCameraPhoto,
        .use3HomeWorkouts, .homeWorkoutNoHealthPhoto, .cancelAReschedule,
        .jumpTwoMonthsAfterJoining, .jumpToJuly1, .newYearFreezesExpire,
        .planFreezeThisWeek, .atRiskThursday, .atRiskSunday, .atRiskHomeWorkoutsUsedUp,
        .ringerStart, .ringerEscalated, .ringerStop, .ringerCeiling,
        .customSongMissing, .customSongProtected,
    ]

    /// Close instantly, then run, so the animation that follows is in view.
    static let playsAfterClose: Set<SimStep> = [.tapWorkoutDoneNotification]

    static var all: [SimScenario] { SimStep.allCases.map(scenario(for:)) }

    static func steps(inSection section: String) -> [SimStep] {
        SimStep.allCases.filter { $0.section == section }
    }

    static func steps(in stage: SimStage) -> [SimStep] {
        SimStep.allCases.filter { scenario(for: $0).stage == stage }
    }

    static func channel(for step: SimStep) -> SimResultChannel? {
        switch step.section {
        case "notification taps": .notificationTaps
        case "week rules": .weekRules
        case "sleep and night lock": .sleep
        case "alarm rules": .alarmRules
        case "at the gym": .gym
        case "skips": .skips
        case "freezes and at risk": .freezes
        default: nil
        }
    }

    static func readings(for step: SimStep) -> [SimReading] {
        switch step.section {
        case "flow", "doors", "fallbacks":
            [.sessionState, .showedUp, .shieldActive, .shieldOwner, .handoff]
        case "screen time":
            [.shieldPermission, .shieldActive, .shieldOwner, .sessionState]
        case "locks", "sleep and night lock":
            [.windDown, .shieldActive, .shieldOwner, .sessionState]
        case "arrival":
            [.sessionState, .showedUp, .gps, .location]
        case "health":
            [.health, .workoutDetected, .sessionState]
        case "notification taps":
            [.route, .sessionState, .handoff]
        case "week rules", "freezes and at risk":
            [.momentum, .sessionState]
        case "alarm rules":
            [.sessionState, .shieldActive, .handoff]
        case "at the gym":
            [.sessionState, .showedUp, .shieldActive]
        case "skips":
            [.sessionState, .homeWorkouts, .momentum]
        case "sound":
            [.ringer, .customSong]
        default:
            [.sessionState]
        }
    }

    /// Exhaustive on purpose: a new `DebugStep` does not compile until it is
    /// described here, so it can never be missing from the simulator.
    static func scenario(for step: SimStep) -> SimScenario {
        let st: Set<SimCondition> = [.screenTime]
        let hl: Set<SimCondition> = [.health]
        let shieldForced = "Screen Time is approved by the scenario itself."
        let notDeparted = SimJourneyReading(state: .notDeparted, verified: false, note: "Still at home.")

        switch step {
        // MARK: Flow
        case .alarmFired:
            return SimScenario(step: step, summary: "Starts a session from your first alarm slot, as if it just rang.",
                               expected: "Alarm screen appears and the gym lock goes on.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .snoozedMorning:
            return SimScenario(step: step, summary: "Rings a 06:30 Wake & Go alarm, then taps 5 more min.",
                               expected: "Session is snoozed with one snooze used.", stage: .alarm,
                               time: .fixed(TimeOfDay(hour: 6, minute: 30), note: "fixed by scenario"),
                               journey: notDeparted, conditions: st, fixedNotes: ["Flow: Wake & Go"])
        case .snoozeElapsed:
            return SimScenario(step: step, summary: "Lets the snooze run out without waiting 5 minutes.",
                               expected: "Alarm rings again; no second snooze is offered.", stage: .alarm,
                               time: .fixed(TimeOfDay(hour: 6, minute: 30), note: "fixed by scenario"),
                               journey: notDeparted, conditions: st, fixedNotes: ["Flow: Wake & Go"])
        case .alarmFiredEvening:
            return SimScenario(step: step, summary: "Same alarm moved to 18:00 as a Go Later session.",
                               expected: "Evening wording, no snooze button.", stage: .alarm,
                               time: .fixed(TimeOfDay(hour: 18, minute: 0), note: "fixed by scenario"),
                               journey: notDeparted, conditions: st, fixedNotes: ["Flow: Go Later"])
        case .imGoing:
            return SimScenario(step: step, summary: "Taps I'm going on the alarm screen.",
                               expected: "Activation mission opens.", stage: .journey,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .missionComplete:
            return SimScenario(step: step, summary: "Finishes the activation mission.",
                               expected: "Preparation countdown starts; apps stay locked.", stage: .journey,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .departed:
            return SimScenario(step: step, summary: "Marks you as left home.",
                               expected: "Departed screen; still locked until arrival.", stage: .journey,
                               time: .planLockAlarm,
                               journey: SimJourneyReading(state: .onTheWay, verified: false, note: "Left home, not at the gym."),
                               conditions: st)
        case .countdownAt75:
            return SimScenario(step: step, summary: "Moves the preparation countdown to 75 percent used.",
                               expected: "The preparation nudge appears once.", stage: .journey,
                               time: .now(note: "relative to now"), journey: notDeparted, conditions: st)
        case .countdownExpired:
            return SimScenario(step: step, summary: "Moves the preparation deadline into the past.",
                               expected: "Window expires and the expiry path runs.", stage: .journey,
                               time: .now(note: "relative to now"), journey: notDeparted, conditions: st)

        // MARK: Screen Time
        case .familyControlsAuthorized:
            return SimScenario(step: step, summary: "Sets Screen Time permission to approved.",
                               expected: "Shield permission reads approved; blocked apps configured.", stage: .journey,
                               day: .dayless, fixedNotes: ["Sets Screen Time to approved."])
        case .familyControlsDenied:
            return SimScenario(step: step, summary: "Sets Screen Time permission to denied.",
                               expected: "Shield permission reads denied.", stage: .journey,
                               day: .dayless, fixedNotes: ["Sets Screen Time to denied."])
        case .shieldApplied:
            return SimScenario(step: step, summary: "Applies the gym shield to the current session.",
                               expected: "Shield active, owned by the gym session.", stage: .journey,
                               time: .planLockAlarm, conditions: st)
        case .shieldRemoved:
            return SimScenario(step: step, summary: "Releases the shield.",
                               expected: "Shield inactive, no owner.", stage: .journey, day: .dayless)
        case .technicalRelease:
            return SimScenario(step: step, summary: "Backdates the failsafe so the real safety release runs.",
                               expected: "Shield lifts by the failsafe.", stage: .journey,
                               time: .now(note: "relative to now"), conditions: st)

        // MARK: Arrival
        case .gymRegionEntered:
            return SimScenario(step: step, summary: "Enters the gym area after leaving home.",
                               expected: "Approaching gym; arrival is not yet confirmed.", stage: .arrival,
                               journey: SimJourneyReading(state: .inRegion, verified: false, note: "In the area, dwell not done."))
        case .badGPSAccuracy:
            return SimScenario(step: step, summary: "Sets the GPS accuracy reading to 480 m.",
                               expected: "GPS accuracy reads 480 m. Reading only; no decision changes.", stage: .arrival,
                               day: .dayless)
        case .goodGPSAccuracy:
            return SimScenario(step: step, summary: "Sets the GPS accuracy reading to 12 m.",
                               expected: "GPS accuracy reads 12 m. Reading only; no decision changes.", stage: .arrival,
                               day: .dayless)
        case .driveBy:
            return SimScenario(step: step, summary: "Enters the gym area and leaves before the dwell completes.",
                               expected: "Nothing unlocks; showed up stays no.", stage: .arrival,
                               journey: SimJourneyReading(state: .onTheWay, verified: false, note: "Entered then left, not verified."))
        case .gymDwellConfirmed:
            return SimScenario(step: step, summary: "Confirms the arrival after the dwell.",
                               expected: "Arrival screen; apps unlock; showed up yes.", stage: .arrival,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "Dwell confirmed."),
                               conditions: hl)
        case .arrivalTrouble:
            return SimScenario(step: step, summary: "In the area, but the arrival cannot be confirmed.",
                               expected: "Arrival trouble screen with manual options.", stage: .arrival,
                               journey: SimJourneyReading(state: .inRegion, verified: false, note: "In the area, could not confirm."))

        // MARK: Health
        case .healthWorkoutDetected:
            return SimScenario(step: step, summary: "Grants Health and emits a strength workout.",
                               expected: "Workout detected on the session.", stage: .workout,
                               fixedNotes: ["Sets Health to authorized."])
        case .noHealthWorkout:
            return SimScenario(step: step, summary: "Clears any detected workout from the live session.",
                               expected: "Workout detected reads no. Needs a live session.", stage: .workout)
        case .healthDenied:
            return SimScenario(step: step, summary: "Sets Health access to denied.",
                               expected: "Health reads denied.", stage: .workout, day: .dayless,
                               fixedNotes: ["Sets Health to denied."])

        // MARK: Fallbacks
        case .quickWorkoutComplete:
            return SimScenario(step: step, summary: "Starts and finishes the quick home workout.",
                               expected: "Home workout recorded for today.", stage: .workout,
                               time: .now(note: "relative to now"),
                               gymTime: .fixed(minutes: 0, note: "Home workout, not at the gym"),
                               conditions: hl, writesRealData: true)

        // MARK: Doors
        case .alarmKitButtonTapped:
            return SimScenario(step: step, summary: "Writes the handoff the AlarmKit I'm up button writes.",
                               expected: "Session starts from the handoff, not snoozed.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .alarmKitSnoozeTapped:
            return SimScenario(step: step, summary: "Writes the handoff the AlarmKit snooze button writes.",
                               expected: "Session starts snoozed.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .notificationActionImUp:
            return SimScenario(step: step, summary: "Notification action I'm up.",
                               expected: "Session starts from the handoff, not snoozed.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .notificationActionSnooze:
            return SimScenario(step: step, summary: "Notification action 5 more min.",
                               expected: "Session starts snoozed.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .notificationTapped:
            return SimScenario(step: step, summary: "Taps the alarm notification body.",
                               expected: "Session starts from the handoff.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .notificationDismissed:
            return SimScenario(step: step, summary: "Swipes the alarm notification away.",
                               expected: "Session still starts and the lock still goes on.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st)
        case .coldLaunchFromAlarm:
            return SimScenario(step: step, summary: "Launch from a killed app with a handoff waiting.",
                               expected: "Session picked up by attach alone.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st,
                               fixedNotes: ["App: closed, then launched"])
        case .foregroundDuringWindow:
            return SimScenario(step: step, summary: "Alarm rang 5 min ago with no handoff; app comes forward.",
                               expected: "The clock alone starts the session.", stage: .alarm,
                               time: .minutesAgo(5, note: "relative to now"), journey: notDeparted, conditions: st,
                               fixedNotes: ["App: comes to the foreground"])
        case .foregroundAfterWindow:
            return SimScenario(step: step, summary: "App comes forward after the window plus grace.",
                               expected: "Nothing happens; no session starts.", stage: .alarm,
                               time: .afterWindow(extraMinutes: SessionResume.resumeGrace + 5, note: "window + grace + 5 min ago"),
                               journey: notDeparted,
                               fixedNotes: ["App: comes to the foreground"])
        case .foregroundAfterResolved:
            return SimScenario(step: step, summary: "Today's slot is already resolved; app comes forward.",
                               expected: "Nothing happens; no session starts.", stage: .alarm,
                               time: .minutesAgo(5, note: "relative to now"), journey: notDeparted,
                               fixedNotes: ["App: comes to the foreground"])
        case .alarmFiredWhileAppOpen:
            return SimScenario(step: step, summary: "Alarm fires while the app is frontmost.",
                               expected: "The posted notification starts the session.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted, conditions: st,
                               fixedNotes: ["App: open"])

        // MARK: Locks
        case .windDownLockStart:
            return SimScenario(step: step, summary: "Opens a night window around now and reconciles.",
                               expected: "Wind-down active; shield owned by wind-down.", stage: .sleep,
                               time: .now(note: "window opened 30 min ago"), fixedNotes: [shieldForced])
        case .windDownLockEnd:
            return SimScenario(step: step, summary: "Ends the night window a minute ago and reconciles.",
                               expected: "Shield lifts by the clock; wind-down inactive.", stage: .sleep,
                               time: .now(note: "window ended 1 min ago"), fixedNotes: [shieldForced])
        case .windDownHandoverToGym:
            return SimScenario(step: step, summary: "Gym alarm fires while the night lock holds the shield.",
                               expected: "Shield never off; owner becomes the gym session.", stage: .sleep,
                               time: .now(note: "relative to now"), journey: notDeparted, fixedNotes: [shieldForced])
        case .windDownWhileSessionLive:
            return SimScenario(step: step, summary: "Night window opens around a live session.",
                               expected: "Nothing changes; owner stays the gym session.", stage: .sleep,
                               time: .now(note: "relative to now"), conditions: st)

        // MARK: Notification taps
        case .tapArrivalAfterGym:
            return SimScenario(step: step, summary: "Taps the arrival notification during and after the visit.",
                               expected: "No handoff written; no second session.", stage: .arrival,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "Arrived, then closed."))
        case .tapDepartureMidSession:
            return SimScenario(step: step, summary: "Taps the departure notification mid-session, then finishes.",
                               expected: "No handoff; no second session after closing.", stage: .journey,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "Departed, arrived, closed."))
        case .tapWindDownAtNight:
            return SimScenario(step: step, summary: "Taps the wind-down notification at night.",
                               expected: "No handoff; no session starts.", stage: .sleep)
        case .tapAlarmNotification:
            return SimScenario(step: step, summary: "Taps the gym alarm notification.",
                               expected: "Handoff written; session starts.", stage: .alarm,
                               time: .planLockAlarm, journey: notDeparted)

        // MARK: Week rules
        case .legacyUserTwoGymDays:
            return SimScenario(step: step, summary: "Turns your plan into a legacy two-gym-day plan.",
                               expected: "Goal reading plus the 3-day rule start; reopen the app for the sheet.",
                               stage: .progress, day: .dayless, writesRealData: true)
        case .changePlanMidWeek:
            return SimScenario(step: step, summary: "Switches gym days 3, 5, then 3 mid-week.",
                               expected: "This week's goal is unchanged.", stage: .progress, writesRealData: true)
        case .sundayLateAlarmVisitAfterMidnight:
            return SimScenario(step: step, summary: "Alarm rang last Sunday 23:30, arrival confirmed now.",
                               expected: "Counts on Sunday, in Sunday's week.", stage: .progress, day: .lastSunday,
                               time: .fixed(TimeOfDay(hour: 23, minute: 30), note: "fixed by scenario"),
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "Confirmed after midnight."),
                               writesRealData: true)
        case .tryRemoveGymDayAtThree:
            return SimScenario(step: step, summary: "Sets Mon, Wed, Fri, then tries to remove Monday.",
                               expected: "Refused with the minimum gym days message; Monday stays on.",
                               stage: .progress, day: .dayless, writesRealData: true)

        // MARK: Sleep and night lock
        case .legacyEveningUser:
            return SimScenario(step: step, summary: "An after-work plan whose wake time copied the 17:15 alarm.",
                               expected: "Migration result line; reopen the app for the wake time question.",
                               stage: .sleep, day: .dayless,
                               time: .fixed(TimeOfDay(hour: 17, minute: 15), note: "fixed by scenario"),
                               writesRealData: true)
        case .changeBedtimeTonight:
            return SimScenario(step: step, summary: "Sleep 23:00 to 07:00, then bedtime moved to 03:00.",
                               expected: "Tonight still locks at 23:00; 03:00 starts tomorrow night.", stage: .sleep,
                               time: .fixed(TimeOfDay(hour: 23, minute: 0), note: "fixed by scenario"),
                               writesRealData: true)
        case .bedtimeAfterMidnightGymMonday:
            return SimScenario(step: step, summary: "Sleep 00:30 to 08:30 with every sleep day switched off.",
                               expected: "Monday 01:00 still locked because Monday is a gym day.", stage: .sleep,
                               day: .nextMonday,
                               time: .fixed(TimeOfDay(hour: 0, minute: 30), note: "fixed by scenario"),
                               writesRealData: true)
        case .oldPlanNightLockOff:
            return SimScenario(step: step, summary: "The old night lock switch is off during an open night.",
                               expected: "Night lock on anyway; apps locked.", stage: .sleep,
                               time: .now(note: "window opened 30 min ago"), fixedNotes: [shieldForced],
                               writesRealData: true)

        // MARK: Alarm rules
        case .wakeAndGoGymDay:
            return SimScenario(step: step, summary: "Wake 06:30, gym 07:05, 35 min gap.",
                               expected: "Wake & Go; the wake alarm is the gym alarm; snooze yes.", stage: .alarm,
                               time: .fixed(TimeOfDay(hour: 6, minute: 30), note: "fixed by scenario"),
                               journey: notDeparted, conditions: st, fixedNotes: ["Flow: Wake & Go"],
                               writesRealData: true)
        case .goLaterGymDay:
            return SimScenario(step: step, summary: "Wake 07:00, gym 18:00, 30 min to get there.",
                               expected: "Go Later; time to go 17:30; no snooze.", stage: .alarm,
                               time: .fixed(TimeOfDay(hour: 17, minute: 30), note: "fixed by scenario"),
                               journey: notDeparted, conditions: st, fixedNotes: ["Flow: Go Later"],
                               writesRealData: true)
        case .plainWakeAlarmRings:
            return SimScenario(step: step, summary: "The plain wake alarm through every door.",
                               expected: "No handoff; no session starts.", stage: .alarm, day: .dayless)
        case .ignoreAlarmUntilDeadline:
            return SimScenario(step: step, summary: "Alarm rang long ago and was never answered.",
                               expected: "Ends as missed; apps unlocked; slot resolved.", stage: .alarm,
                               time: .afterWindow(extraMinutes: 91, note: "window + 91 min ago"), journey: notDeparted,
                               fixedNotes: [shieldForced], writesRealData: true)
        case .runningLate30:
            return SimScenario(step: step, summary: "Go Later session now, running late by 30 min.",
                               expected: "Running late; the alarm rings again later; apps locked.", stage: .journey,
                               time: .now(note: "relative to now"), journey: notDeparted, conditions: st,
                               fixedNotes: ["Flow: Go Later"])
        case .runningLateNearBedtime:
            return SimScenario(step: step, summary: "Bedtime 2 hours away when running late.",
                               expected: "+15 and +30 offered; +60 not.", stage: .journey,
                               time: .now(note: "bedtime in 2 hours"), journey: notDeparted,
                               fixedNotes: ["Flow: Go Later"])
        case .runningLateTwice:
            return SimScenario(step: step, summary: "Running late once, the alarm rings again, then a second try.",
                               expected: "Button gone after the first; second try refused.", stage: .journey,
                               time: .now(note: "relative to now"), journey: notDeparted,
                               fixedNotes: ["Flow: Go Later"])
        case .phoneWasOffOnGymDay:
            return SimScenario(step: step, summary: "Today's alarm never rang; the lock would have lifted.",
                               expected: "Skip screen offered once; nothing recorded.", stage: .alarm,
                               time: .minutesAgo(180, note: "alarm 3 hours ago"), writesRealData: true)

        // MARK: At the gym
        case .arriveStay20:
            return SimScenario(step: step, summary: "Backdates an arrival and stays with no exit.",
                               expected: "Counts only at 20 min or more; the rules decide.", stage: .workout,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "At the gym."),
                               gymTime: .adjustable, conditions: hl, writesRealData: true)
        case .arriveLeaveAt12:
            return SimScenario(step: step, summary: "Arrives, leaves after 12 minutes.",
                               expected: "Does not count; short visit notice.", stage: .workout,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "Arrived, then left."),
                               gymTime: .fixed(minutes: 12, note: "left at 12 min"), conditions: hl, writesRealData: true)
        case .stepOutThreeMinutes:
            return SimScenario(step: step, summary: "25 minute visit, out from minute 10 to 13.",
                               expected: "A 3 minute step out does not break the visit.", stage: .workout,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "Stepped out, came back."),
                               gymTime: .fixed(minutes: 25, note: "out 10 to 13 min"), conditions: hl, writesRealData: true)
        case .healthWorkout22:
            return SimScenario(step: step, summary: "8 minutes at the gym plus a 22 minute watch workout.",
                               expected: "Counts by the Health workout.", stage: .workout,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "At the gym."),
                               gymTime: .fixed(minutes: 8, note: "+ 22 min in Health"), writesRealData: true)
        case .handTypedWorkout:
            return SimScenario(step: step, summary: "8 minutes at the gym plus a 45 minute hand-typed workout.",
                               expected: "Result line shows whether a typed workout counts.", stage: .workout,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "At the gym."),
                               gymTime: .fixed(minutes: 8, note: "+ 45 min typed"), writesRealData: true)
        case .unplannedVisit:
            return SimScenario(step: step, summary: "A 21 minute visit with no alarm running.",
                               expected: "Counts on the arrival day, planned or not.", stage: .workout,
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "No alarm."),
                               gymTime: .fixed(minutes: 21, note: "no alarm"), conditions: hl, writesRealData: true)
        case .visitInSleepHours:
            return SimScenario(step: step, summary: "A sleep window open now, then a 21 minute visit inside it.",
                               expected: "Night lock stays on; result line says whether it counts.", stage: .workout,
                               time: .now(note: "inside sleep hours"),
                               journey: SimJourneyReading(state: .confirmed, verified: true, note: "During sleep hours."),
                               gymTime: .fixed(minutes: 21, note: "in sleep hours"), fixedNotes: [shieldForced],
                               writesRealData: true)
        case .imHereCameraPhoto:
            return SimScenario(step: step, summary: "Taps I'm here 5 min ago, then a library and a camera photo.",
                               expected: "Library photo ignored; camera photo decides.", stage: .workout,
                               journey: SimJourneyReading(state: .inRegion, verified: false, note: "Manual I'm here."),
                               gymTime: .fixed(minutes: 5, note: "time does not count"), writesRealData: true)
        case .tapWorkoutDoneNotification:
            return SimScenario(step: step, summary: "Taps the workout-done notification.",
                               expected: "Closes, lands on Progress; no session starts.", stage: .workout,
                               day: .dayless, fixedNotes: ["Closes the simulator first, then runs."])

        // MARK: Skips
        case .exampleA:
            return SimScenario(step: step, summary: "Mon done, slept through Wednesday.",
                               expected: "Skip screen opens for Wednesday.", stage: .progress,
                               day: .thisWeek(.wednesday), writesRealData: true)
        case .exampleB:
            return SimScenario(step: step, summary: "Mon to Fri plan, Mon done, can't today on Tuesday.",
                               expected: "Skip screen opens for Tuesday.", stage: .progress,
                               day: .thisWeek(.tuesday), writesRealData: true)
        case .exampleC:
            return SimScenario(step: step, summary: "Mon and Tue skipped, slept through Wednesday.",
                               expected: "Skip screen opens for Wednesday.", stage: .progress,
                               day: .thisWeek(.wednesday), writesRealData: true)
        case .exampleD:
            return SimScenario(step: step, summary: "No watch, home workout on Wednesday.",
                               expected: "Skip screen opens for Wednesday.", stage: .progress,
                               day: .thisWeek(.wednesday), writesRealData: true)
        case .use3HomeWorkouts:
            return SimScenario(step: step, summary: "Uses up this month's home workouts.",
                               expected: "Picker greyed out at the monthly limit.", stage: .workout,
                               writesRealData: true)
        case .homeWorkoutNoHealthPhoto:
            return SimScenario(step: step, summary: "Home workout with no Health workout, then a camera photo.",
                               expected: "The photo is what counts it.", stage: .workout,
                               time: .now(note: "timer started 30 min ago"),
                               gymTime: .fixed(minutes: 0, note: "Home workout, not at the gym"), writesRealData: true)
        case .cancelAReschedule:
            return SimScenario(step: step, summary: "Reschedules today to tomorrow, then cancels it.",
                               expected: "Alarm gone; outcome recorded for today.", stage: .progress,
                               writesRealData: true)
        case .skipOnSunday:
            return SimScenario(step: step, summary: "Mon, Wed, Fri plan, skip screen on Sunday.",
                               expected: "Skip screen opens for Sunday.", stage: .progress,
                               day: .thisWeek(.sunday), writesRealData: true)

        // MARK: Freezes and at risk
        case .jumpTwoMonthsAfterJoining:
            return SimScenario(step: step, summary: "Runs the freeze calendar across the 2 months after joining date.",
                               expected: "First freeze granted, unless 2 months lands next year.", stage: .progress,
                               day: .joinedPlusTwoMonths, writesRealData: true)
        case .jumpToJuly1:
            return SimScenario(step: step, summary: "Runs the freeze calendar across July 1, holding one.",
                               expected: "July 1 freeze granted.", stage: .progress,
                               day: .julyFirst, writesRealData: true)
        case .newYearFreezesExpire:
            return SimScenario(step: step, summary: "Holds 2 freezes on Dec 31, then rolls into Jan 1.",
                               expected: "0 freezes held on Jan 1.", stage: .progress,
                               day: .newYearsEve, writesRealData: true)
        case .planFreezeThisWeek:
            return SimScenario(step: step, summary: "Arms a freeze for the current week.",
                               expected: "No gym alarms this week; back from Monday; wake alarms on.", stage: .progress,
                               writesRealData: true)
        case .atRiskThursday:
            return SimScenario(step: step, summary: "One session by Thursday morning.",
                               expected: "At-risk banner reading for Thursday.", stage: .progress,
                               day: .thisWeek(.thursday),
                               time: .fixed(TimeOfDay(hour: 9, minute: 0), note: "fixed by scenario"), writesRealData: true)
        case .atRiskSunday:
            return SimScenario(step: step, summary: "Two sessions by Sunday morning.",
                               expected: "At-risk banner reading for Sunday.", stage: .progress,
                               day: .thisWeek(.sunday),
                               time: .fixed(TimeOfDay(hour: 9, minute: 0), note: "fixed by scenario"), writesRealData: true)
        case .atRiskHomeWorkoutsUsedUp:
            return SimScenario(step: step, summary: "One session by Thursday with home workouts used up.",
                               expected: "At-risk reading without the home workout option.", stage: .progress,
                               day: .thisWeek(.thursday),
                               time: .fixed(TimeOfDay(hour: 9, minute: 0), note: "fixed by scenario"), writesRealData: true)

        // MARK: Sound
        case .ringerStart:
            return SimScenario(step: step, summary: "Starts the in-app ringer with your chosen sound.",
                               expected: "Ringer ringing at its starting volume.", stage: .alarm, day: .dayless)
        case .ringerEscalated:
            return SimScenario(step: step, summary: "Escalates the ringer to full volume.",
                               expected: "Ringer at 100 percent.", stage: .alarm, day: .dayless)
        case .ringerStop:
            return SimScenario(step: step, summary: "Stops the ringer.",
                               expected: "Ringer idle.", stage: .alarm, day: .dayless)
        case .ringerCeiling:
            return SimScenario(step: step, summary: "Runs what the 10 minute ring ceiling runs.",
                               expected: "Ringer idle; a technical release event logged.", stage: .alarm, day: .dayless)
        case .customSongMissing:
            return SimScenario(step: step, summary: "Deletes your exported song clip and rings.",
                               expected: "A fallback sound rings, never silence.", stage: .alarm, day: .dayless,
                               writesRealData: true)
        case .customSongProtected:
            return SimScenario(step: step, summary: "A chosen song with no file behind it.",
                               expected: "The ringer survives and rings a fallback.", stage: .alarm, day: .dayless,
                               writesRealData: true)
        }
    }

    // MARK: - Dates

    /// The Monday that starts the week containing `now`.
    static func weekStart(containing now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    /// Monday to Sunday of the current week.
    static let weekOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    static func date(of weekday: Weekday, inWeekOf now: Date, calendar: Calendar) -> Date {
        let monday = weekStart(containing: now, calendar: calendar)
        let index = weekOrder.firstIndex(of: weekday) ?? 0
        return calendar.date(byAdding: .day, value: index, to: monday) ?? monday
    }

    /// The real date a scenario acts on, when it is not simply today.
    static func resolvedDate(for rule: SimDayRule, joinedAt: Date, now: Date, calendar: Calendar) -> Date? {
        switch rule {
        case .today:
            return calendar.startOfDay(for: now)
        case let .thisWeek(day):
            return date(of: day, inWeekOf: now, calendar: calendar)
        case .lastSunday:
            let monday = weekStart(containing: now, calendar: calendar)
            return calendar.date(byAdding: .day, value: -1, to: monday)
        case .nextMonday:
            return calendar.nextDate(after: now, matching: DateComponents(hour: 1, minute: 0, weekday: Weekday.monday.rawValue),
                                     matchingPolicy: .nextTime)
        case .joinedPlusTwoMonths:
            return calendar.date(byAdding: .month, value: 2, to: calendar.startOfDay(for: joinedAt))
        case .julyFirst:
            let year = max(calendar.component(.year, from: now), calendar.component(.year, from: joinedAt) + 1)
            return calendar.date(from: DateComponents(year: year, month: 7, day: 1))
        case .newYearsEve:
            return calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 12, day: 31))
        case .dayless:
            return nil
        }
    }

    static func dayRuleNote(_ rule: SimDayRule) -> String {
        switch rule {
        case .today: "Uses the real clock, so it runs on today."
        case let .thisWeek(day): "Sets up this week and acts on \(day.shortLabel)."
        case .lastSunday: "Acts on last Sunday at 23:30."
        case .nextMonday: "Checks the coming Monday at 01:00."
        case .joinedPlusTwoMonths: "Two months after your join date."
        case .julyFirst: "July 1 of this year, or the year after joining."
        case .newYearsEve: "Dec 31 rolling into Jan 1."
        case .dayless: "The day plays no part in this test."
        }
    }
}
#endif
