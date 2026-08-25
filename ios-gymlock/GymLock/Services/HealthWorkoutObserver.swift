import Foundation
import HealthKit
import Observation

/// Notices workouts that Apple Health already recorded.
///
/// The defining constraint of this service is that **the user never starts a
/// workout in GymLock**. They do not pick an activity, tap start, tap stop, or
/// log a single set. GymLock is not a workout tracker — it is the thing that
/// gets somebody through the door — so this reads whatever their watch, Apple
/// Fitness, or any other HealthKit-compatible app already wrote, and quietly
/// enriches the day with it.
///
/// Three rules follow from that:
///
/// 1. **Nothing depends on it.** A user with no watch, no tracker, or a denied
///    permission has an identical experience minus one small tick. Gating
///    anything on Health would punish people for their choice of hardware.
/// 2. **It may arrive hours late.** A sample is written when a workout *ends*,
///    long after the user walked in. Matching is therefore retrospective.
/// 3. **Almost nothing is kept.** Activity name, start, end, source. No heart
///    rate, no route, no series data.
@Observable
@MainActor
final class HealthWorkoutObserver {
    enum Availability: Equatable {
        case unknown
        case unavailable
        case notDetermined
        case authorized
        case denied
    }

    private(set) var availability: Availability = .unknown
    /// The most recent workout seen, for the debug panel.
    private(set) var lastDetected: DetectedWorkout?

    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?
    private var anchor: HKQueryAnchor?

    /// Called when a workout appears that has not been seen before.
    private var onWorkout: ((DetectedWorkout) -> Void)?

    private let defaults: UserDefaults
    private let anchorKey = "gymlock.healthAnchor"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadAnchor()
    }

    /// Whether it is worth showing any Health-related UI at all.
    var isUsable: Bool { availability == .authorized }

    // MARK: - Authorization

    /// The narrowest useful set of read permissions.
    ///
    /// Workouts alone would be enough. Steps and active energy are included
    /// because they let a future session summary say something true without a
    /// second permission prompt — and nothing beyond that is requested, because
    /// a long list of health permissions is both a privacy smell and a
    /// conversion killer.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    func refreshAvailability() {
        guard HKHealthStore.isHealthDataAvailable() else {
            availability = .unavailable
            return
        }

        // Read authorisation is deliberately opaque in HealthKit: the API will
        // not tell an app whether it can read a type, precisely so that a
        // refusal cannot be detected and nagged about. So this reports
        // `notDetermined` until a request has been made, and thereafter treats
        // absence of data as absence of data rather than as refusal.
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        switch status {
        case .sharingAuthorized, .sharingDenied:
            availability = defaults.bool(forKey: "gymlock.healthRequested") ? .authorized : .notDetermined
        case .notDetermined:
            availability = defaults.bool(forKey: "gymlock.healthRequested") ? .authorized : .notDetermined
        @unknown default:
            availability = .notDetermined
        }
    }

    @discardableResult
    func requestAuthorization() async -> Availability {
        guard HKHealthStore.isHealthDataAvailable() else {
            availability = .unavailable
            return availability
        }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            defaults.set(true, forKey: "gymlock.healthRequested")
            availability = .authorized
        } catch {
            availability = .denied
        }
        return availability
    }

    // MARK: - Observing

    /// Starts watching for new workouts.
    ///
    /// Background delivery is enabled so a workout that ends while GymLock is
    /// closed still lands. The callback does very little: it runs an anchored
    /// query, hands over anything new, and returns.
    func startObserving(onWorkout: @escaping (DetectedWorkout) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            availability = .unavailable
            return
        }
        guard observerQuery == nil else {
            self.onWorkout = onWorkout
            return
        }

        self.onWorkout = onWorkout

        let workoutType = HKObjectType.workoutType()
        let query = HKObserverQuery(
            sampleType: workoutType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }

            Task { @MainActor in
                await self?.fetchNewWorkouts()
                completionHandler()
            }
        }

        store.execute(query)
        observerQuery = query

        store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in
            // Background delivery is best-effort. Failing here only means
            // workouts are noticed on next foreground instead, which is fine:
            // nothing time-critical depends on this.
        }

        Task { await fetchNewWorkouts() }
    }

    func stopObserving() {
        if let observerQuery {
            store.stop(observerQuery)
        }
        observerQuery = nil
        onWorkout = nil
    }

    /// Pulls anything written since the last check.
    func fetchNewWorkouts() async {
        let samples = await runAnchoredQuery()

        for workout in samples {
            let detected = DetectedWorkout(
                activityName: workout.workoutActivityType.displayName,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                source: workout.sourceRevision.source.name
            )

            // A workout GymLock itself somehow wrote would be circular
            // evidence. Nothing in this app writes to Health, but guarding
            // costs a line and removes the whole class of problem.
            guard workout.sourceRevision.source.bundleIdentifier
                != Bundle.main.bundleIdentifier else { continue }

            lastDetected = detected
            onWorkout?(detected)
        }
    }

    /// Fetches workouts in an explicit window, used when matching a session
    /// retrospectively rather than reacting to a live change.
    func workouts(in interval: DateInterval) async -> [DetectedWorkout] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: interval.start,
                end: interval.end,
                options: [.strictStartDate]
            )

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 20,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    DetectedWorkout(
                        activityName: workout.workoutActivityType.displayName,
                        startedAt: workout.startDate,
                        endedAt: workout.endDate,
                        source: workout.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: workouts)
            }

            store.execute(query)
        }
    }

    // MARK: - Private

    /// An anchored query, so each workout is only ever handed over once.
    ///
    /// The anchor is persisted: without it, every relaunch would re-deliver the
    /// entire workout history and re-tick mornings that were already settled.
    private func runAnchoredQuery() async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, _, newAnchor, _ in
                Task { @MainActor in
                    if let newAnchor {
                        self?.anchor = newAnchor
                        self?.saveAnchor(newAnchor)
                    }
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }

            store.execute(query)
        }
    }

    private func loadAnchor() {
        guard let data = defaults.data(forKey: anchorKey) else { return }
        anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ value: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: value,
            requiringSecureCoding: true
        ) else { return }
        defaults.set(data, forKey: anchorKey)
    }

    #if DEBUG
    /// Debug hooks. Compiled out of release entirely.
    func debugEmitWorkout() {
        let detected = DetectedWorkout(
            activityName: "Traditional Strength Training",
            startedAt: Date().addingTimeInterval(-45 * 60),
            endedAt: Date(),
            source: "Apple Watch"
        )
        lastDetected = detected
        onWorkout?(detected)
    }

    func debugSetAvailability(_ value: Availability) {
        availability = value
    }
    #endif
}

// MARK: - Activity names

extension HKWorkoutActivityType {
    /// A readable name for the handful of activities a gym-goer actually logs.
    ///
    /// HealthKit exposes well over seventy of these and no built-in localised
    /// name, so the common cases are named properly and everything else falls
    /// back to a neutral label rather than a raw integer.
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining: "Strength Training"
        case .functionalStrengthTraining: "Functional Strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .rowing: "Rowing"
        case .swimming: "Swimming"
        case .elliptical: "Elliptical"
        case .stairClimbing, .stairs: "Stair Climbing"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .coreTraining: "Core Training"
        case .flexibility: "Stretching"
        case .crossTraining: "Cross Training"
        case .mixedCardio: "Cardio"
        case .boxing, .kickboxing: "Boxing"
        case .climbing: "Climbing"
        default: "Workout"
        }
    }
}
