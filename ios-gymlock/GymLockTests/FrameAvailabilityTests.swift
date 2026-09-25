import Foundation
import Testing
@testable import GymLock

/// Locked versus not-today, for every frame.
///
/// A lock is a true statement about a record in which something has never
/// happened. A frame that has happened before but not today is hidden, not
/// locked. Comeback is never locked in any state.
@MainActor
struct FrameAvailabilityTests {
    private let day = Date(timeIntervalSince1970: 1_789_600_000)

    private var photo: ProgressPhoto {
        ProgressPhoto(id: UUID(), createdAt: day, fileName: "f.jpg", thumbnailName: "t.jpg", source: .camera)
    }

    private func streak(_ weeks: Int, thisWeek: Int = 2, goal: Int = 3) -> StreakSnapshot {
        StreakSnapshot(
            weeks: weeks, weeklyGoal: goal, thisWeekSessionDays: thisWeek, isThisWeekKept: thisWeek >= goal,
            freezesAvailable: 0, lastCompletedWeekWasFrozen: false, isLiveWeekPreArmed: false, liveWeekStart: day
        )
    }

    private func context(
        hasPhoto: Bool = true,
        weeks: Int = 0,
        thisWeek: Int = 2,
        goal: Int = 3,
        outcome: SessionOutcomeKind? = nil,
        receipt: Bool = false,
        journey: JourneySnapshot? = nil,
        comeback: Bool = false,
        milestone: Bool = false,
        history: FrameHistory = .none
    ) -> ShareContext {
        let timeline = receipt
            ? ReceiptTimeline(alarm: day, left: day.addingTimeInterval(1800), arrived: day.addingTimeInterval(3000), workout: nil)
            : nil
        return ShareContext(
            referenceDay: day,
            photo: hasPhoto ? photo : nil,
            streak: streak(weeks, thisWeek: thisWeek, goal: goal),
            outcome: outcome.map { SessionOutcome(date: day, kind: $0, minutes: 20) },
            receipt: timeline,
            arrivedAt: timeline?.arrived,
            verifiedVisitsTotal: history.verifiedVisitsEver,
            verifiedVisitsThisWeek: 0,
            quick20ThisWeek: 0,
            sessionDaysThisWeek: thisWeek,
            journey: journey,
            comeback: comeback ? ComebackInfo(missedDay: day.addingTimeInterval(-86_400), returnDay: day) : nil,
            milestone: milestone ? Milestone(kind: .verifiedVisits(10)) : nil,
            installDate: day.addingTimeInterval(-2 * 86_400),
            history: history
        )
    }

    private func state(_ frame: ShareFrame, in context: ShareContext) -> FrameAvailability {
        ShareFrameAvailability.availability(for: context).first { $0.frame == frame }?.state ?? .notToday
    }

    @Test("Brand-new user: Clean available, the rest locked, Comeback hidden")
    func brandNew() {
        let context = context()
        #expect(state(.clean, in: context) == .available)
        #expect(state(.showedUp, in: context).isLocked)
        #expect(state(.receipt, in: context).isLocked)
        #expect(state(.momentum, in: context).isLocked)
        #expect(state(.journey, in: context).isLocked)
        #expect(state(.milestone, in: context).isLocked)
        #expect(state(.quickSave, in: context).isLocked)
        #expect(state(.comeback, in: context) == .notToday)
    }

    @Test("Comeback is never locked in any state")
    func comebackNeverLocked() {
        let states: [FrameAvailability] = [
            state(.comeback, in: context()),
            state(.comeback, in: context(outcome: .showedUp, history: .everything)),
            state(.comeback, in: context(outcome: .showedUp, comeback: true, history: .none)),
            state(.comeback, in: context(hasPhoto: false)),
        ]
        #expect(!states.contains { $0.isLocked })
        #expect(state(.comeback, in: context(outcome: .showedUp, comeback: true)) == .available)
    }

    @Test("Earned before but absent today is hidden, not locked")
    func notToday() {
        let rest = context(weeks: 3, history: .everything)
        #expect(state(.showedUp, in: rest) == .notToday)
        #expect(state(.receipt, in: rest) == .notToday)
        #expect(state(.quickSave, in: rest) == .notToday)
        #expect(state(.milestone, in: rest) == .notToday)
        #expect(state(.momentum, in: rest) == .available)
    }

    @Test("Available when satisfied today")
    func availableToday() {
        let morning = context(weeks: 2, outcome: .showedUp, receipt: true, history: .everything)
        #expect(state(.showedUp, in: morning) == .available)
        #expect(state(.receipt, in: morning) == .available)
        #expect(state(.momentum, in: morning) == .available)
    }

    @Test("Milestone names the next uncrossed threshold")
    func milestoneNextThreshold() {
        #expect(ShareFrameAvailability.milestoneLock(verifiedVisits: 0).requirement == "unlocks at your first verified visit")
        #expect(ShareFrameAvailability.milestoneLock(verifiedVisits: 3).requirement == "unlocks at 5 verified visits")
        #expect(ShareFrameAvailability.milestoneLock(verifiedVisits: 3).progress == "3 of 5")
        #expect(ShareFrameAvailability.milestoneLock(verifiedVisits: 7).requirement == "unlocks at 10 verified visits")
        #expect(ShareFrameAvailability.milestoneLock(verifiedVisits: 7).progress == "7 of 10")
    }

    @Test("Milestone is not locked once a visit exists; it just did not land today")
    func milestoneAfterFirstVisit() {
        let history = FrameHistory(hasVerifiedVisit: true, hasReceipt: false, hasKeptWeek: false, hasHomeWorkout: false, verifiedVisitsEver: 3)
        #expect(state(.milestone, in: context(history: history)) == .notToday)
    }

    @Test("Momentum progress reads real session days against the real goal")
    func momentumProgress() {
        let lock = state(.momentum, in: context(thisWeek: 1, goal: 2)).lock
        #expect(lock?.progress == "1 of 2 this week")
        #expect(lock?.closeness == 0.5)

        let kept = FrameHistory(hasVerifiedVisit: true, hasReceipt: false, hasKeptWeek: true, hasHomeWorkout: false, verifiedVisitsEver: 3)
        #expect(state(.momentum, in: context(weeks: 0, history: kept)) == .notToday)
    }

    @Test("Journey lock counts days, then due sessions")
    func journeyLock() {
        let early = JourneySnapshot(dayNumber: 3, verifiedVisits: 1, completion: 1, due: 1, dayZeroPhoto: nil)
        let earlyLock = state(.journey, in: context(journey: early)).lock
        #expect(earlyLock?.requirement == "unlocks on day 14")
        #expect(earlyLock?.progress == "day 3 of 14")

        let thin = JourneySnapshot(dayNumber: 20, verifiedVisits: 2, completion: 1, due: 2, dayZeroPhoto: nil)
        #expect(state(.journey, in: context(journey: thin)).lock?.progress == "2 of 4")

        let earned = JourneySnapshot(dayNumber: 20, verifiedVisits: 5, completion: 1, due: 6, dayZeroPhoto: nil)
        #expect(state(.journey, in: context(hasPhoto: false, journey: earned)) == .notToday)
    }

    @Test("Rail shows the nearest locks first, capped at two, never ahead of an available frame")
    func railOrderAndCap() {
        let journey = JourneySnapshot(dayNumber: 12, verifiedVisits: 0, completion: nil, due: 0, dayZeroPhoto: nil)
        let context = context(thisWeek: 1, journey: journey)
        let availability = ShareFrameAvailability.availability(for: context)
        let locked = ShareFrameAvailability.lockedForRail(availability)

        #expect(locked.count == ShareFrameAvailability.maximumLockedInRail)
        #expect(locked.first?.frame == .journey) // 12/14 beats 1/3
        #expect(locked.map(\.frame).contains(.momentum))
        #expect(ShareFrameAvailability.lockedFrames(availability).count == 6)

        let rail = ShareFrameAvailability.frames(for: context) + locked.map(\.frame)
        let firstLocked = rail.firstIndex { frame in availability.first { $0.frame == frame }?.state.isLocked == true } ?? rail.count
        let lastAvailable = rail.lastIndex { ShareFrameAvailability.frames(for: context).contains($0) } ?? -1
        #expect(lastAvailable < firstLocked)
    }

    @Test("Thumbnail and export share one element set")
    func thumbnailParity() {
        let context = context(weeks: 2, outcome: .showedUp, receipt: true, history: .everything)
        for frame in ShareFrameAvailability.frames(for: context) {
            let elements = StoryCanvasView.activeElements(frame: frame, context: context)
            #expect(elements == StoryCanvasView.activeElements(frame: frame, context: context))
            #expect(!elements.isEmpty)
        }
    }

    @Test("History from the record")
    func historyFromRecord() {
        var log = MomentumLog(outcomes: [])
        var events = SessionEventLog(events: [])
        let empty = ShareContextBuilder.history(log: log, events: events, weeklyGoal: 3, calendar: .current)
        #expect(empty == .none)

        let id = UUID()
        log.outcomes.append(SessionOutcome(date: day, kind: .showedUp, minutes: 40, sessionID: id))
        events.events = [
            SessionEvent(sessionID: id, kind: .alarmFired, at: day),
            SessionEvent(sessionID: id, kind: .departed, at: day.addingTimeInterval(600)),
            SessionEvent(sessionID: id, kind: .gymArrivalVerified, at: day.addingTimeInterval(1800)),
        ]
        let one = ShareContextBuilder.history(log: log, events: events, weeklyGoal: 3, calendar: .current)
        #expect(one.hasVerifiedVisit)
        #expect(one.hasReceipt)
        #expect(!one.hasKeptWeek)
        #expect(one.verifiedVisitsEver == 1)
    }
}
