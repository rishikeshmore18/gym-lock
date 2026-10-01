import Testing
@testable import GymLock

@MainActor
struct LaunchCoverTests {
    @Test func startsCoveringAndHoldsTheApp() {
        let cover = LaunchCover(timing: .standard, startsClock: false)
        #expect(cover.phase == .covering)
        #expect(cover.isHoldingApp)
        #expect(cover.isVisible)
    }

    @Test func readyContentStillWaitsForTheMinimum() {
        let cover = LaunchCover(timing: .standard, startsClock: false)
        cover.contentIsReady()
        #expect(cover.phase == .covering)
        cover.minimumElapsed()
        #expect(cover.phase == .revealing)
        #expect(!cover.isHoldingApp)
    }

    @Test func theMinimumAloneDoesNotRevealUnfinishedContent() {
        let cover = LaunchCover(timing: .standard, startsClock: false)
        cover.minimumElapsed()
        #expect(cover.phase == .covering)
        cover.contentIsReady()
        #expect(cover.phase == .revealing)
    }

    @Test func theDeadlineRevealsEvenWhenContentIsNotReady() {
        let cover = LaunchCover(timing: .standard, startsClock: false)
        cover.minimumElapsed()
        cover.deadlinePassed()
        #expect(cover.phase == .revealing)
    }

    @Test func aLiveMorningRevealsAtOnceWithNoMinimum() {
        let cover = LaunchCover(timing: .standard, startsClock: false)
        cover.yieldToMorning()
        #expect(cover.phase == .revealing)
    }

    @Test func backgroundingFinishesAndNothingBringsItBack() {
        let cover = LaunchCover(timing: .standard, startsClock: false)
        cover.finishImmediately()
        cover.contentIsReady()
        cover.minimumElapsed()
        cover.deadlinePassed()
        cover.yieldToMorning()
        #expect(cover.phase == .finished)
        #expect(!cover.isVisible)
        #expect(!cover.isHoldingApp)
    }

    @Test func theRevealLeavesTheHierarchyAfterItsFade() async {
        let timing = LaunchCover.Timing(minimum: .zero, deadline: .seconds(10), exit: .milliseconds(20))
        let cover = LaunchCover(timing: timing, startsClock: false)
        cover.yieldToMorning()
        #expect(cover.isVisible)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(cover.phase == .finished)
    }

    @Test func theClockRevealsByItsDeadlineWithoutContent() async {
        let timing = LaunchCover.Timing(minimum: .milliseconds(10), deadline: .milliseconds(30), exit: .milliseconds(10))
        let cover = LaunchCover(timing: timing, startsClock: true)
        try? await Task.sleep(for: .milliseconds(500))
        #expect(cover.phase == .finished)
    }

    @Test func theStandardTimingStaysInsideTheLaunchBudget() {
        let timing = LaunchCover.Timing.standard
        #expect(timing.minimum >= .milliseconds(650))
        #expect(timing.minimum <= .milliseconds(750))
        #expect(timing.deadline > timing.minimum)
        #expect(timing.deadline + timing.exit <= .milliseconds(1300))
    }
}
