import UIKit

/// Small wrapper around UIKit feedback generators so views stay declarative.
///
/// The selection generator is kept alive and pre-warmed because the word reel
/// ticks it many times in quick succession, and a cold generator adds latency
/// that would break the picker-wheel illusion.
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// One iOS picker-style tick. Call only when the selected item actually
    /// changes — never per animation frame.
    static func selection() {
        selectionGenerator.selectionChanged()
    }

    /// Pre-warms the selection generator so the first tick is not late.
    static func prepareSelection() {
        selectionGenerator.prepare()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func commit() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
