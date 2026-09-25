import Foundation
import Testing
@testable import GymLock

/// The Alarm screen's dial context and the contextual day card: which arc
/// the screen is talking about, which nights a gym morning requires, and how
/// the sleep schedule reaches the wind-down lock.
@Suite("Sleep schedule and dial context")
@MainActor
struct SleepScheduleTests {
    private let eleven = TimeOfDay(hour: 23, minute: 0)
    private let seven = TimeOfDay(hour: 7, minute: 0)
    private let one = TimeOfDay(hour: 1, minute: 0)
    private let eight = TimeOfDay(hour: 8, minute: 0)

    private func plan(gymDays: Set<Weekday>, bedtime: TimeOfDay, wake: TimeOfDay, sleep: Set<Weekday>) -> MorningPlan {
        var plan = MorningPlan.default
        plan.rhythm.bedtime = bedtime
        plan.rhythm.wakeTime = wake
        plan.slots = [AlarmSlot(days: gymDays, alarmTime: wake)]
        plan.sleepScheduleDays = sleep
        return plan
    }

    // MARK: - Dial context

    @Test func theScreenOpensInTheSleepContext() {
        #expect(AlarmDialContext.initial == .sleep)
    }

    @Test func touchingTheGymArcSelectsGym() {
        for grab in [DayDialModel.Grab.gymStart, .gymEnd, .gymBody] {
            #expect(AlarmDialContext.sleep.updated(with: grab) == .gym)
        }
    }

    @Test func liftingTheFingerKeepsGym() {
        let context = AlarmDialContext.sleep.updated(with: .gymBody).updated(with: nil)
        #expect(context == .gym)
    }

    @Test func touchingTheSleepArcSelectsSleep() {
        for grab in [DayDialModel.Grab.bedtime, .wake, .sleepBody] {
            #expect(AlarmDialContext.gym.updated(with: grab) == .sleep)
        }
    }

    @Test func liftingTheFingerKeepsSleep() {
        let context = AlarmDialContext.gym.updated(with: .wake).updated(with: nil)
        #expect(context == .sleep)
    }

    @Test func gymContextShowsGymHeaderAndGymDaysCard() {
        let context = AlarmDialContext.gym
        #expect(context.headerLabels.leading == "gym")
        #expect(context.headerLabels.trailing == "done")
        #expect(context.dayCardTitle == "gym days")
    }

    @Test func sleepContextShowsSleepHeaderAndSleepScheduleCard() {
        let context = AlarmDialContext.sleep
        #expect(context.headerLabels.leading == "bedtime")
        #expect(context.headerLabels.trailing == "wake up")
        #expect(context.dayCardTitle == "sleep schedule")
    }

    @Test func summariesUseTheShortCopy() {
        #expect(AlarmDialContext.gym.daySummary(count: 0) == "nothing will ring")
        #expect(AlarmDialContext.gym.daySummary(count: 1) == "1 day a week")
        #expect(AlarmDialContext.gym.daySummary(count: 3) == "3 days a week")
        #expect(AlarmDialContext.gym.daySummary(count: 7) == "every day")
        #expect(AlarmDialContext.sleep.daySummary(count: 0) == "no sleep schedule")
        #expect(AlarmDialContext.sleep.daySummary(count: 1) == "1 night a week")
        #expect(AlarmDialContext.sleep.daySummary(count: 5) == "5 nights a week")
        #expect(AlarmDialContext.sleep.daySummary(count: 7) == "every night")
    }

    // MARK: - Crossing midnight

    @Test func crossingMidnightIsStrictlyBedtimeAfterWake() {
        #expect(SleepSchedule.crossesMidnight(bedtime: eleven, wake: seven))
        #expect(!SleepSchedule.crossesMidnight(bedtime: one, wake: eight))
        #expect(!SleepSchedule.crossesMidnight(bedtime: seven, wake: seven))
    }

    // MARK: - Required nights

    @Test func tuesdayGymOvernightRequiresMondayNight() {
        let required = SleepSchedule.requiredNights(gymDays: [.tuesday], bedtime: eleven, wake: seven)
        #expect(required == [.monday])
    }

    @Test func mondayGymWrapsBackToSunday() {
        #expect(Weekday.monday.previous == .sunday)
        #expect(Weekday.sunday.next == .monday)
        let required = SleepSchedule.requiredNights(gymDays: [.monday], bedtime: eleven, wake: seven)
        #expect(required == [.sunday])
    }

    @Test func mondayWednesdayFridayRequireSundayTuesdayThursday() {
        let required = SleepSchedule.requiredNights(
            gymDays: [.monday, .wednesday, .friday], bedtime: eleven, wake: seven
        )
        #expect(required == [.sunday, .tuesday, .thursday])
    }

    @Test func aSameDayNightForcesNothing() {
        let required = SleepSchedule.requiredNights(gymDays: [.tuesday], bedtime: one, wake: eight)
        #expect(required.isEmpty)
    }

    @Test func requiredNightsCountInTheEffectiveSchedule() {
        let plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [.friday])
        #expect(plan.effectiveSleepDays() == [.monday, .friday])
        #expect(AlarmDialContext.sleep.daySummary(count: plan.effectiveSleepDays().count) == "2 nights a week")
    }

    // MARK: - Tapping a required night

    @Test func turningOffARequiredNightChangesNothing() {
        var plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [])
        let before = plan

        let result = plan.toggleSleepNight(.monday)

        #expect(result.outcome == .required(night: .monday, gymDay: .tuesday))
        #expect(result.effects.isEmpty)
        #expect(plan == before)
        #expect(plan.effectiveSleepDays().contains(.monday))
    }

    @Test func theRefusalNamesBothDays() {
        let message = SleepSchedule.requiredMessage(night: .monday, gymDay: .tuesday)
        #expect(message == "tuesday is a gym day. keep monday night on for rest.")
        #expect(!message.contains("\u{2014}"))
    }

    @Test func removingTheGymDayRemovesTheRequirement() {
        var plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [])
        #expect(plan.effectiveSleepDays() == [.monday])

        _ = plan.toggleGymDay(.tuesday, newAlarmTime: seven)

        #expect(plan.requiredSleepNights().isEmpty)
        // Monday was only there because of Tuesday, so it goes with it.
        #expect(!plan.effectiveSleepDays().contains(.monday))
        #expect(plan.sleepScheduleDays.isEmpty)
    }

    @Test func aChosenNightStaysAfterItStopsBeingRequired() {
        var plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [.monday])

        _ = plan.toggleGymDay(.tuesday, newAlarmTime: seven)

        #expect(plan.effectiveSleepDays().contains(.monday))
        // And it is editable again.
        let result = plan.toggleSleepNight(.monday)
        #expect(result.outcome == .updated([]))
    }

    @Test func aDraftThatStopsCrossingMidnightFreesTheNightWithoutStoringAnything() {
        var plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [])
        var draft = plan.rhythm
        draft.bedtime = one
        draft.wakeTime = eight

        #expect(plan.requiredSleepNights(for: draft).isEmpty)
        #expect(plan.requiredSleepNights() == [.monday])

        let result = plan.toggleSleepNight(.monday, rhythm: draft)
        #expect(result.outcome == .updated([.monday]))
    }

    // MARK: - Resync responsibilities

    @Test func gymDayChangesStillRescheduleGymAlarms() {
        var plan = plan(gymDays: [.monday], bedtime: eleven, wake: seven, sleep: [])

        let effects = plan.toggleGymDay(.wednesday, newAlarmTime: seven)

        #expect(effects.contains(.resyncGymAlarms))
        #expect(plan.slots[0].days == [.monday, .wednesday])
    }

    @Test func aGymDayOnADisabledAlarmSwitchesItBackOn() {
        var plan = plan(gymDays: [.monday], bedtime: eleven, wake: seven, sleep: [])
        plan.slots[0].isEnabled = false

        _ = plan.toggleGymDay(.friday, newAlarmTime: seven)

        #expect(plan.slots[0].isEnabled)
        #expect(plan.slots[0].days == [.monday, .friday])
    }

    @Test func theFirstGymDayCreatesAnAlarmAtTheShownTime() {
        var plan = MorningPlan.default
        let effects = plan.toggleGymDay(.thursday, newAlarmTime: seven)
        #expect(effects.contains(.resyncGymAlarms))
        #expect(plan.slots.count == 1)
        #expect(plan.slots[0].days == [.thursday])
        #expect(plan.slots[0].alarmTime == seven)
    }

    @Test func sleepDayChangesDoNotRescheduleGymAlarms() {
        var plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [])
        let slotsBefore = plan.slots

        let result = plan.toggleSleepNight(.friday)

        #expect(!result.effects.contains(.resyncGymAlarms))
        #expect(result.effects.contains(.reconcileWindDown))
        #expect(plan.slots == slotsBefore)
    }

    // MARK: - Persistence

    @Test func legacyPlansDecodeWithEveryNight() throws {
        let data = try JSONEncoder().encode(MorningPlan.default)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "sleepScheduleDays")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(MorningPlan.self, from: legacy)
        #expect(decoded.sleepScheduleDays == Set(Weekday.allCases))
    }

    @Test func theSleepScheduleSurvivesARelaunch() throws {
        let suite = "SleepScheduleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppStore(defaults: defaults)
        first.plan.sleepScheduleDays = [.monday, .thursday]

        let relaunched = AppStore(defaults: defaults)
        #expect(relaunched.plan.sleepScheduleDays == [.monday, .thursday])
    }

    // MARK: - Wind-down

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Monday 9 and Tuesday 10 March 2026.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    private var lock: NightLockWindow {
        var lock = NightLockWindow.default
        lock.isEnabled = true
        lock.followsRhythm = true
        return lock
    }

    private var overnight: MorningRhythm {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = eleven
        rhythm.wakeTime = seven
        return rhythm
    }

    @Test func aSelectedMondayHoldsFromMondayNightIntoTuesdayMorning() {
        let nights: Set<Weekday> = [.monday]
        #expect(lock.isActive(at: date(day: 9, 23, 30), calendar: calendar, rhythm: overnight, nights: nights))
        // 02:00 Tuesday still belongs to Monday's night.
        #expect(lock.isActive(at: date(day: 10, 2), calendar: calendar, rhythm: overnight, nights: nights))
    }

    @Test func anUnselectedMondayDoesNotActivate() {
        let nights: Set<Weekday> = [.tuesday]
        #expect(!lock.isActive(at: date(day: 9, 23, 30), calendar: calendar, rhythm: overnight, nights: nights))
        #expect(!lock.isActive(at: date(day: 10, 2), calendar: calendar, rhythm: overnight, nights: nights))
        // Tuesday's own night still does.
        #expect(lock.isActive(at: date(day: 10, 23, 30), calendar: calendar, rhythm: overnight, nights: nights))
    }

    @Test func noNightsFilterKeepsTheOldEveryNightBehaviour() {
        #expect(lock.isActive(at: date(day: 10, 2), calendar: calendar, rhythm: overnight))
    }

    @Test func aRequiredNightCountsForWindDown() {
        let plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [])
        let nights = plan.effectiveSleepDays()
        #expect(lock.isActive(at: date(day: 10, 2), calendar: calendar, rhythm: plan.rhythm, nights: nights))
    }
}
