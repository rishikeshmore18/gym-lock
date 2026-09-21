import Foundation

/// Holds the coordinator's two long-lived observers and tears them down when it
/// is released.
///
/// This exists for one reason: `GymSessionCoordinator` is `@MainActor`, so its
/// `deinit` is nonisolated and cannot touch isolated stored properties. Rather
/// than weakening the coordinator's isolation to get a cleanup hook, the
/// observers live here, and this type's own nonisolated `deinit` does the work.
///
/// `@unchecked Sendable` is justified narrowly: both properties are written
/// only from the main actor during `attach(to:)`, and read in `deinit` when no
/// other reference can exist. The lock covers the write path regardless.
final class AlarmObserverBag: @unchecked Sendable {
    private let lock = NSLock()
    private var alarmUpdates: Task<Void, Never>?
    private var handoffToken: NSObjectProtocol?

    var hasAlarmObserver: Bool {
        lock.withLock { alarmUpdates != nil }
    }

    var hasHandoffObserver: Bool {
        lock.withLock { handoffToken != nil }
    }

    func hold(alarm task: Task<Void, Never>) {
        lock.withLock {
            alarmUpdates?.cancel()
            alarmUpdates = task
        }
    }

    func hold(handoff token: NSObjectProtocol) {
        lock.withLock {
            if let handoffToken { NotificationCenter.default.removeObserver(handoffToken) }
            handoffToken = token
        }
    }

    deinit {
        alarmUpdates?.cancel()
        if let handoffToken { NotificationCenter.default.removeObserver(handoffToken) }
    }
}
