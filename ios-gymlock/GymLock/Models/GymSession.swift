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
    case activationMission
    case preparing
    case departed
    case approachingGym
    case arrivedPendingWorkout
    /// The window closed without the user reaching the gym. Distinct from
    /// `quickWorkoutOffered` because expiry opens "plans changed?", which still
    /// offers going, and only *then* leads to the fallback picker.
    case windowExpired
    case quickWorkoutOffered
    case quickWorkoutActive
    case cantToday
    case rescheduled
    case gymWorkoutVerified
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
        case .idle, .alarmScheduled, .alarmFired, .awaitingDecision:
            false
        default:
            true
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

    var quickWorkoutMinutes: Int?
    var quickWorkoutStartedAt: Date?
    var quickWorkoutDeadline: Date?

    var cantTodayResolution: CantTodayResolution?

    /// Reserved for the location and workout verification that will land with
    /// the real gym flow. Nothing in the app fakes these.
    var locationVerified: Bool
    var workoutVerified: Bool

    // MARK: Rules

    /// The longest single extension the user may take.
    static let maximumExtensionMinutes = 15
    /// What the extension button offers by default.
    static let defaultExtensionMinutes = 10
    /// A short grace period after "still going" on an expired window. This is
    /// not a fresh timer.
    static let graceMinutes = 10
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
        locationVerified = false
        workoutVerified = false
    }

    // MARK: Derived

    /// Total window in minutes, including any extension already granted.
    var windowMinutes: Int {
        getReadyMinutes + travelMinutes + extensionMinutesUsed
    }

    var canExtend: Bool { extensionMinutesUsed == 0 }

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
