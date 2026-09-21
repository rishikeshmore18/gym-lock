import SwiftUI

/// A round Liquid Glass toolbar button, after the X on Apple's Change Wake Up
/// screen.
///
/// Presses squash and spring back like a bubble: the material yields on
/// finger-down, and the release overshoots before settling. Reduce Motion
/// swaps the spring for a short fade; Reduce Transparency swaps the glass for
/// an opaque disc.
struct GlassCircleButton: View {
    let symbol: String
    let label: String
    var tint: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .buttonStyle(BubbleGlassStyle())
        .accessibilityLabel(label)
    }
}

/// The bubble: scale down on press, spring past resting size on release.
private struct BubbleGlassStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(GlassDisc(isPressed: configuration.isPressed, reduceTransparency: reduceTransparency))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.86 : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.7 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.32, dampingFraction: 0.55),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.press(intensity: 0.6) }
            }
    }
}

private struct GlassDisc: ViewModifier {
    let isPressed: Bool
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.surface, in: .circle)
                .overlay { Circle().strokeBorder(Theme.border, lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: .circle)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1) }
                .shadow(color: .black.opacity(isPressed ? 0.04 : 0.08), radius: isPressed ? 4 : 8, y: 3)
        }
    }
}
