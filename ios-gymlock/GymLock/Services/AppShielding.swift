import Foundation

/// Which blocking backend is actually in play.
enum ShieldCapability: String, Hashable {
    /// Real OS-level blocking through Apple's Screen Time APIs.
    case familyControls
    /// The flow runs end to end, but no other app is actually blocked.
    ///
    /// Used on the simulator, and on devices whose build does not carry the
    /// Family Controls entitlement yet. The UI must say so rather than imply
    /// blocking is happening.
    case demo

    var isReal: Bool { self == .familyControls }

    var headline: String {
        switch self {
        case .familyControls: "Screen Time blocking"
        case .demo: "demo blocking"
        }
    }
}

/// Whether the OS will let GymLock block anything.
enum ShieldAuthorization: String, Hashable {
    case notDetermined
    case approved
    case denied
    /// Previously approved, then withdrawn in Settings.
    case revoked
    /// The device or build cannot do real blocking at all.
    case unavailable
}

/// The one way apps get shielded and released.
///
/// Views never touch `ManagedSettingsStore`. Everything goes through this, which
/// is what lets the whole product be exercised in demo mode while Apple's
/// Family Controls approval is pending, and what guarantees a single place is
/// responsible for the failsafe.
@MainActor
protocol AppShielding: AnyObject {
    var capability: ShieldCapability { get }
    var authorization: ShieldAuthorization { get }
    /// True once the user has chosen which apps to block.
    var hasSelection: Bool { get }
    /// How many apps and categories are selected, for display only.
    var selectionCount: Int { get }
    /// True while a shield is actively applied.
    var isShielded: Bool { get }

    func refreshAuthorization()
    @discardableResult
    func requestAuthorization() async -> ShieldAuthorization

    /// Applies the shield with a mandatory expiry.
    ///
    /// There is no unbounded form of this call on purpose: every lock carries
    /// its own deadline, so no code path can produce a shield that outlives the
    /// reason for it.
    func apply(until deadline: Date, sessionID: UUID?)

    /// Lifts the shield because the user earned it or resolved the day.
    func release()

    /// Lifts the shield because something went wrong.
    ///
    /// Distinguished from `release` so it can be recorded honestly: the user
    /// gets their apps back, but no gym visit is credited.
    func releaseForFailure()

    /// Checks the persisted deadline and releases if it has passed.
    ///
    /// Called on launch, on every foreground, and periodically while running.
    /// Returns true when a release actually happened.
    @discardableResult
    func enforceFailsafe(now: Date) -> Bool

    #if DEBUG
    /// Forces an authorization state so both branches can be exercised without
    /// revoking real Screen Time permission in Settings.
    func debugSetAuthorization(_ value: ShieldAuthorization)
    #endif
}

// MARK: - Policy

/// The rules governing how long apps may ever be blocked.
enum ShieldPolicy {
    /// Slack added to a session's own window before the failsafe fires.
    ///
    /// Generous, because the normal end of a shield is arriving at the gym, and
    /// a slow commute should never trip the safety net.
    static let sessionGraceMinutes: Double = 90

    /// The absolute ceiling. Nothing may keep apps blocked longer than this,
    /// under any circumstances, for any reason.
    ///
    /// This is the last line of defence: if the session state corrupts, the
    /// coordinator crashes, a callback never arrives, or a bug leaves the
    /// shield on, the user gets their phone back after this long. Leaving
    /// somebody unable to open their apps indefinitely would be the single
    /// worst thing this app could do.
    static let absoluteMaximumHours: Double = 4

    /// Deadline for a session-scoped lock.
    static func deadline(forWindowMinutes minutes: Int, from start: Date = Date()) -> Date {
        let requested = Double(minutes) + sessionGraceMinutes
        let capped = min(requested, absoluteMaximumHours * 60)
        return start.addingTimeInterval(capped * 60)
    }
}

// MARK: - Failsafe ledger

/// The persisted record of an active shield.
///
/// Deliberately stored separately from the session. If session state is lost,
/// corrupted, or wiped, this survives — and it is what the failsafe reads. A
/// safety net attached to the thing it is protecting against is not a safety
/// net.
struct ShieldLedger: Codable, Hashable {
    var appliedAt: Date
    var failsafeDeadline: Date
    var sessionID: UUID?

    func hasExpired(at now: Date) -> Bool { now >= failsafeDeadline }
}

/// Shared persistence for the ledger, used by both implementations.
struct ShieldLedgerStore {
    private let defaults: UserDefaults
    private let key = "gymlock.shieldLedger"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: ShieldLedger? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ShieldLedger.self, from: data)
    }

    func save(_ ledger: ShieldLedger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Factory

enum AppShieldingFactory {
    /// Builds the best available shielding backend.
    ///
    /// Real Screen Time on a device that supports it; demo mode otherwise, so
    /// the simulator and pre-approval builds still exercise the whole flow.
    @MainActor
    static func make(defaults: UserDefaults = .standard) -> any AppShielding {
        #if targetEnvironment(simulator)
        return DemoShieldService(defaults: defaults)
        #else
        if #available(iOS 16.0, *) {
            return FamilyControlsShieldService(defaults: defaults)
        }
        return DemoShieldService(defaults: defaults)
        #endif
    }
}
