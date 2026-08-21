import SwiftUI

/// The chip that floats above a weekly checkpoint.
///
/// Labels live in SwiftUI rather than in the 3D scene for two reasons: text
/// stays crisp at every zoom level, and each checkpoint becomes a real
/// accessibility element that VoiceOver can reach and describe. State is
/// carried by an icon and a word as well as by colour, so the mountain is
/// readable without colour vision.
struct CheckpointLabel: View {
    let pin: WeekPin
    /// Night and storms need the dark treatment so text never sits as black on
    /// near-black terrain.
    let isDark: Bool
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 6) {
                badge

                VStack(alignment: .leading, spacing: 0) {
                    Text(pin.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isDark ? .white : Theme.ink)
                    Text(pin.detail)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(detailColour)
                }
                .fixedSize()
            }
            .padding(.leading, 4)
            .padding(.trailing, 9)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(isDark ? Color.black.opacity(0.55) : Color.white.opacity(0.88))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.06),
                                lineWidth: 0.75
                            )
                    }
            }
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .accessibilityLabel(pin.accessibilityDescription)
        .accessibilityHint("Opens this week's detail.")
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(badgeFill)
                .frame(width: 18, height: 18)

            if pin.state == .current {
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .frame(width: 18, height: 18)
            }

            if let icon = badgeIcon {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(badgeIconColour)
            }
        }
    }

    private var badgeFill: Color {
        switch pin.state {
        case .completed: Theme.accent
        case .partial: Theme.accent.opacity(0.28)
        case .current: .clear
        case .missed: Color(white: 0.62)
        case .upcoming: isDark ? Color.white.opacity(0.18) : Color(white: 0.88)
        case .start: Theme.accent
        }
    }

    private var badgeIcon: String? {
        switch pin.state {
        case .completed: "checkmark"
        case .partial: "checkmark"
        case .current: nil
        case .missed: "circle.fill"
        case .upcoming: nil
        case .start: "flag.fill"
        }
    }

    private var badgeIconColour: Color {
        switch pin.state {
        case .partial: Theme.accent
        case .missed: Color(white: 0.42)
        default: .white
        }
    }

    private var detailColour: Color {
        switch pin.state {
        case .completed, .partial, .current, .start:
            Theme.accent
        case .missed:
            isDark ? Color.white.opacity(0.65) : Color(white: 0.45)
        case .upcoming:
            isDark ? Color.white.opacity(0.55) : Theme.inkTertiary
        }
    }
}

/// Shown while the first mountain is being generated.
///
/// A soft silhouette rather than a spinner or a black rectangle, so the card
/// already has the shape of the thing that is about to appear.
struct MountainSkeletonView: View {
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.89, blue: 0.94),
                    Color(red: 0.94, green: 0.94, blue: 0.93),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: width * 0.26, y: height * 0.52))
                    path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.70))
                    path.addLine(to: CGPoint(x: width * 0.62, y: height * 0.24))
                    path.addLine(to: CGPoint(x: width * 0.80, y: height * 0.62))
                    path.addLine(to: CGPoint(x: width, y: height * 0.40))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(Color(white: 0.78).opacity(0.55))
            }

            Color.white
                .opacity(shimmer ? 0.12 : 0.02)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .accessibilityLabel("Preparing your mountain")
    }
}

/// The graceful failure. If the renderer cannot build a scene, Home still
/// works and still shows a mountain.
struct MountainFallbackView: View {
    let palette: EnvironmentPalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(
                        red: Double(palette.skyTop.x),
                        green: Double(palette.skyTop.y),
                        blue: Double(palette.skyTop.z)
                    ),
                    Color(
                        red: Double(palette.skyHorizon.x),
                        green: Double(palette.skyHorizon.y),
                        blue: Double(palette.skyHorizon.z)
                    ),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: -width * 0.1, y: height))
                        path.addLine(to: CGPoint(x: width * 0.34, y: height * 0.34))
                        path.addLine(to: CGPoint(x: width * 0.52, y: height * 0.58))
                        path.addLine(to: CGPoint(x: width * 0.70, y: height * 0.22))
                        path.addLine(to: CGPoint(x: width * 1.1, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.72), Color(white: 0.46)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: CGPoint(x: width * 0.12, y: height * 0.92))
                        path.addCurve(
                            to: CGPoint(x: width * 0.68, y: height * 0.26),
                            control1: CGPoint(x: width * 0.62, y: height * 0.78),
                            control2: CGPoint(x: width * 0.24, y: height * 0.46)
                        )
                    }
                    .stroke(
                        Theme.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 6])
                    )
                }
            }
        }
        .accessibilityLabel("Your journey, shown as a simplified mountain.")
    }
}
