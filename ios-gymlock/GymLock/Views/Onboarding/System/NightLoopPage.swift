import SwiftUI

/// System screen 9, the night half of the loop.
///
/// The scrolling question stays, but everyone is asked for a bedtime and a
/// wake time: the night lock runs for everyone (FLOW, "The Night Lock").
struct NightLoopPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false

    private var answer: NightScrollingFrequency? { store.profile.nightScrollingFrequency }

    private var meetsSleepMinimum: Bool {
        MorningRhythm.meetsSleepMinimum(
            bedtime: store.profile.bedtime,
            wake: store.profile.answeredWakeTime
        )
    }

    private var caption: String? {
        if answer == nil { return "pick whichever is closest." }
        if !meetsSleepMinimum { return MorningRhythm.sleepMinimumMessage }
        return nil
    }

    var body: some View {
        SystemScene(topAnchor: 0.06, contentSpacing: 14) {
            SceneHeading(
                title: "does the scroll follow you to bed too?",
                highlighted: ["to bed too?"],
                subtitle: "the night before decides the morning after."
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(NightScrollingFrequency.allCases.enumerated()), id: \.element.id) { index, option in
                    ChoiceRow(
                        label: option.label,
                        isSelected: answer == option,
                        action: { select(option) }
                    )
                    .staggered(index + 1, isShown: contentShown)
                }

                sleepTimes
                    .staggered(4, isShown: contentShown)
            }
        } footer: {
            SceneContinueButton(
                caption: caption,
                isEnabled: answer != nil && meetsSleepMinimum,
                action: onContinue
            )
            .staggered(5, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
    }

    // PLACEHOLDER UI: designed in Step 3
    @ViewBuilder
    private var sleepTimes: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 4) {
            wheelRow(
                icon: "moon.fill",
                label: "bedtime",
                time: $store.profile.bedtime,
                accessibilityTitle: "Bedtime"
            )
            wheelRow(
                icon: "sun.max.fill",
                label: "wake up",
                time: Binding(
                    get: { store.profile.answeredWakeTime },
                    set: { store.profile.wakeTime = $0 }
                ),
                accessibilityTitle: "Wake time"
            )
        }
        .padding(.top, 4)
    }

    private func wheelRow(
        icon: String,
        label: String,
        time: Binding<TimeOfDay>,
        accessibilityTitle: String
    ) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(width: 64)

            TimeWheel(time: time, accessibilityTitle: accessibilityTitle)
                .frame(height: 92)
        }
        .padding(.horizontal, 12)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }

    private func select(_ option: NightScrollingFrequency) {
        Haptics.tap()
        withAnimation(Theme.stateChange) {
            store.profile.nightScrollingFrequency = option
        }
    }
}
