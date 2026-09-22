import Foundation
import Testing
@testable import GymLock

/// The Alarm screen's options card: snooze on/off, snooze length, haptics,
/// and the plan migration that keeps old installs behaving as before.
@MainActor
struct AlarmOptionsTests {
    private func session(hour: Int) -> GymSession {
        let time = TimeOfDay(hour: hour, minute: 30)
        return GymSession(
            day: Calendar.current.startOfDay(for: Date()),
            slotID: nil,
            alarmTime: time,
            isMorningSession: SessionDaypart(time).usesSleepRhythm,
            getReadyMinutes: 15,
            travelMinutes: 20
        )
    }

    // MARK: - Snooze

    @Test func switchingSnoozeOffRemovesItEvenInTheMorning() {
        #expect(!SessionVoice(daypart: .morning, snoozeEnabled: false).allowsSnooze)
    }

    @Test func theSnoozeButtonNamesTheChosenLength() {
        #expect(SessionVoice(daypart: .morning, snoozeMinutes: 9).snoozeAction == "9 more min")
        #expect(SessionVoice(daypart: .morning).snoozeAction == "5 more min")
    }

    @Test func aSessionCarriesTheSnoozeSettingsItRangWith() {
        var morning = session(hour: 6)
        morning.snoozeOffered = false
        morning.snoozeLengthMinutes = 12
        let voice = SessionVoice(session: morning)
        #expect(!voice.allowsSnooze)
        #expect(voice.snoozeMinutes == 12)
    }

    @Test func sessionsSavedBeforeTheSettingKeepTheOldSnooze() {
        let old = session(hour: 6)
        #expect(old.offersSnooze)
        #expect(old.snoozeDurationMinutes == GymSession.snoozeMinutes)
    }

    @Test func snoozeRangeIsOneToFifteen() {
        #expect(MorningPlan.snoozeRange == 1...15)
    }

    // MARK: - Migration

    @Test func oldPlansDecodeWithTheOriginalBehaviour() throws {
        var plan = MorningPlan.default
        plan.snoozeEnabled = false
        plan.snoozeMinutes = 11
        plan.alarmHaptic = .sos

        // Strip the new keys, as a plan saved by an older build would be.
        let data = try JSONEncoder().encode(plan)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "snoozeEnabled")
        json.removeValue(forKey: "snoozeMinutes")
        json.removeValue(forKey: "alarmHaptic")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(MorningPlan.self, from: legacy)
        #expect(decoded.snoozeEnabled)
        #expect(decoded.snoozeMinutes == 5)
        #expect(decoded.alarmHaptic == .synchronized)
    }

    @Test func newSettingsRoundTrip() throws {
        var plan = MorningPlan.default
        plan.snoozeEnabled = false
        plan.snoozeMinutes = 11
        plan.alarmHaptic = .heartbeat

        let decoded = try JSONDecoder().decode(MorningPlan.self, from: JSONEncoder().encode(plan))
        #expect(!decoded.snoozeEnabled)
        #expect(decoded.snoozeMinutes == 11)
        #expect(decoded.alarmHaptic == .heartbeat)
    }

    // MARK: - Haptics

    @Test func everyPatternExceptNoneVibrates() {
        for haptic in AlarmHaptic.allCases where haptic != .none {
            #expect(!haptic.beats.isEmpty, "\(haptic) has no beats")
        }
        #expect(AlarmHaptic.none.beats.isEmpty)
    }

    @Test func everyPatternFitsInsideItsCycle() {
        for haptic in AlarmHaptic.allCases {
            let end = haptic.beats.map { $0.time + $0.duration }.max() ?? 0
            #expect(end < haptic.cycleLength, "\(haptic) overruns its rest")
        }
    }

    @Test func theStandardListMatchesApplesOrder() {
        #expect(AlarmHaptic.standard.map(\.label) == [
            "Accent", "Alert", "Heartbeat", "Quick", "Rapid", "S.O.S.", "Staccato", "Symphony",
        ])
    }
}
