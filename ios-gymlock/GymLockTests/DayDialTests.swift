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

    // The real dial at 320pt: a gutter radius of about 131pt, a bar 49.5pt
    // wide, a glyph 23.8pt wide, and therefore a round cap 43 minutes of arc
    // deep. Every geometry test below uses these so the numbers mean what
    // they mean on a real screen.
    private static let ring: CGFloat = 131.2
    private static let barWidth: CGFloat = 49.536
    private static let glyph: CGFloat = 23.777
    private static let cap = 43
    private static let tolerance = 86
    private static let slop = 24

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

    // MARK: - Dragging the visit around the whole day

    /// Inside the two-hour window the drag is absorbed by the window itself
    /// and nothing else moves.
    @Test func aShortDragJustWidensTheWindow() {
        let shift = DayDialModel.shiftGym(
            desiredWindow: 110,
            getReadyMinutes: 20,
            sleepMinutes: 450,
            sessionMinutes: 60
        )
        #expect(shift.windowMinutes == 110)
        #expect(shift.towMinutes == 0)
    }

    /// Past the ceiling the window stops growing and the alarm is towed
    /// instead, which is what lets the visit travel past noon rather than
    /// dying against an invisible wall two hours after the alarm.
    @Test func draggingTheVisitPastTheWindowCeilingTowsTheAlarm() {
        let shift = DayDialModel.shiftGym(
            desiredWindow: 300,
            getReadyMinutes: 20,
            sleepMinutes: 450,
            sessionMinutes: 60
        )
        #expect(shift.windowMinutes == MorningRhythm.absoluteMaximumWindow)
        #expect(shift.towMinutes == 300 - MorningRhythm.absoluteMaximumWindow)
    }

    /// The whole point: a 07:00 alarm must be able to put the gym at 16:00.
    /// The window is unchanged, so the promise the app makes about the alarm
    /// leading into the trip still holds.
    @Test func theVisitCanBeDraggedRightRoundTheDial() {
        let getReady = 20
        let session = 60
        let sleep = 450
        var towed = 0

        for desired in stride(from: 0, through: 1200, by: 15) {
            let shift = DayDialModel.shiftGym(
                desiredWindow: desired,
                getReadyMinutes: getReady,
                sleepMinutes: sleep,
                sessionMinutes: session
            )
            // Whatever is asked for, the visit ends up exactly there: the
            // window plus whatever the night was towed by.
            #expect(shift.windowMinutes + shift.towMinutes == desired)
            #expect(shift.windowMinutes <= MorningRhythm.absoluteMaximumWindow)
            if shift.towMinutes > 0 { towed += 1 }
        }

        #expect(towed > 0)
    }

    /// Towing moves the night bodily, so the user does not silently lose
    /// sleep by dragging their workout later.
    @Test func towingKeepsTheNightTheSameLength() {
        var rhythm = MorningRhythm.default
        let sleepBefore = rhythm.sleepMinutes

        let shift = DayDialModel.shiftGym(
            desiredWindow: 400,
            getReadyMinutes: rhythm.getReadyMinutes,
            sleepMinutes: sleepBefore,
            sessionMinutes: rhythm.gymSessionMinutes
        )
        rhythm.bedtime = rhythm.bedtime.offset(byMinutes: shift.towMinutes)
        rhythm.wakeTime = rhythm.wakeTime.offset(byMinutes: shift.towMinutes)

        #expect(rhythm.sleepMinutes == sleepBefore)
        #expect(rhythm.windowMinutes <= MorningRhythm.absoluteMaximumWindow)
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

    // MARK: - Drawn geometry

    /// A stroke with round caps cannot draw shorter than it is wide, so a
    /// one-hour visit occupies 86 minutes of arc even though it means 60.
    /// Everything the finger touches has to be measured against this, which
    /// is the whole reason the grab zones were landing in the wrong place.
    @Test func aShortBarIsDrawnWiderThanItsValue() {
        let drawn = DayDialModel.drawnExtent(start: 450, span: 60, capMinutes: Self.cap)
        #expect(drawn.span == 2 * Self.cap)
        // Centred on the value, so it spills equally past both ends.
        #expect(drawn.start == 480 - Self.cap)
    }

    /// A bar longer than its own caps is drawn exactly where its value says.
    @Test func aLongBarIsDrawnAtItsValue() {
        let drawn = DayDialModel.drawnExtent(start: 1380, span: 450, capMinutes: Self.cap)
        #expect(drawn.start == 1380)
        #expect(drawn.span == 450)
    }

    @Test func drawnGeometryWrapsThroughMidnight() {
        let drawn = DayDialModel.drawnExtent(start: 1430, span: 10, capMinutes: Self.cap)
        #expect(drawn.span == 2 * Self.cap)
        // 23:55 centre, minus a cap, lands before midnight rather than at a
        // negative minute.
        #expect(drawn.start == (1435 - Self.cap + 1440) % 1440)
        #expect(drawn.start < 1440)
    }

    // MARK: - How many icons a bar can carry

    private func fitsBothIcons(_ span: Int, wasShowing: Bool = false) -> Bool {
        DayDialModel.showsBothIcons(
            drawnArcLength: DayDialModel.drawnArcLength(
                spanMinutes: span,
                radius: Self.ring,
                barWidth: Self.barWidth
            ),
            barWidth: Self.barWidth,
            glyphWidth: Self.glyph,
            wasShowing: wasShowing
        )
    }

    /// The default one-hour gym visit is far too short for two icons: drawn,
    /// it is barely wider than the bar itself. Drawing both is exactly the
    /// overlap this rule exists to prevent.
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

    /// The drawn length never goes below the bar width, however short the
    /// value, because that is what a round cap does.
    @Test func drawnLengthNeverFallsBelowTheBarWidth() {
        for span in stride(from: 0, through: 120, by: 5) {
            let drawn = DayDialModel.drawnArcLength(
                spanMinutes: span,
                radius: Self.ring,
                barWidth: Self.barWidth
            )
            #expect(drawn >= Self.barWidth)
        }
    }

    @Test func arcLengthMatchesTheRing() {
        let full = DayDialModel.arcLength(minutes: 1440, radius: 100)
        #expect(abs(full - CGFloat(2 * Double.pi * 100)) < 0.001)
        #expect(DayDialModel.arcLength(minutes: 720, radius: 100) > DayDialModel.arcLength(minutes: 60, radius: 100))
    }

    // MARK: - Grabbing

    private func bar(
        _ start: Int,
        _ span: Int,
        startGrab: DayDialModel.Grab,
        endGrab: DayDialModel.Grab,
        bodyGrab: DayDialModel.Grab
    ) -> DayDialModel.Bar {
        let drawn = DayDialModel.drawnExtent(start: start, span: span, capMinutes: Self.cap)
        return DayDialModel.Bar(
            start: start,
            span: span,
            drawnStart: drawn.start,
            drawnSpan: drawn.span,
            startGrab: startGrab,
            endGrab: endGrab,
            bodyGrab: bodyGrab
        )
    }

    private func sleepBar(_ start: Int, _ span: Int) -> DayDialModel.Bar {
        bar(start, span, startGrab: .bedtime, endGrab: .wake, bodyGrab: .sleepBody)
    }

    private func gymBar(_ start: Int, _ span: Int) -> DayDialModel.Bar {
        bar(start, span, startGrab: .gymStart, endGrab: .gymEnd, bodyGrab: .gymBody)
    }

    /// A finger near an end takes that end, the middle of a bar takes the
    /// whole bar, and bare gutter takes nothing.
    @Test func aTouchGrabsWhatIsUnderIt() {
        let bedtime = 23 * 60
        let wake = 6 * 60 + 30
        let gym = 7 * 60 + 30
        // A three-hour visit, long enough to be drawn at its own value.
        let bars = [gymBar(gym, 180), sleepBar(bedtime, 450)]
        func grab(_ finger: Int) -> DayDialModel.Grab? {
            DayDialModel.grab(fingerMinutes: finger, bars: bars, tolerance: Self.tolerance, slop: 0)
        }

        #expect(grab(bedtime + 10) == .bedtime)
        #expect(grab(wake - 10) == .wake)
        #expect(grab(gym + 5) == .gymStart)
        #expect(grab(gym + 175) == .gymEnd)
        #expect(grab(2 * 60) == .sleepBody)
        #expect(grab(gym + 90) == .gymBody)
        #expect(grab(14 * 60) == nil)
    }

    /// The bug the user hit: on a one-hour visit, a finger on the visible end
    /// of the pill must resize it, not slide the whole thing. The end is
    /// where it *looks*, which is 43 minutes past the value.
    @Test func theVisibleEndOfAShortBarResizesIt() {
        let gym = 7 * 60 + 30
        let bars = [gymBar(gym, 60), sleepBar(23 * 60, 450)]
        func grab(_ finger: Int) -> DayDialModel.Grab? {
            DayDialModel.grab(fingerMinutes: finger, bars: bars, tolerance: Self.tolerance, slop: Self.slop)
        }

        // The drawn pill runs from gym-13 to gym+73 around a 60-minute value.
        #expect(grab(gym + 70) == .gymEnd)
        #expect(grab(gym - 10) == .gymStart)
        // And its middle still slides the visit.
        #expect(grab(gym + 30) == .gymBody)
    }

    /// Even the shortest pill keeps a middle third to slide by, so a visit
    /// can never become all handle and no body.
    @Test func everyBarKeepsAMiddleToSlideBy() {
        for span in stride(from: 15, through: 240, by: 15) {
            let gym = 7 * 60 + 30
            let pill = gymBar(gym, span)
            let middle = (pill.drawnStart + pill.drawnSpan / 2) % 1440
            let zone = DayDialModel.zone(fingerMinutes: middle, bar: pill, tolerance: Self.tolerance)
            #expect(zone == .body)
        }
    }

    /// A long night does not get two-hour handles: the end zones are capped
    /// at one bar width however long the bar is.
    @Test func aLongBarHasProportionateHandles() {
        let pill = sleepBar(23 * 60, 450)
        // A third of the way in is comfortably body, not an end.
        #expect(DayDialModel.zone(fingerMinutes: (23 * 60 + 150) % 1440, bar: pill, tolerance: Self.tolerance) == .body)
        // Just inside the leading cap is the bedtime end.
        #expect(DayDialModel.zone(fingerMinutes: (23 * 60 + 10) % 1440, bar: pill, tolerance: Self.tolerance) == .start)
    }

    /// An end beats a body, so where the two pills overlap the buried alarm
    /// is still reachable instead of being swallowed by the visit on top.
    @Test func aBuriedEndIsStillReachableUnderAnotherBar() {
        let wake = 6 * 60 + 30
        // A visit whose drawn pill covers the alarm end of the night.
        let bars = [gymBar(wake - 30, 60), sleepBar(23 * 60, 450)]
        #expect(
            DayDialModel.grab(fingerMinutes: wake - 5, bars: bars, tolerance: Self.tolerance, slop: 0) == .wake
        )
    }

    /// Off both pills, the nearest end wins rather than the topmost bar.
    /// Without that, the visit steals touches that plainly belong to the
    /// alarm sitting a few minutes away from it.
    @Test func aNearMissGoesToTheNearestEnd() {
        let wake = 6 * 60 + 30
        let gym = wake + 120
        let bars = [gymBar(gym, 60), sleepBar(23 * 60, 450)]
        func grab(_ finger: Int) -> DayDialModel.Grab? {
            DayDialModel.grab(fingerMinutes: finger, bars: bars, tolerance: Self.tolerance, slop: Self.slop)
        }

        #expect(grab(wake + 10) == .wake)
        // Far from everything, nothing is grabbed: a stray tap moves nothing.
        #expect(grab(14 * 60) == nil)
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
