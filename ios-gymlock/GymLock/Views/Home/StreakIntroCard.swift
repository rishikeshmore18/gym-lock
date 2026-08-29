import SwiftUI

/// The floating card the streak briefly expands into on entry.
///
/// The flame is the backdrop and the number sits on top of it — one object,
/// read in one glance. The number is near-black rather than white because the
/// artwork is a saturated orange: black on that orange clears contrast
/// requirements comfortably, white does not.
struct StreakIntroCard: View {
    let streak: Int
    /// False under Reduce Motion, which holds the flame on a single frame.
    let isAnimated: Bool

    /// Fixed so the morph is a clean scale of a stable object. A card that also
    /// reflowed its own text while travelling would look like a glitch.
    static let size = CGSize(width: 196, height: 226)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                FlameAnimationView(isAnimating: isAnimated)
                    .frame(width: 138, height: 138)

                Text("\(streak)")
                    .font(.system(size: 54, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // Lifts the number off the brightest part of the flame
                    // without putting a plate behind it.
                    .shadow(color: .white.opacity(0.65), radius: 7)
                    .padding(.horizontal, 12)
            }

            Text("day streak")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 2)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The card is transient decoration around a value that is also
        // announced in full to VoiceOver, so its type stays fixed rather than
        // reflowing a fixed-size surface at accessibility sizes.
        .dynamicTypeSize(.large)
        .background(Theme.surface, in: .rect(cornerRadius: 34))
        .overlay {
            RoundedRectangle(cornerRadius: 34)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 30, y: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StreakChip.accessibilityLabel(for: streak))
    }
}

#Preview {
    ZStack {
        Theme.canvas.ignoresSafeArea()
        StreakIntroCard(streak: 4, isAnimated: true)
    }
}
