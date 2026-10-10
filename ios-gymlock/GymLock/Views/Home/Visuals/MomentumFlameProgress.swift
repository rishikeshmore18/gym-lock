import SwiftUI

/// The right half of the Momentum card: the week's gym commitment as a row of
/// flames, one per planned session, joined by connectors.
///
/// A flame lights only for a verified gym workout (`MomentumField.verifiedCount`).
/// Home sessions never light one; they stay in the "+X at home" note on the
/// left. The number of flames is the user's own plan (`targetCount`), never
/// the streak's three-day floor.
///
/// Motion is state indication only and always one-shot: a quiet left-to-right
/// pulse over the lit flames when the card first reveals, then, when a new
/// workout is verified, just the newly completed segment. Nothing loops.
struct MomentumFlameProgress: View {
    let verifiedCount: Int
    let targetCount: Int
    /// Flips to true once, when the Momentum card has arrived on screen.
    let isRevealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lit flames as drawn, which trails the data while a segment animates.
    @State private var litCount: Int
    /// Accent connectors as drawn: connector `i` joins flame `i` and `i + 1`.
    @State private var filledConnectors: Int
    /// One trigger per flame; bumping one plays that flame's pulse once.
    @State private var pulses: [Int]
    /// The flame that completes the week gets a slightly stronger settle.
    @State private var strongPulseIndex: Int?
    @State private var sequence: Task<Void, Never>?

    /// Height of the visual. Below the left column's natural height, so the
    /// card keeps exactly the size it had.
    private static let height: CGFloat = 52

    init(verifiedCount: Int, targetCount: Int, isRevealed: Bool) {
        self.verifiedCount = verifiedCount
        self.targetCount = targetCount
        self.isRevealed = isRevealed
        let lit = Self.lit(verifiedCount, of: targetCount)
        _litCount = State(initialValue: lit)
        _filledConnectors = State(initialValue: max(0, lit - 1))
        _pulses = State(initialValue: Array(repeating: 0, count: max(0, targetCount)))
    }

    private struct Snapshot: Equatable {
        var verified: Int
        var target: Int
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
            .onChange(of: isRevealed) { _, revealed in
                if revealed { playEntrance() }
            }
            .onChange(of: Snapshot(verified: verifiedCount, target: targetCount)) { old, new in
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
                    size: metrics.flame,
                    pulse: pulses.indices.contains(index) ? pulses[index] : 0,
                    isStrong: strongPulseIndex == index
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Motion

    private static func lit(_ verified: Int, of target: Int) -> Int {
        min(max(verified, 0), max(target, 0))
    }

    private func pulse(_ index: Int) {
        guard pulses.indices.contains(index) else { return }
        pulses[index] += 1
    }

    /// One quiet pass over the lit flames, left to right, 50 ms apart.
    private func playEntrance() {
        guard !reduceMotion, litCount > 0 else { return }
        sequence?.cancel()
        strongPulseIndex = nil
        let count = litCount
        sequence = Task {
            for index in 0..<count {
                pulse(index)
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
            }
        }
    }

    private func apply(from old: Snapshot, to new: Snapshot) {
        sequence?.cancel()

        if old.target != new.target {
            pulses = Array(repeating: 0, count: max(0, new.target))
            strongPulseIndex = nil
        }

        let target = Self.lit(new.verified, of: new.target)
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
        let wasComplete = old.target > 0 && Self.lit(old.verified, of: old.target) >= old.target
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
                // 2. The flame lights, 3. and settles once.
                let isLast = index == target - 1
                strongPulseIndex = (isLast && completesWeek) ? index : nil
                withAnimation(Theme.stateChange) { litCount = index + 1 }
                pulse(index)
                if isLast {
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
    let size: CGFloat
    let pulse: Int
    let isStrong: Bool

    var body: some View {
        ZStack {
            flame
                .foregroundStyle(Theme.inkTertiary.opacity(0.3))
                .opacity(isLit ? 0 : 1)
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
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: pulse) { content, scale in
            content.scaleEffect(scale, anchor: .bottom)
        } keyframes: { _ in
            // 1 → peak → 1: 200 ms, or 240 ms for the week's last flame. No
            // spring, so nothing bounces.
            LinearKeyframe(isStrong ? 1.1 : 1.06, duration: isStrong ? 0.11 : 0.09, timingCurve: .easeOut)
            LinearKeyframe(1, duration: isStrong ? 0.13 : 0.11, timingCurve: .easeInOut)
        }
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(isLit ? Theme.accent : Theme.border)
                .frame(width: size * 0.72, height: 3)
                .offset(y: 8)
        }
    }

    private var flame: some View {
        Image(systemName: "flame.fill")
            .resizable()
            .scaledToFit()
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
