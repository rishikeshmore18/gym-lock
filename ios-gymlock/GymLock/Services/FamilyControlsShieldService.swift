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
    private let selectionKey = "gymlock.familyActivitySelection"

    #if canImport(FamilyControls)
    /// A named store, so the same shield can be found and lifted by a future
    /// launch or by a monitor extension. The default unnamed store would be
    /// harder to reason about once an extension is added.
    private let store = ManagedSettingsStore(named: .gymLock)

    /// The user's chosen apps and categories, as opaque tokens.
    private(set) var selection = FamilyActivitySelection()
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ledgerStore = ShieldLedgerStore(defaults: defaults)
        loadSelection()
        isShielded = ledgerStore.current != nil
        refreshAuthorization()
    }

    var hasSelection: Bool { selectionCount > 0 }

    // MARK: - Authorization

    func refreshAuthorization() {
        #if canImport(FamilyControls)
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved:
            authorization = .approved
        case .denied:
            // Denied after having been approved is a revocation, and the two
            // want different copy: one is a first refusal, the other is
            // something the user turned off in Settings and may not remember.
            authorization = hasSelection ? .revoked : .denied
        case .notDetermined:
            authorization = .notDetermined
        @unknown default:
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
        if let data = try? JSONEncoder().encode(new) {
            defaults.set(data, forKey: selectionKey)
        }

        // A live shield should immediately reflect a changed list rather than
        // waiting for the next morning.
        if isShielded { applyTokens() }
    }
    #endif

    private func loadSelection() {
        #if canImport(FamilyControls)
        guard let data = defaults.data(forKey: selectionKey),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        selection = decoded
        selectionCount = decoded.applicationTokens.count
            + decoded.categoryTokens.count
            + decoded.webDomainTokens.count
        #endif
    }

    // MARK: - Shielding

    func apply(until deadline: Date, sessionID: UUID?, owner: ShieldOwner) {
        guard authorization == .approved, hasSelection else { return }

        let capped = min(
            deadline,
            Date().addingTimeInterval(ShieldPolicy.absoluteMaximumHours * 3600)
        )

        // The ledger is written *before* the shield goes on. If the process is
        // killed between the two, the failsafe still knows a lock exists and
        // can clear it; the reverse ordering could strand a shield with no
        // record of it.
        ledgerStore.save(
            ShieldLedger(
                appliedAt: Date(),
                failsafeDeadline: capped,
                sessionID: sessionID,
                owner: owner
            )
        )

        applyTokens()
        startMonitoringWindow(until: capped)
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
                owner: ledger.owner
            )
        )
    }
    #endif

    // MARK: - Private

    private func applyTokens() {
        #if canImport(FamilyControls)
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens

        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)

        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
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
        center.stopMonitoring([.gymWindow])
        try? center.startMonitoring(.gymWindow, during: schedule)
        #endif
    }

    private func stopMonitoringWindow() {
        #if canImport(FamilyControls)
        DeviceActivityCenter().stopMonitoring([.gymWindow])
        #endif
    }
}

#if canImport(FamilyControls)
extension ManagedSettingsStore.Name {
    /// The single named store GymLock owns.
    static let gymLock = Self("gymlock")
}

extension DeviceActivityName {
    static let gymWindow = Self("gymlock.window")
}
#endif
