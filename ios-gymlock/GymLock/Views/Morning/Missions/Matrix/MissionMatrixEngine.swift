//
//  MissionMatrixEngine.swift
//  GymLock
//
//  The particle spring engine behind the Matrix figures (ported from the approved web engine).
//  A pool of dots flies from wherever it is into the next figure: a left-to-right sweep delay plus
//  deterministic jitter per dot, then an exact damped-spring step (zeta 0.75, ~0.45 s response).
//  An interruption retargets from the current position and velocity. State lives in flat
//  ContiguousArray<Float> buffers; stepping and frame building do not allocate (besides the one
//  frame value handed to Canvas).
//

import Foundation

// MARK: - Constants

nonisolated enum MissionMatrixSpring {
    static let zeta: Float = 0.75
    static let omega: Float = Float(2 * Double.pi / 0.45)
    static let zo: Float = zeta * omega
    static let wd: Float = omega * (1 - zeta * zeta).squareRoot()
    /// Fixed physics step (seconds).
    static let h: Double = 1.0 / 120.0
    static let decay: Float = Float(exp(-Double(zo) * h))
    static let cosWd: Float = Float(cos(Double(wd) * h))
    static let sinWd: Float = Float(sin(Double(wd) * h))
    /// Alpha follow rate per step, normal and reduce-motion crossfade.
    static let alphaK: Float = Float(1 - exp(-h * 12))
    static let alphaKReduced: Float = Float(1 - exp(-h * 30))
    /// Level easing (settles in about 250 ms).
    static let levelK: Float = Float(1 - exp(-h / 0.07))
}

/// Alpha quantisation: dots are batched into 8 alpha buckets (0.35 and 1.0 are exact).
nonisolated enum MissionMatrixLevels {
    static let dotLevels: [Float] = [0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 0.9, 1.0]
    static let haloLevels: [Float] = [0.4, 0.7, 1.0]
    static let accentOffset = 8
    static let haloOffset = 16
    static let layerCount = 19

    static func bucket(_ a: Float) -> Int {
        if a <= 0.15 { return 0 }
        if a <= 0.275 { return 1 }
        if a <= 0.425 { return 2 }
        if a <= 0.575 { return 3 }
        if a <= 0.725 { return 4 }
        if a <= 0.85 { return 5 }
        if a <= 0.95 { return 6 }
        return 7
    }
}

/// Deterministic hash in [0, 1). UInt32 wrapping arithmetic only.
nonisolated func missionMatrixHash(_ value: Int) -> Float {
    var n = UInt32(truncatingIfNeeded: value)
    let n0 = n
    n = ((n0 ^ 61) &* 0x9e3779b1) ^ (n0 >> 15)
    n = n &* 0x85ebca6b
    n ^= n >> 13
    n = n &* 0xc2b2ae35
    n ^= n >> 16
    return Float(n) / 4294967296.0
}

/// One frame of drawing data: plain values only, so it can be captured by a Canvas renderer.
nonisolated struct MissionMatrixFrame: Sendable {
    /// Four floats per dot: centre x, centre y, radius, layer (see `MissionMatrixLevels`).
    var records: ContiguousArray<Float> = []
    var pitch: Float = 1
    var originX: Float = 0
    var originY: Float = 0
    var cols: Int = 32
    var rows: Int = 22
    var sweepOn: Bool = false
    var sweepPos: Float = 0
    /// Halo alpha scale (0.16 x level).
    var haloScale: Float = 0
}

// MARK: - Engine

@MainActor
final class MissionMatrixEngine {
    // Public particle state (flat buffers, one entry per pooled dot).
    private(set) var x = ContiguousArray<Float>()
    private(set) var y = ContiguousArray<Float>()
    private(set) var vx = ContiguousArray<Float>()
    private(set) var vy = ContiguousArray<Float>()
    private(set) var alpha = ContiguousArray<Float>()
    /// Target alpha per dot.
    var target: ContiguousArray<Float> { ta }

    private(set) var cols = 32
    private(set) var rows = 22
    private(set) var count = 0
    private(set) var figure: MissionFigure?
    private(set) var mode: MissionDotMode = .fill
    private(set) var isConfigured = false

    /// Fires once when the dots have formed the current figure (delivered asynchronously).
    var onLand: ((MissionFigure) -> Void)?
    /// Reduce Motion: no idle, no sweep, no pulse, figure change is a crossfade.
    var reduceMotion = false

    // Targets and per-particle data.
    private var tx = ContiguousArray<Float>()
    private var ty = ContiguousArray<Float>()
    private var ta = ContiguousArray<Float>()
    private var tg = ContiguousArray<UInt8>()
    private var ts = ContiguousArray<UInt8>()        // 1 = real cell
    private var acc = ContiguousArray<UInt8>()       // 1 = accent cell
    // Pending (next) targets, applied when the dot's delay elapses.
    private var nx = ContiguousArray<Float>()
    private var ny = ContiguousArray<Float>()
    private var na = ContiguousArray<Float>()
    private var ng = ContiguousArray<UInt8>()
    private var ns = ContiguousArray<UInt8>()
    private var nacc = ContiguousArray<UInt8>()
    private var delay = ContiguousArray<Float>()
    private var pend = ContiguousArray<UInt8>()
    private var act = ContiguousArray<UInt8>()
    private var seen = ContiguousArray<UInt8>()

    private var clock: Double = 0
    private var setT: Double = 0
    private var accum: Double = 0
    private var lastTime: TimeInterval?
    private var landed = true
    private var nReal = 0
    private var reduceMode = false
    private var fox = 0
    private var foy = 0
    private var level: Float = 1
    private var levelTarget: Float = 1
    private var pulseT: Double = -1

    nonisolated init() {}

    // MARK: Public API

    /// Sizes the pool for a board. Safe to call again when the board changes.
    func configure(cols newCols: Int, rows newRows: Int) {
        cols = max(1, newCols)
        rows = max(1, newRows)
        let p = poolSize()
        if p > count { grow(to: p) }
        isConfigured = true
        if figure != nil { retarget(instant: false) }
    }

    /// Flies the dots into `figure` (from wherever they are now).
    func set(figure newFigure: MissionFigure, instant: Bool = false) {
        figure = newFigure
        retarget(instant: instant)
    }

    func setMode(_ newMode: MissionDotMode) {
        if newMode == mode { return }
        mode = newMode
        if figure != nil { retarget(instant: false) }
    }

    /// Brightness level 0...1, eased over ~250 ms (or applied at once).
    func setLevel(_ newLevel: Float, instant: Bool = false) {
        levelTarget = min(1, max(0, newLevel))
        if instant { level = levelTarget }
    }

    /// Brightness ripple from the centre outward (400 ms). No-op under Reduce Motion.
    func pulse() {
        if !reduceMotion { pulseT = clock }
    }

    /// Advances to an absolute time (seconds). Long gaps (paused timeline) count as one frame.
    func advance(to time: TimeInterval) {
        var dt = 1.0 / 60.0
        if let last = lastTime {
            let gap = time - last
            dt = gap > 0.25 ? 1.0 / 60.0 : max(0, gap)
        }
        lastTime = time
        step(dt: dt)
    }

    /// Fixed-step advance: `dt` is clamped to 1/30 s and consumed in 1/120 s spring steps.
    func step(dt: Double) {
        accum += min(max(dt, 0), 1.0 / 30.0)
        let h = MissionMatrixSpring.h
        while accum >= h {
            substep()
            accum -= h
        }
    }

    /// True when nothing is moving, fading or pulsing (used to pause the timeline under Reduce Motion).
    var isSettled: Bool {
        if figure == nil || pulseT >= 0 { return false }
        if abs(level - levelTarget) > 0.01 { return false }
        for i in 0..<count {
            if pend[i] != 0 { return false }
            if abs(x[i] - tx[i]) > 0.01 || abs(y[i] - ty[i]) > 0.01 { return false }
            if abs(alpha[i] - ta[i]) > 0.01 { return false }
        }
        return true
    }

    // MARK: Pool

    private func poolSize() -> Int {
        var m = 0
        for f in MissionFigure.allCases {
            m = max(m, MissionMatrixArt.cells(for: f, cols: cols, rows: rows).n)
        }
        return Int((Double(m) * 1.1).rounded(.up)) + 2
    }

    private func grow(to n: Int) {
        let add = n - count
        if add <= 0 { return }
        func extend(_ a: inout ContiguousArray<Float>) { a.append(contentsOf: repeatElement(0, count: add)) }
        func extend8(_ a: inout ContiguousArray<UInt8>) { a.append(contentsOf: repeatElement(0, count: add)) }
        extend(&x); extend(&y); extend(&vx); extend(&vy); extend(&alpha)
        extend(&tx); extend(&ty); extend(&ta); extend8(&tg); extend8(&ts); extend8(&acc)
        extend(&nx); extend(&ny); extend(&na); extend8(&ng); extend8(&ns); extend8(&nacc)
        extend(&delay); extend8(&pend); extend8(&act); extend8(&seen)
        frameBuf.reserveCapacity(n * 4 + 16)
        count = n
    }

    // MARK: Retargeting (sorted x/y matching)

    private var frameBuf = ContiguousArray<Float>()

    private func retarget(instant: Bool) {
        guard let fig = figure, count > 0 else { return }
        let cells = MissionMatrixArt.cells(for: fig, cols: cols, rows: rows)
        let outline = mode == .outline
        let N = outline ? cells.ne : cells.n
        if N == 0 { return }
        let ox = Int((Double(cols - cells.w) / 2).rounded(.down))
        let oy = Int((Double(rows - cells.h) / 2).rounded(.down))
        fox = ox
        foy = oy

        // Active particles sorted by their current target (x then y, index as tie-break).
        var order = [Int]()
        order.reserveCapacity(count)
        var spare = [Int]()
        spare.reserveCapacity(count)
        for i in 0..<count {
            if act[i] != 0 { order.append(i) } else { spare.append(i) }
        }
        let sx = tx, sy = ty
        order.sort { a, b in
            if sx[a] != sx[b] { return sx[a] < sx[b] }
            if sy[a] != sy[b] { return sy[a] < sy[b] }
            return a < b
        }
        let M = order.count
        var S = spare.count
        for i in 0..<count {
            seen[i] = 0
            act[i] = 0
        }
        let fixedDelay: Float = reduceMotion ? 0.1 : 0
        nReal = 0

        func cellIndex(_ j: Int) -> Int { outline ? cells.edgeIndex[j] : j }

        if M == 0 {
            // First assembly (or after everything folded): scatter the spares.
            for j in 0..<N {
                if S == 0 { break }
                S -= 1
                let p = spare[S]
                assign(p, cells: cells, cell: cellIndex(j), real: true, nbx: 0, nby: 0,
                       ox: ox, oy: oy, figure: fig, fixedDelay: fixedDelay)
                spawnScatter(p, tx: nx[p], ty: ny[p], instant: instant, j: j)
            }
        } else if N >= M {
            var sIdx = S
            var lastOwner = -1
            var ownerIdx = -1
            for j in 0..<N {
                let k = j * M / N
                let owner = order[k]
                let p: Int
                if k != lastOwner {
                    p = owner
                    lastOwner = k
                    ownerIdx = owner
                } else {
                    if sIdx == 0 { continue }
                    sIdx -= 1
                    p = spare[sIdx]
                    spawnAt(p, owner: ownerIdx)
                }
                assign(p, cells: cells, cell: cellIndex(j), real: true, nbx: 0, nby: 0,
                       ox: ox, oy: oy, figure: fig, fixedDelay: fixedDelay)
            }
            S = sIdx
        } else {
            // More particles than cells: proportional matching, extras fold onto a neighbour cell.
            var lastCell = -1
            for k in 0..<M {
                let j = min(N - 1, k * N / M)
                let p = order[k]
                if j != lastCell {
                    lastCell = j
                    assign(p, cells: cells, cell: cellIndex(j), real: true, nbx: 0, nby: 0,
                           ox: ox, oy: oy, figure: fig, fixedDelay: fixedDelay)
                } else {
                    let prev = order[k - 1]
                    assign(p, cells: cells, cell: 0, real: false, nbx: nx[prev], nby: ny[prev],
                           ox: ox, oy: oy, figure: fig, fixedDelay: fixedDelay)
                }
            }
        }

        // Leftover spares: park invisible ones, fade visible ones out in place.
        var s = 0
        while s < S {
            let p = spare[s]
            s += 1
            if seen[p] != 0 { continue }
            nx[p] = tx[p]; ny[p] = ty[p]; na[p] = 0; ng[p] = 35; ns[p] = 0; nacc[p] = 0
            delay[p] = 0; pend[p] = 1; act[p] = 0
        }

        setT = clock
        landed = false
        reduceMode = reduceMotion
        if instant {
            for p in 0..<count where pend[p] != 0 {
                applyPending(p)
                x[p] = tx[p]; y[p] = ty[p]; vx[p] = 0; vy[p] = 0; alpha[p] = ta[p]
            }
            landed = true
            setT = clock - 10
        }
    }

    private func assign(_ p: Int, cells: MissionMatrixCells, cell: Int, real: Bool, nbx: Float, nby: Float,
                        ox: Int, oy: Int, figure: MissionFigure, fixedDelay: Float) {
        var cx: Float, cy: Float
        var g: UInt8 = 35
        var a: Float = 0
        var accent: UInt8 = 0
        if real {
            cx = Float(ox + Int(cells.x[cell]))
            cy = Float(oy + Int(cells.y[cell]))
            g = cells.g[cell]
            a = cells.a[cell]
            accent = (g == 97 && figure == .check) ? 1 : 0
            nReal += 1
        } else {
            cx = nbx
            cy = nby
        }
        nx[p] = cx; ny[p] = cy; na[p] = a; ng[p] = g; ns[p] = real ? 1 : 0; nacc[p] = accent
        act[p] = real ? 1 : 0   // folded particles stay inactive so they can be reused
        let lr: Float = cells.w > 1 ? (cx - Float(ox)) / Float(cells.w - 1) : 0
        delay[p] = fixedDelay != 0 ? fixedDelay : (lr * 0.18 + missionMatrixHash(p * 7 + 3) * 0.08)
        pend[p] = 1
    }

    private func spawnScatter(_ p: Int, tx targetX: Float, ty targetY: Float, instant: Bool, j: Int) {
        if instant {
            x[p] = targetX; y[p] = targetY; tx[p] = targetX; ty[p] = targetY
            alpha[p] = 0; vx[p] = 0; vy[p] = 0
            return
        }
        if alpha[p] > 0.05 { return }   // visible leftovers keep their place
        let ang = missionMatrixHash(p * 13 + j) * Float(Double.pi * 2)
        let r = 5 + missionMatrixHash(p * 5 + 1) * 10
        x[p] = targetX + cos(ang) * r
        y[p] = targetY + sin(ang) * r * 0.7
        vx[p] = 0; vy[p] = 0; alpha[p] = 0
        tx[p] = x[p]; ty[p] = y[p]
    }

    private func spawnAt(_ p: Int, owner: Int) {
        seen[p] = 1
        if alpha[p] > 0.05 { return }   // visible: keep own position (no jump)
        x[p] = x[owner]; y[p] = y[owner]; vx[p] = vx[owner]; vy[p] = vy[owner]; alpha[p] = 0
        tx[p] = tx[owner]; ty[p] = ty[owner]
    }

    private func applyPending(_ p: Int) {
        tx[p] = nx[p]; ty[p] = ny[p]; ta[p] = na[p]; tg[p] = ng[p]; ts[p] = ns[p]; acc[p] = nacc[p]
        pend[p] = 0
    }

    // MARK: Stepping

    private func substep() {
        let h = MissionMatrixSpring.h
        clock += h
        let since = Float(clock - setT)
        level += (levelTarget - level) * MissionMatrixSpring.levelK
        let zo = MissionMatrixSpring.zo, wd = MissionMatrixSpring.wd
        let e = MissionMatrixSpring.decay, c = MissionMatrixSpring.cosWd, s = MissionMatrixSpring.sinWd
        let ka = reduceMode ? MissionMatrixSpring.alphaKReduced : MissionMatrixSpring.alphaK
        var near = 0
        var anyPending = false
        for i in 0..<count {
            if pend[i] != 0 && since >= delay[i] {
                applyPending(i)
                if reduceMode {
                    x[i] = tx[i]; y[i] = ty[i]; vx[i] = 0; vy[i] = 0
                }
            }
            // Exact damped-spring step.
            var a = x[i] - tx[i]
            var b = (vx[i] + zo * a) / wd
            x[i] = tx[i] + e * (a * c + b * s)
            vx[i] = e * (c * (b * wd - zo * a) - s * (a * wd + zo * b))
            a = y[i] - ty[i]
            b = (vy[i] + zo * a) / wd
            y[i] = ty[i] + e * (a * c + b * s)
            vy[i] = e * (c * (b * wd - zo * a) - s * (a * wd + zo * b))
            if pend[i] != 0 { anyPending = true }
            if reduceMode {
                let goal: Float = pend[i] != 0 ? 0 : ta[i]   // crossfade: out until the swap, then in
                alpha[i] += (goal - alpha[i]) * ka
            } else {
                alpha[i] += (ta[i] - alpha[i]) * ka
            }
            if ts[i] != 0 && pend[i] == 0 {
                let dx = x[i] - tx[i], dy = y[i] - ty[i]
                if dx * dx + dy * dy < 0.0225 { near += 1 }   // within 0.15 cell
            }
        }
        if !landed && since > 0.1 && nReal > 0 {
            if !anyPending && Float(near) >= Float(nReal) * 0.9 {
                landed = true
                if let f = figure { fireLand(f) }
            }
        }
    }

    private func fireLand(_ f: MissionFigure) {
        // Deferred so the callback never runs while SwiftUI is evaluating a view.
        Task { @MainActor [weak self] in self?.onLand?(f) }
    }
}

// MARK: - Frame building

extension MissionMatrixEngine {
    /// Builds this frame's draw records (one record per visible dot, tagged with its batch layer).
    /// Idle motion, level, pulse ripple and reduce-motion fade are applied here.
    func makeFrame(pitch: Float, originX: Float, originY: Float) -> MissionMatrixFrame {
        var frame = MissionMatrixFrame()
        frame.pitch = pitch
        frame.originX = originX
        frame.originY = originY
        frame.cols = cols
        frame.rows = rows
        frame.sweepOn = !reduceMotion
        frame.sweepPos = Float((clock.truncatingRemainder(dividingBy: 5)) / 5) * Float(cols + rows + 12) - 6

        guard let fig = figure else { return frame }
        frameBuf.removeAll(keepingCapacity: true)

        let outline = mode == .outline
        let rad0 = pitch * (outline ? 0.30 : 0.38)
        let since = Float(clock - setT)
        let idleW: Float = reduceMotion ? 0 : min(1, max(0, (since - 0.7) / 0.5))
        let idleT = max(0, clock - setT - 0.7)
        var fm: Float = 1
        if reduceMode && since < 0.2 { fm = min(1, abs(since - 0.1) / 0.1) }
        let lvl = level * fm
        frame.haloScale = 0.16 * lvl

        // Pulse ripple.
        var pr: Float = -1
        let cxm = Float(cols) / 2, cym = Float(rows) / 2
        if pulseT >= 0 {
            let pt = Float((clock - pulseT) / 0.4)
            if pt > 1 {
                pulseT = -1
            } else {
                let maxR = Float((Double(cols) * Double(cols) + Double(rows) * Double(rows)).squareRoot()) * 0.35
                pr = pt * maxR
            }
        }

        for i in 0..<count {
            var a = alpha[i]
            if a < 0.015 { continue }
            var px = x[i], py = y[i]
            if idleW > 0 && ts[i] != 0 && pend[i] == 0 {
                let o = MissionMatrixIdle.cell(fig, g: tg[i], x: tx[i] - Float(fox), y: ty[i] - Float(foy), t: idleT)
                px += o.dx * idleW
                py += o.dy * idleW
                a *= 1 + (o.alpha - 1) * idleW
            }
            a *= lvl
            var rad = rad0
            var halo: Float = 0
            if pr >= 0 {
                let ddx = px - cxm
                let ddy = py - cym
                let dist = (ddx * ddx + ddy * ddy).squareRoot()
                let dd = (dist - pr) / 1.8
                let w = exp(-dd * dd)
                a = min(1, a * (1 + 0.4 * w))
                rad *= 1 + 0.12 * w
                halo = w
            }
            a = min(1, a)
            let cx = originX + (px + 0.5) * pitch
            let cy = originY + (py + 0.5) * pitch
            if halo > 0.05 {
                let hb = halo < 0.45 ? 0 : (halo < 0.75 ? 1 : 2)
                frameBuf.append(cx); frameBuf.append(cy); frameBuf.append(rad * 1.6)
                frameBuf.append(Float(MissionMatrixLevels.haloOffset + hb))
            }
            if a < 0.01 { continue }
            let layer = MissionMatrixLevels.bucket(a) + (acc[i] != 0 ? MissionMatrixLevels.accentOffset : 0)
            frameBuf.append(cx); frameBuf.append(cy); frameBuf.append(rad); frameBuf.append(Float(layer))
        }
        frame.records = frameBuf
        return frame
    }
}
