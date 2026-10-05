import SwiftUI

/// "Share your progress 🔥", the spotlight's one line.
///
/// Drawn as the Progress Photos card's background, so it sits behind the real
/// card: while it starts just below the card's top edge, the card itself
/// covers that part, and only what rises into the dark above is seen. It
/// settles a fixed gap above the card through an alignment guide, so it
/// follows the card wherever it is laid out, and adds no size to the page.
struct ProgressSpotlightHeadline: View {
    let reduceMotion: Bool
    let onDismiss: () -> Void

    @ScaledMetric(relativeTo: .title2) private var fontSize: CGFloat = 24
    @AccessibilityFocusState private var isFocused: Bool
    @State private var stage: Stage

    /// Gap between the line and the card once settled.
    private static let gap: CGFloat = 12

    init(reduceMotion: Bool, onDismiss: @escaping () -> Void) {
        self.reduceMotion = reduceMotion
        self.onDismiss = onDismiss
        _stage = State(initialValue: reduceMotion ? .settled : .hidden)
    }

    /// Start (behind the card), the rise with its slight overshoot, and rest.
    enum Stage {
        case hidden, rise, settled

        var opacity: Double { self == .hidden ? 0 : 1 }
        var lift: CGFloat {
            switch self {
            case .hidden: 18
            case .rise: 2
            case .settled: 0
            }
        }
        var scale: CGFloat {
            switch self {
            case .hidden: 0.94
            case .rise: 1.065
            case .settled: 1
            }
        }
    }

    var body: some View {
        Text("Share your progress 🔥")
            .font(.system(size: min(fontSize, 30), weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .scaleEffect(stage.scale, anchor: .bottom)
            .offset(y: stage.lift)
            .opacity(stage.opacity)
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

    /// 170 ms up from behind the card to a slight overshoot, 110 ms back to
    /// rest: 280 ms in all, no spring, played once.
    private func play() {
        isFocused = true
        guard !reduceMotion else { return }
        withAnimation(
            .timingCurve(0.2, 0.85, 0.2, 1, duration: 0.17),
            completionCriteria: .logicallyComplete
        ) {
            stage = .rise
        } completion: {
            withAnimation(.easeOut(duration: 0.11)) { stage = .settled }
        }
    }
}
