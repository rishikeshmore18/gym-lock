import Foundation
import Testing
@testable import GymLock

/// `docs/FLOW.md` items 1 (without the background extension), 2 and the
/// after-midnight half of 4.
@MainActor
struct SleepRulesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    /// Monday 9 March 2026 is day 9; Tuesday is 10, Wednesday 11.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func rhythm(bed: TimeOfDay, wake: TimeOfDay) -> MorningRhythm {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = bed
        rhythm.wakeTime = wake
        return rhythm
    }

    private let monWedFri: Set<Weekday> = [.monday, .wednesday, .friday]

    // MARK: - Required nights

    @Test func anOvernightScheduleProtectsTheNightsBeforeGymDays() {
        let required = SleepSchedule.requiredNights(gymDays: monWedFri, bedtime: t(23), wake: t(7))
        #expect(required == [.sunday, .tuesday, .thursday])
    }

    @Test func anAfterMidnightScheduleProtectsTheGymDaysOwnNights() {
        let required = SleepSchedule.requiredNights(gymDays: monWedFri, bedtime: t(0, 30), wake: t(8, 30))
        #expect(required == monWedFri)
    }

    @Test func theRefusalNoteKeepsItsWordingAfterMidnight() {
        let outcome = SleepSchedule.toggle(.monday, chosen: [], gymDays: [.monday], bedtime: t(0, 30), wake: t(8, 30))
        #expect(outcome == .required(night: .monday, gymDay: .monday))
        #expect(SleepSchedule.requiredMessage(night: .monday, gymDay: .monday)
            == "monday is a gym day. keep monday night on for rest.")
    }

    @Test func mondaysAfterMidnightNightLocksEvenWhenSwitchedOff() {
        var plan = MorningPlan.default
        plan.rhythm = rhythm(bed: t(0, 30), wake: t(8, 30))
        plan.slots = [AlarmSlot(days: monWedFri, alarmTime: t(8, 30))]
        plan.sleepScheduleDays = []

        // Monday 01:00 is inside the night that started Monday 00:30.
        #expect(plan.nightLockWindow(at: date(day: 9, 1), calendar: calendar) != nil)
        // Tuesday isn't a gym day and was switched off.
        #expect(plan.nightLockWindow(at: date(day: 10, 1), calendar: calendar) == nil)
    }

    // MARK: - The gym bar pushes the night

    @Test func theFlowExamplePushesSleepTo0030Through0830() {
        // Sleep 23:00 -> 07:00, a 60-minute visit dragged to 23:00.
        let wake = 7 * 60
        let awake = 1440 - 480
        let desiredGap = 23 * 60 - wake

        let push = DayDialModel.pushedGymBody(desiredGap: desiredGap, awakeSpan: awake, sessionMinutes: 60)
        #expect(push.nightShift == 90)
        #expect(push.overshoot == 0)

        let newWake = t(7).offset(byMinutes: push.nightShift)
        let newBed = t(23).offset(byMinutes: push.nightShift)
        let gym = newWake.offset(byMinutes: push.gapMinutes)
        #expect(newBed == t(0, 30))
        #expect(newWake == t(8, 30))
        #expect(gym == t(23))
        #expect(DayDialModel.pushMessage(bedtime: newBed, wake: newWake)
            == "moved your sleep to 00:30\u{2013}08:30 so it starts after the gym.")
    }

    @Test func aPushKeepsTheNightsLengthAndThirtyMinutesOfTravel() {
        let awake = 1440 - 480
        for desired in stride(from: 870, through: 1400, by: 25) {
            let push = DayDialModel.pushedGymBody(desiredGap: desired, awakeSpan: awake, sessionMinutes: 60)
            // The night only moves, it never stretches: awake span is fixed,
            // and the visit ends exactly 30 minutes before the new bedtime.
            #expect(push.gapMinutes + 60 + DayDialModel.minimumGapMinutes == awake)
            #expect(push.nightShift == desired - push.gapMinutes)
        }
    }

    @Test func aVisitThatFitsDoesNotPush() {
        let push = DayDialModel.pushedGymBody(desiredGap: 300, awakeSpan: 960, sessionMinutes: 60)
        #expect(push.nightShift == 0)
        #expect(push.gapMinutes == 300)
    }

    @Test func thePushStopsWhenTheRingIsFull() {
        // A 22-hour night leaves no room for a 2-hour visit plus travel.
        let push = DayDialModel.pushedGymBody(desiredGap: 500, awakeSpan: 140, sessionMinutes: 120)
        #expect(push.nightShift == 0)
        #expect(push.overshoot > 0)
    }

    @Test func lengtheningTheVisitPushesUntilTheAlarmReachesIt() {
        // 60 minutes after the alarm, visit ends at bedtime minus travel.
        let awake = 960
        let gap = awake - 60 - DayDialModel.minimumGapMinutes
        let push = DayDialModel.pushedGymEnd(desiredSession: 120, awakeSpan: awake, gapMinutes: gap)
        #expect(push.sessionMinutes == 120)
        #expect(push.nightShift == 60)
        #expect(push.gapMinutes == gap - 60)

        // With only 20 minutes of gap, it can push just 10 before the alarm
        // would sit on the visit.
        let tight = DayDialModel.pushedGymEnd(desiredSession: 240, awakeSpan: 20 + 60 + 30, gapMinutes: 20)
        #expect(tight.nightShift == 20 - DayDialModel.minimumLeadMinutes)
        #expect(tight.overshoot > 0)
    }

    // MARK: - Five hours minimum

    @Test func sleepUnderFiveHoursIsRefused() {
        #expect(DayDialModel.minimumSleepMinutes == 300)
        #expect(DayDialModel.clampedSleep(295, gapMinutes: 45, sessionMinutes: 60) == 300)
        #expect(DayDialModel.clampedSleep(300, gapMinutes: 45, sessionMinutes: 60) == 300)

        #expect(!MorningRhythm.meetsSleepMinimum(bedtime: t(23), wake: t(3, 55)))
        #expect(MorningRhythm.meetsSleepMinimum(bedtime: t(23), wake: t(4)))
        #expect(!rhythm(bed: t(23), wake: t(3, 55)).meetsSleepMinimum)
        #expect(rhythm(bed: t(23), wake: t(4)).meetsSleepMinimum)
        #expect(MorningRhythm.sleepMinimumMessage == "the sleep schedule must be at least 5 hours.")
    }

    // MARK: - A new bedtime starts tomorrow night

    private func planWith(bed: TimeOfDay, wake: TimeOfDay) -> MorningPlan {
        var plan = MorningPlan.default
        plan.rhythm = rhythm(bed: bed, wake: wake)
        return plan
    }

    @Test func aBedtimeChangedTuesdayEveningStartsWednesdayNight() {
        var plan = planWith(bed: t(23), wake: t(7))
        plan.applyRhythmChange(rhythm(bed: t(23, 30), wake: t(7)), now: date(day: 10, 22), calendar: calendar)

        #expect(plan.rhythm.bedtime == t(23))
        #expect(plan.pendingBedtime?.bedtime == t(23, 30))
        #expect(plan.scheduledRhythm.bedtime == t(23, 30))

        // Tuesday 23:15: tonight still locks at the old 23:00.
        #expect(plan.nightLockWindow(at: date(day: 10, 23, 15), calendar: calendar) != nil)
        // Wednesday 23:15: the new 23:30 bedtime is in force.
        #expect(plan.nightLockWindow(at: date(day: 11, 23, 15), calendar: calendar) == nil)
        #expect(plan.nightLockWindow(at: date(day: 11, 23, 45), calendar: calendar) != nil)
    }

    @Test func dodgingTonightWithA3amBedtimeDoesNotWork() {
        var plan = planWith(bed: t(23), wake: t(7))
        plan.applyRhythmChange(rhythm(bed: t(3), wake: t(7)), now: date(day: 10, 22, 55), calendar: calendar)
        #expect(plan.nightLockWindow(at: date(day: 10, 23, 30), calendar: calendar) != nil)
        #expect(plan.nightLockWindow(at: date(day: 11, 1), calendar: calendar) != nil)
    }

    @Test func aChangeFromInsideTheWindowLeavesTonightAlone() {
        var plan = planWith(bed: t(23), wake: t(7))
        // Wednesday 01:00, inside Tuesday's night.
        plan.applyRhythmChange(rhythm(bed: t(2), wake: t(7)), now: date(day: 11, 1), calendar: calendar)
        #expect(plan.nightLockWindow(at: date(day: 11, 1, 30), calendar: calendar) != nil)
        // Wednesday night now starts at 02:00 Thursday.
        #expect(plan.nightLockWindow(at: date(day: 11, 23, 30), calendar: calendar) == nil)
        #expect(plan.nightLockWindow(at: date(day: 12, 2, 30), calendar: calendar) != nil)
    }

    @Test func thePendingBedtimeFoldsInOnceTonightIsOver() {
        var plan = planWith(bed: t(23), wake: t(7))
        plan.applyRhythmChange(rhythm(bed: t(23, 30), wake: t(7)), now: date(day: 10, 22), calendar: calendar)

        // Bound first: `#expect` can't call a mutating method inside its closure.
        let beforeMorning = plan.applyDuePendingBedtime(now: date(day: 11, 6, 59))
        let atWake = plan.applyDuePendingBedtime(now: date(day: 11, 7))
        #expect(!beforeMorning)
        #expect(atWake)
        #expect(plan.rhythm.bedtime == t(23, 30))
        #expect(plan.pendingBedtime == nil)
    }

    @Test func wakeTimeChangesApplyAtOnce() {
        var plan = planWith(bed: t(23), wake: t(7))
        plan.applyRhythmChange(rhythm(bed: t(23), wake: t(6)), now: date(day: 10, 22), calendar: calendar)
        #expect(plan.rhythm.wakeTime == t(6))
        #expect(plan.pendingBedtime == nil)
    }

    @Test func theFirstBedtimeAppliesAtOnce() {
        var plan = planWith(bed: t(23), wake: t(7))
        plan.applyRhythmChange(rhythm(bed: t(22), wake: t(7)), now: date(day: 10, 21), calendar: calendar, immediately: true)
        #expect(plan.rhythm.bedtime == t(22))
        #expect(plan.pendingBedtime == nil)
    }

    @Test func settingTheBedtimeBackCancelsThePendingOne() {
        var plan = planWith(bed: t(23), wake: t(7))
        plan.applyRhythmChange(rhythm(bed: t(0, 30), wake: t(7)), now: date(day: 10, 20), calendar: calendar)
        plan.applyRhythmChange(rhythm(bed: t(23), wake: t(7)), now: date(day: 10, 20, 5), calendar: calendar)
        #expect(plan.pendingBedtime == nil)
    }

    // MARK: - Always on

    @Test func anOldPlanWithTheNightLockOffStillLocks() throws {
        var plan = planWith(bed: t(23), wake: t(7))
        let data = try JSONEncoder().encode(plan)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["nightLock"] = [
            "isEnabled": false,
            "followsRhythm": false,
            "customStart": ["hour": 1, "minute": 0],
            "customEnd": ["hour": 2, "minute": 0],
        ]
        for key in ["pendingBedtime", "needsWakeTimeAnswer", "hasCheckedWakeTime"] {
            json.removeValue(forKey: key)
        }
        plan = try JSONDecoder().decode(MorningPlan.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(plan.nightLock.isEnabled == false)
        #expect(plan.pendingBedtime == nil)
        #expect(plan.needsWakeTimeAnswer == false)
        #expect(plan.hasCheckedWakeTime == false)
        // The switch is ignored, and so is the custom 01:00 to 02:00 window.
        #expect(plan.nightLockWindow(at: date(day: 10, 23, 30), calendar: calendar) != nil)
        #expect(plan.nightLockWindow(at: date(day: 11, 3), calendar: calendar) != nil)
    }

    @Test func aPendingBedtimeSurvivesARoundTrip() throws {
        var plan = planWith(bed: t(23), wake: t(7))
        plan.applyRhythmChange(rhythm(bed: t(23, 30), wake: t(7)), now: date(day: 10, 22), calendar: calendar)
        let decoded = try JSONDecoder().decode(MorningPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded == plan)
    }

    @Test func anOldProfileDecodesWithNoWakeTime() throws {
        let data = try JSONEncoder().encode(OnboardingProfile.default)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "wakeTime")
        let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.wakeTime == nil)
        #expect(decoded.answeredWakeTime == t(7))
    }

    // MARK: - Seeding and the evening-user migration

    @Test func seedingUsesTheAnsweredSleepTimesAndTheFailureTimeForTheGym() {
        var profile = OnboardingProfile.default
        profile.failureWindow = .afterWork
        profile.failureTime = t(17, 30)
        profile.bedtime = t(23, 30)
        profile.wakeTime = t(6, 45)

        let plan = MorningPlan.seeded(from: profile, schedule: .default)
        #expect(plan.rhythm.bedtime == t(23, 30))
        #expect(plan.rhythm.wakeTime == t(6, 45))
        #expect(plan.rhythm.gymTime == t(17, 30))
        #expect(plan.hasCheckedWakeTime)
    }

    @Test func anEveningUsersGymAlarmStopsBeingTheirWakeTime() {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: monWedFri, alarmTime: t(17, 15))]
        plan.rhythm.wakeTime = t(17, 15)
        plan.hasCheckedWakeTime = false
        let gymByBefore = plan.rhythm.gymByTime
        let slotsBefore = plan.slots

        let repaired = SleepRules.migrateLegacyWakeTime(&plan, failureWindow: .afterWork)

        #expect(repaired)
        #expect(plan.rhythm.wakeTime == t(7))
        #expect(plan.rhythm.gymTime == gymByBefore)
        #expect(plan.needsWakeTimeAnswer)
        #expect(plan.hasCheckedWakeTime)
        // No alarm time changes in this prompt.
        #expect(plan.slots == slotsBefore)
    }

    @Test func aLateWakeTimeIsRepairedWhateverTheWindow() {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: monWedFri, alarmTime: t(11, 30))]
        plan.rhythm.wakeTime = t(11, 30)
        plan.hasCheckedWakeTime = false
        let repaired = SleepRules.migrateLegacyWakeTime(&plan, failureWindow: .beforeWork)
        #expect(repaired)
    }

    @Test func aMorningUserIsLeftExactlyAsTheyAre() {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: monWedFri, alarmTime: t(6, 15))]
        plan.rhythm.wakeTime = t(6, 15)
        plan.hasCheckedWakeTime = false
        var expected = plan
        expected.hasCheckedWakeTime = true

        let repaired = SleepRules.migrateLegacyWakeTime(&plan, failureWindow: .beforeWork)
        #expect(!repaired)
        #expect(plan == expected)
        #expect(!plan.needsWakeTimeAnswer)
    }

    @Test func theMigrationRunsOnlyOnce() {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: monWedFri, alarmTime: t(17, 15))]
        plan.rhythm.wakeTime = t(17, 15)
        plan.hasCheckedWakeTime = false
        SleepRules.migrateLegacyWakeTime(&plan, failureWindow: .evening)
        plan.rhythm.wakeTime = t(18)
        let repairedAgain = SleepRules.migrateLegacyWakeTime(&plan, failureWindow: .evening)
        #expect(!repairedAgain)
        #expect(plan.rhythm.wakeTime == t(18))
    }
}
