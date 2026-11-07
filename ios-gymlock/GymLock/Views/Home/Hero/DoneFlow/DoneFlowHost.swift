import SwiftUI

/// The done flow on screen (02-experience-spec §4.2–4.3).
///
/// Sits above the tabs and the tab bar, ignoring safe areas, so the collapse can fly into the hero
/// card where it was when the flow opened. Owns the two ways out: the glass X (visible from the first
/// frame) and the swipe down (35% of the height or 500 pt/s). Rank-ups inside the flow crossfade over
/// the story in 200 ms; the story holds its collapse until the last one is tapped through.
struct DoneFlowHost: View {
    let queue: CelebrationQueue

    var body: some View {
        // Read the insets before ignoring them: inside the full-bleed stack they read as zero, which
        // put the close button under the status bar and Dynamic Island.
        GeometryReader { safe in
            ZStack {
                if let p = queue.presentation {
                    DoneFlowStage(presentation: p, rankUp: queue.rankUp, topInset: safe.safeAreaInsets.top, onClose: { queue.close() }, onContinue: { queue.continueRankUp() })
                        .id(p.id)
                        .transition(.opacity.animation(.easeOut(duration: 0.18)))
                }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(queue.presentation != nil)
    }
}

private struct DoneFlowStage: View {
    let presentation: CelebrationQueue.Presentation
    let rankUp: BadgeRankUpRequest?
    /// The screen's top safe-area inset, measured outside the full-bleed stack.
    let topInset: CGFloat
    let onClose: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragY: CGFloat = 0

    private var model: MatrixStoryModel { presentation.model }

    var body: some View {
        GeometryReader { geo in
            let height = max(1, geo.size.height)
            ZStack(alignment: .topTrailing) {
                story
                    .offset(y: dragY)
                    .scaleEffect(1 - min(0.06, dragY / height * 0.12), anchor: .top)
                    .simultaneousGesture(swipe(height: height), including: model.collapseAt == nil && rankUp == nil ? .all : .subviews)

                if model.collapseAt == nil && rankUp == nil {
                    closeButton
                        .padding(.top, topInset + 8)
                        .padding(.trailing, 16)
                        .offset(y: dragY)
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }

                if let req = rankUp {
                    RankUpView(to: req.to, from: req.from, onContinue: onContinue)
                        .id(req.id)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .ignoresSafeArea()
                        .overlay(alignment: .topTrailing) {
                            closeButton
                                .padding(.top, topInset + 8)
                                .padding(.trailing, 16)
                        }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: rankUp?.id)
        }
    }

    @ViewBuilder
    private var story: some View {
        switch presentation.style {
        case .ridge: RidgeStoryView(model: model, cardFrame: presentation.cardFrame)
        case .matrix: MatrixStoryView(model: model, cardFrame: presentation.cardFrame)
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.selection()
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .modifier(DoneFlowGlassCircle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private func swipe(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { v in
                guard model.collapseAt == nil, v.translation.height > 0,
                      abs(v.translation.height) > abs(v.translation.width) else { return }
                // a little resistance so it feels attached, not loose
                dragY = v.translation.height * 0.85
            }
            .onEnded { v in
                let travel = v.translation.height
                let speed = v.velocity.height
                let commits = travel >= height * 0.35 || (speed >= 500 && travel > 24)
                if commits && model.collapseAt == nil {
                    onClose()
                }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.86)) {
                    dragY = 0
                }
            }
    }
}

/// Liquid Glass on iOS 26, a dark material circle before it.
private struct DoneFlowGlassCircle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.black.opacity(0.72), in: Circle())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
    }
}
