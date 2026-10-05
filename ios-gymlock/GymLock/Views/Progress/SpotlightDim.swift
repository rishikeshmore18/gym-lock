import SwiftUI

/// The Progress spotlight's dimming, applied by each surface to itself.
///
/// Every dimmed section darkens inside its own bounds and shape, so there is
/// nothing to measure and nothing to line up: a surface that is not dimmed
/// simply stays as it is.
enum SpotlightDim {
    /// Strength of the dark treatment over every dimmed surface.
    static let opacity = 0.55
    /// Text and chrome without a surface of their own (the page title, the
    /// tab bar) fade toward the dark canvas instead, so they never draw a
    /// second dark layer over the one already behind them.
    static let chromeOpacity = 0.45
}

extension View {
    /// Darkens this card in place while `isDimmed`, in the card's own shape.
    ///
    /// While dimmed, the dark layer also takes the card's touches, so a tap
    /// reaches the spotlight's dismiss gesture on the page rather than the
    /// control underneath. Nothing is drawn at all when not dimmed.
    func spotlightDimmed(_ isDimmed: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isDimmed {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(SpotlightDim.opacity))
                    .contentShape(.rect)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }
}
