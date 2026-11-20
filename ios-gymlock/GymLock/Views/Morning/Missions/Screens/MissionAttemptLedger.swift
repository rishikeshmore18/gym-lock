//
//  MissionAttemptLedger.swift
//  GymLock · mission screens
//
//  "Swap is earned": the user gets one assigned mission and may only ask for a different one after
//  the current mission has failed twice (or when it cannot run at all). This ledger counts the
//  failed attempts per session id and mission, in UserDefaults, so a relaunch or a dismissed
//  runner keeps the count.
//
//  Key: "gymlock.morning.missionAttempts.<sessionID>.<mission>" (the mission's raw value).
//  Only counts live here. Nothing about a photo, a phrase or a step ever does.
//

import Foundation

enum MissionAttemptLedger {
    /// Failed attempts on the same mission before "Try a different one" is offered.
    static let failuresToEarnSwap = 2

    static let keyPrefix = "gymlock.morning.missionAttempts."

    static func key(sessionID: UUID, mission: ActivationMissionType) -> String {
        "\(keyPrefix)\(sessionID.uuidString).\(mission.rawValue)"
    }

    static func failures(
        sessionID: UUID,
        mission: ActivationMissionType,
        defaults: UserDefaults = .standard
    ) -> Int {
        max(0, defaults.integer(forKey: key(sessionID: sessionID, mission: mission)))
    }

    static func isSwapEarned(
        sessionID: UUID,
        mission: ActivationMissionType,
        defaults: UserDefaults = .standard
    ) -> Bool {
        failures(sessionID: sessionID, mission: mission, defaults: defaults) >= failuresToEarnSwap
    }

    /// Adds one failed attempt and returns the new count. Counts left behind by earlier sessions
    /// are removed on the way, so the defaults never grow.
    @discardableResult
    static func recordFailure(
        sessionID: UUID,
        mission: ActivationMissionType,
        defaults: UserDefaults = .standard
    ) -> Int {
        pruneOtherSessions(keeping: sessionID, defaults: defaults)
        let next = failures(sessionID: sessionID, mission: mission, defaults: defaults) + 1
        defaults.set(next, forKey: key(sessionID: sessionID, mission: mission))
        return next
    }

    private static func pruneOtherSessions(keeping sessionID: UUID, defaults: UserDefaults) {
        let current = "\(keyPrefix)\(sessionID.uuidString)."
        for existing in defaults.dictionaryRepresentation().keys
        where existing.hasPrefix(keyPrefix) && !existing.hasPrefix(current) {
            defaults.removeObject(forKey: existing)
        }
    }
}
