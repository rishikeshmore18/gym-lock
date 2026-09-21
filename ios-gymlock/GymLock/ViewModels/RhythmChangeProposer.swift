import SwiftUI

/// Shared decision for "the sleep window moved, what happens to the night lock".
///
/// Extracted from `MorningAlarmPlanView` so the alarm settings screen asks the
/// identical question with the identical copy instead of growing a second,
/// slightly different version of the same rule.
@MainActor
enum RhythmChangeProposer {
    /// Asked when the sleep window moves under a night lock the user has
    /// already tuned by hand.
    struct Prompt: Identifiable {
        let id = UUID()
        let proposed: MorningRhythm
    }

    /// Returns a prompt when the user's hand-tuned night lock would be
    /// overwritten by this rhythm change; nil when the change can be applied
    /// without asking.
    ///
    /// No question is needed when the lock is off, or when it already follows
    /// the rhythm and will simply keep doing so.
    static func prompt(
        for updated: MorningRhythm,
        since previous: MorningRhythm,
        plan: MorningPlan
    ) -> Prompt? {
        let sleepWindowMoved = previous.bedtime != updated.bedtime
            || previous.wakeTime != updated.wakeTime

        guard plan.nightLock.isEnabled,
              !plan.nightLock.followsRhythm,
              sleepWindowMoved
        else { return nil }

        return Prompt(proposed: updated)
    }

    /// Applies a rhythm change that needed no question.
    static func apply(_ updated: MorningRhythm, store: AppStore) {
        store.plan.rhythm = updated
        store.applyRhythmToNightLock()
    }

    /// Applies a prompted rhythm change, folding the user's answer into the
    /// night lock. The user tuned the lock by hand; the rhythm change must not
    /// quietly overwrite it.
    static func resolve(
        _ prompt: Prompt,
        adoptingNightLock: Bool,
        store: AppStore
    ) {
        store.plan.rhythm = prompt.proposed
        store.plan.nightLock.followsRhythm = adoptingNightLock
        store.applyRhythmToNightLock()
    }
}

// MARK: - Shared alert

extension View {
    /// The night lock question, presented identically everywhere a rhythm can
    /// change. `onResolved` lets the caller refresh anything it cached, such
    /// as the rhythm snapshot taken when the screen opened.
    func nightLockPromptAlert(
        _ prompt: Binding<RhythmChangeProposer.Prompt?>,
        store: AppStore,
        onResolved: @escaping () -> Void = {}
    ) -> some View {
        alert(item: prompt) { item in
            Alert(
                title: Text("Update Night Lock too?"),
                message: Text(
                    "Your sleep window moved to \(item.proposed.bedtime.displayString) → \(item.proposed.wakeTime.displayString)."
                ),
                primaryButton: .default(Text("Update")) {
                    RhythmChangeProposer.resolve(item, adoptingNightLock: true, store: store)
                    onResolved()
                },
                secondaryButton: .cancel(Text("Keep existing")) {
                    RhythmChangeProposer.resolve(item, adoptingNightLock: false, store: store)
                    onResolved()
                }
            )
        }
    }
}
