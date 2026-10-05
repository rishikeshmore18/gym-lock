import SwiftUI

/// "Share your progress 🔥", the spotlight's one line.
///
/// Drawn as the Progress Photos card's background, so it sits behind the real
/// card: while its words start just below the card's top edge, the card
/// itself covers them, and only what bursts up into the dark above is seen.
/// It settles a fixed gap above the card through an alignment guide, so it
/// follows the card wherever it is laid out, and adds no size to the page.
struct ProgressSpotlightHeadline: View {
    let reduceMotion: Bool
    let onDismiss: () -> Void

    @ScaledMetric(relativeTo: .title2) private var fontSize: CGFloat = 24
    @AccessibilityFocusState private var isFocused: Bool
    /// Seconds into the entrance. Starts at the end under Reduce Motion, where
    /// the page's own short opacity transition is the whole reveal.
    @State private var time: Double

    /// Gap between the line and the card once settled.
    private static let gap: CGFloat = 12

    init(reduceMotion: Bool, onDismiss: @escaping () -> Void) {
        self.reduceMotion = reduceMotion
        self.onDismiss = onDismiss
        _time = State(initialValue: reduceMotion ? HeadlineBurstRenderer.duration : 0)
    }

    var body: some View {
        // One Text, so it lays out exactly like the plain sentence; the tags
        // only tell the renderer which word each run belongs to.
        Text("\(word("Share", 0))\(word(" your", 1))\(word(" progress", 2))\(word(" 🔥", 3))")
            .font(.system(size: min(fontSize, 30), weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .textRenderer(HeadlineBurstRenderer(time: time))
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityLabel("Share your progress")
            .accessibilityAddTraits(.isHeader)
            .accessibilityAction(.escape, onDismiss)
            .accessibilityFocused($isFocused)
            .onAppear(perform: play)
            // Placed in a top-aligned background: its bottom rests `gap`
            // above the card's top edge.
            .alignmentGuide(.top) { $0[.bottom] + Self.gap }
    }

    private func word(_ text: String, _ index: Int) -> Text {
        Text(verbatim: text).customAttribute(HeadlineWord(index: index))
    }

    /// Runs the clock once, linearly: every curve lives in the renderer, so
    /// each word keeps its own timing. Shown only on the landing, so this
    /// plays once per focus and never repeats.
    private func play() {
        isFocused = true
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: HeadlineBurstRenderer.duration)) {
            time = HeadlineBurstRenderer.duration
        }
    }
}

/// Which word of the headline a run of text belongs to.
nonisolated struct HeadlineWord: TextAttribute {
    let index: Int
}

/// Bursts each word up from behind the card with a short stagger, then lets
/// the 🔥 pop in last as the finishing beat.
///
/// Transforms and opacity only: the text's layout never changes, and once the
/// clock reaches `duration` the lines are drawn untouched, exactly as a plain
/// `Text` would draw them.
nonisolated struct HeadlineBurstRenderer: TextRenderer {
    var time: Double

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    /// The whole entrance: the last word lands at ~0.49 s, the 🔥 at 0.54 s.
    static let duration: Double = 0.54

    /// Room for the words while they start low and overshoot.
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 10, leading: 10, bottom: 30, trailing: 10)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard time < Self.duration else {
            for line in layout { context.draw(line) }
            return
        }
        for line in layout {
            for run in line {
                guard let word = run[HeadlineWord.self] else {
                    context.draw(run)
                    continue
                }
                let pose = Self.pose(forWord: word.index, at: time)
                guard pose.opacity > 0 else { continue }

                let bounds = run.typographicBounds.rect
                let anchor = CGPoint(x: bounds.midX, y: bounds.maxY)
                var copy = context
                copy.opacity *= pose.opacity
                copy.translateBy(x: anchor.x, y: anchor.y + pose.lift)
                copy.scaleBy(x: pose.scale, y: pose.scale)
                copy.translateBy(x: -anchor.x, y: -anchor.y)
                copy.draw(run)
            }
        }
    }

    // MARK: Timing

    struct Pose {
        var lift: CGFloat
        var scale: CGFloat
        var opacity: Double

        static let rest = Pose(lift: 0, scale: 1, opacity: 1)
    }

    /// Gap between word starts: tight enough to read as one burst.
    private static let stagger: Double = 0.055
    /// The 🔥 waits for "progress" to be on its way.
    private static let fireDelay: Double = 0.24

    static func pose(forWord index: Int, at time: Double) -> Pose {
        if index == 3 {
            return firePose(at: time - fireDelay)
        }
        return wordPose(at: time - Double(index) * stagger)
    }

    /// 220 ms burst from 22 pt low (behind the card) to a 3.5 pt overshoot,
    /// decelerating hard, then 160 ms easing back to rest.
    private static func wordPose(at t: Double) -> Pose {
        let rise = 0.22
        let settle = 0.16
        guard t > 0 else { return Pose(lift: 22, scale: 0.9, opacity: 0) }
        let opacity = easeOut(clamp(t / 0.12))
        if t < rise {
            let e = easeOutCubic(t / rise)
            return Pose(lift: lerp(22, -3.5, e), scale: lerp(0.9, 1.05, e), opacity: opacity)
        }
        guard t < rise + settle else { return .rest }
        let e = easeInOut((t - rise) / settle)
        return Pose(lift: lerp(-3.5, 0, e), scale: lerp(1.05, 1, e), opacity: opacity)
    }

    /// One pop: 160 ms from small to 1.2×, 140 ms back to 1×.
    private static func firePose(at t: Double) -> Pose {
        let pop = 0.16
        let settle = 0.14
        guard t > 0 else { return Pose(lift: 10, scale: 0.3, opacity: 0) }
        let opacity = easeOut(clamp(t / 0.08))
        if t < pop {
            let e = easeOutCubic(t / pop)
            return Pose(lift: lerp(10, -2, e), scale: lerp(0.3, 1.2, e), opacity: opacity)
        }
        guard t < pop + settle else { return .rest }
        let e = easeInOut((t - pop) / settle)
        return Pose(lift: lerp(-2, 0, e), scale: lerp(1.2, 1, e), opacity: opacity)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
    private static func easeOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
    private static func easeOutCubic(_ t: Double) -> Double {
        let inverse = 1 - clamp(t)
        return 1 - inverse * inverse * inverse
    }
    private static func easeInOut(_ t: Double) -> Double {
        let x = clamp(t)
        return 0.5 - cos(x * .pi) / 2
    }
}
