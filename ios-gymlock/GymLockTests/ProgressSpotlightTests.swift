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

    // MARK: Presentation refinements

    @Test func dismissingDuringTravelCancelsTheLanding() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        #expect(spotlight.startTravel(animated: true))
        spotlight.dismiss()

        try await Task.sleep(for: .milliseconds(600))

        #expect(spotlight.phase == .inactive)
        #expect(!spotlight.isRevealed)
        #expect(spotlight.focusCount == 0)
    }

    @Test func aRequestLandsOnceAndTravelsOnce() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        #expect(spotlight.startTravel(animated: false))
        #expect(!spotlight.startTravel(animated: false))

        try await Task.sleep(for: .milliseconds(300))
        #expect(spotlight.phase == .focused)
        #expect(spotlight.isRevealed)
        #expect(!spotlight.startTravel(animated: false))

        try await Task.sleep(for: .milliseconds(200))
        #expect(spotlight.focusCount == 1)
    }

    @Test func cardMovementNeverLandsASecondTime() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        spotlight.startTravel(animated: false)
        for step in 0..<5 {
            spotlight.cardMoved(to: CGRect(x: 20, y: 500 - CGFloat(step) * 20, width: 350, height: 280))
        }
        try await Task.sleep(for: .milliseconds(400))
        #expect(spotlight.focusCount == 1)

        // Layout keeps changing after landing: no new landing, no new haptic.
        for step in 0..<5 {
            spotlight.cardMoved(to: CGRect(x: 20, y: 400 + CGFloat(step), width: 350, height: 280))
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(spotlight.focusCount == 1)
        #expect(spotlight.cardFrame == CGRect(x: 20, y: 404, width: 350, height: 280))
    }

    @Test func aNewNotificationRearmsTheOneShotGuards() async throws {
        let spotlight = ProgressSpotlightModel()
        spotlight.arm(day: today)
        spotlight.startTravel(animated: false)
        try await Task.sleep(for: .milliseconds(300))
        spotlight.dismiss()

        spotlight.arm(day: today)
        #expect(!spotlight.isRevealed)
        #expect(spotlight.startTravel(animated: false))
        try await Task.sleep(for: .milliseconds(300))
        #expect(spotlight.focusCount == 2)
    }

    @Test func travelWithoutASpotlightDoesNothing() {
        let spotlight = ProgressSpotlightModel()
        #expect(!spotlight.startTravel(animated: true))
        #expect(spotlight.phase == .inactive)
    }

    /// The screenshot bug: an overlay canvas that does not start at the
    /// space's origin (safe-area shifted) must still put the hole exactly on
    /// the card.
    @Test func theHoleMatchesTheCardWhenTheCanvasIsShifted() {
        let card = CGRect(x: 20, y: 512, width: 350, height: 296)

        // Canvas extended under a 59 pt status bar: it starts above the space.
        let underStatusBar = CGPoint(x: 0, y: -59)
        let hole = ProgressSpotlightModel.localHole(cardFrame: card, canvasOrigin: underStatusBar)
        #expect(hole == CGRect(x: 20, y: 571, width: 350, height: 296))
        // Drawn back at the canvas origin, it lands on the card again.
        #expect(hole.offsetBy(dx: underStatusBar.x, dy: underStatusBar.y) == card)

        // A canvas that coincides with the space leaves the frame untouched.
        #expect(ProgressSpotlightModel.localHole(cardFrame: card, canvasOrigin: .zero) == card)
    }

    @Test func noOutsideRegionTouchesTheCardAtAnyHeight() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        for top in stride(from: CGFloat(80), through: 520, by: 40) {
            let card = CGRect(x: 20, y: top, width: 350, height: 296)
            let regions = ProgressSpotlightModel.outsideRegions(around: card, in: bounds)
            #expect(regions.allSatisfy { $0.intersection(card).isEmpty })
            let covered = regions.reduce(0) { $0 + $1.width * $1.height } + card.width * card.height
            #expect(covered == bounds.width * bounds.height)
        }
    }
}
