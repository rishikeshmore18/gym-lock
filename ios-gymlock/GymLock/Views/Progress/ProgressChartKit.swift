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
    /// The 20-minute home fallback. Never black — it kept the commitment, but
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
        VStack(spacing: -overlap) {
            ForEach(layers) { layer in
                card(for: layer)
            }
        }
    }

    private func card(for layer: ProgressLayer) -> some View {
        let height = max(unitHeight, CGFloat(layer.units) * unitHeight) + overlap

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(layer.kind.fill)
            .frame(height: height)
            .overlay {
                if let stroke = layer.kind.stroke {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                }
            }
            .overlay(alignment: .top) {
                if layer.kind.wantsTopHighlight {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        .blendMode(.plusLighter)
                }
            }
            // Cast upward, onto the card behind: that is where the overlap is,
            // and it is what separates one layer from the next.
            .shadow(color: .black.opacity(layer.kind == .ghost ? 0.03 : 0.14), radius: 3, y: -2)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : riseDistance)
            .animation(animation(for: layer), value: hasAppeared)
    }

    /// Cards glide up into place from just below the baseline.
    private var riseDistance: CGFloat { reduceMotion ? 0 : 22 }

    private func animation(for layer: ProgressLayer) -> Animation {
        guard !reduceMotion else { return .easeOut(duration: 0.2) }
        return .spring(response: 0.42, dampingFraction: 0.82)
            .delay(baseDelay + Double(layer.kind.riseOrder) * 0.07)
    }
}

// MARK: - Legend

/// The four marks, named once at the foot of the card.
struct ProgressLegend: View {
    var body: some View {
        HStack(spacing: 0) {
            item(.gym, "Gym")
            item(.quick, "Quick 20")
            item(.ghost, "Planned")
            item(.missed, "Missed")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend. Black is a gym session, orange is a 20-minute workout, outlined is planned, grey is missed.")
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
