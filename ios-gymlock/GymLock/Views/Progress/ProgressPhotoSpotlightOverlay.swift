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
struct ProgressPhotoSpotlightOverlay: View {
    let spotlight: ProgressSpotlightModel
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isTitleFocused: Bool
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24

    private static let dimOpacity = 0.55
    private static let titleGap: CGFloat = 14

    private var isFocused: Bool { spotlight.phase == .focused }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let hole = spotlight.cardFrame.offsetBy(dx: -origin.x, dy: -origin.y)

            ZStack(alignment: .topLeading) {
                scrim(hole: hole)
                dismissRegions(hole: hole, in: bounds)
                if isFocused {
                    title(above: hole)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Scrim

    /// One flat translucent layer. While travelling there is no hole at all;
    /// on focus the hole is erased in, so the real card is what lights up.
    private func scrim(hole: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(Self.dimOpacity))

            RoundedRectangle(cornerRadius: ProgressCardMetrics.cornerRadius, style: .continuous)
                .fill(Color.black)
                .frame(width: max(hole.width, 0), height: max(hole.height, 0))
                .offset(x: hole.minX, y: hole.minY)
                .opacity(isFocused ? 1 : 0)
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
        let regions = isFocused
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

    // MARK: Title

    /// Spotlight chrome, not part of the card: it sits in the dark area just
    /// above the measured card and is gone with the spotlight.
    private func title(above hole: CGRect) -> some View {
        Text("Share your progress 🔥")
            .font(.system(size: titleSize, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(
                width: max(hole.width, 0),
                height: max(hole.minY - Self.titleGap, 0),
                alignment: .bottom
            )
            .offset(x: hole.minX)
            .allowsHitTesting(false)
            .accessibilityLabel("Share your progress")
            .accessibilityAddTraits(.isHeader)
            .accessibilityAction(.escape, onDismiss)
            .accessibilityFocused($isTitleFocused)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
            )
            .task { isTitleFocused = true }
    }
}
