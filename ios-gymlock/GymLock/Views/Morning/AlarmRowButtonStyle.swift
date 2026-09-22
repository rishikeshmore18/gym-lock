import SwiftUI

/// The press state of a row inside a grouped alarm card, after Apple's lists:
/// a faint wash that arrives the instant the finger lands and fades out on
/// release, reaching the card's edges rather than stopping at the text.
///
/// `bleed` is the card's horizontal padding, so the wash runs edge to edge.
/// The card clips its content, so the wash never escapes the rounded corners.
struct AlarmRowButtonStyle: ButtonStyle {
    var bleed: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        return configuration.label
            .contentShape(.rect)
            .background {
                Rectangle()
                    .fill(Theme.ink.opacity(isPressed ? 0.06 : 0))
                    .padding(.horizontal, -bleed)
            }
            // Instant on the way in, eased on the way out: feedback must not
            // wait, and a release that snaps off reads as a flicker.
            .animation(isPressed ? nil : .easeOut(duration: 0.22), value: isPressed)
    }
}
