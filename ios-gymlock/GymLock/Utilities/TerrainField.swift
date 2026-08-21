import Foundation
import simd

/// A deterministic, analytic height field for one mountain.
///
/// The mountain is never stored and never randomised at runtime: every height
/// is a pure function of `(x, z)` and the expedition's seed, so the same
/// expedition produces byte-identical terrain on every launch, on every device.
/// That is what lets checkpoint world coordinates be trusted between sessions
/// without persisting a single vertex.
nonisolated struct TerrainField: Sendable {
    /// Derived from the expedition index — mountain 2 is a different mountain,
    /// not a re-roll of mountain 1.
    let seed: UInt32
    /// Distance from the summit axis at which the mountain has flattened out.
    let radius: Float
    /// Height of the summit above the base plane.
    let peak: Float

    init(expedition: Int, radius: Float = 62, peak: Float = 38) {
        // Mixed rather than used raw, so consecutive expeditions do not produce
        // visually related mountains.
        self.seed = UInt32(truncatingIfNeeded: (expedition &+ 1) &* 0x9E37_79B9)
        self.radius = radius
        self.peak = peak
    }

    // MARK: - Noise

    /// Integer hash → 0...1. Cheap, stable across architectures.
    private func hash(_ ix: Int32, _ iz: Int32) -> Float {
        var h = UInt32(bitPattern: ix) &* 0x1665_3609
        h = h &+ UInt32(bitPattern: iz) &* 0x27D4_EB2D
        h = h &+ seed &* 0x9E37_79B1
        h = (h ^ (h >> 15)) &* 0x85EB_CA6B
        h = (h ^ (h >> 13)) &* 0xC2B2_AE35
        h = h ^ (h >> 16)
        return Float(h) * (1.0 / Float(UInt32.max))
    }

    /// Smooth value noise on a unit lattice.
    private func valueNoise(_ x: Float, _ z: Float) -> Float {
        let x0 = floor(x)
        let z0 = floor(z)
        let fx = x - x0
        let fz = z - z0
        // Quintic fade — smoother second derivative than smoothstep, which
        // matters because normals are derived from this field.
        let ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
        let uz = fz * fz * fz * (fz * (fz * 6 - 15) + 10)

        let ix = Int32(x0)
        let iz = Int32(z0)
        let n00 = hash(ix, iz)
        let n10 = hash(ix &+ 1, iz)
        let n01 = hash(ix, iz &+ 1)
        let n11 = hash(ix &+ 1, iz &+ 1)

        let a = n00 + (n10 - n00) * ux
        let b = n01 + (n11 - n01) * ux
        return a + (b - a) * uz
    }

    /// Fractal sum, returning 0...1.
    private func fbm(_ x: Float, _ z: Float, octaves: Int) -> Float {
        var total: Float = 0
        var amplitude: Float = 1
        var frequency: Float = 1
        var normalisation: Float = 0

        for _ in 0..<octaves {
            total += valueNoise(x * frequency, z * frequency) * amplitude
            normalisation += amplitude
            amplitude *= 0.5
            frequency *= 2.03
        }
        return total / max(normalisation, 0.0001)
    }

    /// Sharp-crested ridge noise — this is what gives the mountain its spines
    /// rather than the blobby look of plain fractal noise.
    private func ridged(_ x: Float, _ z: Float, octaves: Int) -> Float {
        var total: Float = 0
        var amplitude: Float = 1
        var frequency: Float = 1
        var normalisation: Float = 0

        for _ in 0..<octaves {
            let n = valueNoise(x * frequency, z * frequency)
            let ridge = 1 - abs(n * 2 - 1)
            total += ridge * ridge * amplitude
            normalisation += amplitude
            amplitude *= 0.52
            frequency *= 2.11
        }
        return total / max(normalisation, 0.0001)
    }

    // MARK: - Height

    /// Terrain height at a point, in the mountain's local space.
    func height(_ x: Float, _ z: Float) -> Float {
        // Warping the lookup breaks the radial symmetry, so the summit does not
        // sit in the middle of a perfect cone.
        let warp = (fbm(x * 0.012 + 11.3, z * 0.012 - 4.7, octaves: 2) - 0.5) * 12
        let wx = x + warp
        let wz = z + warp * 0.7

        let distance = sqrt(wx * wx + wz * wz) / radius
        // A bell rather than a cone: rounded summit, skirts that settle into the
        // plain instead of ending in a hard edge.
        let massif = exp(-pow(distance * 1.28, 2.05))

        let spines = ridged(wx * 0.031, wz * 0.031, octaves: 4)
        let detail = fbm(wx * 0.11, wz * 0.11, octaves: 3)
        let foothills = fbm(wx * 0.019 - 30, wz * 0.019 + 18, octaves: 3)

        var h = peak * massif * 0.74
        h += peak * massif * spines * 0.40
        h += peak * massif * (detail - 0.5) * 0.07
        // Low rolling ground that keeps the horizon from being a flat plate.
        h += peak * 0.085 * foothills * (1 - min(massif * 1.6, 1))

        return h
    }

    /// Surface normal, from central differences on the height field.
    func normal(_ x: Float, _ z: Float, step: Float = 0.6) -> SIMD3<Float> {
        let hL = height(x - step, z)
        let hR = height(x + step, z)
        let hD = height(x, z - step)
        let hU = height(x, z + step)
        return normalize(SIMD3<Float>(hL - hR, 2 * step, hD - hU))
    }

    /// 0 at flat ground, 1 at a vertical face. Feeds the terrain ramp's U axis.
    func steepness(_ x: Float, _ z: Float) -> Float {
        min(max(1 - normal(x, z).y, 0), 1) * 1.9
    }

    /// Summit height, used to normalise altitude into the 0...1 the ramp wants.
    var summitHeight: Float { peak * 1.14 }

    /// The point at the very top, for the goal flag.
    func summit() -> SIMD3<Float> {
        // Walk a coarse grid near the middle and refine — cheaper and more
        // robust than trying to invert the warp analytically.
        var best = SIMD3<Float>(0, height(0, 0), 0)
        var span: Float = radius * 0.32
        var centre = SIMD2<Float>(0, 0)

        for _ in 0..<4 {
            let steps = 6
            for i in 0...steps {
                for j in 0...steps {
                    let x = centre.x - span + (2 * span) * Float(i) / Float(steps)
                    let z = centre.y - span + (2 * span) * Float(j) / Float(steps)
                    let h = height(x, z)
                    if h > best.y { best = SIMD3<Float>(x, h, z) }
                }
            }
            centre = SIMD2<Float>(best.x, best.z)
            span *= 0.34
        }
        return best
    }
}

/// The climbing route: a switchback trail that is generated once from the
/// terrain and then sampled by everything else.
///
/// Control points are laid out in polar coordinates on the mountain's *front*
/// face so the route stays visible from the hero angle, alternating direction
/// on the way up the way a real hiking path does. Height is never authored —
/// it is always read from the terrain, which is what keeps the trail welded to
/// the surface instead of floating over it.
nonisolated struct MountainRoute: Sendable {
    /// Densely sampled centre line, in the mountain's local space.
    let points: [SIMD3<Float>]
    /// Cumulative arc length at each sample, normalised to 0...1.
    let arc: [Float]

    private let field: TerrainField

    /// Angle (degrees) and radius fraction of each switchback turn.
    ///
    /// The angles stay inside roughly -145°...+45° so the path never
    /// disappears round the back of the peak, and the radius decreases
    /// monotonically so the climb never doubles back downhill.
    private static let controls: [(angle: Float, radius: Float)] = [
        (-118, 1.02), (-92, 0.94), (-46, 0.86), (2, 0.79),
        (38, 0.70), (6, 0.61), (-42, 0.55), (-86, 0.47),
        (-108, 0.39), (-64, 0.32), (-14, 0.26), (26, 0.20),
        (2, 0.13), (-26, 0.07), (-6, 0.015),
    ]

    init(field: TerrainField, sampleCount: Int = 420, lift: Float = 0.34) {
        self.field = field

        // Catmull-Rom through the polar controls, evaluated in polar space so
        // the turns come out as arcs rather than as chords across the slope.
        var polar: [SIMD2<Float>] = Self.controls.map {
            SIMD2<Float>($0.angle * .pi / 180, $0.radius * field.radius)
        }
        // Duplicate the ends so the spline reaches its first and last control.
        polar.insert(polar[0], at: 0)
        polar.append(polar[polar.count - 1])

        var raw: [SIMD3<Float>] = []
        raw.reserveCapacity(sampleCount)

        let segments = polar.count - 3
        for index in 0..<sampleCount {
            let global = Float(index) / Float(sampleCount - 1) * Float(segments)
            let segment = min(Int(global), segments - 1)
            let t = global - Float(segment)

            let p0 = polar[segment]
            let p1 = polar[segment + 1]
            let p2 = polar[segment + 2]
            let p3 = polar[segment + 3]
            let value = Self.catmullRom(p0, p1, p2, p3, t)

            let angle = value.x
            let radius = max(value.y, 0)
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            raw.append(SIMD3<Float>(x, field.height(x, z) + lift, z))
        }

        points = raw

        var lengths: [Float] = [0]
        lengths.reserveCapacity(raw.count)
        var total: Float = 0
        for index in 1..<raw.count {
            total += distance(raw[index], raw[index - 1])
            lengths.append(total)
        }
        arc = total > 0 ? lengths.map { $0 / total } : lengths
    }

    private static func catmullRom(
        _ p0: SIMD2<Float>,
        _ p1: SIMD2<Float>,
        _ p2: SIMD2<Float>,
        _ p3: SIMD2<Float>,
        _ t: Float
    ) -> SIMD2<Float> {
        // Written out term by term: as a single expression the type checker
        // struggles with the mix of SIMD2 and scalar operands.
        let t2: Float = t * t
        let t3: Float = t2 * t

        let a: SIMD2<Float> = p1 * 2
        let b: SIMD2<Float> = (p2 - p0) * t

        var c: SIMD2<Float> = p0 * 2
        c -= p1 * 5
        c += p2 * 4
        c -= p3
        c *= t2

        var d: SIMD2<Float> = p1 * 3
        d -= p0
        d -= p2 * 3
        d += p3
        d *= t3

        return (a + b + c + d) * 0.5
    }

    /// Index of the sample closest to a normalised arc position.
    private func index(at t: Float) -> Int {
        let clamped = min(max(t, 0), 1)
        // Arc lengths are monotonic, so a binary search is exact and cheap.
        var low = 0
        var high = arc.count - 1
        while low < high {
            let mid = (low + high) / 2
            if arc[mid] < clamped { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Position along the route by *distance travelled*, not by control index,
    /// so weekly checkpoints are evenly spaced along the ground.
    func point(at t: Float) -> SIMD3<Float> {
        points[index(at: t)]
    }

    /// Unit direction of travel at a position.
    func tangent(at t: Float) -> SIMD3<Float> {
        let i = index(at: t)
        let a = points[max(i - 1, 0)]
        let b = points[min(i + 1, points.count - 1)]
        let delta = b - a
        return length(delta) > 0.0001 ? normalize(delta) : SIMD3<Float>(0, 0, -1)
    }

    /// Terrain normal beneath a route position.
    func surfaceNormal(at t: Float) -> SIMD3<Float> {
        let p = point(at: t)
        return field.normal(p.x, p.z)
    }
}
