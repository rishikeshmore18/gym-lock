import SwiftUI

/// The round Liquid Glass buttons Apple puts in the corners of its full-screen
/// editors: the close circle in Photos, the X and tick on Change Wake Up.
///
/// On iOS 26 this is Apple's own `.glass` and `.glassProminent` button style.
/// Nothing here reimplements the interaction: the material lenses, brightens
/// and squashes under the finger by itself, and that is where the bubble feel
/// comes from. An earlier version wrapped the material in a custom
/// `ButtonStyle`, which replaced all of that with a hand-rolled scale and lost
/// the feel entirely.
///
/// These are also deliberately **not** toolbar items. A `ToolbarItem` on
/// iOS 26 styles its own content, so glass applied inside one is dropped and
/// the button collapses to a bare tinted glyph. The Alarm screen draws its own
/// header row instead.
///
/// Two roles, matching Apple's own pairing:
/// - `.neutral` — plain glass with an ink glyph. Dismiss, back.
/// - `.prominent` — ink-tinted glass with a white glyph, for the one action
///   that commits. Coral is not used: on this screen the single accent
///   belongs to the gym bar on the dial.
struct GlassCircleButton: View {
    enum Role {
        case neutral
        case prominent
    }

    let symbol: String
    let label: String
    var role: Role = .neutral
    var diameter: CGFloat = 40
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            if reduceTransparency {
                fallback
            } else {
                appleGlass
            }
        } else {
            fallback
        }
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: diameter * 0.40, weight: .semibold))
            .foregroundStyle(role == .prominent ? Color.white : Theme.ink)
            .frame(width: diameter, height: diameter)
    }

    /// The real thing.
    @available(iOS 26.0, *)
    @ViewBuilder
    private var appleGlass: some View {
        let button = Button {
            Haptics.press(intensity: 0.5)
            action()
        } label: {
            glyph
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)

        switch role {
        case .neutral:
            button.buttonStyle(.glass)
        case .prominent:
            button.buttonStyle(.glassProminent).tint(Theme.ink)
        }
    }

    /// iOS 18 has no Liquid Glass, so the disc is built by hand: a blurred
    /// base, a specular highlight across the top, a rim that catches light on
    /// one side and darkens on the other, and a lift shadow. The warm
    /// off-white canvas gives clear material almost nothing to refract, so
    /// without the rim and the shadow the button reads as a bare icon.
    private var fallback: some View {
        Button {
            Haptics.press(intensity: 0.5)
            action()
        } label: {
            glyph
        }
        .buttonStyle(
            LegacyGlassButtonStyle(role: role, isOpaque: reduceTransparency)
        )
        .accessibilityLabel(label)
    }
}

private struct LegacyGlassButtonStyle: ButtonStyle {
    let role: GlassCircleButton.Role
    let isOpaque: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .background { disc(pressed: pressed) }
            .scaleEffect(reduceMotion ? 1 : (pressed ? 0.90 : 1))
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .bouncy(duration: 0.32, extraBounce: 0.3),
                value: pressed
            )
    }

    private var isProminent: Bool { role == .prominent }

    private func disc(pressed: Bool) -> some View {
        ZStack {
            if isProminent {
                Circle().fill(Theme.ink)
            } else if isOpaque {
                Circle().fill(Theme.surface)
            } else {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Theme.surface.opacity(0.45))
            }

            // Specular highlight: light arrives from the top, as it does on
            // every piece of glass Apple draws.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isProminent ? 0.26 : 0.8),
                            .white.opacity(0),
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isProminent ? 0.42 : 0.95),
                            .black.opacity(isProminent ? 0.22 : 0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .compositingGroup()
        .shadow(
            color: .black.opacity(pressed ? 0.07 : 0.16),
            radius: pressed ? 3 : 8,
            y: pressed ? 1 : 3
        )
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
