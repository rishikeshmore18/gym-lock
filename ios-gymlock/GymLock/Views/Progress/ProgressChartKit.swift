import SwiftUI

// MARK: - Palette

/// The four marks the progress charts are allowed to draw.
///
/// Deliberately local to this feature rather than added to `Theme`: these are
/// chart semantics, not app-wide tokens, and the global palette stays as it is.
/// Black and orange are the only two ink-heavy colours, so a filled bar always
/// means the user did something.
enum ProgressPalette {
    /// Verified gym visit. The strongest mark on the page.
    static let gym = Theme.ink
    /// The 25-minute home fallback. Never black — it kept the commitment, but
    /// it was not a trip to the gym.
    static let quick = Color(red: 1.0, green: 0.451, blue: 0.0)
    /// A recorded miss. Stated as a fact, in the quietest grey that still reads.
    static let missed = Color(red: 0.855, green: 0.851, blue: 0.839)
    /// Planned and still ahead. Barely there, and outlined rather than filled.
    static let ghostFill = Color(red: 0.949, green: 0.945, blue: 0.933)
    static let ghostStroke = Color(red: 0.882, green: 0.878, blue: 0.866)
    /// The empty channel a day column sits in.
    static let track = Color(red: 0.965, green: 0.961, blue: 0.953)
}

// MARK: - Layers

/// One physical card inside a stack.
///
/// The order of the cases is the order they are drawn, top to bottom: the
/// lightest, least-earned layer sits at the top of the bar and the verified
/// gym sessions sit at its base.
enum ProgressLayerKind: Int, Hashable, Comparable {
    case ghost
    case missed
    case quick
    case gym

    static func < (lhs: ProgressLayerKind, rhs: ProgressLayerKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var fill: Color {
        switch self {
        case .ghost: ProgressPalette.ghostFill
        case .missed: ProgressPalette.missed
        case .quick: ProgressPalette.quick
        case .gym: ProgressPalette.gym
        }
    }

    /// Only the ghost layer is outlined; the others are solid enough to read.
    var stroke: Color? {
        self == .ghost ? ProgressPalette.ghostStroke : nil
    }

    /// Dark cards catch a hairline of light on their top edge, which is what
    /// makes the stack read as separate objects rather than one painted bar.
    var wantsTopHighlight: Bool {
        self == .gym || self == .quick
    }

    /// Build order. The neutral back card rises first, then the verified gym
    /// layer, then the quick workout — so the stack assembles front-to-back
    /// the way a hand of cards is put down.
    var riseOrder: Int {
        switch self {
        case .ghost, .missed: 0
        case .gym: 1
        case .quick: 2
        }
    }
}

/// A layer and how many session slots it stands for.
struct ProgressLayer: Identifiable, Hashable {
    let kind: ProgressLayerKind
    let units: Int

    var id: Int { kind.rawValue }
}

extension ProgressTally {
    /// The stack this tally draws as, biggest-earned at the base.
    ///
    /// Upcoming, unresolved and excused slots collapse into one ghost layer:
    /// they are all "nothing happened here yet", and splitting them into
    /// separate greys would invent a distinction the user did not ask about.
    var layers: [ProgressLayer] {
        var built: [ProgressLayer] = []
        if ghost > 0 { built.append(ProgressLayer(kind: .ghost, units: ghost)) }
        if missed > 0 { built.append(ProgressLayer(kind: .missed, units: missed)) }
        if quickWorkout > 0 { built.append(ProgressLayer(kind: .quick, units: quickWorkout)) }
        if verifiedGym > 0 { built.append(ProgressLayer(kind: .gym, units: verifiedGym)) }
        return built.sorted { $0.kind < $1.kind }
    }
}

// MARK: - The stack

/// A column built from overlapping rounded cards.
///
/// Not a bar with colours painted inside it: every layer is its own shape with
/// its own edge and its own shadow, tucked under the one below it, so the
/// column reads as a small stack of physical cards rather than a histogram.
struct ProgressLayeredBar: View {
    let layers: [ProgressLayer]
    /// Height of a single session slot.
    let unitHeight: CGFloat
    var cornerRadius: CGFloat = 7
    /// How far each card tucks under its neighbour.
    var overlap: CGFloat = 5
    let hasAppeared: Bool
    let reduceMotion: Bool
    /// Stagger applied to the whole column, on top of the per-layer order.
    var baseDelay: Double = 0

    var body: some View {
        let neutral = layers.filter { $0.kind == .ghost || $0.kind == .missed }
        let gym = layers.first { $0.kind == .gym }
        let quick = layers.first { $0.kind == .quick }

        VStack(spacing: -overlap) {
            ForEach(neutral) { layer in
                card(for: layer)
            }
            if gym != nil || quick != nil {
                workoutCards(gym: gym, quick: quick)
            }
        }
    }

    // MARK: Workout cards

    /// How far the orange card lifts and steps aside when the counts tie, so
    /// two equal cards never hide each other.
    private var tieLift: CGFloat { min(6, unitHeight * 0.3) }
    private let tieInset: CGFloat = 5

    /// Gym and Quick 25 drawn as two physical cards, one in front of the other,
    /// rather than two blocks stacked end to end.
    ///
    /// Both stand on the baseline at their own height. The bigger one sits
    /// behind and carries on down behind the smaller one, so its lower edge is
    /// never seen; the smaller one sits in front with a soft shadow.
    @ViewBuilder
    private func workoutCards(gym: ProgressLayer?, quick: ProgressLayer?) -> some View {
        if let gym, let quick {
            if gym.units == quick.units {
                tiedCards(gym: gym, quick: quick)
            } else {
                let back = gym.units > quick.units ? gym : quick
                let front = gym.units > quick.units ? quick : gym
                layeredCards(back: back, front: front)
            }
        } else if let only = gym ?? quick {
            card(for: only)
        }
    }

    private func layeredCards(back: ProgressLayer, front: ProgressLayer) -> some View {
        let backHeight = height(for: back) + overlap
        let frontHeight = height(for: front)
        // The back card stops at the middle of the front card. A card is always
        // full width there (its radius never exceeds half its height), so the
        // back card's lower edge is hidden and no corner peeks out beside it.
        let tuck = frontHeight / 2

        return ZStack(alignment: .bottom) {
            styledCard(
                kind: back.kind,
                height: backHeight - tuck,
                bottomRadius: 0,
                shadow: false,
                riseOrder: 1
            )
            .padding(.bottom, tuck)

            styledCard(
                kind: front.kind,
                height: frontHeight,
                bottomRadius: nil,
                shadow: true,
                riseOrder: 2
            )
        }
        .frame(height: backHeight, alignment: .bottom)
    }

    /// Equal counts: equal heights, with the orange card lifted a touch and
    /// stepped to one side behind the black one, so both stay readable.
    private func tiedCards(gym: ProgressLayer, quick: ProgressLayer) -> some View {
        let cardHeight = height(for: gym) + overlap

        return ZStack(alignment: .bottom) {
            styledCard(
                kind: quick.kind,
                height: cardHeight,
                bottomRadius: nil,
                shadow: false,
                riseOrder: 1
            )
            .padding(.leading, tieInset)
            .padding(.bottom, tieLift)

            styledCard(
                kind: gym.kind,
                height: cardHeight,
                bottomRadius: nil,
                shadow: true,
                riseOrder: 2
            )
            .padding(.trailing, tieInset)
        }
        .frame(height: cardHeight + tieLift, alignment: .bottom)
    }

    // MARK: Cards

    private func height(for layer: ProgressLayer) -> CGFloat {
        max(unitHeight, CGFloat(layer.units) * unitHeight)
    }

    private func card(for layer: ProgressLayer) -> some View {
        styledCard(
            kind: layer.kind,
            height: height(for: layer) + overlap,
            bottomRadius: nil,
            // Cast upward, onto the card behind: that is where the overlap is,
            // and it is what separates one layer from the next.
            shadow: true,
            riseOrder: layer.kind.riseOrder
        )
    }

    /// One card in the shared chart style. `bottomRadius` of nil keeps every
    /// corner rounded; 0 squares the bottom off for a card that runs behind
    /// another.
    private func styledCard(
        kind: ProgressLayerKind,
        height: CGFloat,
        bottomRadius: CGFloat?,
        shadow: Bool,
        riseOrder: Int
    ) -> some View {
        let top = min(cornerRadius, height / 2)
        let bottom = bottomRadius ?? top
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )

        return shape
            .fill(kind.fill)
            .frame(height: height)
            .overlay {
                if let stroke = kind.stroke {
                    shape.strokeBorder(stroke, lineWidth: 1)
                }
            }
            .overlay(alignment: .top) {
                if kind.wantsTopHighlight {
                    shape
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        .blendMode(.plusLighter)
                }
            }
            .shadow(
                color: .black.opacity(shadow ? (kind == .ghost ? 0.03 : 0.16) : 0),
                radius: 3,
                y: -2
            )
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : riseDistance)
            .animation(animation(order: riseOrder), value: hasAppeared)
    }

    /// Cards glide up into place from just below the baseline.
    private var riseDistance: CGFloat { reduceMotion ? 0 : 22 }

    private func animation(order: Int) -> Animation {
        guard !reduceMotion else { return .easeOut(duration: 0.2) }
        return .spring(response: 0.42, dampingFraction: 0.82)
            .delay(baseDelay + Double(order) * 0.07)
    }
}

// MARK: - Legend

/// The four marks, named once at the foot of the card.
struct ProgressLegend: View {
    var body: some View {
        HStack(spacing: 0) {
            item(.gym, "Gym")
            item(.quick, "Quick 25")
            item(.ghost, "Planned")
            item(.missed, "Missed")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend. Black is a gym session, orange is a 25-minute workout, outlined is planned, grey is missed.")
    }

    private func item(_ kind: ProgressLayerKind, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(kind == .ghost ? Color.clear : kind.fill)
                .frame(width: 8, height: 8)
                .overlay {
                    if kind == .ghost {
                        Circle().strokeBorder(ProgressPalette.ghostStroke, lineWidth: 1.2)
                    }
                }

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Workout cards · layering cases") {
    let cases: [(gym: Int, quick: Int)] = [(3, 1), (1, 3), (1, 1), (2, 2), (3, 0), (0, 3)]
    HStack(alignment: .bottom, spacing: 12) {
        ForEach(Array(cases.enumerated()), id: \.offset) { _, pair in
            VStack(spacing: 8) {
                ProgressLayeredBar(
                    layers: [
                        pair.quick > 0 ? ProgressLayer(kind: .quick, units: pair.quick) : nil,
                        pair.gym > 0 ? ProgressLayer(kind: .gym, units: pair.gym) : nil,
                    ].compactMap { $0 },
                    unitHeight: 28,
                    hasAppeared: true,
                    reduceMotion: true
                )
                .frame(height: 130, alignment: .bottom)

                Text("\(pair.gym) / \(pair.quick)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    .padding(24)
    .background(Color.white)
}
#endif
