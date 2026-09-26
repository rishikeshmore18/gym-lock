import Foundation
import Testing
@testable import GymLock

/// The wind-down lock's clock maths and its ownership rules.
///
/// The midnight wrap is the thing that breaks: a 23:00 → 06:30 window must be
/// active at 23:30 and again at 02:00, and must be over at exactly 06:30.
/// The handover test pins the rule that a gym session beginning inside the
/// window takes the shield without ever switching it off.
@Suite("Wind-down window")
@MainActor
struct WindDownWindowTests {
    /// Fixed timezone so the tests do not move with the CI machine.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// A Tuesday in March 2026, comfortably before the DST transition.
    private var referenceDay: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: referenceDay)!
    }

    /// The window from the product copy: 11:00 PM to 6:30 AM.
    private var nightStart: TimeOfDay { TimeOfDay(hour: 23, minute: 0) }
    private var nightEnd: TimeOfDay { TimeOfDay(hour: 6, minute: 30) }

    // MARK: - The midnight wrap

    @Test func isActiveLateInTheEvening() {
        #expect(
            WindDownLock.isActive(
                start: nightStart, end: nightEnd, at: date(23, 30), calendar: calendar
            )
        )
    }

    /// 02:00 belongs to the window that started at 23:00 the night before.
    @Test func isActiveAfterMidnight() {
        #expect(
            WindDownLock.isActive(
                start: nightStart, end: nightEnd, at: date(2, 0), calendar: calendar
            )
        )
    }

    @Test func isInactiveBeforeTheWindowOpens() {
        #expect(
            !WindDownLock.isActive(
                start: nightStart, end: nightEnd, at: date(22, 59), calendar: calendar
            )
        )
    }

    /// The end is exclusive: at wake time the night lock is already over.
    @Test func isInactiveAtTheEndExactly() {
        #expect(
            !WindDownLock.isActive(
                start: nightStart, end: nightEnd, at: date(6, 30), calendar: calendar
            )
        )
    }

    /// A daytime reading must not land in either candidate window.
    @Test func isInactiveMidday() {
        #expect(
            !WindDownLock.isActive(
                start: nightStart, end: nightEnd, at: date(12, 0), calendar: calendar
            )
        )
    }

    /// A same-day window without a wrap works too.
    @Test func nonWrappingWindowIsContained() {
        let start = TimeOfDay(hour: 1, minute: 0)
        let end = TimeOfDay(hour: 5, minute: 0)

        #expect(WindDownLock.isActive(start: start, end: end, at: date(3, 0), calendar: calendar))
        #expect(!WindDownLock.isActive(start: start, end: end, at: date(0, 30), calendar: calendar))
        #expect(!WindDownLock.isActive(start: start, end: end, at: date(5, 0), calendar: calendar))
    }

    // MARK: - Degenerate windows

    /// start == end means switched off, never twenty-four hours of lock.
    @Test func startEqualsEndIsDisabled() {
        #expect(
            !WindDownLock.isActive(
                start: nightStart, end: nightStart, at: date(23, 30), calendar: calendar
            )
        )
        #expect(
            !WindDownLock.isActive(
                start: nightStart, end: nightStart, at: date(11, 0), calendar: calendar
            )
        )
    }

    // MARK: - Following the rhythm

    private func isLocked(_ rhythm: MorningRhythm, at now: Date) -> Bool {
        SleepRules.lockWindow(
            at: now, rhythm: rhythm, pending: nil,
            nights: Set(Weekday.allCases), calendar: calendar
        ) != nil
    }

    @Test func theLockAlwaysRunsFromBedtimeToWakeTime() {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = TimeOfDay(hour: 22, minute: 0)
        rhythm.wakeTime = TimeOfDay(hour: 6, minute: 0)

        #expect(isLocked(rhythm, at: date(22, 30)))
        #expect(isLocked(rhythm, at: date(2, 0)))
        #expect(!isLocked(rhythm, at: date(6, 0)))

        // Bedtime itself moves the window: 22:30 is free at a 23:30 bedtime.
        rhythm.bedtime = TimeOfDay(hour: 23, minute: 30)
        #expect(!isLocked(rhythm, at: date(22, 30)))
    }

    /// Night workers: the lock follows their own hours, whatever they are.
    @Test func aDaytimeSleepScheduleLocksDuringTheDay() {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = TimeOfDay(hour: 9, minute: 0)
        rhythm.wakeTime = TimeOfDay(hour: 16, minute: 0)

        #expect(isLocked(rhythm, at: date(12, 0)))
        #expect(!isLocked(rhythm, at: date(23, 0)))
    }

    // MARK: - The handover

    private func makeShield() throws -> DemoShieldService {
        let suite = "WindDownWindowTests"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return DemoShieldService(defaults: UserDefaults(suiteName: suite)!)
    }

    /// Sleep 01:00 → 06:00, every night.
    private func planWithCustomWindow() -> MorningPlan {
        var plan = MorningPlan.default
        plan.rhythm.bedtime = TimeOfDay(hour: 1, minute: 0)
        plan.rhythm.wakeTime = TimeOfDay(hour: 5, minute: 0)
        return plan
    }

    /// A gym session beginning inside the wind-down window takes the shield
    /// over in one step: continuously applied, owner flipped, and the
    /// wind-down controller never reclaims it afterwards.
    @Test func handoverLeavesTheShieldAppliedAndFlipsTheOwner() throws {
        let shield = try makeShield()
        shield.setDemoSelection(count: 4)

        let plan = planWithCustomWindow()
        let controller = WindDownController()
        let insideWindow = date(3, 0)

        controller.reconcile(now: insideWindow, plan: plan, shield: shield, calendar: calendar)

        #expect(shield.owner == .windDown)
        #expect(shield.isShielded)

        let shieldedAtHandover = shield.isShielded
        shield.apply(until: insideWindow.addingTimeInterval(2 * 3600), sessionID: UUID(), owner: .gymSession)

        // The one rule the two-second gap bug was about: never off.
        #expect(shieldedAtHandover && shield.isShielded)
        #expect(shield.owner == .gymSession)

        // The night controller sees an owner that is no longer .windDown and
        // stops claiming, even though the window is still open.
        controller.reconcile(now: insideWindow.addingTimeInterval(600), plan: plan, shield: shield, calendar: calendar)

        #expect(shield.owner == .gymSession)
        #expect(shield.isShielded)
    }

    /// A wind-down shield is released by the clock, nothing else.
    @Test func reconcileLiftsTheShieldWhenTheWindowEnds() throws {
        let shield = try makeShield()
        shield.setDemoSelection(count: 4)

        let plan = planWithCustomWindow()
        let controller = WindDownController()

        controller.reconcile(now: date(3, 0), plan: plan, shield: shield, calendar: calendar)
        #expect(shield.isShielded)

        controller.reconcile(now: date(5, 30), plan: plan, shield: shield, calendar: calendar)

        #expect(!shield.isShielded)
        #expect(shield.owner == nil)
    }

    /// An old ledger, written before the wind-down lock existed, must decode
    /// as session-owned rather than failing.
    @Test func ledgersFromBeforeTheOwnerExistedDecodeAsSessionOwned() throws {
        // Default JSON encoding writes dates as seconds since the reference
        // date, so a hand-written ledger only needs plausible numbers.
        let legacyJSON = """
        {
          "appliedAt": 750000000.0,
          "failsafeDeadline": 750003600.0,
          "sessionID": "7A4B2F1C-0000-4000-8000-000000000001"
        }
        """
        let ledger = try JSONDecoder().decode(ShieldLedger.self, from: Data(legacyJSON.utf8))
        #expect(ledger.owner == .gymSession)
    }
}
