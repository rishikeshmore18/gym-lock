import Foundation
import Testing
@testable import GymLock

/// The matrix that decides whether people get ambushed.
///
/// This is the rule that can lock somebody's phone without them asking, so
/// every boundary is pinned against a fixed clock rather than discovered at
/// 6:30 in the morning.
struct SessionResumeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Monday 7 September 2026.
    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 0, minute: 0)) ?? Date()
    }

    private func time(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: dayOffset, to: monday) ?? monday
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private let slotID = UUID()

    private var morningSlot: AlarmSlot {
        AlarmSlot(
            id: slotID,
            days: [.monday, .wednesday, .friday],
            alarmTime: TimeOfDay(hour: 6, minute: 30)
        )
    }

    /// 35 minutes: a 20 minute get-ready plus 15 minutes of travel.
    private let window = 35

    private func decide(
        at now: Date,
        isSessionLive: Bool = false,
        handoff: AlarmHandoff.Pending? = nil,
        slots: [AlarmSlot]? = nil,
        resolvedKeys: Set<String> = []
    ) -> SessionResume.Decision? {
        SessionResume.decide(
            now: now,
            isSessionLive: isSessionLive,
            handoff: handoff,
            slots: slots ?? [morningSlot],
            windowMinutes: window,
            resolvedKeys: resolvedKeys,
            calendar: calendar
        )
    }

    // MARK: - The clock alone

    @Test func oneMinuteBeforeTheAlarmIsNotDue() {
        #expect(decide(at: time(6, 29)) == nil)
    }

    @Test func oneMinuteAfterTheAlarmIsDue() {
        let decision = decide(at: time(6, 31))
        #expect(decision?.slotID == slotID)
        #expect(decision?.source == .clock)
    }

    @Test func midWindowIsDue() {
        #expect(decide(at: time(6, 50)) != nil)
    }

    @Test func justPastTheDeadlineIsStillDue() {
        // 6:30 + 35 min window = 7:05, plus the 30 minute grace.
        #expect(decide(at: time(7, 6)) != nil)
    }

    @Test func wellPastTheDeadlineIsNotDue() {
        // Nobody gets ambushed with a locked phone at lunchtime.
        #expect(decide(at: time(7, 36)) == nil)
    }

    @Test func theClockStartIsTheAlarmTimeNotNow() {
        // The window is measured from when the alarm rang, so ignoring it for
        // twenty minutes does not quietly buy twenty more.
        let decision = decide(at: time(6, 50))
        #expect(decision?.startAt == time(6, 30))
    }

    @Test func aDayTheAlarmDoesNotRingIsNotDue() {
        // Tuesday is not in the slot's days.
        #expect(decide(at: time(6, 50, dayOffset: 1)) == nil)
    }

    @Test func theNextMatchingDayIsDueAgain() {
        // Wednesday. Resolving Monday must not silence the rest of the week.
        let mondayKey = SessionResume.resolvedKey(slotID: slotID, day: monday, calendar: calendar)
        let decision = decide(at: time(6, 50, dayOffset: 2), resolvedKeys: [mondayKey])
        #expect(decision != nil)
    }

    // MARK: - Things that must stop a resume

    @Test func aResolvedSlotIsNotDueAgainToday() {
        // The worst bug this feature could ship: saying "can't today" at 6:35
        // and having the apps lock again at 6:50.
        let key = SessionResume.resolvedKey(slotID: slotID, day: monday, calendar: calendar)
        #expect(decide(at: time(6, 50), resolvedKeys: [key]) == nil)
    }

    @Test func aLiveSessionIsNeverRestarted() {
        #expect(decide(at: time(6, 50), isSessionLive: true) == nil)
    }

    @Test func aLiveSessionDoesNotConsumeTheNote() {
        // `decide` only reports. Nothing here may clear the handoff, because
        // the caller is the only thing allowed to consume it.
        let handoff = AlarmHandoff.Pending(slotID: slotID, firedAt: time(6, 30), wantsSnooze: false)
        #expect(decide(at: time(6, 50), isSessionLive: true, handoff: handoff) == nil)
    }

    @Test func aDisabledSlotNeverResumes() {
        var slot = morningSlot
        slot.isEnabled = false
        #expect(decide(at: time(6, 50), slots: [slot]) == nil)
    }

    // MARK: - The handoff wins

    @Test func aHandoffBeatsTheClock() {
        // 22:00 is nowhere near the window, but the user just tapped "I'm up".
        let handoff = AlarmHandoff.Pending(slotID: slotID, firedAt: time(22, 0), wantsSnooze: false)
        let decision = decide(at: time(22, 1), handoff: handoff)

        #expect(decision?.source == .handoff)
        #expect(decision?.slotID == slotID)
    }

    @Test func theHandoffFiredAtIsUsedRatherThanNow() {
        // The user ignored the alarm for eleven minutes. The deadline is
        // measured from 6:30, not from when they finally picked the phone up.
        let handoff = AlarmHandoff.Pending(slotID: slotID, firedAt: time(6, 30), wantsSnooze: false)
        let decision = decide(at: time(6, 41), handoff: handoff)

        #expect(decision?.startAt == time(6, 30))
    }

    @Test func theSnoozeIntentCarriesThroughToTheDecision() {
        let handoff = AlarmHandoff.Pending(slotID: slotID, firedAt: time(6, 30), wantsSnooze: true)
        #expect(decide(at: time(6, 31), handoff: handoff)?.wantsSnooze == true)
    }

    // MARK: - Handoff guards (docs/FLOW.md, item 12)

    private func resolve(
        at now: Date,
        isSessionLive: Bool = false,
        liveSlotID: UUID? = nil,
        liveSessionDay: Date? = nil,
        handoff: AlarmHandoff.Pending?,
        resolvedKeys: Set<String> = [],
        alarmSlotIDs: [UUID: UUID] = [:]
    ) -> SessionResume.Resolution {
        SessionResume.resolve(
            now: now,
            isSessionLive: isSessionLive,
            liveSlotID: liveSlotID,
            liveSessionDay: liveSessionDay,
            handoff: handoff,
            slots: [morningSlot],
            windowMinutes: window,
            resolvedKeys: resolvedKeys,
            alarmSlotIDs: alarmSlotIDs,
            calendar: calendar
        )
    }

    @Test func aHandoffForASlotResolvedThatDayIsDiscarded() {
        // Replaces the old "deliberate handoff beats a resolved day" rule:
        // after a gym visit, no note for that slot may lock the apps again.
        let key = SessionResume.resolvedKey(slotID: slotID, day: monday, calendar: calendar)
        let handoff = AlarmHandoff.Pending(slotID: slotID, firedAt: time(6, 30), wantsSnooze: false)
        let result = resolve(at: time(6, 50), handoff: handoff, resolvedKeys: [key])

        #expect(result.decision == nil)
        #expect(result.clearsHandoff)
    }

    @Test func aResolvedDayIsJudgedByWhenTheHandoffFired() {
        // Fired 23:50 Monday, read 00:05 Tuesday: Monday's key still applies.
        let key = SessionResume.resolvedKey(slotID: slotID, day: monday, calendar: calendar)
        let handoff = AlarmHandoff.Pending(slotID: slotID, firedAt: time(23, 50), wantsSnooze: false)
        let result = resolve(at: time(0, 5, dayOffset: 1), handoff: handoff, resolvedKeys: [key])

        #expect(result.decision == nil)
        #expect(result.clearsHandoff)
    }

    @Test func yesterdaysResolvedKeyDoesNotBlockTodaysAlarm() {
        let mondayKey = SessionResume.resolvedKey(slotID: slotID, day: monday, calendar: calendar)
        let handoff = AlarmHandoff.Pending(
            slotID: slotID,
            firedAt: time(6, 30, dayOffset: 2),
            wantsSnooze: false
        )
        let result = resolve(at: time(6, 31, dayOffset: 2), handoff: handoff, resolvedKeys: [mondayKey])

        #expect(result.decision?.source == .handoff)
    }

    @Test func aOneOffAlarmIsCheckedAgainstItsSlotsResolvedKey() {
        // "Change next alarm only" rings under its own id, but the day is
        // settled under the slot's id.
        let oneOffID = UUID()
        let key = SessionResume.resolvedKey(slotID: slotID, day: monday, calendar: calendar)
        let handoff = AlarmHandoff.Pending(slotID: oneOffID, firedAt: time(6, 30), wantsSnooze: false)
        let result = resolve(
            at: time(6, 50),
            handoff: handoff,
            resolvedKeys: [key],
            alarmSlotIDs: [oneOffID: slotID]
        )

        #expect(result.decision == nil)
        #expect(result.clearsHandoff)
    }

    @Test func aLiveSessionDiscardsASameSlotHandoff() {
        let handoff = AlarmHandoff.Pending(slotID: slotID, firedAt: time(6, 40), wantsSnooze: false)
        let result = resolve(
            at: time(6, 41),
            isSessionLive: true,
            liveSlotID: slotID,
            liveSessionDay: monday,
            handoff: handoff
        )

        #expect(result.decision == nil)
        #expect(result.clearsHandoff)
    }

    @Test func aLiveSessionDiscardsANoSlotHandoff() {
        let handoff = AlarmHandoff.Pending(slotID: nil, firedAt: time(6, 40), wantsSnooze: false)
        let result = resolve(
            at: time(6, 41),
            isSessionLive: true,
            liveSlotID: slotID,
            liveSessionDay: monday,
            handoff: handoff
        )

        #expect(result.decision == nil)
        #expect(result.clearsHandoff)
    }

    @Test func aLiveSessionKeepsADifferentSlotHandoffWaiting() {
        let handoff = AlarmHandoff.Pending(slotID: UUID(), firedAt: time(6, 40), wantsSnooze: false)
        let result = resolve(
            at: time(6, 41),
            isSessionLive: true,
            liveSlotID: slotID,
            liveSessionDay: monday,
            handoff: handoff
        )

        #expect(result.decision == nil)
        #expect(!result.clearsHandoff)
    }

    @Test func aNormalAlarmHandoffStillStartsTheSession() {
        let handoff = AlarmHandoff.Pending(slotID: slotID, firedAt: time(6, 30), wantsSnooze: false)
        let result = resolve(at: time(6, 31), handoff: handoff)

        #expect(result.decision?.source == .handoff)
        #expect(result.decision?.slotID == slotID)
        #expect(result.decision?.startAt == time(6, 30))
        #expect(result.clearsHandoff)
    }

    @Test func theClockPathNeverClearsAHandoff() {
        let result = resolve(at: time(6, 50), handoff: nil)
        #expect(result.decision?.source == .clock)
        #expect(!result.clearsHandoff)
    }

    // MARK: - Two slots in one day

    @Test func theMostRecentOpenWindowWins() {
        // A morning and an evening slot are both legitimate. At 18:10 the
        // evening one is the morning the user is actually in.
        let evening = AlarmSlot(days: [.monday], alarmTime: TimeOfDay(hour: 18, minute: 0))
        let decision = decide(at: time(18, 10), slots: [morningSlot, evening])

        #expect(decision?.slotID == evening.id)
    }

    @Test func resolvingOneSlotLeavesTheOtherAlone() {
        let evening = AlarmSlot(days: [.monday], alarmTime: TimeOfDay(hour: 18, minute: 0))
        let morningKey = SessionResume.resolvedKey(slotID: slotID, day: monday, calendar: calendar)

        let decision = decide(
            at: time(18, 10),
            slots: [morningSlot, evening],
            resolvedKeys: [morningKey]
        )
        #expect(decision?.slotID == evening.id)
    }

    // MARK: - Keys

    @Test func theResolvedKeyIsStableForADay() {
        let morning = SessionResume.resolvedKey(slotID: slotID, day: time(6, 30), calendar: calendar)
        let evening = SessionResume.resolvedKey(slotID: slotID, day: time(23, 59), calendar: calendar)
        #expect(morning == evening)
    }

    @Test func theResolvedKeyChangesWithTheDay() {
        let today = SessionResume.resolvedKey(slotID: slotID, day: monday, calendar: calendar)
        let tomorrow = SessionResume.resolvedKey(
            slotID: slotID,
            day: time(6, 30, dayOffset: 1),
            calendar: calendar
        )
        #expect(today != tomorrow)
    }
}
