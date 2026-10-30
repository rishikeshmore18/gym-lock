import Foundation
import Testing
@testable import GymLock

/// The badges, pinned: every unlock is derived from the ledger and
/// `StreakEngine`, and nothing scheduled or unproven ever counts.
@MainActor
struct BadgeEngineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Monday 7 September 2026, 00:00 Berlin: the live week.
    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)) ?? Date()
    }

    private func day(_ offset: Int, hour: Int = 7, minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private func dayStart(_ offset: Int) -> Date {
        calendar.startOfDay(for: day(offset))
    }

    /// Three gym days a week.
    private var plan: MorningPlan {
        var plan = MorningPlan.default
        plan.slots = [AlarmSlot(days: [.monday, .wednesday, .friday], alarmTime: TimeOfDay(hour: 6, minute: 30))]
        return plan
    }

    private func gym(_ offset: Int, hour: Int = 7, proof: WorkoutProof = .photo) -> SessionOutcome {
        SessionOutcome(date: day(offset, hour: hour), kind: .showedUp, countsOn: dayStart(offset), proof: proof)
    }

    /// Mon, Wed, Fri of the week `weeksAgo` before the live one.
    private func keptWeek(_ weeksAgo: Int) -> [SessionOutcome] {
        [0, 2, 4].map { gym(-7 * weeksAgo + $0) }
    }

    private func states(
        _ outcomes: [SessionOutcome],
        vault: StreakVault = .empty,
        now: Date? = nil
    ) -> (facts: BadgeFacts, states: [String: BadgeState]) {
        let facts = BadgeEngine.facts(
            log: MomentumLog(outcomes: outcomes),
            plan: plan,
            schedule: .default,
            vault: vault,
            now: now ?? day(1, hour: 12),
            calendar: calendar
        )
        return (facts, BadgeRules.states(for: facts))
    }

    private func freshDefaults() -> UserDefaults {
        let name = "badges.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Scenarios

    @Test("A brand-new user has no badges and no progress to show")
    func brandNew() {
        let result = states([])
        #expect(result.states.values.allSatisfy { !$0.isEarned })
        #expect(BadgeCopy.cardProgress(result.states["locked-in"]?.progress) == nil)
        #expect(result.facts.bestStreak == 0)
    }

    @Test("One verified gym workout earns First Proof, dated that day")
    func oneWorkout() {
        let result = states([gym(0)])
        #expect(result.states["first-proof"] == .earned(on: dayStart(0)))
        #expect(result.states["showed-up"] == .locked(BadgeProgress(current: 1, target: 3, unit: .workoutDays)))
        #expect(result.states["first-lock"]?.isEarned == false)
        #expect(result.states["home-hero"]?.isEarned == false)
    }

    @Test("An arrival whose workout is not done counts for nothing")
    func unprovenArrivalDoesNotCount() {
        let result = states([gym(0, proof: .unproven)])
        #expect(result.states["first-proof"]?.isEarned == false)
        #expect(result.facts.workoutDays.isEmpty)
    }

    @Test("Workout-day milestones count distinct days and unlock on the day they were reached")
    func workoutDayMilestones() {
        var outcomes = (0..<10).map { gym(-20 + $0 * 2) }
        // A second outcome on the same day counts once.
        outcomes.append(SessionOutcome(date: day(-20, hour: 19), kind: .homeWorkout, minutes: 20, countsOn: dayStart(-20), proof: .photo))
        let result = states(outcomes)
        #expect(result.facts.workoutDays.count == 10)
        #expect(result.states["showed-up"] == .earned(on: dayStart(-16)))
        #expect(result.states["ten-strong"] == .earned(on: dayStart(-2)))
        #expect(result.states["quarter-century"] == .locked(BadgeProgress(current: 10, target: 25, unit: .workoutDays)))
        #expect(BadgeCopy.cardProgress(result.states["quarter-century"]?.progress) == "10 / 25 DAYS")
    }

    @Test("One kept week earns First Lock on the day the goal was met")
    func oneKeptWeek() {
        let result = states(keptWeek(1))
        #expect(result.states["first-lock"] == .earned(on: dayStart(-3)))
        #expect(result.states["momentum"] == .locked(BadgeProgress(current: 1, target: 2, unit: .weeksInARow)))
    }

    @Test("Four kept weeks in a row earn Locked In; the next rung shows real progress")
    func multipleKeptWeeks() {
        let result = states((1...4).flatMap(keptWeek))
        #expect(result.facts.currentStreak == 4)
        #expect(result.states["momentum"]?.isEarned == true)
        #expect(result.states["locked-in"] == .earned(on: dayStart(-3)))
        #expect(result.states["habit-builder"] == .locked(BadgeProgress(current: 4, target: 8, unit: .weeksInARow)))
    }

    @Test("Streak badges follow the best streak, and a kept week after a break is a comeback")
    func bestStreakAndComeback() {
        // Two kept weeks, two empty weeks with no freeze, then one kept week.
        let result = states(keptWeek(5) + keptWeek(4) + keptWeek(1))
        #expect(result.facts.currentStreak == 1)
        #expect(result.facts.bestStreak == 2)
        #expect(result.states["momentum"] == .earned(on: dayStart(-24)))
        #expect(result.states["comeback"] == .earned(on: dayStart(-3)))
        #expect(result.states["recovery"]?.isEarned == false)
    }

    @Test("A kept week straight after a frozen one is a Recovery, and the freeze ends a clean run")
    func recoveryAfterFreeze() {
        var vault = StreakVault.empty
        vault.freezesAvailable = 1
        let result = states(keptWeek(3) + keptWeek(1), vault: vault)
        #expect(result.facts.currentStreak == 2)
        #expect(result.states["recovery"] == .earned(on: dayStart(-3)))
        #expect(result.states["comeback"]?.isEarned == false)
        #expect(result.states["clean-run"] == .locked(BadgeProgress(current: 1, target: 8, unit: .cleanWeeks)))
    }

    @Test("Early and late workouts, a return after 14 days, and a home save")
    func specialMilestones() {
        let sundayNightVisit = SessionOutcome(date: day(-14, hour: 0, minute: 20), kind: .showedUp, countsOn: dayStart(-15), proof: .photo)
        let result = states([
            sundayNightVisit,
            gym(-7, hour: 6),
            gym(-5, hour: 21),
            SessionOutcome(date: day(-3, hour: 18), kind: .homeWorkout, minutes: 20, countsOn: dayStart(-3), proof: .health),
        ])
        // The 00:20 visit counts on Sunday: not a sunrise.
        #expect(result.states["sunrise"] == .earned(on: dayStart(-7)))
        #expect(result.states["night-owl"] == .earned(on: dayStart(-5)))
        #expect(result.states["home-saver"] == .earned(on: dayStart(-3)))
        #expect(result.states["health-synced"] == .earned(on: dayStart(-3)))
        #expect(result.states["home-hero"] == .earned(on: dayStart(-3)))
        #expect(result.states["second-wind"]?.isEarned == false)

        let gap = states([gym(-30), gym(-15)])
        #expect(gap.states["second-wind"] == .earned(on: dayStart(-15)))
    }

    @Test("Overachiever needs a session day beyond the week's goal")
    func overachiever() {
        let result = states(keptWeek(1) + [gym(-1)])
        #expect(result.states["overachiever"] == .earned(on: dayStart(-1)))
        #expect(states(keptWeek(1)).states["overachiever"]?.isEarned == false)
    }

    // MARK: Store: newly earned vs seen

    @Test("A newly earned badge is unseen once, then never again")
    func newlyEarnedThenSeen() {
        let defaults = freshDefaults()
        let store = BadgeStore(defaults: defaults)
        store.apply(states([gym(0)]).states)
        #expect(store.unseenEarned == ["first-proof"])
        #expect(store.earnedCount == 1)

        store.markSeen(store.unseenEarned)
        #expect(store.unseenEarned.isEmpty)

        let reopened = BadgeStore(defaults: defaults)
        reopened.apply(states([gym(0)]).states)
        #expect(reopened.unseenEarned.isEmpty)
        #expect(reopened.state(for: "first-proof") == .earned(on: dayStart(0)))
    }

    @Test("An earned badge survives the ledger forgetting the outcome behind it")
    func earnedIsSticky() {
        let defaults = freshDefaults()
        let store = BadgeStore(defaults: defaults)
        store.apply(states([gym(0)]).states)
        store.apply(states([]).states)
        #expect(store.state(for: "first-proof") == .earned(on: dayStart(0)))
        #expect(store.earnedCount == 1)
    }

    @Test("The full reveal goes to the highest tier among the unseen")
    func headlineReveal() {
        let store = BadgeStore(defaults: freshDefaults())
        #expect(store.headlineReveal(among: ["first-lock", "momentum", "first-proof"]) == "momentum")
        #expect(store.headlineReveal(among: ["first-lock", "showed-up"]) == "showed-up")
    }

    // MARK: Copy

    @Test("VoiceOver reads name, milestone or progress, and state")
    func accessibilityLabels() {
        #expect(BadgeCopy.accessibilityLabel(BadgeCatalog.badge("locked-in"), state: .earned(on: nil))
            == "Locked In badge. Four week streak milestone. Earned.")
        #expect(BadgeCopy.accessibilityLabel(
            BadgeCatalog.badge("century"),
            state: .locked(BadgeProgress(current: 63, target: 100, unit: .workoutDays))
        ) == "Century badge. 63 of 100 workout days. Locked.")
    }
}
