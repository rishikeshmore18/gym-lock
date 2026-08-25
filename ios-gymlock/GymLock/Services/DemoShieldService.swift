import Foundation
import Observation

/// Shielding that runs the whole flow without blocking anything.
///
/// This exists for two honest reasons:
///
/// 1. The simulator cannot do OS-level blocking at all.
/// 2. Real blocking needs Apple's Family Controls entitlement in the signed
///    provisioning profile, and distribution needs Apple's manual approval.
///    Until that lands, the product still has to be buildable, demonstrable,
///    and testable end to end.
///
/// Everything else behaves identically — the same states, the same timings, the
/// same failsafe — so switching to the real backend changes no UI. What it must
/// never do is let the interface claim apps are locked when they are not, which
/// is why `capability` reports `.demo` and the UI labels it.
@Observable
@MainActor
final class DemoShieldService: AppShielding {
    let capability: ShieldCapability = .demo

    private(set) var authorization: ShieldAuthorization = .notDetermined
    private(set) var isShielded = false

    /// A stand-in count so the flow can show a plausible number.
    private(set) var selectionCount = 0

    private let ledgerStore: ShieldLedgerStore
    private let defaults: UserDefaults
    private let selectionKey = "gymlock.demoShieldSelection"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ledgerStore = ShieldLedgerStore(defaults: defaults)
        selectionCount = defaults.integer(forKey: selectionKey)
        isShielded = ledgerStore.current != nil
        authorization = selectionCount > 0 ? .approved : .notDetermined
    }

    var hasSelection: Bool { selectionCount > 0 }

    func refreshAuthorization() {
        // Nothing to query: demo mode is whatever the user last chose.
    }

    @discardableResult
    func requestAuthorization() async -> ShieldAuthorization {
        authorization = .approved
        return authorization
    }

    /// Records a pretend selection so onboarding and settings have something to
    /// show.
    func setDemoSelection(count: Int) {
        selectionCount = max(0, count)
        defaults.set(selectionCount, forKey: selectionKey)
    }

    func apply(until deadline: Date, sessionID: UUID?) {
        let capped = min(
            deadline,
            Date().addingTimeInterval(ShieldPolicy.absoluteMaximumHours * 3600)
        )
        ledgerStore.save(
            ShieldLedger(appliedAt: Date(), failsafeDeadline: capped, sessionID: sessionID)
        )
        isShielded = true
    }

    func release() {
        ledgerStore.clear()
        isShielded = false
    }

    func releaseForFailure() {
        release()
    }

    @discardableResult
    func enforceFailsafe(now: Date) -> Bool {
        guard let ledger = ledgerStore.current else {
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
                sessionID: ledger.sessionID
            )
        )
    }
    #endif
}
