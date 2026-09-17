import SwiftUI

// MARK: - Metrics

/// Sizing for the hero, derived from the width actually available.
///
/// Nothing in the hero is a constant: type, ring, padding and the CTA all scale
/// off the card, so the composition holds its proportions from an SE to an
/// iPad — the card simply stops growing past the width where it reads well.
struct HeroMetrics {
    let width: CGFloat

    /// The reference proportion. The same physical shape in every state — the
    /// card never resizes for its content.
    static let aspect: CGFloat = 2.05
    /// Past this the card stops growing and centres instead.
    static let maxWidth: CGFloat = 480

    var height: CGFloat { width / Self.aspect }
    var cornerRadius: CGFloat { 24 }
    var padding: CGFloat { max(15, width * 0.052) }

    var eyebrowSize: CGFloat { max(9, width * 0.030) }
    var headlineSize: CGFloat { width * 0.088 }
    var supportSize: CGFloat { width * 0.040 }

    var ctaDiameter: CGFloat { max(34, height * 0.27) }
    var ringDiameter: CGFloat { height * 0.80 }
    var chartHeight: CGFloat { height * 0.40 }
    var checklistFont: CGFloat { max(10, width * 0.036) }

    /// Copy width when the only thing behind it is a photograph, which can be
    /// held back to whatever width the text needs.
    var leftFraction: CGFloat { 0.58 }
    /// Copy width when a ring or a chart occupies the right side. Narrower on
    /// purpose: the two together have to fit inside the card, and at the wider
    /// value the ring was pushed past the trailing edge and clipped.
    var copyFraction: CGFloat { 0.46 }
}

// MARK: - The hero card

/// The wide card under the calendar: one fixed geometry, many visual states.
///
/// The left column is always number-led — eyebrow, dominant value, one
/// supporting line — and the right side carries whichever primitive communicates
/// the current state best: a blended photograph, a ring, a checklist, a micro
/// chart, or a numbered progression.
struct HeroCardView: View {
    let stage: HeroStage
    /// Optional destination; the CTA only appears when there is somewhere to go.
    var onCTA: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let metrics = HeroMetrics(width: min(proxy.size.width, HeroMetrics.maxWidth))

            content(metrics)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .leading
                )
        }
        .aspectRatio(HeroMetrics.aspect, contentMode: .fit)
        .frame(maxWidth: HeroMetrics.maxWidth)
        .background(cardSurface)
        .clipShape(.rect(cornerRadius: 24))
    }

    private var cardSurface: some View {
        Rectangle()
            .fill(Theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }

    @ViewBuilder
    private func content(_ metrics: HeroMetrics) -> some View {
        ZStack {
            switch stage {
            case .setupIncomplete(let items):
                SetupHero(items: items, metrics: metrics)
            case .firstDay(let alarm):
                ImageHero(
                    imageName: "HeroSummit",
                    eyebrow: "YOUR COMMITMENT",
                    headline: [alarm.displayString],
                    support: "Tomorrow",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA
                )
            case .night(let bedtime, let nextAlarm):
                ImageHero(
                    imageName: "HeroRest",
                    eyebrow: "REST NOW",
                    headline: [bedtime.displayString],
                    support: nextAlarm.map { "Tomorrow \($0.displayString)" } ?? "Tomorrow",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA
                )
            case .countdown(let secondsRemaining, let windowSeconds):
                CountdownHero(
                    secondsRemaining: secondsRemaining,
                    windowSeconds: windowSeconds,
                    metrics: metrics
                )
            // The live states lead with the instruction, never the fraction:
            // the Path card owns "how far through you are", and printing that
            // twice on one screen makes both copies mean less.
            case .committed(let step, let total):
                RingHero(
                    eyebrow: "FIRST STEP WON",
                    headline: ["Get ready"],
                    support: "Your window is open",
                    progress: Double(step) / Double(total),
                    ringIcon: "dumbbell.fill",
                    ringValue: "ready",
                    tint: Theme.accent,
                    metrics: metrics
                )
            case .departed(_, _, let nearGym):
                ImageHero(
                    imageName: "HeroDiscipline",
                    eyebrow: "YOU'RE MOVING",
                    headline: nearGym ? ["Nearly", "there."] : ["Gym next."],
                    support: nearGym ? "Almost at the door" : "Keep going",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA
                )
            case .arrived(let step, let total):
                RingHero(
                    eyebrow: "YOU'RE HERE",
                    headline: ["Train now"],
                    support: "Apps unlocked — nice work",
                    progress: Double(step) / Double(total),
                    ringIcon: "dumbbell.fill",
                    ringValue: "here",
                    tint: Theme.accent,
                    metrics: metrics
                )
            case .verified(let step, let total, _):
                RingHero(
                    eyebrow: "WORKOUT VERIFIED",
                    headline: ["Done."],
                    support: "You showed up today.",
                    progress: Double(step) / Double(total),
                    ringIcon: "checkmark",
                    ringValue: "done",
                    tint: Theme.ink,
                    metrics: metrics
                )
            case .missed:
                ImageHero(
                    imageName: "HeroRoad",
                    eyebrow: "DON'T MISS TWICE",
                    headline: ["New start", "today."],
                    support: "One session resets everything.",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA
                )
            case .comeback:
                ComebackHero(metrics: metrics)
            case .restDay(let nextDay, let nextTime):
                ImageHero(
                    imageName: "HeroRest",
                    eyebrow: "REST DAY",
                    headline: ["Recover", "today."],
                    support: [nextDay, nextTime].compactMap { $0 }.joined(separator: " "),
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA
                )
            case .weekProgress(let done, let of, let useDots):
                ImageHero(
                    imageName: "HeroMountain",
                    eyebrow: "YOUR PROGRESS",
                    headline: ["\(done) of \(of)"],
                    support: "sessions completed",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA,
                    bottom: {
                        if useDots {
                            GymLockStepDots(
                                total: min(of, 4),
                                completed: min(done, 4),
                                dotSize: metrics.supportSize * 0.62
                            )
                        } else {
                            GymLockLinearProgress(
                                progress: of > 0 ? Double(done) / Double(of) : 0
                            )
                            .frame(width: metrics.width * 0.34)
                        }
                    }
                )
            case .pattern(let labels, let values, let bestIndex):
                PatternHero(
                    labels: labels,
                    values: values,
                    bestIndex: bestIndex,
                    metrics: metrics
                )
            case .monthComplete(let sessions, let consistency):
                ImageHero(
                    imageName: "HeroSummit",
                    eyebrow: "MONTH COMPLETE",
                    headline: [],
                    support: "Ready for the next one.",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA,
                    bottom: {
                        GymLockMetricPair(
                            leftValue: "\(sessions)",
                            leftLabel: "verified sessions",
                            rightValue: "\(consistency)%",
                            rightLabel: "consistency",
                            valueSize: metrics.headlineSize * 0.72,
                            labelSize: metrics.supportSize * 0.8
                        )
                        .frame(maxWidth: metrics.width * 0.5, alignment: .leading)
                    }
                )
            case .startMonth(let totalSessions, let goal):
                ImageHero(
                    imageName: "HeroMountain",
                    eyebrow: "FRESH MONTH",
                    headline: ["\(totalSessions) verified", "sessions"],
                    support: "Goal this month: \(goal)",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA
                )
            case .midMonth(let done, let of, let percent):
                ImageHero(
                    imageName: "HeroRoad",
                    eyebrow: "ON TRACK",
                    headline: ["\(done) of \(of) done"],
                    support: "\(percent)% consistency",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA,
                    bottom: {
                        GymLockLinearProgress(
                            progress: of > 0 ? Double(done) / Double(of) : 0
                        )
                        .frame(width: metrics.width * 0.34)
                    }
                )
            case .latePattern(let momentumWeeks):
                ImageHero(
                    imageName: "HeroSummit",
                    eyebrow: "PATTERN BUILT",
                    headline: ["You built", "a pattern."],
                    support: "\(momentumWeeks) week momentum",
                    metrics: metrics,
                    showsCTA: onCTA != nil,
                    onCTA: onCTA
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: stage)
    }
}

// MARK: - Shared hero layouts

/// Text-only left column over a blended photograph.
private struct ImageHero: View {
    let imageName: String
    let eyebrow: String
    let headline: [String]
    let support: String
    let metrics: HeroMetrics
    let showsCTA: Bool
    let onCTA: (() -> Void)?
    /// Optional compact component under the copy — dots, a bar, a metric pair.
    private let bottomContent: AnyView?

    init(
        imageName: String,
        eyebrow: String,
        headline: [String],
        support: String,
        metrics: HeroMetrics,
        showsCTA: Bool,
        onCTA: (() -> Void)?
    ) {
        self.imageName = imageName
        self.eyebrow = eyebrow
        self.headline = headline
        self.support = support
        self.metrics = metrics
        self.showsCTA = showsCTA
        self.onCTA = onCTA
        self.bottomContent = nil
    }

    init(
        imageName: String,
        eyebrow: String,
        headline: [String],
        support: String,
        metrics: HeroMetrics,
        showsCTA: Bool,
        onCTA: (() -> Void)?,
        @ViewBuilder bottom: () -> some View
    ) {
        self.imageName = imageName
        self.eyebrow = eyebrow
        self.headline = headline
        self.support = support
        self.metrics = metrics
        self.showsCTA = showsCTA
        self.onCTA = onCTA
        self.bottomContent = AnyView(bottom())
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // The photograph is held back across the whole copy column, so text
            // always sits on white rather than on whatever happens to be in the
            // artwork behind it.
            GymLockHeroImageBlend(name: imageName, safeFraction: metrics.leftFraction)
                .frame(width: metrics.width, height: metrics.height)

            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .font(.system(size: metrics.eyebrowSize, weight: .bold))
                    .tracking(metrics.eyebrowSize * 0.14)
                    .foregroundStyle(Theme.inkSecondary)

                headlineText
                    .padding(.top, 2)

                Text(support)
                    .font(.system(size: metrics.supportSize, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    // Two lines rather than one truncated one: a supporting
                    // line ending in an ellipsis reads as a bug.
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 3)

                if let bottomContent {
                    bottomContent
                        .padding(.top, metrics.padding * 0.45)
                }

                if showsCTA {
                    Spacer(minLength: 0)
                    GymLockCircularCTA(diameter: metrics.ctaDiameter, action: { onCTA?() })
                }
            }
            .padding(.leading, metrics.padding)
            .padding(.vertical, metrics.padding)
            .frame(width: metrics.width * metrics.leftFraction, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var headlineText: some View {
        if !headline.isEmpty {
            VStack(alignment: .leading, spacing: -metrics.headlineSize * 0.08) {
                ForEach(headline.indices, id: \.self) { index in
                    Text(headline[index])
                        .font(.system(size: metrics.headlineSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}

/// Left copy, right progress ring.
private struct RingHero: View {
    let eyebrow: String
    let headline: [String]
    let support: String
    let progress: Double
    let ringIcon: String
    let ringValue: String
    let tint: Color
    let metrics: HeroMetrics

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .font(.system(size: metrics.eyebrowSize, weight: .bold))
                    .tracking(metrics.eyebrowSize * 0.14)
                    .foregroundStyle(Theme.inkSecondary)

                ForEach(headline.indices, id: \.self) { index in
                    Text(headline[index])
                        .font(.system(size: metrics.headlineSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .padding(.top, 2)
                }

                Text(support)
                    .font(.system(size: metrics.supportSize, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 3)
            }
            .frame(width: metrics.width * metrics.copyFraction, alignment: .leading)
            .padding(.leading, metrics.padding)

            Spacer(minLength: 0)

            GymLockProgressRing(
                progress: progress,
                icon: ringIcon,
                valueText: ringValue,
                diameter: metrics.ringDiameter,
                tint: tint
            )
            .padding(.trailing, metrics.padding)
        }
        .frame(height: metrics.height)
        .accessibilityElement(children: .combine)
    }
}

/// Ticking countdown with a coral ring.
private struct CountdownHero: View {
    let windowSeconds: Int
    let metrics: HeroMetrics

    /// The countdown is anchored to wall-clock time once, so re-renders tick
    /// the same clock down instead of resetting it — and a stale target from a
    /// finished countdown re-anchors itself.
    private static var anchoredTarget: Date?
    private let target: Date

    init(secondsRemaining: Int, windowSeconds: Int, metrics: HeroMetrics) {
        self.windowSeconds = windowSeconds
        self.metrics = metrics

        let now = Date()
        if let anchored = Self.anchoredTarget, anchored > now {
            target = anchored
        } else {
            target = now.addingTimeInterval(Double(secondsRemaining))
            Self.anchoredTarget = target
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(target.timeIntervalSince(context.date)))
            let fraction = windowSeconds > 0
                ? 1 - Double(remaining) / Double(windowSeconds)
                : 0

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("GYM TIME IN")
                        .font(.system(size: metrics.eyebrowSize, weight: .bold))
                        .tracking(metrics.eyebrowSize * 0.14)
                        .foregroundStyle(Theme.inkSecondary)

                    Text(Self.clockString(remaining))
                        .font(.system(size: metrics.headlineSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 2)

                    Text("4 steps to a stronger you")
                        .font(.system(size: metrics.supportSize, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 3)
                }
                .frame(width: metrics.width * metrics.copyFraction, alignment: .leading)
                .padding(.leading, metrics.padding)

                Spacer(minLength: 0)

                GymLockProgressRing(
                    progress: fraction,
                    icon: "dumbbell.fill",
                    valueText: "ready",
                    diameter: metrics.ringDiameter,
                    tint: Theme.accent,
                    valueScale: 0.13
                )
                .padding(.trailing, metrics.padding)
            }
            .frame(height: metrics.height)
        }
        .accessibilityElement(children: .combine)
    }

    private static func clockString(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

/// Setup checklist hero: left number, right checklist.
private struct SetupHero: View {
    let items: [ChecklistItem]
    let metrics: HeroMetrics

    private var doneCount: Int { items.filter(\.isDone).count }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("FINISH YOUR SYSTEM")
                    .font(.system(size: metrics.eyebrowSize, weight: .bold))
                    .tracking(metrics.eyebrowSize * 0.14)
                    .foregroundStyle(Theme.inkSecondary)

                Text("\(doneCount) of \(items.count) ready")
                    .font(.system(size: metrics.headlineSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .padding(.top, 2)

                // Honest at both ends: nothing is "nearly armed" on the first
                // run, and nothing needs three steps when one is left.
                Text(doneCount == 0 ? "Three quick steps" : "Nearly armed")
                    .font(.system(size: metrics.supportSize, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 3)
            }
            .frame(width: metrics.width * 0.40, alignment: .leading)
            .padding(.leading, metrics.padding)

            Spacer(minLength: 0)

            GymLockChecklist(
                items: items,
                markerSize: metrics.checklistFont * 1.2,
                fontScale: metrics.checklistFont
            )
            .padding(.trailing, metrics.padding)
        }
        .frame(height: metrics.height)
        .accessibilityElement(children: .combine)
    }
}

/// Pattern insight: copy left, seven-bar micro chart right.
private struct PatternHero: View {
    let labels: [String]
    let values: [Int]
    let bestIndex: Int
    let metrics: HeroMetrics

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("WEEK INSIGHT")
                    .font(.system(size: metrics.eyebrowSize, weight: .bold))
                    .tracking(metrics.eyebrowSize * 0.14)
                    .foregroundStyle(Theme.inkSecondary)

                Text("Best consistency:")
                    .font(.system(size: metrics.headlineSize * 0.62, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .padding(.top, 2)

                Text(bestLabels)
                    .font(.system(size: metrics.headlineSize * 0.82, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("verified sessions by day")
                    .font(.system(size: metrics.supportSize, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            .frame(width: metrics.width * 0.44, alignment: .leading)
            .padding(.leading, metrics.padding)

            Spacer(minLength: 0)

            GymLockMiniBarChart(
                values: values,
                bestIndex: bestIndex,
                weekdayLabels: labels,
                height: metrics.chartHeight
            )
            .frame(width: metrics.width * 0.34)
            .padding(.trailing, metrics.padding)
        }
        .frame(height: metrics.height)
        .accessibilityElement(children: .combine)
    }

    /// The strongest day, plus a tie or near-tie, as "Tue / Thu".
    private var bestLabels: String {
        guard !values.isEmpty else { return "—" }
        let best = values[bestIndex]
        let tied = values.indices.filter { values[$0] >= max(best - 1, 1) && $0 >= bestIndex }
        let picked = Array(tied.prefix(2)).sorted()
        return picked.map { labels[$0] }.joined(separator: " / ")
    }
}

/// Comeback hero: copy left, numbered progression right.
private struct ComebackHero: View {
    let metrics: HeroMetrics

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("NEXT STEP")
                    .font(.system(size: metrics.eyebrowSize, weight: .bold))
                    .tracking(metrics.eyebrowSize * 0.14)
                    .foregroundStyle(Theme.inkSecondary)

                Text("Show up")
                    .font(.system(size: metrics.headlineSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)

                Text("today.")
                    .font(.system(size: metrics.headlineSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)

                Text("1 session = momentum back.")
                    .font(.system(size: metrics.supportSize, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 3)
            }
            .frame(width: metrics.width * 0.46, alignment: .leading)
            .padding(.leading, metrics.padding)

            Spacer(minLength: 0)

            GymLockNumberedSteps(
                labels: ["Show up", "Work out", "Complete", "Feel better"],
                currentIndex: 0,
                fontScale: metrics.supportSize
            )
            .padding(.trailing, metrics.padding)
        }
        .frame(height: metrics.height)
        .accessibilityElement(children: .combine)
    }
}
