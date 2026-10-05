import Foundation
import Testing
@testable import GymLock

/// `docs/FLOW.md`, Flow 3, "The Progress spotlight": only the workout-done
/// tap opens it, once, and closing it changes nothing but the screen.
@MainActor
struct ProgressSpotlightTests {
    private let calendar = Calendar.current

    private func makeCoordinator(suite: String = "spotlight-\(UUID().uuidString)") -> (GymSessionCoordinator, AppStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let store = AppStore(defaults: defaults)
        let coordinator = GymSessionCoordinator(defaults: defaults, shield: DemoShieldService(defaults: defaults))
        coordinator.bindStoreOnly(store)
        return (coordinator, store, defaults)
    }

    private var today: Date { calendar.startOfDay(for: Date()) }

    @Test func theWorkoutDoneRouteIsNeverAnAlarm() {
        let route = NotificationRoute(
            identifier: NotificationRoute.ID.workoutDone(day: today, visitID: UUID()),
            categoryIdentifier: ""
        )
        #expect(route == .workoutDone(day: today))
        #expect(!route.isAlarm)
        #expect(route.handoff(forAction: "com.apple.UNNotificationDefaultActionIdentifier", at: Date()) == nil)
    }

    @Test func tappingWorkoutDoneAsksForProgressWithThatDay() {
        let (coordinator, store, defaults) = makeCoordinator()
        defer { withExtendedLifetime(store) {} }
        PendingNotificationRoute.write(.workoutDone(day: today), defaults: defaults)

        coordinator.openPendingSkipScreenIfNeeded()

        #expect(coordinator.requestedTab == .progress)
        #expect(coordinator.pendingSpotlightDay == today)
        #expect(coordinator.session == nil)
        #expect(store.pendingNotificationRoute == nil)
    }

    @Test func theSpotlightTakesThePendingDayOnlyOnce() {
        let (coordinator, store, _) = makeCoordinator()
        defer { withExtendedLifetime(store) {} }
        coordinator.openProgressSpotlight(for: today)
        let spotlight = ProgressSpotlightModel()

        #expect(spotlight.accept(requestedTab: .progress, from: coordinator))
        #expect(spotlight.phase == .scrolling)
        #expect(spotlight.day == today)
        #expect(coordinator.pendingSpotlightDay == nil)

        spotlight.dismiss()
        #expect(!spotlight.accept(requestedTab: .progress, from: coordinator))
        #expect(spotlight.phase == .inactive)
    }

    @Test func openingProgressByHandShowsNoSpotlight() {
        let (coordinator, store, _) = makeCoordinator()
        defer { withExtendedLifetime(store) {} }
        let spotlight = ProgressSpotlightModel()

        #expect(!spotlight.accept(requestedTab: .progress, from: coordinator))
        #expect(!spotlight.isActive)
    }

    @Test func aConsumedSpotlightDoesNotSurviveARelaunch() {
        let suite = "spotlight-relaunch-\(UUID().uuidString)"
        let (first, firstStore, _) = makeCoordinator(suite: suite)
        first.openProgressSpotlight(for: today)
        _ = ProgressSpotlightModel().accept(requestedTab: .progress, from: first)
        withExtendedLifetime(firstStore) {}

        let (second, secondStore, _) = makeCoordinator(suite: suite)
        defer { withExtendedLifetime(secondStore) {} }
        #expect(second.pendingSpotlightDay == nil)
    }

    @Test func aColdLaunchTapStillReachesProgress() {
        let suite = "spotlight-cold-\(UUID().uuidString)"
        // The delegate writes the tap before any store or coordinator exists.
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        PendingNotificationRoute.write(.workoutDone(day: today), defaults: defaults)

        let (coordinator, store, _) = makeCoordinator(suite: suite)
        defer { withExtendedLifetime(store) {} }
        coordinator.openPendingSkipScreenIfNeeded()

        #expect(coordinator.requestedTab == .progress)
        let spotlight = ProgressSpotlightModel()
        #expect(spotlight.accept(requestedTab: .progress, from: coordinator))
        #expect(coordinator.session == nil)
    }

    @Test func otherRoutesNeverOpenTheSpotlight() {
        let (coordinator, store, defaults) = makeCoordinator()
        defer { withExtendedLifetime(store) {} }
        PendingNotificationRoute.write(.streakAtRisk, defaults: defaults)

        coordinator.openPendingSkipScreenIfNeeded()

        #expect(coordinator.requestedTab == .home)
        #expect(coordinator.pendingSpotlightDay == nil)
        let spotlight = ProgressSpotlightModel()
        #expect(!spotlight.accept(requestedTab: .home, from: coordinator))
        #expect(!spotlight.isActive)
    }

    @Test func aRequestForAnotherTabLeavesAPendingSpotlightAlone() {
        let (coordinator, store, _) = makeCoordinator()
        defer { withExtendedLifetime(store) {} }
        coordinator.openProgressSpotlight(for: today)

        #expect(!ProgressSpotlightModel().accept(requestedTab: .home, from: coordinator))
        #expect(coordinator.pendingSpotlightDay == today)
    }

    @Test func dismissingChangesNoWorkoutStreakOrPhotoData() {
        let (coordinator, store, _) = makeCoordinator()
        defer { withExtendedLifetime(store) {} }
        let photos = ProgressPhotoStore()
        coordinator.openProgressSpotlight(for: today)
        let log = store.log
        let streak = store.streak
        let photoIDs = photos.photos.map(\.id)

        let spotlight = ProgressSpotlightModel()
        spotlight.accept(requestedTab: .progress, from: coordinator)
        spotlight.dismiss()

        #expect(store.log == log)
        #expect(store.streak == streak)
        #expect(photos.photos.map(\.id) == photoIDs)
        #expect(coordinator.session == nil)
        #expect(!spotlight.isActive)
    }

    // MARK: Presentation

    @Test func dismissingDuringTravelCancelsTheLanding() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        #expect(spotlight.startTravel(animated: true))

        try await Task.sleep(for: .milliseconds(100))
        spotlight.dismiss()
        try await Task.sleep(for: .milliseconds(500))

        #expect(spotlight.phase == .inactive)
        #expect(spotlight.focusCount == 0)
    }

    @Test func theAnimatedTravelLandsAfterItHasRun() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        spotlight.startTravel(animated: true)

        try await Task.sleep(for: .milliseconds(120))
        #expect(spotlight.phase == .scrolling)

        try await Task.sleep(for: .milliseconds(400))
        #expect(spotlight.phase == .focused)
        #expect(spotlight.focusCount == 1)
    }

    @Test func aRequestLandsOnceAndTravelsOnce() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        #expect(spotlight.startTravel(animated: false))
        #expect(!spotlight.startTravel(animated: false))

        try await Task.sleep(for: .milliseconds(300))
        #expect(spotlight.phase == .focused)
        #expect(!spotlight.startTravel(animated: false))

        try await Task.sleep(for: .milliseconds(200))
        #expect(spotlight.focusCount == 1)
    }

    /// A second notification while the first is still travelling replaces
    /// it: the first request's landing must not land the second early.
    @Test func aReplacedRequestNeverLandsTheNewOne() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        spotlight.startTravel(animated: true)
        try await Task.sleep(for: .milliseconds(100))

        spotlight.arm(day: today)
        try await Task.sleep(for: .milliseconds(400))

        #expect(spotlight.phase == .scrolling)
        #expect(spotlight.focusCount == 0)
    }

    @Test func aNewNotificationRearmsTheOneShotGuards() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        spotlight.startTravel(animated: false)
        try await Task.sleep(for: .milliseconds(300))
        spotlight.dismiss()

        spotlight.arm(day: today)
        #expect(spotlight.phase == .scrolling)
        #expect(spotlight.startTravel(animated: false))
        try await Task.sleep(for: .milliseconds(300))
        #expect(spotlight.focusCount == 2)
    }

    @Test func travelWithoutASpotlightDoesNothing() {
        let spotlight = ProgressSpotlightModel()
        #expect(!spotlight.startTravel(animated: true))
        #expect(spotlight.phase == .inactive)
    }

    /// The spotlight is presentation state only: no frame, rectangle or
    /// coordinate of any kind lives in the model.
    @Test func theModelCarriesNoGeometry() {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        let labels = Mirror(reflecting: spotlight).children.compactMap(\.label)
        let geometric = labels.filter { label in
            let lowered = label.lowercased()
            return ["frame", "rect", "hole", "region", "coordinate", "origin"]
                .contains { lowered.contains($0) }
        }
        #expect(geometric.isEmpty)
        let types = Mirror(reflecting: spotlight).children.map { String(describing: type(of: $0.value)) }
        #expect(!types.contains { $0.contains("CGRect") || $0.contains("CGPoint") })
    }
}
