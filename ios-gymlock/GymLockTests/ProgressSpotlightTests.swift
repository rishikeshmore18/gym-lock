import Foundation
import CoreGraphics
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

    @Test func theOutsideRegionsLeaveTheCardUncovered() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let card = CGRect(x: 20, y: 400, width: 350, height: 280)
        let regions = ProgressSpotlightModel.outsideRegions(around: card, in: bounds)

        #expect(regions.count == 4)
        #expect(regions.allSatisfy { !$0.intersects(card) })
        let covered = regions.reduce(0) { $0 + $1.width * $1.height } + card.width * card.height
        #expect(covered == bounds.width * bounds.height)
    }

    @Test func withNoCardTheWholeScreenDismisses() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        #expect(ProgressSpotlightModel.outsideRegions(around: .zero, in: bounds) == [bounds])
    }
}
