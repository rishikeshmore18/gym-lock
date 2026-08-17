import UIKit

/// Small wrapper around UIKit feedback generators so views stay declarative.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func commit() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
