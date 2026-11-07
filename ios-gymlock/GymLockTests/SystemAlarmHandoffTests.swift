import Foundation
import Testing
@testable import GymLock

/// `docs/FLOW.md`, Flow 1: the system alarm's "I'm up" is the commitment,
/// "5 more min" works once and rings again as a real alarm, and the second
/// ring has no snooze.
@MainActor
struct SystemAlarmHandoffTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }()

    /// 2026-09-28 is a Monday.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func t(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    /// Wake & Go: wake 06:30, 35 min to the gym.
    private var wakeAndGo: MorningRhythm {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = t(23)
        rhythm.wakeTime = t(6, 30)
        rhythm.gymTime = nil
        rhythm.timeToGymMinutes = 35
        rhythm.hasBeenSet = true
        return rhythm
    }

    private func plan() -> MorningPlan {
        var plan = MorningPlan.default
        plan.rhythm = wakeAndGo
        plan.slots = [AlarmSlot(days: Set(Weekday.allCases), alarmTime: t(6, 30))]
        plan.hasBeenReviewed = true
        return plan
    }

    private struct Harness {
        let coordinator: GymSessionCoordinator
        let store: AppStore
        let defaults: UserDefaults
        let alarms: RecordingAlarmScheduler
        var slot: AlarmSlot? { store.plan.enabledSlots.first }
    }

    private func makeHarness() -> Harness {
        let suite = "system-alarm-handoff-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = AppStore(defaults: defaults)
        store.plan = plan()
        let shield = DemoShieldService(defaults: defaults)
        shield.setDemoSelection(count: 3)
        let alarms = RecordingAlarmScheduler()
        let coordinator = GymSessionCoordinator(defaults: defaults, alarms: alarms, shield: shield)
        coordinator.bindStoreOnly(store)
        return Harness(coordinator: coordinator, store: store, defaults: defaults, alarms: alarms)
    }

    private func write(_ action: AlarmHandoffAction, slotID: UUID?, at firedAt: Date, in harness: Harness) {
        AlarmHandoff.write(.init(slotID: slotID, firedAt: firedAt, action: action), defaults: harness.defaults)
    }

    // MARK: - Snooze ids

    @Test func aSnoozeIDIsDeterministicAndRecognisable() throws {
        let source = try #require(UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-8E9FA0B1C2D3"))
        let snooze = SnoozeAlarmID.derive(from: source)
        #expect(snooze == SnoozeAlarmID.derive(from: source))
        #expect(snooze != source)
        #expect(SnoozeAlarmID.isSnooze(snooze))
        #expect(!SnoozeAlarmID.isSnooze(source))
        #expect(!SnoozeAlarmID.isSnooze(nil))
        #expect(SnoozeAlarmID.sourceID(for: snooze, among: [UUID(), source]) == source)
        #expect(SnoozeAlarmID.sourceID(for: source, among: [source]) == nil)
    }

    @Test func aSnoozeIDMapsBackToItsSlot() throws {
        let plan = plan()
        let slot = try #require(plan.enabledSlots.first)
        let snooze = SnoozeAlarmID.derive(from: slot.id)
        #expect(plan.slot(forAlarmID: snooze)?.id == slot.id)
        #expect(plan.oneOffSlotIDs[snooze] == slot.id)
    }

    // MARK: - Which alarms ring

    @Test func theSecondRingIsAGymAlarmWithNoSnoozeEvenOnceItIsRinging() throws {
        var plan = plan()
        let slot = try #require(plan.enabledSlots.first)
        let id = SnoozeAlarmID.derive(from: slot.id)
        let fire = date(day: 28, 6, 35)
        plan.oneOffAlarms = [OneOffAlarm(id: id, kind: .snooze, slotID: slot.id, fireDate: fire)]

        // Booked, and still held while it rings, so a foreground sync never
        // cancels the alarm on screen.
        for now in [date(day: 28, 6, 31), date(day: 28, 6, 36)] {
            let alarms = AlarmPlan.alarms(for: plan, now: now, calendar: calendar)
            let second = try #require(alarms.first { $0.id == id })
            #expect(second.kind == .gym)
            #expect(second.allowsSnooze == false)
            #expect(second.fireDate == fire)
        }
    }

    @Test func theSecondRingNeverStandsInForTheNextMorning() throws {
        var plan = plan()
        let slot = try #require(plan.enabledSlots.first)
        let fire = date(day: 28, 6, 35)
        plan.oneOffAlarms = [
            OneOffAlarm(id: SnoozeAlarmID.derive(from: slot.id), kind: .snooze, slotID: slot.id, fireDate: fire)
        ]
        let next = plan.nextOccurrence(after: date(day: 28, 6, 31), calendar: calendar)
        #expect(next?.fireDate != fire)
        #expect(OneOffAlarm.Kind.snooze.replacesWeeklyRing == false)
    }

    @Test func theSnoozeTemplateBooksOneRingAtTheEndOfTheSnooze() {
        let template = SnoozeRealertTemplate(
            minutes: 5,
            title: "Gym time",
            message: "Apps stay locked.",
            soundResource: "sunrise",
            soundFileName: "sunrise.caf"
        )
        let source = UUID()
        let tapped = date(day: 28, 6, 31)
        let request = template.request(sourceAlarmID: source, snoozedAt: tapped, calendar: calendar)
        #expect(request.slotID == SnoozeAlarmID.derive(from: source))
        #expect(request.fireDate == date(day: 28, 6, 36))
        #expect(request.kind == .gym)
        #expect(request.allowsSnooze == false)
        #expect(request.soundFileName == "sunrise.caf")
        #expect(request.weekdays == [.monday])
    }

    @Test func theSnoozeTemplateRoundTrips() {
        let suite = "snooze-template-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        #expect(SnoozeRealertTemplate.load(defaults: defaults) == nil)
        let template = SnoozeRealertTemplate(minutes: 5, title: "a", message: "b", soundResource: nil, soundFileName: nil)
        template.save(defaults: defaults)
        #expect(SnoozeRealertTemplate.load(defaults: defaults) == template)
    }

    // MARK: - "I'm up" on the system alarm

    @Test func imUpWithTheAppClosedGoesStraightToTheMorning() throws {
        let harness = makeHarness()
        let slot = try #require(harness.slot)
        write(.stopped, slotID: slot.id, at: Date().addingTimeInterval(-60), in: harness)

        harness.coordinator.resumeSessionIfDue()

        let session = try #require(harness.coordinator.session)
        #expect(session.state.hasCommitted)
        #expect(session.state == .activationMission)
        #expect(session.committedAt != nil)
        #expect(!harness.coordinator.ringer.isRinging)
        #expect(AlarmHandoff.peek(defaults: harness.defaults) == nil)
        harness.coordinator.endSession()
    }

    @Test func imUpAfterTheAppAlreadyShowedTheAlarmCommitsOnce() throws {
        let harness = makeHarness()
        let slot = try #require(harness.slot)
        let rang = Date().addingTimeInterval(-60)
        harness.coordinator.beginSession(for: slot, at: rang)
        #expect(harness.coordinator.session?.state == .alarmFired)

        write(.stopped, slotID: slot.id, at: rang, in: harness)
        harness.coordinator.resumeSessionIfDue()
        let committed = try #require(harness.coordinator.session)
        #expect(committed.state.hasCommitted)
        let committedAt = try #require(committed.committedAt)
        #expect(!harness.coordinator.ringer.isRinging)

        // The intent and the observer racing: a second "stopped" never
        // commits again or rewinds the morning.
        write(.stopped, slotID: slot.id, at: rang, in: harness)
        harness.coordinator.resumeSessionIfDue()
        #expect(harness.coordinator.session?.committedAt == committedAt)
        #expect(harness.coordinator.session?.id == committed.id)
        harness.coordinator.endSession()
    }

    @Test func aRingingAlarmAloneIsNotACommitment() throws {
        let harness = makeHarness()
        let slot = try #require(harness.slot)
        write(.fired, slotID: slot.id, at: Date().addingTimeInterval(-60), in: harness)

        harness.coordinator.resumeSessionIfDue()

        let session = try #require(harness.coordinator.session)
        #expect(!session.state.hasCommitted)
        #expect(GymSessionCoordinator.awaitsAnswer(session.state))
        harness.coordinator.endSession()
    }

    // MARK: - One snooze, one second ring

    @Test func snoozeOnTheSystemAlarmBooksARealSecondRing() throws {
        let harness = makeHarness()
        let slot = try #require(harness.slot)
        // Whole seconds, so the stored note round-trips exactly.
        let tapped = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate - 30).rounded(.down))
        write(.snoozed, slotID: slot.id, at: tapped, in: harness)

        harness.coordinator.resumeSessionIfDue()

        let session = try #require(harness.coordinator.session)
        #expect(session.state == .snoozed)
        #expect(session.snoozeUsedAt == tapped)
        let second = try #require(harness.store.plan.oneOffAlarms.first { $0.kind == .snooze })
        #expect(second.id == SnoozeAlarmID.derive(from: slot.id))
        #expect(second.fireDate == tapped.addingTimeInterval(Double(session.snoozeDurationMinutes) * 60))
        #expect(!harness.coordinator.ringer.isRinging)

        // No second snooze.
        harness.coordinator.resolveElapsedSnooze(at: second.fireDate.addingTimeInterval(1))
        #expect(harness.coordinator.session?.state == .awaitingDecision)
        harness.coordinator.snooze()
        #expect(harness.coordinator.session?.state == .awaitingDecision)
        #expect(harness.store.plan.oneOffAlarms.filter { $0.kind == .snooze }.count == 1)
        harness.coordinator.endSession()
    }

    @Test func committingTakesTheSecondRingBackOff() throws {
        let harness = makeHarness()
        let slot = try #require(harness.slot)
        harness.coordinator.beginSession(for: slot, at: Date().addingTimeInterval(-30))
        harness.coordinator.snooze()
        #expect(harness.store.plan.oneOffAlarms.contains { $0.kind == .snooze })

        harness.coordinator.commitToGoing()
        #expect(!harness.store.plan.oneOffAlarms.contains { $0.kind == .snooze })
        harness.coordinator.endSession()
    }

    @Test func theSecondRingReachingAClosedAppHasNoSnoozeAndNoAppRinger() throws {
        let harness = makeHarness()
        let slot = try #require(harness.slot)
        let rang = Date().addingTimeInterval(-20)
        write(.fired, slotID: SnoozeAlarmID.derive(from: slot.id), at: rang, in: harness)

        harness.coordinator.resumeSessionIfDue()

        let session = try #require(harness.coordinator.session)
        #expect(session.slotID == slot.id)
        #expect(GymSessionCoordinator.awaitsAnswer(session.state))
        #expect(session.snoozeUsedAt != nil)
        #expect(session.snoozeRealert == .systemAlarm)
        #expect(!SessionVoice(session: session).allowsSnooze)
        #expect(!harness.coordinator.ringer.isRinging)

        harness.coordinator.snooze()
        #expect(harness.coordinator.session?.state != .snoozed)
        harness.coordinator.endSession()
    }

    @Test func theSecondRingDuringALiveMorningDoesNotStartAnother() throws {
        let harness = makeHarness()
        let slot = try #require(harness.slot)
        harness.coordinator.beginSession(for: slot, at: Date().addingTimeInterval(-6 * 60))
        harness.coordinator.snooze()
        let snoozed = try #require(harness.coordinator.session)

        write(.fired, slotID: SnoozeAlarmID.derive(from: slot.id), at: Date(), in: harness)
        harness.coordinator.resumeSessionIfDue()
        #expect(harness.coordinator.session?.id == snoozed.id)
        #expect(harness.coordinator.session?.state.hasCommitted == false)

        // Its "I'm up" commits the same morning.
        write(.stopped, slotID: SnoozeAlarmID.derive(from: slot.id), at: Date(), in: harness)
        harness.coordinator.resumeSessionIfDue()
        #expect(harness.coordinator.session?.id == snoozed.id)
        #expect(harness.coordinator.session?.state.hasCommitted == true)
        harness.coordinator.endSession()
    }

    // MARK: - Stored sessions

    @Test func aSessionSavedBeforeTheSecondRingExistedStillLoads() throws {
        let harness = makeHarness()
        harness.coordinator.beginSession(for: harness.slot, at: Date())
        let session = try #require(harness.coordinator.session)
        let data = try JSONEncoder().encode(session)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "snoozeRealert")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(GymSession.self, from: legacy)
        #expect(decoded.snoozeRealert == nil)
        #expect(decoded.id == session.id)
        harness.coordinator.endSession()
    }
}
