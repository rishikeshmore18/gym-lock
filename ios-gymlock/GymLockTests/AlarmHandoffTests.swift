import Foundation
import Testing
@testable import GymLock

/// The note the alarm leaves for the app.
///
/// Small surface, but it is the join between three separate entry paths and the
/// session, and getting it wrong means either two sessions for one alarm or
/// none at all.
struct AlarmHandoffTests {
    /// An isolated suite per test: these would otherwise write into the real
    /// app's defaults and leak between runs.
    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    @Test func writeThenTakeReturnsTheNote() {
        let defaults = makeDefaults()
        let slot = UUID()

        AlarmHandoff.write(
            .init(slotID: slot, firedAt: now, wantsSnooze: true),
            defaults: defaults
        )

        let taken = AlarmHandoff.take(now: now, defaults: defaults)
        #expect(taken?.slotID == slot)
        #expect(taken?.wantsSnooze == true)
        #expect(taken?.firedAt == now)
    }

    @Test func aSecondTakeReturnsNothing() {
        // The intent and the alarmUpdates observer race on purpose. Both write;
        // exactly one may start a session.
        let defaults = makeDefaults()
        AlarmHandoff.write(.init(slotID: UUID(), firedAt: now, wantsSnooze: false), defaults: defaults)

        _ = AlarmHandoff.take(now: now, defaults: defaults)
        #expect(AlarmHandoff.take(now: now, defaults: defaults) == nil)
    }

    @Test func aStaleNoteIsDiscarded() {
        // A note from yesterday morning must never start a session today.
        let defaults = makeDefaults()
        AlarmHandoff.write(.init(slotID: UUID(), firedAt: now, wantsSnooze: false), defaults: defaults)

        let later = now.addingTimeInterval(AlarmHandoff.staleAfter + 1)
        #expect(AlarmHandoff.take(now: later, defaults: defaults) == nil)
    }

    @Test func aNoteInsideTheWindowSurvives() {
        let defaults = makeDefaults()
        AlarmHandoff.write(.init(slotID: UUID(), firedAt: now, wantsSnooze: false), defaults: defaults)

        let later = now.addingTimeInterval(AlarmHandoff.staleAfter - 60)
        #expect(AlarmHandoff.take(now: later, defaults: defaults) != nil)
    }

    @Test func peekDoesNotConsume() {
        // The debug panel reports on the note. It must not eat it.
        let defaults = makeDefaults()
        AlarmHandoff.write(.init(slotID: UUID(), firedAt: now, wantsSnooze: false), defaults: defaults)

        #expect(AlarmHandoff.peek(now: now, defaults: defaults) != nil)
        #expect(AlarmHandoff.peek(now: now, defaults: defaults) != nil)
        #expect(AlarmHandoff.take(now: now, defaults: defaults) != nil)
    }

    @Test func clearRemovesTheNote() {
        let defaults = makeDefaults()
        AlarmHandoff.write(.init(slotID: UUID(), firedAt: now, wantsSnooze: false), defaults: defaults)

        AlarmHandoff.clear(defaults: defaults)
        #expect(AlarmHandoff.peek(now: now, defaults: defaults) == nil)
    }
}
