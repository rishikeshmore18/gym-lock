import Foundation

extension Notification.Name {
    /// Posted the moment something outside the app's object graph leaves a note
    /// that the alarm fired, so a foreground app reacts immediately instead of
    /// waiting for the next scene-phase change.
    static let gymLockAlarmHandoffAvailable = Notification.Name("gymlock.alarm.handoffAvailable")
    /// Posted when a non-alarm notification tap leaves a route, so a
    /// frontmost app can act on it straight away.
    static let gymLockNotificationRouteAvailable = Notification.Name("gymlock.notification.routeAvailable")
}

/// What the alarm hands to the app.
///
/// The system creates intents and delivers notification responses outside the
/// app's own object graph, so neither can reach the coordinator directly. They
/// leave a note here instead, and the app drains it the moment it is alive.
///
/// `nonisolated` on purpose: an `AppIntent` performs off the main actor, and a
/// notification response can arrive before any UI exists.
/// What happened at the alarm, which decides whether the app may play the
/// song again.
///
/// - `fired`: the alarm is ringing and nobody has touched it yet.
/// - `stopped`: the user tapped the system alarm's stop button.
/// - `snoozed`: the user tapped the system alarm's snooze button.
///
/// Only `fired` ever starts `AlarmRinger`. After a stop or a snooze the user
/// has already silenced the system alarm, and the app ringing the same song
/// again would undo the tap.
nonisolated enum AlarmHandoffAction: String, Codable, Hashable {
    case fired, stopped, snoozed
}

nonisolated enum AlarmHandoff {
    struct Pending: Codable, Hashable {
        var slotID: UUID?
        var firedAt: Date
        var action: AlarmHandoffAction

        /// Compatibility view for callers that only care about snooze.
        var wantsSnooze: Bool { action == .snoozed }

        init(slotID: UUID?, firedAt: Date = Date(), action: AlarmHandoffAction) {
            self.slotID = slotID
            self.firedAt = firedAt
            self.action = action
        }

        /// The pre-action spelling. Notes written this way always came from a
        /// button tap, so `false` means stopped, which never restarts audio.
        init(slotID: UUID?, firedAt: Date = Date(), wantsSnooze: Bool) {
            self.init(slotID: slotID, firedAt: firedAt, action: wantsSnooze ? .snoozed : .stopped)
        }

        private enum CodingKeys: String, CodingKey {
            case slotID, firedAt, action, wantsSnooze
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            slotID = try container.decodeIfPresent(UUID.self, forKey: .slotID)
            firedAt = try container.decode(Date.self, forKey: .firedAt)
            if let action = try? container.decodeIfPresent(AlarmHandoffAction.self, forKey: .action) {
                self.action = action
            } else {
                // A note saved by an older build: only `wantsSnooze`.
                let snooze = (try? container.decodeIfPresent(Bool.self, forKey: .wantsSnooze)) ?? false
                action = snooze ? .snoozed : .stopped
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(slotID, forKey: .slotID)
            try container.encode(firedAt, forKey: .firedAt)
            try container.encode(action, forKey: .action)
            // Kept so an older build reading this note still understands it.
            try container.encode(wantsSnooze, forKey: .wantsSnooze)
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
        // A user's tap is never overwritten by the observer reporting that the
        // same alarm rang: that would turn a stop back into a ring.
        if pending.action == .fired,
           let existing = peek(now: pending.firedAt, defaults: defaults),
           existing.action != .fired,
           existing.slotID == pending.slotID {
            return
        }
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
