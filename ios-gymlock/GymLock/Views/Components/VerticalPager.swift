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
/// 3. **Pages may hold their own sub-steps.** A page with several sub-steps stays
///    pinned while the user swipes through them, which is how the loop sequence
///    tells its story without stacking seven screens. Pinned pages also receive
///    a continuous `sceneStep`, so a multi-phase scene can be driven directly by
///    the finger and reverse when the user scrolls back.
struct VerticalPager<Page: View>: View {
    @Binding var index: Int
    /// Step within the current page, for pinned narrative pages.
    @Binding var subStep: Int
    let pageCount: Int
    /// Highest page the user is allowed to reach, used to gate progression.
    var maxReachableIndex: Int
    /// Number of sub-steps for a page. `1` means the page advances immediately.
    var subStepCount: (Int) -> Int
    /// Disables the drag entirely, for example while the keyboard is up.
    var isDragDisabled: Bool
    @ViewBuilder var page: (Int) -> Page

    @State private var dragTranslation: CGFloat = 0
    /// Undamped drag, used to drive sub-step progress on pinned pages.
    @State private var rawDrag: CGFloat = 0

    private let advanceThreshold: CGFloat = 56
    /// Drag distance that corresponds to one whole sub-step.
    private let subStepTravel: CGFloat = 180

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
                        .environment(\.sceneReveal, max(0, 1 - abs(distance)))
                        .environment(\.sceneStep, stepPosition(for: pageIndex))
                        .offset(y: distance * height)
                }
            }
            .frame(width: proxy.size.width, height: height, alignment: .top)
            .contentShape(.rect)
            .simultaneousGesture(dragGesture(pageHeight: height), isEnabled: !isDragDisabled)
            .animation(Theme.pageTurn, value: index)
            .animation(Theme.pageTurn, value: subStep)
        }
        .clipped()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Continuous sub-step position to publish to a given page.
    ///
    /// Pages already behind the current one report their final sub-step, so a
    /// multi-phase scene does not snap back to its first phase while it is still
    /// partly on screen during a page turn.
    private func stepPosition(for pageIndex: Int) -> CGFloat {
        let lastStep = CGFloat(max(0, subStepCount(pageIndex) - 1))

        if pageIndex < index { return lastStep }
        guard pageIndex == index, lastStep > 0 else { return 0 }

        let live = CGFloat(subStep) - rawDrag / subStepTravel
        return min(max(live, 0), lastStep)
    }

    /// Keeps only the pages that can be on screen alive, so the illustration
    /// memory footprint stays flat regardless of how long the story is.
    private func mountedIndices(around position: CGFloat) -> [Int] {
        let lower = max(0, Int(floor(position)) - 1)
        let upper = min(pageCount - 1, Int(ceil(position)) + 1)
        guard lower <= upper else { return [index] }
        return Array(lower...upper)
    }

    private var forwardLimit: Int {
        min(maxReachableIndex, pageCount - 1)
    }

    private func dragGesture(pageHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                rawDrag = value.translation.height
                dragTranslation = resistedTranslation(
                    value.translation.height,
                    pageHeight: pageHeight
                )
            }
            .onEnded { value in
                let projected = value.translation.height + value.predictedEndTranslation.height * 0.3

                withAnimation(Theme.pageTurn) {
                    dragTranslation = 0
                    rawDrag = 0

                    if projected < -advanceThreshold {
                        advance()
                    } else if projected > advanceThreshold {
                        retreat()
                    }
                }
            }
    }

    private func advance() {
        if subStep + 1 < subStepCount(index) {
            subStep += 1
            Haptics.tap()
        } else if index < forwardLimit {
            index += 1
            subStep = 0
            Haptics.soft()
        }
    }

    private func retreat() {
        if subStep > 0 {
            subStep -= 1
            Haptics.tap()
        } else if index > 0 {
            let target = index - 1
            index = target
            // Land on the last sub-step so a pinned narrative reverses cleanly.
            subStep = max(0, subStepCount(target) - 1)
            Haptics.soft()
        }
    }

    /// Decides how much of the drag the page itself absorbs.
    ///
    /// A pinned page barely moves — its own content is animating under the
    /// finger instead — while the ends of the story rubber-band.
    private func resistedTranslation(_ raw: CGFloat, pageHeight: CGFloat) -> CGFloat {
        let pullingUp = raw < 0

        let pinnedForward = subStep + 1 < subStepCount(index)
        let pinnedBackward = subStep > 0
        let blockedForward = index >= forwardLimit
        let blockedBackward = index <= 0

        if pullingUp {
            if pinnedForward { return raw * 0.03 }
            if blockedForward { return raw * 0.16 }
        } else {
            if pinnedBackward { return raw * 0.03 }
            if blockedBackward { return raw * 0.16 }
        }
        return max(min(raw, pageHeight), -pageHeight)
    }
}
