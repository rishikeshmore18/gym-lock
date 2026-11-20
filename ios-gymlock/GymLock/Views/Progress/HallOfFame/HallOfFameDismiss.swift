import SwiftUI

/// The Hall of Fame page as a card: it follows a dismiss drag (shrinking,
/// rounding its corners and moving under the finger, over a dimmed Progress
/// page) and, on close, zooms from wherever it is into the Progress Photos
/// card it came from.
struct HallOfFamePageZoom: ViewModifier, Animatable {
    /// Full screen size.
    var size: CGSize
    /// Finger translation of a dismiss drag (or the frozen value while closing).
    var drag: CGSize
    /// Overscroll past the top of the film, which only shrinks the page.
    var pull: CGFloat
    /// 0 = following the finger, 1 = sitting exactly on the card.
    var exit: CGFloat
    /// The card in global coordinates; empty when unknown.
    var target: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(exit, AnimatablePair(drag.width, AnimatablePair(drag.height, pull))) }
        set {
            exit = newValue.first
            drag = CGSize(width: newValue.second.first, height: newValue.second.second.first)
            pull = newValue.second.second.second
        }
    }

    /// How far a drag has gone towards closing, 0...1.
    static func progress(drag: CGSize, pull: CGFloat, size: CGSize) -> CGFloat {
        let dy = max(drag.height, 0) / max(size.height * 0.5, 1)
        let dx = max(drag.width, 0) / max(size.width * 0.9, 1)
        return min(dy + dx + max(pull, 0) / 260, 1)
    }

    private struct Pose {
        var scale: CGFloat
        var clip: CGSize
        var center: CGPoint
        var radius: CGFloat
    }

    private var live: Pose {
        let p = Self.progress(drag: drag, pull: pull, size: size)
        let s = 1 - 0.32 * p
        return Pose(
            scale: s,
            clip: CGSize(width: size.width * s, height: size.height * s),
            center: CGPoint(x: size.width / 2 + drag.width * 0.8, y: size.height / 2 + drag.height * 0.8),
            radius: min(1, p * 8) * 40
        )
    }

    private var hasTarget: Bool {
        target.width > 20 && target.height > 20
            && target.intersects(CGRect(origin: .zero, size: size))
    }

    private var card: Pose {
        guard hasTarget else {
            let s: CGFloat = 0.6
            return Pose(scale: s, clip: CGSize(width: size.width * s, height: size.height * s),
                        center: CGPoint(x: size.width / 2, y: size.height / 2), radius: 40)
        }
        return Pose(scale: target.width / max(size.width, 1), clip: target.size,
                    center: CGPoint(x: target.midX, y: target.midY), radius: cornerRadius)
    }

    func body(content: Content) -> some View {
        let a = live, b = card
        let e = min(max(exit, 0), 1)
        let mix: (CGFloat, CGFloat) -> CGFloat = { x, y in x + (y - x) * e }
        let scale = mix(a.scale, b.scale)
        let clip = CGSize(width: mix(a.clip.width, b.clip.width), height: mix(a.clip.height, b.clip.height))
        let center = CGPoint(x: mix(a.center.x, b.center.x), y: mix(a.center.y, b.center.y))
        let radius = mix(a.radius, b.radius)
        let p = Self.progress(drag: drag, pull: pull, size: size)
        // Fades only in the last stretch, so the page lands on the card first.
        let f = min(max((e - 0.45) / 0.55, 0), 1)
        let opacity = 1 - f * f * (3 - 2 * f)
        let moving = p > 0.001 || e > 0.001
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        ZStack(alignment: .topLeading) {
            Color.black
                .opacity(0.2 * Double((1 - p) * (1 - e)) * (moving ? 1 : 0))
                .allowsHitTesting(false)
            content
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: clip.width, height: clip.height)
                .clipShape(shape)
                .shadow(color: .black.opacity(moving ? 0.16 * Double(1 - e * 0.6) : 0), radius: 24, y: 10)
                .position(center)
                .opacity(opacity)
        }
        .frame(width: size.width, height: size.height)
    }
}
