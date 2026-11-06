//
//  MatrixEngine.swift
//  GymLock · Matrix hero (native port)
//
//  Exact port of web/hero13/mdots.ts (class MDots): the particle board behind the Matrix hero card
//  and the full-screen done flow.
//
//  What it does (same as the web):
//    - A fixed pool of `n` particles. Every frame the scene hands it a list of targets
//      (MatrixTarget: x, y in grid cells, brightness b, coral flag c, identity id).
//    - A target keeps its particle by IDENTITY (`id`), so a growing shape does not reshuffle every
//      later dot: new cells light in place like an LED, moving things keep their own dot.
//    - When the `key` changes (a new state, day or scene phase) every particle is re-dealt by angle
//      around the targets' centroid, with a stagger, so the dots swirl to the next form.
//    - Fixed-step spring physics at 1/120 s substeps (stiffness 210, damping 21), so 60 Hz and
//      120 Hz displays integrate identically (60 Hz = two substeps, 120 Hz = one).
//    - Brightness eases toward the target (0.3 when active, 0.42 toward 0 when released).
//    - Optional pointer repel (finger drag), radius 4.5 cells.
//
//  Parity rules (read PORTING-GUIDE.md):
//    - Particle state is stored as Float (the web uses Float32Array). Every web assignment rounds to
//      float32, so every store here is `Float(<double expression>)`, computed in Double from the
//      Float-widened inputs, in the SAME operation order as the TypeScript.
//    - Comparisons against literals are done in Double (`Double(b[i]) > 0.04`), never Float, or a
//      threshold like 0.04 rounds differently and a particle flips buckets.
//    - The deterministic hash is bit-identical to the TS hash (32-bit wrapping math).
//    - Sorts are made stable with an index tie-break (JS Array.prototype.sort is stable).
//
//  Deliberate, documented deviation:
//    - `brightnessMode = .timeBased` (default) converts the per-frame easing constants to the same
//      curve per second, measured against a 60 Hz reference frame. The web eases per *frame*, so it
//      fades twice as fast on a 120 Hz display. `.timeBased` makes 60 Hz and 120 Hz iPhones look the
//      same and equal to the web at 60 fps. Use `.perFrame` for bit-exact parity tests.
//
//  Threading: plain final class, not Sendable. Create, update and draw it on the main thread only
//  (it lives inside the view's runtime object and is stepped from the Canvas renderer).
//
//  Depends on: SwiftUI (Path, GraphicsContext, Color) only.
//

import SwiftUI

// MARK: - JS numeric parity helpers

/// The handful of JavaScript numeric semantics the prototype relies on, reproduced exactly.
/// Use these in every ported scene instead of the Swift look-alikes (see PORTING-GUIDE.md §3).
public enum JSMath {
    private static let two32: Double = 4_294_967_296.0

    /// ECMAScript `ToInt32` (what `x | 0` does): truncate toward zero, wrap modulo 2^32.
    /// NaN and ±Infinity give 0, like JS.
    @inline(__always)
    public static func toInt32(_ v: Double) -> Int32 {
        guard v.isFinite else { return 0 }
        var m = v.rounded(.towardZero).truncatingRemainder(dividingBy: two32)
        if m < 0 { m += two32 }
        return Int32(bitPattern: UInt32(m))
    }

    /// ECMAScript `ToUint32` (what `x >>> 0` does).
    @inline(__always)
    public static func toUint32(_ v: Double) -> UInt32 {
        UInt32(bitPattern: toInt32(v))
    }

    /// `Math.round`: halves round UP (toward +infinity). `Math.round(-2.5) == -2`, while Swift's
    /// `(-2.5).rounded()` is -3. Every `Math.round` in a scene must use this.
    @inline(__always)
    public static func round(_ x: Double) -> Double {
        let f = x.rounded(.down)
        return x - f >= 0.5 ? f + 1 : f
    }

    /// `Math.imul`: low 32 bits of the product.
    @inline(__always)
    public static func imul(_ a: UInt32, _ b: UInt32) -> UInt32 { a &* b }

    /// JS `a % b` on numbers: the result has the sign of the dividend. Same as truncatingRemainder.
    @inline(__always)
    public static func rem(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }
}

// MARK: - Deterministic hash

public enum MatrixHash {
    /// mdots.ts `hash(i, k)`:
    /// ```ts
    /// let h = (i * 374761393 + k * 668265263) | 0;
    /// h = Math.imul(h ^ (h >>> 13), 1274126177);
    /// return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
    /// ```
    /// The sum is formed in Double first (as in JS) and then wrapped with ToInt32, so non-integer and
    /// negative inputs match too. Returns a value in [0, 1).
    @inline(__always)
    public static func hash(_ i: Double, _ k: Double) -> Double {
        var h = JSMath.toUint32(i * 374_761_393 + k * 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double(h ^ (h >> 16)) / 4_294_967_296.0
    }

    @inline(__always)
    public static func hash(_ i: Int, _ k: Int) -> Double { hash(Double(i), Double(k)) }
}

// MARK: - Targets and deal options

/// One lit target for one frame. Coordinates are in grid cells (cell centres are at n + 0.5).
public struct MatrixTarget: Equatable, Sendable {
    public var x: Double
    public var y: Double
    /// Brightness 0...1.
    public var b: Double
    /// 1 = coral (the single accent dot), 0 = ink.
    public var c: UInt8
    /// Identity. Snapped cells: `iy * 256 + ix`. Free particles: `1_000_000 + push index`.
    public var id: Int

    public init(x: Double, y: Double, b: Double, c: UInt8 = 0, id: Int) {
        self.x = x; self.y = y; self.b = b; self.c = c; self.id = id
    }
}

/// hero4/dots.ts `Opts` as used by mdots: how the dots fly when the key changes.
public struct MatrixDealOptions: Equatable, Sendable {
    /// Seconds over which the deal is staggered. `nil` means the engine default (0.18).
    public var stagger: Double?
    /// When non-zero, dealt dots are first thrown into a square of this size around the centroid.
    public var scatter: Double
    /// When non-zero, dealt dots get a random kick of this speed (cells / s).
    public var burst: Double

    public init(stagger: Double? = nil, scatter: Double = 0, burst: Double = 0) {
        self.stagger = stagger
        self.scatter = scatter
        self.burst = burst
    }
}

// MARK: - Engine

public final class MatrixEngine {
    public enum BrightnessMode: Sendable {
        /// Web-exact: k = 0.3 / 0.42 per update call. Frame-rate dependent. Use for parity tests.
        case perFrame
        /// Same curve per second as the web at 60 fps: k = 1 - (1 - 0.3)^(dt * 60).
        case timeBased
    }

    public let n: Int
    public private(set) var x: ContiguousArray<Float>
    public private(set) var y: ContiguousArray<Float>
    public private(set) var vx: ContiguousArray<Float>
    public private(set) var vy: ContiguousArray<Float>
    public private(set) var b: ContiguousArray<Float>
    public private(set) var c: ContiguousArray<UInt8>
    private var tx: ContiguousArray<Float>
    private var ty: ContiguousArray<Float>
    private var tb: ContiguousArray<Float>
    private var act: ContiguousArray<UInt8>
    /// Float like the web's Float32Array. Keep the caller's `t` small (seconds since the view's
    /// epoch) so float32 keeps sub-millisecond precision (see MatrixCardView runtime).
    private var start: ContiguousArray<Float>
    private var idOf: [Int: Int] = [:]
    public private(set) var key: String = ""
    private var last: Double = -1

    /// Pointer position in grid cells, or nil. Particles within 4.5 cells are pushed away.
    public var pointer: SIMD2<Double>?
    public var stiff: Double = 210
    public var damp: Double = 21
    public var brightnessMode: BrightnessMode = .timeBased

    // per-frame scratch, kept to avoid allocations at 120 Hz
    private var used: ContiguousArray<UInt8>
    private var seen = Set<Int>()
    private var gone: [Int] = []

    /// `new MDots(n, cols, rows)`: particles start scattered over the board by the hash.
    public init(n: Int, cols: Int, rows: Int) {
        precondition(n > 0, "MatrixEngine needs at least one particle")
        self.n = n
        let zf = ContiguousArray<Float>(repeating: 0, count: n)
        let zb = ContiguousArray<UInt8>(repeating: 0, count: n)
        x = zf; y = zf; vx = zf; vy = zf; b = zf
        tx = zf; ty = zf; tb = zf; start = zf
        c = zb; act = zb; used = zb
        seen.reserveCapacity(n)
        idOf.reserveCapacity(n)
        for i in 0..<n {
            x[i] = Float(MatrixHash.hash(i, 1) * Double(cols))
            y[i] = Float(MatrixHash.hash(i, 2) * Double(rows))
        }
    }

    // MARK: deal

    /// mdots.ts `deal`: assign particles to the new target list by angle around the centroid.
    private func deal(_ T: ContiguousArray<MatrixTarget>, t: Double, o: MatrixDealOptions) {
        let L = min(T.count, n)
        var cx = 0.0, cy = 0.0
        for j in 0..<L {
            cx += T[j].x
            cy += T[j].y
        }
        // `cx /= L || 1`
        let div = L == 0 ? 1.0 : Double(L)
        cx /= div
        cy /= div

        // prefer particles already on screen, then idle ones (both in index order)
        var vis: [Int] = []
        var idle: [Int] = []
        vis.reserveCapacity(n)
        idle.reserveCapacity(n)
        for i in 0..<n {
            if Double(b[i]) > 0.04 { vis.append(i) } else { idle.append(i) }
        }
        var chosen = Array(vis.prefix(L))
        var k = 0
        while chosen.count < L && k < idle.count {
            chosen.append(idle[k])
            k += 1
        }

        // JS sort is stable: ties keep their original order, so break ties by original position.
        var tKeyed: [(a: Double, j: Int)] = []
        tKeyed.reserveCapacity(L)
        for j in 0..<L { tKeyed.append((atan2(T[j].y - cy, T[j].x - cx), j)) }
        tKeyed.sort { $0.a != $1.a ? $0.a < $1.a : $0.j < $1.j }

        var pKeyed: [(a: Double, pos: Int, p: Int)] = []
        pKeyed.reserveCapacity(chosen.count)
        for (pos, p) in chosen.enumerated() {
            pKeyed.append((atan2(Double(y[p]) - cy, Double(x[p]) - cx), pos, p))
        }
        pKeyed.sort { $0.a != $1.a ? $0.a < $1.a : $0.pos < $1.pos }

        idOf.removeAll(keepingCapacity: true)
        for i in 0..<n { act[i] = 0 }
        let stagger = o.stagger ?? 0.18
        for k in 0..<L {
            let p = pKeyed[k].p
            let j = tKeyed[k].j
            idOf[T[j].id] = p
            start[p] = Float(t + stagger * (Double(k) / Double(max(1, L))))
            if o.scatter != 0 && !o.scatter.isNaN {
                x[p] = Float(cx + (MatrixHash.hash(p, 7) - 0.5) * o.scatter)
                y[p] = Float(cy + (MatrixHash.hash(p, 8) - 0.5) * o.scatter)
                vx[p] = 0
                vy[p] = 0
                b[p] = Float(min(Double(b[p]), 0.3))
            }
            if o.burst != 0 && !o.burst.isNaN {
                let a = MatrixHash.hash(p, 9) * Double.pi * 2
                let s = (0.3 + MatrixHash.hash(p, 10)) * o.burst
                vx[p] = Float(cos(a) * s)
                vy[p] = Float(sin(a) * s)
            }
        }
    }

    // MARK: update

    /// mdots.ts `update(key, T, t, o)`. Call once per drawn frame with the scene's targets
    /// (`MatrixBoard.out()`), the current time `t` in seconds, and the scene's deal options.
    public func update(key: String, targets T: ContiguousArray<MatrixTarget>, t: Double, options o: MatrixDealOptions = MatrixDealOptions()) {
        if key != self.key {
            deal(T, t: t, o: o)
            self.key = key
        }

        // targets by identity: keep a dot on its cell; a new cell lights in place; a gone cell lets go
        seen.removeAll(keepingCapacity: true)
        for i in 0..<n { used[i] = 0 }
        for p in idOf.values { used[p] = 1 }
        var free = 0
        for i in 0..<n { act[i] = 0 }
        for q in T {
            let p: Int
            if let existing = idOf[q.id] {
                p = existing
            } else {
                // nextFree(): first particle that is unowned and dark
                while free < n && (used[free] != 0 || Double(b[free]) > 0.03) { free += 1 }
                if free >= n { continue }
                p = free
                used[p] = 1
                idOf[q.id] = p
                x[p] = Float(q.x)
                y[p] = Float(q.y)
                vx[p] = 0
                vy[p] = 0
                b[p] = 0
                start[p] = Float(t)
            }
            seen.insert(q.id)
            if t < Double(start[p]) { continue }
            act[p] = 1
            tx[p] = Float(q.x)
            ty[p] = Float(q.y)
            tb[p] = Float(q.b)
            c[p] = q.c != 0 ? 1 : 0
        }
        gone.removeAll(keepingCapacity: true)
        for (id, _) in idOf where !seen.contains(id) { gone.append(id) }
        for id in gone {
            if let p = idOf.removeValue(forKey: id) { tb[p] = 0 }
        }

        // fixed-step physics
        let firstUpdate = last < 0
        if firstUpdate { last = t }
        var dt = min(0.1, max(0, t - last))
        let frameDt = dt
        last = t
        let h = 1.0 / 120.0
        let P = pointer
        while dt > 1e-6 {
            let s = min(h, dt)
            dt -= s
            let decay = 1 - 6 * s
            for i in 0..<n {
                if act[i] != 0 {
                    vx[i] = Float(Double(vx[i]) + ((Double(tx[i]) - Double(x[i])) * stiff - Double(vx[i]) * damp) * s)
                    vy[i] = Float(Double(vy[i]) + ((Double(ty[i]) - Double(y[i])) * stiff - Double(vy[i]) * damp) * s)
                } else {
                    vx[i] = Float(Double(vx[i]) * decay)
                    vy[i] = Float(Double(vy[i]) * decay)
                }
                if let P {
                    let dx = Double(x[i]) - P.x
                    let dy = Double(y[i]) - P.y
                    let d = hypot(dx, dy)
                    if d < 4.5 && d > 0.01 {
                        let k = (1 - d / 4.5) * 520 * s
                        vx[i] = Float(Double(vx[i]) + (dx / d) * k)
                        vy[i] = Float(Double(vy[i]) + (dy / d) * k)
                    }
                }
                x[i] = Float(Double(x[i]) + Double(vx[i]) * s)
                y[i] = Float(Double(y[i]) + Double(vy[i]) * s)
            }
        }

        // brightness easing
        let kOn: Double
        let kOff: Double
        switch brightnessMode {
        case .perFrame:
            kOn = 0.3
            kOff = 0.42
        case .timeBased:
            // The web's very first update has dt == 0 and still eases once: treat it as one 60 Hz frame.
            let frames = firstUpdate ? 1.0 : frameDt * 60
            kOn = 1 - pow(1 - 0.3, frames)
            kOff = 1 - pow(1 - 0.42, frames)
        }
        if kOn == 0 && kOff == 0 { return }
        for i in 0..<n {
            let on = act[i] != 0
            let target = on ? Double(tb[i]) : 0
            let bi = Double(b[i])
            b[i] = Float(bi + (target - bi) * (on ? kOn : kOff))
        }
    }

    /// Forget all history: particles go back to their hashed start positions, dark.
    /// Used before a deterministic warm-up so a re-appearing card renders the same frame as the web.
    public func reset(cols: Int, rows: Int) {
        for i in 0..<n {
            x[i] = Float(MatrixHash.hash(i, 1) * Double(cols))
            y[i] = Float(MatrixHash.hash(i, 2) * Double(rows))
            vx[i] = 0; vy[i] = 0; b[i] = 0; c[i] = 0
            tx[i] = 0; ty[i] = 0; tb[i] = 0; act[i] = 0; start[i] = 0
        }
        idOf.removeAll(keepingCapacity: true)
        key = ""
        last = -1
    }

    // MARK: draw

    /// mdots.ts `draw`: every lit particle as a disc, batched into 7 brightness levels (one fill
    /// each) plus one coral batch. Coordinates are design units: X = ox + x * pitch.
    ///
    /// - Parameters:
    ///   - context: the Canvas context, already scaled into design units.
    ///   - radius: full-brightness dot radius in design units (card 4.6, story 7.4).
    ///   - clip: optional brightness multiplier by design-space X (the card's fade under the copy).
    ///
    /// Each batch is ONE path filled with the non-zero rule, so dots that overlap in flight merge
    /// into one shape at one alpha, exactly like canvas `fill(Path2D)`. Never use `eoFill` here.
    public func draw(
        in context: GraphicsContext,
        ox: Double,
        oy: Double,
        pitch: Double,
        ink: Color,
        coral: Color,
        radius r: Double,
        clip: ((Double) -> Double)? = nil
    ) {
        let LV = 7
        var paths = [Path](repeating: Path(), count: LV)
        var cp = Path()
        var anyC = false
        for i in 0..<n {
            var bb = Double(b[i])
            if bb < 0.03 { continue }
            let X = ox + Double(x[i]) * pitch
            let Y = oy + Double(y[i]) * pitch
            if let clip { bb *= clip(X) }
            if bb < 0.03 { continue }
            let rr = r * (0.42 + 0.58 * min(1, bb))
            let rect = CGRect(x: X - rr, y: Y - rr, width: rr * 2, height: rr * 2)
            if c[i] != 0 && bb > 0.3 {
                cp.addEllipse(in: rect)
                anyC = true
                continue
            }
            let lv = min(LV - 1, Int((bb * Double(LV)).rounded(.down)))
            paths[lv].addEllipse(in: rect)
        }
        for k in 0..<LV where !paths[k].isEmpty {
            let alpha = 0.12 + 0.88 * ((Double(k) + 0.5) / Double(LV))
            context.fill(paths[k], with: .color(ink.opacity(alpha)))
        }
        if anyC {
            context.fill(cp, with: .color(coral))
        }
    }
}
