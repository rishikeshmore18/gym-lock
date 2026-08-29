import SwiftUI

/// The compact streak control that lives in the top-right of home.
///
/// This is the resting state of the streak, and the place the entrance
/// animation comes out of and returns to. It stays quiet: a flame, a number,
/// and nothing else. The words "day streak" belong in the expanded card, not in
/// a capsule the user sees every time they open the app.
struct StreakChip: View {
    let streak: Int

    /// The orange of the supplied flame artwork, so the resting icon and the
    /// animated one are recognisably the same object.
    private static let flameOrange = Color(red: 1, green: 0.451, blue: 0)

    var body: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: streak))
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

#Preview {
    HStack(spacing: 16) {
        StreakChip(streak: 4)
        StreakChip(streak: 0)
        StreakChip(streak: 128)
    }
    .padding(40)
    .background(Theme.canvas)
}
