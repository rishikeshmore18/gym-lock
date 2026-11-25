import Foundation
import Testing
@testable import GymLock

/// The "plans changed" pause: the copy, its timing, the doors, and when the day 0 page plays.
@MainActor
struct PauseScriptTests {
    private func facts(
        context: PauseFacts.Context = .windowOpen,
        visitsBefore: Int = 23,
        streakWeeks: Int = 6,
        weekDone: Int = 1,
        weekGoal: Int = 3,
        chancesAfterToday: Int = 2,
        lastSkipped: Bool = false,
        reason: FailureReason? = .laterToday,
        homeLeft: Int = 2
    ) -> PauseFacts {
        PauseFacts(
            context: context,
            gymBy: "7:05 AM",
            nowLabel: "6:41 AM",
            graceMinutes: GymSession.graceMinutes,
            visitsBefore: visitsBefore,
            streakWeeks: streakWeeks,
            weekDone: weekDone,
            weekGoal: weekGoal,
            chancesAfterToday: chancesAfterToday,
            lastSkipped: lastSkipped,
            reason: reason,
            homeLeft: homeLeft,
            homeMinutes: HomeWorkoutRules.defaultMinutes,
            day0: nil,
            alarmLabel: "6:30 AM",
            week: [],
            dateLabel: "tue, nov 24"
        )
    }

    @Test func linesFitInsideTheThirtySeconds() {
        for f in [facts(), facts(context: .windowClosed, lastSkipped: true), facts(visitsBefore: 4, reason: .exhausted), facts(reason: nil)] {
            let script = PauseScript(facts: f)
            #expect(!script.lines.isEmpty)
            #expect((script.lines.last?.end ?? 0) <= PauseScript.wait)
            // In order and never overlapping.
            for (a, b) in zip(script.lines, script.lines.dropFirst()) {
                #expect(abs(a.end - b.start) < 0.0001)
            }
        }
    }

    @Test func ownWordsTravelAsOneBlock() {
        let script = PauseScript(facts: facts())
        let own = script.lines.filter { $0.kind == .own || $0.kind == .quote }
        #expect(own.count == 0 || own.count == 3)
    }

    @Test func noReasonMeansNoQuote() {
        let script = PauseScript(facts: facts(reason: nil))
        #expect(script.quote == nil)
        #expect(!script.lines.contains { $0.kind == .quote })
    }

    @Test func criticalWhenTheSkipBreaksTheStreakOrIsTheSecondInARow() {
        // 1 done + 1 chance left < 3: the week is out of reach.
        #expect(facts(chancesAfterToday: 1).isCritical)
        // No streak to break and no earlier skip: not critical, even with the week at risk.
        #expect(!facts(streakWeeks: 0, chancesAfterToday: 1).isCritical)
        #expect(facts(streakWeeks: 0, lastSkipped: true).isCritical)
        #expect(!facts().isCritical)
    }

    @Test func homeDoorHidesAtTheMonthlyCap() {
        #expect(PauseScript(facts: facts(homeLeft: 2)).choices.map(\.key) == [.gym, .home, .cant])
        #expect(PauseScript(facts: facts(homeLeft: 0)).choices.map(\.key) == [.gym, .cant])
    }

    @Test func closedWindowOffersGraceNotANewWindow() {
        let gym = PauseScript(facts: facts(context: .windowClosed)).choices[0]
        #expect(gym.lead == "\(GymSession.graceMinutes) more minutes. not a new window.")
    }

    @Test func timerLabelCountsDownThenContinues() {
        #expect(PauseScript.timerLabel(elapsed: 0) == "0:30")
        #expect(PauseScript.timerLabel(elapsed: 5.2) == "0:25")
        #expect(PauseScript.timerLabel(elapsed: 30) == "continue")
    }

    @Test func copyHasNoEmDashes() {
        let script = PauseScript(facts: facts())
        let all = script.lines.map(\.text) + script.choices.flatMap { [$0.title, $0.lead, $0.primary, $0.secondary] + $0.perks }
        #expect(!all.contains { $0.contains("\u{2014}") })
    }
}
