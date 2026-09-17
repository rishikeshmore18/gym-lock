import SwiftUI

/// The result screen after a home fallback.
///
/// It has one difficult job: celebrate honestly. The user did something, and
/// that is worth marking — but they did not go to the gym, and the app says so
/// on the same screen, in the same breath, without turning it into a scolding.
///
/// Two numbers, never conflated: momentum is maintained, the gym visit is not
/// counted.
struct MomentumSavedView: View {
    let momentumWeeks: Int
    let recentMomentum: [Bool]
    let onKeepGoing: () -> Void
    let onDone: () -> Void
    /// Opens the Story editor for this morning — offered, never pushed.
    var onShare: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accentWash.opacity(0.7), Theme.canvas],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(
                    trailingTitle: "Done",
                    trailingAction: onDone,
                    leadingSymbol: "flame.fill"
                )

                ScrollView {
                    VStack(spacing: 22) {
                        flame
                        heading
                        momentumCard
                        gymVisitCard
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                MorningPrimaryButton(title: "keep going", systemImage: nil) {
                    onKeepGoing()
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, onShare == nil ? 14 : 4)

                if let onShare {
                    Button("share this") {
                        Haptics.tap()
                        onShare()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(minHeight: 36)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Share this morning")
                }
            }
        }
        .task {
            withAnimation(Theme.settle) { hasAppeared = true }
        }
    }

    // MARK: - Pieces

    private var flame: some View {
        ZStack {
            Circle()
                .fill(Theme.surface)
                .frame(width: 132, height: 132)
                .shadow(color: Theme.accent.opacity(0.16), radius: 24, y: 8)

            Image(systemName: "flame.fill")
                .font(.system(size: 62, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accentWarm, Theme.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.92)
        .opacity(hasAppeared ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text("momentum saved")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)

            VStack(spacing: 1) {
                Text("life changed the plan.")
                Text("you still showed up.")
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .multilineTextAlignment(.center)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 14)
    }

    private var momentumCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("momentum maintained")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent, in: .circle)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 14 }

                Text("\(momentumWeeks)")
                    .font(.system(size: 52, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())

                Text("week streak")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)

                Spacer(minLength: 0)
            }

            MomentumSparkline(days: recentMomentum)
                .frame(height: 46)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 22)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 16)
    }

    /// The honest half.
    ///
    /// Deliberately grey rather than red: this is a fact being recorded, not a
    /// penalty being applied.
    private var gymVisitCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 44, height: 44)
                .background(Theme.surfaceMuted, in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text("gym visit not counted")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text("your fallback protected your momentum.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 20)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 18)
    }
}

// MARK: - Sparkline

/// A fortnight of momentum as a soft line with dots on the days that held.
struct MomentumSparkline: View {
    let days: [Bool]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let count = max(days.count, 2)
            let step = width / CGFloat(count - 1)

            // A gentle wave whose height reflects whether the day held, so the
            // line reads as a trend rather than as a bar chart.
            let points: [CGPoint] = days.enumerated().map { index, held in
                CGPoint(
                    x: CGFloat(index) * step,
                    y: height * (held ? 0.28 : 0.72)
                )
            }

            ZStack {
                if points.count >= 2 {
                    smoothPath(points)
                        .stroke(
                            LinearGradient(
                                colors: [Theme.accentWarm.opacity(0.45), Theme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )

                    ForEach(points.indices.filter { days[$0] }, id: \.self) { index in
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                            .position(points[index])
                    }

                    // The most recent day gets a ring, so "today" is findable.
                    if let last = points.last {
                        Circle()
                            .strokeBorder(Theme.accent, lineWidth: 2.5)
                            .background(Circle().fill(Theme.surface))
                            .frame(width: 14, height: 14)
                            .position(last)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// A Catmull-Rom-ish smoothing: each segment is a curve through the midpoint
    /// of its neighbours, which avoids the hard corners of a polyline without
    /// needing a spline solver.
    private func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midX = (previous.x + current.x) / 2

            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }

        return path
    }
}
