import SwiftUI

/// The compact streak control that lives in the top-right of home.
///
/// This is the resting state of the streak, and the place the entrance
/// animation comes out of and returns to. It stays quiet: a flame, a number,
/// and nothing else. The words "day streak" belong in the expanded card, not in
/// a capsule the user sees every time they open the app.
struct StreakChip: View {
    let streak: Int
    /// Nil when the chip is only being used to reserve layout space.
    var onTap: (() -> Void)?

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
        .buttonStyle(PressableChipStyle())
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

/// A small inward press. Enough to confirm the tap landed, not enough to look
/// like the chip is a game button.
private struct PressableChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
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
