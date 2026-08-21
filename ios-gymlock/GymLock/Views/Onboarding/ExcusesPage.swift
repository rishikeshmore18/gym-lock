import SwiftUI

/// Scene 7 — the reasons. The artwork carries the scene; the page's one moving
/// part is a picker-style wheel of the reasons themselves.
///
/// The user lands on the wheel already at speed. It arrives blurred and
/// unreadable, brakes through three stages, and picks a reason — the same
/// grammar as a slot machine coming to rest. Nothing static is ever shown first:
/// a wheel that sits still and then starts turning reads as a list being
/// animated, while a wheel that is already turning reads as something the user
/// interrupted.
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

    /// Seconds each reason holds once the wheel has settled into its slow turn.
    private static let dwell: Double = 1.05
    /// Blur while the wheel is at full speed. This is the scene's entrance: the
    /// wheel resolves from unreadable to sharp rather than fading in.
    private static let spinBlurMax: CGFloat = 6.0
    /// Where the wheel comes to rest after the brake.
    private static let restPosition: Double = 12
    /// Ticks stop after the wheel has been round once on its own.
    private static let quietTickLimit = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var wheelPosition: Double = 0
    @State private var spinBlur: CGFloat = ExcusesPage.spinBlurMax
    @State private var hintShown = false

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

                SwipeUpHint(isActive: isActive && hintShown)
                    .frame(maxWidth: .infinity)
                    .opacity(hintShown ? 1 : 0)
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
            .blur(radius: reduceMotion ? 0 : spinBlur)
        }
        .frame(height: 84)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reasons: " + Self.reasons.joined(separator: ", "))
    }

    // MARK: - The wheel, braking on arrival

    private func run() async {
        guard isActive else {
            reset()
            return
        }

        Haptics.prepareSelection()

        await brakeIntoPlace()
        guard !Task.isCancelled else { return }

        withAnimation(Theme.settle) { hintShown = true }

        await turnQuietly()
    }

    private func reset() {
        wheelPosition = 0
        spinBlur = Self.spinBlurMax
        hintShown = false
    }

    /// Four stages from full speed to a picked word. The stage boundaries are
    /// where the ticks land, so each one coincides with a real row crossing the
    /// centre rather than being decorative.
    private func brakeIntoPlace() async {
        guard !reduceMotion else {
            spinBlur = 0
            withAnimation(.easeInOut(duration: 0.3)) { wheelPosition = Self.restPosition }
            try? await Task.sleep(for: .milliseconds(320))
            return
        }

        // Stage 0 — full speed, unreadable. Roughly sixteen rows a second.
        spinBlur = Self.spinBlurMax
        withAnimation(.linear(duration: 0.44)) { wheelPosition = 7 }
        try? await Task.sleep(for: .milliseconds(430))
        guard !Task.isCancelled else { return }

        // Stage 1 — speed comes off and the words start to become legible.
        withAnimation(.easeOut(duration: 0.40)) {
            wheelPosition = 10.6
            spinBlur = 3.0
        }
        try? await Task.sleep(for: .milliseconds(390))
        guard !Task.isCancelled else { return }
        Haptics.selection()

        // Stage 2 — the last row and a bit, almost sharp.
        withAnimation(.easeOut(duration: 0.36)) {
            wheelPosition = Self.restPosition - 0.3
            spinBlur = 1.2
        }
        try? await Task.sleep(for: .milliseconds(340))
        guard !Task.isCancelled else { return }
        Haptics.selection()

        // Stage 3 — settles onto the picked reason.
        withAnimation(.timingCurve(0.16, 0.9, 0.2, 1, duration: 0.6)) {
            wheelPosition = Self.restPosition
            spinBlur = 0
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        Haptics.selection()
    }

    /// After the brake the wheel keeps turning, one reason at a time, so the
    /// scene stays alive while the user reads.
    private func turnQuietly() async {
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

            if step < Self.quietTickLimit { Haptics.selection() }
            step += 1
        }
    }
}
