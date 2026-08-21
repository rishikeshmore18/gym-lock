import SwiftUI

/// System screen 9 — the night half of the loop.
///
/// The bedtime question only appears once the user has admitted the scroll
/// follows them to bed. Asking everyone for a bedtime would be a form; asking
/// only the people who just said yes makes the follow-up feel like listening.
struct NightLoopPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false

    private var answer: NightScrollingFrequency? { store.profile.nightScrollingFrequency }
    private var wantsBedtime: Bool { answer?.wantsBedtime ?? false }

    var body: some View {
        @Bindable var store = store

        SystemScene(topAnchor: 0.09, contentSpacing: 18) {
            SceneHeading(
                title: "does the scroll follow you to bed too?",
                highlighted: ["to bed too?"],
                subtitle: "the night before decides the morning after."
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(NightScrollingFrequency.allCases.enumerated()), id: \.element.id) { index, option in
                    ChoiceRow(
                        label: option.label,
                        isSelected: answer == option,
                        action: { select(option) }
                    )
                    .staggered(index + 1, isShown: contentShown)
                }

                if wantsBedtime {
                    bedtimeSection
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            )
                        )
                }
            }
            .animation(Theme.settle, value: wantsBedtime)
        } footer: {
            SceneContinueButton(
                caption: answer == nil ? "pick whichever is closest." : nil,
                isEnabled: answer != nil,
                action: onContinue
            )
            .staggered(5, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
    }

    @ViewBuilder
    private var bedtimeSection: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 8) {
            Text("when do you want the phone to stop winning?")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)

            HStack(spacing: 14) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.11), in: .circle)

                TimeWheel(time: $store.profile.bedtime, accessibilityTitle: "Bedtime")
                    .frame(height: 132)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
        }
    }

    private func select(_ option: NightScrollingFrequency) {
        Haptics.tap()
        withAnimation(Theme.stateChange) {
            store.profile.nightScrollingFrequency = option
        }
    }
}
