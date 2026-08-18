import SwiftUI

/// Scene 4 — "Problem". The only scene in the story with no illustration: the
/// typography *is* the visual.
///
/// Four phases, all mapped onto scroll position rather than timers, so the whole
/// sequence reverses cleanly when the user scrolls back up:
///
/// - **Phase 1** (page arrival) — the word "Problem" settles into the centre.
/// - **Phase 2** (step 0→1) — it fans out into a vertical picker-wheel column.
/// - **Phase 3** (step 1→2) — the duplicates fade, leaving the centre copy.
/// - **Phase 4** (step 2→3) — the centre copy locks to the left and a slot-machine
///   reel of problem names spins beside it.
///
/// The centre "Problem" is a single view for the whole scene. It is never
/// re-created between phases, which is what makes the sequence read as one
/// continuous animation instead of four slides.
struct ProblemReelPage: View {
    let isActive: Bool

    /// Scroll sub-steps this scene occupies.
    static let stepCount = 4

    /// The names the problem goes by, in reel order.
    private static let words: [String] = [
        "Distraction",
        "Indecision",
        "Exhaustion",
        "Spiraling",
        "Inconsistency",
        "Discouragement",
        "Isolation",
        "Aimlessness",
        "Burnout",
        "Rigidity",
        "Overcommitment",
        "Intimidation",
    ]

    /// Duplicate rows above and below the centre copy, giving 9 visible copies.
    private static let columnReach = 4

    private static let problemSize: CGFloat = 50
    /// "Problem" shrinks to this fraction once it moves left, to leave room for
    /// the reel. Applied as a scale so the measured width stays stable.
    private static let lockedScale: CGFloat = 0.72
    private static let columnRowHeight: CGFloat = 56
    private static let reelRowHeight: CGFloat = 66
    private static let reelSize: CGFloat = 31

    @Environment(\.sceneReveal) private var reveal
    @Environment(\.sceneStep) private var step
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Natural width of "Problem" at full size. Measured once and never
    /// invalidated, so the left-lock offset cannot jitter mid-animation.
    @State private var problemWidth: CGFloat = 0
    @State private var reelPosition: Double = 0

    // MARK: - Phase progress

    private var entrance: CGFloat { smoothstep((reveal - 0.30) / 0.55) }
    private var expansion: CGFloat { smoothstep(step) }
    private var collapse: CGFloat { smoothstep(step - 1) }
    private var lockLeft: CGFloat { smoothstep(step - 2) }

    private var isEntranceSettled: Bool { isActive && entrance > 0.99 }
    private var isReelEngaged: Bool { isActive && step > CGFloat(Self.stepCount - 1) - 0.02 }

    private var problemScale: CGFloat {
        1 - (1 - Self.lockedScale) * lockLeft
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack {
                ForEach(duplicateRows, id: \.self) { row in
                    duplicate(row)
                }

                problemWord(containerWidth: width)

                reel(containerWidth: width)
            }
            .frame(width: width, height: proxy.size.height)
        }
        .overlay(alignment: .bottom) {
            SwipeUpHint(label: "see why", isActive: isActive)
                .opacity(entrance)
                .padding(.bottom, 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .task(id: isEntranceSettled) {
            guard isEntranceSettled else { return }
            Haptics.tap()
            Haptics.prepareSelection()
        }
        .task(id: isReelEngaged) {
            await runReel()
        }
    }

    // MARK: - The persistent centre word

    private func problemWord(containerWidth: CGFloat) -> some View {
        // Centred, its leading edge sits here; the lock-left move drives it to
        // the page margin instead.
        let centredLeading = (containerWidth - problemWidth) / 2
        let lockedOffset = Theme.pageMargin - centredLeading

        return Text("Problem")
            .font(.system(size: Self.problemSize, weight: .heavy))
            .foregroundStyle(Theme.ink)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newValue in
                problemWidth = newValue
            }
            .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * entrance)
            .offset(y: reduceMotion ? 0 : (1 - entrance) * 20)
            .opacity(entrance)
            // Scaling about the leading edge keeps the left-locked position exact
            // regardless of how far the shrink has progressed.
            .scaleEffect(problemScale, anchor: .leading)
            .offset(x: lockedOffset * lockLeft)
    }

    // MARK: - Phase 2 column

    private var duplicateRows: [Int] {
        let reach = Self.columnReach
        return (-reach...reach).filter { $0 != 0 }
    }

    private func duplicate(_ row: Int) -> some View {
        let distance = CGFloat(abs(row))
        // Nearer copies fan out first, so the column grows outward from the
        // centre rather than appearing all at once.
        let arrival = smoothstep(expansion * 1.3 - 0.10 * distance)
        let travel = reduceMotion ? 1 : arrival

        let restingOpacity = 0.62 * pow(0.63, distance - 1)
        // The duplicates pull very slightly inward as they leave.
        let retreat = 1 - 0.18 * collapse

        return Text("Problem")
            .font(.system(size: Self.problemSize, weight: .heavy))
            .foregroundStyle(Theme.ink)
            .fixedSize()
            .scaleEffect(1 - 0.115 * distance)
            .offset(y: CGFloat(row) * Self.columnRowHeight * travel * retreat)
            .opacity(restingOpacity * arrival * (1 - collapse) * entrance)
            // Purely decorative echoes of the centre word.
            .accessibilityHidden(true)
    }

    // MARK: - Phase 4 reel

    private func reel(containerWidth: CGFloat) -> some View {
        let leading = Theme.pageMargin + problemWidth * Self.lockedScale + 18
        let available = max(120, containerWidth - leading - 14)
        // The reel only exists once "Problem" has begun clearing space for it.
        let presence = smoothstep((lockLeft - 0.55) / 0.45)

        return HStack(spacing: 0) {
            reelColumn(width: available)
            Spacer(minLength: 0)
        }
        .padding(.leading, leading)
        .opacity(presence)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func reelColumn(width: CGFloat) -> some View {
        if reduceMotion {
            // No wheel travel: the active name simply crossfades in place.
            Text(Self.words[activeIndex])
                .font(.system(size: Self.reelSize, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: width, alignment: .leading)
                .id(activeIndex)
                .transition(.opacity)
        } else {
            ZStack {
                ForEach(visibleSlots, id: \.id) { slot in
                    reelRow(slot, width: width)
                }
            }
        }
    }

    private func reelRow(_ slot: ReelSlot, width: CGFloat) -> some View {
        let delta = slot.position - reelPosition
        let distance = abs(delta)
        let focus = max(0, 1 - distance)

        return Text(slot.word)
            .font(.system(size: Self.reelSize, weight: .bold))
            .foregroundStyle(Theme.ink.mix(with: Theme.inkTertiary, by: min(1, distance)))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: width, alignment: .leading)
            .scaleEffect(0.94 + 0.06 * focus, anchor: .leading)
            .blur(radius: min(2.4, max(0, distance - 1.6) * 1.6))
            .opacity(max(0, 1 - 0.32 * distance))
            .offset(y: CGFloat(delta) * Self.reelRowHeight)
            .accessibilityHidden(true)
    }

    /// One rendered row of the reel.
    private struct ReelSlot: Identifiable {
        let id: Int
        let word: String
        /// Position on the wheel, which may fall outside the word list so the
        /// column reads as endless at both ends.
        let position: Double
    }

    /// The wheel is cycled three times over so there are always names visible
    /// above the first word and below the last, then trimmed to the rows that
    /// can actually be seen.
    private var visibleSlots: [ReelSlot] {
        let count = Self.words.count
        var slots: [ReelSlot] = []

        for cycle in -1...1 {
            for (offset, word) in Self.words.enumerated() {
                let position = Double(offset + cycle * count)
                guard abs(position - reelPosition) <= 4 else { continue }
                slots.append(
                    ReelSlot(
                        id: (cycle + 1) * 100 + offset,
                        word: word,
                        position: position
                    )
                )
            }
        }
        return slots
    }

    private var activeIndex: Int {
        let count = Self.words.count
        let rounded = Int(reelPosition.rounded())
        return ((rounded % count) + count) % count
    }

    /// Spins the reel once the scene has locked into its final composition, and
    /// rewinds it if the user scrolls back out of that phase.
    private func runReel() async {
        guard isReelEngaged else {
            reelPosition = 0
            return
        }

        // Let the lock-left move finish before anything else fires, so the two
        // haptics stay legible as separate events.
        try? await Task.sleep(for: .milliseconds(300))
        Haptics.medium()
        try? await Task.sleep(for: .milliseconds(200))

        guard !reduceMotion else {
            await advanceWordsWithoutMotion()
            return
        }

        let count = Self.words.count
        for target in 1..<count {
            // Decelerating, like a picker wheel losing momentum.
            let ramp = Double(target - 1) / Double(count - 2)
            let duration = 0.16 + 0.30 * ramp * ramp

            withAnimation(.timingCurve(0.33, 0, 0.67, 1, duration: duration)) {
                reelPosition = Double(target)
            }
            // One tick per word, never per frame.
            Haptics.selection()

            try? await Task.sleep(for: .seconds(duration * 0.92))
            if Task.isCancelled { return }
        }

        try? await Task.sleep(for: .milliseconds(140))
        Haptics.medium()
    }

    private func advanceWordsWithoutMotion() async {
        for target in 1..<Self.words.count {
            withAnimation(.easeInOut(duration: 0.3)) {
                reelPosition = Double(target)
            }
            Haptics.selection()
            try? await Task.sleep(for: .milliseconds(420))
            if Task.isCancelled { return }
        }
        Haptics.medium()
    }

    private var accessibilityLabel: String {
        "Problem. It goes by many names: " + Self.words.joined(separator: ", ") + "."
    }
}
