import SwiftUI

/// The compact streak control that lives in the top-right of home.
///
/// This is the resting state of the streak, and the place the expanded card
/// comes out of and returns to. It stays quiet: a flame, a number, and nothing
/// else. The words "day streak" belong in the expanded card, not in a capsule
/// the user sees every time they open the app.
struct StreakChip: View {
    let streak: Int
    /// Nil when the chip is only being used to reserve layout space.
    var onTap: (() -> Void)?
    /// Reports the press, so the owner can drive the compression of the bubble
    /// and of the card growing out of it from a single value. The chip does not
    /// scale itself: halfway through a press it stops being the only thing on
    /// screen representing this streak, and two views animating their own
    /// version of the same squeeze would drift apart.
    var onPressChange: ((Bool) -> Void)?
    /// Reports the frame of the visible capsule — not the padded touch target,
    /// which is larger and would leave the expanding card misaligned by a few
    /// points at the moment it matters most.
    var onCapsuleFrame: ((CGRect) -> Void)?

    /// The orange of the supplied flame artwork, so the resting icon and the
    /// animated one are recognisably the same object.
    private static let flameOrange = Color(red: 1, green: 0.451, blue: 0)

    var body: some View {
        Button {
            onTap?()
        } label: {
            capsule
                // Transparent margin around the capsule. The chip stays visually
                // compact while the thing you actually have to hit clears 44pt.
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                .contentShape(.capsule)
        }
        .buttonStyle(PressableChipStyle(onPressChange: onPressChange))
        .disabled(onTap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: streak))
        .accessibilityHint(onTap == nil ? "" : "Double tap to view streak")
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private var capsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(flameTint)

            Text("\(streak)")
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassCapsule()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            onCapsuleFrame?($0)
        }
    }

    /// A zero streak is shown in grey, never red, and never as a broken flame.
    /// Nobody opens a gym app to be told off by an icon.
    private var flameTint: Color {
        streak > 0 ? Self.flameOrange : Theme.inkTertiary
    }

    static func accessibilityLabel(for streak: Int) -> String {
        "Current gym streak, \(streak) \(streak == 1 ? "day" : "days")"
    }
}

/// Reports the press and takes a little light out of the capsule while it is
/// held. The compression itself belongs to the owner — see `onPressChange`.
private struct PressableChipStyle: ButtonStyle {
    let onPressChange: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Pressure rather than a click: the capsule dims very slightly, as
            // though it has been pushed into the surface.
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChange?(isPressed)
            }
    }
}

#Preview {
    HStack(spacing: 16) {
        StreakChip(streak: 4, onTap: {})
        StreakChip(streak: 0, onTap: {})
        StreakChip(streak: 128, onTap: {})
    }
    .padding(40)
    .background(Theme.canvas)
}
