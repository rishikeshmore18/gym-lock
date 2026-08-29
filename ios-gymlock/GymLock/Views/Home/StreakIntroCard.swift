import SwiftUI

/// How big the expanded streak card and its contents are on this device.
///
/// Derived from the space actually available rather than hardcoded, so the card
/// keeps the same presence on a small phone as on a large one, and computed
/// once per layout rather than per frame.
struct StreakCardMetrics: Equatable {
    let size: CGSize

    /// Roughly half the card's width, which is what makes the flame the thing
    /// you see rather than an illustration sitting in a box.
    var flameSize: CGFloat { size.width * 0.54 }


    /// Sized off the flame, not the card, so the number always sits in the same
    /// proportion to the thing it is layered over.
    var numberSize: CGFloat { flameSize * 0.42 }

    var cornerRadius: CGFloat { 44 }

    /// Fits the card into the available space: dominant in the middle of the
    /// screen, but never edge to edge — home has to stay visible behind it for
    /// the card to read as something sitting on top of home.
    static func fit(_ available: CGSize) -> StreakCardMetrics {
        let width = min(max(available.width * 0.82, 232), 380)
        let height = min(max(available.height * 0.46, 268), 440)
        return StreakCardMetrics(size: CGSize(width: width, height: height))
    }
}

/// The floating card the streak expands into.
///
/// The flame is the backdrop and the number sits on top of it — one object,
/// read in one glance. The number is near-black rather than white because the
/// artwork is a saturated orange: black on that orange clears contrast
/// requirements comfortably, white does not.
struct StreakIntroCard: View {
    let streak: Int
    let metrics: StreakCardMetrics
    /// Driven from outside so it can interpolate toward the capsule's radius as
    /// the card shrinks into it.
    let cornerRadius: CGFloat
    /// False under Reduce Motion, which holds the flame on a single frame.
    let isAnimated: Bool
    /// Only a card the user opened themselves offers a way to close it.
    let showsClose: Bool
    let onClose: () -> Void

    var body: some View {
        ZStack {
            flameAndNumber

            if showsClose {
                closeButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        // The card is transient decoration around a value that is also
        // announced in full to VoiceOver, so its type stays fixed rather than
        // reflowing a fixed-size surface at accessibility sizes.
        .dynamicTypeSize(.large)
        // Solid warm white, never glass. The card has to stay readable against
        // a dimmed home, and contrast that depends on translucency is contrast
        // that disappears the moment Reduce Transparency is switched on.
        .background(Theme.surface, in: .rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    /// The flame is decorative: the number and its label already say everything
    /// this card is communicating, so VoiceOver is given one clear element
    /// instead of an animation it cannot describe.
    private var flameAndNumber: some View {
        VStack(spacing: 0) {
            ZStack {
                FlameAnimationView(isAnimating: isAnimated)
                    .frame(width: metrics.flameSize, height: metrics.flameSize)

                Text("\(streak)")
                    .font(.system(size: metrics.numberSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // Lifts the number off the brightest part of the flame
                    // without putting a plate behind it.
                    .shadow(color: .white.opacity(0.65), radius: 9)
                    .padding(.horizontal, 12)
            }

            Text("day streak")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StreakChip.accessibilityLabel(for: streak))
        // Focused first, so VoiceOver reads the streak before offering the
        // close button.
        .accessibilitySortPriority(1)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceMuted, in: .circle)
                // Quiet to look at, but still a full-size target to hit.
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .padding(.trailing, 10)
        .accessibilityLabel("Close streak")
    }

}

#Preview {
    ZStack {
        Theme.canvas.ignoresSafeArea()
        StreakIntroCard(
            streak: 12,
            metrics: .fit(CGSize(width: 393, height: 720)),
            cornerRadius: 44,
            isAnimated: true,
            showsClose: true,
            onClose: {}
        )
        .shadow(color: .black.opacity(0.16), radius: 40, y: 18)
    }
}
