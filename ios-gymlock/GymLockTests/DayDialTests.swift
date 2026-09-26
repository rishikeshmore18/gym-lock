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

    /// The bar may be placed anywhere, but the lock is still a run-up: the
    /// window that actually blocks apps follows the gap only as far as the
    /// product ceiling and then stops.
    @Test func theLockWindowFollowsTheGapUpToItsCeiling() {
        #expect(DayDialModel.travelMinutes(gapMinutes: 200, getReadyMinutes: 20) == 100)
        #expect(DayDialModel.travelMinutes(gapMinutes: 5, getReadyMinutes: 20) == 0)
        #expect(DayDialModel.travelMinutes(gapMinutes: 45, getReadyMinutes: 20) == 25)
    }

    /// One of the regressions: the gym bar hit an invisible wall two hours
    /// after the alarm and could not be dragged past noon. It may now sit
    /// anywhere in the waking day, and the only thing that stops it is the
    /// night itself.
    @Test func theGymBarHasNoTwoHourWall() {
        let awake = 1440 - 450

        // Nine hours after the alarm: far beyond the old ceiling.
        #expect(DayDialModel.clampedGap(540, awakeSpan: awake, sessionMinutes: 60) == 540)
        #expect(DayDialModel.clampedGap(300, awakeSpan: awake, sessionMinutes: 60) == 300)

        // It stops where the visit would run into bedtime, not before.
        let latest = awake - 60 - DayDialModel.minimumGapMinutes
        #expect(DayDialModel.clampedGap(5000, awakeSpan: awake, sessionMinutes: 60) == latest)
        // And it keeps a few minutes of lead after the alarm.
        #expect(DayDialModel.clampedGap(0, awakeSpan: awake, sessionMinutes: 60) == DayDialModel.minimumLeadMinutes)
    }

    @Test func theGymVisitHasItsOwnLength() {
        let awake = 1440 - 450
        #expect(DayDialModel.clampedSession(90, awakeSpan: awake, gapMinutes: 35) == 90)
        #expect(DayDialModel.clampedSession(5, awakeSpan: awake, gapMinutes: 35) == MorningRhythm.sessionRange.lowerBound)
        #expect(DayDialModel.clampedSession(999, awakeSpan: awake, gapMinutes: 35) == MorningRhythm.sessionRange.upperBound)
        // A long night leaves less room for the visit.
        let squeezed = DayDialModel.clampedSession(240, awakeSpan: 1440 - 1200, gapMinutes: 35)
        #expect(squeezed == 1440 - 1200 - 35 - DayDialModel.minimumGapMinutes)
    }

    /// Every position the bar can be dragged to keeps the visit inside the
    /// waking day, ending a gap before bed. The clamp is the guardrail, so it
    /// cannot itself be escaped.
    @Test func theGapClampAlwaysHolds() {
        let awake = 1440 - 450
        for desired in stride(from: -600, through: 2000, by: 15) {
            let gap = DayDialModel.clampedGap(desired, awakeSpan: awake, sessionMinutes: 60)
            #expect(gap >= DayDialModel.minimumLeadMinutes)
            #expect(gap + 60 + DayDialModel.minimumGapMinutes <= awake)
        }
    }

    /// However far out the visit is placed, the lock window stays inside the
    /// product ceiling. A workout at noon must not mean a five-hour block.
    @Test func theLockNeverStretchesPastItsCeiling() {
        for gap in stride(from: -120, through: 1440, by: 30) {
            let travel = DayDialModel.travelMinutes(gapMinutes: gap, getReadyMinutes: 60)
            #expect(MorningRhythm.travelRange.contains(travel))
            #expect(60 + travel <= MorningRhythm.absoluteMaximumWindow)
        }
    }

    // MARK: - The two bars are independent

    /// The other regression: dragging the gym bar dragged the sleep bar with
    /// it. Placing the visit anywhere in the day must leave bedtime and the
    /// alarm exactly where they were.
    @Test func movingTheGymBarNeverMovesTheNight() {
        var rhythm = MorningRhythm.default
        rhythm.gymTime = TimeOfDay(hour: 7, minute: 30)
        let bedBefore = rhythm.bedtime
        let wakeBefore = rhythm.wakeTime
        let sleepBefore = rhythm.sleepMinutes

        for hour in 7...16 {
            rhythm.gymTime = TimeOfDay(hour: hour, minute: 0)
            #expect(rhythm.bedtime == bedBefore)
            #expect(rhythm.wakeTime == wakeBefore)
            #expect(rhythm.sleepMinutes == sleepBefore)
        }

        // And the bar really is where it was put, rather than wherever the
        // window happens to land.
        #expect(rhythm.gymByTime == TimeOfDay(hour: 16, minute: 0))
        #expect(rhythm.gymDoneTime == TimeOfDay(hour: 17, minute: 0))
    }

    /// The alarm does not take the gym bar with it either. Dragged later it
    /// stops a few minutes short of the visit rather than pushing it along.
    @Test func theAlarmStopsShortOfTheGymRatherThanPushingIt() {
        // An hour of gap to eat into.
        let later = DayDialModel.clampedWakeShift(300, sleepMinutes: 450, gapMinutes: 60)
        #expect(later == 60 - DayDialModel.minimumLeadMinutes)

        // Dragged earlier, it is the shortest allowed night that stops it.
        let earlier = DayDialModel.clampedWakeShift(-600, sleepMinutes: 450, gapMinutes: 60)
        #expect(earlier == DayDialModel.minimumSleepMinutes - 450)

        // A drag that fits is passed through untouched, so the bar tracks the
        // finger 1:1 everywhere inside the limits.
        #expect(DayDialModel.clampedWakeShift(20, sleepMinutes: 450, gapMinutes: 60) == 20)
    }

    /// Sliding the whole night is bounded at both ends by the standing gym
    /// bar: the alarm closing on it one way, bedtime closing on it the other.
    @Test func theNightSlidesUntilItReachesTheGymBar() {
        let awake = 1440 - 450
        let gap = 60
        let session = 60

        let later = DayDialModel.clampedNightShift(600, awakeSpan: awake, gapMinutes: gap, sessionMinutes: session)
        #expect(later == gap - DayDialModel.minimumLeadMinutes)

        let tail = awake - gap - session
        // Asked for further than the limit (-840 here), so the clamp shows.
        let earlier = DayDialModel.clampedNightShift(-900, awakeSpan: awake, gapMinutes: gap, sessionMinutes: session)
        #expect(earlier == DayDialModel.minimumGapMinutes - tail)

        // Whatever is asked for, the night never laps the visit.
        for desired in stride(from: -900, through: 900, by: 15) {
            let shift = DayDialModel.clampedNightShift(desired, awakeSpan: awake, gapMinutes: gap, sessionMinutes: session)
            #expect(gap - shift >= DayDialModel.minimumLeadMinutes)
        }
    }

    /// A plan saved before the gym bar had its own value still reads
    /// correctly: the bar sits at the end of the window, where it used to be
    /// drawn, so nobody's schedule moves under them on upgrade.
    @Test func aPlanWithNoStoredGymTimeFallsBackToTheWindow() {
        let rhythm = MorningRhythm.default
        #expect(rhythm.gymTime == nil)
        #expect(rhythm.gymByTime == rhythm.wakeTime.offset(byMinutes: rhythm.windowMinutes))
        #expect(rhythm.gapToGymMinutes == rhythm.windowMinutes)
    }

    // MARK: - The alarm and getting up are one decision

    /// Setting the alarm sets wake time, so the user is never asked the same
    /// question twice. Bedtime holds and the night changes length, which is
    /// what the wake handle on the dial does too.
    @Test func settingTheAlarmSetsWakeTime() {
        var rhythm = MorningRhythm.default
        let bedBefore = rhythm.bedtime

        rhythm.setWakeTime(TimeOfDay(hour: 5, minute: 30))

        #expect(rhythm.wakeTime == TimeOfDay(hour: 5, minute: 30))
        #expect(rhythm.bedtime == bedBefore)
        #expect(rhythm.sleepMinutes == 390)
    }

    /// A placed gym bar is an independent decision, so moving the alarm by
    /// hand leaves it exactly where it was put.
    @Test func settingTheAlarmLeavesThePlacedGymBarAlone() {
        var rhythm = MorningRhythm.default
        rhythm.gymTime = TimeOfDay(hour: 9, minute: 0)

        rhythm.setWakeTime(TimeOfDay(hour: 5, minute: 30))
        #expect(rhythm.gymByTime == TimeOfDay(hour: 9, minute: 0))
        #expect(rhythm.gapToGymMinutes == 210)

        // Even moving it later, while it still clears the bar.
        rhythm.setWakeTime(TimeOfDay(hour: 8, minute: 0))
        #expect(rhythm.gymByTime == TimeOfDay(hour: 9, minute: 0))
    }

    /// The one exception, and it is a repair rather than towing: an alarm set
    /// on or past the visit would leave a gap reading as most of a day. The
    /// visit comes along keeping the gap it had, so the plan stays sane.
    @Test func anAlarmSetPastTheGymCarriesTheVisitWithIt() {
        var rhythm = MorningRhythm.default
        rhythm.wakeTime = TimeOfDay(hour: 6, minute: 30)
        rhythm.gymTime = TimeOfDay(hour: 7, minute: 30)

        rhythm.setWakeTime(TimeOfDay(hour: 10, minute: 0))

        #expect(rhythm.gapToGymMinutes == 60)
        #expect(rhythm.gymByTime == TimeOfDay(hour: 11, minute: 0))
    }

    /// However the alarm is moved, the plan that comes out is always readable:
    /// the gym is after the alarm, with room to spare, and never the long way
    /// round the clock.
    @Test func theGapStaysSaneWhateverTheAlarmIsSetTo() {
        for hour in 0...23 {
            var rhythm = MorningRhythm.default
            rhythm.gymTime = TimeOfDay(hour: 7, minute: 30)
            rhythm.setWakeTime(TimeOfDay(hour: hour, minute: 0))

            #expect(rhythm.gapToGymMinutes >= MorningRhythm.minimumGymLead)
            #expect(rhythm.gapToGymMinutes <= MorningRhythm.maximumSaneGapMinutes)
        }
    }

    /// A bar that was never placed follows the window on its own, so nothing
    /// needs pinning and the old behaviour is untouched.
    @Test func anUnplacedGymBarStillFollowsTheAlarm() {
        var rhythm = MorningRhythm.default
        rhythm.setWakeTime(TimeOfDay(hour: 5, minute: 0))

        #expect(rhythm.gymTime == nil)
        #expect(rhythm.gymByTime == TimeOfDay(hour: 5, minute: 0).offset(byMinutes: rhythm.windowMinutes))
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
        #expect(DayDialModel.clampedSleep(20, gapMinutes: 45, sessionMinutes: 60) == DayDialModel.minimumSleepMinutes)
        let longest = DayDialModel.maximumSleepMinutes(gapMinutes: 45, sessionMinutes: 60)
        #expect(DayDialModel.clampedSleep(1400, gapMinutes: 45, sessionMinutes: 60) == longest)
        #expect(longest + 45 + 60 + DayDialModel.minimumGapMinutes == 1440)
        #expect(DayDialModel.clampedSleep(450, gapMinutes: 45, sessionMinutes: 60) == 450)
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
