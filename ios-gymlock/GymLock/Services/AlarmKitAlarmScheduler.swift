#if canImport(AlarmKit)
// AlarmKit builds its alert presentation on ActivityKit's data models, so the
// sound type lives there rather than in AlarmKit itself.
import ActivityKit
import AlarmKit
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
        await cancelAll()

        guard await authorizationStatus() == .authorized else { return }

        for request in requests where !request.weekdays.isEmpty {
            await schedule(request)
        }
    }

    func cancelAll() async {
        // Reconciling against the system's own list rather than a local table:
        // if the app was reinstalled or its state restored from a backup, the
        // stored ids may be stale while the alarms are very much still there.
        guard let alarms = try? manager.alarms else { return }
        for alarm in alarms {
            try? manager.cancel(id: alarm.id)
        }
    }

    func scheduledSlotIDs() async -> Set<UUID> {
        guard let alarms = try? manager.alarms else { return [] }
        return Set(alarms.map(\.id))
    }

    // MARK: - Private

    private func schedule(_ request: GymAlarmRequest) async {
        let stopButton = AlarmButton(
            text: "I'm up",
            textColor: .white,
            systemImageName: "figure.walk"
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: request.title),
            stopButton: stopButton
        )

        let attributes = AlarmAttributes<GymAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: GymAlarmMetadata(),
            tintColor: Theme.accent
        )

        let schedule = Alarm.Schedule.relative(
            .init(
                time: .init(hour: request.time.hour, minute: request.time.minute),
                repeats: .weekly(request.weekdays.map(\.localeWeekday))
            )
        )

        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            sound: sound(for: request)
        )

        // The slot id is reused as the alarm id, which is what makes a replace a
        // genuine replace: the same slot can never occupy two alarms.
        _ = try? await manager.schedule(id: request.slotID, configuration: configuration)
    }

    /// The user's chosen bundled track, or the system alarm sound.
    ///
    /// An imported song is not offered to AlarmKit: it lives in Documents rather
    /// than the bundle, so it would fail silently at the exact moment it
    /// mattered most.
    private func sound(for request: GymAlarmRequest) -> AlertConfiguration.AlertSound {
        guard let resource = request.soundResource,
              Bundle.main.url(forResource: resource, withExtension: "mp3") != nil
        else {
            return .default
        }
        return .named("\(resource).mp3")
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
