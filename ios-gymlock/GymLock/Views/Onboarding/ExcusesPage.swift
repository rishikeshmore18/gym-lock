import SwiftUI

/// Scene 6 — the reasons. The artwork carries five of them, so the page's one
/// micro-payoff is a counter that ticks up and then delivers the verdict.
struct ExcusesPage: View {
    let isActive: Bool

    @State private var count = 0
    @State private var verdictShown = false

    private let totalReasons = 5

    var body: some View {
        OnboardingScene(topAnchor: 0.11, heroMaxHeightFraction: 0.44) {
            AccentedText(
                full: "and every miss has a good reason.",
                highlighted: ["a good reason."],
                size: 32
            )
            .sceneElement(.headline)
        } hero: {
            IllustrationView(illustration: .excusesDesk)
                .sceneElement(.hero)
        } footer: {
            VStack(alignment: .leading, spacing: 14) {
                counterRow

                Text("all of them are true. none of them help.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .opacity(verdictShown ? 1 : 0)
                    .offset(y: verdictShown ? 0 : 8)

                SwipeUpHint(isActive: isActive && verdictShown)
                    .frame(maxWidth: .infinity)
                    .opacity(verdictShown ? 1 : 0)
            }
            .sceneElement(.footer)
        }
        .task(id: isActive) {
            guard isActive else {
                count = 0
                verdictShown = false
                return
            }

            try? await Task.sleep(for: .milliseconds(620))
            for value in 1...totalReasons {
                withAnimation(.easeOut(duration: 0.2)) { count = value }
                Haptics.tap()
                try? await Task.sleep(for: .milliseconds(220))
            }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(Theme.settle) { verdictShown = true }
        }
    }

    private var counterRow: some View {
        HStack(spacing: 10) {
            Text("\(count)")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText())

            Text("legitimate reasons\nthis week alone")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) legitimate reasons this week alone")
    }
}
