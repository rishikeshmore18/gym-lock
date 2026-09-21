import SwiftUI

/// The wide glass capsule Apple stacks inside a popover when it asks a
/// this-or-that question, as on Change Wake Up.
///
/// Same bubble press as the round glass buttons, scaled down: a full-width
/// capsule that squashes this much would look rubbery, so it dips less and
/// leans on the material brightening instead.
struct GlassChoiceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(GlassChoiceSurface(isPressed: configuration.isPressed, reduceTransparency: reduceTransparency))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.955 : 1))
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .bouncy(duration: 0.3, extraBounce: 0.22),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.press(intensity: 0.45) }
            }
    }
}

private struct GlassChoiceSurface: ViewModifier {
    let isPressed: Bool
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.surfaceMuted, in: .capsule)
                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(Theme.surfaceMuted.opacity(isPressed ? 0.7 : 1), in: .capsule)
                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
        }
    }
}
