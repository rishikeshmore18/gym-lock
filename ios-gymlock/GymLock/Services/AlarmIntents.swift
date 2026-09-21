#if canImport(AppIntents) && canImport(AlarmKit)
import AppIntents
import Foundation

/// Runs when the user taps "I'm up" on the system alarm.
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
        AlarmHandoff.write(
            .init(slotID: UUID(uuidString: alarmID), firedAt: Date(), wantsSnooze: false)
        )
        NotificationCenter.default.post(name: .gymLockAlarmHandoffAvailable, object: nil)
        return .result()
    }
}

/// Runs when the user taps "5 more min".
///
/// It still starts the session, and the apps still lock. A snooze buys five
/// minutes of sleep, not five minutes of scrolling, so the only difference from
/// "I'm up" is which state the session opens in.
@available(iOS 26.0, *)
struct SnoozeGymSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze gym alarm"
    static var description = IntentDescription("Takes the single five minute snooze.")
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Alarm")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        AlarmHandoff.write(
            .init(slotID: UUID(uuidString: alarmID), firedAt: Date(), wantsSnooze: true)
        )
        NotificationCenter.default.post(name: .gymLockAlarmHandoffAvailable, object: nil)
        return .result()
    }
}
#endif
