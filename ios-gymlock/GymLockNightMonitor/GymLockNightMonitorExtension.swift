import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class GymLockNightMonitorExtension: DeviceActivityMonitor {
    private let defaults = GymLockScreenTime.defaults
    private let settings = ManagedSettingsStore(named: GymLockScreenTime.storeName)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        let name = activity.rawValue
        guard GymLockScreenTime.isNightActivity(name) else { return }

        if name != GymLockScreenTime.pendingNightActivityName,
           let cutover = defaults.object(forKey: GymLockScreenTime.pendingBedtimeCutoverKey) as? Date,
           Date() < cutover {
            return
        }

        let ledgerStore = ShieldLedgerStore(defaults: defaults)
        if let ledger = ledgerStore.current,
           ledger.owner == .gymSession,
           !ledger.hasExpired(at: Date()) {
            return
        }

        let selection = GymLockFamilySelection.load(from: defaults)
        guard GymLockFamilySelection.count(selection) > 0 else { return }

        let deadline = DeviceActivityCenter().schedule(for: activity)?.nextInterval?.end
            ?? Date().addingTimeInterval(24 * 60 * 60)

        ledgerStore.save(
            ShieldLedger(
                appliedAt: Date(),
                failsafeDeadline: deadline,
                sessionID: nil,
                owner: .windDown,
                activityName: name
            )
        )
        GymLockFamilySelection.apply(selection, to: settings)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        let name = activity.rawValue
        let ledgerStore = ShieldLedgerStore(defaults: defaults)
        guard let ledger = ledgerStore.current,
              ledger.activityName == name
        else { return }

        if GymLockScreenTime.isNightActivity(name), ledger.owner == .windDown {
            settings.clearAllSettings()
            ledgerStore.clear()
        } else if name == GymLockScreenTime.gymActivityName, ledger.owner == .gymSession {
            if let night = activeNightActivity(at: Date()) {
                let selection = GymLockFamilySelection.load(from: defaults)
                if GymLockFamilySelection.count(selection) > 0 {
                    ledgerStore.save(
                        ShieldLedger(
                            appliedAt: Date(),
                            failsafeDeadline: night.interval.end,
                            sessionID: nil,
                            owner: .windDown,
                            activityName: night.activity.rawValue
                        )
                    )
                    GymLockFamilySelection.apply(selection, to: settings)
                    return
                }
            }
            settings.clearAllSettings()
            ledgerStore.clear()
        }
    }

    private func activeNightActivity(
        at now: Date
    ) -> (activity: DeviceActivityName, interval: DateInterval)? {
        let center = DeviceActivityCenter()
        let activities = center.activities.filter {
            GymLockScreenTime.isNightActivity($0.rawValue)
        }
        let eligible = activities.filter { activity in
            if activity.rawValue == GymLockScreenTime.pendingNightActivityName {
                return true
            }
            guard let cutover = defaults.object(
                forKey: GymLockScreenTime.pendingBedtimeCutoverKey
            ) as? Date else { return true }
            return now >= cutover
        }
        let ordered = eligible.sorted {
            $0.rawValue == GymLockScreenTime.pendingNightActivityName
                && $1.rawValue != GymLockScreenTime.pendingNightActivityName
        }
        for activity in ordered {
            if let interval = center.schedule(for: activity)?.nextInterval,
               interval.contains(now) {
                return (activity, interval)
            }
        }
        return nil
    }
}
