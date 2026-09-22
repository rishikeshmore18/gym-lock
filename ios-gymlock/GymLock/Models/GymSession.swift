import Foundation

/// Every position a morning can be in, as one value.
///
/// The alternative — a scattering of booleans for fired, committed, departed,
/// extended, expired — is what makes flows like this rot. A single enum means
/// the UI is a pure function of where the user actually is, and an impossible
/// combination cannot be represented.
enum GymSessionState: String, Codable, Hashable {
    case idle
    case alarmScheduled
    case alarmFired
    case awaitingDecision
    /// The one snooze, running. The user is still in the flow and their apps
    /// are still locked — a snooze buys five minutes of sleep, not five
    /// minutes of scrolling.
    case snoozed
    case activationMission
    case preparing
    case departed
    /// The phone entered the gym region. Not success yet — the dwell check has
    /// to rule out driving past.
    case approachingGym
    /// Confirmed physical arrival. This is the success state: apps unlock here,
    /// and a workout is *not* required to reach it.
    case arrived
    /// The window closed without the user reaching the gym.
    case windowExpired
    /// Location could not be confirmed for technical reasons. Explicitly not
    /// the same as the user choosing not to go.
    case arrivalTrouble
    case quickWorkoutOffered
    case quickWorkoutActive
    case cantToday
    case rescheduled
    case homeWorkoutVerified
    case completed
    case missed

    /// States where the user is in the middle of a morning and the flow should
    /// take over the screen.
    var isLive: Bool {
        switch self {
        case .idle, .alarmScheduled, .completed, .missed, .rescheduled:
            false
        default:
            true
        }
    }

    /// True once the user has said they are going. From here the app stops
    /// escalating and starts supporting.
    var hasCommitted: Bool {
        switch self {
        case .idle, .alarmScheduled, .alarmFired, .awaitingDecision, .snoozed:
            false
        default:
            true
        }
    }

    /// True once this morning has an answer, one way or another.
    ///
    /// Drives the resolved-slot key: a day the user has already settled must
    /// never be restarted by the clock when they next open the app. Arrival and
    /// a completed home workout count, because being re-locked after earning
    /// your apps back would be the worst possible bug.
    var isResolved: Bool {
        switch self {
        case .completed, .missed, .rescheduled, .cantToday,
             .arrived, .homeWorkoutVerified:
            true
        default:
            false
        }
    }

    /// Whether the selected apps should be shielded in this state.
    ///
    /// The whole product exists for the moment another app wins, so the shield
    /// is on from the alarm right through the trip — and lifts the instant the
    /// user is confirmed at the gym, or resolves the day another way.
    var wantsShield: Bool {
        switch self {
        case .alarmFired, .awaitingDecision, .snoozed, .activationMission,
             .preparing, .departed, .approachingGym,
             .windowExpired, .quickWorkoutActive:
            true
        default:
            false
        }
    }
}

/// A geographic point captured for the duration of one session only.
///
/// Deliberately not called "home". GymLock needs to know whether the user has
/// meaningfully left wherever they started this morning — which may be a hotel,
/// a friend's sofa, or their own flat — and it forgets the moment the session
/// ends.
struct SessionAnchor: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var capturedAt: Date

    /// Radius, in metres, beyond which the user counts as having left.
    /// Deliberately generous: a large building or a poor GPS fix should not
    /// trigger a false departure.
    static let departureRadius: Double = 200
}

/// How a "can't today" was resolved.
enum CantTodayResolution: String, Codable, Hashable {
    case rescheduledWithin24h
    case quickWorkout
    case tookTheDayOff
}

/// One morning, from the alarm to whatever actually happened.
///
/// Persisted in full. If the app is killed mid-countdown, terminated by the
/// system, or the phone reboots, this is restored and the morning continues from
/// where it was rather than restarting.
struct GymSession: Codable, Hashable, Identifiable {
    var id: UUID
    /// Midnight of the day this session belongs to, so multiple sessions in one
    /// day can be told apart from the same session across a relaunch.
    var day: Date
    /// Which recurring alarm produced it.
    var slotID: UUID?

    var alarmTime: TimeOfDay
    var isMorningSession: Bool
    var getReadyMinutes: Int
    var travelMinutes: Int

    var state: GymSessionState

    var alarmFiredAt: Date?
    var committedAt: Date?

    /// Absolute moment the window closes.
    ///
    /// The countdown is derived from this and the wall clock, never from an
    /// accumulating in-memory timer. That is the only way a relaunch can show
    /// the correct remaining time instead of resetting to full.
    var deadline: Date?

    var mission: ActivationMissionType?
    var missionStartedAt: Date?
    var missionCompletedAt: Date?
    /// Which mirror phrase this attempt drew, so it is stable across a redraw.
    var mirrorPhraseIndex: Int

    /// Minutes of extension already granted. Only one extension is ever allowed.
    var extensionMinutesUsed: Int

    var anchor: SessionAnchor?
    var departedAt: Date?
    /// Which departure message was used, so the next gym day picks a different
    /// one.
    var departureMessageIndex: Int?
    /// True once the 75% nudge has been shown, so it only ever appears once.
    var hasShownPreparationNudge: Bool

    // MARK: Snooze

    /// When the single snooze was taken. Its presence is the whole rule: the
    /// button is not drawn a second time, so there is no counter to show and
    /// nothing to shame anybody with.
    var snoozeUsedAt: Date?
    /// When the snooze re-fires. Absolute, like the window deadline, so a
    /// relaunch or a suspended app resolves to the truth rather than restarting
    /// the five minutes.
    var snoozeExpiresAt: Date?
    /// Whether the plan offered a snooze when this alarm rang. Captured at
    /// the ring rather than read live, so flipping the setting mid-morning
    /// cannot make a button appear or vanish under someone's thumb. Optional
    /// so sessions saved before the setting existed still decode.
    var snoozeOffered: Bool?
    /// The snooze length the plan had when this alarm rang.
    var snoozeLengthMinutes: Int?

    var quickWorkoutMinutes: Int?
    var quickWorkoutStartedAt: Date?
    var quickWorkoutDeadline: Date?

    var cantTodayResolution: CantTodayResolution?

    // MARK: Arrival

    /// When the phone first entered the gym region. Entering is only a
    /// candidate; `arrivedAt` is the confirmed fact.
    var arrivalCandidateAt: Date?
    /// When arrival was actually confirmed, after the dwell check.
    var arrivedAt: Date?
    /// The single source of truth for "did they show up".
    var gymArrivalVerified: Bool
    /// Set when detection failed for technical reasons rather than because the
    /// user did not go. Never presented as a missed workout.
    var hadArrivalTrouble: Bool

    // MARK: Workout

    /// True when Apple Health independently recorded a workout for this
    /// session. Enrichment only — nothing depends on it.
    var workoutDetected: Bool
    var detectedWorkout: DetectedWorkout?

    // MARK: Shield

    /// Hard upper bound on the shield for this session.
    ///
    /// Belt and braces alongside the shield service's own failsafe. If anything
    /// at all goes wrong, apps come back.
    var shieldFailsafeDeadline: Date?
    /// True when the shield was lifted by the failsafe rather than by the user
    /// earning it. Recorded, never credited.
    var wasTechnicallyReleased: Bool

    // MARK: Rules

    /// The longest single extension the user may take.
    static let maximumExtensionMinutes = 15
    /// What the extension button offers by default.
    static let defaultExtensionMinutes = 10
    /// A short grace period after "still going" on an expired window. This is
    /// not a fresh timer.
    static let graceMinutes = 10
    /// The snooze length when the plan has not said otherwise. Short on
    /// purpose: long enough to be worth taking, too short to fall back asleep.
    static let snoozeMinutes = 5
    /// Fraction of the window at which the "still getting ready?" nudge appears.
    static let nudgeFraction: Double = 0.75

    init(
        id: UUID = UUID(),
        day: Date,
        slotID: UUID?,
        alarmTime: TimeOfDay,
        isMorningSession: Bool,
        getReadyMinutes: Int,
        travelMinutes: Int,
        state: GymSessionState = .alarmFired
    ) {
        self.id = id
        self.day = day
        self.slotID = slotID
        self.alarmTime = alarmTime
        self.isMorningSession = isMorningSession
        self.getReadyMinutes = getReadyMinutes
        self.travelMinutes = travelMinutes
        self.state = state
        alarmFiredAt = nil
        committedAt = nil
        deadline = nil
        mission = nil
        missionStartedAt = nil
        missionCompletedAt = nil
        mirrorPhraseIndex = Int.random(in: 0..<ActivationMissionType.mirrorPhrases.count)
        extensionMinutesUsed = 0
        anchor = nil
        departedAt = nil
        departureMessageIndex = nil
        hasShownPreparationNudge = false
        quickWorkoutMinutes = nil
        quickWorkoutStartedAt = nil
        quickWorkoutDeadline = nil
        cantTodayResolution = nil
        snoozeUsedAt = nil
        snoozeExpiresAt = nil
        arrivalCandidateAt = nil
        arrivedAt = nil
        gymArrivalVerified = false
        hadArrivalTrouble = false
        workoutDetected = false
        detectedWorkout = nil
        shieldFailsafeDeadline = nil
        wasTechnicallyReleased = false
    }

    // MARK: Derived

    /// Total window in minutes, including any extension already granted.
    var windowMinutes: Int {
        getReadyMinutes + travelMinutes + extensionMinutesUsed
    }

    var canExtend: Bool { extensionMinutesUsed == 0 }

    /// True once the single snooze has been spent, for the rest of this
    /// session. Drives both the missing button and the shorter copy.
    var hasSnoozed: Bool { snoozeUsedAt != nil }

    /// Whether this session's alarm offers a snooze at all.
    var offersSnooze: Bool { snoozeOffered ?? true }

    /// How long this session's snooze lasts.
    var snoozeDurationMinutes: Int { snoozeLengthMinutes ?? Self.snoozeMinutes }

    /// Seconds left of the snooze, from the wall clock.
    func snoozeRemaining(at now: Date = Date()) -> TimeInterval {
        guard let snoozeExpiresAt else { return 0 }
        return max(0, snoozeExpiresAt.timeIntervalSince(now))
    }

    /// True when a running snooze has elapsed and the alarm owes the user a
    /// second look at the decision.
    func snoozeHasElapsed(at now: Date = Date()) -> Bool {
        guard state == .snoozed, let snoozeExpiresAt else { return false }
        return now >= snoozeExpiresAt
    }

    /// Seconds left before the window closes, from the wall clock.
    func remaining(at now: Date = Date()) -> TimeInterval {
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// 0 at the start of the window, 1 when it closes.
    func elapsedFraction(at now: Date = Date()) -> Double {
        guard let deadline, let committedAt else { return 0 }
        let total = deadline.timeIntervalSince(committedAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(committedAt) / total))
    }

    var hasExpired: Bool {
        guard let deadline else { return false }
        return Date() >= deadline
    }

    /// The moment the user should be leaving, used by the timeline rail.
    var leaveMoment: Date? {
        guard let committedAt else { return nil }
        return committedAt.addingTimeInterval(Double(getReadyMinutes) * 60)
    }

    /// Which stage of get-ready → leave → arrive the user is in.
    func stage(at now: Date = Date()) -> PreparationStage {
        if departedAt != nil { return .arrive }
        guard let committedAt else { return .getReady }
        let elapsed = now.timeIntervalSince(committedAt) / 60
        if elapsed < Double(getReadyMinutes) { return .getReady }
        if elapsed < Double(getReadyMinutes + travelMinutes) { return .leave }
        return .arrive
    }

    var mirrorPhrase: String {
        let phrases = ActivationMissionType.mirrorPhrases
        return phrases[mirrorPhraseIndex % phrases.count]
    }

    /// How far through the dwell confirmation the candidate is, 0...1.
    func dwellProgress(at now: Date = Date()) -> Double {
        guard let arrivalCandidateAt else { return 0 }
        let elapsed = now.timeIntervalSince(arrivalCandidateAt)
        return min(1, max(0, elapsed / ArrivalTuning.dwellSeconds))
    }

    /// The window during which a Health workout is considered part of this
    /// session.
    ///
    /// Opens at arrival and runs well past it, because a workout sample is
    /// written when the workout *ends* — often an hour or more after the user
    /// walked in.
    var workoutMatchWindow: DateInterval? {
        guard let start = arrivedAt ?? quickWorkoutStartedAt ?? committedAt else { return nil }
        return DateInterval(
            start: start.addingTimeInterval(-15 * 60),
            end: start.addingTimeInterval(5 * 3600)
        )
    }
}

/// The three beats of the window, shown as a rail under the countdown.
enum PreparationStage: Int, CaseIterable, Identifiable {
    case getReady
    case leave
    case arrive

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .getReady: "get ready"
        case .leave: "leave"
        case .arrive: "arrive"
        }
    }

    var icon: String {
        switch self {
        case .getReady: "figure.walk"
        case .leave: "figure.walk.departure"
        case .arrive: "mappin.and.ellipse"
        }
    }
}
