import Foundation

// MARK: - Answer types

/// When the user's plan usually falls apart.
enum FailureWindow: String, CaseIterable, Codable, Identifiable, Hashable {
    case beforeWork
    case afterWork
    case evening
    case itChanges
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .beforeWork: "before work / school"
        case .afterWork: "after work / school"
        case .evening: "evening"
        case .itChanges: "it changes"
        case .other: "something else"
        }
    }

    /// Short form used in the summary and timeline screens.
    var shortLabel: String {
        switch self {
        case .beforeWork: "before work"
        case .afterWork: "after work"
        case .evening: "evening"
        case .itChanges: "varies"
        case .other: "your own window"
        }
    }

    /// A sensible default failure time for this window, used to pre-position the
    /// time wheel so the user usually only has to nudge it.
    var suggestedTime: TimeOfDay {
        switch self {
        case .beforeWork: TimeOfDay(hour: 6, minute: 30)
        case .afterWork: TimeOfDay(hour: 17, minute: 30)
        case .evening: TimeOfDay(hour: 19, minute: 30)
        case .itChanges, .other: TimeOfDay(hour: 17, minute: 30)
        }
    }
}

/// What usually wins in the moment the workout was planned.
enum FailureReason: String, CaseIterable, Codable, Identifiable, Hashable {
    case scrolling
    case snooze
    case laterToday
    case exhausted
    case scheduleChanges
    case somethingElse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scrolling: "i start scrolling"
        case .snooze: "i snooze the alarm"
        case .laterToday: "i tell myself i'll go later"
        case .exhausted: "i'm exhausted"
        case .scheduleChanges: "my schedule changes"
        case .somethingElse: "something else"
        }
    }

    var icon: String {
        switch self {
        case .scrolling: "iphone"
        case .snooze: "alarm"
        case .laterToday: "clock.arrow.circlepath"
        case .exhausted: "battery.25"
        case .scheduleChanges: "calendar.badge.exclamationmark"
        case .somethingElse: "ellipsis"
        }
    }
}

/// The apps that usually take the time instead.
enum DistractingApp: String, CaseIterable, Codable, Identifiable, Hashable {
    case instagram
    case tiktok
    case youtube
    case reddit
    case x
    case snapchat
    case games
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .reddit: "Reddit"
        case .x: "X"
        case .snapchat: "Snapchat"
        case .games: "Games"
        case .other: "Other"
        }
    }

    /// Display order. `other` deliberately sits last, after `games`.
    static let displayOrder: [DistractingApp] = [
        .instagram, .tiktok, .youtube, .reddit, .x, .snapchat, .games, .other,
    ]
}

/// How often the scroll follows the user to bed.
enum NightScrollingFrequency: String, CaseIterable, Codable, Identifiable, Hashable {
    case almostEveryNight
    case fewNights
    case notReally

    var id: String { rawValue }

    var label: String {
        switch self {
        case .almostEveryNight: "almost every night"
        case .fewNights: "a few nights a week"
        case .notReally: "not really"
        }
    }

    /// Whether this answer justifies asking for a bedtime.
    var wantsBedtime: Bool { self != .notReally }
}

/// The bundled alarm tracks.
///
/// These are real audio files shipped with the app. The app deliberately does
/// not claim access to the user's streaming library, because it has none.
enum AlarmSound: String, CaseIterable, Codable, Identifiable, Hashable {
    case energyUp
    case beastMode
    case focusTime
    case noLimits
    case ownSong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .energyUp: "Energy Up"
        case .beastMode: "Beast Mode"
        case .focusTime: "Focus Time"
        case .noLimits: "No Limits"
        case .ownSong: "my own song"
        }
    }

    var subtitle: String {
        switch self {
        case .energyUp: "bright · builds fast"
        case .beastMode: "heavy · no negotiating"
        case .focusTime: "calm · but awake"
        case .noLimits: "anthemic · full send"
        case .ownSong: "pick a track from your library"
        }
    }

    /// Bundled resource name, or nil for the user's own imported track.
    ///
    /// These are the file names as bundled into `Resources/`, which do not match
    /// the display names above. Each one ships twice, in two formats, for two
    /// very different players — see `ringerFileName` and `notificationFileName`.
    var resourceName: String? {
        switch self {
        case .energyUp: "gym_workout_alarm"
        case .beastMode: "aggressive_gym_hype"
        case .focusTime: "calm_morning_alarm_loop"
        case .noLimits: "triumphant_rock_workout"
        case .ownSong: nil
        }
    }

    /// What `AVAudioPlayer` plays: the in-app preview and the real ringer.
    ///
    /// mp3 is fine here. `AVAudioPlayer` decodes it, and stereo at 128 kbps is
    /// what these tracks were authored at.
    var ringerFileName: String? {
        guard let resourceName else { return nil }
        return "\(resourceName).mp3"
    }

    /// What a notification plays, which is a different file on purpose.
    ///
    /// The system sound facility cannot decode mp3. It accepts only Linear PCM,
    /// IMA4, µLaw or aLaw packaged as aiff, wav or caf, and silently substitutes
    /// the default system sound for anything else — so every "custom" alarm tone
    /// this app shipped through the notification backend was never actually
    /// heard. These are IMA4 in caf for exactly that reason.
    var notificationFileName: String? {
        guard let resourceName else { return nil }
        return "\(resourceName).caf"
    }

    /// The four tracks that ship with the app.
    static let bundled: [AlarmSound] = [.energyUp, .beastMode, .focusTime, .noLimits]
}

/// A Day 0 capture stored on this device only.
struct Day0Media: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case photo
        case video
    }

    var kind: Kind
    /// File name inside the app's Documents directory. Only the name is stored,
    /// because the container path changes between launches and updates.
    var fileName: String
    var capturedAt: Date

    var fileURL: URL? {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return documents.appendingPathComponent(fileName)
    }
}

// MARK: - The profile

/// Everything the user tells GymLock during onboarding.
///
/// Later screens are written entirely against these values — the "aha", the
/// timeline, the summary, and the activation checklist all read from here, so a
/// user who answered honestly never sees a generic placeholder.
struct OnboardingProfile: Codable, Hashable {
    var day0Media: Day0Media?
    var targetWorkoutsPerWeek: Int
    var currentWorkoutsPerWeek: Int
    var failureWindow: FailureWindow?
    var failureWindowOther: String
    var failureTime: TimeOfDay
    var failureReasons: Set<FailureReason>
    var selectedDistractingApps: Set<DistractingApp>
    var distractingAppOther: String
    var nightScrollingFrequency: NightScrollingFrequency?
    var bedtime: TimeOfDay
    var alarmSound: AlarmSound
    /// File name in Documents of a track the user imported themselves.
    var ownSongFileName: String?
    /// Display name of that imported track.
    var ownSongTitle: String?
    /// File name in `Library/Sounds` of the 30-second clip the user trimmed.
    ///
    /// Only the name, never an absolute path: the container directory changes
    /// between launches and updates, so a stored path goes stale silently.
    var customAlarmSoundFile: String?
    /// What to call that clip on screen.
    var customAlarmSoundTitle: String?
    /// Where in the original track the clip starts, in seconds, so reopening
    /// the trimmer puts the window back where the user left it.
    var customAlarmTrimStart: Double?
    /// The bundled track selected before the user imported their own.
    ///
    /// Kept so a missing custom file falls back to a sound they actually chose
    /// rather than to a generic default.
    var previousBundledSound: AlarmSound?
    var comebackModeEnabled: Bool
    /// Set once the user activates the system on the final screen.
    var hasActivated: Bool

    static let `default` = OnboardingProfile(
        day0Media: nil,
        targetWorkoutsPerWeek: 3,
        currentWorkoutsPerWeek: 3,
        failureWindow: nil,
        failureWindowOther: "",
        failureTime: TimeOfDay(hour: 17, minute: 30),
        failureReasons: [],
        selectedDistractingApps: [],
        distractingAppOther: "",
        nightScrollingFrequency: nil,
        bedtime: TimeOfDay(hour: 23, minute: 0),
        alarmSound: .energyUp,
        ownSongFileName: nil,
        ownSongTitle: nil,
        customAlarmSoundFile: nil,
        customAlarmSoundTitle: nil,
        customAlarmTrimStart: nil,
        previousBundledSound: nil,
        comebackModeEnabled: true,
        hasActivated: false
    )

    // MARK: - Derived values

    /// Distracting apps in their canonical display order.
    var orderedDistractingApps: [DistractingApp] {
        DistractingApp.displayOrder.filter { selectedDistractingApps.contains($0) }
    }

    /// Failure reasons in their canonical display order.
    var orderedFailureReasons: [FailureReason] {
        FailureReason.allCases.filter { failureReasons.contains($0) }
    }

    /// Human list of the locked apps, e.g. "Instagram · TikTok".
    var lockedAppsSummary: String {
        let apps = orderedDistractingApps
        guard !apps.isEmpty else { return "your distracting apps" }
        return apps.map(\.label).joined(separator: " · ")
    }

    /// Sessions per week the user wants but is not currently getting.
    var weeklyGap: Int {
        max(targetWorkoutsPerWeek - currentWorkoutsPerWeek, 0)
    }

    /// True when the user is already meeting their own target, in which case the
    /// "cost of the gap" framing would be both wrong and insulting.
    var isAlreadyOnTarget: Bool { weeklyGap == 0 }

    /// Average weeks in a month, used for every monthly projection.
    static let weeksPerMonth: Double = 4.33
    /// The single stated assumption behind every time figure on the aha screen.
    static let minutesPerWorkout: Double = 60

    var monthlyMissedWorkouts: Double {
        Double(weeklyGap) * Self.weeksPerMonth
    }

    var monthlyMissedMinutes: Double {
        monthlyMissedWorkouts * Self.minutesPerWorkout
    }

    var monthlyMissedHours: Double {
        monthlyMissedMinutes / 60
    }

    var yearlyMissedWorkouts: Double {
        Double(weeklyGap) * 52
    }

    var yearlyMissedHours: Double {
        yearlyMissedWorkouts * Self.minutesPerWorkout / 60
    }

    /// Yearly loss expressed in whole days, which is the number that lands.
    var yearlyMissedDays: Double {
        yearlyMissedHours / 24
    }

    /// The moment GymLock's alarm fires — fifteen minutes before the window the
    /// user said they lose, so it arrives before the negotiation starts.
    var alarmTime: TimeOfDay {
        failureTime.offset(byMinutes: -15)
    }

    /// Whether the user asked for a night lock.
    var wantsNightLock: Bool {
        nightScrollingFrequency?.wantsBedtime ?? false
    }

    /// What to call the chosen alarm track anywhere it is summarised.
    var alarmSoundLabel: String {
        if alarmSound == .ownSong {
            return customAlarmSoundTitle ?? ownSongTitle ?? "your own track"
        }
        return alarmSound.label
    }

    /// The custom clip's file name, whichever route produced it.
    ///
    /// The trimmer writes `customAlarmSoundFile`; the older onboarding importer
    /// wrote `ownSongFileName`. Both must keep working for anyone mid-upgrade.
    var effectiveCustomSoundFile: String? {
        customAlarmSoundFile ?? ownSongFileName
    }

    /// Local URL of the imported track, if there is one.
    var ownSongURL: URL? {
        guard let ownSongFileName,
              let documents = FileManager.default.urls(
                  for: .documentDirectory,
                  in: .userDomainMask
              ).first
        else { return nil }
        return documents.appendingPathComponent(ownSongFileName)
    }
}

extension TimeOfDay {
    /// A new time shifted by a number of minutes, wrapping around midnight.
    func offset(byMinutes minutes: Int) -> TimeOfDay {
        let total = (hour * 60 + minute + minutes + 24 * 60) % (24 * 60)
        return TimeOfDay(hour: total / 60, minute: total % 60)
    }
}
