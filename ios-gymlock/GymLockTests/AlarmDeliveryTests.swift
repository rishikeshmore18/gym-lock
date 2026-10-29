import Foundation
import Testing
@testable import GymLock

/// The custom song reaching the system alarm, and the app never ringing it
/// again after the user has already answered the alarm.
@MainActor
struct AlarmDeliveryTests {
    // MARK: - Which sound AlarmKit is handed

    @Test func anExistingCustomCafIsNamedWithItsExtension() {
        let choice = AlarmKitSoundResolver.resolve(
            soundFileName: "gymlock-custom-alarm.caf",
            soundResource: nil,
            osHonoursNamedSounds: true,
            fileExists: { $0 == "gymlock-custom-alarm.caf" }
        )
        #expect(choice == .named("gymlock-custom-alarm.caf"))
    }

    @Test func aMissingCustomCafFallsBackToTheSelectedBundledCaf() {
        let choice = AlarmKitSoundResolver.resolve(
            soundFileName: "gymlock-custom-alarm.caf",
            soundResource: "gym_workout_alarm",
            osHonoursNamedSounds: true,
            fileExists: { $0 == "gym_workout_alarm.caf" }
        )
        #expect(choice == .named("gym_workout_alarm.caf"))
    }

    @Test func aBundledCafResolvesFromTheRealBundle() {
        // The real lookup, not a stub: the bundled caf must be found as a caf.
        #expect(AlarmKitSoundResolver.soundFileExists(named: "gym_workout_alarm.caf"))
        let choice = AlarmKitSoundResolver.resolve(
            soundFileName: "gym_workout_alarm.caf",
            soundResource: "gym_workout_alarm",
            osHonoursNamedSounds: true
        )
        #expect(choice == .named("gym_workout_alarm.caf"))
    }

    @Test func iOS26Point0AlwaysGetsTheSystemSound() {
        let choice = AlarmKitSoundResolver.resolve(
            soundFileName: "gymlock-custom-alarm.caf",
            soundResource: "gym_workout_alarm",
            osHonoursNamedSounds: false,
            fileExists: { _ in true }
        )
        #expect(choice == .systemDefault)
    }

    @Test func aMissingFileIsNeverSilent() {
        // Nothing on disk at all: the system alarm sound, never nothing.
        let choice = AlarmKitSoundResolver.resolve(
            soundFileName: "gymlock-custom-alarm.caf",
            soundResource: nil,
            osHonoursNamedSounds: true,
            fileExists: { _ in false }
        )
        #expect(choice == .systemDefault)

        let noName = AlarmKitSoundResolver.resolve(
            soundFileName: nil,
            soundResource: nil,
            osHonoursNamedSounds: true,
            fileExists: { _ in true }
        )
        #expect(noName == .systemDefault)
    }

    @Test func theBundledTrackIsNeverHandedOverAsMp3() {
        var asked: [String] = []
        _ = AlarmKitSoundResolver.resolve(
            soundFileName: nil,
            soundResource: "calm_morning_alarm_loop",
            osHonoursNamedSounds: true,
            fileExists: { asked.append($0); return false }
        )
        #expect(asked == ["calm_morning_alarm_loop.caf"])
    }

    // MARK: - What the handoff says happened

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    private var rang: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 6, minute: 30)) ?? Date()
    }

    private func resolve(
        _ action: AlarmHandoffAction,
        slotID: UUID,
        isSessionLive: Bool = false
    ) -> SessionResume.Resolution {
        let slot = AlarmSlot(id: slotID, days: Set(Weekday.allCases), alarmTime: TimeOfDay(hour: 6, minute: 30))
        return SessionResume.resolve(
            now: rang.addingTimeInterval(30),
            isSessionLive: isSessionLive,
            liveSlotID: isSessionLive ? slotID : nil,
            liveSessionDay: isSessionLive ? calendar.startOfDay(for: rang) : nil,
            handoff: AlarmHandoff.Pending(slotID: slotID, firedAt: rang, action: action),
            slots: [slot],
            windowMinutes: 35,
            resolvedKeys: [],
            calendar: calendar
        )
    }

    @Test func aFiredNoteMayStartTheRinger() {
        let decision = resolve(.fired, slotID: UUID()).decision
        #expect(decision?.source == .handoff)
        #expect(decision?.mayStartRinger == true)
        #expect(decision?.wantsSnooze == false)
    }

    @Test func aStoppedNoteResumesTheSessionWithoutTheRinger() {
        let slotID = UUID()
        let decision = resolve(.stopped, slotID: slotID).decision
        #expect(decision?.slotID == slotID)
        #expect(decision?.startAt == rang)
        #expect(decision?.mayStartRinger == false)
        #expect(decision?.wantsSnooze == false)
    }

    @Test func aSnoozedNoteSnoozesWithoutTheRinger() {
        let decision = resolve(.snoozed, slotID: UUID()).decision
        #expect(decision?.wantsSnooze == true)
        #expect(decision?.mayStartRinger == false)
    }

    @Test func aStopForTheRunningMorningIsAcknowledgedNotRestarted() {
        // The observer started the morning first; the Stop tap arrives after.
        let stopped = resolve(.stopped, slotID: UUID(), isSessionLive: true)
        #expect(stopped.decision == nil)
        #expect(stopped.clearsHandoff)
        #expect(stopped.acknowledgedAction == .stopped)

        let snoozed = resolve(.snoozed, slotID: UUID(), isSessionLive: true)
        #expect(snoozed.acknowledgedAction == .snoozed)
    }

    @Test func aClockResumeStillRingsAsBefore() {
        let slot = AlarmSlot(id: UUID(), days: Set(Weekday.allCases), alarmTime: TimeOfDay(hour: 6, minute: 30))
        let decision = SessionResume.decide(
            now: rang.addingTimeInterval(60),
            isSessionLive: false,
            handoff: nil,
            slots: [slot],
            windowMinutes: 35,
            resolvedKeys: [],
            calendar: calendar
        )
        #expect(decision?.source == .clock)
        #expect(decision?.mayStartRinger == true)
    }

    // MARK: - Writing and reading the note

    private func makeDefaults() -> UserDefaults {
        let name = "alarm-delivery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func anOldWantsSnoozeNoteStillDecodes() throws {
        let snoozeJSON = #"{"slotID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","firedAt":800000000,"wantsSnooze":true}"#
        let stopJSON = #"{"slotID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","firedAt":800000000,"wantsSnooze":false}"#

        let snooze = try JSONDecoder().decode(AlarmHandoff.Pending.self, from: Data(snoozeJSON.utf8))
        let stop = try JSONDecoder().decode(AlarmHandoff.Pending.self, from: Data(stopJSON.utf8))

        #expect(snooze.action == .snoozed)
        #expect(snooze.wantsSnooze)
        // An old note came from a button tap, so it never restarts audio.
        #expect(stop.action == .stopped)
    }

    @Test func theActionSurvivesARoundTrip() throws {
        for action in [AlarmHandoffAction.fired, .stopped, .snoozed] {
            let note = AlarmHandoff.Pending(slotID: UUID(), firedAt: rang, action: action)
            let data = try JSONEncoder().encode(note)
            #expect(try JSONDecoder().decode(AlarmHandoff.Pending.self, from: data) == note)
        }
    }

    @Test func theObserverNeverOverwritesAStopTap() {
        let defaults = makeDefaults()
        let slot = UUID()
        AlarmHandoff.write(.init(slotID: slot, firedAt: rang, action: .stopped), defaults: defaults)
        AlarmHandoff.write(.init(slotID: slot, firedAt: rang, action: .fired), defaults: defaults)
        #expect(AlarmHandoff.peek(now: rang, defaults: defaults)?.action == .stopped)

        // The other way round, the tap replaces the fired note.
        let other = makeDefaults()
        AlarmHandoff.write(.init(slotID: slot, firedAt: rang, action: .fired), defaults: other)
        AlarmHandoff.write(.init(slotID: slot, firedAt: rang, action: .snoozed), defaults: other)
        #expect(AlarmHandoff.peek(now: rang, defaults: other)?.action == .snoozed)
    }

    // MARK: - Saving a song reaches the system alarm

    @Test func syncAfterSavingASongNamesTheCustomCaf() async throws {
        // Mirrors what the trimmer's save does to the profile, then the
        // `syncAlarms()` it awaits. The view's call itself is not driven here.
        let directory = try #require(AlarmTrackResolver.ensureSoundsDirectory())
        let base = "test-delivery-\(UUID().uuidString)"
        let caf = directory.appendingPathComponent("\(base).caf")
        try Data([0]).write(to: caf)
        defer { try? FileManager.default.removeItem(at: caf) }

        let suite = "alarm-delivery-sync-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = AppStore(defaults: defaults)
        var plan = MorningPlan.default
        plan.slots = [
            AlarmSlot(days: Set(Weekday.allCases), alarmTime: TimeOfDay(hour: 6, minute: 30))
        ]
        plan.hasBeenReviewed = true
        store.plan = plan
        store.profile.customAlarmSoundFile = "\(base).m4a"
        store.profile.alarmSound = .ownSong

        let alarms = RecordingAlarmScheduler()
        let coordinator = GymSessionCoordinator(
            defaults: defaults,
            alarms: alarms,
            shield: DemoShieldService(defaults: defaults)
        )
        coordinator.bindStoreOnly(store)

        await coordinator.syncAlarms()

        let request = try #require(alarms.lastRequests.first)
        #expect(request.soundFileName == "\(base).caf")
        #expect(AlarmKitSoundResolver.resolve(
            soundFileName: request.soundFileName,
            soundResource: request.soundResource,
            osHonoursNamedSounds: true
        ) == .named("\(base).caf"))
    }
}

/// Records what the coordinator hands the OS.
@MainActor
final class RecordingAlarmScheduler: AlarmScheduling {
    nonisolated let capability: AlarmDeliveryCapability = .systemAlarm
    private(set) var lastRequests: [GymAlarmRequest] = []

    func authorizationStatus() async -> AlarmAuthorization { .authorized }
    func requestAuthorization() async -> AlarmAuthorization { .authorized }
    func replaceAll(with requests: [GymAlarmRequest]) async { lastRequests = requests }
    func cancelAll() async { lastRequests = [] }
    func scheduledSlotIDs() async -> Set<UUID> { Set(lastRequests.map(\.slotID)) }
}
