import Foundation
import UserNotifications

/// Turns a notification the user touched into a session that actually starts.
///
/// Without this the alarm notification has no buttons at all — the scheduler
/// sets a category identifier, but a category that is never registered is a
/// category that does not exist — and tapping the banner simply opens GymLock
/// to whatever screen it was last on.
///
/// Only an alarm tap writes a note in `AlarmHandoff` (`docs/FLOW.md`, Flow 3).
/// Every other notification just opens the app, and its route is kept in
/// `PendingNotificationRoute`. The delegate does not touch the coordinator,
/// because on a cold launch from an alarm tap there is no coordinator yet.
final class AlarmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    enum Category {
        static let alarm = NotificationAlarmScheduler.categoryIdentifier
        /// The re-fire `MorningNotifier` sends when the single snooze runs out.
        static let snoozeRefire = NotificationRoute.ID.snooze
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
    ///
    /// Called again from every alarm sync with the plan's snooze length, so
    /// the button always names the minutes the user actually chose.
    static func registerCategories(
        snoozeMinutes: Int = GymSession.snoozeMinutes,
        snoozeEnabled: Bool = true
    ) {
        let imUp = UNNotificationAction(
            identifier: Action.imUp,
            title: "I'm up",
            options: [.foreground]
        )

        // Deliberately not `.foreground`. Dragging someone into the app is the
        // opposite of what they just asked for.
        let snooze = UNNotificationAction(
            identifier: Action.snooze,
            title: "\(snoozeMinutes) more min",
            options: []
        )

        let alarm = UNNotificationCategory(
            identifier: Category.alarm,
            // Switched off on the Alarm screen means no button, not a button
            // that quietly does nothing.
            actions: snoozeEnabled ? [imUp, snooze] : [imUp],
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
        let request = response.notification.request
        Self.handle(
            identifier: request.identifier,
            categoryIdentifier: request.content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier
        )
    }

    // MARK: - Routing

    /// The whole tap rule, shared by the delegate and the debug simulator so
    /// the simulator runs the real path.
    ///
    /// An alarm tap writes the handoff exactly as before: snooze starts and
    /// snoozes; "I'm up", a body tap and a swipe-away start the session.
    /// Anything else only opens the app and never writes a handoff.
    @discardableResult
    static func handle(
        identifier: String,
        categoryIdentifier: String,
        actionIdentifier: String,
        now: Date = Date()
    ) -> NotificationRoute {
        let route = NotificationRoute(identifier: identifier, categoryIdentifier: categoryIdentifier)

        if let handoff = route.handoff(forAction: actionIdentifier, at: now) {
            AlarmHandoff.write(handoff)
            NotificationCenter.default.post(name: .gymLockAlarmHandoffAvailable, object: nil)
        } else if !route.isAlarm, actionIdentifier != UNNotificationDismissActionIdentifier {
            // Swiping a non-alarm away does not open the app, so it is not
            // a route anyone asked for.
            PendingNotificationRoute.write(route, at: now)
        }

        return route
    }
}
