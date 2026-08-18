import SwiftUI

/// Scene 3 — the app proves it remembered the name, then names the real pattern.
/// Deliberately quiet and vertically centred: one thought, lots of air.
struct GreetingPage: View {
    let isActive: Bool
    let name: String

    @State private var bodyShown = false

    var body: some View {
        QuietScene {
            VStack(alignment: .leading, spacing: 0) {
                AccentedText(
                    full: "hi, \(name).",
                    highlighted: [name],
                    size: 46
                )
                .sceneElement(.headline)

                Text("most people don't miss the gym because they're lazy.")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(6)
                    .padding(.top, 24)
                    .sceneElement(.support)

                Text("they miss it because the moment always wins.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(4)
                    .padding(.top, 14)
                    .opacity(bodyShown ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            SwipeUpHint(label: "see how", isActive: isActive && bodyShown)
                .opacity(bodyShown ? 1 : 0)
        }
        .task(id: isActive) {
            guard isActive else { return }
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(Theme.settle) { bodyShown = true }
        }
    }
}
