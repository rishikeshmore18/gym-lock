import SwiftUI

/// Page 3 — the app proves it remembered the name, then names the real pattern.
struct GreetingPage: View {
    let isActive: Bool
    let name: String

    @State private var greetingShown = false
    @State private var bodyShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            AccentedText(
                full: "hi, \(name).",
                highlighted: [name],
                size: 46
            )
            .opacity(greetingShown ? 1 : 0)
            .offset(y: greetingShown ? 0 : 14)

            Text("most people don't fail because they're lazy.\nthey fail because their phone wins in the moment.")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineSpacing(6)
                .padding(.top, 22)
                .opacity(bodyShown ? 1 : 0)
                .offset(y: bodyShown ? 0 : 12)

            Text("let's change that.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 18)
                .opacity(bodyShown ? 1 : 0)

            Spacer()

            SwipeUpHint(isActive: isActive && bodyShown)
                .frame(maxWidth: .infinity)
                .opacity(bodyShown ? 1 : 0)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: isActive) {
            guard isActive else { return }
            withAnimation(Theme.settle) { greetingShown = true }
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(Theme.settle) { bodyShown = true }
        }
    }
}
