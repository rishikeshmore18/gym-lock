import Foundation
import ManagedSettings

enum GymLockScreenTime {
    static let appGroupIdentifier = "group.app.rork.b0c3y2ngorbbs63iwva1i"

    static let selectionKey = "gymlock.familyActivitySelection"
    static let ledgerKey = "gymlock.shieldLedger"
    static let pendingBedtimeCutoverKey = "gymlock.pendingBedtimeCutover"

    static let storeName = ManagedSettingsStore.Name("gymlock")
    static let gymActivityName = "gymlock.window"
    static let nightActivityPrefix = "gymlock.night."
    static let pendingNightActivityName = "gymlock.night.pending"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func nightActivityName(for weekday: Int) -> String {
        "\(nightActivityPrefix)\(weekday)"
    }

    static func isNightActivity(_ name: String) -> Bool {
        name.hasPrefix(nightActivityPrefix)
    }
}

enum ShieldOwner: String, Codable, Hashable {
    case windDown
    case gymSession
}

struct ShieldLedger: Codable, Hashable {
    var appliedAt: Date
    var failsafeDeadline: Date
    var sessionID: UUID?
    var owner: ShieldOwner
    var activityName: String?

    init(
        appliedAt: Date,
        failsafeDeadline: Date,
        sessionID: UUID?,
        owner: ShieldOwner = .gymSession,
        activityName: String? = nil
    ) {
        self.appliedAt = appliedAt
        self.failsafeDeadline = failsafeDeadline
        self.sessionID = sessionID
        self.owner = owner
        self.activityName = activityName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appliedAt = try container.decode(Date.self, forKey: .appliedAt)
        failsafeDeadline = try container.decode(Date.self, forKey: .failsafeDeadline)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        owner = try container.decodeIfPresent(ShieldOwner.self, forKey: .owner) ?? .gymSession
        activityName = try container.decodeIfPresent(String.self, forKey: .activityName)
    }

    private enum CodingKeys: String, CodingKey {
        case appliedAt, failsafeDeadline, sessionID, owner, activityName
    }

    func hasExpired(at now: Date) -> Bool { now >= failsafeDeadline }
}

struct ShieldLedgerStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var current: ShieldLedger? {
        guard let data = defaults.data(forKey: GymLockScreenTime.ledgerKey) else { return nil }
        return try? JSONDecoder().decode(ShieldLedger.self, from: data)
    }

    func save(_ ledger: ShieldLedger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: GymLockScreenTime.ledgerKey)
    }

    func clear() {
        defaults.removeObject(forKey: GymLockScreenTime.ledgerKey)
    }
}
