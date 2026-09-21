import SwiftUI

/// Metrics for the floating header, kept out of the generic view so they can be
/// plain stored constants and so the tabs can reason about the same numbers.
private enum HeaderMetrics {
    /// Page title at rest. 26 bold is the house screen-title size.
    static let expandedSize: CGFloat = 26
    /// Where it settles once collapsed — the system's inline title size.
    static let collapsedSize: CGFloat = 17
    /// How far the finger has to travel to complete the collapse. Short enough
    /// that the title is out of the way by the time the second card arrives,
    /// long enough that it never snaps.
    static let collapseDistance: CGFloat = 56
    /// The band the title lives in, and therefore the space reserved for it at
    /// the top of the content.
    static let bandHeight: CGFloat = 52
    /// Matches the horizontal padding the tab screens give their cards, so the
    /// expanded title sits on the same left edge as everything below it.
    static let pageMargin: CGFloat = 20
    static let pillPadding: CGFloat = 14
    /// A little air between the last card and the glass of the tab bar.
    static let bottomAir: CGFloat = 16
}

/// A tab screen whose title collapses, as the page scrolls, from a large page
/// title into a small pill floating at the top centre of the screen.
///
/// These tabs push nothing, so they no longer carry a `NavigationStack` purely
/// to obtain a title bar. That stack was the cause of the overlap: with four of
/// them alive at once inside the tab shell, the system bar stopped insetting its
/// scroll view and drew the large title straight over the first card. Owning the
/// header here makes the top and bottom spacing explicit and unconditional
/// rather than inherited from a bar that may or may not have claimed the screen.
///
/// The collapse is driven directly by the scroll offset rather than by a
/// threshold and an animation, so the title tracks the finger 1:1, reverses the
/// instant the user scrolls back up, and can be interrupted at any point.
struct FloatingTitleScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var scrollOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    /// Width of the title at its collapsed size, measured rather than guessed
    /// so the pill centres correctly for any word and any Dynamic Type size.
    /// Measured at a fixed size, so it cannot feed back into the collapse.
    @State private var collapsedTitleWidth: CGFloat = 0
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // The large title is drawn in the overlay, not in the flow, so
                // it can outlive the scroll and become the floating pill. This
                // is the room it occupies while it is still large.
                Color.clear.frame(height: HeaderMetrics.bandHeight)

                content()
            }
            .padding(.bottom, bottomClearance)
        }
        .background(Theme.canvas)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            CGSize(width: proxy.size.width, height: proxy.safeAreaInsets.bottom)
        } action: { value in
            containerWidth = value.width
            bottomInset = value.height
        }
        .overlay(alignment: .top) { header }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .leading) {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, HeaderMetrics.pillPadding)
                .padding(.vertical, 7)
                .background { pill }
                .offset(x: titleX, y: -2 * collapse)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: HeaderMetrics.bandHeight)
        .background(alignment: .topLeading) { collapsedWidthProbe }
        // The pill is chrome floating over the page; taps belong to the cards
        // passing underneath it.
        .allowsHitTesting(false)
    }

    /// The glass only exists once the title has left the page and needs to be
    /// told apart from whatever is now scrolling behind it. At rest there is
    /// nothing behind the title, so a pill there would be decoration.
    @ViewBuilder
    private var pill: some View {
        Group {
            if reduceTransparency {
                Capsule()
                    .fill(Theme.surface)
                    .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: .capsule)
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
            }
        }
        .opacity(pillOpacity)
    }

    /// An invisible copy at the collapsed size. Its width is what the pill has
    /// to be centred on, and because its size never changes it cannot start a
    /// measure-layout-measure loop with the title it is measuring for.
    private var collapsedWidthProbe: some View {
        Text(title)
            .font(.system(size: HeaderMetrics.collapsedSize, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { collapsedTitleWidth = $0 }
    }

    // MARK: Derived

    /// 0 while the page is at the top, 1 once the title has fully collapsed.
    private var collapse: CGFloat {
        min(max(scrollOffset / HeaderMetrics.collapseDistance, 0), 1)
    }

    /// Held back slightly so the glass does not appear while the title is still
    /// obviously a page title, then in fully by the time it reaches the centre.
    private var pillOpacity: CGFloat {
        min(max((collapse - 0.35) / 0.5, 0), 1)
    }

    private var titleSize: CGFloat {
        let base = HeaderMetrics.expandedSize
            - (HeaderMetrics.expandedSize - HeaderMetrics.collapsedSize) * collapse
        // Pulling the page down past the top grows the title a little, the way
        // a system large title does. Capped hard — this is a hint of give, not
        // a stretch effect.
        let overscroll = scrollOffset < 0 ? min(-scrollOffset, 40) * 0.09 : 0
        // Half-point steps: an unrounded size shimmers as the text re-renders
        // on every frame of the scroll.
        return ((base + overscroll) * 2).rounded() / 2
    }

    private var titleX: CGFloat {
        let expanded = HeaderMetrics.pageMargin - HeaderMetrics.pillPadding
        guard containerWidth > 0, collapsedTitleWidth > 0 else { return expanded }
        let pillWidth = collapsedTitleWidth + HeaderMetrics.pillPadding * 2
        let centred = (containerWidth - pillWidth) / 2
        return expanded + (centred - expanded) * collapse
    }

    /// Guarantees the last card clears the floating tab bar.
    ///
    /// The bar is installed as a bottom safe-area inset, so a scroll view that
    /// received that inset has already made room and only needs a little air.
    /// The `max` is the belt and braces: if the inset ever fails to reach this
    /// screen, the padding grows to cover the bar itself rather than letting
    /// content hide behind it.
    private var bottomClearance: CGFloat {
        max(
            HeaderMetrics.bottomAir,
            RootTabBar.reservedHeight + HeaderMetrics.bottomAir - bottomInset
        )
    }
}

#Preview("Floating title") {
    FloatingTitleScreen(title: "Progress") {
        VStack(spacing: 14) {
            ForEach(0..<8, id: \.self) { index in
                Text("Card \(index + 1)")
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .warmCard()
            }
        }
        .padding(.horizontal, 20)
    }
}
