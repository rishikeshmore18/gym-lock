import SwiftUI

/// System screen 1 — the handshake.
///
/// The warning screen before this one gave the user a way out. This one accepts
/// that they did not take it, and the whole screen is built around a single
/// deliberate act: a button that has to be *held*, not tapped. Everything else
/// is quiet so that one gesture carries the weight.
struct CommitmentPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @State private var accepted = false
    @State private var promiseShown = false
    @State private var actionShown = false

    var body: some View {
        QuietScene {
            VStack(alignment: .leading, spacing: 20) {
                // "okay." lands on its own first — the app answering the user,
                // before it starts asking for anything.
                Text("okay.")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .opacity(accepted ? 1 : 0)
                    .offset(y: accepted ? 0 : 12)

                AccentedText(
                    full: "then let's build this around you.",
                    highlighted: ["around you."],
                    size: 34
                )
                .opacity(promiseShown ? 1 : 0)
                .offset(y: promiseShown ? 0 : 12)

                Text("not another routine.\nyour actual system.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(4)
                    .opacity(promiseShown ? 1 : 0)
                    .offset(y: promiseShown ? 0 : 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            HoldToCommitButton(
                title: "i'm serious",
                caption: "press and hold",
                onComplete: onContinue
            )
            .opacity(actionShown ? 1 : 0)
            .offset(y: actionShown ? 0 : 10)
        }
        .task(id: isActive) { await run() }
    }

    private func run() async {
        guard isActive else {
            accepted = false
            promiseShown = false
            actionShown = false
            return
        }

        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { accepted = true }

        try? await Task.sleep(for: .milliseconds(620))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { promiseShown = true }

        try? await Task.sleep(for: .milliseconds(560))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { actionShown = true }
    }
}
