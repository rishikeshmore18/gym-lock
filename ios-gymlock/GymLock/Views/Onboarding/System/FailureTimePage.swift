import SwiftUI

/// System screen 6 — the exact moment.
///
/// A bare "around what time?" would be a form field. The framing here asks the
/// user to picture a specific recurring moment — the one where they meant to go
/// and did something else — because that memory is what makes the alarm on
/// screen 16 feel aimed rather than scheduled.
struct FailureTimePage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false

    var body: some View {
        @Bindable var store = store

        SystemScene(topAnchor: 0.09) {
            SceneHeading(
                title: "around what time does the gym usually get skipped?",
                highlighted: ["get skipped?"],
                subtitle: "think about the moment you planned to go, but usually end up doing something else instead.",
                footnote: "this helps GymLock step in at the right moment.",
                size: 28
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 12) {
                TimeWheel(time: $store.profile.failureTime, accessibilityTitle: "Skipped time")

                Text(store.profile.failureTime.displayString.lowercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .contentTransition(.numericText())
                    .animation(Theme.stateChange, value: store.profile.failureTime)
                    .frame(maxWidth: .infinity)
            }
            .staggered(1, isShown: contentShown)
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(2, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
    }
}
