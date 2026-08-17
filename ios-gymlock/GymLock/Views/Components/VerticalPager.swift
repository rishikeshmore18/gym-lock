import SwiftUI

/// A full-screen vertical pager with TikTok-style paging: one page fills the
/// viewport, a drag past the threshold advances, and the transition is a quick
/// ease with no visible bounce.
///
/// Pages receive the exact page height so they can lay out edge to edge, and
/// the pager can be locked while a keyboard or a modal owns the gesture space.
struct VerticalPager<Content: View>: View {
    @Binding var index: Int
    let pageCount: Int
    /// Highest page the user is allowed to reach, used to gate progression.
    var maxReachableIndex: Int
    /// Disables the drag gesture entirely (for example while typing).
    var isDragDisabled: Bool
    @ViewBuilder var content: (CGFloat) -> Content

    @State private var dragTranslation: CGFloat = 0

    private let advanceThreshold: CGFloat = 60

    var body: some View {
        GeometryReader { proxy in
            let pageHeight = proxy.size.height

            VStack(spacing: 0) {
                content(pageHeight)
            }
            .frame(width: proxy.size.width, alignment: .top)
            .offset(y: -CGFloat(index) * pageHeight + dragTranslation)
            .animation(Theme.pageTurn, value: index)
            .gesture(dragGesture(pageHeight: pageHeight), isEnabled: !isDragDisabled)
        }
        .clipped()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func dragGesture(pageHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragTranslation = resistedTranslation(value.translation.height, pageHeight: pageHeight)
            }
            .onEnded { value in
                let combined = value.translation.height + value.predictedEndTranslation.height * 0.35
                var target = index

                if combined < -advanceThreshold {
                    target = min(index + 1, min(maxReachableIndex, pageCount - 1))
                } else if combined > advanceThreshold {
                    target = max(index - 1, 0)
                }

                if target != index {
                    Haptics.soft()
                }

                withAnimation(Theme.pageTurn) {
                    dragTranslation = 0
                    index = target
                }
            }
    }

    /// Rubber-bands the drag when the user pulls beyond the reachable range.
    private func resistedTranslation(_ raw: CGFloat, pageHeight: CGFloat) -> CGFloat {
        let pullingUp = raw < 0
        let blockedForward = index >= min(maxReachableIndex, pageCount - 1)
        let blockedBackward = index <= 0

        if (pullingUp && blockedForward) || (!pullingUp && blockedBackward) {
            return raw * 0.18
        }
        return max(min(raw, pageHeight), -pageHeight)
    }
}
