import SwiftUI

/// A number that counts up to its value instead of appearing at it.
///
/// The view is `Animatable` on the value itself, so animating `value` makes the
/// digits roll through every intermediate figure. That matters on the screen
/// where the user learns what their gap actually costs: a number that climbs is
/// read as an accumulation, while a number that simply appears is read as a
/// label.
struct CountingNumber: View, Animatable {
    var value: Double
    var decimals: Int = 0
    var size: CGFloat = 54
    var weight: Font.Weight = .bold
    var color: Color = Theme.accent
    /// Shown before the number, typically "≈".
    var prefix: String = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(prefix + formatted)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            // Fixes the glyph width so the layout does not jitter as digits
            // change during the count.
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var formatted: String {
        let clamped = max(0, value)
        if decimals == 0 {
            return clamped.formatted(.number.precision(.fractionLength(0)))
        }
        return clamped.formatted(.number.precision(.fractionLength(decimals)))
    }
}
