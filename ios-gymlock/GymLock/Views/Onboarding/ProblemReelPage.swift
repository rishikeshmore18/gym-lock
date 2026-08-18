import SwiftUI

/// Scene 4 — "Problem". The only scene in the story with no illustration: the
/// typography *is* the visual, and the whole sequence plays itself.
///
/// Four movements, on one timeline, with no input required at any point:
///
/// 1. The page is landed on mid-spin: a slot-machine wheel of the word "Problem"
///    is already racing past, too fast and too blurred to read, and it resolves
///    into focus as it decelerates like a picker until the centre copy is
///    *picked*. Nothing static is ever shown first.
/// 2. The picked copy holds while the echoes above and below it fade away.
/// 3. It locks to the left margin and shrinks to make room.
/// 4. A second wheel spins up beside it, naming the problem — endlessly.
///
/// The picked copy is one view for the entire scene. It is never re-created
/// between movements, which is what makes this read as a single continuous
/// animation instead of four slides.
struct ProblemReelPage: View {
    let isActive: Bool

    /// The names the problem goes by, in reel order.
    private static let problems: [String] = [
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

    private static let problemSize: CGFloat = 50
    /// "Problem" shrinks to this fraction once it moves left, to leave room for
    /// the reel. Applied as a scale so the measured width stays stable.
    private static let lockedScale: CGFloat = 0.72
    private static let wheelRowHeight: CGFloat = 56
    private static let reelRowHeight: CGFloat = 62
    private static let reelSize: CGFloat = 30
    /// Where the wheel starts, in rows below its resting position. Far enough
    /// back that the opening stage is a genuine sprint rather than a nudge.
    private static let spinStart: Double = -13.0
    /// Blur while the wheel is at full speed. This is the scene's entrance: the
    /// wheel resolves from unreadable to sharp instead of fading in.
    private static let spinBlurMax: CGFloat = 6.5

    @Environment(\.sceneReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var spin: Double = ProblemReelPage.spinStart
    @State private var spinBlur: CGFloat = ProblemReelPage.spinBlurMax
    /// Opacity multiplier for every copy except the picked one.
    @State private var echoFade: CGFloat = 1
    @State private var lockLeft: CGFloat = 0
    @State private var reelPresence: CGFloat = 0
    @State private var reelSpin: Double = 0
    @State private var canAdvance = false
    /// Natural width of "Problem" at full size, measured once so the
    /// left-locked position can never jitter mid-animation.
    @State private var problemWidth: CGFloat = 0

    /// Opacity comes up early and fast, because blur — not fade — is what this
    /// scene resolves out of. Waiting on a fade would show a still frame first.
    private var entrance: CGFloat { smoothstep((reveal - 0.10) / 0.42) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Centred, the word's leading edge sits here; the lock-left move
            // drives it to the page margin instead.
            let centredLeading = (width - problemWidth) / 2

            ZStack {
                ProblemWordWheel(
                    position: spin,
                    echoFade: echoFade,
                    lockLeft: lockLeft,
                    lockedOffset: Theme.pageMargin - centredLeading,
                    lockedScale: Self.lockedScale,
                    rowHeight: reduceMotion ? 0 : Self.wheelRowHeight,
                    size: Self.problemSize
                )
                .blur(radius: reduceMotion ? 0 : spinBlur)

                reel(containerWidth: width)
            }
            .frame(width: width, height: proxy.size.height)
            .opacity(entrance)
            .background(alignment: .topLeading) { widthProbe }
        }
        .overlay(alignment: .bottom) {
            SwipeUpHint(label: "keep going", isActive: isActive && canAdvance)
                .opacity(canAdvance ? entrance : 0)
                .padding(.bottom, 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .task(id: isActive) { await run() }
    }

    /// Measures "Problem" at full size without affecting layout.
    private var widthProbe: some View {
        Text("Problem")
            .font(.system(size: Self.problemSize, weight: .heavy))
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newValue in
                problemWidth = newValue
            }
            .hidden()
    }

    private func reel(containerWidth: CGFloat) -> some View {
        let leading = Theme.pageMargin + problemWidth * Self.lockedScale + 18
        let available = max(140, containerWidth - leading - 16)

        return HStack(spacing: 0) {
            WordWheel(
                words: Self.problems,
                position: reelSpin,
                size: Self.reelSize,
                rowHeight: reduceMotion ? 0 : Self.reelRowHeight,
                reach: reduceMotion ? 0 : 3,
                isBlurred: !reduceMotion
            )
            .frame(width: available)

            Spacer(minLength: 0)
        }
        .padding(.leading, leading)
        .opacity(reelPresence)
        .allowsHitTesting(false)
    }

    // MARK: - The timeline

    private func run() async {
        guard isActive else {
            reset()
            return
        }

        Haptics.prepareSelection()
        // No opening pause: the wheel is already at speed while the page is still
        // turning, so the user lands on motion rather than on a still frame.
        await pickTheWord()
        guard !Task.isCancelled else { return }

        // The picked word owns the screen for a beat.
        try? await Task.sleep(for: .milliseconds(600))
        withAnimation(.easeInOut(duration: 0.52)) { echoFade = 0 }
        try? await Task.sleep(for: .milliseconds(680))
        guard !Task.isCancelled else { return }

        withAnimation(.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.6)) { lockLeft = 1 }
        try? await Task.sleep(for: .milliseconds(520))
        guard !Task.isCancelled else { return }
        Haptics.medium()

        withAnimation(.easeOut(duration: 0.36)) { reelPresence = 1 }
        try? await Task.sleep(for: .milliseconds(240))

        await spinReel()
    }

    /// Decelerates the wheel in three stages, so it lands the way a picker does
    /// rather than easing to a stop in one motion.
    private func pickTheWord() async {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.3)) { spin = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            Haptics.medium()
            return
        }

        // Stage 0 — full speed, unreadable. Roughly fourteen rows a second.
        spinBlur = Self.spinBlurMax
        withAnimation(.linear(duration: 0.46)) { spin = -6.4 }
        try? await Task.sleep(for: .milliseconds(440))
        guard !Task.isCancelled else { return }

        // Stage 1 — speed comes off and the word starts to become legible.
        withAnimation(.easeOut(duration: 0.40)) {
            spin = -2.6
            spinBlur = 3.2
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        // Stage 2 — two rows cross the centre here, so these ticks land on real
        // word crossings rather than being decorative.
        withAnimation(.easeOut(duration: 0.38)) {
            spin = -0.6
            spinBlur = 1.4
        }
        Haptics.selection()
        try? await Task.sleep(for: .milliseconds(190))
        Haptics.selection()
        try? await Task.sleep(for: .milliseconds(190))
        guard !Task.isCancelled else { return }

        // Stage 3 — settles onto the picked copy.
        withAnimation(.timingCurve(0.16, 0.9, 0.2, 1, duration: 0.62)) {
            spin = 0
            spinBlur = 0
        }
        try? await Task.sleep(for: .milliseconds(480))
        Haptics.medium()
    }

    /// Spins the name reel forever. It ramps up to a steady rhythm and then
    /// simply keeps going; the swipe affordance appears once a full cycle of
    /// names has passed.
    private func spinReel() async {
        let ramp: [Double] = [0.18, 0.22, 0.27, 0.32, 0.36]
        let steady = 0.38
        var step = 0

        while !Task.isCancelled {
            let duration: Double = reduceMotion
                ? 0.85
                : (step < ramp.count ? ramp[step] : steady)

            withAnimation(reduceMotion ? .easeInOut(duration: 0.24) : .linear(duration: duration)) {
                reelSpin += 1
            }

            // Ticks for the first cycle only — a wheel that turns forever must
            // not buzz forever.
            if step < Self.problems.count { Haptics.selection() }

            step += 1
            if step == Self.problems.count {
                withAnimation(Theme.settle) { canAdvance = true }
            }

            try? await Task.sleep(for: .seconds(duration))
        }
    }

    private func reset() {
        spin = Self.spinStart
        spinBlur = Self.spinBlurMax
        echoFade = 1
        lockLeft = 0
        reelPresence = 0
        reelSpin = 0
        canAdvance = false
    }

    private var accessibilityLabel: String {
        "Problem. It goes by many names: " + Self.problems.joined(separator: ", ") + "."
    }
}

// MARK: - The "Problem" wheel

/// A slot-machine wheel where every row is the word "Problem", plus one special
/// row — index `0` — that is the copy the wheel lands on.
///
/// That picked copy is styled like any other row while the wheel is turning, so
/// the landing reads as a selection rather than a reveal. Afterwards it is the
/// only row that survives the echo fade, and the only one that moves left.
///
/// `Animatable` on `position` for the same reason as `WordWheel`: the per-row
/// styling is derived from distance and has to be recomputed every frame.
private struct ProblemWordWheel: View, Animatable {
    var position: Double
    var echoFade: CGFloat
    var lockLeft: CGFloat
    /// Horizontal distance from the centred position to the left margin.
    var lockedOffset: CGFloat
    var lockedScale: CGFloat
    var rowHeight: CGFloat
    var size: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    private static let reach = 4

    var body: some View {
        ZStack {
            ForEach(visibleRows, id: \.self) { row in
                copy(at: row)
            }
        }
    }

    /// The window around the wheel's current position, always including the
    /// picked row so it is never torn down mid-sequence.
    private var visibleRows: [Int] {
        let centre = Int(position.rounded())
        var rows = Array((centre - Self.reach)...(centre + Self.reach))
        if !rows.contains(0) { rows.append(0) }
        return rows
    }

    private func copy(at row: Int) -> some View {
        let delta = Double(row) - position
        let distance = abs(delta)
        let isPicked = row == 0
        // Echoes pull very slightly inward as they leave.
        let retreat = isPicked ? 1 : 0.82 + 0.18 * Double(echoFade)

        return Text("Problem")
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(Theme.ink.mix(with: Theme.inkTertiary, by: min(1, distance * 0.5)))
            .fixedSize()
            .scaleEffect(1 - 0.085 * distance)
            .offset(y: CGFloat(delta * retreat) * rowHeight)
            .opacity(opacity(at: distance, isPicked: isPicked))
            // Scaling about the leading edge keeps the left-locked position
            // exact regardless of how far the shrink has progressed.
            .scaleEffect(isPicked ? 1 - (1 - lockedScale) * lockLeft : 1, anchor: .leading)
            .offset(x: isPicked ? lockedOffset * lockLeft : 0)
    }

    private func opacity(at distance: Double, isPicked: Bool) -> Double {
        let edge = Double(Self.reach) + 0.9
        guard distance < edge else { return 0 }
        let falloff = pow(0.78, distance)
        let cutoff = Double(smoothstep(CGFloat((edge - distance) / 1.3)))
        let base = falloff * cutoff
        return isPicked ? base : base * Double(echoFade)
    }
}
