import SwiftUI

/// Scene 4 — the emotional cost. The artwork already carries the thoughts, so
/// the page adds exactly one line after it settles and nothing else.
struct GuiltPage: View {
    let isActive: Bool

    @State private var verdictShown = false

    var body: some View {
        OnboardingScene(topAnchor: 0.11, heroMaxHeightFraction: 0.46) {
            AccentedText(
                full: "you already know this feeling.",
                highlighted: ["this feeling"],
                size: 33
            )
            .sceneElement(.headline)
        } hero: {
            IllustrationView(illustration: .guiltCouch)
                .sceneElement(.hero)
        } footer: {
            VStack(alignment: .leading, spacing: 16) {
                Text("the missed workout takes an hour.\nthe guilt takes the whole evening.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(5)
                    .opacity(verdictShown ? 1 : 0)
                    .offset(y: verdictShown ? 0 : 10)

                SwipeUpHint(isActive: isActive && verdictShown)
                    .frame(maxWidth: .infinity)
                    .opacity(verdictShown ? 1 : 0)
            }
            .sceneElement(.footer)
        }
        .task(id: isActive) {
            guard isActive else {
                verdictShown = false
                return
            }
            try? await Task.sleep(for: .milliseconds(760))
            withAnimation(Theme.settle) { verdictShown = true }
        }
    }
}
