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
        #expect(AlarmDialContext.sleep.daySummary(count: 0) == "no active days")
        #expect(AlarmDialContext.sleep.daySummary(count: 1) == "1 day a week")
        #expect(AlarmDialContext.sleep.daySummary(count: 5) == "5 days a week")
        #expect(AlarmDialContext.sleep.daySummary(count: 7) == "every day")
        for count in 0...7 {
            #expect(!AlarmDialContext.sleep.daySummary(count: count).contains("night"))
        }
    }

    // MARK: - Crossing midnight

    @Test func crossingMidnightIsStrictlyBedtimeAfterWake() {
        #expect(SleepSchedule.crossesMidnight(bedtime: eleven, wake: seven))
        #expect(!SleepSchedule.crossesMidnight(bedtime: one, wake: eight))
        #expect(!SleepSchedule.crossesMidnight(bedtime: seven, wake: seven))
    }

    // MARK: - Required days

    private let monWedFri: Set<Weekday> = [.monday, .wednesday, .friday]

    @Test func gymMondayWednesdayFridayRequireTheSameDays() {
        for (bed, wake) in [(eleven, seven), (one, eight)] {
            let plan = plan(gymDays: monWedFri, bedtime: bed, wake: wake, sleep: [])
            #expect(plan.requiredSleepDays() == monWedFri)
            #expect(plan.effectiveSleepDays() == monWedFri)
        }
    }

    @Test func requiredDaysCountInTheEffectiveSchedule() {
        let plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [.friday])
        #expect(plan.effectiveSleepDays() == [.tuesday, .friday])
        #expect(AlarmDialContext.sleep.daySummary(count: plan.effectiveSleepDays().count) == "2 days a week")
    }

    // MARK: - Tapping a required day

    @Test func turningOffARequiredDayChangesNothing() {
        var plan = plan(gymDays: monWedFri, bedtime: eleven, wake: seven, sleep: [])
        let before = plan

        let result = plan.toggleSleepDay(.monday)

        #expect(result.outcome == .required(day: .monday))
        #expect(result.effects.isEmpty)
        #expect(plan == before)
        #expect(plan.effectiveSleepDays().contains(.monday))
        #expect(SleepSchedule.requiredMessage(day: .monday) == "monday is a gym day, so monday stays active.")
    }

    @Test func theDayBeforeAGymDayIsFree() {
        var plan = plan(gymDays: monWedFri, bedtime: eleven, wake: seven, sleep: [])
        let result = plan.toggleSleepDay(.sunday)
        #expect(result.outcome == .updated([.sunday]))
    }

    // Four gym days, so one can come off without going under the minimum.
    private let fourGymDays: Set<Weekday> = [.tuesday, .thursday, .saturday, .sunday]

    @Test func removingTheGymDayRemovesTheRequirement() {
        var plan = plan(gymDays: fourGymDays, bedtime: eleven, wake: seven, sleep: [])
        #expect(plan.effectiveSleepDays() == fourGymDays)

        let result = plan.toggleGymDay(.tuesday, newAlarmTime: seven)

        #expect(result.outcome == .updated)
        #expect(plan.requiredSleepDays() == [.thursday, .saturday, .sunday])
        // Tuesday was only there because it was a gym day.
        #expect(!plan.effectiveSleepDays().contains(.tuesday))
        #expect(plan.sleepScheduleDays.isEmpty)

        // And it is editable again.
        let toggled = plan.toggleSleepDay(.tuesday)
        #expect(toggled.outcome == .updated([.tuesday]))
    }

    @Test func aChosenDayStaysAfterItStopsBeingRequired() {
        var plan = plan(gymDays: fourGymDays, bedtime: eleven, wake: seven, sleep: [.tuesday])

        _ = plan.toggleGymDay(.tuesday, newAlarmTime: seven)

        #expect(plan.effectiveSleepDays().contains(.tuesday))
        let result = plan.toggleSleepDay(.tuesday)
        #expect(result.outcome == .updated([]))
    }

    // MARK: - Migration to wake days

    private func legacyPlan(bed: TimeOfDay, wake: TimeOfDay, sleep: Set<Weekday>) throws -> MorningPlan {
        var plan = plan(gymDays: monWedFri, bedtime: bed, wake: wake, sleep: sleep)
        plan.sleepDaysAreWakeDays = true
        let data = try JSONEncoder().encode(plan)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "sleepDaysAreWakeDays")
        return try JSONDecoder().decode(MorningPlan.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func newPlansAlreadyUseWakeDays() {
        var plan = MorningPlan.default
        #expect(plan.sleepDaysAreWakeDays)
        let before = plan
        #expect(!SleepSchedule.migrateToWakeDays(&plan))
        #expect(plan == before)
    }

    @Test func overnightNightStartDaysShiftOnceToTheWakeDay() throws {
        var plan = try legacyPlan(bed: eleven, wake: seven, sleep: [.sunday, .saturday])
        #expect(!plan.sleepDaysAreWakeDays)

        #expect(SleepSchedule.migrateToWakeDays(&plan))
        #expect(plan.sleepScheduleDays == [.monday, .sunday])
        #expect(plan.sleepDaysAreWakeDays)

        // Never twice, including after a round trip.
        #expect(!SleepSchedule.migrateToWakeDays(&plan))
        var reloaded = try JSONDecoder().decode(MorningPlan.self, from: JSONEncoder().encode(plan))
        #expect(!SleepSchedule.migrateToWakeDays(&reloaded))
        #expect(reloaded.sleepScheduleDays == [.monday, .sunday])
    }

    @Test func sameDaySchedulesKeepTheirWeekday() throws {
        var plan = try legacyPlan(bed: one, wake: eight, sleep: [.monday, .thursday])
        #expect(SleepSchedule.migrateToWakeDays(&plan))
        #expect(plan.sleepScheduleDays == [.monday, .thursday])
    }

    @Test func theStoreMigratesOnceAcrossRelaunches() throws {
        let suite = "SleepScheduleTests.migration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Seed an old plan (night-start Sunday) directly into storage.
        var seeded = plan(gymDays: monWedFri, bedtime: eleven, wake: seven, sleep: [.sunday])
        seeded.hasCheckedWakeTime = true
        var json = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(seeded)) as? [String: Any]
        )
        json.removeValue(forKey: "sleepDaysAreWakeDays")
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "gymlock.morningPlan")

        let second = AppStore(defaults: defaults)
        #expect(second.plan.sleepScheduleDays == [.monday])
        #expect(second.plan.sleepDaysAreWakeDays)

        let third = AppStore(defaults: defaults)
        #expect(third.plan.sleepScheduleDays == [.monday])
    }

    // MARK: - Resync responsibilities

    @Test func gymDayChangesStillRescheduleGymAlarms() {
        var plan = plan(gymDays: [.monday], bedtime: eleven, wake: seven, sleep: [])

        let effects = plan.toggleGymDay(.wednesday, newAlarmTime: seven).effects

        #expect(effects.contains(.resyncAlarms))
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
        let effects = plan.toggleGymDay(.thursday, newAlarmTime: seven).effects
        #expect(effects.contains(.resyncAlarms))
        #expect(plan.slots.count == 1)
        #expect(plan.slots[0].days == [.thursday])
        #expect(plan.slots[0].alarmTime == seven)
    }

    /// A sleep day decides that morning's plain wake alarm, so the alarms
    /// are rebuilt too. The gym slots themselves never change.
    @Test func sleepDayChangesResyncAlarmsAndTheNightLock() {
        var plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [])
        let slotsBefore = plan.slots

        let result = plan.toggleSleepDay(.friday)

        #expect(result.effects.contains(.resyncAlarms))
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

    private var overnight: MorningRhythm {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = eleven
        rhythm.wakeTime = seven
        return rhythm
    }

    private func isLocked(_ rhythm: MorningRhythm, at now: Date, wakeDays: Set<Weekday>) -> Bool {
        SleepRules.lockWindow(at: now, rhythm: rhythm, pending: nil, wakeDays: wakeDays, calendar: calendar) != nil
    }

    @Test func aSelectedMondayHoldsFromSundayNightIntoMondayMorning() {
        let days: Set<Weekday> = [.monday]
        #expect(isLocked(overnight, at: date(day: 8, 23, 30), wakeDays: days))
        #expect(isLocked(overnight, at: date(day: 9, 2), wakeDays: days))
        // Monday 23:00 to Tuesday 07:00 is Tuesday's, which is off.
        #expect(!isLocked(overnight, at: date(day: 9, 23, 30), wakeDays: days))
        #expect(!isLocked(overnight, at: date(day: 10, 2), wakeDays: days))
    }

    @Test func aSelectedTuesdayHoldsFromMondayNight() {
        let days: Set<Weekday> = [.tuesday]
        #expect(!isLocked(overnight, at: date(day: 9, 2), wakeDays: days))
        #expect(isLocked(overnight, at: date(day: 9, 23, 30), wakeDays: days))
        #expect(isLocked(overnight, at: date(day: 10, 2), wakeDays: days))
    }

    @Test func everyNightLocksWhenEveryDayIsOn() {
        #expect(isLocked(overnight, at: date(day: 10, 2), wakeDays: Set(Weekday.allCases)))
    }

    @Test func aRequiredGymDayCountsForWindDown() {
        // Tuesday gym: Monday 23:00 to Tuesday 07:00 locks.
        let plan = plan(gymDays: [.tuesday], bedtime: eleven, wake: seven, sleep: [])
        #expect(plan.nightLockWindow(at: date(day: 9, 23, 30), calendar: calendar) != nil)
        #expect(plan.nightLockWindow(at: date(day: 10, 2), calendar: calendar) != nil)
        #expect(plan.nightLockWindow(at: date(day: 10, 23, 30), calendar: calendar) == nil)
    }
}
