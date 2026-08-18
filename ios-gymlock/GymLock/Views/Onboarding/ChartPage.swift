import SwiftUI

/// Scene 7 — the argument. Both curves leave the same point in week one, so the
/// only variable on screen is the mechanism.
struct ChartPage: View {
    let isActive: Bool

    @State private var drawProgress: CGFloat = 0
    @State private var legendShown = false

    var body: some View {
        OnboardingScene(topAnchor: 0.13, heroMaxHeightFraction: 0.40) {
            VStack(alignment: .leading, spacing: 10) {
                AccentedText(
                    full: "willpower fades. systems don't.",
                    highlighted: ["systems don't."],
                    size: 32
                )

                Text("same start. same person. different mechanism.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .sceneElement(.headline)
        } hero: {
            RetentionChart(progress: drawProgress)
                .padding(18)
                .warmCard()
                .sceneElement(.hero)
        } footer: {
            VStack(alignment: .leading, spacing: 14) {
                legend
                    .opacity(legendShown ? 1 : 0)
                    .offset(y: legendShown ? 0 : 8)

                SwipeUpHint(isActive: isActive && legendShown)
                    .frame(maxWidth: .infinity)
                    .opacity(legendShown ? 1 : 0)
            }
            .sceneElement(.footer)
        }
        .task(id: isActive) {
            guard isActive else {
                drawProgress = 0
                legendShown = false
                return
            }

            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.easeInOut(duration: 1.9)) { drawProgress = 1 }
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(Theme.settle) { legendShown = true }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 9) {
            legendRow(
                color: Theme.inkTertiary,
                isDashed: true,
                text: "motivation — decides every single morning"
            )
            legendRow(
                color: Theme.accent,
                isDashed: false,
                text: "a forcing function — decides once"
            )
        }
    }

    private func legendRow(color: Color, isDashed: Bool, text: String) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(color)
                .frame(width: isDashed ? 8 : 22, height: 3)
                .frame(width: 22, alignment: .leading)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}
