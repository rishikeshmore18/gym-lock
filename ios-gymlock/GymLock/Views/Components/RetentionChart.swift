import SwiftUI

/// The two-curve retention chart. Both series leave the same point in week 1 —
/// the whole argument of the screen is that the start is identical and only the
/// mechanism differs.
struct RetentionChart: View {
    let progress: CGFloat

    /// Normalised 0...1 values across 13 weekly samples.
    private let willpower: [CGFloat] = [
        0.62, 0.66, 0.63, 0.55, 0.46, 0.38, 0.31, 0.26, 0.22, 0.19, 0.17, 0.16, 0.15,
    ]
    private let gymLockSystem: [CGFloat] = [
        0.62, 0.65, 0.68, 0.71, 0.74, 0.77, 0.80, 0.83, 0.86, 0.88, 0.90, 0.92, 0.94,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in
                let plot = CGRect(
                    x: 0,
                    y: 8,
                    width: proxy.size.width,
                    height: proxy.size.height - 8
                )

                ZStack(alignment: .topLeading) {
                    gridLines(in: plot)

                    // Declining series — dashed, muted, visually "gives up".
                    smoothPath(values: willpower, in: plot)
                        .trim(from: 0, to: progress)
                        .stroke(
                            Theme.inkTertiary,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 6])
                        )

                    // Climbing series — solid accent, the product's promise.
                    smoothPath(values: gymLockSystem, in: plot)
                        .trim(from: 0, to: progress)
                        .stroke(
                            Theme.accent,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )

                    // Shared origin marker, so the "same start" reads instantly.
                    marker(at: point(index: 0, values: gymLockSystem, in: plot), filled: false)
                        .opacity(progress > 0.02 ? 1 : 0)

                    if progress > 0.985 {
                        marker(at: point(index: gymLockSystem.count - 1, values: gymLockSystem, in: plot), filled: true)
                        marker(at: point(index: willpower.count - 1, values: willpower, in: plot), filled: true, muted: true)
                    }
                }
            }
            .frame(height: 188)

            axisLabels
                .padding(.top, 10)

            legend
                .padding(.top, 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Chart. Both paths start together in week one. Willpower alone declines to near zero by week twelve. With GymLock System it climbs steadily."
        )
    }

    // MARK: - Geometry

    private func point(index: Int, values: [CGFloat], in rect: CGRect) -> CGPoint {
        let stepX = rect.width / CGFloat(values.count - 1)
        let x = rect.minX + stepX * CGFloat(index)
        let y = rect.maxY - values[index] * rect.height
        return CGPoint(x: x, y: y)
    }

    /// Catmull-Rom smoothed path through the sample points.
    private func smoothPath(values: [CGFloat], in rect: CGRect) -> Path {
        let points = values.indices.map { point(index: $0, values: values, in: rect) }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }

    private func gridLines(in rect: CGRect) -> some View {
        Path { path in
            for fraction in [0.0, 0.5, 1.0] {
                let y = rect.maxY - CGFloat(fraction) * rect.height
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Theme.border, lineWidth: 1)
    }

    private func marker(at position: CGPoint, filled: Bool, muted: Bool = false) -> some View {
        Circle()
            .fill(filled ? (muted ? Theme.inkTertiary : Theme.accent) : Theme.surface)
            .frame(width: filled ? 9 : 11, height: filled ? 9 : 11)
            .overlay {
                Circle()
                    .strokeBorder(muted ? Theme.inkTertiary : Theme.accent, lineWidth: 2.5)
                    .opacity(filled ? 0 : 1)
            }
            .position(position)
    }

    // MARK: - Labels

    private var axisLabels: some View {
        HStack {
            Text("week 1")
            Spacer()
            Text("week 6")
            Spacer()
            Text("week 12")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.inkTertiary)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            legendRow(
                color: Theme.accent,
                dashed: false,
                label: "with GymLock System"
            )
            legendRow(
                color: Theme.inkTertiary,
                dashed: true,
                label: "willpower alone"
            )
        }
    }

    private func legendRow(color: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: 10) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 22, y: 1))
            }
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [4, 5] : [])
            )
            .frame(width: 22, height: 3)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}
