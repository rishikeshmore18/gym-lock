import SwiftUI

/// A full-width capsule action in Liquid Glass, for "hear it" and "use this".
///
/// `.neutral` is clear glass; `.prominent` is glass tinted with the accent,
/// for the one action that commits. On iOS 26 the glass is interactive and
/// answers the finger itself. On iOS 18 the capsule is solid and gives a
/// springy press instead.
///
/// The caller sets the label's size and colour; this only supplies the
/// material and the touch response.
struct AlarmGlassCapsuleButtonStyle: ButtonStyle {
    enum Role {
        case neutral
        case prominent
    }

    var role: Role = .neutral

    func makeBody(configuration: Configuration) -> some View {
        AlarmGlassCapsuleBody(configuration: configuration, role: role)
    }
}

private struct AlarmGlassCapsuleBody: View {
    let configuration: ButtonStyleConfiguration
    let role: AlarmGlassCapsuleButtonStyle.Role

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var solidFill: Color {
        role == .prominent ? Theme.accent : Theme.surfaceMuted
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            configuration.label
                .contentShape(.capsule)
                .glassEffect(glass, in: .capsule)
        } else {
            let pressed = configuration.isPressed
            configuration.label
                .background(solidFill.opacity(pressed ? 0.88 : 1), in: .capsule)
                .contentShape(.capsule)
                .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
                .animation(
                    pressed
                        ? .spring(response: 0.18, dampingFraction: 0.9)
                        : .spring(response: 0.42, dampingFraction: 0.6),
                    value: pressed
                )
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        switch role {
        case .neutral: .regular.interactive()
        case .prominent: .regular.tint(Theme.accent).interactive()
        }
    }
}
