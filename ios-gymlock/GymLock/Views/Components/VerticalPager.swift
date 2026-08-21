import SwiftUI

/// A full-screen vertical pager driving one continuous onboarding story.
///
/// Three things matter here:
///
/// 1. **The whole page is the gesture surface.** Every page is given an opaque
///    backing and an explicit hit-test shape, so a swipe anywhere — over
///    whitespace, over artwork, over the headline — moves the story. The drag is
///    attached simultaneously, so buttons and text fields keep working.
/// 2. **Animation derives from position, not from appearance.** The continuous
///    scroll position is published to each page as `sceneReveal`, so entrances
///    play forwards as a page arrives and reverse as it leaves.
/// 3. **Scenes play themselves.** No page requires more than one swipe: any
///    multi-part scene runs on its own timeline and simply opens the way forward
///    when it is done. The pager's only job is to move between them.
struct VerticalPager<Page: View>: View {
    @Binding var index: Int
    let pageCount: Int
    /// Highest page the user is allowed to reach, used to gate progression.
    var maxReachableIndex: Int
    /// Disables the drag entirely, for example while the keyboard is up.
    var isDragDisabled: Bool
    /// Pages whose forward transition the parent draws itself. Leaving one of
    /// these does not turn the page — `onInterceptedAdvance` is called instead,
    /// and the parent is responsible for moving `index`.
    var interceptedPages: Set<Int> = []
    var onInterceptedAdvance: ((Int) -> Void)?
    /// Animation used for an ordinary page turn. Set to `nil` to make the next
    /// index change land instantly — needed when a parent-drawn transition has
    /// to cut to the following scene rather than slide to it.
    var pageAnimation: Animation? = Theme.pageTurn
    /// Overrides the reveal published to the *current* page while the parent is
    /// drawing its own transition.
    ///
    /// A parent-drawn cut puts the incoming page at its final position
    /// instantly, which means `sceneReveal` is already `1` and that scene's
    /// entrance never plays — it simply exists, fully formed, the moment it is
    /// uncovered. Driving the reveal by hand lets the parent stage the entrance
    /// against whatever it is drawing on top.
    var sceneRevealOverride: Double?
    @ViewBuilder var page: (Int) -> Page

    @State private var dragTranslation: CGFloat = 0

    private let advanceThreshold: CGFloat = 56

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            // Continuous position measured in pages: 2.4 means 40% of the way
            // from page 2 towards page 3.
            let position = CGFloat(index) - dragTranslation / height

            ZStack(alignment: .top) {
                ForEach(mountedIndices(around: position), id: \.self) { pageIndex in
                    let distance = CGFloat(pageIndex) - position

                    page(pageIndex)
                        .frame(width: proxy.size.width, height: height)
                        .background(Theme.canvas)
                        .contentShape(.rect)
                        .environment(\.sceneReveal, reveal(for: pageIndex, distance: distance))
                        .offset(y: distance * height)
                }
            }
            .frame(width: proxy.size.width, height: height, alignment: .top)
            .contentShape(.rect)
            .simultaneousGesture(dragGesture(pageHeight: height), isEnabled: !isDragDisabled)
            .animation(pageAnimation, value: index)
        }
        .clipped()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Keeps only the pages that can be on screen alive, so the illustration
    /// memory footprint stays flat regardless of how long the story is.
    ///
    /// Nothing past `forwardLimit` is ever mounted. That is what makes a gate a
    /// gate: while a scene is holding the story, the next one cannot be dragged
    /// into view even a sliver, so there is nothing to mistake for progress.
    private func mountedIndices(around position: CGFloat) -> [Int] {
        let lower = max(0, Int(floor(position)) - 1)
        let upper = min(forwardLimit, Int(ceil(position)) + 1)
        guard lower <= upper else { return [index] }
        return Array(lower...upper)
    }

    private var forwardLimit: Int {
        min(maxReachableIndex, pageCount - 1)
    }

    /// How arrived a page is: normally derived from scroll position, unless the
    /// parent has taken the current page's entrance over.
    private func reveal(for pageIndex: Int, distance: CGFloat) -> CGFloat {
        if pageIndex == index, let override = sceneRevealOverride {
            return CGFloat(override)
        }
        return max(0, 1 - abs(distance))
    }

    private func dragGesture(pageHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragTranslation = resistedTranslation(
                    value.translation.height,
                    pageHeight: pageHeight
                )
            }
            .onEnded { value in
                let projected = value.translation.height + value.predictedEndTranslation.height * 0.3
                let wantsForward = projected < -advanceThreshold
                let wantsBack = projected > advanceThreshold

                // An intercepted page hands the whole transition to the parent.
                // This runs outside `withAnimation` on purpose: the parent may
                // need to cut to the next scene with no animation at all, and an
                // enclosing transaction would override that.
                if wantsForward, index < forwardLimit, interceptedPages.contains(index) {
                    dragTranslation = 0
                    onInterceptedAdvance?(index)
                    return
                }

                withAnimation(Theme.pageTurn) {
                    dragTranslation = 0

                    if wantsForward {
                        advance()
                    } else if wantsBack {
                        retreat()
                    }
                }
            }
    }

    private func advance() {
        guard index < forwardLimit else { return }
        guard !interceptedPages.contains(index) else { return }
        index += 1
        Haptics.soft()
    }

    private func retreat() {
        guard index > 0 else { return }
        index -= 1
        Haptics.soft()
    }

    /// Rubber-bands the drag where the swipe will not move the page.
    ///
    /// A gated forward swipe is met with a near-solid wall — a few points of give
    /// so the gesture is acknowledged, then nothing. A loose rubber-band would
    /// slide the page far enough to look like it was about to turn.
    /// An intercepted page is even more rigid than a gated one. Whatever the
    /// parent draws on release starts from the settled screen, so the page must
    /// not have crept upward first — a few points acknowledge the touch and
    /// nothing more.
    private func resistedTranslation(_ raw: CGFloat, pageHeight: CGFloat) -> CGFloat {
        let pullingUp = raw < 0

        if pullingUp && interceptedPages.contains(index) { return max(raw * 0.04, -6) }
        if pullingUp && index >= forwardLimit { return max(raw * 0.05, -18) }
        if !pullingUp && index <= 0 { return min(raw * 0.12, 42) }

        return max(min(raw, pageHeight), -pageHeight)
    }
}
