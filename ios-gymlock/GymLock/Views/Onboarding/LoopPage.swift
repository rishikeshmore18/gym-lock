import SwiftUI

/// Scene 6 — the loop, and the centrepiece of the story.
///
/// The diagram never moves and the user never has to work for it: the six states
/// play themselves, the artwork crossfades in place, and the caption changes with
/// it. A segmented bar along the bottom shows how far through the lap the loop
/// currently is.
///
/// The loop does not stop. Once a full lap has played, the word "break it."
/// appears and the way forward opens — while the loop keeps turning behind it,
/// because that is the point being made.
struct LoopPage: View {
    let isActive: Bool

    /// Seconds each state holds on screen.
    private static let dwell: Double = 1.25
    /// How long the resting overview frame holds before the lap starts.
    private static let openingHold: Double = 1.0
    private static let stepCount = 6

    @State private var stateIndex = 0
    /// 0...1 across one lap of the loop, animated linearly through each state
    /// so the bar fills at a constant, honest rate.
    @State private var lapProgress: CGFloat = 0
    @State private var hasCompletedLap = false

    private var state: LoopState {
        let clamped = min(max(stateIndex, 0), LoopState.sequence.count - 1)
        return LoopState.sequence[clamped]
    }

    var body: some View {
        OnboardingScene(topAnchor: 0.10, heroMaxHeightFraction: 0.40) {
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

                progressBar

                breakRow
            }
            .sceneElement(.footer)
        }
        .task(id: isActive) { await run() }
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

    /// Six segments that fill in real time as each state plays, so the scene
    /// reads as something running rather than something waiting to be poked.
    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(1...Self.stepCount, id: \.self) { step in
                let fill = min(max(lapProgress * CGFloat(Self.stepCount) - CGFloat(step - 1), 0), 1)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.ink.opacity(0.10))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent)
                                .frame(width: proxy.size.width * fill)
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    /// Appears once the loop has come all the way around.
    private var breakRow: some View {
        VStack(spacing: 8) {
            Text("break it.")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.accent)

            SwipeUpHint(isActive: isActive && hasCompletedLap)
        }
        .frame(maxWidth: .infinity)
        .opacity(hasCompletedLap ? 1 : 0)
        .offset(y: hasCompletedLap ? 0 : 8)
    }

    // MARK: - The loop, playing itself

    private func run() async {
        guard isActive else {
            stateIndex = 0
            lapProgress = 0
            hasCompletedLap = false
            return
        }

        // Open on the resting overview frame, so the diagram is legible before
        // it starts changing state.
        try? await Task.sleep(for: .seconds(Self.openingHold))
        guard !Task.isCancelled else { return }

        var lap = 0

        while !Task.isCancelled {
            for step in 1...Self.stepCount {
                withAnimation(.easeInOut(duration: 0.34)) { stateIndex = step }
                withAnimation(.linear(duration: Self.dwell)) {
                    lapProgress = CGFloat(step) / CGFloat(Self.stepCount)
                }

                // Only the first lap ticks; after that the loop turns quietly.
                if lap == 0 { Haptics.tap() }

                try? await Task.sleep(for: .seconds(Self.dwell))
                if Task.isCancelled { return }
            }

            lap += 1

            if !hasCompletedLap {
                withAnimation(Theme.settle) { hasCompletedLap = true }
                Haptics.commit()
            }

            // A short breath at the top of the loop, then it starts over.
            withAnimation(.easeOut(duration: 0.3)) { lapProgress = 0 }
            try? await Task.sleep(for: .milliseconds(420))
        }
    }
}
