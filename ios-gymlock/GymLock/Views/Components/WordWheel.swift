import SwiftUI

/// An endlessly rotating vertical word wheel, in the manner of a slot-machine
/// reel or the iOS picker.
///
/// The view is `Animatable` on its wheel position, so its body is re-evaluated
/// on every frame of an animation. That detail is the whole trick: each row's
/// colour, scale, blur, and opacity are derived from how far it sits from the
/// centre, and those derivations are not animatable modifiers. Without
/// frame-by-frame evaluation the rows would snap straight to their final
/// styling and merely slide, which reads as a list being nudged rather than a
/// wheel being spun.
///
/// `position` is unbounded and the word list wraps, so the wheel can keep
/// turning forever without ever reaching an end.
///
/// Under Reduce Motion, callers pass `rowHeight: 0`, `reach: 0`, and
/// `isBlurred: false`; the wheel then holds a single row that swaps in place
/// with a light dip in opacity, and no travel at all.
struct WordWheel: View, Animatable {
    let words: [String]
    /// Continuous wheel position. Whole numbers centre the word at that index.
    var position: Double
    var size: CGFloat
    var weight: Font.Weight = .bold
    /// Vertical spacing between rows. `0` disables travel entirely.
    var rowHeight: CGFloat
    /// How many rows are rendered either side of the centre.
    var reach: Int = 3
    var alignment: Alignment = .leading
    var isBlurred: Bool = true

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        ZStack(alignment: alignment) {
            ForEach(visibleRows, id: \.self) { row in
                self.row(at: row)
            }
        }
        .accessibilityHidden(true)
    }

    /// The window of rows worth drawing, centred on wherever the wheel
    /// currently is.
    private var visibleRows: [Int] {
        let centre = Int(position.rounded())
        return Array((centre - reach)...(centre + reach))
    }

    private func row(at index: Int) -> some View {
        let delta = Double(index) - position
        let distance = abs(delta)
        let focus = max(0, 1 - distance)

        return Text(word(at: index))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Theme.ink.mix(with: Theme.inkTertiary, by: min(1, distance * 0.85)))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: alignment)
            .scaleEffect(0.94 + 0.06 * focus, anchor: scaleAnchor)
            .blur(radius: isBlurred ? min(2.6, max(0, distance - 1.3) * 1.5) : 0)
            .opacity(opacity(at: distance))
            .offset(y: CGFloat(delta) * rowHeight)
    }

    /// Wraps the index so the list has no first or last word.
    private func word(at index: Int) -> String {
        guard !words.isEmpty else { return "" }
        let count = words.count
        return words[((index % count) + count) % count]
    }

    /// Near rows dominate, and everything is gone by the edge of the window so
    /// rows never pop in or out visibly.
    private func opacity(at distance: Double) -> Double {
        let edge = Double(reach) + 0.9
        guard distance < edge else { return 0 }
        let falloff = pow(0.74, distance)
        let cutoff = Double(smoothstep(CGFloat((edge - distance) / 1.2)))
        return falloff * cutoff
    }

    private var scaleAnchor: UnitPoint {
        switch alignment {
        case .trailing: return .trailing
        case .center: return .center
        default: return .leading
        }
    }
}
