import SwiftUI

/// The moon-to-sun illustration used wherever time of day is the actual subject.
///
/// Deliberately narrow in scope. This appears on the rhythm screen, the morning
/// plan, and the two moments where night genuinely turns into morning — and
/// nowhere else. Sprinkling it across progress screens and dashboards would turn
/// a meaningful visual into wallpaper.
///
/// The app canvas stays warm off-white throughout. Only the inside of this
/// illustration carries the deep blue of night, contained within its own circle
/// so the surrounding UI never goes dark.
struct CelestialRhythmView: View {
    /// 0 is full night, 1 is full morning. Animate this, not the subviews.
    var phase: Double
    var size: CGFloat = 148
    /// Stars are worth drawing at rest, but not while a dial is being dragged.
    var showsStars: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Under Reduce Motion the bodies do not travel — the scene simply
    /// crossfades between night and morning.
    private var travel: Double { reduceMotion ? 0 : 1 }

    private var clamped: Double { min(max(phase, 0), 1) }

    var body: some View {
        ZStack {
            sky
            if showsStars { stars }
            moon
            sun
            horizonGlow
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay {
            Circle().strokeBorder(Theme.border.opacity(0.6), lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel(clamped < 0.5 ? "Night" : "Morning")
    }

    // MARK: - Layers

    /// Night is a deep blue well; morning warms to cream. The transition is a
    /// colour mix rather than two stacked gradients so there is no crossfade
    /// seam midway.
    private var sky: some View {
        let top = Theme.night.mix(with: Color(red: 0.996, green: 0.945, blue: 0.898), by: clamped)
        let bottom = Theme.night
            .mix(with: Color(red: 0.290, green: 0.318, blue: 0.435), by: 0.35)
            .mix(with: Theme.accentWarm.opacity(0.9), by: clamped)

        return LinearGradient(
            colors: [top, bottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// A handful of stars, fading out as the sky lightens.
    private var stars: some View {
        // Fixed offsets rather than random ones: the constellation should be the
        // same every time the screen is opened.
        let points: [(x: Double, y: Double, r: Double)] = [
            (0.24, 0.22, 1.6), (0.62, 0.16, 1.2), (0.78, 0.31, 1.8),
            (0.38, 0.34, 1.1), (0.15, 0.44, 1.3), (0.70, 0.47, 1.0),
        ]

        return ZStack {
            ForEach(points.indices, id: \.self) { index in
                let point = points[index]
                Circle()
                    .fill(.white)
                    .frame(width: point.r * 2, height: point.r * 2)
                    .position(x: size * point.x, y: size * point.y)
                    .opacity((1 - clamped) * 0.85)
            }
        }
        .frame(width: size, height: size)
    }

    /// The moon sets: it slides down and to the left as morning arrives, rather
    /// than flying across the screen.
    private var moon: some View {
        let drift = clamped * travel

        return Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.976, green: 0.973, blue: 0.949),
                        Color(red: 0.855, green: 0.871, blue: 0.906),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size * 0.26, height: size * 0.26)
            // The crescent is cut by a second circle rather than drawn, so the
            // terminator stays crisp at any size.
            .mask {
                Circle()
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .frame(width: size * 0.21, height: size * 0.21)
                            .offset(x: size * 0.055, y: -size * 0.045)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .shadow(color: .white.opacity(0.35 * (1 - clamped)), radius: 10)
            .position(
                x: size * (0.34 - 0.16 * drift),
                y: size * (0.33 + 0.52 * drift)
            )
            .opacity(1 - clamped * 0.95)
    }

    /// The sun rises from below the horizon into the upper right.
    private var sun: some View {
        let rise = clamped * travel + (1 - travel) * clamped

        return ZStack {
            Circle()
                .fill(Theme.accentWarm.opacity(0.28))
                .frame(width: size * 0.52, height: size * 0.52)
                .blur(radius: size * 0.07)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.855, blue: 0.596),
                            Theme.accentWarm,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.27, height: size * 0.27)
        }
        .position(
            x: size * (0.52 + 0.16 * rise),
            y: size * (1.05 - 0.72 * rise)
        )
        .opacity(clamped)
    }

    /// Warm light gathering along the bottom as the sun comes up.
    private var horizonGlow: some View {
        LinearGradient(
            colors: [.clear, Theme.accentWarm.opacity(0.42 * clamped)],
            startPoint: .center,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Time-driven phase

extension CelestialRhythmView {
    /// The phase implied by an actual clock time.
    ///
    /// Full night before 5, full day after 9, and a smooth ramp between — so
    /// opening the plan screen at 6:40 shows a sunrise rather than an arbitrary
    /// choice between two states.
    static func phase(for time: TimeOfDay) -> Double {
        let minutes = Double(time.minutesFromMidnight)
        let dawn: Double = 5 * 60
        let day: Double = 9 * 60
        let dusk: Double = 19 * 60
        let night: Double = 21 * 60

        switch minutes {
        case ..<dawn: return 0
        case dawn..<day: return (minutes - dawn) / (day - dawn)
        case day..<dusk: return 1
        case dusk..<night: return 1 - (minutes - dusk) / (night - dusk)
        default: return 0
        }
    }

    static func phaseNow(_ date: Date = Date()) -> Double {
        phase(for: TimeOfDay(from: date))
    }
}
