import CoreGraphics
import Foundation
import Testing
@testable import GymLock

/// The Day Dial's maths.
///
/// These rules decide what a user's morning looks like, so they are pinned to
/// numbers rather than to however the dial happens to behave on a simulator.
struct DayDialTests {
    private let centre = CGPoint(x: 150, y: 150)
    private let radius: CGFloat = 100

    private func point(at minutes: Int) -> CGPoint {
        let offset = DayDialModel.offset(minutes: minutes, radius: radius)
        return CGPoint(x: centre.x + offset.width, y: centre.y + offset.height)
    }

    // MARK: - Angle ↔ minutes

    /// All four quadrants, plus the awkward edges: exactly midnight, a few
    /// minutes past it, and one tick before it.
    @Test(arguments: [0, 5, 95, 180, 375, 540, 725, 900, 1085, 1260, 1435])
    func minutesRoundTripThroughTheAngle(minutes: Int) {
        #expect(DayDialModel.minutes(at: point(at: minutes), centre: centre) == minutes % 1440)
    }

    /// 23:58 sits two minutes before the top; its angle must snap forward to
    /// 00:00, not backwards to 23:55.
    @Test func snappingWrapsThroughMidnight() {
        #expect(DayDialModel.minutes(at: point(at: 1438), centre: centre) == 0)
        #expect(DayDialModel.snapped(1437.5) == 0)
    }

    @Test func theTopOfTheDialIsMidnight() {
        #expect(DayDialModel.minutes(at: CGPoint(x: centre.x, y: centre.y - radius), centre: centre) == 0)
    }

    // MARK: - The gym handle

    @Test func travelClampsToTheProductRange() {
        #expect(DayDialModel.travelMinutes(desiredWindow: 200, getReadyMinutes: 20) == 60)
        #expect(DayDialModel.travelMinutes(desiredWindow: 5, getReadyMinutes: 20) == 0)
        #expect(DayDialModel.travelMinutes(desiredWindow: 45, getReadyMinutes: 20) == 25)
    }

    /// Even a wildly out-of-range drag must land inside the travel range and
    /// inside the window ceiling. The clamp is the guardrail, so it cannot
    /// itself be escaped.
    @Test func theClampAlwaysHolds() {
        for desired in stride(from: -120, through: 1440, by: 30) {
            let travel = DayDialModel.travelMinutes(desiredWindow: desired, getReadyMinutes: 60)
            #expect(MorningRhythm.travelRange.contains(travel))
            #expect(60 + travel <= MorningRhythm.absoluteMaximumWindow)
        }
    }

    /// Moving the sun handle moves wake time; the gym arc must follow it
    /// rigidly, which it can only do if the window never changes underneath.
    @Test func movingWakeTimePreservesTheWindow() {
        var rhythm = MorningRhythm.default
        let windowBefore = rhythm.windowMinutes

        rhythm.wakeTime = TimeOfDay(hour: 7, minute: 45)
        rhythm.bedtime = TimeOfDay(hour: 0, minute: 15)

        #expect(rhythm.windowMinutes == windowBefore)
    }

    // MARK: - Sleep across midnight

    @Test func sleepAcrossMidnightIsPositive() {
        // 23:00 to 06:30 is seven and a half hours, not a negative number.
        #expect(MorningRhythm.default.sleepMinutes == 450)
    }

    @Test func sleepAfterAMidnightBedtimeStillAddsUp() {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = TimeOfDay(hour: 1, minute: 0)
        rhythm.wakeTime = TimeOfDay(hour: 9, minute: 0)
        #expect(rhythm.sleepMinutes == 480)
    }

    // MARK: - Rubber-band

    @Test func rubberbandResistsWithoutHardStopping() {
        let small = DayDialModel.rubberband(10, dimension: 300)
        let large = DayDialModel.rubberband(400, dimension: 300)

        #expect(small > 0)
        #expect(large > small)
        // Progressive resistance: the visual overshoot never reaches the raw
        // distance the finger travelled past the limit.
        #expect(large < 400)
    }

    // MARK: - Momentum projection

    @Test func aFlickClockwiseProjectsForward() {
        // At the top of the dial, clockwise (later) runs toward +x.
        let projected = DayDialModel.projectedMinutes(
            translation: CGSize(width: 100, height: 0),
            handleAngleDegrees: 0,
            radius: 120
        )
        #expect(projected > 0)
    }

    @Test func aFlickCounterClockwiseProjectsBackward() {
        let projected = DayDialModel.projectedMinutes(
            translation: CGSize(width: -100, height: 0),
            handleAngleDegrees: 0,
            radius: 120
        )
        #expect(projected < 0)
    }

    @Test func aStationaryLiftProjectsNothing() {
        #expect(
            DayDialModel.projectedMinutes(
                translation: .zero,
                handleAngleDegrees: 90,
                radius: 120
            ) == 0
        )
    }
}
