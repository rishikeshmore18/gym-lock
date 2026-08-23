import Foundation

/// What a workout check concluded.
enum WorkoutVerificationOutcome: Equatable {
    case verified
    case notEnoughEvidence(String)
    case unavailable(String)
}

/// How a home workout gets confirmed.
///
/// The real implementation belongs to HealthKit, a watch session, or motion
/// data, and none of that is built yet. Rather than shipping something that
/// returns `verified` unconditionally and calling it done — which would put a
/// fake success screen in front of users and quietly corrupt the momentum
/// ledger — the seam is defined now and the only implementation is one that
/// cannot reach a release build.
protocol WorkoutVerificationProviding: Sendable {
    /// Whether real verification can run at all.
    var isAvailable: Bool { get }
    /// Honest description of what this provider actually checks.
    var methodDescription: String { get }

    func verifyWorkout(startedAt: Date, minimumMinutes: Int) async -> WorkoutVerificationOutcome
}

/// The provider used in release builds until a real one lands.
///
/// It reports unavailable, and the UI reads that as "the user tells us whether
/// they finished". Self-reported and clearly labelled beats an invented sensor
/// reading.
struct UnverifiedWorkoutProvider: WorkoutVerificationProviding {
    let isAvailable = false
    let methodDescription = "self-reported"

    func verifyWorkout(startedAt: Date, minimumMinutes: Int) async -> WorkoutVerificationOutcome {
        .unavailable("workout verification isn't connected yet.")
    }
}

#if DEBUG
/// Development-only verifier. Confirms a workout purely by elapsed time.
///
/// Wrapped in `#if DEBUG` so it physically cannot exist in a shipped binary.
struct DebugWorkoutProvider: WorkoutVerificationProviding {
    let isAvailable = true
    let methodDescription = "debug: elapsed time only"

    func verifyWorkout(startedAt: Date, minimumMinutes: Int) async -> WorkoutVerificationOutcome {
        let elapsed = Date().timeIntervalSince(startedAt) / 60
        return elapsed >= Double(minimumMinutes) * 0.5
            ? .verified
            : .notEnoughEvidence("keep going a little longer.")
    }
}
#endif

enum WorkoutVerificationFactory {
    static func make() -> any WorkoutVerificationProviding {
        #if DEBUG
        return DebugWorkoutProvider()
        #else
        return UnverifiedWorkoutProvider()
        #endif
    }
}
