import SwiftUI

/// Scene 7 — the reasons. The artwork carries the scene; the page's one moving
/// part is a picker-style wheel of the reasons themselves, turning endlessly.
///
/// The reasons are deliberately reasonable. Nothing here blames the user.
struct ExcusesPage: View {
    let isActive: Bool
    let name: String

    /// The reasons, in wheel order. The wheel wraps, so there is no last one.
    private static let reasons: [String] = [
        "work deadline",
        "family matters",
        "not enough time",
        "unexpected events",
        "feeling drained",
    ]

    /// Seconds each reason holds before the wheel turns again.
    private static let dwell: Double = 0.85

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var wheelPosition: Double = 0
    @State private var verdictShown = false

    var body: some View {
        OnboardingScene(topAnchor: 0.10, heroMaxHeightFraction: 0.40) {
            AccentedText(
                full: "not every miss is your fault, \(name). life gets in the way.",
                highlighted: ["life gets in the way."],
                size: 30
            )
            .sceneElement(.headline)
        } hero: {
            IllustrationView(illustration: .excusesDesk)
                .sceneElement(.hero)
        } footer: {
            VStack(alignment: .leading, spacing: 14) {
                reasonWheel

                SwipeUpHint(isActive: isActive && verdictShown)
                    .frame(maxWidth: .infinity)
                    .opacity(verdictShown ? 1 : 0)
            }
            .sceneElement(.footer)
        }
        .task(id: isActive) { await run() }
    }

    /// A short picker window: one reason in focus, the neighbours just visible
    /// at its edges so the wheel reads as continuous.
    private var reasonWheel: some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: 3, height: 30)

            WordWheel(
                words: Self.reasons,
                position: wheelPosition,
                size: 24,
                weight: .semibold,
                rowHeight: reduceMotion ? 0 : 42,
                reach: reduceMotion ? 0 : 2,
                isBlurred: !reduceMotion
            )
        }
        .frame(height: 84)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reasons: " + Self.reasons.joined(separator: ", "))
    }

    // MARK: - The wheel, turning on its own

    private func run() async {
        guard isActive else {
            wheelPosition = 0
            verdictShown = false
            return
        }

        Haptics.prepareSelection()
        try? await Task.sleep(for: .milliseconds(620))

        var step = 0

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.dwell))
            if Task.isCancelled { return }

            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.24)
                    : .timingCurve(0.25, 0.9, 0.25, 1, duration: 0.42)
            ) {
                wheelPosition += 1
            }

            // Ticks for the first cycle only, then the wheel turns quietly.
            if step < Self.reasons.count { Haptics.selection() }

            step += 1
            if step == Self.reasons.count {
                withAnimation(Theme.settle) { verdictShown = true }
            }
        }
    }
}
