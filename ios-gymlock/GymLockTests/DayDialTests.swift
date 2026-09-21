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

    // MARK: - Angle to minutes

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

    // MARK: - The gym bar

    @Test func travelClampsToTheProductRange() {
        // The ceiling is the two-hour window, not an arbitrary travel cap.
        #expect(DayDialModel.travelMinutes(desiredWindow: 200, getReadyMinutes: 20) == 100)
        #expect(DayDialModel.travelMinutes(desiredWindow: 5, getReadyMinutes: 20) == 0)
        #expect(DayDialModel.travelMinutes(desiredWindow: 45, getReadyMinutes: 20) == 25)
    }

    /// The gym bar can be dragged anywhere the dial has room for it; the only
    /// hard limits are the two-hour window and the space left by the night.
    @Test func theGymWindowIsOnlyLimitedByTheDayAndTheCeiling() {
        let wide = DayDialModel.clampedWindow(110, getReadyMinutes: 20, sleepMinutes: 450, sessionMinutes: 60)
        #expect(wide == 110)
        let tooWide = DayDialModel.clampedWindow(300, getReadyMinutes: 20, sleepMinutes: 450, sessionMinutes: 60)
        #expect(tooWide == MorningRhythm.absoluteMaximumWindow)
        let tooShort = DayDialModel.clampedWindow(3, getReadyMinutes: 20, sleepMinutes: 450, sessionMinutes: 60)
        #expect(tooShort == 20)
    }

    @Test func theGymVisitHasItsOwnLength() {
        #expect(DayDialModel.clampedSession(90, sleepMinutes: 450, windowMinutes: 35) == 90)
        #expect(DayDialModel.clampedSession(5, sleepMinutes: 450, windowMinutes: 35) == MorningRhythm.sessionRange.lowerBound)
        #expect(DayDialModel.clampedSession(999, sleepMinutes: 450, windowMinutes: 35) == MorningRhythm.sessionRange.upperBound)
        // A long night leaves less room for the visit.
        let squeezed = DayDialModel.clampedSession(240, sleepMinutes: 1200, windowMinutes: 35)
        #expect(squeezed == 1440 - 1200 - 35 - DayDialModel.minimumGapMinutes)
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

    /// Moving the alarm end moves wake time; the gym bar must follow it
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

    // MARK: - How many icons a bar can carry

    // The real dial at 320pt: a gutter radius of about 131pt, a bar 49pt
    // wide, and a glyph 24pt wide.
    private static let ring: CGFloat = 131
    private static let barWidth: CGFloat = 49
    private static let glyph: CGFloat = 24

    private func fitsBothIcons(_ span: Int, wasShowing: Bool = false) -> Bool {
        DayDialModel.showsBothIcons(
            spanMinutes: span,
            radius: Self.ring,
            barWidth: Self.barWidth,
            glyphWidth: Self.glyph,
            wasShowing: wasShowing
        )
    }

    /// The default one-hour gym visit is far too short for two icons: its arc
    /// is narrower than the bar is wide. Drawing both is exactly the overlap
    /// this rule exists to prevent.
    @Test func aShortBarCarriesOnlyOneIcon() {
        #expect(fitsBothIcons(60) == false)
        #expect(fitsBothIcons(90) == false)
    }

    /// A full night has room to spare, so bed and alarm both show.
    @Test func aLongBarCarriesBothIcons() {
        #expect(fitsBothIcons(450))
        #expect(fitsBothIcons(300))
    }

    /// Dragging back and forth across the threshold must not strobe the
    /// second icon, so appearing costs more room than staying does.
    @Test func theSecondIconDoesNotFlickerAtTheThreshold() throws {
        let appearsAt = try #require(
            stride(from: 60, through: 600, by: 5).first { fitsBothIcons($0) }
        )

        // One step below the appearing threshold: stays out if it was out,
        // stays in if it was already in.
        #expect(fitsBothIcons(appearsAt - 5, wasShowing: false) == false)
        #expect(fitsBothIcons(appearsAt - 5, wasShowing: true))
    }

    @Test func arcLengthMatchesTheRing() {
        let full = DayDialModel.arcLength(minutes: 1440, radius: 100)
        #expect(abs(full - CGFloat(2 * Double.pi * 100)) < 0.001)
        #expect(DayDialModel.arcLength(minutes: 720, radius: 100) > DayDialModel.arcLength(minutes: 60, radius: 100))
    }

    // MARK: - Grabbing

    private func sleepBar(_ start: Int, _ span: Int, showsBothIcons: Bool = true) -> DayDialModel.Bar {
        DayDialModel.Bar(
            start: start,
            span: span,
            startGrab: .bedtime,
            endGrab: .wake,
            bodyGrab: .sleepBody,
            showsBothIcons: showsBothIcons
        )
    }

    private func gymBar(_ start: Int, _ span: Int, showsBothIcons: Bool) -> DayDialModel.Bar {
        DayDialModel.Bar(
            start: start,
            span: span,
            startGrab: .gymStart,
            endGrab: .gymEnd,
            bodyGrab: .gymBody,
            showsBothIcons: showsBothIcons
        )
    }

    /// A finger near an end takes that end, the middle of a bar takes the
    /// whole bar, and bare gutter takes nothing.
    @Test func aTouchGrabsWhatIsUnderIt() {
        let bedtime = 23 * 60
        let wake = 6 * 60 + 30
        let gym = 7 * 60 + 30
        // A three-hour visit, long enough for the gym bar to show both ends.
        let bars = [gymBar(gym, 180, showsBothIcons: true), sleepBar(bedtime, 450)]
        func grab(_ finger: Int) -> DayDialModel.Grab? {
            DayDialModel.grab(fingerMinutes: finger, bars: bars, tolerance: 20)
        }

        #expect(grab(bedtime + 10) == .bedtime)
        #expect(grab(wake - 10) == .wake)
        #expect(grab(gym + 5) == .gymStart)
        #expect(grab(gym + 175) == .gymEnd)
        #expect(grab(2 * 60) == .sleepBody)
        #expect(grab(gym + 90) == .gymBody)
        #expect(grab(14 * 60) == nil)
    }

    /// A collapsed bar is a handle: anywhere inside the pill slides the whole
    /// thing, rather than resizing an end that has no icon to show for it.
    @Test func aCollapsedBarSlidesFromAnywhereInside() {
        let gym = 7 * 60 + 30
        let bars = [gymBar(gym, 60, showsBothIcons: false), sleepBar(23 * 60, 450)]
        func grab(_ finger: Int) -> DayDialModel.Grab? {
            DayDialModel.grab(fingerMinutes: finger, bars: bars, tolerance: 85)
        }

        #expect(grab(gym) == .gymBody)
        #expect(grab(gym + 5) == .gymBody)
        #expect(grab(gym + 30) == .gymBody)
        #expect(grab(gym + 60) == .gymBody)
    }

    /// Its length stays reachable from just past either cap, which is the
    /// only room left once the inside belongs to the body.
    @Test func aCollapsedBarResizesFromJustOutsideIt() {
        let gym = 7 * 60 + 30
        let bars = [gymBar(gym, 60, showsBothIcons: false), sleepBar(23 * 60, 450)]
        func grab(_ finger: Int) -> DayDialModel.Grab? {
            DayDialModel.grab(fingerMinutes: finger, bars: bars, tolerance: 85)
        }

        #expect(grab(gym + 90) == .gymEnd)
        #expect(grab(gym - 20) == .gymStart)
        // Far beyond the reach of either end, nothing is grabbed.
        #expect(grab(gym + 400) == nil)
    }

    /// The empty window between the alarm and the gym is split down the
    /// middle: nearer the alarm takes the alarm, nearer the gym takes the
    /// gym. Without that, a generous tolerance lets the gym steal the alarm.
    @Test func theGapBetweenTwoBarsIsSplitByWhicheverEndIsNearer() {
        let wake = 6 * 60 + 30
        let gym = wake + 40
        let bars = [gymBar(gym, 60, showsBothIcons: false), sleepBar(23 * 60, 450)]
        func grab(_ finger: Int) -> DayDialModel.Grab? {
            DayDialModel.grab(fingerMinutes: finger, bars: bars, tolerance: 85)
        }

        #expect(grab(wake + 5) == .wake)
        #expect(grab(gym - 5) == .gymStart)
    }

    /// On a genuine tie the gym bar wins, because it is the one drawn on top.
    @Test func theGymEndWinsATieWithWake() {
        let wake = 6 * 60 + 30
        let gym = wake + 20
        let bars = [gymBar(gym, 60, showsBothIcons: false), sleepBar(23 * 60, 450)]
        #expect(DayDialModel.grab(fingerMinutes: wake + 10, bars: bars, tolerance: 85) == .gymStart)
    }

    /// An expanded bar keeps its middle third for sliding, so a long night is
    /// never all handle and no body.
    @Test func anExpandedBarKeepsAMiddleToSlideBy() {
        let bars = [sleepBar(23 * 60, 450, showsBothIcons: true)]
        #expect(DayDialModel.grab(fingerMinutes: (23 * 60 + 225) % 1440, bars: bars, tolerance: 600) == .sleepBody)
    }

    /// A finger crossing midnight is a small step, not a jump of a day.
    @Test func deltasWrapThroughMidnight() {
        #expect(DayDialModel.wrappedDelta(from: 1435, to: 5) == 10)
        #expect(DayDialModel.wrappedDelta(from: 5, to: 1435) == -10)
        #expect(DayDialModel.wrappedDelta(from: 0, to: 720) == 720)
    }

    /// The two bars share one gutter, so the night can never be dragged over
    /// the gym window, and never shorter than the icons need.
    @Test func sleepIsClampedSoTheBarsNeverLap() {
        #expect(DayDialModel.clampedSleep(20, windowMinutes: 45, sessionMinutes: 60) == DayDialModel.minimumSleepMinutes)
        let longest = DayDialModel.maximumSleepMinutes(windowMinutes: 45, sessionMinutes: 60)
        #expect(DayDialModel.clampedSleep(1400, windowMinutes: 45, sessionMinutes: 60) == longest)
        #expect(longest + 45 + 60 + DayDialModel.minimumGapMinutes == 1440)
        #expect(DayDialModel.clampedSleep(450, windowMinutes: 45, sessionMinutes: 60) == 450)
    }

    // MARK: - Next alarm only

    /// A one-off change stands in for the weekly ring on its day and then
    /// gets out of the way.
    @Test func aOneOffAlarmReplacesTheNextRingOnly() throws {
        var plan = MorningPlan.default
        let slot = AlarmSlot(days: Set(Weekday.allCases), alarmTime: TimeOfDay(hour: 6, minute: 30))
        plan.slots = [slot]

        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12)))
        let tomorrow = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 5, minute: 45)))

        var oneOff = plan.rhythm
        oneOff.wakeTime = TimeOfDay(hour: 5, minute: 45)
        plan.nextAlarmOverride = NextAlarmOverride(slotID: slot.id, fireDate: tomorrow, rhythm: oneOff)

        let next = try #require(plan.nextOccurrence(after: now, calendar: calendar))
        #expect(next.fireDate == tomorrow)
        #expect(next.slot.alarmTime == TimeOfDay(hour: 5, minute: 45))
        #expect(plan.rhythm(at: tomorrow, calendar: calendar).wakeTime == TimeOfDay(hour: 5, minute: 45))
        #expect(plan.slot(forAlarmID: plan.nextAlarmOverride?.id)?.id == slot.id)

        // The schedule itself is untouched, and the day after is back to normal.
        #expect(plan.rhythm.wakeTime == TimeOfDay(hour: 6, minute: 30))
        let afterwards = try #require(calendar.date(byAdding: .day, value: 1, to: tomorrow))
        #expect(plan.rhythm(at: afterwards, calendar: calendar).wakeTime == TimeOfDay(hour: 6, minute: 30))
        #expect(plan.activeOverride(at: afterwards) == nil)
    }

    /// Plans saved before the workout length existed still decode.
    @Test func oldPlansDecodeWithADefaultVisitLength() throws {
        let json = """
        {"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":6,"minute":30},"getReadyMinutes":20,"travelMinutes":15,"hasBeenSet":true}
        """
        let rhythm = try JSONDecoder().decode(MorningRhythm.self, from: Data(json.utf8))
        #expect(rhythm.gymSessionMinutes == 60)
        #expect(rhythm.gymDoneTime == TimeOfDay(hour: 8, minute: 5))
    }

    @Test func durationsReadLikeApplesSleepSchedule() {
        #expect(DayDialModel.durationText(minutes: 495) == "8 hr 15 min")
        #expect(DayDialModel.durationText(minutes: 480) == "8 hr")
        #expect(DayDialModel.durationText(minutes: 45) == "45 min")
    }
}
