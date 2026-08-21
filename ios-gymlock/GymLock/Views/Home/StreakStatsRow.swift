import SwiftUI

/// The three-part statistics row that sits under the mountain.
struct StreakStatsRow: View {
    let streak: Int
    let missedWeeks: Int
    let nextCheckIn: String?

    var body: some View {
        HStack(spacing: 0) {
            StreakFlameStat(streak: streak)

            statDivider

            SimpleStat(
                icon: "circle.hexagongrid.fill",
                iconColour: Color(white: 0.52),
                value: "\(missedWeeks)",
                caption: missedWeeks == 1 ? "week" : "weeks",
                detail: "missed"
            )

            statDivider

            SimpleStat(
                icon: "calendar",
                iconColour: Theme.accent,
                value: nextCheckIn ?? "—",
                caption: "next check-in",
                detail: "Stay consistent",
                isCompact: true
            )
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 42)
    }
}

/// One large flame with the number floating above it.
///
/// The flame is the background shape rather than an icon beside the number, so
/// the streak reads as a single object. It moves — but slowly, as a shape
/// rather than a flicker, because a home screen that strobes is a home screen
/// people stop opening.
struct StreakFlameStat: View {
    let streak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0
    @State private var pop: CGFloat = 1

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                FlameShape(phase: phase)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(0.95),
                                Color(red: 0.98, green: 0.62, blue: 0.25),
                                Color(red: 1.0, green: 0.80, blue: 0.42),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 46, height: 56)
                    .opacity(0.92)

                Text("\(streak)")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .shadow(color: Theme.accent.opacity(0.55), radius: 4, y: 1)
                    .scaleEffect(pop)
                    .offset(y: 3)
            }
            .frame(height: 56)

            Text(streak == 1 ? "day" : "days")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)

            Text(streak == 0 ? "Start today" : "Keep it going!")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: startFlame)
        .onChange(of: reduceMotion) { _, _ in startFlame() }
        .onChange(of: streak) { oldValue, newValue in
            guard newValue > oldValue else { return }
            Haptics.commit()
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { pop = 1.10 }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7).delay(0.16)) { pop = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            streak == 0
                ? "No streak yet"
                : "\(streak) day streak"
        )
    }

    private func startFlame() {
        phase = 0
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            phase = 1
        }
    }
}

/// A flame drawn as a closed curve whose control points drift, so the silhouette
/// breathes instead of the whole layer scaling.
struct FlameShape: Shape, Animatable {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        // Two out-of-step waves keep the left and right edges from moving as a
        // mirrored pair, which is what would make it read as a pulsing balloon.
        let sway = CGFloat(sin(phase * .pi * 2)) * width * 0.05
        let lick = CGFloat(sin(phase * .pi * 2 + 1.1)) * height * 0.045

        var path = Path()
        let tip = CGPoint(x: rect.midX + sway * 0.7, y: rect.minY - lick * 0.4)
        let base = CGPoint(x: rect.midX, y: rect.maxY)

        path.move(to: base)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.minX - width * 0.04, y: rect.maxY - height * 0.30),
            control2: CGPoint(x: rect.minX + width * 0.22 + sway, y: rect.minY + height * 0.24 + lick)
        )
        path.addCurve(
            to: base,
            control1: CGPoint(x: rect.maxX - width * 0.20 - sway, y: rect.minY + height * 0.28 - lick),
            control2: CGPoint(x: rect.maxX + width * 0.04, y: rect.maxY - height * 0.32)
        )
        path.closeSubpath()

        // An inner core, offset the other way, gives the flame depth without a
        // second animated layer.
        var inner = Path()
        let innerTip = CGPoint(x: rect.midX - sway * 0.4, y: rect.minY + height * 0.30 + lick * 0.5)
        inner.move(to: base)
        inner.addCurve(
            to: innerTip,
            control1: CGPoint(x: rect.midX - width * 0.24, y: rect.maxY - height * 0.18),
            control2: CGPoint(x: rect.midX - width * 0.10, y: rect.minY + height * 0.48)
        )
        inner.addCurve(
            to: base,
            control1: CGPoint(x: rect.midX + width * 0.12, y: rect.minY + height * 0.50),
            control2: CGPoint(x: rect.midX + width * 0.24, y: rect.maxY - height * 0.18)
        )
        path.addPath(inner)

        return path
    }
}

/// The middle and right cells of the stats row.
struct SimpleStat: View {
    let icon: String
    let iconColour: Color
    let value: String
    let caption: String
    let detail: String
    var isCompact: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColour)
                .frame(height: 22)

            Text(value)
                .font(.system(size: isCompact ? 15 : 26, weight: .heavy, design: .rounded))
                .foregroundStyle(isCompact ? Theme.accent : Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: isCompact ? 26 : 30)

            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
