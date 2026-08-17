import SwiftUI

/// Page 6 — "Problem" stays put while the cause rolls beside it like a lottery
/// machine: slow enough to read at first, then accelerating. When the roll
/// settles the sentence moves up and the loop diagram takes the page.
struct ProblemCyclePage: View {
    let isActive: Bool

    private enum Phase {
        case idle
        case rolling
        case revealed
    }

    @State private var phase: Phase = .idle
    @State private var phrase: String = ProblemCycle.phrases[0]
    @State private var activeNodeIndex: Int?
    @State private var ringProgress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: phase == .revealed ? 18 : 0)

            if phase != .revealed {
                Spacer()
            }

            roller
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.pageMargin)

            if phase == .revealed {
                Text("one loop. not twelve separate problems.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            if phase != .revealed {
                Spacer()
            }

            if phase == .revealed {
                CycleDiagram(activeNodeIndex: activeNodeIndex, revealProgress: ringProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 4)
                    .transition(.opacity)

                SwipeUpHint(isActive: isActive)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 26)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.settle, value: phase)
        .task(id: isActive) {
            guard isActive, phase == .idle else { return }
            await runSequence()
        }
    }

    // MARK: - Inline roller

    /// `Problem` is fixed; only the cause changes, on the very same line.
    private var roller: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Problem")
                .font(.system(size: phase == .revealed ? 25 : 30, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize()

            Text(phrase)
                .font(.system(size: phase == .revealed ? 25 : 30, weight: .bold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.52)
                .id(phrase)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
        }
        .frame(height: 42, alignment: .center)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Problem: \(phrase)")
    }

    // MARK: - Choreography

    private func runSequence() async {
        phase = .rolling

        // Roll: readable at first, then accelerating into a blur of causes.
        var delay: Double = 0.62
        for step in 0..<26 {
            let next = ProblemCycle.phrases[(step + 1) % ProblemCycle.phrases.count]
            try? await Task.sleep(for: .seconds(delay))
            guard isActive else { return }
            withAnimation(.easeInOut(duration: min(0.22, delay * 0.6))) {
                phrase = next
            }
            delay = max(0.05, delay * 0.86)
        }

        try? await Task.sleep(for: .milliseconds(420))
        guard isActive else { return }

        // The sentence moves up; the loop draws itself in.
        withAnimation(Theme.settle) { phase = .revealed }
        withAnimation(.easeInOut(duration: 1.5)) { ringProgress = 1 }
        Haptics.soft()

        try? await Task.sleep(for: .milliseconds(1500))

        // A slow, endless lap of the ring — the loop never resolves on its own.
        await travelRing()
    }

    private func travelRing() async {
        var index = 0
        while !Task.isCancelled && isActive {
            let node = ProblemCycle.nodes[index % ProblemCycle.nodes.count]
            withAnimation(.easeInOut(duration: 0.3)) {
                activeNodeIndex = node.id
                phrase = node.phrase
            }
            try? await Task.sleep(for: .milliseconds(1050))
            index += 1
        }
    }
}
