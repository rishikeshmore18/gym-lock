import Foundation
import UserNotifications

/// What a notification the user touched actually is, and so what the tap may do.
///
/// `docs/FLOW.md`, Flow 3: only alarm notifications may start a session. Every
/// other notification GymLock sends (departure, deadline, arrival, comeback,
/// moved, the snooze re-fire, wind-down) just opens the app. Before this type
/// existed, tapping any of them wrote an alarm handoff, so tapping "you're
/// here" after the gym could lock the apps again for up to two hours.
///
/// Pure: built from the request identifier and category alone, so every
/// identifier the app sends can be pinned in a test.
enum NotificationRoute: Codable, Hashable {
    /// The session-scoped notifications `MorningNotifier` sends.
    enum SessionKind: String, Codable, Hashable, CaseIterable {
        case departure
        case deadline
        case arrival
        case comeback
        case moved

        var identifier: String {
            switch self {
            case .departure: ID.departure
            case .deadline: ID.deadline
            case .arrival: ID.arrival
            case .comeback: ID.comeback
            case .moved: ID.moved
            }
        }
    }

    /// A real gym alarm. The only route that may write a handoff.
    case alarm(slotID: UUID?)
    /// The alarm coming back after the single snooze. The live session is
    /// already on screen, so the tap only opens the app.
    case snoozeRefire
    case session(SessionKind)
    /// The night lock's heads-up. The lock catches up on foreground by itself.
    case windDown
    case unknown

    /// Every identifier `MorningNotifier` sends, in one place, so the sender
    /// and the router cannot drift apart.
    enum ID {
        static let departure = "gymlock.session.departure"
        static let deadline = "gymlock.session.deadline"
        static let comeback = "gymlock.session.comeback"
        static let moved = "gymlock.session.moved"
        static let arrival = "gymlock.session.arrival"
        static let snooze = "gymlock.session.snooze"
        /// Not session-scoped: ending a morning must not cancel tonight's
        /// heads-up, so it is deliberately not in `sessionScoped`.
        static let windDown = "gymlock.session.windDown"

        static let sessionScoped = [departure, deadline, comeback, moved, arrival, snooze]
    }

    init(identifier: String, categoryIdentifier: String) {
        if identifier.hasPrefix(GymAlarmRequest.identifierPrefix)
            || categoryIdentifier == NotificationAlarmScheduler.categoryIdentifier {
            self = .alarm(slotID: GymAlarmRequest.slotID(fromNotificationIdentifier: identifier))
            return
        }

        switch identifier {
        case ID.snooze:
            self = .snoozeRefire
        case ID.windDown:
            self = .windDown
        default:
            if let kind = SessionKind.allCases.first(where: { $0.identifier == identifier }) {
                self = .session(kind)
            } else {
                self = .unknown
            }
        }
    }

    var isAlarm: Bool {
        if case .alarm = self { return true }
        return false
    }

    /// The handoff a tap writes, or nil when the tap must not start anything.
    ///
    /// Only `.alarm` ever returns one. For an alarm: the snooze button starts
    /// the session and snoozes; "I'm up", a body tap and a swipe-away all start
    /// it (swiping an alarm away is not permission to skip the gym).
    func handoff(forAction actionIdentifier: String, at now: Date) -> AlarmHandoff.Pending? {
        guard case let .alarm(slotID) = self else { return nil }

        switch actionIdentifier {
        case AlarmNotificationDelegate.Action.snooze:
            return AlarmHandoff.Pending(slotID: slotID, firedAt: now, wantsSnooze: true)
        case AlarmNotificationDelegate.Action.imUp,
             UNNotificationDefaultActionIdentifier,
             UNNotificationDismissActionIdentifier:
            return AlarmHandoff.Pending(slotID: slotID, firedAt: now, wantsSnooze: false)
        default:
            return nil
        }
    }
}
