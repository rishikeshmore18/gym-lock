import SwiftUI

/// Whether gym-bag missions are on, as a card.
///
/// Extracted from `MorningAlarmPlanView` so the alarm settings screen carries
/// the identical control. The tint is a parameter: the alarm settings screen
/// keeps its single coral accent for the dial, so its toggles render in ink.
struct MissionToggleCard: View {
    var tint: Color = Theme.accent

    @Environment(AppStore.self) private var store

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.plan.missionsEnabled },
            set: { store.plan.missionsEnabled = $0; Haptics.tap() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("activation mission")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("one tiny action after you commit.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .tint(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .warmCard(radius: 18)
    }
}
