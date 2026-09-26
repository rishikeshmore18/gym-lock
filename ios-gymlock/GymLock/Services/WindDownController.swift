import Foundation
import Observation

/// Owns the wind-down lock: applies and releases a `.windDown` shield for the
/// evening window, and nothing else.
///
/// The honest shape of this feature, stated up front: **the lock engages when
/// GymLock next runs inside the window.** There is no background process in
/// this build that applies a shield at 11:00 PM while the app is suspended.
/// What exists instead is:
///
/// 1. The foreground catch-up here, which runs on launch and on every
///    foreground and asks the plain question "should the night lock be
///    holding right now?" This is cheap, idempotent, and always correct
///    relative to the clock.
/// 2. A time-sensitive notification at the window's start, which gives the
///    user a reason to touch the phone, which triggers 1.
/// 3. The failsafe deadline, which is set to the window's end, so a lock that
///    outlived its window is lifted by the next foreground even if nothing
///    else noticed.
///
/// A `DeviceActivityMonitor` extension would make the shield engage without
/// the app ever running. That target does not exist in this project, and
/// pretending otherwise would put a lie on the wind-down card.
@Observable
@MainActor
final class WindDownController {
    /// True while the wind-down window should be holding the shield.
    ///
    /// This is the window's own truth, independent of whether the shield
    /// backend could actually apply it: a user with no apps selected still
    /// has an active window, and the copy says so rather than pretending a
    /// lock exists.
    private(set) var isActive = false

    /// Brings the lock in line with the clock. Safe to call as often as the
    /// app comes to the foreground.
    ///
    /// The ownership rule does the delicate work: if the shield is currently
    /// owned by `.gymSession`, this method touches nothing. The gym lock
    /// takes the shield without an intervening release, so a handover can
    /// happen mid-window, and the wind-down controller then sees the owner is
    /// no longer `.windDown` and stops claiming it.
    ///
    /// Always on: the lock runs from bedtime to wake time on the sleep
    /// schedule's nights, required ones included, with no switch (FLOW, "The
    /// Night Lock"). A pending bedtime never moves tonight's window.
    func reconcile(
        now: Date = Date(),
        plan: MorningPlan,
        shield: any AppShielding,
        calendar: Calendar = .current
    ) {
        let window = plan.nightLockWindow(at: now, calendar: calendar)
        isActive = window != nil

        // A shield belonging to the morning is the morning's business.
        guard shield.owner == .windDown || shield.owner == nil else { return }
        // Only the apps the user chose are ever blocked, so with none chosen
        // there is nothing to lock. Calls, messages, maps and alarms are never
        // in that selection.
        guard shield.hasSelection else { return }

        if let window {
            // The deadline is the window's own end, so the failsafe lifts the
            // lock by the clock even if no foreground ever runs again.
            shield.apply(until: window.end, sessionID: nil, owner: .windDown)
        } else if shield.owner == .windDown {
            shield.release()
        }
    }
}
