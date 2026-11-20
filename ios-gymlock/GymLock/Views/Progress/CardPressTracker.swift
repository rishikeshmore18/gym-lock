import SwiftUI
import UIKit

/// Reports a finger resting on a card, without taking the touch from
/// anything inside it: taps, the stack's drag, menus and the page scroll all
/// still get it. The press ends as soon as the finger travels, so scrolling
/// past the card never leaves it pushed in.
struct CardPressTracker: UIGestureRecognizerRepresentable {
    /// Touches inside this rect (in the card's own space) are ignored.
    var excluded: CGRect = .null
    var onChange: (Bool) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var start: CGPoint?
        var isPressed = false

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 0
        g.allowableMovement = 10
        g.cancelsTouchesInView = false
        g.delaysTouchesBegan = false
        g.delaysTouchesEnded = false
        g.delegate = context.coordinator
        return g
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let c = context.coordinator
        let point = context.converter.localLocation
        switch recognizer.state {
        case .began:
            c.start = point
            guard !excluded.contains(point) else { return }
            set(true, c)
        case .changed:
            guard let start = c.start, c.isPressed else { return }
            if hypot(point.x - start.x, point.y - start.y) > 10 { set(false, c) }
        default:
            c.start = nil
            set(false, c)
        }
    }

    private func set(_ pressed: Bool, _ c: Coordinator) {
        guard c.isPressed != pressed else { return }
        c.isPressed = pressed
        onChange(pressed)
    }
}
