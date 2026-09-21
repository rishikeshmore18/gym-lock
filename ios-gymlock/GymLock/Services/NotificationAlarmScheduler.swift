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

        // A one-off pins the full date so it cannot come back next week.
        let trigger: UNCalendarNotificationTrigger
        if let fireDate = request.fireDate {
            let full = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: full, repeats: false)
        } else {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }
        let notification = UNNotificationRequest(
            identifier: request.notificationIdentifier(for: day),
            content: content,
            trigger: trigger
        )

        try? await center.add(notification)
    }

    /// The user's chosen track, if the system will really play it.
    ///
    /// Three constraints, all of them silent failures when broken: the file must
    /// be under 30 seconds, must live in the bundle or `Library/Sounds`, and must
    /// be Linear PCM, IMA4, µLaw or aLaw in an aiff, wav or caf container. mp3 is
    /// *not* on that list, which is why `soundFileName` hands over a caf.
    ///
    /// An imported song is served from `Library/Sounds` by the trimmer, which
    /// exports m4a for the ringer and a caf sibling for this path.
    private func sound(for request: GymAlarmRequest) -> UNNotificationSound {
        guard let fileName = request.soundFileName,
              Self.soundFileExists(named: fileName)
        else {
            return .defaultCritical
        }
        return UNNotificationSound(named: UNNotificationSoundName(fileName))
    }

    /// Looks where the system itself looks, so a missing file falls back loudly
    /// at schedule time rather than silently at 6:30 in the morning.
    private static func soundFileExists(named fileName: String) -> Bool {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        if Bundle.main.url(forResource: name, withExtension: ext) != nil { return true }

        guard let library = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else { return false }

        let sounds = library.appendingPathComponent("Sounds").appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: sounds.path)
    }

    static let categoryIdentifier = "gymlock.alarm"
}
