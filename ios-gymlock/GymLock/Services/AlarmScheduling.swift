import Foundation

/// A recurring gym alarm, described in terms GymLock cares about rather than in
/// terms of whichever framework ends up delivering it.
struct GymAlarmRequest: Hashable {
    /// Stable identity, taken from the `AlarmSlot`. Rescheduling the same slot
    /// must replace rather than duplicate, and this is how that is guaranteed.
    var slotID: UUID
    var time: TimeOfDay
    var weekdays: Set<Weekday>
    var title: String
    var message: String
    /// Bundled resource name of the chosen alarm sound, without extension.
    var soundResource: String?
    /// The file the *notification* backend should play, with its extension.
    ///
    /// Separate from `soundResource` because the two backends need different
    /// formats of the same track: `AVAudioPlayer` takes the mp3, the system
    /// sound facility only accepts IMA4/PCM in caf, aiff or wav.
    var soundFileName: String?
    /// Whether this alarm offers the single snooze.
    ///
    /// Morning only, decided from the daypart at schedule time. The alert is
    /// built by the system before the app is running, so the rule has to travel
    /// with the request rather than being asked for at the moment of the tap.
    var allowsSnooze: Bool = false
    /// Set for a one-off alarm: it rings once at this exact moment and never
    /// repeats. `time` and `weekdays` still describe it for backends that
    /// only think in weekly terms.
    var fireDate: Date? = nil

    var isOneOff: Bool { fireDate != nil }
}

/// How capable the current alarm backend is, so the UI can be honest about what
/// will actually happen at 6:30 in the morning.
enum AlarmDeliveryCapability: String, Hashable {
    /// AlarmKit: a real system alarm that breaks through silent mode and Focus.
    case systemAlarm
    /// Local notifications: respects the ringer switch and Focus.
    case notification

    var headline: String {
        switch self {
        case .systemAlarm: "system alarm"
        case .notification: "notification"
        }
    }

    var explanation: String {
        switch self {
        case .systemAlarm:
            "rings through silent mode and Focus."
        case .notification:
            "follows your ringer and Focus settings."
        }
    }
}

/// Whether the app is allowed to wake the user at all.
enum AlarmAuthorization: String, Hashable {
    case notDetermined
    case authorized
    case denied
}

/// The one way alarms are created, replaced, and removed.
///
/// Views never touch AlarmKit or `UNUserNotificationCenter` directly. Everything
/// goes through this, which is what makes it possible to swap the backend by OS
/// version without a single call site changing — and what stops duplicate alarms
/// accumulating, because replacement is the only write operation offered.
protocol AlarmScheduling: AnyObject, Sendable {
    var capability: AlarmDeliveryCapability { get }

    func authorizationStatus() async -> AlarmAuthorization
    @discardableResult
    func requestAuthorization() async -> AlarmAuthorization

    /// Replaces the entire set of scheduled alarms with exactly these.
    ///
    /// Deliberately not "add one": a whole-set replace is idempotent, so
    /// re-running it on launch, after an edit, after a timezone change, or after
    /// a restore converges on the right state instead of stacking duplicates.
    func replaceAll(with requests: [GymAlarmRequest]) async

    /// Removes everything this app has scheduled.
    func cancelAll() async

    /// Identifiers currently scheduled, for diagnostics and duplicate checks.
    func scheduledSlotIDs() async -> Set<UUID>
}

// MARK: - Selection

enum AlarmSchedulerFactory {
    /// The best backend this OS can offer.
    ///
    /// AlarmKit needs iOS 26. The deployment target stays at 18 — raising it for
    /// one feature would strand users who can still be served perfectly well by
    /// a notification, so the capability is isolated here instead.
    static func make() -> any AlarmScheduling {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmKitAlarmScheduler()
        }
        #endif
        return NotificationAlarmScheduler()
    }
}

// MARK: - Shared helpers

extension GymAlarmRequest {
    /// A deterministic per-weekday identifier.
    ///
    /// Notifications repeat weekly per day, so one request becomes several
    /// registrations. Deriving each id from the slot means a replace can find
    /// and remove all of them without keeping a side table.
    func notificationIdentifier(for day: Weekday) -> String {
        "gymlock.alarm.\(slotID.uuidString).\(day.rawValue)"
    }

    static let identifierPrefix = "gymlock.alarm."

    static func slotID(fromNotificationIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let remainder = identifier.dropFirst(identifierPrefix.count)
        guard let separator = remainder.lastIndex(of: ".") else { return nil }
        return UUID(uuidString: String(remainder[remainder.startIndex..<separator]))
    }
}
