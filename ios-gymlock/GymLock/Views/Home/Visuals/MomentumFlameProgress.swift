import SwiftUI

/// The right half of the Momentum card: the week's gym commitment as a row of
/// flames, one per planned session, joined by connectors.
///
/// A flame lights for each counted workout day (`MomentumField.countedCount`):
/// gym or home, the same days the streak counts, each day once. The number
/// of flames is this week's goal (`targetCount`), the days the user planned.
/// Extra workouts past the goal light nothing more.
///
/// Motion follows the badges emblem's rule: light is the only motion. Lit
/// flames carry the same slow specular sweep as `BadgeEmblem`, the next unlit
/// flame breathes gently to mark itself as the next task, and nothing ever
/// scales, bounces, or pulses.
struct MomentumFlameProgress: View {
    let countedCount: Int
    let targetCount: Int
    /// Flips to true once, when the Momentum card has arrived on screen.
    let isRevealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lit flames as drawn, which trails the data while a segment animates.
    @State private var litCount: Int
    /// Accent connectors as drawn: connector `i` joins flame `i` and `i + 1`.
    @State private var filledConnectors: Int
    @State private var sequence: Task<Void, Never>?

    /// Height of the visual. Below the left column's natural height, so the
    /// card keeps exactly the size it had.
    private static let height: CGFloat = 52

    init(countedCount: Int, targetCount: Int, isRevealed: Bool) {
        self.countedCount = countedCount
        self.targetCount = targetCount
        self.isRevealed = isRevealed
        let lit = Self.lit(countedCount, of: targetCount)
        _litCount = State(initialValue: lit)
        _filledConnectors = State(initialValue: max(0, lit - 1))
    }

    private struct Snapshot: Equatable {
        var counted: Int
        var target: Int
    }

    /// The flame that is the user's next task: the first unlit one, while the
    /// week still has room. There is no next flame once the week is complete.
    private var nextFlame: Int? {
        litCount < targetCount ? litCount : nil
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .overlay {
                GeometryReader { proxy in
                    row(metrics: Metrics(width: proxy.size.width, count: targetCount))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .onChange(of: Snapshot(counted: countedCount, target: targetCount)) { old, new in
                apply(from: old, to: new)
            }
            .onDisappear { sequence?.cancel() }
    }

    // MARK: Layout

    /// Flame size and connector length from the width actually available.
    private struct Metrics {
        var flame: CGFloat
        var connector: CGFloat

        init(width: CGFloat, count: Int) {
            let n = CGFloat(max(count, 1))
            let gaps = n - 1
            // Connectors run at about 60% of a flame, then everything is
            // clamped: big flames for a three-day plan, small for seven.
            var flame = width / (n + gaps * 0.6)
            flame = min(max(flame, 14), 34)
            if gaps > 0 { flame = min(flame, (width - gaps * 10) / n) }
            self.flame = max(flame, 10)
            self.connector = gaps > 0 ? min(max((width - n * self.flame) / gaps, 10), 40) : 0
        }
    }

    private func row(metrics: Metrics) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<max(targetCount, 0), id: \.self) { index in
                if index > 0 {
                    MomentumFlameConnector(isFilled: index - 1 < filledConnectors, reduceMotion: reduceMotion)
                        .frame(width: metrics.connector)
                        // Level with the body of the flame rather than its tip.
                        .offset(y: metrics.flame * 0.1)
                }
                MomentumFlameStage(
                    isLit: index < litCount,
                    isNext: nextFlame == index,
                    isRevealed: isRevealed,
                    size: metrics.flame
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Motion

    private static func lit(_ counted: Int, of target: Int) -> Int {
        min(max(counted, 0), max(target, 0))
    }

    private func apply(from old: Snapshot, to new: Snapshot) {
        sequence?.cancel()

        let target = Self.lit(new.counted, of: new.target)
        let start = min(litCount, target)

        // Fewer lit (a new week, a corrected record): show it, quietly.
        guard target > start, isRevealed else {
            withAnimation(Theme.stateChange) {
                litCount = target
                filledConnectors = max(0, target - 1)
            }
            return
        }

        // The week's own goal reached just now, not a bonus visit past it.
        let wasComplete = old.target > 0 && Self.lit(old.counted, of: old.target) >= old.target
        let completesWeek = target == new.target && !wasComplete

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                litCount = target
                filledConnectors = max(0, target - 1)
            }
            completesWeek ? Haptics.commit() : Haptics.tap()
            return
        }

        sequence = Task {
            for index in start..<target {
                // 1. The connector into this flame draws across.
                if index > 0 {
                    withAnimation(.easeOut(duration: 0.16)) { filledConnectors = index }
                    try? await Task.sleep(for: .milliseconds(130))
                    if Task.isCancelled { return }
                }
                // 2. The flame lights with the card's state change.
                withAnimation(Theme.stateChange) { litCount = index + 1 }
                if index == target - 1 {
                    completesWeek ? Haptics.commit() : Haptics.tap()
                } else {
                    try? await Task.sleep(for: .milliseconds(200))
                    if Task.isCancelled { return }
                }
            }
        }
    }
}

// MARK: - One planned session

private struct MomentumFlameStage: View {
    let isLit: Bool
    /// True for the one unlit flame that is the user's next task.
    let isNext: Bool
    let isRevealed: Bool
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            idle
            litFlame
            sheen
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(isLit ? Theme.accent : Theme.border)
                .frame(width: size * 0.72, height: 3)
                .offset(y: 8)
        }
    }

    /// The unlit flame: quiet grey, breathing only while it is the next task.
    private var idle: some View {
        flame
            .foregroundStyle(Theme.inkTertiary.opacity(0.3))
            .opacity(isLit ? 0 : 1)
            .modifier(NextTaskBreathe(isActive: isNext && !reduceMotion && isRevealed))
    }

    private var litFlame: some View {
        flame
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.accentWarm, Theme.accent, Theme.accentDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(isLit ? 1 : 0)
    }

    // MARK: Specular sweep — the badge emblem's motion, on the lit flame

    /// A soft diagonal band of light, clipped to the flame itself. The same
    /// slow sweep the badge uses: it crosses, pauses well out of frame, and
    /// comes back. It never pulses or asks for attention.
    @ViewBuilder
    private var sheen: some View {
        if isLit && !reduceMotion {
            band
                .phaseAnimator(SheenPhase.allCases) { content, phase in
                    content
                        .offset(x: phase.offset * size)
                        .opacity(phase.opacity)
                } animation: { phase in
                    switch phase {
                    // The return trip is long and fully transparent: it doubles
                    // as the pause between sweeps, so nothing flickers back.
                    case .rest: .linear(duration: 3.8)
                    case .sweep: .easeInOut(duration: 1.15)
                    case .fade: .easeOut(duration: 0.3)
                    }
                }
                .blendMode(.plusLighter)
                .mask { litFlame.allowsHitTesting(false) }
                .allowsHitTesting(false)
        }
    }

    private var band: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.9), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: size * 0.4, height: size * 2)
        .rotationEffect(.degrees(18))
    }

    private var flame: some View {
        Image(systemName: "flame.fill")
            .resizable()
            .scaledToFit()
    }
}

/// Where the light is, and whether it is visible there.
private enum SheenPhase: CaseIterable {
    /// Parked off the left edge, invisible.
    case rest
    /// Crossing the flame.
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

/// The next task's cue: a slow, shallow opacity breathe — light coming and
/// going, nothing more. Stops the moment the flame is lit, the week is
/// complete, or Reduce Motion is on.
private struct NextTaskBreathe: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([0.3, 0.55, 0.3]) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 1.6)
            }
        } else {
            content
        }
    }
}

// MARK: - Between two sessions

private struct MomentumFlameConnector: View {
    let isFilled: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            DashedLine()
                .stroke(Theme.inkTertiary.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 4]))
                .opacity(isFilled ? 0 : 1)
            Capsule()
                .fill(Theme.accent)
                // Drawn across from the lit flame; under Reduce Motion it
                // simply fades in.
                .scaleEffect(x: isFilled || reduceMotion ? 1 : 0.001, anchor: .leading)
                .opacity(isFilled ? 1 : 0)
        }
        .frame(height: 2)
        .padding(.horizontal, 3)
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
