#if canImport(AlarmKit)
// AlarmKit builds its alert presentation on ActivityKit's data models, so the
// sound type lives there rather than in AlarmKit itself.
import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

/// Lightweight payload carried alongside the alarm.
///
/// Kept nearly empty on purpose: the metadata travels into system UI, so it
/// holds a reference rather than a copy of anything the app already knows.
@available(iOS 26.0, *)
struct GymAlarmMetadata: AlarmMetadata {
    init() {}
}

/// The real thing: a system alarm that breaks through silent mode and Focus.
///
/// This is what a 6:30 gym alarm has to be. A notification that the ringer
/// switch can silence is not an alarm, and a user who misses their session
/// because the phone was on vibrate will blame GymLock, correctly.
///
/// Every AlarmKit symbol is confined to this file behind an availability guard,
/// so the deployment target stays at iOS 18 and older devices simply get the
/// notification backend instead.
@available(iOS 26.0, *)
final class AlarmKitAlarmScheduler: AlarmScheduling {
    let capability: AlarmDeliveryCapability = .systemAlarm

    private let manager = AlarmManager.shared

    func authorizationStatus() async -> AlarmAuthorization {
        switch manager.authorizationState {
        case .authorized: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    @discardableResult
    func requestAuthorization() async -> AlarmAuthorization {
        do {
            let state = try await manager.requestAuthorization()
            return state == .authorized ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    func replaceAll(with requests: [GymAlarmRequest]) async {
        // A one-off whose moment has already come (only the snooze re-alert
        // is ever sent like this) is either ringing right now or finished.
        // It is left exactly as the system has it: cancelling would silence
        // a ringing alarm, rescheduling a past date would make no sense.
        let now = Date()
        let held = Set(
            requests
                .filter { request in request.fireDate.map { $0 <= now } ?? false }
                .map(\.slotID)
        )
        await cancelAll(except: held)

        guard await authorizationStatus() == .authorized else { return }

        for request in requests where !request.weekdays.isEmpty && !held.contains(request.slotID) {
            await schedule(request)
        }
    }

    func cancelAll() async {
        await cancelAll(except: [])
    }

    private func cancelAll(except kept: Set<UUID>) async {
        // Reconciling against the system's own list rather than a local table:
        // if the app was reinstalled or its state restored from a backup, the
        // stored ids may be stale while the alarms are very much still there.
        guard let alarms = try? manager.alarms else { return }
        for alarm in alarms where !kept.contains(alarm.id) {
            try? manager.cancel(id: alarm.id)
        }
    }

    /// The one-time snooze re-alert, scheduled straight from the system
    /// alarm's snooze button (FLOW, Flow 1: "rings again. no more snooze").
    ///
    /// Runs inside `SnoozeGymSessionIntent`, which can perform while the
    /// phone is still locked and before the app has drawn anything, so the
    /// second ring never depends on the user unlocking first. The id is
    /// derived from the snoozed alarm, so the coordinator's own sync later
    /// replaces this same alarm rather than adding another.
    ///
    /// - Returns: Whether the system now holds the re-alert.
    @discardableResult
    func scheduleSnoozeRealert(after sourceAlarmID: UUID, snoozedAt: Date = Date()) async -> Bool {
        guard WakeAlarmID.startsSession(alarmID: sourceAlarmID),
              !SnoozeAlarmID.isSnooze(sourceAlarmID),
              let template = SnoozeRealertTemplate.load(),
              await authorizationStatus() == .authorized
        else { return false }

        let request = template.request(sourceAlarmID: sourceAlarmID, snoozedAt: snoozedAt)
        // Already there: a second tap, or the intent and the app racing.
        if let alarms = try? manager.alarms, alarms.contains(where: { $0.id == request.slotID }) {
            return true
        }
        return await schedule(request)
    }

    func scheduledSlotIDs() async -> Set<UUID> {
        guard let alarms = try? manager.alarms else { return [] }
        return Set(alarms.map(\.id))
    }

    // MARK: - Private

    @discardableResult
    private func schedule(_ request: GymAlarmRequest) async -> Bool {
        if request.kind == .plainWake {
            return await schedulePlainWake(request)
        }

        let stopButton = AlarmButton(
            text: request.kind == .timeToGo ? "I'm going" : "I'm up",
            textColor: .white,
            systemImageName: "figure.walk"
        )

        // `.custom` rather than AlarmKit's built-in countdown: GymLock's snooze
        // has rules the generic one cannot express (the apps stay locked, it is
        // offered exactly once, and it is clamped inside the gym window), so
        // our own intent has to be what runs. The "time to go" alarm has no
        // secondary button: running late lives on the decision screen.
        let alert: AlarmPresentation.Alert = if request.allowsSnooze && request.kind == .gym {
            AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: request.title),
                stopButton: stopButton,
                secondaryButton: AlarmButton(
                    text: LocalizedStringResource(stringLiteral: "\(request.snoozeMinutes) more min"),
                    textColor: .white,
                    systemImageName: "zzz"
                ),
                secondaryButtonBehavior: .custom
            )
        } else {
            AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: request.title),
                stopButton: stopButton
            )
        }

        let attributes = AlarmAttributes<GymAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: GymAlarmMetadata(),
            tintColor: Theme.accent
        )

        // A one-off rings at a fixed date; the schedule repeats weekly.
        let schedule: Alarm.Schedule = if let fireDate = request.fireDate {
            .fixed(fireDate)
        } else {
            .relative(
                .init(
                    time: .init(hour: request.time.hour, minute: request.time.minute),
                    repeats: .weekly(request.weekdays.map(\.localeWeekday))
                )
            )
        }

        // Without a `stopIntent` the alarm silences and the app is never told
        // anything happened, which is precisely the bug that made the alarm
        // unable to start a session at all.
        let configuration = AlarmManager.AlarmConfiguration(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StartGymSessionIntent(alarmID: request.slotID.uuidString),
            secondaryIntent: request.allowsSnooze && request.kind == .gym
                ? SnoozeGymSessionIntent(alarmID: request.slotID.uuidString)
                : nil,
            sound: sound(for: request)
        )

        // The slot id is reused as the alarm id, which is what makes a replace a
        // genuine replace: the same slot can never occupy two alarms.
        return (try? await manager.schedule(id: request.slotID, configuration: configuration)) != nil
    }

    /// A plain wake-up: AlarmKit's own stop and its own snooze, and no
    /// intents at all, so nothing it does can reach the app or start a
    /// session. Its id is a `WakeAlarmID`, which the observer ignores.
    @discardableResult
    private func schedulePlainWake(_ request: GymAlarmRequest) async -> Bool {
        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let alert: AlarmPresentation.Alert = if request.allowsSnooze {
            AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: request.title),
                stopButton: stopButton,
                secondaryButton: AlarmButton(
                    text: LocalizedStringResource(stringLiteral: "\(request.snoozeMinutes) more min"),
                    textColor: .white,
                    systemImageName: "zzz"
                ),
                secondaryButtonBehavior: .countdown
            )
        } else {
            AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: request.title),
                stopButton: stopButton
            )
        }

        let attributes = AlarmAttributes<GymAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: GymAlarmMetadata(),
            tintColor: Theme.accent
        )

        let schedule: Alarm.Schedule = if let fireDate = request.fireDate {
            .fixed(fireDate)
        } else {
            .relative(
                .init(
                    time: .init(hour: request.time.hour, minute: request.time.minute),
                    repeats: .weekly(request.weekdays.map(\.localeWeekday))
                )
            )
        }

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: request.allowsSnooze
                ? Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(request.snoozeMinutes * 60))
                : nil,
            schedule: schedule,
            attributes: attributes,
            sound: sound(for: request)
        )

        return (try? await manager.schedule(id: request.slotID, configuration: configuration)) != nil
    }

    // MARK: - Observing what the system actually did

    /// A long-lived observer of the system's own view of our alarms.
    ///
    /// The stop intent is the fast path. This is the honest one: it reports what
    /// AlarmKit actually did, including a dismissal from the Lock Screen that
    /// never ran an intent.
    ///
    /// It races the intent on purpose. `AlarmHandoff.take()` is a genuine take,
    /// so both paths may write and only one can start a session.
    func observeAlarmUpdates(onFire: @escaping @Sendable (UUID) -> Void) -> Task<Void, Never> {
        Task {
            var alerting: Set<UUID> = []

            for await alarms in AlarmManager.shared.alarmUpdates {
                guard !Task.isCancelled else { return }

                // A plain wake alarm never starts a session, so it is never
                // reported as a gym alarm firing.
                let nowAlerting = Set(
                    alarms
                        .filter { $0.state == .alerting && WakeAlarmID.startsSession(alarmID: $0.id) }
                        .map(\.id)
                )

                // Only the transition into alerting is interesting. Reporting
                // the steady state every update would restart the morning on
                // every emission.
                for id in nowAlerting.subtracting(alerting) {
                    onFire(id)
                }

                alerting = nowAlerting
            }
        }
    }

    /// The user's clip, played by the system alarm itself, so it rings while
    /// locked or with the app closed.
    ///
    /// The full file name with its extension (`gymlock-custom-alarm.caf`, or a
    /// bundled track's caf). iOS 26.0 and anything missing on disk get the
    /// system alarm sound, never silence. See `AlarmKitSoundResolver`.
    private func sound(for request: GymAlarmRequest) -> AlertConfiguration.AlertSound {
        switch AlarmKitSoundResolver.resolve(
            soundFileName: request.soundFileName,
            soundResource: request.soundResource
        ) {
        case .named(let fileName): .named(fileName)
        case .systemDefault: .default
        }
    }
}

@available(iOS 26.0, *)
private extension Weekday {
    /// AlarmKit works in `Locale.Weekday`, which is named rather than numbered.
    var localeWeekday: Locale.Weekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }
}
#endif
