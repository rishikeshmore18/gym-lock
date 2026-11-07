#if canImport(AppIntents) && canImport(AlarmKit)
import AppIntents
import Foundation

/// Runs when the user taps "I'm up" (or "I'm going") on the system alarm.
///
/// The tap is the commitment: the note says `.stopped`, and the app goes
/// straight on to the quick task or the countdown, never to a second "I'm
/// up" of its own (FLOW, Flow 1 and 2).
///
/// `.foreground(.immediate)` is what brings GymLock to the front, and that
/// matters for more than politeness: the shield cannot be applied by a process
/// that is not running, so foregrounding the app *is* the mechanism. The iOS 18
/// spelling of this was `openAppWhenRun`, which is deprecated in iOS 26.
@available(iOS 26.0, *)
struct StartGymSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start gym session"
    static var description = IntentDescription("Starts the gym session the alarm was set for.")
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Alarm")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        // Plain wake alarms carry no intents; this is a second belt.
        if let id = UUID(uuidString: alarmID), !WakeAlarmID.startsSession(alarmID: id) {
            return .result()
        }
        AlarmHandoff.write(
            .init(slotID: UUID(uuidString: alarmID), firedAt: Date(), action: .stopped)
        )
        NotificationCenter.default.post(name: .gymLockAlarmHandoffAvailable, object: nil)
        return .result()
    }
}

/// Runs when the user taps the snooze button ("5 more min" by default).
///
/// It still starts the session, and the apps still lock. A snooze buys five
/// minutes of sleep, not five minutes of scrolling, so the only difference from
/// "I'm up" is which state the session opens in.
@available(iOS 26.0, *)
struct SnoozeGymSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze gym alarm"
    static var description = IntentDescription("Takes the single snooze.")
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Alarm")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID), !WakeAlarmID.startsSession(alarmID: id) {
            return .result()
        }
        let now = Date()
        // The second ring is booked here, before anything else, so it rings
        // even if the phone stays locked and the app never comes forward.
        // The coordinator adopts the same alarm (same derived id) later.
        if let id = UUID(uuidString: alarmID) {
            await Self.bookSecondRing(after: id, snoozedAt: now)
        }
        AlarmHandoff.write(
            .init(slotID: UUID(uuidString: alarmID), firedAt: now, action: .snoozed)
        )
        NotificationCenter.default.post(name: .gymLockAlarmHandoffAvailable, object: nil)
        return .result()
    }

    @MainActor
    private static func bookSecondRing(after id: UUID, snoozedAt: Date) async {
        await AlarmKitAlarmScheduler().scheduleSnoozeRealert(after: id, snoozedAt: snoozedAt)
    }
}
#endif
