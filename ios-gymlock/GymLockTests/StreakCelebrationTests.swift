import Foundation
import Testing
@testable import GymLock

/// When the streak card is allowed to open on its own.
///
/// The one rule: the week has just been kept, and this week has not been
/// celebrated yet, and Home is on screen. Everything else — reopening the
/// app, backgrounding it, switching tabs, a frozen week — never opens it.
@MainActor
struct StreakCelebrationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    /// Monday 7 September 2026, and the Monday after.
    private var thisMonday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)) ?? Date()
    }

    private var nextMonday: Date {
        calendar.date(byAdding: .day, value: 7, to: thisMonday) ?? thisMonday
    }

    private func snapshot(
        days: Int,
        goal: Int,
        weeks: Int = 2,
        week: Date? = nil,
        preArmed: Bool = false
    ) -> StreakSnapshot {
        let kept = days >= goal
        return StreakSnapshot(
            weeks: kept ? weeks + 1 : weeks,
            weeklyGoal: goal,
            thisWeekSessionDays: days,
            isThisWeekKept: kept,
            freezesAvailable: preArmed ? 0 : 1,
            lastCompletedWeekWasFrozen: false,
            isLiveWeekPreArmed: preArmed,
            liveWeekStart: week ?? thisMonday
        )
    }

    /// A controller on a clean, isolated defaults suite. Returns both so a
    /// test can build a second controller on the same suite — a relaunch.
    ///
    /// By default the device has already run this rule before (the normal
    /// case). `fresh: true` is the first run after the update, where an
    /// already-kept week is baselined — see the Migration tests.
    private func makeController(
        suite: String = UUID().uuidString,
        fresh: Bool = false
    ) -> (controller: StreakIntroController, defaults: UserDefaults) {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        if !fresh { defaults.set(true, forKey: StreakIntroController.celebrationBaselineKey) }
        return (StreakIntroController(defaults: defaults, calendar: calendar), defaults)
    }

    private func present(
        _ controller: StreakIntroController,
        _ streak: StreakSnapshot,
        home: Bool = true
    ) -> Bool {
        controller.presentEarnedCelebrationIfNeeded(streak: streak, reduceMotion: true, isHomeVisible: home)
    }

    // MARK: - Eligibility is the week's goal

    @Test func twoOfThreeDoesNotPresent() {
        let (intro, _) = makeController()
        #expect(!present(intro, snapshot(days: 2, goal: 3)))
        #expect(intro.lastCelebratedWeekStart == nil)
    }

    @Test func threeOfThreePresents() {
        let (intro, _) = makeController()
        #expect(present(intro, snapshot(days: 3, goal: 3)))
        #expect(intro.lastCelebratedWeekStart == thisMonday)
    }

    @Test func threeOfFourDoesNotPresent() {
        let (intro, _) = makeController()
        #expect(!present(intro, snapshot(days: 3, goal: 4)))
    }

    @Test func fourOfFourPresents() {
        let (intro, _) = makeController()
        #expect(present(intro, snapshot(days: 4, goal: 4)))
    }

    @Test func fourOfFivePresentsOnlyAtFive() {
        let (intro, _) = makeController()
        #expect(!present(intro, snapshot(days: 4, goal: 5)))
        #expect(present(intro, snapshot(days: 5, goal: 5)))
    }

    @Test func aFrozenWeekThatFellShortIsNotACelebration() {
        let (intro, _) = makeController()
        #expect(!present(intro, snapshot(days: 1, goal: 3, preArmed: true)))
        #expect(!intro.hasPendingCelebration(for: snapshot(days: 1, goal: 3, preArmed: true)))
    }

    // MARK: - Once per kept week

    @Test func theSameWeekIsCelebratedOnceEvenAcrossARelaunch() {
        let suite = UUID().uuidString
        let (first, defaults) = makeController(suite: suite)
        let kept = snapshot(days: 3, goal: 3)
        #expect(present(first, kept))
        first.normalizeImmediately()
        #expect(!present(first, kept))

        // Relaunch: a new controller reading the same disk.
        let again = StreakIntroController(defaults: defaults, calendar: calendar)
        #expect(!present(again, kept))
        #expect(!again.hasPendingCelebration(for: kept))
    }

    @Test func comingBackFromTheBackgroundDoesNotReplay() {
        let (intro, _) = makeController()
        let kept = snapshot(days: 4, goal: 4)
        #expect(present(intro, kept))

        // Away for any length of time — there is no session gap any more.
        intro.sceneLeftForeground()
        #expect(intro.state == .compact)
        intro.sceneBecameActive(streak: kept, reduceMotion: true, isHomeVisible: true)
        #expect(intro.state == .compact)
        #expect(!present(intro, kept))
    }

    @Test func nextWeeksCompletionCelebratesAgain() {
        let (intro, _) = makeController()
        #expect(present(intro, snapshot(days: 3, goal: 3, weeks: 2)))
        intro.normalizeImmediately()

        // A new live week, not yet kept: nothing.
        #expect(!present(intro, snapshot(days: 2, goal: 3, weeks: 3, week: nextMonday)))
        // Kept: one more celebration.
        #expect(present(intro, snapshot(days: 3, goal: 3, weeks: 3, week: nextMonday)))
        #expect(intro.lastCelebratedWeekStart == nextMonday)
    }

    @Test func theStreakNumberAloneIsNotTheIdentity() {
        // Same weeks count, same week: still once. The week, not the number,
        // is what has been celebrated.
        let (intro, _) = makeController()
        #expect(present(intro, snapshot(days: 3, goal: 3, weeks: 0)))
        intro.normalizeImmediately()
        #expect(!present(intro, snapshot(days: 4, goal: 3, weeks: 0)))
    }

    // MARK: - Home only

    @Test func aCompletionSeenOnProgressStaysPending() {
        let (intro, _) = makeController()
        let kept = snapshot(days: 3, goal: 3)
        #expect(!present(intro, kept, home: false))
        #expect(intro.lastCelebratedWeekStart == nil)
        #expect(intro.hasPendingCelebration(for: kept))
    }

    @Test func progressThenHomePresentsOnce() {
        let (intro, _) = makeController()
        let kept = snapshot(days: 3, goal: 3)
        #expect(!present(intro, kept, home: false))
        intro.normalizeImmediately() // leaving a tab
        #expect(present(intro, kept, home: true))
        #expect(!present(intro, kept, home: true))
    }

    @Test func coldLaunchToHomeWaitsForTheLaunchCover() {
        let (intro, _) = makeController()
        let kept = snapshot(days: 4, goal: 4)
        // Behind the cover Home does not count as visible.
        #expect(!present(intro, kept, home: false))
        #expect(intro.hasPendingCelebration(for: kept))
        // Cover lifts.
        #expect(present(intro, kept, home: true))
    }

    @Test func coldLaunchToProgressWaitsForHome() {
        let (intro, _) = makeController()
        let kept = snapshot(days: 3, goal: 3)
        intro.sceneBecameActive(streak: kept, reduceMotion: true, isHomeVisible: false)
        #expect(intro.state == .compact)
        #expect(intro.hasPendingCelebration(for: kept))
        // Later, the user taps Home.
        #expect(present(intro, kept, home: true))
    }

    @Test func aSuspendedControllerHoldsTheCelebration() {
        let (intro, _) = makeController()
        let kept = snapshot(days: 3, goal: 3)
        intro.isSuspended = true
        #expect(!present(intro, kept))
        #expect(intro.hasPendingCelebration(for: kept))
        intro.resume(streak: kept, reduceMotion: true, isHomeVisible: true)
        #expect(!intro.hasPendingCelebration(for: kept))
    }

    // MARK: - Manual open is untouched

    @Test func theChipStillOpensTheCardWhateverTheCelebrationState() {
        let (intro, _) = makeController()
        let unkept = snapshot(days: 1, goal: 3)
        #expect(!present(intro, unkept))
        intro.open(reduceMotion: true)
        #expect(intro.state == .manuallyExpanded)
        #expect(intro.showsCloseButton)
        intro.normalizeImmediately()

        // After a celebration has been spent, too.
        let kept = snapshot(days: 3, goal: 3)
        #expect(present(intro, kept))
        intro.normalizeImmediately()
        intro.open(reduceMotion: true)
        #expect(intro.state == .manuallyExpanded)
        // And opening manually never marks or unmarks a week.
        #expect(intro.lastCelebratedWeekStart == thisMonday)
    }

    // MARK: - Migration

    @Test func anAlreadyKeptWeekIsBaselinedOnFirstRun() {
        let (intro, defaults) = makeController(fresh: true)
        let kept = snapshot(days: 4, goal: 4)
        #expect(!defaults.bool(forKey: StreakIntroController.celebrationBaselineKey))
        // Discovered while the update first runs — on any tab.
        #expect(!intro.hasPendingCelebration(for: kept))
        #expect(intro.lastCelebratedWeekStart == thisMonday)
        #expect(defaults.bool(forKey: StreakIntroController.celebrationBaselineKey))
        #expect(!present(intro, kept))
    }

    @Test func anUnkeptWeekOnFirstRunStillCelebratesWhenItIsKept() {
        let (intro, _) = makeController(fresh: true)
        #expect(!present(intro, snapshot(days: 2, goal: 3)))
        #expect(intro.lastCelebratedWeekStart == nil)
        // The third day lands after the rule is active: genuinely new.
        #expect(present(intro, snapshot(days: 3, goal: 3)))
    }

    @Test func theBaselineRunsOnlyOnce() {
        let (intro, _) = makeController(fresh: true)
        #expect(!present(intro, snapshot(days: 2, goal: 3)))
        intro.normalizeImmediately()
        // A relaunch-free completion later the same week is not baselined away.
        #expect(intro.hasPendingCelebration(for: snapshot(days: 3, goal: 3)))
    }

    @Test func theRetiredSessionKeyIsCleared() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.set(5, forKey: "gymlock.home.lastSeenStreak")
        _ = StreakIntroController(defaults: defaults, calendar: calendar)
        #expect(defaults.object(forKey: "gymlock.home.lastSeenStreak") == nil)
    }
}
