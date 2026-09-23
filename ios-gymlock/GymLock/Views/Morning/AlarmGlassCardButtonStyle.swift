import SwiftUI

/// A single-row card that is itself the button: the Sound page's Haptics
/// row, "choose your own song", the song sources, the lone Haptics choices.
///
/// On iOS 26 it is Apple's interactive Liquid Glass, so the card lenses,
/// brightens and gives under the finger exactly as system glass does, with
/// no hand-rolled imitation on top. On iOS 18 the glass is drawn by hand and
/// the press is a small, springy give: in instantly, out with a little life,
/// and interruptible because it is a spring on the pressed state.
///
/// Grouped cards with several rows keep `AlarmRowButtonStyle` instead, since
/// the whole card swelling for one row's tap would point at the wrong thing.
struct AlarmGlassCardButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        AlarmGlassCardBody(
            configuration: configuration,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }
}

private struct AlarmGlassCardBody: View {
    let configuration: ButtonStyleConfiguration
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var radius: CGFloat { AlarmGroupCard<EmptyView>.radius }

    private var content: some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: radius))
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: radius))
        } else {
            let pressed = configuration.isPressed
            Group {
                if reduceTransparency {
                    content
                        .background(Theme.surface, in: .rect(cornerRadius: radius))
                        .overlay {
                            RoundedRectangle(cornerRadius: radius)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        }
                } else {
                    content
                        .background {
                            RoundedRectangle(cornerRadius: radius)
                                .fill(Theme.ink.opacity(pressed ? 0.05 : 0))
                        }
                        .glassCard(radius: radius)
                }
            }
            .scaleEffect(pressed && !reduceMotion ? 0.975 : 1)
            .animation(
                pressed
                    ? .spring(response: 0.18, dampingFraction: 0.9)
                    : .spring(response: 0.45, dampingFraction: 0.62),
                value: pressed
            )
        }
    }
}
