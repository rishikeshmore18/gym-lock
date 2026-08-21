import SwiftUI
import UIKit

// MARK: - Screen capture

/// Grabs the pixels currently on screen as a single image.
///
/// The shatter needs something solid to break. Re-rendering the loop scene into
/// thirty-odd fragments would mean mounting its seven illustrations thirty-odd
/// times, so instead the screen is photographed once at the instant of the swipe
/// and the *photograph* is what comes apart. One bitmap, many pieces.
enum ScreenSnapshot {
    @MainActor
    static func capture() -> UIImage? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first,
              window.bounds.width > 1,
              window.bounds.height > 1
        else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            // `afterScreenUpdates: false` captures the frame the user is looking
            // at right now, which is the one that has to appear to break.
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}

// MARK: - Deterministic randomness

/// A tiny seeded generator, so the fracture pattern is irregular but identical
/// every run — a shatter that reshuffles itself between launches feels synthetic.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF)
    }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit()
    }
}

// MARK: - Shards

/// One piece of broken glass: its outline, and how it leaves the screen.
private struct GlassShard {
    let path: Path
    let centroid: CGPoint
    /// Unit vector away from the point of impact.
    let direction: CGVector
    let outwardSpeed: CGFloat
    let gravity: CGFloat
    /// Radians of tumble across the shard's whole flight.
    let spin: Double
    /// Fraction of the animation this shard waits before it lets go.
    let delay: Double

    /// This shard's own 0...1 flight, offset by its delay.
    func flight(at progress: Double) -> Double {
        let span = max(0.0001, 1 - delay)
        return min(max((progress - delay) / span, 0), 1)
    }

    /// Pieces stay solid for the first half, then fade as they fall away.
    func opacity(at flight: Double) -> Double {
        guard flight > 0.5 else { return 1 }
        return 1 - Double(smoothstep(CGFloat((flight - 0.5) / 0.5)))
    }

    /// The bright edge of a fresh break: a hard flash the moment the crack
    /// appears, gone by the time the piece is airborne.
    func edgeAlpha(at flight: Double) -> Double {
        let rise = Double(smoothstep(CGFloat(flight / 0.09)))
        let fall = 1 - Double(smoothstep(CGFloat((flight - 0.10) / 0.34)))
        return 0.9 * rise * fall
    }

    /// A radial fracture: spokes out from a point of impact, crossed by rings,
    /// with every vertex jittered so no two pieces match.
    static func field(in size: CGSize) -> [GlassShard] {
        guard size.width > 1, size.height > 1 else { return [] }

        var rng = SeededRandom(seed: 0x5EED_C0DE)

        // Impact lands on the artwork, not dead centre — an off-centre origin
        // reads as something that was hit rather than something that dissolved.
        let origin = CGPoint(x: size.width * 0.5, y: size.height * 0.46)

        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ]
        let maxRadius = corners
            .map { hypot($0.x - origin.x, $0.y - origin.y) }
            .max()! * 1.08

        let spokeCount = 9
        let ringFractions: [CGFloat] = [0, 0.17, 0.38, 0.64, 1.0]

        var angles: [Double] = (0..<spokeCount).map { index in
            Double(index) / Double(spokeCount) * 2 * .pi + rng.range(-0.17, 0.17)
        }
        angles.append(angles[0] + 2 * .pi)

        // Radius jitter per spoke, so the rings are ragged rather than circular.
        var radii: [[CGFloat]] = (0..<spokeCount).map { _ in
            ringFractions.map { fraction in
                fraction == 0 ? 0 : maxRadius * fraction * CGFloat(rng.range(0.84, 1.18))
            }
        }
        radii.append(radii[0]) // close the wrap seam cleanly

        var shards: [GlassShard] = []

        for spoke in 0..<spokeCount {
            for ring in 0..<(ringFractions.count - 1) {
                let angleA = angles[spoke]
                let angleB = angles[spoke + 1]

                let innerA = point(from: origin, angle: angleA, radius: radii[spoke][ring])
                let innerB = point(from: origin, angle: angleB, radius: radii[spoke + 1][ring])
                let outerB = point(from: origin, angle: angleB, radius: radii[spoke + 1][ring + 1])
                let outerA = point(from: origin, angle: angleA, radius: radii[spoke][ring + 1])

                var path = Path()
                var vertices: [CGPoint] = []

                if ring == 0 {
                    vertices = [origin, outerB, outerA]
                } else {
                    vertices = [innerA, innerB, outerB, outerA]
                }

                path.move(to: vertices[0])
                for vertex in vertices.dropFirst() { path.addLine(to: vertex) }
                path.closeSubpath()

                let centroid = CGPoint(
                    x: vertices.map(\.x).reduce(0, +) / CGFloat(vertices.count),
                    y: vertices.map(\.y).reduce(0, +) / CGFloat(vertices.count)
                )

                let offset = CGVector(dx: centroid.x - origin.x, dy: centroid.y - origin.y)
                let length = max(1, hypot(offset.dx, offset.dy))
                let normalised = CGVector(dx: offset.dx / length, dy: offset.dy / length)
                let spread = min(1, length / maxRadius)

                // Pieces near the impact are thrown hardest; the outer field
                // mostly just loses its grip and drops.
                let outward = rng.range(70, 180) * (1.3 - 0.7 * Double(spread))

                // The bottom band holds a beat longer, so the line the user just
                // earned survives for a moment while the rest of the screen goes.
                let holdsBottom = centroid.y > size.height * 0.80
                let delay = Double(spread) * 0.20
                    + rng.range(0, 0.05)
                    + (holdsBottom ? 0.17 : 0)

                shards.append(
                    GlassShard(
                        path: path,
                        centroid: centroid,
                        direction: normalised,
                        outwardSpeed: CGFloat(outward),
                        gravity: CGFloat(rng.range(700, 1080)),
                        spin: rng.range(-0.6, 0.6),
                        delay: min(delay, 0.42)
                    )
                )
            }
        }

        return shards
    }

    private static func point(from origin: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + radius * CGFloat(cos(angle)),
            y: origin.y + radius * CGFloat(sin(angle))
        )
    }
}

// MARK: - The break

/// Breaks a captured screen into falling glass.
///
/// The view is `Animatable` on `progress`, so its body — and therefore the
/// `Canvas` — is re-evaluated every frame of the animation. Each shard is drawn
/// by transforming the context, clipping it to the shard outline and then
/// painting the *whole* snapshot through that clip. Because the clip and the
/// image move together, every piece carries the exact pixels that were under it,
/// which is what makes the screen look like it broke rather than like an
/// explosion was pasted over it.
///
/// At `progress == 0` the pieces sit in their original positions with no visible
/// seams, so the overlay can be mounted before anything moves without the user
/// ever seeing a cracked screen appear out of nowhere.
struct GlassShatterView: View, Animatable {
    private let image: Image
    private let canvasSize: CGSize
    private let shards: [GlassShard]

    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    init(image: Image, size: CGSize, progress: Double) {
        self.image = image
        self.canvasSize = size
        self.progress = progress
        self.shards = GlassShard.field(in: size)
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let resolved = context.resolve(image)
            let full = CGRect(origin: .zero, size: size)

            for shard in shards {
                let flight = shard.flight(at: progress)
                let opacity = shard.opacity(at: flight)
                guard opacity > 0.01 else { continue }

                // Motion is quadratic in time: a piece barely creeps as the crack
                // opens, then accelerates. Linear travel reads as a slide.
                let travel = CGFloat(flight * flight)
                let scale = 1 - 0.14 * CGFloat(flight)

                var placed = context
                placed.opacity = opacity
                placed.translateBy(
                    x: shard.direction.dx * shard.outwardSpeed * travel,
                    y: shard.direction.dy * shard.outwardSpeed * travel + shard.gravity * travel
                )

                // Tumble and recede about the piece's own centre, so it rotates
                // like a rigid body instead of swinging around the screen.
                placed.translateBy(x: shard.centroid.x, y: shard.centroid.y)
                placed.rotate(by: .radians(shard.spin * flight))
                placed.scaleBy(x: scale, y: scale)
                placed.translateBy(x: -shard.centroid.x, y: -shard.centroid.y)

                var pane = placed
                pane.clip(to: shard.path)
                pane.draw(resolved, in: full)

                let edge = shard.edgeAlpha(at: flight)
                if edge > 0.01 {
                    placed.stroke(
                        shard.path,
                        with: .color(Theme.ink.opacity(edge * 0.22)),
                        lineWidth: 1.6
                    )
                    placed.stroke(
                        shard.path,
                        with: .color(.white.opacity(edge)),
                        lineWidth: 0.8
                    )
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
