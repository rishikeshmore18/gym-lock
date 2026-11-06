import Foundation
import Testing
@testable import GymLock

/// The pure theme rotation and position rules (02-experience-spec §1.4–§1.6).
///
/// Monday-first Gregorian calendar in a fixed zone so the 04:00 rollover and the weekday
/// index never depend on the machine running the suite.
struct ThemeRotationTests {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private static func isTraining(_ day: Date) -> Bool {
        [0, 2, 4].contains(ThemeRotation.weekdayIndex(day, cal))   // Mon / Wed / Fri
    }

    private static func nextTraining(after day: Date) -> Date {
        var d = cal.date(byAdding: .day, value: 1, to: day)!
        while !isTraining(d) { d = cal.date(byAdding: .day, value: 1, to: d)! }
        return d
    }

    /// Opens the app at noon every day from Mon 2 Nov 2026 and does every planned session.
    private static func runMonWedFri(days: Int) -> (themes: [Int], ledger: ThemeLedger, cycleAfter: [Int]) {
        var ledger = ThemeLedger()
        var themes: [Int] = []
        var cycles: [Int] = []
        for i in 0..<days {
            let now = cal.date(byAdding: .day, value: i, to: date(2026, 11, 2))!
            let day = ThemeRotation.displayDay(now, cal)
            let training = isTraining(day)
            let t = ThemeRotation.theme(
                for: now,
                kind: training ? .training : .other,
                nextTrainingDay: nextTraining(after: day),
                ledger: &ledger,
                cal
            )
            if training { ThemeRotation.markBuilt(t, ledger: &ledger) }
            themes.append(t.rawValue)
            cycles.append(ledger.cycle)
        }
        return (themes, ledger, cycles)
    }

    // MARK: §1.6 worked example

    @Test func monWedFriReproducesTheWorkedExample() {
        let expected = [0, 1, 2, 3, 4, 6, 0, 5, 1, 6, 2, 1, 4, 0, 3, 5, 2, 6, 4]
        let run = Self.runMonWedFri(days: expected.count)
        #expect(run.themes == expected)
    }

    @Test func firstCycleCompletesOnSixteenthNovember() {
        let run = Self.runMonWedFri(days: 19)
        // index 14 = Mon 16 Nov: the seventh session closes cycle 1 and resets `built`
        #expect(run.cycleAfter[13] == 0)
        #expect(run.cycleAfter[14] == 1)
        // after Wed 18 and Fri 20 Nov: {2, 4}
        #expect(run.ledger.built == (1 << 2) | (1 << 4))
        #expect(run.ledger.builtCount == 2)
    }

    @Test func noTwoConsecutiveDaysShareATheme() {
        let themes = Self.runMonWedFri(days: 19).themes
        for i in 1..<themes.count {
            #expect(themes[i] != themes[i - 1], "day \(i) repeats \(themes[i])")
        }
    }

    @Test func trainingDaysNeverRepeatThePreviousTrainingDay() {
        let themes = Self.runMonWedFri(days: 19).themes
        let training = themes.enumerated().filter { [0, 2, 4].contains($0.offset % 7) }.map(\.element)
        for i in 1..<training.count {
            #expect(training[i] != training[i - 1])
        }
    }

    @Test func allSevenObjectsBuiltInSevenSessions() {
        let themes = Self.runMonWedFri(days: 15).themes
        let training = themes.enumerated().filter { [0, 2, 4].contains($0.offset % 7) }.map(\.element)
        #expect(Set(training).count == 7)
        #expect(training.count == 7)
    }

    // MARK: Stability and rollover

    @Test func anAssignedDayIsStable() {
        var ledger = ThemeLedger()
        let now = Self.date(2026, 11, 3)
        let first = ThemeRotation.theme(for: now, kind: .other, nextTrainingDay: nil, ledger: &ledger, Self.cal)
        // asked again later the same day, as a training day, with a different peek: still the same
        let again = ThemeRotation.theme(for: Self.date(2026, 11, 3, 22), kind: .training,
                                        nextTrainingDay: Self.date(2026, 11, 4), ledger: &ledger, Self.cal)
        #expect(first == again)
    }

    @Test func displayDayRollsOverAtFourAM() {
        let lateNight = Self.date(2026, 11, 3, 3, 59)
        let morning = Self.date(2026, 11, 3, 4, 0)
        #expect(ThemeRotation.key(ThemeRotation.displayDay(lateNight, Self.cal), Self.cal) == "2026-11-02")
        #expect(ThemeRotation.key(ThemeRotation.displayDay(morning, Self.cal), Self.cal) == "2026-11-03")
    }

    @Test func weekdayIndexIsMondayFirst() {
        #expect(ThemeRotation.weekdayIndex(Self.date(2026, 11, 2), Self.cal) == 0)   // Mon
        #expect(ThemeRotation.weekdayIndex(Self.date(2026, 11, 8), Self.cal) == 6)   // Sun
    }

    @Test func ledgerTrimsToFortyFiveDays() {
        var ledger = ThemeLedger()
        for i in 0..<60 {
            let now = Self.cal.date(byAdding: .day, value: i, to: Self.date(2026, 11, 2))!
            _ = ThemeRotation.theme(for: now, kind: .other, nextTrainingDay: nil, ledger: &ledger, Self.cal)
        }
        #expect(ledger.assigned.count <= 46)
        #expect(ledger.assigned["2026-11-02"] == nil)
    }

    @Test func markBuiltResetsWhenAllSevenAreBuilt() {
        var ledger = ThemeLedger()
        for t in HeroTheme.allCases.dropLast() { ThemeRotation.markBuilt(t, ledger: &ledger) }
        #expect(ledger.builtCount == 6)
        #expect(ledger.cycle == 0)
        ThemeRotation.markBuilt(.week, ledger: &ledger)
        #expect(ledger.built == 0)
        #expect(ledger.cycle == 1)
        #expect(ledger.lastTrainingTheme == HeroTheme.week.rawValue)
    }

    // MARK: §1.5 week position (from real sessions, never the weekday)

    @Test func weekPositionFollowsCountedSessions() {
        #expect(HeroPositions.weekPos(k: 1, goal: 3) == .first)
        #expect(HeroPositions.weekPos(k: 2, goal: 3) == .middle)
        #expect(HeroPositions.weekPos(k: 3, goal: 3) == .last)
        #expect(HeroPositions.weekPos(k: 4, goal: 3) == .bonus)
        #expect(HeroPositions.weekPos(k: 5, goal: 5) == .last)
        #expect(HeroPositions.weekPos(k: 3, goal: 5) == .middle)
    }

    @Test func goalOfOneMakesTheFirstSessionTheLast() {
        // `.last` wins over `.first` when the single session keeps the week
        #expect(HeroPositions.weekPos(k: 1, goal: 1) == .last)
        #expect(HeroPositions.weekPos(k: 2, goal: 1) == .bonus)
    }

    @Test func bonusDrawsMiddleVisuals() {
        #expect(HeroWeekPos.bonus.visual == .middle)
        #expect(HeroWeekPos.first.visual == .first)
        #expect(HeroWeekPos.last.visual == .last)
    }

    // MARK: §1.5 month position

    @Test func monthPositionFirstMiddleLast() {
        #expect(HeroPositions.monthPos(earlierCountedThisMonth: 0, plannedDaysLeftAfterToday: 8, recapShownThisMonth: false) == .first)
        #expect(HeroPositions.monthPos(earlierCountedThisMonth: 4, plannedDaysLeftAfterToday: 3, recapShownThisMonth: false) == .middle)
        #expect(HeroPositions.monthPos(earlierCountedThisMonth: 9, plannedDaysLeftAfterToday: 0, recapShownThisMonth: false) == .last)
    }

    @Test func recapWinsATieWithFirst() {
        #expect(HeroPositions.monthPos(earlierCountedThisMonth: 0, plannedDaysLeftAfterToday: 0, recapShownThisMonth: false) == .last)
    }

    @Test func recapShowsOncePerMonth() {
        #expect(HeroPositions.monthPos(earlierCountedThisMonth: 9, plannedDaysLeftAfterToday: 0, recapShownThisMonth: true) == .middle)
        #expect(HeroPositions.monthPos(earlierCountedThisMonth: 0, plannedDaysLeftAfterToday: 0, recapShownThisMonth: true) == .first)
    }

    // MARK: §1.5 taps

    @Test func climaxTaps() {
        #expect(HeroPositions.taps(theme: .radiant, pos: .middle) == 5)
        #expect(HeroPositions.taps(theme: .radiant, pos: .bonus) == 5)
        #expect(HeroPositions.taps(theme: .radiant, pos: .last) == 7)
        #expect(HeroPositions.taps(theme: .week, pos: .first) == 7)
    }
}
