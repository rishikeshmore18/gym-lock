import Foundation
import Testing
@testable import GymLock

/// The unified Time to Gym: one duration from the alarm to the gym, the
/// migration from separate get ready and travel minutes, and the countdown
/// deadline that follows the scheduled arrival.
@MainActor
struct TimeToGymTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }()

    /// 2026-09-28 is a Monday.
    private func date(day: Int = 28, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func rhythm(wake: TimeOfDay, gym: TimeOfDay?, timeToGym: Int) -> MorningRhythm {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = t(23)
        rhythm.wakeTime = wake
        rhythm.gymTime = gym
        rhythm.timeToGymMinutes = timeToGym
        rhythm.hasBeenSet = true
        return rhythm
    }

    private func decodeRhythm(_ json: String) throws -> MorningRhythm {
        try JSONDecoder().decode(MorningRhythm.self, from: Data(json.utf8))
    }

    private func session(alarm: TimeOfDay, timeToGym: Int, arrivalTarget: Date?) -> GymSession {
        GymSession(
            day: calendar.startOfDay(for: date(6)),
            slotID: UUID(),
            alarmTime: alarm,
            isMorningSession: true,
            timeToGymMinutes: timeToGym,
            arrivalTarget: arrivalTarget
        )
    }

    // MARK: - Migration

    @Test func migrationAddsGetReadyAndTravel() throws {
        let rhythm = try decodeRhythm("""
        {"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":6,"minute":0},"getReadyMinutes":20,"travelMinutes":40,"hasBeenSet":true}
        """)
        #expect(rhythm.timeToGymMinutes == 60)
        #expect(rhythm.gymByTime == t(7))
    }

    @Test func migrationKeepsAWakeAndGoGapSoNothingMoves() throws {
        // Gym placed 60 minutes after the alarm, older split of 20 + 15: the
        // plan ran on the 60 minute gap, and keeps doing so.
        let rhythm = try decodeRhythm("""
        {"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":6,"minute":30},"getReadyMinutes":20,"travelMinutes":15,"gymTime":{"hour":7,"minute":30},"hasBeenSet":true}
        """)
        #expect(rhythm.timeToGymMinutes == 60)
        #expect(rhythm.flowMode == .wakeAndGo)
        #expect(rhythm.lockAlarmTime == t(6, 30))
        #expect(rhythm.gymByTime == t(7, 30))
    }

    @Test func migrationOfGoLaterAddsTheTwoAndKeepsTheTimeToGo() throws {
        // FLOW Flow 2: gym 18:00, 10 + 20, time to go 17:30.
        let rhythm = try decodeRhythm("""
        {"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":7,"minute":0},"getReadyMinutes":10,"travelMinutes":20,"gymTime":{"hour":18,"minute":0},"hasBeenSet":true}
        """)
        #expect(rhythm.timeToGymMinutes == 30)
        #expect(rhythm.flowMode == .goLater)
        #expect(rhythm.timeToGo == t(17, 30))
    }

    @Test func migrationClampsToTheRange() throws {
        let short = try decodeRhythm("""
        {"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":7,"minute":0},"getReadyMinutes":5,"travelMinutes":0,"gymTime":{"hour":18,"minute":0},"hasBeenSet":true}
        """)
        #expect(short.timeToGymMinutes == 10)
        let long = try decodeRhythm("""
        {"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":7,"minute":0},"getReadyMinutes":60,"travelMinutes":115,"gymTime":{"hour":18,"minute":0},"hasBeenSet":true}
        """)
        #expect(long.timeToGymMinutes == 120)
    }

    @Test func migrationHappensOnceAndOnlyTheNewKeyIsWritten() throws {
        let migrated = try decodeRhythm("""
        {"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":6,"minute":0},"getReadyMinutes":20,"travelMinutes":40,"hasBeenSet":true}
        """)
        let data = try JSONEncoder().encode(migrated)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["timeToGymMinutes"] as? Int == 60)
        #expect(object["getReadyMinutes"] == nil)
        #expect(object["travelMinutes"] == nil)
        #expect(try JSONDecoder().decode(MorningRhythm.self, from: data) == migrated)
    }

    @Test func aOneOffAlarmRhythmMigratesToo() throws {
        let slot = UUID()
        let json = """
        {"rhythm":{"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":6,"minute":30},"getReadyMinutes":20,"travelMinutes":15,"hasBeenSet":true},
         "nightLock":{"isEnabled":true,"followsRhythm":true,"customStart":{"hour":23,"minute":0},"customEnd":{"hour":6,"minute":30}},
         "slots":[{"id":"\(slot.uuidString)","days":[2,4,6],"alarmTime":{"hour":6,"minute":30},"isEnabled":true}],
         "missionsEnabled":true,"recentMissions":[],"hasBeenReviewed":true,
         "nextAlarmOverride":{"id":"\(UUID().uuidString)","slotID":"\(slot.uuidString)","fireDate":812000000,
           "rhythm":{"bedtime":{"hour":23,"minute":0},"wakeTime":{"hour":5,"minute":45},"getReadyMinutes":25,"travelMinutes":20,"hasBeenSet":true}}}
        """
        let plan = try JSONDecoder().decode(MorningPlan.self, from: Data(json.utf8))
        #expect(plan.rhythm.timeToGymMinutes == 35)
        #expect(plan.nextAlarmOverride?.rhythm?.timeToGymMinutes == 45)
    }

    // MARK: - Alarm and deadline times

    @Test func wakeAndGoSixPlusSixtyIsSeven() {
        var rhythm = rhythm(wake: t(6), gym: nil, timeToGym: 35)
        rhythm.setTimeToGym(60)
        #expect(rhythm.flowMode == .wakeAndGo)
        #expect(rhythm.lockAlarmTime == t(6))
        #expect(rhythm.gymByTime == t(7))
        #expect(rhythm.windowMinutes == 60)

        let target = GymSession.arrivalTarget(
            alarmTime: rhythm.lockAlarmTime,
            near: date(6),
            timeToGymMinutes: rhythm.windowMinutes,
            calendar: calendar
        )
        #expect(target == date(7))
    }

    @Test func goLaterEighteenMinusFortyFiveIsSeventeenFifteen() {
        var rhythm = rhythm(wake: t(7), gym: t(18), timeToGym: 30)
        rhythm.setTimeToGym(45)
        #expect(rhythm.flowMode == .goLater)
        #expect(rhythm.gymByTime == t(18))
        #expect(rhythm.timeToGo == t(17, 15))
        #expect(rhythm.lockAlarmTime == t(17, 15))

        let target = GymSession.arrivalTarget(
            alarmTime: rhythm.lockAlarmTime,
            near: date(17, 15),
            timeToGymMinutes: rhythm.windowMinutes,
            calendar: calendar
        )
        #expect(target == date(18))
    }

    @Test func editingInWakeAndGoMovesTheGymTime() {
        var rhythm = rhythm(wake: t(6, 30), gym: t(7, 30), timeToGym: 60)
        rhythm.setTimeToGym(45)
        #expect(rhythm.gymTime == t(7, 15))
        #expect(rhythm.wakeTime == t(6, 30))
        #expect(rhythm.lockAlarmTime == t(6, 30))
    }

    @Test func editingInGoLaterKeepsTheGymTime() {
        var rhythm = rhythm(wake: t(7), gym: t(18), timeToGym: 30)
        rhythm.setTimeToGym(90)
        #expect(rhythm.gymTime == t(18))
        #expect(rhythm.timeToGo == t(16, 30))
    }

    @Test func editsClampAndSnapToFiveMinutes() {
        var rhythm = rhythm(wake: t(7), gym: t(18), timeToGym: 30)
        rhythm.setTimeToGym(3)
        #expect(rhythm.timeToGymMinutes == 10)
        rhythm.setTimeToGym(500)
        #expect(rhythm.timeToGymMinutes == 120)
        rhythm.setTimeToGym(62)
        #expect(rhythm.timeToGymMinutes == 60)
        #expect(MorningRhythm.timeToGymPresets.allSatisfy { MorningRhythm.timeToGymRange.contains($0) })
    }

    // MARK: - The gym arc

    @Test func draggingTheGymArcInWakeAndGoSetsTimeToGym() {
        let base = rhythm(wake: t(6, 30), gym: t(7, 30), timeToGym: 60)
        let next = DayDialModel.applying(.gymBody, delta: -15, base: base, current: base).rhythm
        #expect(next.gymTime == t(7, 15))
        #expect(next.timeToGymMinutes == 45)
        #expect(next.lockAlarmTime == t(6, 30))
    }

    @Test func crossingIntoGoLaterKeepsTheOwnNumberNotTheCeiling() {
        let base = rhythm(wake: t(6, 30), gym: t(7, 30), timeToGym: 60)
        let next = DayDialModel.applying(.gymBody, delta: 180, base: base, current: base).rhythm
        #expect(next.flowMode == .goLater)
        #expect(next.timeToGymMinutes == 60)
        #expect(next.timeToGo == (next.gymTime ?? t(0)).offset(byMinutes: -60))

        // And back again: the gap takes over once more.
        let back = DayDialModel.applying(.gymBody, delta: 30, base: base, current: next).rhythm
        #expect(back.flowMode == .wakeAndGo)
        #expect(back.timeToGymMinutes == 90)
    }

    // MARK: - The countdown deadline

    @Test func aSnoozeOrASlowMissionDoesNotMoveTheDeadline() {
        let current = session(alarm: t(6), timeToGym: 60, arrivalTarget: date(7))
        // Committed after a 5 minute snooze and a 10 minute mission.
        #expect(current.preparationDeadline(committedAt: date(6, 15)) == date(7))
        #expect(current.preparationDeadline(committedAt: date(6, 1)) == date(7))
    }

    @Test func aSessionWithoutATargetCountsTheWindowFromTheCommit() {
        let current = session(alarm: t(6), timeToGym: 35, arrivalTarget: nil)
        #expect(current.preparationDeadline(committedAt: date(6, 10)) == date(6, 45))
    }

    @Test func runningLateMovesTheTargetAndTheLockTogether() {
        var current = session(alarm: t(17, 30), timeToGym: 30, arrivalTarget: date(18))
        current.flowMode = .goLater
        current.state = .awaitingDecision
        let now = date(17, 32)
        let late = RunningLate.apply(30, to: current, now: now)
        #expect(late.runningLateUntil == date(18, 2))
        #expect(late.arrivalTarget == date(18, 32))
        #expect(late.lockDeadline == ShieldPolicy.deadline(forWindowMinutes: 30, from: date(18, 2)))
    }

    @Test func theExtensionStillCountsInTheWindow() {
        var current = session(alarm: t(6), timeToGym: 60, arrivalTarget: date(7))
        current.extensionMinutesUsed = 10
        #expect(current.windowMinutes == 70)
        #expect(!current.canExtend)
    }

    @Test func theScheduledRingIsTheNearestOne() {
        // Resumed just after midnight for a 23:50 alarm: yesterday's ring.
        #expect(GymSession.scheduledRing(alarmTime: t(23, 50), near: date(day: 29, 0, 10), calendar: calendar)
            == date(day: 28, 23, 50))
        #expect(GymSession.scheduledRing(alarmTime: t(6), near: date(6, 3), calendar: calendar) == date(6))
    }

    // MARK: - Old sessions

    @Test func anOldSessionDecodesWithItsTwoDurationsAdded() throws {
        let current = session(alarm: t(6, 30), timeToGym: 99, arrivalTarget: nil)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any]
        )
        object.removeValue(forKey: "timeToGym")
        object.removeValue(forKey: "arrivalTarget")
        object["getReadyMinutes"] = 15
        object["travelMinutes"] = 20
        let decoded = try JSONDecoder().decode(GymSession.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.timeToGymMinutes == 35)
        #expect(decoded.windowMinutes == 35)
        #expect(decoded.arrivalTarget == nil)
    }

    @Test func aNewSessionRoundTrips() throws {
        let current = session(alarm: t(6), timeToGym: 60, arrivalTarget: date(7))
        let decoded = try JSONDecoder().decode(GymSession.self, from: JSONEncoder().encode(current))
        #expect(decoded.timeToGymMinutes == 60)
        #expect(decoded.arrivalTarget == date(7))
    }

    // MARK: - One value everywhere

    @Test func preferencesAndTheAlarmShareOneValue() {
        var plan = MorningPlan.default
        plan.rhythm = rhythm(wake: t(7), gym: t(18), timeToGym: 30)
        plan.slots = [AlarmSlot(days: [.monday], alarmTime: t(17, 30))]
        // Edited from Preferences...
        plan.setTimeToGym(45)
        #expect(plan.rhythm.timeToGymMinutes == 45)
        #expect(plan.slots[0].alarmTime == t(17, 15))
        #expect(plan.enabledSlots.first?.alarmTime == t(17, 15))
        // ...and read back by the Alarm screen's row.
        #expect(plan.rhythm.currentTimeToGymMinutes == 45)
    }

    @Test func timeToGymSurvivesARelaunch() throws {
        var plan = MorningPlan.default
        plan.rhythm = rhythm(wake: t(7), gym: t(18), timeToGym: 30)
        plan.slots = [AlarmSlot(days: [.monday], alarmTime: t(17, 30))]
        plan.setTimeToGym(75)
        let decoded = try JSONDecoder().decode(MorningPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded == plan)
        #expect(decoded.rhythm.timeToGymMinutes == 75)
        #expect(decoded.rhythm.timeToGo == t(16, 45))
    }

    @Test func theNudgeSpeaksToTheWholeTrip() {
        for daypart in SessionDaypart.allCases {
            #expect(SessionVoice(daypart: daypart, hasSnoozed: false).nudgeHeading == "still heading to the gym?")
        }
    }
}
