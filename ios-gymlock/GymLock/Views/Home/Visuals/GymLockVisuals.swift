import SwiftUI

// MARK: - Progress ring

/// The circular progress treatment: thick elegant track, round caps, progress
/// from 12 o'clock, an icon and a value in the middle. Never spins on its own —
/// it animates when the value changes and then it stops.
struct GymLockProgressRing: View {
    /// 0...1.
    var progress: Double
    var icon: String
    var valueText: String
    var diameter: CGFloat
    /// Black for quiet states, coral only where the arc is the active signal.
    var tint: Color = Theme.ink
    var iconScale: CGFloat = 0.22
    var valueScale: CGFloat = 0.17

    @State private var drawnProgress: Double = 0

    var body: some View {
        let lineWidth = diameter * 0.115

        ZStack {
            Circle()
                .stroke(Theme.surfaceMuted, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: drawnProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: diameter * 0.02) {
                Image(systemName: icon)
                    .font(.system(size: diameter * iconScale, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text(valueText)
                    .font(.system(size: diameter * valueScale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(lineWidth + diameter * 0.08)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { drawnProgress = clampedProgress }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.6)) { drawnProgress = clamped(newValue) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(valueText) complete")
    }

    private var clampedProgress: Double { clamped(progress) }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - Step dots

/// The four-step path at a glance: filled for done, coral for the step the user
/// is on, outlined for what is left. Only the newly completed dot animates.
struct GymLockStepDots: View {
    var total: Int = 4
    /// Steps fully completed.
    var completed: Int
    var dotSize: CGFloat = 9
    var spacing: CGFloat = 7
    /// False before the morning has begun. Nothing is "current" yet, so no dot
    /// takes the coral — an untouched path reads as waiting, never as behind.
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The dot that just landed, held long enough to pop and settle.
    @State private var poppedIndex: Int?
    @State private var settle: Task<Void, Never>?

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<total, id: \.self) { index in
                dot(for: index)
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .onChange(of: completed) { previous, current in
            guard current > previous, !reduceMotion else { return }
            markLanded(current - 1)
        }
        .onDisappear { settle?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(total) steps complete")
    }

    @ViewBuilder
    private func dot(for index: Int) -> some View {
        let isCompleted = index < completed
        let isCurrent = isActive && index == completed && completed < total
        let isPopped = poppedIndex == index

        Circle()
            .fill(fill(isCompleted: isCompleted, isCurrent: isCurrent))
            .overlay {
                if !isCompleted, !isCurrent {
                    Circle().strokeBorder(Theme.border, lineWidth: 1.2)
                }
            }
            // Only the dot that just turned is worth animating; the ones
            // already done render settled.
            .scaleEffect(isPopped ? 1.45 : 1)
    }

    private func fill(isCompleted: Bool, isCurrent: Bool) -> Color {
        if isCompleted { return Theme.ink }
        if isCurrent { return Theme.accent }
        return Theme.surface
    }

    /// A step landing: one quick swell, then back to resting. Small enough that
    /// it registers as confirmation rather than celebration — the celebration
    /// belongs to finishing the path.
    private func markLanded(_ index: Int) {
        settle?.cancel()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.45)) { poppedIndex = index }

        settle = Task {
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { poppedIndex = nil }
        }
    }
}

// MARK: - Segmented progress

/// Compact horizontal segments — the four-step path as bars rather than dots.
struct GymLockSegmentedProgress: View {
    var total: Int = 4
    var completed: Int
    var height: CGFloat = 5
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < completed ? Theme.ink : Theme.surfaceMuted)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(total) complete")
    }
}

// MARK: - Linear progress

/// The minimalist bar: thin track, near-black fill, fully rounded. Height 5–7pt
/// — never a great colourful fitness bar.
struct GymLockLinearProgress: View {
    /// 0...1.
    var progress: Double
    /// Coral only for meaningful active progress.
    var tint: Color = Theme.ink
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let filled = proxy.size.width * min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceMuted)
                Capsule()
                    .fill(tint)
                    .frame(width: max(filled, height))
                    .animation(.easeOut(duration: 0.5), value: progress)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent")
    }
}

// MARK: - Micro bar chart

/// Seven weekday bars, no axes, no gridlines, no border. The strongest day may
/// take a subtle coral; everything else stays grayscale. This is a
/// microvisualisation, not analytics.
struct GymLockMiniBarChart: View {
    /// Exactly seven values, Monday-first.
    var values: [Int]
    /// Index of the strongest day, drawn darker than the rest.
    var bestIndex: Int?
    var weekdayLabels: [String]
    var height: CGFloat = 44

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(values.indices, id: \.self) { index in
                column(for: index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sessions by weekday")
    }

    @ViewBuilder
    private func column(for index: Int) -> some View {
        let maxValue = max(values.max() ?? 1, 1)
        let fraction = CGFloat(values[index]) / CGFloat(maxValue)
        let isBest = index == bestIndex

        VStack(spacing: 3) {
            Capsule()
                .fill(barFill(isBest: isBest, hasValue: values[index] > 0))
                .frame(height: barHeight(fraction: fraction))
                .frame(maxWidth: .infinity)

            Text(weekdayLabels.indices.contains(index) ? weekdayLabels[index] : "")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func barHeight(fraction: CGFloat) -> CGFloat {
        let minimum: CGFloat = 3
        guard fraction > 0 else { return minimum }
        return minimum + (height - minimum) * min(fraction, 1)
    }

    private func barFill(isBest: Bool, hasValue: Bool) -> Color {
        if isBest { return Theme.accent }
        if !hasValue { return Theme.border }
        return Theme.ink
    }
}

// MARK: - Checklist

/// The setup checklist: filled black circle with a white check for done, thin
/// outlined circle for open. Maximum four rows, compact enough for a hero.
struct GymLockChecklist: View {
    var items: [ChecklistItem]
    var rowSpacing: CGFloat = 7
    var markerSize: CGFloat = 15
    var fontScale: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(items) { item in
                HStack(spacing: 7) {
                    marker(isDone: item.isDone)
                        .frame(width: markerSize, height: markerSize)

                    Text(item.label)
                        .font(.system(size: fontScale, weight: .medium))
                        .foregroundStyle(item.isDone ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func marker(isDone: Bool) -> some View {
        if isDone {
            Circle()
                .fill(Theme.ink)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: markerSize * 0.48, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(isDone ? 1 : 0.8)
        } else {
            Circle()
                .fill(Theme.surface)
                .overlay {
                    Circle().strokeBorder(Theme.border, lineWidth: 1.2)
                }
        }
    }
}

// MARK: - Metric pair

/// Two headline metrics side by side with a hairline between them. Maximum two
/// — never a dashboard.
struct GymLockMetricPair: View {
    var leftValue: String
    var leftLabel: String
    var rightValue: String
    var rightLabel: String
    var valueSize: CGFloat = 24
    var labelSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 14) {
            metric(value: leftValue, label: leftLabel)
            Rectangle().fill(Theme.border).frame(width: 1, height: valueSize * 1.5)
            metric(value: rightValue, label: rightLabel)
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Hero image blend

/// Full-bleed grayscale photograph dissolving into the white information area.
///
/// The supplied assets carry their own feathered blend and their motivational
/// type — that typography is part of the artwork and is never duplicated in
/// SwiftUI. A soft leading gradient is layered on top purely as insurance so
/// the left column keeps its contrast on any crop.
struct GymLockHeroImageBlend: View {
    var name: String
    /// The share of the width the copy occupies. The photograph is held at full
    /// white across this region and only begins to appear past it, so a
    /// headline can never end up sitting on top of a grey shoulder or a lighting
    /// change in the artwork.
    var safeFraction: CGFloat = 0.5
    /// How far past the safe region the image takes to reach full strength.
    var featherWidth: CGFloat = 0.2

    var body: some View {
        GeometryReader { proxy in
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .grayscale(1)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: max(safeFraction * 0.88, 0.01)),
                            .init(color: .white.opacity(0.88), location: max(safeFraction, 0.02)),
                            .init(color: .white.opacity(0), location: min(safeFraction + featherWidth, 1)),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .allowsHitTesting(false)
                }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Circular CTA

/// The black circle with a chevron, bottom-left of the hero.
struct GymLockCircularCTA: View {
    var diameter: CGFloat
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: diameter * 0.32, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Theme.ink, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(PressDownStyle())
        .accessibilityLabel("Open")
    }
}

/// Gentle press: a small scale and a slightly dimmed surface, nothing bouncy.
struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Status icon

/// Monochrome symbol in a very subtle warm circle — the mini-card topper.
struct GymLockStatusIcon: View {
    var systemName: String
    var circleSize: CGFloat = 26
    var iconScale: CGFloat = 0.5
    var tint: Color = Theme.ink

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: circleSize * iconScale, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: circleSize, height: circleSize)
            .background(Theme.surfaceMuted, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - Mini metric

/// The content stack inside a mini card: tiny label, large value, optional
/// supporting line. Not a card in itself — the row owns the surfaces.
struct GymLockMiniMetric: View {
    var label: String
    var value: String
    var detail: String?
    var valueScale: CGFloat
    var labelScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: labelScale, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(size: valueScale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            if let detail {
                Text(detail)
                    .font(.system(size: labelScale * 0.92, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 1)
            }
        }
    }
}

// MARK: - Trend row

/// The two-item milestone row ("Stronger pattern | Week 1 complete") under a
/// hero headline. Small icon, small text, hairline between.
struct GymLockTrendBars: View {
    var items: [(icon: String, label: String)]
    var fontScale: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Theme.border).frame(width: 1, height: fontScale * 1.6)
                }

                HStack(spacing: 5) {
                    Image(systemName: items[index].icon)
                        .font(.system(size: fontScale, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(items[index].label)
                        .font(.system(size: fontScale, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Numbered steps

/// The vertical comeback progression: small numbered circles, current in black,
/// future in light gray. Never styled as a failure checklist.
struct GymLockNumberedSteps: View {
    var labels: [String]
    /// Index of the step the user is on; earlier steps read as done.
    var currentIndex: Int = 0
    var fontScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: fontScale * 0.55) {
            ForEach(labels.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: fontScale * 0.72, weight: .bold, design: .rounded))
                        .foregroundStyle(index <= currentIndex ? .white : Theme.inkTertiary)
                        .frame(
                            width: fontScale * 1.25,
                            height: fontScale * 1.25
                        )
                        .background(
                            index <= currentIndex ? Theme.ink : Theme.surface,
                            in: .circle
                        )
                        .overlay {
                            if index > currentIndex {
                                Circle().strokeBorder(Theme.border, lineWidth: 1)
                            }
                        }

                    Text(labels[index])
                        .font(.system(size: fontScale * 0.82, weight: .medium))
                        .foregroundStyle(index <= currentIndex ? Theme.ink : Theme.inkTertiary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
