import SwiftUI

/// The wide glass capsule Apple stacks inside a popover when it asks a
/// this-or-that question, as on Change Wake Up.
///
/// Like `GlassCircleButton`, iOS 26 gets Apple's own glass button style rather
/// than a hand-rolled imitation of it.
struct GlassChoiceButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            if reduceTransparency {
                fallback
            } else {
                Button {
                    Haptics.press(intensity: 0.45)
                    action()
                } label: {
                    label
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        } else {
            fallback
        }
    }

    private var label: some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
    }

    private var fallback: some View {
        Button {
            Haptics.press(intensity: 0.45)
            action()
        } label: {
            label
        }
        .buttonStyle(LegacyGlassCapsuleStyle(isOpaque: reduceTransparency))
    }
}

/// A full-width capsule that squashed as hard as the round buttons would look
/// rubbery, so it dips less and leans on the surface brightening instead.
private struct LegacyGlassCapsuleStyle: ButtonStyle {
    let isOpaque: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .background {
                ZStack {
                    if isOpaque {
                        Capsule().fill(Theme.surfaceMuted)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Theme.surfaceMuted.opacity(pressed ? 0.55 : 0.85))
                    }
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.7), .white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    Capsule().strokeBorder(Theme.border, lineWidth: 1)
                }
                .compositingGroup()
            }
            .scaleEffect(reduceMotion ? 1 : (pressed ? 0.965 : 1))
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .bouncy(duration: 0.3, extraBounce: 0.22),
                value: pressed
            )
    }
}
