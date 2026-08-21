import SwiftUI
import UIKit

// MARK: - Screen capture

/// Grabs the pixels currently on screen as a single image.
///
/// The shatter needs something solid to break. Re-rendering the loop scene into
/// forty-odd fragments would mean mounting its seven illustrations forty-odd
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

/// One piece of broken glass, and the throw that carries it off screen.
///
/// Every piece is a projectile: it leaves with a velocity and is then pulled
/// down by gravity, so its path is a genuine arc — up, over, and down. Nothing
/// here interpolates towards a destination, which is what separates thrown glass
/// from a dissolve.
private struct GlassShard {
    let path: Path
    let centroid: CGPoint
    /// Initial velocity in points per unit of flight. Negative `dy` is upward,
    /// and for almost every piece it is: the swipe threw the screen up.
    let launch: CGVector
    /// Downward acceleration in points per unit of flight squared.
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

    /// Where the piece is, relative to where it broke off.
    ///
    /// Horizontal travel is linear — there is nothing to slow a piece down
    /// sideways — while vertical travel is the ballistic `vt + ½gt²`. That single
    /// term is what makes the glass rise, hang, and then fall.
    func offset(at flight: Double) -> CGVector {
        let t = CGFloat(flight)
        return CGVector(
            dx: launch.dx * t,
            dy: launch.dy * t + 0.5 * gravity * t * t
        )
    }

    /// Pieces stay solid through the rise and the hang, and only thin out once
    /// they are falling — fading on the way up would kill the throw.
    func opacity(at flight: Double) -> Double {
        guard flight > 0.60 else { return 1 }
        return 1 - Double(smoothstep(CGFloat((flight - 0.60) / 0.40)))
    }

    /// The bright edge of a fresh break: a hard flash the moment the crack
    /// reaches this piece, gone by the time it is airborne. Because the pieces
    /// let go from the bottom upwards, these flashes read as a crack running up
    /// the screen.
    func edgeAlpha(at flight: Double) -> Double {
        let rise = Double(smoothstep(CGFloat(flight / 0.08)))
        let fall = 1 - Double(smoothstep(CGFloat((flight - 0.09) / 0.30)))
        return 0.95 * rise * fall
    }

    /// A radial fracture struck from the bottom of the screen — where the thumb
    /// just was — so the spokes fan upwards and the whole pattern reads as force
    /// arriving from below.
    static func field(in size: CGSize) -> [GlassShard] {
        guard size.width > 1, size.height > 1 else { return [] }

        var rng = SeededRandom(seed: 0x5EED_C0DE)

        // The point of impact sits low and slightly off centre, right about
        // where the swipe started. Everything above it is being thrown.
        let origin = CGPoint(x: size.width * 0.47, y: size.height * 0.88)

        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ]
        let maxRadius = corners
            .map { hypot($0.x - origin.x, $0.y - origin.y) }
            .max()! * 1.06

        let spokeCount = 11
        let ringFractions: [CGFloat] = [0, 0.13, 0.32, 0.58, 1.0]

        var angles: [Double] = (0..<spokeCount).map { index in
            Double(index) / Double(spokeCount) * 2 * .pi + rng.range(-0.15, 0.15)
        }
        angles.append(angles[0] + 2 * .pi)

        // Radius jitter per spoke, so the rings are ragged rather than circular.
        var radii: [[CGFloat]] = (0..<spokeCount).map { _ in
            ringFractions.enumerated().map { ringIndex, fraction in
                guard fraction > 0 else { return 0 }
                // The outermost ring may only bulge outwards, never inwards, or
                // the far corners would be left uncovered by any shard at all
                // and the screen would appear to have holes in it before it
                // even broke.
                let isOutermost = ringIndex == ringFractions.count - 1
                let jitter = isOutermost ? rng.range(1.0, 1.22) : rng.range(0.82, 1.18)
                return maxRadius * fraction * CGFloat(jitter)
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

                let vertices: [CGPoint] = ring == 0
                    ? [origin, outerB, outerA]
                    : [innerA, innerB, outerB, outerA]

                var path = Path()
                path.move(to: vertices[0])
                for vertex in vertices.dropFirst() { path.addLine(to: vertex) }
                path.closeSubpath()

                let centroid = CGPoint(
                    x: vertices.map(\.x).reduce(0, +) / CGFloat(vertices.count),
                    y: vertices.map(\.y).reduce(0, +) / CGFloat(vertices.count)
                )

                let offset = CGVector(dx: centroid.x - origin.x, dy: centroid.y - origin.y)
                let length = max(1, hypot(offset.dx, offset.dy))
                let direction = CGVector(dx: offset.dx / length, dy: offset.dy / length)
                let spread = min(1, length / maxRadius)

                // The crack runs outwards from the impact, which — with the
                // impact at the bottom — means it runs up the screen. Pieces at
                // the top are the last to let go.
                let delay = min(0.10 + Double(spread) * 0.20 + rng.range(0, 0.035), 0.33)
                let span = 1 - delay

                // Two forces on every piece. The punch shoves it away from the
                // impact, and the throw sends it up. Both fall off with distance,
                // so the far corners mostly just lose their grip and drop.
                let punch = rng.range(80, 200) * (1.25 - 0.60 * Double(spread))
                let throwUp = rng.range(820, 1180) * (1.20 - 0.50 * Double(spread))

                // Velocities are expressed per unit of *this shard's* flight, so
                // a piece that leaves late has to be scaled down to keep moving
                // at the same real-world speed as one that left early.
                // Acceleration scales with the square, for the same reason.
                let launch = CGVector(
                    dx: CGFloat(direction.dx * punch * span),
                    dy: CGFloat((direction.dy * punch - throwUp) * span)
                )

                shards.append(
                    GlassShard(
                        path: path,
                        centroid: centroid,
                        launch: launch,
                        gravity: CGFloat(rng.range(3800, 4600) * span * span),
                        spin: rng.range(-1.15, 1.15),
                        delay: delay
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

/// Breaks a captured screen upwards, then lets the pieces fall.
///
/// The sequence is deliberate and in three beats:
///
/// 1. **The heave.** For the first fraction of the animation nothing fractures —
///    the whole pane simply lifts, as one piece, in the direction of the swipe.
///    This is the wind-up, and it is what makes the break read as *caused* by
///    the gesture rather than as an effect that happened to play afterwards.
/// 2. **The break.** The pane fails at the point of impact near the bottom and
///    the crack runs upward, each piece flashing white along its edges as it
///    lets go. Pieces are thrown up and outward.
/// 3. **The fall.** Gravity wins. Every piece arcs over and rains down, tumbling
///    and fading as it goes.
///
/// The view is `Animatable` on `progress`, so its body — and therefore the
/// `Canvas` — is re-evaluated every frame. Each shard is drawn by transforming
/// the context, clipping it to the shard outline and then painting the *whole*
/// snapshot through that clip. Because the clip and the image move together,
/// every piece carries the exact pixels that were under it, which is what makes
/// the screen look like it broke rather than like an explosion was pasted over
/// it.
///
/// At `progress == 0` the pieces sit in their original positions with no visible
/// seams, so the overlay can be mounted before anything moves without the user
/// ever seeing a cracked screen appear out of nowhere.
struct GlassShatterView: View, Animatable {
    private let image: Image
    private let canvasSize: CGSize
    private let shards: [GlassShard]

    var progress: Double

    /// How far the intact pane rides up on the swipe before it fails.
    private static let heaveLift: CGFloat = 18
    /// Fraction of the animation spent heaving, before the first crack.
    private static let heaveWindow: Double = 0.10

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

    /// The unified lift, applied to every piece whether or not it has broken off
    /// yet. It saturates rather than springing back: the pane goes up and stays
    /// up, and each shard's own throw is added on top of it.
    private var heave: CGFloat {
        -Self.heaveLift * smoothstep(CGFloat(progress / Self.heaveWindow))
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let resolved = context.resolve(image)
            let full = CGRect(origin: .zero, size: size)
            let lift = heave

            for shard in shards {
                let flight = shard.flight(at: progress)
                let opacity = shard.opacity(at: flight)
                guard opacity > 0.01 else { continue }

                let travel = shard.offset(at: flight)
                let scale = 1 - 0.12 * CGFloat(flight)

                var placed = context
                placed.opacity = opacity
                placed.translateBy(x: travel.dx, y: travel.dy + lift)

                // Tumble and recede about the piece's own centre, so it rotates
                // like a rigid body instead of swinging around the screen. The
                // spin eases in: a piece barely turns while it is still part of
                // the pane, and tumbles freely once it is falling.
                let turn = shard.spin * flight * (0.35 + 0.65 * flight)
                placed.translateBy(x: shard.centroid.x, y: shard.centroid.y)
                placed.rotate(by: .radians(turn))
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
