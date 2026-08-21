import SwiftUI

/// System screen 5 — where the plan breaks.
///
/// Everything downstream hangs off this answer: it decides when the alarm fires,
/// when the apps lock, and what the timeline on screen 16 looks like. "Something
/// else" opens a field rather than being a dead end, because the users whose
/// week does not fit four buckets are exactly the ones most likely to churn.
struct FailureWindowPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false

    private var selected: FailureWindow? { store.profile.failureWindow }

    var body: some View {
        @Bindable var store = store

        SystemScene(topAnchor: 0.10) {
            SceneHeading(
                title: "when does your plan usually fall apart?",
                highlighted: ["fall apart?"],
                subtitle: "there's a pattern. we just need to find it."
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 9) {
                ForEach(Array(FailureWindow.allCases.enumerated()), id: \.element.id) { index, window in
                    ChoiceRow(
                        label: window.label,
                        isSelected: selected == window,
                        action: { select(window) }
                    )
                    .staggered(index + 1, isShown: contentShown)
                }

                OtherDetailField(
                    placeholder: "tell us what usually happens…",
                    text: $store.profile.failureWindowOther,
                    isShown: selected == .other
                )
            }
        } footer: {
            SceneContinueButton(
                caption: selected == nil ? "pick the one that sounds most like you." : nil,
                isEnabled: selected != nil,
                action: onContinue
            )
            .staggered(7, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
    }

    private func select(_ window: FailureWindow) {
        Haptics.tap()
        withAnimation(Theme.stateChange) {
            store.profile.failureWindow = window
        }

        // Pre-position the time wheel on the next screen so the user usually
        // only has to nudge it rather than dial it in from scratch.
        store.profile.failureTime = window.suggestedTime
    }
}
