import Foundation
import Testing
@testable import GymLock

/// Which frames are offered for which situation.
///
/// The availability table is the honesty rule made executable: a frame whose
/// data is missing must be absent, and no frame may be invented to fill a gap.
@MainActor
struct ShareFrameAvailabilityTests {
    private let day = Date(timeIntervalSince1970: 1_789_600_000)

    private var photo: ProgressPhoto {
        ProgressPhoto(id: UUID(), createdAt: day, fileName: "f.jpg", thumbnailName: "t.jpg", source: .camera)
    }

    private func streak(_ weeks: Int, thisWeek: Int = 2) -> StreakSnapshot {
        StreakSnapshot(
            weeks: weeks, weeklyGoal: 3, thisWeekSessionDays: thisWeek, isThisWeekKept: thisWeek >= 3,
            freezesAvailable: 0, lastCompletedWeekWasFrozen: false, isLiveWeekPreArmed: false, liveWeekStart: day
        )
    }

    private var receipt: ReceiptTimeline {
        ReceiptTimeline(alarm: day, left: day.addingTimeInterval(1800), arrived: day.addingTimeInterval(3000), workout: nil)
    }

    private var journey: JourneySnapshot {
        JourneySnapshot(dayNumber: 30, verifiedVisits: 12, completion: 0.8, due: 10, dayZeroPhoto: nil)
    }

    private func context(
        hasPhoto: Bool = true,
        weeks: Int = 6,
        outcome: SessionOutcomeKind? = .showedUp,
        receipt: ReceiptTimeline? = nil,
        journey: JourneySnapshot? = nil,
        comeback: Bool = false,
        milestone: Bool = false
    ) -> ShareContext {
        ShareContext(
            referenceDay: day,
            photo: hasPhoto ? photo : nil,
            streak: streak(weeks),
            outcome: outcome.map { SessionOutcome(date: day, kind: $0, minutes: 20) },
            receipt: receipt,
            arrivedAt: receipt?.arrived,
            verifiedVisitsTotal: 12,
            verifiedVisitsThisWeek: 2,
            quick20ThisWeek: 0,
            sessionDaysThisWeek: 2,
            journey: journey,
            comeback: comeback ? ComebackInfo(missedDay: day.addingTimeInterval(-86_400), returnDay: day) : nil,
            milestone: milestone ? Milestone(kind: .verifiedVisits(10)) : nil,
            installDate: day.addingTimeInterval(-30 * 86_400)
        )
    }

    @Test("Showed up: everything present")
    func showedUpFull() {
        let frames = ShareFrameAvailability.frames(for: context(
            receipt: receipt, journey: journey, comeback: true, milestone: true
        ))
        #expect(frames.first == .clean)
        #expect(frames.contains(.showedUp))
        #expect(frames.contains(.receipt))
        #expect(frames.contains(.momentum))
        #expect(frames.contains(.comeback))
        #expect(frames.contains(.milestone))
        #expect(!frames.contains(.quickSave))
        #expect(frames.count == ShareFrameAvailability.maximumFrames)
    }

    @Test("Cap at six drops Journey, then Milestone, then Comeback")
    func capDropOrder() {
        // Seven qualify: clean, showedUp, receipt, momentum, comeback, milestone, journey.
        let seven = ShareFrameAvailability.frames(for: context(
            receipt: receipt, journey: journey, comeback: true, milestone: true
        ))
        #expect(seven.count == 6)
        #expect(!seven.contains(.journey))
        #expect(seven.contains(.milestone))
        #expect(seven.contains(.comeback))

        // Journey alone is dropped first; with only six qualifying nothing goes.
        let six = ShareFrameAvailability.frames(for: context(
            receipt: receipt, journey: journey, comeback: true, milestone: false
        ))
        #expect(six.count == 6)
        #expect(six.contains(.journey))
    }

    @Test("Receipt is hidden without a complete timeline")
    func receiptRequiresTimeline() {
        #expect(!ShareFrameAvailability.frames(for: context(receipt: nil)).contains(.receipt))
        #expect(ShareContextBuilder.receipt(from: [
            SessionEvent(kind: .alarmFired, at: day),
            SessionEvent(kind: .gymArrivalVerified, at: day.addingTimeInterval(3000)),
        ]) == nil)
    }

    @Test("Momentum needs at least one kept week")
    func momentumNeedsWeeks() {
        #expect(!ShareFrameAvailability.frames(for: context(weeks: 0)).contains(.momentum))
        #expect(ShareFrameAvailability.frames(for: context(weeks: 1)).contains(.momentum))
    }

    @Test("Home workout offers The Save and never Showed Up or Receipt")
    func homeWorkout() {
        let frames = ShareFrameAvailability.frames(for: context(outcome: .homeWorkout, receipt: receipt, comeback: true))
        #expect(frames == [.clean, .momentum, .comeback, .quickSave])
    }

    @Test("No outcome: Clean, Journey when eligible, Momentum when earned")
    func noOutcome() {
        #expect(ShareFrameAvailability.frames(for: context(weeks: 0, outcome: nil)) == [.clean])
        #expect(ShareFrameAvailability.frames(for: context(outcome: nil, journey: journey)) == [.clean, .momentum, .journey])
    }

    @Test("Journey needs day 14 and four due sessions")
    func journeyEligibility() {
        let young = JourneySnapshot(dayNumber: 10, verifiedVisits: 4, completion: 1, due: 5, dayZeroPhoto: nil)
        let thin = JourneySnapshot(dayNumber: 40, verifiedVisits: 2, completion: 1, due: 2, dayZeroPhoto: nil)
        #expect(!ShareFrameAvailability.frames(for: context(outcome: nil, journey: young)).contains(.journey))
        #expect(!ShareFrameAvailability.frames(for: context(outcome: nil, journey: thin)).contains(.journey))
    }

    @Test("Session origin omits Clean and Journey")
    func sessionOrigin() {
        let showed = ShareFrameAvailability.frames(for: context(hasPhoto: false, receipt: receipt, journey: journey, comeback: true, milestone: true))
        #expect(!showed.contains(.clean))
        #expect(!showed.contains(.journey))
        #expect(showed == [.showedUp, .momentum, .receipt, .comeback, .milestone])

        let saved = ShareFrameAvailability.frames(for: context(hasPhoto: false, outcome: .homeWorkout, comeback: true))
        #expect(saved == [.momentum, .comeback, .quickSave])
    }
}
