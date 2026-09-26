import Foundation

/// The last non-alarm notification the user opened the app from.
///
/// Written by the notification delegate, which runs before any store exists
/// on a cold launch, so it lives in defaults like `AlarmHandoff`. Nothing acts
/// on it yet: a later step sends the workout-done notification to the
/// Progress tab through it. Alarm taps never land here; they write a handoff.
enum PendingNotificationRoute {
    struct Entry: Codable, Hashable {
        var route: NotificationRoute
        var tappedAt: Date
    }

    static let storageKey = "gymlock.notification.pendingRoute"

    static func write(_ route: NotificationRoute, at now: Date = Date(), defaults: UserDefaults = .standard) {
        guard !route.isAlarm,
              let data = try? JSONEncoder().encode(Entry(route: route, tappedAt: now))
        else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func peek(defaults: UserDefaults = .standard) -> Entry? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    /// Reads and clears in one step, so one tap is acted on once.
    static func take(defaults: UserDefaults = .standard) -> Entry? {
        let entry = peek(defaults: defaults)
        defaults.removeObject(forKey: storageKey)
        return entry
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
