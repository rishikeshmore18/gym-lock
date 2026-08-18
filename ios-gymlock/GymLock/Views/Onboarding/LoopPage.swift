import SwiftUI

/// Scene 5 — the pinned narrative, and the centrepiece of the story.
///
/// The diagram never moves. Each swipe advances one node of the loop, the
/// artwork crossfades in place, and the caption beneath it changes. This is why
/// the loop reads as one thing changing state rather than seven screens.
struct LoopPage: View {
    let isActive: Bool
    /// Index into `LoopState.sequence`, owned by the flow and driven by swipes.
    let step: Int

    private var state: LoopState {
        let clamped = min(max(step, 0), LoopState.sequence.count - 1)
        return LoopState.sequence[clamped]
    }

    private var isFinalState: Bool {
        state.id == LoopState.sequence.count - 1
    }

    var body: some View {
        OnboardingScene(topAnchor: 0.10, heroMaxHeightFraction: 0.48) {
            VStack(alignment: .leading, spacing: 10) {
                AccentedText(
                    full: "it's not laziness. it's a loop.",
                    highlighted: ["a loop."],
                    size: 32
                )

                Text("six steps that repeat every week.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .sceneElement(.headline)
        } hero: {
            LoopDiagramView(state: state)
                .sceneElement(.hero)
        } footer: {
            VStack(alignment: .leading, spacing: 14) {
                caption

                stepRail

                SwipeUpHint(
                    label: isFinalState ? "break it" : "keep going",
                    isActive: isActive
                )
                .frame(maxWidth: .infinity)
            }
            .sceneElement(.footer)
        }
    }

    /// The caption swaps with the state, matched to the highlighted node.
    private var caption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let number = state.nodeNumber {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.accent, in: .circle)
                    .transition(.opacity)
            }

            Text(state.caption)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(state.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.28), value: state.id)
        .frame(minHeight: 52, alignment: .top)
    }

    /// Six ticks showing how far through the loop the user has swiped.
    private var stepRail: some View {
        HStack(spacing: 5) {
            ForEach(LoopState.sequence.dropFirst()) { candidate in
                let isReached = state.nodeNumber.map { candidate.id <= $0 } ?? false

                Capsule()
                    .fill(isReached ? Theme.accent : Theme.ink.opacity(0.12))
                    .frame(height: 3)
                    .animation(Theme.stateChange, value: isReached)
            }
        }
        .accessibilityHidden(true)
    }
}
