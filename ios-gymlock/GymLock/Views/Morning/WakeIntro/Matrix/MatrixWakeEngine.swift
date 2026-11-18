//
//  MatrixWakeEngine.swift
//  GymLock · Wake intro, Matrix concepts (native port)
//
//  Exact port of web/hero13/mdots.ts (class MDots), the particle board behind every Matrix visual.
//  Reused from rork-pack/swift/MatrixEngine.swift after review; changes from that file:
//    - The engine is now a VALUE type (struct). A snapshot is a plain copy (copy-on-write arrays), so
//      the wake Sim can keep one per second and restore it in O(1), exactly like board.ts `Sim`.
//    - Particle state is one array of structs; the physics loop runs on an unsafe buffer (no bounds,
//      uniqueness or exclusivity checks per particle).
//    - Default brightness easing is `.perFrame` (the wake Sim ticks on the web's 30 fps grid, so the
//      web's per-update constants apply as they are). `.timeBased` is kept for 60/120 Hz callers.
//    - Drawing moved to MatrixWakeStage (it interpolates between ticks and maps into the stage rect).
//    - Every type is prefixed (MatrixWake*, MXW): the Home hero card's own Matrix files in the same
//      module already define MatrixEngine, MatrixBoard, MX, JSMath, MatrixHash, MatrixTarget, PixelRows...
//
//  Behaviour (same as the web):
//    - A fixed pool of `n` particles. Every update gets a list of targets (x, y in grid cells,
//      brightness b, coral flag c, identity id).
//    - A target keeps its particle by IDENTITY (`id`): new cells light in place, moving things keep
//      their own dot, a gone target lets its dot fade.
//    - A new `key` re-deals every particle by angle around the targets' centroid, with a stagger.
//    - Fixed-step spring physics at 1/120 s substeps (stiffness 210, damping 21), dt clamped to 0.1 s.
//
//  Parity rules (PORTING-GUIDE.md):
//    - State is Float (the web uses Float32Array): every store is `Float(<Double expression>)`, computed
//      in Double from Float-widened inputs, in the SAME operation order as the TypeScript.
//    - Comparisons against literals widen first (`Double(b) > 0.04`).
//    - The hash is bit-identical to the TS hash (wrapping 32-bit math).
//    - Sorts are made stable with an index tie-break (JS Array.prototype.sort is stable).
//

import Foundation

// MARK: - JS numeric parity helpers

/// The JavaScript numeric semantics the prototype relies on, reproduced exactly.
public enum MatrixWakeJS {
    private static let two32: Double = 4_294_967_296.0

    /// ECMAScript `ToInt32` (what `x | 0` does): truncate toward zero, wrap modulo 2^32. NaN/inf give 0.
    @inline(__always)
    public static func toInt32(_ v: Double) -> Int32 {
        guard v.isFinite else { return 0 }
        var m = v.rounded(.towardZero).truncatingRemainder(dividingBy: two32)
        if m < 0 { m += two32 }
        return Int32(bitPattern: UInt32(m))
    }

    /// ECMAScript `ToUint32` (what `x >>> 0` does).
    @inline(__always)
    public static func toUint32(_ v: Double) -> UInt32 { UInt32(bitPattern: toInt32(v)) }

    /// `Math.round`: halves round UP (toward +infinity). `Math.round(-2.5) == -2`; Swift's
    /// `(-2.5).rounded()` is -3. Every `Math.round` in ported code uses this.
    @inline(__always)
    public static func round(_ x: Double) -> Double {
        let f = x.rounded(.down)
        return x - f >= 0.5 ? f + 1 : f
    }

    /// JS `a % b` on numbers: the result has the sign of the dividend.
    @inline(__always)
    public static func rem(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }
}

// MARK: - Deterministic hash

public enum MatrixWakeHash {
    /// mdots.ts `hash(i, k)`:
    /// ```ts
    /// let h = (i * 374761393 + k * 668265263) | 0;
    /// h = Math.imul(h ^ (h >>> 13), 1274126177);
    /// return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
    /// ```
    /// The sum is formed in Double (as in JS), then wrapped with ToInt32. Wrapping ops only (`&*`).
    @inline(__always)
    public static func hash(_ i: Double, _ k: Double) -> Double {
        var h = MatrixWakeJS.toUint32(i * 374_761_393 + k * 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double(h ^ (h >> 16)) / 4_294_967_296.0
    }

    @inline(__always)
    public static func hash(_ i: Int, _ k: Int) -> Double { hash(Double(i), Double(k)) }
}

// MARK: - Targets and deal options

/// One lit target for one update. Coordinates in grid cells (cell centres at n + 0.5).
public struct MatrixWakeTarget: Equatable, Sendable {
    public var x: Double
    public var y: Double
    /// Brightness 0...1.
    public var b: Double
    /// 1 = coral (the single accent), 0 = ink.
    public var c: UInt8
    /// Identity. Snapped cells `iy * 256 + ix`; free particles `1_000_000 + push index`;
    /// the home card's board adds 5_000_000 (board.ts `targets`).
    public var id: Int

    public init(x: Double, y: Double, b: Double, c: UInt8 = 0, id: Int) {
        self.x = x; self.y = y; self.b = b; self.c = c; self.id = id
    }
}

/// hero4/dots.ts `Opts` as used by mdots: how the dots fly when the key changes.
public struct MatrixWakeDealOptions: Equatable, Sendable {
    /// Seconds over which the deal is staggered. `nil` = engine default 0.18.
    public var stagger: Double?
    /// Non-zero: dealt dots are first thrown into a square of this size around the centroid.
    public var scatter: Double
    /// Non-zero: dealt dots get a random kick of this speed (cells / s).
    public var burst: Double

    public init(stagger: Double? = nil, scatter: Double = 0, burst: Double = 0) {
        self.stagger = stagger
        self.scatter = scatter
        self.burst = burst
    }
}

// MARK: - Engine

/// One particle. Float fields mirror the web's Float32Arrays field for field.
public struct MatrixWakeParticle: Equatable, Sendable {
    public var x: Float = 0
    public var y: Float = 0
    public var vx: Float = 0
    public var vy: Float = 0
    public var b: Float = 0
    public var tx: Float = 0
    public var ty: Float = 0
    public var tb: Float = 0
    public var start: Float = 0
    public var c: UInt8 = 0
    public var act: UInt8 = 0
}

public struct MatrixWakeEngine: Sendable {
    public enum BrightnessMode: Sendable {
        /// Web-exact: k = 0.3 / 0.42 per update call. Use when updates run on a fixed tick grid.
        case perFrame
        /// Same curve per second as the web at 60 fps: k = 1 - (1 - 0.3)^(dt * 60).
        case timeBased
    }

    public let n: Int
    public private(set) var p: ContiguousArray<MatrixWakeParticle>
    private var idOf: [Int: Int] = [:]
    public private(set) var key: String = ""
    private var last: Double = -1

    /// Pointer position in grid cells, or nil. Particles within 4.5 cells are pushed away.
    public var pointer: SIMD2<Double>?
    public var stiff: Double = 210
    public var damp: Double = 21
    public var brightnessMode: BrightnessMode = .perFrame

    // scratch (kept to avoid allocations; copied along with a snapshot, harmless)
    private var used: ContiguousArray<UInt8>
    private var seen = Set<Int>()
    private var gone: [Int] = []

    /// `new MDots(n, cols, rows)`: particles start scattered over the board by the hash, dark.
    public init(n: Int, cols: Int, rows: Int) {
        let n = max(1, n)
        self.n = n
        p = ContiguousArray(repeating: MatrixWakeParticle(), count: n)
        used = ContiguousArray(repeating: 0, count: n)
        seen.reserveCapacity(n)
        idOf.reserveCapacity(n)
        for i in 0..<n {
            p[i].x = Float(MatrixWakeHash.hash(i, 1) * Double(cols))
            p[i].y = Float(MatrixWakeHash.hash(i, 2) * Double(rows))
        }
    }

    // MARK: deal

    /// mdots.ts `deal`: assign particles to the new target list by angle around the centroid.
    private mutating func deal(_ T: ContiguousArray<MatrixWakeTarget>, t: Double, o: MatrixWakeDealOptions) {
        let L = min(T.count, n)
        var cx = 0.0, cy = 0.0
        for j in 0..<L {
            cx += T[j].x
            cy += T[j].y
        }
        let div = L == 0 ? 1.0 : Double(L) // `cx /= L || 1`
        cx /= div
        cy /= div

        // prefer particles already on screen, then idle ones (both in index order)
        var vis: [Int] = []
        var idle: [Int] = []
        vis.reserveCapacity(n)
        idle.reserveCapacity(n)
        for i in 0..<n {
            if Double(p[i].b) > 0.04 { vis.append(i) } else { idle.append(i) }
        }
        var chosen = Array(vis.prefix(L))
        var k = 0
        while chosen.count < L && k < idle.count {
            chosen.append(idle[k])
            k += 1
        }

        // JS sort is stable: ties keep their original order.
        var tKeyed: [(a: Double, j: Int)] = []
        tKeyed.reserveCapacity(L)
        for j in 0..<L { tKeyed.append((atan2(T[j].y - cy, T[j].x - cx), j)) }
        tKeyed.sort { $0.a != $1.a ? $0.a < $1.a : $0.j < $1.j }

        var pKeyed: [(a: Double, pos: Int, i: Int)] = []
        pKeyed.reserveCapacity(chosen.count)
        for (pos, i) in chosen.enumerated() {
            pKeyed.append((atan2(Double(p[i].y) - cy, Double(p[i].x) - cx), pos, i))
        }
        pKeyed.sort { $0.a != $1.a ? $0.a < $1.a : $0.pos < $1.pos }

        idOf.removeAll(keepingCapacity: true)
        for i in 0..<n { p[i].act = 0 }
        let stagger = o.stagger ?? 0.18
        let M = min(L, pKeyed.count)
        for k in 0..<M {
            let q = pKeyed[k].i
            let j = tKeyed[k].j
            idOf[T[j].id] = q
            p[q].start = Float(t + stagger * (Double(k) / Double(max(1, L))))
            if o.scatter != 0 && !o.scatter.isNaN {
                p[q].x = Float(cx + (MatrixWakeHash.hash(q, 7) - 0.5) * o.scatter)
                p[q].y = Float(cy + (MatrixWakeHash.hash(q, 8) - 0.5) * o.scatter)
                p[q].vx = 0
                p[q].vy = 0
                p[q].b = Float(min(Double(p[q].b), 0.3))
            }
            if o.burst != 0 && !o.burst.isNaN {
                let a = MatrixWakeHash.hash(q, 9) * Double.pi * 2
                let s = (0.3 + MatrixWakeHash.hash(q, 10)) * o.burst
                p[q].vx = Float(cos(a) * s)
                p[q].vy = Float(sin(a) * s)
            }
        }
    }

    // MARK: update

    /// mdots.ts `update(key, T, t, o)`.
    public mutating func update(key: String, targets T: ContiguousArray<MatrixWakeTarget>, t: Double, options o: MatrixWakeDealOptions = MatrixWakeDealOptions()) {
        if key != self.key {
            deal(T, t: t, o: o)
            self.key = key
        }

        // targets by identity: keep a dot on its cell; a new cell lights in place; a gone cell lets go
        seen.removeAll(keepingCapacity: true)
        for i in 0..<n { used[i] = 0 }
        for q in idOf.values { used[q] = 1 }
        var free = 0
        for i in 0..<n { p[i].act = 0 }
        for q in T {
            let i: Int
            if let existing = idOf[q.id] {
                i = existing
            } else {
                // nextFree(): first particle that is unowned and dark
                while free < n && (used[free] != 0 || Double(p[free].b) > 0.03) { free += 1 }
                if free >= n { continue }
                i = free
                used[i] = 1
                idOf[q.id] = i
                p[i].x = Float(q.x)
                p[i].y = Float(q.y)
                p[i].vx = 0
                p[i].vy = 0
                p[i].b = 0
                p[i].start = Float(t)
            }
            seen.insert(q.id)
            if t < Double(p[i].start) { continue }
            p[i].act = 1
            p[i].tx = Float(q.x)
            p[i].ty = Float(q.y)
            p[i].tb = Float(q.b)
            p[i].c = q.c != 0 ? 1 : 0
        }
        gone.removeAll(keepingCapacity: true)
        for (id, _) in idOf where !seen.contains(id) { gone.append(id) }
        for id in gone {
            if let i = idOf.removeValue(forKey: id) { p[i].tb = 0 }
        }

        // fixed-step physics
        let firstUpdate = last < 0
        if firstUpdate { last = t }
        var dt = min(0.1, max(0, t - last))
        let frameDt = dt
        last = t
        let h = 1.0 / 120.0
        let stiff = self.stiff, damp = self.damp
        let P = pointer
        p.withUnsafeMutableBufferPointer { buf in
            while dt > 1e-6 {
                let s = min(h, dt)
                dt -= s
                let decay = 1 - 6 * s
                for i in 0..<buf.count {
                    var q = buf[i]
                    if q.act != 0 {
                        q.vx = Float(Double(q.vx) + ((Double(q.tx) - Double(q.x)) * stiff - Double(q.vx) * damp) * s)
                        q.vy = Float(Double(q.vy) + ((Double(q.ty) - Double(q.y)) * stiff - Double(q.vy) * damp) * s)
                    } else {
                        q.vx = Float(Double(q.vx) * decay)
                        q.vy = Float(Double(q.vy) * decay)
                    }
                    if let P {
                        let dx = Double(q.x) - P.x
                        let dy = Double(q.y) - P.y
                        let d = (dx * dx + dy * dy).squareRoot()
                        if d < 4.5 && d > 0.01 {
                            let k = (1 - d / 4.5) * 520 * s
                            q.vx = Float(Double(q.vx) + (dx / d) * k)
                            q.vy = Float(Double(q.vy) + (dy / d) * k)
                        }
                    }
                    q.x = Float(Double(q.x) + Double(q.vx) * s)
                    q.y = Float(Double(q.y) + Double(q.vy) * s)
                    buf[i] = q
                }
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
            let frames = firstUpdate ? 1.0 : frameDt * 60
            kOn = 1 - pow(1 - 0.3, frames)
            kOff = 1 - pow(1 - 0.42, frames)
        }
        if kOn == 0 && kOff == 0 { return }
        p.withUnsafeMutableBufferPointer { buf in
            for i in 0..<buf.count {
                let on = buf[i].act != 0
                let target = on ? Double(buf[i].tb) : 0
                let bi = Double(buf[i].b)
                buf[i].b = Float(bi + (target - bi) * (on ? kOn : kOff))
            }
        }
    }

    /// board.ts `Sim.step` special case (first frame, and every frame under Reduce Motion): active dots
    /// sit on their targets with no velocity; with `brightnessToTarget` their brightness snaps too
    /// (dark when inactive).
    public mutating func snapToTargets(brightnessToTarget: Bool) {
        p.withUnsafeMutableBufferPointer { buf in
            for i in 0..<buf.count {
                if buf[i].act != 0 {
                    buf[i].x = buf[i].tx
                    buf[i].y = buf[i].ty
                    buf[i].vx = 0
                    buf[i].vy = 0
                }
                if brightnessToTarget { buf[i].b = buf[i].act != 0 ? buf[i].tb : 0 }
            }
        }
    }
}
