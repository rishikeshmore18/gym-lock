import SwiftUI

/// The dark layer of the Progress spotlight, drawn over the whole tab shell,
/// tab bar included.
///
/// There is one Progress Photos card, the real one underneath. The scrim
/// erases a rounded hole at its measured frame rather than lighting a copy,
/// and the touch-catching surface is four rectangles around that hole, so the
/// card gets every tap, drag and menu exactly as it does on the normal page.
/// A tap on the dark area only closes the spotlight: the regions sit above
/// everything else, so nothing underneath sees that tap.
///
/// The canvas and the card are measured in the same named coordinate space,
/// and the canvas measures the very view its shapes are offset inside, so the
/// hole cannot drift by a safe-area inset on any device.
struct ProgressPhotoSpotlightOverlay: View {
    let spotlight: ProgressSpotlightModel
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24
    /// This overlay's drawing area in the spotlight coordinate space.
    @State private var canvas: CGRect = .zero

    private static let dimOpacity = 0.55
    /// Half a point past the card's edge, so anti-aliasing leaves no dim seam
    /// on its border. Drawing only; the hit regions use the exact frame.
    private static let seamOutset: CGFloat = 0.5

    var body: some View {
        let hole = ProgressSpotlightModel.localHole(
            cardFrame: spotlight.cardFrame,
            canvasOrigin: canvas.origin
        )
        let bounds = CGRect(origin: .zero, size: canvas.size)

        ZStack(alignment: .topLeading) {
            scrim(hole: hole)
            dismissRegions(hole: hole, in: bounds)
            if spotlight.isRevealed {
                SpotlightHeadline(
                    cardTop: hole.minY,
                    cardMinX: hole.minX,
                    cardWidth: hole.width,
                    fontSize: min(titleSize, 30),
                    reduceMotion: reduceMotion,
                    onDismiss: onDismiss
                )
                .transition(reduceMotion ? .opacity : .identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Measured inside `ignoresSafeArea`, on the view the shapes are
        // placed in, so the origin includes the status-bar expansion.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(ProgressSpotlightModel.coordinateSpaceName))
        } action: { frame in
            canvas = frame
        }
        .ignoresSafeArea()
    }

    // MARK: Scrim

    /// One flat translucent layer. While travelling there is no hole at all;
    /// on landing the hole is erased in, so the real card is what lights up.
    private func scrim(hole: CGRect) -> some View {
        let cutout = hole.insetBy(dx: -Self.seamOutset, dy: -Self.seamOutset)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(Self.dimOpacity))

            RoundedRectangle(cornerRadius: ProgressCardMetrics.cornerRadius, style: .continuous)
                .fill(Color.black)
                .frame(width: max(cutout.width, 0), height: max(cutout.height, 0))
                .offset(x: cutout.minX, y: cutout.minY)
                .opacity(spotlight.isRevealed ? 1 : 0)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Outside taps

    /// Above, below, left and right of the card once it is lit; the whole
    /// screen while the page is still travelling. VoiceOver sees one
    /// "Dismiss" button, not four.
    private func dismissRegions(hole: CGRect, in bounds: CGRect) -> some View {
        let regions = spotlight.isRevealed
            ? ProgressSpotlightModel.outsideRegions(around: hole, in: bounds)
            : [bounds]

        return ForEach(Array(regions.enumerated()), id: \.offset) { index, region in
            Color.clear
                .frame(width: region.width, height: region.height)
                .contentShape(.rect)
                .onTapGesture(perform: onDismiss)
                .offset(x: region.minX, y: region.minY)
                .accessibilityElement()
                .accessibilityLabel("Dismiss progress spotlight")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, onDismiss)
                .accessibilityAction(.escape, onDismiss)
                .accessibilityHidden(index != 0)
        }
    }
}

// MARK: - Headline

/// "Share your progress 🔥", rising out from behind the card's top edge.
///
/// Spotlight chrome only, never part of the page. Its box ends exactly at the
/// card's top edge and is masked there, so while the line starts below that
/// edge the part still "behind" the card is not drawn; only what has risen
/// into the dark is visible.
private struct SpotlightHeadline: View {
    let cardTop: CGFloat
    let cardMinX: CGFloat
    let cardWidth: CGFloat
    let fontSize: CGFloat
    let reduceMotion: Bool
    let onDismiss: () -> Void

    @AccessibilityFocusState private var isFocused: Bool
    @State private var stage: Stage

    /// Visual gap between the line and the card once settled.
    private static let gap: CGFloat = 12
    /// Room the scale-up may use past the box's sides and top without being
    /// cut by the mask.
    private static let maskBleed: CGFloat = 48

    init(
        cardTop: CGFloat,
        cardMinX: CGFloat,
        cardWidth: CGFloat,
        fontSize: CGFloat,
        reduceMotion: Bool,
        onDismiss: @escaping () -> Void
    ) {
        self.cardTop = cardTop
        self.cardMinX = cardMinX
        self.cardWidth = cardWidth
        self.fontSize = fontSize
        self.reduceMotion = reduceMotion
        self.onDismiss = onDismiss
        _stage = State(initialValue: reduceMotion ? .settled : .hidden)
    }

    /// Start, the rise with its slight overshoot, and rest.
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
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .scaleEffect(stage.scale, anchor: .bottom)
            .offset(y: stage.lift)
            .opacity(stage.opacity)
            .padding(.bottom, Self.gap)
            .frame(width: max(cardWidth, 0), height: max(cardTop, 0), alignment: .bottom)
            // The box's bottom edge is the card's top edge. Open on the
            // other three sides so the overshoot is never trimmed.
            .mask(alignment: .bottom) {
                Rectangle()
                    .padding(.horizontal, -Self.maskBleed)
                    .padding(.top, -Self.maskBleed)
            }
            .offset(x: cardMinX)
            .allowsHitTesting(false)
            .accessibilityLabel("Share your progress")
            .accessibilityAddTraits(.isHeader)
            .accessibilityAction(.escape, onDismiss)
            .accessibilityFocused($isFocused)
            .onAppear {
                isFocused = true
                guard !reduceMotion else { return }
                // 170 ms up and out to a slight overshoot, 110 ms back to
                // rest: 280 ms in all, no spring, played once.
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
}
