import Foundation
import UserNotifications

/// Turns a notification the user touched into a session that actually starts.
///
/// Without this the alarm notification has no buttons at all — the scheduler
/// sets a category identifier, but a category that is never registered is a
/// category that does not exist — and tapping the banner simply opens GymLock
/// to whatever screen it was last on.
///
/// Every route ends in the same place: a note in `AlarmHandoff`. The delegate
/// does not touch the coordinator, because on a cold launch from an alarm tap
/// there is no coordinator yet.
final class AlarmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    enum Category {
        static let alarm = NotificationAlarmScheduler.categoryIdentifier
        /// The re-fire `MorningNotifier` sends when the single snooze runs out.
        static let snoozeRefire = "gymlock.session.snooze"
    }

    enum Action {
        static let imUp = "gymlock.alarm.action.imUp"
        static let snooze = "gymlock.alarm.action.snooze"
    }

    /// Registers every category this app sends, in one call.
    ///
    /// Must run before the first notification can arrive, which in practice
    /// means app `init()`. Registering later works for the next notification
    /// and silently loses the one that launched the app.
    static func registerCategories() {
        let imUp = UNNotificationAction(
            identifier: Action.imUp,
            title: "I'm up",
            options: [.foreground]
        )

        // Deliberately not `.foreground`. Dragging someone into the app is the
        // opposite of what they just asked for.
        let snooze = UNNotificationAction(
            identifier: Action.snooze,
            title: "5 more min",
            options: []
        )

        let alarm = UNNotificationCategory(
            identifier: Category.alarm,
            actions: [imUp, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // No second snooze exists, so the re-fire is not allowed to offer one.
        let refire = UNNotificationCategory(
            identifier: Category.snoozeRefire,
            actions: [imUp],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([alarm, refire])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// An alarm that fires while the app is open must not be swallowed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let slotID = GymAlarmRequest.slotID(fromNotificationIdentifier: identifier)

        switch response.actionIdentifier {
        case Action.snooze:
            write(slotID: slotID, wantsSnooze: true)

        case Action.imUp, UNNotificationDefaultActionIdentifier:
            // Opening the app during your own alarm is getting up.
            write(slotID: slotID, wantsSnooze: false)

        case UNNotificationDismissActionIdentifier:
            // Swiping an alarm away is not permission to skip the gym. The
            // session still has to exist, so the lock goes on the moment the
            // app next runs and the user has to resolve the day deliberately.
            write(slotID: slotID, wantsSnooze: false)

        default:
            break
        }
    }

    // MARK: - Private

    private func write(slotID: UUID?, wantsSnooze: Bool) {
        AlarmHandoff.write(.init(slotID: slotID, firedAt: Date(), wantsSnooze: wantsSnooze))
        NotificationCenter.default.post(name: .gymLockAlarmHandoffAvailable, object: nil)
    }
}
