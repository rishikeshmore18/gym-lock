import SwiftUI

/// The badges emblem: the GymLock mark cast as brushed metal.
///
/// This is deliberately not the app-icon tile. A black square with a logo in it
/// reads as branding; a metal relief with no background reads as an *award* —
/// the thing a badge count is actually counting. Silver is the resting state
/// because nothing has been earned yet, which is the same honesty rule the
/// momentum field follows for a day with no record: show the real state, and let
/// the state itself say "not yet".
///
/// Light is the only motion. A slow specular sweep crosses the relief, pauses
/// well out of frame, and comes back — the way light catches metal when you turn
/// it in your hand. It never pulses, bounces, or asks for attention.
struct BadgeEmblem: View {
    /// True once at least one badge exists. Earned metal is brighter and casts a
    /// deeper shadow; the same sweep then reads as polish rather than dormancy.
    var isEarned: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let markWidth: CGFloat = 84
    private let markHeight: CGFloat = 76

    var body: some View {
        ZStack {
            mark
            if !reduceMotion {
                sheen
            }
        }
        .frame(width: markWidth, height: markHeight)
        .compositingGroup()
        .shadow(color: .black.opacity(isEarned ? 0.18 : 0.10), radius: 7, y: 4)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82), value: isEarned)
    }

    // MARK: The relief

    private var mark: some View {
        Image("BadgeMarkLocked")
            .resizable()
            .scaledToFit()
            .frame(width: markWidth, height: markHeight)
            // Unearned metal sits back a little so the flame beside it stays the
            // brighter object on the row.
            .opacity(isEarned ? 1 : 0.92)
    }

    // MARK: Specular sweep

    /// A soft diagonal band of light, clipped to the metal itself so the
    /// highlight travels across the relief and never over the card behind it.
    private var sheen: some View {
        band
            .phaseAnimator(SheenPhase.allCases) { content, phase in
                content
                    .offset(x: phase.offset * markWidth)
                    .opacity(phase.opacity)
            } animation: { phase in
                switch phase {
                // The return trip is long and fully transparent: it doubles as
                // the pause between sweeps, so nothing flickers back.
                case .rest: .linear(duration: 3.8)
                case .sweep: .easeInOut(duration: 1.15)
                case .fade: .easeOut(duration: 0.3)
                }
            }
            .blendMode(.plusLighter)
            .mask { mark }
            .allowsHitTesting(false)
    }

    private var band: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.9), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: markWidth * 0.4, height: markHeight * 2)
        .rotationEffect(.degrees(18))
    }

    /// Where the light is, and whether it is visible there.
    private enum SheenPhase: CaseIterable {
        /// Parked off the left edge, invisible.
        case rest
        /// Crossing the relief.
        case sweep
        /// Off the right edge, dimming out.
        case fade

        var offset: CGFloat {
            switch self {
            case .rest: -1
            case .sweep, .fade: 1
            }
        }

        var opacity: Double {
            switch self {
            case .rest, .fade: 0
            case .sweep: 1
            }
        }
    }
}

#Preview("Unearned") {
    BadgeEmblem()
        .padding(40)
        .background(Theme.surface)
}

#Preview("Earned") {
    BadgeEmblem(isEarned: true)
        .padding(40)
        .background(Theme.surface)
}
