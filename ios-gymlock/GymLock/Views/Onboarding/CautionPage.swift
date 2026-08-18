import SwiftUI

/// Scene 8 — the gate. A quiet, honest filter before the commitment, and the one
/// place in the story where a single element is allowed to pulse.
struct CautionPage: View {
    let isActive: Bool

    @State private var isPulsing = false
    @State private var warningShown = false

    var body: some View {
        OnboardingScene(topAnchor: 0.12, heroMaxHeightFraction: 0.42) {
            AccentedText(
                full: "GymLock is not a motivation app.",
                highlighted: ["not a motivation app."],
                size: 32
            )
            .sceneElement(.headline)
        } hero: {
            IllustrationView(illustration: .cautionSign, isBreathing: false)
                .subtlePulse(isPulsing)
                .breathing(warningShown, amplitude: 2)
                .sceneElement(.hero)
        } footer: {
            VStack(alignment: .leading, spacing: 14) {
                Text("it removes the negotiation.\nthat only helps if you actually want to go.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(5)
                    .opacity(warningShown ? 1 : 0)
                    .offset(y: warningShown ? 0 : 10)

                SwipeUpHint(label: "i'm serious", isActive: isActive && warningShown)
                    .frame(maxWidth: .infinity)
                    .opacity(warningShown ? 1 : 0)
            }
            .sceneElement(.footer)
        }
        .task(id: isActive) {
            guard isActive else {
                isPulsing = false
                warningShown = false
                return
            }

            try? await Task.sleep(for: .milliseconds(560))
            isPulsing = true
            Haptics.soft()
            try? await Task.sleep(for: .milliseconds(680))
            withAnimation(Theme.settle) { warningShown = true }
        }
    }
}
