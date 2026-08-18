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
                        .environment(\.sceneReveal, max(0, 1 - abs(distance)))
                        .offset(y: distance * height)
                }
            }
            .frame(width: proxy.size.width, height: height, alignment: .top)
            .contentShape(.rect)
            .simultaneousGesture(dragGesture(pageHeight: height), isEnabled: !isDragDisabled)
            .animation(Theme.pageTurn, value: index)
        }
        .clipped()
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
                dragTranslation = resistedTranslation(
                    value.translation.height,
                    pageHeight: pageHeight
                )
            }
            .onEnded { value in
                let projected = value.translation.height + value.predictedEndTranslation.height * 0.3

                withAnimation(Theme.pageTurn) {
                    dragTranslation = 0

                    if projected < -advanceThreshold {
                        advance()
                    } else if projected > advanceThreshold {
                        retreat()
                    }
                }
            }
    }

    private func advance() {
        guard index < forwardLimit else { return }
        index += 1
        Haptics.soft()
    }

    private func retreat() {
        guard index > 0 else { return }
        index -= 1
        Haptics.soft()
    }

    /// Rubber-bands the drag at the ends of the story, where the swipe will not
    /// move the page.
    private func resistedTranslation(_ raw: CGFloat, pageHeight: CGFloat) -> CGFloat {
        let pullingUp = raw < 0

        if pullingUp && index >= forwardLimit { return raw * 0.16 }
        if !pullingUp && index <= 0 { return raw * 0.16 }

        return max(min(raw, pageHeight), -pageHeight)
    }
}
