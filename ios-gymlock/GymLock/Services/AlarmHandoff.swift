import Foundation

extension Notification.Name {
    /// Posted the moment something outside the app's object graph leaves a note
    /// that the alarm fired, so a foreground app reacts immediately instead of
    /// waiting for the next scene-phase change.
    static let gymLockAlarmHandoffAvailable = Notification.Name("gymlock.alarm.handoffAvailable")
}

/// What the alarm hands to the app.
///
/// The system creates intents and delivers notification responses outside the
/// app's own object graph, so neither can reach the coordinator directly. They
/// leave a note here instead, and the app drains it the moment it is alive.
///
/// `nonisolated` on purpose: an `AppIntent` performs off the main actor, and a
/// notification response can arrive before any UI exists.
nonisolated enum AlarmHandoff {
    struct Pending: Codable, Hashable {
        var slotID: UUID?
        var firedAt: Date
        var wantsSnooze: Bool

        init(slotID: UUID?, firedAt: Date = Date(), wantsSnooze: Bool) {
            self.slotID = slotID
            self.firedAt = firedAt
            self.wantsSnooze = wantsSnooze
        }
    }

    /// Discards anything older than this. A note from yesterday morning must
    /// never start a session today.
    static let staleAfter: TimeInterval = 2 * 60 * 60

    /// Standard defaults are correct today because every writer runs inside the
    /// app's own process: a `LiveActivityIntent` with `.foreground(.immediate)`
    /// executes in-process, and so does a notification response. If a widget or
    /// a `DeviceActivityMonitor` extension is ever added, this moves to an App
    /// Group container, because those are genuinely separate processes and would
    /// silently write to a suite the app never reads.
    static let storageKey = "gymlock.alarm.handoff"

    static func write(_ pending: Pending, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Reads and clears in one step, so the same alarm cannot start two
    /// sessions. The intent and the `alarmUpdates` observer race by design;
    /// both write, and exactly one of them gets to act.
    static func take(now: Date = Date(), defaults: UserDefaults = .standard) -> Pending? {
        let pending = peek(now: now, defaults: defaults)
        defaults.removeObject(forKey: storageKey)
        return pending
    }

    /// Reads without consuming. Used by the debug panel, which must never eat
    /// the note it is reporting on.
    static func peek(now: Date = Date(), defaults: UserDefaults = .standard) -> Pending? {
        guard let data = defaults.data(forKey: storageKey),
              let pending = try? JSONDecoder().decode(Pending.self, from: data)
        else { return nil }

        guard now.timeIntervalSince(pending.firedAt) < staleAfter else { return nil }
        return pending
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
