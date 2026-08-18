import SwiftUI

/// Scene 5 — the emotional cost. The artwork already carries the thoughts, so
/// the page adds exactly one line after it settles and nothing else.
///
/// The line is addressed to the user by name: this is the first moment in the
/// story that accuses them of something, and it lands harder signed.
struct GuiltPage: View {
    let isActive: Bool
    let name: String

    @State private var verdictShown = false

    var body: some View {
        OnboardingScene(topAnchor: 0.11, heroMaxHeightFraction: 0.46) {
            AccentedText(
                full: "\(name), you already know this feeling.",
                highlighted: ["this feeling"],
                size: 32
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
