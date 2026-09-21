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

    @Test func aFollowingWindowTracksABedtimeChange() {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = TimeOfDay(hour: 22, minute: 0)
        rhythm.wakeTime = TimeOfDay(hour: 6, minute: 0)

        var lock = NightLockWindow.default
        lock.isEnabled = true
        lock.followsRhythm = true

        let halfPastTen = date(22, 30)
        #expect(lock.isActive(at: halfPastTen, calendar: calendar, rhythm: rhythm))

        // Pushing bedtime later moves the window with it: 22:30 is now free.
        rhythm.bedtime = TimeOfDay(hour: 23, minute: 30)
        #expect(!lock.isActive(at: halfPastTen, calendar: calendar, rhythm: rhythm))
    }

    @Test func aCustomWindowIgnoresTheRhythm() {
        var rhythm = MorningRhythm.default
        rhythm.bedtime = TimeOfDay(hour: 20, minute: 0)
        rhythm.wakeTime = TimeOfDay(hour: 6, minute: 0)

        var lock = NightLockWindow.default
        lock.isEnabled = true
        lock.followsRhythm = false
        lock.customStart = TimeOfDay(hour: 23, minute: 0)
        lock.customEnd = TimeOfDay(hour: 6, minute: 30)

        // The rhythm says 20:00, but the hand-tuned window says 23:00.
        #expect(!lock.isActive(at: date(20, 30), calendar: calendar, rhythm: rhythm))
        #expect(lock.isActive(at: date(23, 30), calendar: calendar, rhythm: rhythm))
    }

    @Test func aDisabledLockIsNeverActive() {
        var lock = NightLockWindow.default
        lock.isEnabled = false
        lock.followsRhythm = false
        lock.customStart = TimeOfDay(hour: 1, minute: 0)
        lock.customEnd = TimeOfDay(hour: 5, minute: 0)

        #expect(!lock.isActive(at: date(3, 0), calendar: calendar, rhythm: .default))
    }

    // MARK: - The handover

    private func makeShield() throws -> DemoShieldService {
        let suite = "WindDownWindowTests"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return DemoShieldService(defaults: UserDefaults(suiteName: suite)!)
    }

    private func planWithCustomWindow() -> MorningPlan {
        var plan = MorningPlan.default
        plan.nightLock.isEnabled = true
        plan.nightLock.followsRhythm = false
        plan.nightLock.customStart = TimeOfDay(hour: 1, minute: 0)
        plan.nightLock.customEnd = TimeOfDay(hour: 5, minute: 0)
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

        controller.reconcile(now: insideWindow, plan: plan, shield: shield)

        #expect(shield.owner == .windDown)
        #expect(shield.isShielded)

        let shieldedAtHandover = shield.isShielded
        shield.apply(until: insideWindow.addingTimeInterval(2 * 3600), sessionID: UUID(), owner: .gymSession)

        // The one rule the two-second gap bug was about: never off.
        #expect(shieldedAtHandover && shield.isShielded)
        #expect(shield.owner == .gymSession)

        // The night controller sees an owner that is no longer .windDown and
        // stops claiming, even though the window is still open.
        controller.reconcile(now: insideWindow.addingTimeInterval(600), plan: plan, shield: shield)

        #expect(shield.owner == .gymSession)
        #expect(shield.isShielded)
    }

    /// A wind-down shield is released by the clock, nothing else.
    @Test func reconcileLiftsTheShieldWhenTheWindowEnds() throws {
        let shield = try makeShield()
        shield.setDemoSelection(count: 4)

        let plan = planWithCustomWindow()
        let controller = WindDownController()

        controller.reconcile(now: date(3, 0), plan: plan, shield: shield)
        #expect(shield.isShielded)

        controller.reconcile(now: date(5, 30), plan: plan, shield: shield)

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
