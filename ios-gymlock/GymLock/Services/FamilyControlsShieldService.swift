import Foundation
import Observation

#if canImport(FamilyControls)
import DeviceActivity
import FamilyControls
import ManagedSettings
#endif

/// Real OS-level app blocking through Apple's Screen Time stack.
///
/// Three frameworks do three jobs here:
///
/// - `FamilyControls` asks permission and owns the privacy-preserving picker.
///   GymLock never learns which apps were chosen — the selection is a set of
///   opaque tokens the system resolves on its behalf.
/// - `ManagedSettings` applies the shield. The store is system-owned and
///   persists across launches, terminations, and reboots, which is what makes
///   blocking meaningful and also what makes the failsafe essential.
/// - `DeviceActivity` registers the schedule.
///
/// **Entitlement gate.** None of this functions without
/// `com.apple.developer.family-controls` in the signed provisioning profile,
/// and App Store distribution additionally requires Apple's manual approval.
/// Where authorisation fails, the service reports it plainly rather than
/// pretending to block.
@Observable
@MainActor
final class FamilyControlsShieldService: AppShielding {
    let capability: ShieldCapability = .familyControls

    private(set) var authorization: ShieldAuthorization = .notDetermined
    private(set) var isShielded = false

    /// Which lock currently holds the shield, read straight from the ledger.
    var owner: ShieldOwner? { ledgerStore.current?.owner }
    private(set) var selectionCount = 0

    private let ledgerStore: ShieldLedgerStore
    private let defaults: UserDefaults

    #if canImport(FamilyControls)
    /// A named store, so the same shield can be found and lifted by a future
    /// launch or by a monitor extension. The default unnamed store would be
    /// harder to reason about once an extension is added.
    private let store = ManagedSettingsStore(named: GymLockScreenTime.storeName)

    /// The user's chosen apps and categories, as opaque tokens.
    private(set) var selection = FamilyActivitySelection()
    #endif

    init(defaults suppliedDefaults: UserDefaults? = nil) {
        let defaults = suppliedDefaults ?? GymLockScreenTime.defaults
        self.defaults = defaults
        ledgerStore = ShieldLedgerStore(defaults: defaults)
        migrateLegacyStateIfNeeded()
        loadSelection()
        isShielded = ledgerStore.current != nil
        refreshAuthorization()
    }

    var hasSelection: Bool { selectionCount > 0 }

    // MARK: - Authorization

    func refreshAuthorization() {
        #if canImport(FamilyControls)
        let status = AuthorizationCenter.shared.authorizationStatus
        if status == .approved {
            authorization = .approved
        } else if #available(iOS 26.4, *), status == .approvedWithDataAccess {
            authorization = .approved
        } else if status == .denied {
            // Denied after having been approved is a revocation, and the two
            // want different copy: one is a first refusal, the other is
            // something the user turned off in Settings and may not remember.
            authorization = hasSelection ? .revoked : .denied
        } else {
            authorization = .notDetermined
        }
        #else
        authorization = .unavailable
        #endif
    }

    @discardableResult
    func requestAuthorization() async -> ShieldAuthorization {
        #if canImport(FamilyControls)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorization = .approved
        } catch {
            // The overwhelmingly common cause here is a missing entitlement in
            // the signed profile, not a user refusal. Either way the honest
            // answer is that GymLock cannot block anything.
            authorization = .denied
        }
        return authorization
        #else
        authorization = .unavailable
        return authorization
        #endif
    }

    // MARK: - Selection

    #if canImport(FamilyControls)
    /// Stores the user's picker result.
    ///
    /// Asked once and remembered. Nobody should be choosing their blocklist at
    /// 6:30 in the morning.
    func updateSelection(_ new: FamilyActivitySelection) {
        selection = new
        selectionCount = new.applicationTokens.count
            + new.categoryTokens.count
            + new.webDomainTokens.count

        // `FamilyActivitySelection` is Codable and the tokens stay opaque
        // through the round trip. They are never logged or transmitted.
        GymLockFamilySelection.save(new, to: defaults)

        // A live shield should immediately reflect a changed list rather than
        // waiting for the next morning.
        if isShielded { applyTokens() }
    }
    #endif

    private func loadSelection() {
        #if canImport(FamilyControls)
        selection = GymLockFamilySelection.load(from: defaults)
        selectionCount = GymLockFamilySelection.count(selection)
        #endif
    }

    // MARK: - Shielding

    func apply(until deadline: Date, sessionID: UUID?, owner: ShieldOwner) {
        guard authorization == .approved, hasSelection else { return }

        let effectiveDeadline = owner == .gymSession
            ? min(deadline, Date().addingTimeInterval(ShieldPolicy.absoluteMaximumHours * 3600))
            : deadline
        let activityName = owner == .gymSession
            ? GymLockScreenTime.gymActivityName
            : activeNightActivityName(at: Date())

        // The ledger is written *before* the shield goes on. If the process is
        // killed between the two, the failsafe still knows a lock exists and
        // can clear it; the reverse ordering could strand a shield with no
        // record of it.
        ledgerStore.save(
            ShieldLedger(
                appliedAt: Date(),
                failsafeDeadline: effectiveDeadline,
                sessionID: sessionID,
                owner: owner,
                activityName: activityName
            )
        )

        applyTokens()
        if owner == .gymSession {
            startMonitoringWindow(until: effectiveDeadline)
        }
        isShielded = true
    }

    func release() {
        clearTokens()
        stopMonitoringWindow()
        ledgerStore.clear()
        isShielded = false
    }

    func releaseForFailure() {
        release()
    }

    @discardableResult
    func enforceFailsafe(now: Date) -> Bool {
        guard let ledger = ledgerStore.current else {
            // No ledger means nothing should be shielded. Clearing defensively
            // costs nothing and closes the window where a shield outlived its
            // own record.
            if isShielded { clearTokens() }
            isShielded = false
            return false
        }

        guard ledger.hasExpired(at: now) else {
            isShielded = true
            return false
        }

        release()
        return true
    }

    #if DEBUG
    func debugSetAuthorization(_ value: ShieldAuthorization) {
        authorization = value
    }

    /// Forces the failsafe to be overdue so the safety release can be seen.
    func debugExpireFailsafe() {
        guard let ledger = ledgerStore.current else { return }
        ledgerStore.save(
            ShieldLedger(
                appliedAt: ledger.appliedAt,
                failsafeDeadline: Date().addingTimeInterval(-1),
                sessionID: ledger.sessionID,
                owner: ledger.owner,
                activityName: ledger.activityName
            )
        )
    }
    #endif

    // MARK: - Private

    private func applyTokens() {
        #if canImport(FamilyControls)
        GymLockFamilySelection.apply(selection, to: store)
        #endif
    }

    /// Removes every restriction this app owns.
    ///
    /// `clearAllSettings` rather than nilling each field: it is the one call
    /// that cannot leave a stray restriction behind, and on this path being
    /// thorough matters more than being surgical.
    private func clearTokens() {
        #if canImport(FamilyControls)
        store.clearAllSettings()
        #endif
    }

    /// Registers the lock window with DeviceActivity.
    ///
    /// Note the honest limitation: acting on these callbacks while the app is
    /// terminated requires a DeviceActivityMonitor extension target. Without
    /// one, the shield is still applied and lifted correctly by the app itself
    /// and by the failsafe — this registration is what an extension will hook
    /// into once it exists.
    private func startMonitoringWindow(until deadline: Date) {
        #if canImport(FamilyControls)
        let calendar = Calendar.current
        let now = Date()

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute], from: now),
            intervalEnd: calendar.dateComponents([.hour, .minute], from: deadline),
            repeats: false
        )

        let center = DeviceActivityCenter()
        let activity = DeviceActivityName(GymLockScreenTime.gymActivityName)
        center.stopMonitoring([activity])
        try? center.startMonitoring(activity, during: schedule)
        #endif
    }

    private func stopMonitoringWindow() {
        #if canImport(FamilyControls)
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(GymLockScreenTime.gymActivityName)])
        #endif
    }

    func syncNightActivities(plan: MorningPlan, now: Date) {
        #if canImport(FamilyControls)
        guard authorization == .approved else { return }

        let center = DeviceActivityCenter()
        let calendar = Calendar.current
        let rhythm = plan.scheduledRhythm
        var desired = Set<DeviceActivityName>()

        for night in plan.effectiveSleepDays(for: rhythm) {
            let activity = DeviceActivityName(GymLockScreenTime.nightActivityName(for: night.rawValue))
            let endDay = SleepSchedule.crossesMidnight(
                bedtime: rhythm.bedtime,
                wake: rhythm.wakeTime
            ) ? night.next : night
            let schedule = DeviceActivitySchedule(
                intervalStart: components(
                    weekday: night.rawValue,
                    time: rhythm.bedtime,
                    calendar: calendar
                ),
                intervalEnd: components(
                    weekday: endDay.rawValue,
                    time: rhythm.wakeTime,
                    calendar: calendar
                ),
                repeats: true
            )
            try? center.startMonitoring(activity, during: schedule)
            desired.insert(activity)
        }

        let pendingActivity = DeviceActivityName(GymLockScreenTime.pendingNightActivityName)
        if let pending = plan.pendingBedtime, pending.startsAt > now {
            defaults.set(pending.startsAt, forKey: GymLockScreenTime.pendingBedtimeCutoverKey)
        } else {
            defaults.removeObject(forKey: GymLockScreenTime.pendingBedtimeCutoverKey)
        }

        if let pending = plan.pendingBedtime,
           let night = SleepRules.night(
               endingOnMorningOf: pending.startsAt,
               rhythm: plan.rhythm,
               pending: nil,
               calendar: calendar
           ),
           night.end > now,
           plan.effectiveSleepDays().contains(night.weekday) {
            let schedule = DeviceActivitySchedule(
                intervalStart: components(for: night.start, calendar: calendar),
                intervalEnd: components(for: night.end, calendar: calendar),
                repeats: false
            )
            try? center.startMonitoring(pendingActivity, during: schedule)
            desired.insert(pendingActivity)
        }

        let obsolete = center.activities.filter {
            GymLockScreenTime.isNightActivity($0.rawValue) && !desired.contains($0)
        }
        if !obsolete.isEmpty { center.stopMonitoring(obsolete) }
        #endif
    }

    private func migrateLegacyStateIfNeeded() {
        let legacy = UserDefaults.standard
        if defaults.data(forKey: GymLockScreenTime.selectionKey) == nil,
           let selection = legacy.data(forKey: GymLockScreenTime.selectionKey) {
            defaults.set(selection, forKey: GymLockScreenTime.selectionKey)
        }
        if defaults.data(forKey: GymLockScreenTime.ledgerKey) == nil,
           let ledger = legacy.data(forKey: GymLockScreenTime.ledgerKey) {
            defaults.set(ledger, forKey: GymLockScreenTime.ledgerKey)
        }
    }

    #if canImport(FamilyControls)
    private func activeNightActivityName(at now: Date) -> String? {
        let center = DeviceActivityCenter()
        let activities = center.activities.filter {
            GymLockScreenTime.isNightActivity($0.rawValue)
        }
        if let pending = activities.first(where: {
            $0.rawValue == GymLockScreenTime.pendingNightActivityName
                && center.schedule(for: $0)?.nextInterval?.contains(now) == true
        }) {
            return pending.rawValue
        }
        return activities.first {
            center.schedule(for: $0)?.nextInterval?.contains(now) == true
        }?.rawValue
    }

    private func components(
        weekday: Int,
        time: TimeOfDay,
        calendar: Calendar
    ) -> DateComponents {
        var result = DateComponents()
        result.calendar = calendar
        result.timeZone = calendar.timeZone
        result.weekday = weekday
        result.hour = time.hour
        result.minute = time.minute
        return result
    }

    private func components(for date: Date, calendar: Calendar) -> DateComponents {
        var result = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        result.calendar = calendar
        result.timeZone = calendar.timeZone
        return result
    }
    #endif
}
