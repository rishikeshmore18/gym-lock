import SwiftUI

/// The numbers behind the collapsing page title, in one place so every screen
/// that uses it collapses over the same distance, at the same sizes, onto the
/// same left edge. A title that behaves differently from screen to screen is
/// read as a bug, not as variety.
enum CollapsingTitleMetrics {
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
    /// Matches the horizontal padding the screens give their cards, so the
    /// expanded title sits on the same left edge as everything below it.
    static let pageMargin: CGFloat = 20
    static let pillPadding: CGFloat = 14

    /// 0 while the page is at the top, 1 once the title has fully collapsed.
    static func collapse(forOffset offset: CGFloat) -> CGFloat {
        min(max(offset / collapseDistance, 0), 1)
    }

    /// How far past the top the page has been pulled, which is what lets the
    /// title grow a little under the finger.
    static func overscroll(forOffset offset: CGFloat) -> CGFloat {
        max(-offset, 0)
    }
}

/// A page title that travels, as the page scrolls, from a large left-aligned
/// heading into a small glass pill floating at the top centre of the screen.
///
/// The travel is driven directly by the scroll offset rather than by a
/// threshold and an animation, so the title tracks the finger 1:1, reverses the
/// instant the user scrolls back up, and can be interrupted at any point.
///
/// Callers own the scroll offset and say where the title sits at each end, so
/// the same glide works whether it is landing in an empty strip (the tabs) or
/// in a row that already holds a back button and a tick (the alarm screen).
struct CollapsingTitle: View {
    let title: String
    /// 0 at rest, 1 fully collapsed. Use `CollapsingTitleMetrics.collapse`.
    let collapse: CGFloat
    /// Points the page has been pulled past its top.
    var overscroll: CGFloat = 0
    /// Width of the area the pill has to centre itself in.
    let containerWidth: CGFloat
    /// Vertical centre of the title at rest, measured from the top of the
    /// thing this is overlaid on.
    var expandedCenterY: CGFloat = CollapsingTitleMetrics.bandHeight / 2
    /// Vertical centre once collapsed. A couple of points of lift is what
    /// stops the pill looking like it simply shrank in place.
    var collapsedCenterY: CGFloat = CollapsingTitleMetrics.bandHeight / 2 - 2

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Width of the title at its collapsed size, measured rather than guessed
    /// so the pill centres correctly for any word and any Dynamic Type size.
    /// Measured at a fixed size, so it cannot feed back into the collapse.
    @State private var collapsedTitleWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, CollapsingTitleMetrics.pillPadding)
                .padding(.vertical, 7)
                .background { pill }
                .frame(height: CollapsingTitleMetrics.bandHeight)
                .offset(x: titleX, y: titleY)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CollapsingTitleMetrics.bandHeight)
        .background(alignment: .topLeading) { collapsedWidthProbe }
        // The pill is chrome floating over the page; taps belong to whatever
        // is passing underneath it.
        .allowsHitTesting(false)
    }

    /// The glass only exists once the title has left its resting place and
    /// needs to be told apart from whatever is now scrolling behind it. At rest
    /// there is nothing behind the title, so a pill there would be decoration.
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
            .font(.system(size: CollapsingTitleMetrics.collapsedSize, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { collapsedTitleWidth = $0 }
    }

    // MARK: Derived

    /// Held back slightly so the glass does not appear while the title is still
    /// obviously a page title, then in fully by the time it reaches the centre.
    private var pillOpacity: CGFloat {
        min(max((collapse - 0.35) / 0.5, 0), 1)
    }

    private var titleSize: CGFloat {
        let base = CollapsingTitleMetrics.expandedSize
            - (CollapsingTitleMetrics.expandedSize - CollapsingTitleMetrics.collapsedSize) * collapse
        // Pulling the page down past the top grows the title a little, the way
        // a system large title does. Capped hard — this is a hint of give, not
        // a stretch effect.
        let give = min(overscroll, 40) * 0.09
        // Half-point steps: an unrounded size shimmers as the text re-renders
        // on every frame of the scroll.
        return ((base + give) * 2).rounded() / 2
    }

    private var titleX: CGFloat {
        let expanded = CollapsingTitleMetrics.pageMargin - CollapsingTitleMetrics.pillPadding
        guard containerWidth > 0, collapsedTitleWidth > 0 else { return expanded }
        let pillWidth = collapsedTitleWidth + CollapsingTitleMetrics.pillPadding * 2
        let centred = (containerWidth - pillWidth) / 2
        return expanded + (centred - expanded) * collapse
    }

    private var titleY: CGFloat {
        let center = expandedCenterY + (collapsedCenterY - expandedCenterY) * collapse
        return center - CollapsingTitleMetrics.bandHeight / 2
    }
}
