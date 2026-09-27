import Foundation
import UserNotifications

/// The only place morning notifications are sent from.
///
/// The governing rule is restraint. Once the user has said they are going, the
/// commitment exists and the app's job changes from pushing to supporting. A
/// stream of motivational buzzes every few minutes is how an app that was
/// helping at 6:31 becomes an app that gets deleted at 6:45.
///
/// So: exactly one message when they leave, exactly one near the deadline, and
/// exactly one on a comeback day. Each is scheduled by a fixed identifier, so
/// re-entering the same state cannot stack duplicates.
@MainActor
final class MorningNotifier {
    private let center = UNUserNotificationCenter.current()

    /// Defined on `NotificationRoute` so the tap router reads the same ids
    /// this sends. None of these may start a session when tapped.
    private enum ID {
        static let departure = NotificationRoute.ID.departure
        static let deadline = NotificationRoute.ID.deadline
        static let comeback = NotificationRoute.ID.comeback
        static let arrival = NotificationRoute.ID.arrival
        static let snooze = NotificationRoute.ID.snooze
        /// Not session-scoped, so deliberately not in `all`: ending a morning
        /// must not cancel tonight's heads-up.
        static let windDown = NotificationRoute.ID.windDown

        static let all = NotificationRoute.ID.sessionScoped
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    // MARK: - Departure

    /// One positive message, fired the moment the user leaves.
    ///
    /// Returns the index used so the session can record it and the next gym day
    /// draws a different line.
    @discardableResult
    func sendDeparture(previousIndex: Int?) async -> Int {
        let message = DepartureMessage.next(after: previousIndex)

        await deliver(
            id: ID.departure,
            title: message.title,
            body: message.body,
            after: 1
        )

        return message.index
    }

    // MARK: - Arrival

    /// The one message sent when the user is confirmed at the gym. Arriving
    /// is not the workout, so it says what makes the day count (FLOW, Flow 3).
    func sendArrival() async {
        await deliver(
            id: ID.arrival,
            title: "",
            body: WorkoutDoneLine.arrival,
            after: 1
        )
    }

    // MARK: - At the gym

    /// The workout-done line and "you left after", scheduled ahead because
    /// iOS won't run the app on a timer. Moved by scheduling again under the
    /// same id, withdrawn by cancelling it.
    func scheduleGymNotice(id: String, at date: Date, body: String) async {
        await deliver(id: id, title: "", body: body, after: max(1, date.timeIntervalSinceNow))
    }

    func cancelGymNotice(id: String) async {
        await cancel(id)
    }

    // MARK: - Deadline

    /// One useful reminder shortly before the window closes.
    ///
    /// Skipped entirely if the user has already left — they are moving, and a
    /// buzz telling them time is short would be pure noise.
    func scheduleDeadlineReminder(at deadline: Date, gymBy: String) async {
        await cancel(ID.deadline)

        let fireAt = deadline.addingTimeInterval(-5 * 60)
        let interval = fireAt.timeIntervalSinceNow
        guard interval > 30 else { return }

        await deliver(
            id: ID.deadline,
            title: "5 minutes left",
            body: "your window closes at \(gymBy).",
            after: interval
        )
    }

    func cancelDeadlineReminder() async {
        await cancel(ID.deadline)
    }

    // MARK: - Missed

    /// "missed ... pick a day to make it up." scheduled the moment the alarm
    /// rings, for when the lock lifts, so it arrives even if the app was
    /// killed (FLOW, Flow 1 and 2). Committing or resolving cancels it.
    func scheduleMissedNotice(day: Date, at date: Date, message: String) async {
        let id = MissedNotice.identifier(forDay: day)
        await deliver(
            id: id,
            title: "gymlock",
            body: message,
            after: max(1, date.timeIntervalSinceNow)
        )
    }

    func cancelMissedNotice(day: Date) async {
        await cancel(MissedNotice.identifier(forDay: day))
    }

    /// Makes sure the notice reaches the user once: left alone if it is still
    /// waiting or was already shown, sent now otherwise (a session saved
    /// before it was scheduled at the ring).
    func ensureMissedNotice(day: Date, message: String) async {
        let id = MissedNotice.identifier(forDay: day)
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        guard !pending.contains(id), !delivered.contains(id) else { return }
        await deliver(id: id, title: "gymlock", body: message, after: 1)
    }

    // MARK: - Snooze

    /// Brings the alarm back after the single snooze.
    ///
    /// A notification rather than silence, because the overwhelmingly likely
    /// case is that the phone went back down on the nightstand and the app was
    /// suspended within seconds. `timeSensitive` so it still arrives through a
    /// sleep Focus — this is the one message in the whole app that exists
    /// specifically to wake somebody.
    func scheduleSnoozeRefire(at date: Date, minutes: Int = GymSession.snoozeMinutes) async {
        await cancel(ID.snooze)

        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }

        await deliver(
            id: ID.snooze,
            title: "Time to move",
            body: minutes == 1
                ? "your minute is up. your apps are still locked."
                : "your \(minutes) minutes are up. your apps are still locked.",
            after: interval,
            interruption: .timeSensitive
        )
    }

    func cancelSnoozeRefire() async {
        await cancel(ID.snooze)
    }

    // MARK: - Wind-down

    /// One time-sensitive heads-up when the evening window opens.
    ///
    /// It does not claim apps lock at that moment, because without a
    /// `DeviceActivityMonitor` extension they do not: the lock engages the
    /// next time GymLock runs. The notification's whole job is to be that
    /// next run. `timeSensitive` so it gets through a sleep Focus, which is
    /// precisely when the window opens.
    func scheduleWindDownStart(at date: Date) async {
        await cancel(ID.windDown)

        let interval = date.timeIntervalSinceNow
        guard interval > 30 else { return }

        await deliver(
            id: ID.windDown,
            title: "wind-down",
            body: "the window started. apps lock when you next open gymlock.",
            after: interval,
            interruption: .timeSensitive
        )
    }

    func cancelWindDownStart() async {
        await cancel(ID.windDown)
    }

    // MARK: - Comeback

    /// One notification on the next realistic opportunity after a missed day.
    ///
    /// Comeback Mode exists to make returning easy, so the copy carries no
    /// reference to what was missed.
    func scheduleComeback(at date: Date) async {
        await cancel(ID.comeback)

        let interval = date.timeIntervalSinceNow
        guard interval > 60 else { return }

        await deliver(
            id: ID.comeback,
            title: "today's a good one to take",
            body: "your comeback session is set. nothing to make up.",
            after: interval
        )
    }

    // MARK: - Streak at risk (FLOW, Flow 6)

    /// The one pending at-risk notification, moved by scheduling again under
    /// the same id. Only when notifications are already allowed: this is
    /// recomputed quietly on every change and must never raise the prompt.
    func scheduleStreakAtRisk(at date: Date, body: String) async {
        await deliverIfAuthorized(
            id: NotificationRoute.ID.streakAtRisk,
            body: body,
            after: date.timeIntervalSinceNow
        )
    }

    /// Withdrawn the moment the week is safe.
    func cancelStreakAtRisk() async {
        await cancel(NotificationRoute.ID.streakAtRisk)
    }

    // MARK: - Freezes (FLOW, Flow 5)

    /// Replaces every pending "you earned a freeze." notice with `planned`.
    func replaceFreezeNotices(_ planned: [FreezeNotice.Planned]) async {
        let prefix = NotificationRoute.ID.freezePrefix
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for notice in planned {
            await deliverIfAuthorized(id: notice.id, body: notice.body, after: notice.fireDate.timeIntervalSinceNow)
        }
    }

    // MARK: - Cleanup

    /// Clears everything session-scoped. Called whenever a morning ends, so a
    /// reminder cannot arrive after the thing it was reminding about.
    func cancelSessionNotifications() async {
        center.removePendingNotificationRequests(withIdentifiers: ID.all)
    }

    // MARK: - Private

    private func deliver(
        id: String,
        title: String,
        body: String,
        after interval: TimeInterval,
        interruption: UNNotificationInterruptionLevel = .active
    ) async {
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruption

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, interval),
            repeats: false
        )

        // Reusing the identifier means re-entering a state replaces the pending
        // notification rather than adding a second one.
        await cancel(id)
        try? await center.add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    private func deliverIfAuthorized(id: String, body: String, after interval: TimeInterval) async {
        guard interval > 1 else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let content = UNMutableNotificationContent()
        content.title = "gymlock"
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        await cancel(id)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func cancel(_ id: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
