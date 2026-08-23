import Foundation
import UserNotifications

/// The alarm backend that works everywhere.
///
/// A local notification is not a real alarm — it obeys the ringer switch and
/// Focus — and the app says so rather than pretending otherwise. It is still the
/// right fallback: it fires at the correct local time, survives reboots, and
/// handles daylight saving correctly because the trigger is expressed in
/// calendar components rather than an absolute date.
final class NotificationAlarmScheduler: AlarmScheduling {
    let capability: AlarmDeliveryCapability = .notification

    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> AlarmAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    @discardableResult
    func requestAuthorization() async -> AlarmAuthorization {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    func replaceAll(with requests: [GymAlarmRequest]) async {
        // Everything this app owns is removed first, so an edited or deleted
        // slot cannot leave a stale alarm behind to fire tomorrow morning.
        await cancelAll()

        guard await authorizationStatus() == .authorized else { return }

        for request in requests {
            for day in request.weekdays {
                await add(request, on: day)
            }
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(GymAlarmRequest.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    func scheduledSlotIDs() async -> Set<UUID> {
        let pending = await center.pendingNotificationRequests()
        return Set(pending.compactMap { GymAlarmRequest.slotID(fromNotificationIdentifier: $0.identifier) })
    }

    // MARK: - Private

    private func add(_ request: GymAlarmRequest, on day: Weekday) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.message
        content.sound = sound(for: request)
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Self.categoryIdentifier

        // Calendar components rather than a date: the system re-resolves this
        // against the current calendar every week, so a timezone change or a
        // clocks-go-forward night does not shift the alarm.
        var components = DateComponents()
        components.hour = request.time.hour
        components.minute = request.time.minute
        components.weekday = day.rawValue

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let notification = UNNotificationRequest(
            identifier: request.notificationIdentifier(for: day),
            content: content,
            trigger: trigger
        )

        try? await center.add(notification)
    }

    /// The user's chosen track, if the system will play it.
    ///
    /// Notification sounds must be under 30 seconds and live in the bundle or
    /// Library/Sounds. The generated alarm tracks qualify; an imported song does
    /// not, so that case falls back to the default rather than silently failing.
    private func sound(for request: GymAlarmRequest) -> UNNotificationSound {
        guard let resource = request.soundResource,
              Bundle.main.url(forResource: resource, withExtension: "mp3") != nil
        else {
            return .defaultCritical
        }
        return UNNotificationSound(named: UNNotificationSoundName("\(resource).mp3"))
    }

    static let categoryIdentifier = "gymlock.alarm"
}
