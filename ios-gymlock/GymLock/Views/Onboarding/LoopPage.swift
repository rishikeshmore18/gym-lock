import SwiftUI

/// Scene 6 — the loop, and the centrepiece of the story.
///
/// The user never has to work for it: the six states play themselves as a single
/// continuous shot, and the caption changes with them. One unbroken bar along the
/// bottom shows how far through the lap the loop currently is.
///
/// The loop does not stop. Halfway through the first lap the word "break it."
/// appears and the way forward opens — while the loop keeps turning behind it,
/// because that is the point being made. Until that halfway mark the story is
/// held here on purpose.
struct LoopPage: View {
    let isActive: Bool
    /// Called once the loop has played to its halfway mark, which is what
    /// unlocks the rest of the story.
    var onReachHalfway: () -> Void = {}

    /// Seconds each state holds on screen.
    private static let dwell: Double = 1.15
    /// How long the resting overview frame holds before the lap starts.
    private static let openingHold: Double = 1.0
    private static let stepCount = 6
    /// The state after which the way forward opens.
    private static let halfwayStep = 3

    @State private var stateIndex = 0
    /// 0...1 across one lap of the loop, animated linearly through each state
    /// so the bar fills at a constant, honest rate.
    @State private var lapProgress: CGFloat = 0
    @State private var barOpacity: Double = 1
    @State private var isHalfwayReached = false

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
            LoopFilmView(state: state, isPlaying: isActive)
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

    /// One continuous bar filling in real time across the whole lap, so the scene
    /// reads as something running rather than something waiting to be poked.
    ///
    /// A faint notch marks the halfway point while it is still ahead — that is
    /// where the story opens up, and showing it is fairer than silently refusing
    /// the swipe.
    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.ink.opacity(0.10))

                Capsule()
                    .fill(Theme.accent)
                    .frame(width: proxy.size.width * lapProgress)
                    .opacity(barOpacity)

                Capsule()
                    .fill(Theme.ink.opacity(0.22))
                    .frame(width: 2, height: 8)
                    .offset(x: proxy.size.width * 0.5 - 1)
                    .opacity(isHalfwayReached ? 0 : 1)
                    .animation(Theme.settle, value: isHalfwayReached)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    /// Appears once the loop has played to its halfway mark.
    private var breakRow: some View {
        VStack(spacing: 8) {
            Text("break it.")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.accent)

            SwipeUpHint(isActive: isActive && isHalfwayReached)
        }
        .frame(maxWidth: .infinity)
        .opacity(isHalfwayReached ? 1 : 0)
        .offset(y: isHalfwayReached ? 0 : 8)
    }

    // MARK: - The loop, playing itself

    private func run() async {
        guard isActive else {
            stateIndex = 0
            lapProgress = 0
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

                if step == Self.halfwayStep { unlock() }
            }

            lap += 1
            await resetBar()
        }
    }

    /// Opens the way forward. Safe to call repeatedly.
    private func unlock() {
        guard !isHalfwayReached else { return }
        withAnimation(Theme.settle) { isHalfwayReached = true }
        Haptics.commit()
        onReachHalfway()
    }

    /// Returns the bar to empty between laps by fading the fill out rather than
    /// animating it backwards, which would read as undoing progress.
    private func resetBar() async {
        withAnimation(.easeOut(duration: 0.26)) { barOpacity = 0 }
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }

        lapProgress = 0
        withAnimation(.easeIn(duration: 0.2)) { barOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(240))
    }
}
