import SwiftUI

/// One stat tile at the top of Progress: an emblem with the count stamped onto
/// its bottom edge, and a label beneath.
///
/// The overlap is the whole point of the layout. The number is not a caption
/// beside an icon — it is pressed into the object it counts, the way a wax seal
/// sits on an envelope — so the tile reads as a single object from across the
/// room. Built once, used for every stat card on this screen.
///
/// Sits between the home mini cards (18) and the momentum card (22): these
/// tiles are wider than the minis, and a radius that does not grow with the
/// card reads as a tighter, cheaper corner.
private let statCardRadius: CGFloat = 20

struct ProgressStatCard<Emblem: View>: View {
    /// Where the digit sits when the emblem underneath is colourful.
    enum DigitStyle {
        /// White disc, ink digit — legible on top of the flame.
        case light
        /// Near-black disc, white digit — the treatment the logo carries.
        case dark
    }

    let title: String
    let count: Int
    var digitStyle: DigitStyle = .light
    /// Stagger for the entrance cascade, in seconds.
    var appearanceDelay: Double = 0
    /// Destination is still being designed; the card gives press feedback and a
    /// soft tick today so it never feels dead, and takes real wiring later.
    var action: (() -> Void)?
    @ViewBuilder var emblem: () -> Emblem

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        Button {
            Haptics.soft()
            action?()
        } label: {
            VStack(spacing: 0) {
                emblemArea
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    // Clears the digit disc, which hangs 15 below its emblem.
                    .padding(.top, 26)
            }
            .frame(maxWidth: .infinity)
            // Content runs to roughly 150; this leaves matching air above the
            // emblem and below the label.
            .frame(height: 174)
            // The same surface, hairline and lift the home cards use. Without
            // it the emblems float on the canvas and the tile stops reading as
            // an object you can press.
            .background(Theme.surface, in: .rect(cornerRadius: statCardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: statCardRadius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 10, y: 4)
            .contentShape(.rect(cornerRadius: statCardRadius))
        }
        .buttonStyle(PressableTileStyle(reduceMotion: reduceMotion))
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16)
        .task {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(Theme.settle.delay(appearanceDelay)) {
                    hasAppeared = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Emblem with the overlapped digit

    private var emblemArea: some View {
        emblem()
            .frame(height: 84)
            .overlay(alignment: .bottom) {
                digitDisc
                    .offset(y: 15)
            }
            .padding(.top, 22)
    }

    private var digitDisc: some View {
        Text("\(count)")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(digitStyle == .light ? Theme.ink : .white)
            .frame(width: 31, height: 31)
            .background(
                Circle().fill(digitStyle == .light ? Theme.surface : Theme.logoBackdrop)
            )
            .overlay {
                Circle().strokeBorder(
                    digitStyle == .light ? Theme.border : Color.white.opacity(0.22),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: count)
    }

    private var accessibilityText: String {
        "\(title), \(count)"
    }
}

// MARK: - Press feedback

/// The whole tile presses, like an app icon: a small scale with a quick
/// settle. Under Reduce Motion it only dims slightly.
private struct PressableTileStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview("Stat cards") {
    HStack(spacing: 12) {
        ProgressStatCard(title: "Week Streak", count: 12) {
            FlameEmblem()
        }
        ProgressStatCard(title: "Badges Earned", count: 0, digitStyle: .dark) {
            BadgeEmblem()
        }
    }
    .padding(20)
    .background(Theme.canvas)
}
