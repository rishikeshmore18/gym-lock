#if DEBUG
import Foundation

/// Jumps the morning to any state without waiting for a real 6:30 AM, a real
/// gym, or a real Apple Watch.
///
/// The whole file is inside `#if DEBUG`, so none of it — not the enum, not the
/// methods, not the panel that calls them — exists in a shipped binary. There is
/// no runtime flag to get wrong and no way a production user reaches a simulated
/// arrival.
extension GymSessionCoordinator {
    enum DebugStep: String, CaseIterable, Identifiable {
        // The flow
        case alarmFired
        case imGoing
        case missionComplete
        case departed
        case countdownAt75
        case countdownExpired

        // Screen Time
        case familyControlsAuthorized
        case familyControlsDenied
        case shieldApplied
        case shieldRemoved
        case technicalRelease

        // Arrival
        case gymRegionEntered
        case badGPSAccuracy
        case goodGPSAccuracy
        case driveBy
        case gymDwellConfirmed
        case arrivalTrouble

        // Health
        case healthWorkoutDetected
        case noHealthWorkout
        case healthDenied

        // Fallbacks
        case quickWorkoutComplete
        case cantTodayWithinAllowance
        case cantTodayOverAllowance

        var id: String { rawValue }

        var section: String {
            switch self {
            case .alarmFired, .imGoing, .missionComplete, .departed,
                 .countdownAt75, .countdownExpired:
                "flow"
            case .familyControlsAuthorized, .familyControlsDenied,
                 .shieldApplied, .shieldRemoved, .technicalRelease:
                "screen time"
            case .gymRegionEntered, .badGPSAccuracy, .goodGPSAccuracy,
                 .driveBy, .gymDwellConfirmed, .arrivalTrouble:
                "arrival"
            case .healthWorkoutDetected, .noHealthWorkout, .healthDenied:
                "health"
            case .quickWorkoutComplete, .cantTodayWithinAllowance, .cantTodayOverAllowance:
                "fallbacks"
            }
        }

        var label: String {
            switch self {
            case .alarmFired: "alarm fired"
            case .imGoing: "tapped I'm going"
            case .missionComplete: "mission complete"
            case .departed: "departed"
            case .countdownAt75: "countdown at 75%"
            case .countdownExpired: "countdown expired"
            case .familyControlsAuthorized: "FamilyControls authorized"
            case .familyControlsDenied: "FamilyControls denied"
            case .shieldApplied: "shield applied"
            case .shieldRemoved: "shield removed"
            case .technicalRelease: "technical release (failsafe)"
            case .gymRegionEntered: "gym region entered"
            case .badGPSAccuracy: "bad GPS accuracy"
            case .goodGPSAccuracy: "good GPS accuracy"
            case .driveBy: "drive-by (no unlock)"
            case .gymDwellConfirmed: "gym dwell confirmed"
            case .arrivalTrouble: "arrival couldn't be confirmed"
            case .healthWorkoutDetected: "HealthKit workout detected"
            case .noHealthWorkout: "no HealthKit workout"
            case .healthDenied: "HealthKit denied"
            case .quickWorkoutComplete: "quick workout complete"
            case .cantTodayWithinAllowance: "can't today (within allowance)"
            case .cantTodayOverAllowance: "can't today (over allowance)"
            }
        }

        static var sections: [String] {
            ["flow", "screen time", "arrival", "health", "fallbacks"]
        }
    }

    func simulate(_ step: DebugStep) {
        switch step {
        // MARK: Flow

        case .alarmFired:
            endSession()
            debugStore?.debugSeedGym()
            beginSession(for: debugStore?.plan.enabledSlots.first)

        case .imGoing:
            if session == nil { simulate(.alarmFired) }
            commitToGoing()

        case .missionComplete:
            if session == nil { simulate(.imGoing) }
            completeMission()

        case .departed:
            if session == nil { simulate(.missionComplete) }
            if session?.state == .activationMission { beginPreparation() }
            markDeparted(detected: false)

        case .countdownAt75:
            if session?.state != .preparing { simulate(.missionComplete) }
            guard var current = session else { return }
            let total = Double(current.windowMinutes) * 60
            current.committedAt = Date().addingTimeInterval(-total * GymSession.nudgeFraction)
            current.deadline = Date().addingTimeInterval(total * (1 - GymSession.nudgeFraction))
            current.hasShownPreparationNudge = false
            debugReplace(current)
            debugShowNudge()

        case .countdownExpired:
            if session?.state != .preparing { simulate(.missionComplete) }
            guard var current = session else { return }
            current.deadline = Date().addingTimeInterval(-1)
            current.state = .preparing
            debugReplace(current)
            handleExpiry()

        // MARK: Screen Time

        case .familyControlsAuthorized:
            shield.debugSetAuthorization(.approved)
            if let demo = shield as? DemoShieldService, !demo.hasSelection {
                demo.setDemoSelection(count: 5)
            }
            debugStore?.hasConfiguredBlockedApps = true

        case .familyControlsDenied:
            shield.debugSetAuthorization(.denied)

        case .shieldApplied:
            if session == nil { simulate(.alarmFired) }
            guard let current = session else { return }
            shield.apply(
                until: ShieldPolicy.deadline(forWindowMinutes: current.windowMinutes),
                sessionID: current.id
            )
            debugStore?.record(.shieldApplied, sessionID: current.id)

        case .shieldRemoved:
            shield.release()
            debugStore?.record(.shieldRemoved, sessionID: session?.id)

        case .technicalRelease:
            // Backdates the ledger so the real failsafe path runs, rather than
            // just calling release and pretending.
            if !shield.isShielded { simulate(.shieldApplied) }
            (shield as? DemoShieldService)?.debugExpireFailsafe()
            #if canImport(FamilyControls)
            if #available(iOS 16.0, *) {
                (shield as? FamilyControlsShieldService)?.debugExpireFailsafe()
            }
            #endif
            debugEnforceFailsafe()

        // MARK: Arrival

        case .gymRegionEntered:
            if session?.state != .departed { simulate(.departed) }
            arrival.debugSimulateRegionEntry()
            debugNoteCandidate()

        case .badGPSAccuracy:
            arrival.debugSetAccuracy(480)

        case .goodGPSAccuracy:
            arrival.debugSetAccuracy(12)

        case .driveBy:
            // Enters the region and leaves before the dwell completes. The
            // correct outcome is that nothing unlocks.
            if session?.state != .departed { simulate(.departed) }
            arrival.debugSimulateDriveBy()
            debugCancelCandidate()

        case .gymDwellConfirmed:
            if session == nil { simulate(.departed) }
            confirmArrival()

        case .arrivalTrouble:
            if session?.state != .approachingGym { simulate(.gymRegionEntered) }
            arrival.debugSimulateTrouble()
            reportArrivalTroubleManually()

        // MARK: Health

        case .healthWorkoutDetected:
            health.debugSetAvailability(.authorized)
            health.debugEmitWorkout()

        case .noHealthWorkout:
            guard var current = session else { return }
            current.workoutDetected = false
            current.detectedWorkout = nil
            debugReplace(current)

        case .healthDenied:
            health.debugSetAvailability(.denied)

        // MARK: Fallbacks

        case .quickWorkoutComplete:
            if session == nil { simulate(.alarmFired) }
            startQuickWorkout(minutes: 20)
            finishQuickWorkout(completed: true)

        case .cantTodayWithinAllowance:
            debugStore?.debugClearSkips()
            if session == nil { simulate(.alarmFired) }
            beginCantToday()

        case .cantTodayOverAllowance:
            debugStore?.debugExhaustSkips(count: easySkipAllowance)
            if session == nil { simulate(.alarmFired) }
            beginCantToday()
        }
    }
}
#endif
