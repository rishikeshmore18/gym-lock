import Foundation
import Testing
@testable import GymLock

/// The daypart voice and the single-snooze rule, pinned.
///
/// These are the rules that decide what a user actually reads at the moment the
/// alarm goes off, so they are worth holding still. Everything here is pure
/// derivation from a time and a session, which is exactly why the voice was
/// pulled out of the views in the first place.
@MainActor
struct SessionVoiceTests {
    private func session(hour: Int, minute: Int = 30) -> GymSession {
        let time = TimeOfDay(hour: hour, minute: minute)
        return GymSession(
            day: Calendar.current.startOfDay(for: Date()),
            slotID: nil,
            alarmTime: time,
            isMorningSession: SessionDaypart(time).usesSleepRhythm,
            getReadyMinutes: 15,
            travelMinutes: 20
        )
    }

    // MARK: - Daypart boundaries

    @Test func daypartBoundariesMatchTheProductDefinition() {
        #expect(SessionDaypart(TimeOfDay(hour: 0, minute: 0)) == .morning)
        #expect(SessionDaypart(TimeOfDay(hour: 10, minute: 59)) == .morning)
        #expect(SessionDaypart(TimeOfDay(hour: 11, minute: 0)) == .midday)
        #expect(SessionDaypart(TimeOfDay(hour: 15, minute: 59)) == .midday)
        #expect(SessionDaypart(TimeOfDay(hour: 16, minute: 0)) == .evening)
        #expect(SessionDaypart(TimeOfDay(hour: 23, minute: 59)) == .evening)
    }

    // MARK: - The snooze exists in the morning only

    @Test func snoozeIsOfferedInTheMorning() {
        #expect(SessionVoice(daypart: .morning).allowsSnooze)
    }

    @Test func snoozeIsNeverOfferedOutsideTheMorning() {
        // The whole reason the rule exists: at 17:25 the user is already awake,
        // so the button would be a procrastination button.
        #expect(!SessionVoice(daypart: .midday).allowsSnooze)
        #expect(!SessionVoice(daypart: .evening).allowsSnooze)
    }

    @Test func snoozeIsOfferedOnceOnly() {
        #expect(!SessionVoice(daypart: .morning, hasSnoozed: true).allowsSnooze)
    }

    // MARK: - The copy genuinely differs

    @Test func theGreetingDoesNotClaimAnEveningWasPlannedLastNight() {
        #expect(SessionVoice(daypart: .morning).alarmGreeting == "you planned this last night.")
        #expect(SessionVoice(daypart: .midday).alarmGreeting == "you planned this.")
        #expect(SessionVoice(daypart: .evening).alarmGreeting == "you planned this.")
    }

    @Test func eachDaypartGetsItsOwnSupportingLine() {
        let lines = Set(
            SessionDaypart.allCases.map { SessionVoice(daypart: $0).alarmSupport }
        )
        #expect(lines.count == SessionDaypart.allCases.count)
    }

    @Test func thePrimaryActionMatchesWhatTheUserIsBeingAskedToDo() {
        #expect(SessionVoice(daypart: .morning).primaryAction == "I'm up")
        #expect(SessionVoice(daypart: .midday).primaryAction == "I'm going")
        #expect(SessionVoice(daypart: .evening).primaryAction == "I'm going")
    }

    @Test func aSnoozedMorningSpeaksMoreDirectly() {
        let voice = SessionVoice(daypart: .morning, hasSnoozed: true)
        #expect(voice.alarmGreeting == "time to move.")
        // No counter, no "you already snoozed once" — the missing button is the
        // only message about it.
        #expect(!voice.alarmSupport.localizedCaseInsensitiveContains("again"))
        #expect(!voice.alarmSupport.localizedCaseInsensitiveContains("snooze"))
    }

    @Test func noCopyLineUsesAnEmDash() {
        // An em-dash is the most recognisable machine-written tell, and these
        // strings are the ones a half-awake user reads most closely.
        for daypart in SessionDaypart.allCases {
            for snoozed in [false, true] {
                let voice = SessionVoice(daypart: daypart, hasSnoozed: snoozed)
                let lines = [
                    voice.alarmGreeting,
                    voice.alarmSupport,
                    voice.snoozeSupport,
                    voice.moveTimeNote,
                    voice.plansChangedSupport,
                    voice.nudgeHeading,
                    voice.nudgeSupport,
                    voice.departureSupport,
                    voice.rescheduleDetail,
                    voice.windowHeading(hasLeft: false),
                    voice.windowSupport(hasLeft: false),
                    voice.windowFooterDetail(hasLeft: false),
                ]
                for line in lines {
                    #expect(!line.contains("\u{2014}"))
                }
            }
        }
    }

    // MARK: - Voice derived from a session

    @Test func voiceFollowsTheSessionsOwnAlarmTime() {
        #expect(SessionVoice(session: session(hour: 6)).daypart == .morning)
        #expect(SessionVoice(session: session(hour: 12)).daypart == .midday)
        #expect(SessionVoice(session: session(hour: 18)).daypart == .evening)
    }

    @Test func voiceReadsTheSnoozeStraightOffTheSession() {
        var morning = session(hour: 6)
        #expect(SessionVoice(session: morning).allowsSnooze)

        morning.snoozeUsedAt = Date()
        #expect(!SessionVoice(session: morning).allowsSnooze)
    }
}

/// The snooze state machine on `GymSession` itself.
@MainActor
struct SnoozeStateTests {
    private var now: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func snoozedSession(expiringIn seconds: TimeInterval) -> GymSession {
        var session = GymSession(
            day: Calendar.current.startOfDay(for: now),
            slotID: nil,
            alarmTime: TimeOfDay(hour: 6, minute: 30),
            isMorningSession: true,
            getReadyMinutes: 15,
            travelMinutes: 20
        )
        session.state = .snoozed
        session.snoozeUsedAt = now
        session.snoozeExpiresAt = now.addingTimeInterval(seconds)
        return session
    }

    @Test func aFreshSessionHasNotSnoozed() {
        let session = GymSession(
            day: now,
            slotID: nil,
            alarmTime: TimeOfDay(hour: 6, minute: 30),
            isMorningSession: true,
            getReadyMinutes: 15,
            travelMinutes: 20
        )
        #expect(!session.hasSnoozed)
        #expect(session.snoozeRemaining(at: now) == 0)
    }

    @Test func aRunningSnoozeReportsItsRemainingTime() {
        let session = snoozedSession(expiringIn: 300)
        #expect(session.snoozeRemaining(at: now) == 300)
        #expect(!session.snoozeHasElapsed(at: now))
    }

    @Test func anElapsedSnoozeIsDetectedFromTheWallClock() {
        // Absolute expiry, not an in-memory timer: this is what makes a snooze
        // survive the app being suspended on a nightstand.
        let session = snoozedSession(expiringIn: 300)
        #expect(session.snoozeHasElapsed(at: now.addingTimeInterval(301)))
        #expect(session.snoozeRemaining(at: now.addingTimeInterval(301)) == 0)
    }

    @Test func onlyASnoozedSessionCanHaveAnElapsedSnooze() {
        // A re-fire that arrives after the user already got up must be dropped
        // rather than dragging them back to the decision screen.
        var session = snoozedSession(expiringIn: 300)
        session.state = .preparing
        #expect(!session.snoozeHasElapsed(at: now.addingTimeInterval(600)))
    }

    @Test func aSnoozedSessionStillWantsTheShield() {
        // The apps stay locked through the five minutes. A snooze buys sleep,
        // not scrolling.
        #expect(GymSessionState.snoozed.wantsShield)
        #expect(GymSessionState.snoozed.isLive)
        #expect(!GymSessionState.snoozed.hasCommitted)
    }

    @Test func aSnoozeSurvivesEncodingAndDecoding() throws {
        let session = snoozedSession(expiringIn: 300)
        let data = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(GymSession.self, from: data)

        #expect(restored.state == .snoozed)
        #expect(restored.hasSnoozed)
        #expect(restored.snoozeExpiresAt == session.snoozeExpiresAt)
    }
}
