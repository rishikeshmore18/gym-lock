import SwiftUI

/// Spacing this screen owns. The title's own numbers live in
/// `CollapsingTitleMetrics`, shared with every other screen that glides a
/// title, so none of them can drift apart.
private enum HeaderMetrics {
    static let bandHeight = CollapsingTitleMetrics.bandHeight
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

    @State private var scrollOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
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
        .overlay(alignment: .top) {
            CollapsingTitle(
                title: title,
                collapse: CollapsingTitleMetrics.collapse(forOffset: scrollOffset),
                overscroll: CollapsingTitleMetrics.overscroll(forOffset: scrollOffset),
                containerWidth: containerWidth
            )
        }
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
