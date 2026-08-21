import SwiftUI

/// System screen 7 — what actually wins.
///
/// Multi-select, because the honest answer is usually two or three of these at
/// once. The options are written in the user's own voice rather than as
/// diagnoses: "i start scrolling", not "excessive screen time".
struct FailureReasonsPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false

    private var chosen: Set<FailureReason> { store.profile.failureReasons }

    var body: some View {
        SystemScene(topAnchor: 0.09) {
            SceneHeading(
                title: "and what usually wins?",
                highlighted: ["wins?"],
                subtitle: "select all that apply"
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 8) {
                ForEach(Array(FailureReason.allCases.enumerated()), id: \.element.id) { index, reason in
                    ChoiceRow(
                        label: reason.label,
                        icon: reason.icon,
                        isSelected: chosen.contains(reason),
                        allowsMultiple: true,
                        action: { toggle(reason) }
                    )
                    .staggered(index + 1, isShown: contentShown)
                }
            }
        } footer: {
            SceneContinueButton(
                caption: chosen.isEmpty ? "pick at least one. it stays private." : nil,
                isEnabled: !chosen.isEmpty,
                action: onContinue
            )
            .staggered(8, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
    }

    private func toggle(_ reason: FailureReason) {
        Haptics.tap()
        withAnimation(Theme.stateChange) {
            if store.profile.failureReasons.contains(reason) {
                store.profile.failureReasons.remove(reason)
            } else {
                store.profile.failureReasons.insert(reason)
            }
        }
    }
}
