import Foundation
import Testing
@testable import GymLock

/// The alarm screen choice: its default, the migration of older plans, and
/// the picker's draft, which must never touch the plan until Done.
@MainActor
struct AlarmScreenStyleTests {
    @Test func aNewPlanWakesToSunrise() {
        #expect(MorningPlan.default.alarmScreenStyle == .sunrise)
    }

    @Test func thereAreExactlyTwoStyles() {
        #expect(AlarmScreenStyle.allCases == [.sunrise, .focus])
    }

    @Test func aPlanSavedBeforeTheChoiceExistedDecodesToSunrise() throws {
        var plan = MorningPlan.default
        plan.alarmScreenStyle = .focus

        let data = try JSONEncoder().encode(plan)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "alarmScreenStyle")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(MorningPlan.self, from: legacy)
        #expect(decoded.alarmScreenStyle == .sunrise)
    }

    @Test func anUnknownStyleFallsBackRatherThanLosingThePlan() throws {
        var plan = MorningPlan.default
        plan.snoozeMinutes = 9

        let data = try JSONEncoder().encode(plan)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["alarmScreenStyle"] = "neon"
        let future = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(MorningPlan.self, from: future)
        #expect(decoded.alarmScreenStyle == .sunrise)
        #expect(decoded.snoozeMinutes == 9)
    }

    @Test func focusSurvivesARoundTrip() throws {
        var plan = MorningPlan.default
        plan.alarmScreenStyle = .focus

        let decoded = try JSONDecoder().decode(MorningPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded.alarmScreenStyle == .focus)
    }

    // MARK: Draft

    @Test func browsingWithoutDoneLeavesThePlanAlone() {
        let plan = MorningPlan.default
        var draft = AlarmScreenDraft(stored: plan.alarmScreenStyle)

        draft.select(.focus)

        #expect(draft.selection == .focus)
        #expect(draft.hasChanges)
        #expect(plan.alarmScreenStyle == .sunrise)
    }

    @Test func doneWritesTheSelection() {
        var plan = MorningPlan.default
        var draft = AlarmScreenDraft(stored: plan.alarmScreenStyle)

        draft.select(.focus)
        let wrote = draft.commit(to: &plan)

        #expect(wrote)
        #expect(plan.alarmScreenStyle == .focus)
    }

    @Test func selectionOnlyReportsARealChange() {
        var draft = AlarmScreenDraft(stored: .sunrise)

        // Bound first: `#expect` can't call a mutating method inside its closure.
        let sameAsSaved = draft.select(.sunrise)
        let changed = draft.select(.focus)
        let repeated = draft.select(.focus)
        #expect(!sameAsSaved)
        #expect(changed)
        #expect(!repeated)
    }

    @Test func choosingTheSavedStyleAgainIsNotAChange() {
        var draft = AlarmScreenDraft(stored: .focus)

        draft.select(.sunrise)
        draft.select(.focus)

        #expect(!draft.hasChanges)
    }
}
