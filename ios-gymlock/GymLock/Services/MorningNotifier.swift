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

    private enum ID {
        static let departure = "gymlock.session.departure"
        static let deadline = "gymlock.session.deadline"
        static let comeback = "gymlock.session.comeback"
        static let moved = "gymlock.session.moved"

        static let all = [departure, deadline, comeback, moved]
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

    // MARK: - Moved session

    /// One reminder at the time the user pushed today's session to.
    ///
    /// A one-off, deliberately separate from the recurring alarms: moving today
    /// must not disturb tomorrow.
    func scheduleMovedSession(at date: Date) async {
        await cancel(ID.moved)

        let interval = date.timeIntervalSinceNow
        guard interval > 30 else { return }

        await deliver(
            id: ID.moved,
            title: "Gym time",
            body: "you moved today's session to now. still yours to take.",
            after: interval
        )
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

    // MARK: - Cleanup

    /// Clears everything session-scoped. Called whenever a morning ends, so a
    /// reminder cannot arrive after the thing it was reminding about.
    func cancelSessionNotifications() async {
        center.removePendingNotificationRequests(withIdentifiers: ID.all)
    }

    // MARK: - Private

    private func deliver(id: String, title: String, body: String, after interval: TimeInterval) async {
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active

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

    private func cancel(_ id: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
