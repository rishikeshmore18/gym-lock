import SwiftUI

/// The round Liquid Glass buttons Apple puts in the corners of its full-screen
/// editors: the X and the tick on Change Wake Up, the close circle in Photos.
///
/// Two roles, matching Apple's own pairing:
/// - `.neutral` — plain interactive glass with an ink glyph. Dismiss, back.
/// - `.prominent` — ink-tinted glass with a white glyph. The one action that
///   commits. Coral is not used here: on this screen the single accent
///   belongs to the gym bar on the dial.
///
/// Presses behave like a bubble. The disc squashes under the finger and
/// springs back past its resting size on release. On iOS 26 the glass itself
/// also lenses and brightens under the touch, which is where most of the life
/// comes from; the spring is what carries it on iOS 18.
struct GlassCircleButton: View {
    enum Role {
        case neutral
        case prominent
    }

    let symbol: String
    let label: String
    var role: Role = .neutral
    var diameter: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.44, weight: .bold))
                .foregroundStyle(role == .prominent ? Theme.surface : Theme.ink)
                .frame(width: diameter, height: diameter)
                .contentShape(.circle)
        }
        .buttonStyle(BubbleGlassButtonStyle(role: role))
        .accessibilityLabel(label)
    }
}

/// Squash on press, spring past resting size on release.
private struct BubbleGlassButtonStyle: ButtonStyle {
    let role: GlassCircleButton.Role

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(GlassDisc(role: role, isPressed: configuration.isPressed, reduceTransparency: reduceTransparency))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.86 : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.6 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .bouncy(duration: 0.34, extraBounce: 0.3),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.press(intensity: 0.55) }
            }
    }
}

/// The material itself, with honest fallbacks. A warm off-white canvas gives
/// clear glass almost nothing to refract, so the pre-iOS-26 path leans on a
/// hairline and a soft drop shadow to keep the disc visible.
private struct GlassDisc: ViewModifier {
    let role: GlassCircleButton.Role
    let isPressed: Bool
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(role == .prominent ? Theme.ink : Theme.surface, in: .circle)
                .overlay {
                    Circle().strokeBorder(role == .prominent ? Color.clear : Theme.border, lineWidth: 1)
                }
        } else if #available(iOS 26.0, *) {
            if role == .prominent {
                content.glassEffect(.regular.tint(Theme.ink).interactive(), in: .circle)
            } else {
                content.glassEffect(.regular.interactive(), in: .circle)
            }
        } else {
            content
                .background(
                    role == .prominent ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(.ultraThinMaterial),
                    in: .circle
                )
                .overlay {
                    Circle().strokeBorder(
                        Color.black.opacity(role == .prominent ? 0 : 0.07),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: .black.opacity(isPressed ? 0.05 : 0.12),
                    radius: isPressed ? 3 : 9,
                    y: isPressed ? 1 : 3
                )
        }
    }
}

#Preview("Glass circle buttons") {
    ZStack {
        Theme.canvas.ignoresSafeArea()
        HStack(spacing: 24) {
            GlassCircleButton(symbol: "chevron.left", label: "Back") {}
            GlassCircleButton(symbol: "checkmark", label: "Save", role: .prominent) {}
        }
    }
}
