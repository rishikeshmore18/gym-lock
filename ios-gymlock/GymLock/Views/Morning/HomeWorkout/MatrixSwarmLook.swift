//
//  MatrixSwarmLook.swift
//  GymLock · home workout, Matrix A "swarm"
//
//  1600 dots become the setup "20", then the count-up clock. At every checkpoint they explode and
//  re-form into "5" / "10" / "15"; at 20:00 they form a coral flame over the streak number; then
//  the clock with a mini flame above it. A finger drag pushes the dots away.
//
//  Port of the approved prototype (docs/prototypes/home-workout-variations.html, look "ma").
//  The HTML particle sim differs from MatrixEngine (explode on a hold, snap, three colour classes,
//  identity keys that grab the nearest free dot), so this file carries its own small sim instead of
//  bending MatrixEngine. Same springs (210 / 21), 1/120 s fixed steps.
//
//  The host draws the top-right control, the bottom button and dialogs; this view is a pure
//  function of `frame` plus private caches (sim, grid bitmap) held in @State.
//

import SwiftUI

// MARK: - Constants

private enum MSW {
    static let pitch: Double = 7.5
    static let np = 1600
    static let designW: Double = 390
    /// The prototype's safe top (its top control sits at 62 = 54 + 8).
    static let designSafeTop: Double = 54
}

// MARK: - Easing

/// cubic-bezier(x1, y1, x2, y2) solved by bisection, like CSS.
private func mswBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ p: Double) -> Double {
    if p <= 0 { return 0 }
    if p >= 1 { return 1 }
    var lo = 0.0, hi = 1.0, t = p
    for _ in 0..<24 {
        t = (lo + hi) / 2
        let u = 1 - t
        let x = 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t
        if x < p { lo = t } else { hi = t }
    }
    let u = 1 - t
    return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
}

/// The prototype's --settle curve.
private func mswSettle(_ p: Double) -> Double { mswBezier(0.22, 0.9, 0.24, 1, p) }
/// CSS ease-in-out.
private func mswEase(_ p: Double) -> Double { mswBezier(0.42, 0, 0.58, 1, p) }
private func mswClamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { max(a, min(b, x)) }

// MARK: - 5x7 font and flame bitmap

private enum MSWFont {
    static let rows: [Character: [String]] = [
        "0": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".###."]
    ]
    static let on: [Character: [[Bool]]] = rows.mapValues { $0.map { $0.map { $0 == "#" } } }
}

/// The app's flame silhouette (24 x 24 viewBox), rasterised once and sampled into dot grids.
/// 0 = empty, 1 = outer (ink), 2 = inner core (coral).
private enum MSWFlame {
    static let big: [[UInt8]] = bits(w: 24, h: 30)
    static let mini: [[UInt8]] = bits(w: 10, h: 13)

    private static func silhouette() -> CGPath {
        // The SVG path "M12.6 1.8 c.5 3.2 3.4 5 4.9 8 ... z" written as absolute curves. The one arc
        // (r 6, from (17.1,16.7) to (6.8,16.1), sweep 1) is sampled into short segments.
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 12.6, y: 1.8))
        p.addCurve(to: CGPoint(x: 17.5, y: 9.8), control1: CGPoint(x: 13.1, y: 5.0), control2: CGPoint(x: 16.0, y: 6.8))
        p.addCurve(to: CGPoint(x: 17.1, y: 16.7), control1: CGPoint(x: 18.6, y: 12.0), control2: CGPoint(x: 18.5, y: 14.6))
        let s = CGPoint(x: 17.1, y: 16.7), e = CGPoint(x: 6.8, y: 16.1), r = 6.0
        let dx = e.x - s.x, dy = e.y - s.y
        let d = (dx * dx + dy * dy).squareRoot()
        let h = (r * r - (d / 2) * (d / 2)).squareRoot()
        let ux = dx / d, uy = dy / d
        // centre on the side that makes the short arc bulge downward (sweep 1, y down)
        let c = CGPoint(x: (s.x + e.x) / 2 - uy * h, y: (s.y + e.y) / 2 + ux * h)
        let a0 = atan2(s.y - c.y, s.x - c.x)
        var a1 = atan2(e.y - c.y, e.x - c.x)
        if a1 < a0 { a1 += 2 * .pi }
        let steps = 20
        for i in 1...steps {
            let a = a0 + (a1 - a0) * Double(i) / Double(steps)
            p.addLine(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
        }
        p.addCurve(to: CGPoint(x: 7.2, y: 10.6), control1: CGPoint(x: 5.9, y: 14.3), control2: CGPoint(x: 6.2, y: 12.2))
        p.addCurve(to: CGPoint(x: 9.5, y: 13.4), control1: CGPoint(x: 7.6, y: 12.1), control2: CGPoint(x: 8.4, y: 13.0))
        p.addCurve(to: CGPoint(x: 12.6, y: 1.8), control1: CGPoint(x: 9.2, y: 9.7), control2: CGPoint(x: 10.1, y: 5.0))
        p.closeSubpath()
        return p
    }

    private static func bits(w W: Int, h H: Int) -> [[UInt8]] {
        let n = 240
        var buf = [UInt8](repeating: 0, count: n * n)
        buf.withUnsafeMutableBytes { raw in
            guard let g = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            g.translateBy(x: 0, y: CGFloat(n))
            g.scaleBy(x: 10, y: -10)
            g.setFillColor(gray: 1, alpha: 1)
            g.addPath(silhouette())
            g.fillPath()
        }
        var x0 = n, x1 = 0, y0 = n, y1 = 0
        for y in 0..<n {
            for x in 0..<n where buf[y * n + x] > 40 {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        guard x1 >= x0, y1 >= y0 else { return [] }
        let bw = Double(x1 - x0 + 1), bh = Double(y1 - y0 + 1)
        func inside(_ u: Double, _ v: Double) -> Bool {
            if u < 0 || u > 1 || v < 0 || v > 1 { return false }
            let x = Int((Double(x0) + u * bw).rounded(.down)), y = Int((Double(y0) + v * bh).rounded(.down))
            return buf[min(n - 1, y) * n + min(n - 1, x)] > 100
        }
        var rows: [[UInt8]] = []
        for y in 0..<H {
            var row: [UInt8] = []
            for x in 0..<W {
                let u = (Double(x) + 0.5) / Double(W), v = (Double(y) + 0.5) / Double(H)
                if !inside(u, v) { row.append(0); continue }
                row.append(inside(0.5 + (u - 0.5) * 1.7, 0.94 + (v - 0.94) * 1.7) ? 2 : 1)
            }
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Forms (which cells the dots make)

private struct MSWCell {
    /// Identity: a dot that owns this key stays on this cell while the form changes around it.
    let key: Int
    let c: Int
    let r: Int
    /// 0 ink, 2 coral, 3 blink (coral colon).
    let f: UInt8
}

private enum MSWForm: Equatable {
    case setup, clock, cp(Int), flame
}

private enum MSWCells {
    static func glyph(_ out: inout [MSWCell], _ ch: Character, kx: Int, ky: Int, c0: Int, r0: Int, g: Int) {
        guard let gl = MSWFont.on[ch] else { return }
        for r in 0..<7 {
            for q in 0..<5 where gl[r][q] {
                for a in 0..<kx {
                    for b in 0..<ky {
                        out.append(MSWCell(key: g * 100_000 + ((r * 5 + q) * 8 + a) * 8 + b, c: c0 + q * kx + a, r: r0 + r * ky + b, f: 0))
                    }
                }
            }
        }
    }

    static func colon(_ out: inout [MSWCell], kx: Int, ky: Int, c0: Int, r0: Int, g: Int, f: UInt8) {
        for r in [2, 4] {
            for a in 0..<kx {
                for b in 0..<ky {
                    out.append(MSWCell(key: g * 100_000 + (r * 8 + a) * 8 + b, c: c0 + a, r: r0 + r * ky + b, f: f))
                }
            }
        }
    }

    static func flame(_ out: inout [MSWCell], _ bits: [[UInt8]], c0: Int, r0: Int, g: Int) {
        for y in 0..<bits.count {
            for x in 0..<bits[y].count where bits[y][x] != 0 {
                out.append(MSWCell(key: g * 100_000 + y * 32 + x, c: c0 + x, r: r0 + y, f: bits[y][x] == 2 ? 2 : 0))
            }
        }
    }

    /// Setup "20" sits on row 15 and checkpoint glyphs on row 14 (the latest prototype).
    static func make(_ form: MSWForm, elapsed e: Double, streak: Int) -> [MSWCell] {
        var out: [MSWCell] = []
        out.reserveCapacity(900)
        switch form {
        case .setup:
            glyph(&out, "2", kx: 4, ky: 5, c0: 4, r0: 15, g: 1)
            glyph(&out, "0", kx: 4, ky: 5, c0: 28, r0: 15, g: 2)
        case .clock:
            let s = HomeWorkoutClock.format(min(e, 99 * 60 + 59))
            let ch = Array(s)
            let c0 = [2, 13, 29, 40]
            let ds = [ch[0], ch[1], ch[3], ch[4]]
            for i in 0..<4 { glyph(&out, ds[i], kx: 2, ky: 4, c0: c0[i], r0: 20, g: 3 + i) }
            colon(&out, kx: 2, ky: 4, c0: 25, r0: 20, g: 7, f: 3)
            if e >= 1200 { flame(&out, MSWFlame.mini, c0: 21, r0: 4, g: 8) }
        case .cp(let i):
            let w = ["5", "10", "15"][max(0, min(2, i))]
            let chars = Array(w)
            if chars.count == 1 {
                glyph(&out, chars[0], kx: 8, ky: 8, c0: 6, r0: 14, g: 9)
            } else {
                glyph(&out, chars[0], kx: 4, ky: 7, c0: 4, r0: 14, g: 10)
                glyph(&out, chars[1], kx: 4, ky: 7, c0: 28, r0: 14, g: 11)
            }
        case .flame:
            flame(&out, MSWFlame.big, c0: 14, r0: 6, g: 12)
            let n = Array(String(streak > 0 ? min(streak, 99) : 20))
            if n.count == 1 {
                glyph(&out, n[0], kx: 3, ky: 3, c0: 18, r0: 42, g: 13)
            } else {
                glyph(&out, n[0], kx: 2, ky: 3, c0: 15, r0: 42, g: 14)
                glyph(&out, n[1], kx: 2, ky: 3, c0: 27, r0: 42, g: 15)
            }
        }
        return out
    }
}

// MARK: - The sim (reference type, stepped from the Canvas)

@MainActor
private final class MSWSim {
    struct Hold { var form: MSWForm; var until: Double; var explode: Bool }

    let n = MSW.np
    var x: [Double], y: [Double], vx: [Double], vy: [Double]
    var tx: [Double], ty: [Double], ntx: [Double], nty: [Double], pend: [Double]
    /// 0 ink, 1 coral, 2 loose (dim), 3 blink.
    var col: [UInt8]
    var key: [Int]
    var ph1: [Double], ph2: [Double]

    var form: MSWForm?
    var sig = Int.min
    var hold: Hold?
    var lastBeatAt: Double?
    var needInit = true
    var last: Double = 0
    var acc: Double = 0
    /// Finger position in sim space, or nil.
    var ptr: CGPoint?

    var cMin = 0, cMax = 51, rMin = 0, rMax = 112
    var subLin: Double = 0

    var gridKey = ""
    var grid: CGImage?

    init() {
        let z = [Double](repeating: 0, count: MSW.np)
        x = z; y = z; vx = z; vy = z; tx = z; ty = z; ntx = z; nty = z; pend = z
        col = [UInt8](repeating: 2, count: MSW.np)
        key = [Int](repeating: -1, count: MSW.np)
        ph1 = z; ph2 = z
        var s: UInt64 = 3
        func r() -> Double { s = (s * 16807) % 2_147_483_647; return Double(s) / 2_147_483_647 }
        for i in 0..<MSW.np { ph1[i] = r() * 6.28; ph2[i] = r() * 6.28 }
    }

    @inline(__always) func px(_ c: Int) -> Double { (Double(c) + 0.5) * MSW.pitch }

    // MARK: placing dots

    func scatter(_ i: Int) {
        tx[i] = px(Int.random(in: cMin...cMax))
        ty[i] = px(Int.random(in: rMin...rMax))
        col[i] = 2
        key[i] = -1
    }

    func flyIn(width: Double, height: Double, ox: Double, dy: Double) {
        for i in 0..<n {
            let e = Int.random(in: 0..<4), r = Double.random(in: 0..<1)
            let l = -ox - 20, rt = width - ox + 20, t = -dy - 20, b = height - dy + 20
            switch e {
            case 0: x[i] = l; y[i] = t + r * (b - t)
            case 1: x[i] = rt; y[i] = t + r * (b - t)
            case 2: x[i] = l + r * (rt - l); y[i] = t
            default: x[i] = l + r * (rt - l); y[i] = b
            }
            vx[i] = 0; vy[i] = 0; key[i] = -1
            tx[i] = x[i]; ty[i] = y[i]; pend[i] = 0
        }
        form = nil; sig = Int.min; hold = nil; needInit = false
    }

    static func colOf(_ f: UInt8) -> UInt8 { f == 2 ? 1 : (f == 3 ? 3 : 0) }

    /// Re-deal every dot by angle around the form's centre, staggered (swirl into the new form).
    func deal(_ cells: [MSWCell], now: Double, stagger: Double, explode: Bool, snap: Bool) {
        let m = min(cells.count, n)
        guard m > 0 else { return }
        var cx = 0.0, cy = 0.0
        for i in 0..<m { cx += px(cells[i].c); cy += px(cells[i].r) }
        cx /= Double(m); cy /= Double(m)
        var idx = (0..<n).map { ($0, atan2(y[$0] - cy, x[$0] - cx)) }
        idx.sort { $0.1 < $1.1 }
        var cs = (0..<m).map { ($0, atan2(px(cells[$0].r) - cy, px(cells[$0].c) - cx)) }
        cs.sort { $0.1 < $1.1 }
        var used = [Bool](repeating: false, count: n)
        for i in 0..<m {
            let j = idx[Int((Double(i) + 0.5) * Double(n) / Double(m))].0
            used[j] = true
            let c = cells[cs[i].0]
            ntx[j] = px(c.c); nty[j] = px(c.r); key[j] = c.key; col[j] = MSWSim.colOf(c.f)
            pend[j] = now + stagger * Double(i) / Double(m)
        }
        for j in 0..<n {
            if !used[j] {
                scatter(j)
                ntx[j] = tx[j]; nty[j] = ty[j]
                pend[j] = now + Double.random(in: 0..<1) * stagger
            }
            if explode {
                let a = atan2(y[j] - cy, x[j] - cx) + (Double.random(in: 0..<1) - 0.5) * 0.6
                let sp = used[j] ? 260 + Double.random(in: 0..<1) * 380 : 80 + Double.random(in: 0..<1) * 120
                vx[j] = cos(a) * sp; vy[j] = sin(a) * sp
                pend[j] = now
            }
            if snap {
                x[j] = ntx[j]; y[j] = nty[j]; vx[j] = 0; vy[j] = 0; pend[j] = now
            }
        }
    }

    /// Same form, different cells (a clock digit ticked): dots keep their cell by key, new cells take
    /// the nearest free dot, vanished cells release theirs to scatter.
    func keyed(_ cells: [MSWCell]) {
        var map: [Int: MSWCell] = [:]
        map.reserveCapacity(cells.count)
        for c in cells { map[c.key] = c }
        var freed: [Int] = []
        var free: [Int] = []
        for i in 0..<n {
            let k = key[i]
            if k >= 0 {
                if let c = map[k] {
                    tx[i] = px(c.c); ntx[i] = tx[i]; ty[i] = px(c.r); nty[i] = ty[i]
                    col[i] = MSWSim.colOf(c.f); pend[i] = 0
                    map.removeValue(forKey: k)
                } else {
                    key[i] = -1; col[i] = 2
                    freed.append(i); free.append(i)
                }
            } else {
                free.append(i)
            }
        }
        for c in cells where map[c.key] != nil {
            let X = px(c.c), Y = px(c.r)
            var bi = -1
            var bd = Double.greatestFiniteMagnitude
            for q in 0..<free.count {
                let i = free[q]
                let dx = x[i] - X, dy = y[i] - Y
                let d = dx * dx + dy * dy
                if d < bd { bd = d; bi = q }
            }
            if bi < 0 { break }
            let i = free[bi]
            free[bi] = free[free.count - 1]
            free.removeLast()
            key[i] = c.key; col[i] = MSWSim.colOf(c.f)
            tx[i] = X; ntx[i] = X; ty[i] = Y; nty[i] = Y; pend[i] = 0
            if let fi = freed.firstIndex(of: i) { freed.remove(at: fi) }
        }
        for i in freed {
            scatter(i)
            ntx[i] = tx[i]; nty[i] = ty[i]; pend[i] = 0
        }
    }

    func pulse(_ amp: Double) {
        let cx = MSW.designW / 2, cy = 300.0
        for i in 0..<n where key[i] >= 0 {
            let a = atan2(y[i] - cy, x[i] - cx)
            vx[i] += cos(a) * amp; vy[i] += sin(a) * amp
        }
    }

    func step(_ dt: Double, now: Double) {
        let K = 210.0, Cd = 21.0, R = 4.5 * MSW.pitch, R2 = R * R, REP = 7000.0
        for i in 0..<n {
            if pend[i] > 0 && now >= pend[i] { tx[i] = ntx[i]; ty[i] = nty[i]; pend[i] = 0 }
            var ax = K * (tx[i] - x[i]) - Cd * vx[i]
            var ay = K * (ty[i] - y[i]) - Cd * vy[i]
            if let p = ptr {
                let dx = x[i] - Double(p.x), dy = y[i] - Double(p.y), d2 = dx * dx + dy * dy
                if d2 < R2 {
                    let d = d2.squareRoot() + 0.01, f = (1 - d / R) * REP
                    ax += dx / d * f; ay += dy / d * f
                }
            }
            vx[i] += ax * dt; vy[i] += ay * dt
            x[i] += vx[i] * dt; y[i] += vy[i] * dt
        }
    }

    // MARK: frame

    /// Advance the sim to this frame: beats, form changes, physics.
    func advance(_ f: HomeWorkoutFrame, ox: Double, dy: Double) {
        let now = f.now
        let w = Double(f.size.width), h = Double(f.size.height)
        let cmin = Int((-ox / MSW.pitch - 0.5).rounded(.up)), cmax = Int(((w - ox) / MSW.pitch - 0.5).rounded(.down))
        let rmin = Int((-dy / MSW.pitch - 0.5).rounded(.up)), rmax = Int(((h - dy) / MSW.pitch - 0.5).rounded(.down))
        if cmin != cMin || cmax != cMax || rmin != rMin || rmax != rMax {
            cMin = cmin; cMax = max(cmin, cmax); rMin = rmin; rMax = max(rmin, rmax)
            needInit = true
        }
        if needInit { flyIn(width: w, height: h, ox: ox, dy: dy) }

        // beats: a checkpoint holds its own form (explode and reform); "+5." only pulses
        if f.phase == .setup || f.elapsed < 300 {
            lastBeatAt = nil
            if f.phase == .setup { hold = nil }
        }
        if let b = f.beat, b.at != lastBeatAt {
            lastBeatAt = b.at
            if b.age < 0.5 {
                if let i = b.checkpointIndex {
                    hold = Hold(form: i < 3 ? .cp(i) : .flame, until: now + (i < 3 ? 1.45 : 2.0) - b.age, explode: true)
                } else {
                    pulse(110)
                }
            }
        }
        if let hd = hold, now >= hd.until { hold = nil }

        let newForm: MSWForm
        let newSig: Int
        if f.phase == .setup {
            newForm = .setup; newSig = -1
        } else if let hd = hold {
            newForm = hd.form
            switch hd.form {
            case .cp(let i): newSig = -10 - i
            default: newSig = -20
            }
        } else {
            newForm = .clock
            newSig = Int(f.elapsed.rounded(.down)) + (f.elapsed >= 1200 ? 1_000_000 : 0)
        }

        let streak = f.facts.streakWeeks
        if newForm != form {
            var stagger = newForm == .setup ? 0.42 : ((form != nil && form != .clock && newForm == .clock) ? 0.26 : 0.22)
            var explode = false
            if let hd = hold, hd.explode, newForm == hd.form {
                explode = true; stagger = 0; hold?.explode = false
            }
            deal(MSWCells.make(newForm, elapsed: f.elapsed, streak: streak), now: now, stagger: stagger, explode: explode, snap: f.reduceMotion)
            form = newForm; sig = newSig
        } else if newSig != sig {
            keyed(MSWCells.make(newForm, elapsed: f.elapsed, streak: streak))
            sig = newSig
            if f.reduceMotion {
                for i in 0..<n { x[i] = tx[i]; y[i] = ty[i]; vx[i] = 0; vy[i] = 0 }
            }
        }

        var dt = min((now - last), 0.1)
        if last == 0 || dt < 0 { dt = 0 }
        last = now
        acc += dt
        var steps = 0
        while acc >= 1.0 / 120 && steps < 10 {
            step(1.0 / 120, now: now)
            acc -= 1.0 / 120
            steps += 1
        }
        if steps == 10 { acc = 0 }

        // the small label fades out while a checkpoint form holds the screen (250 ms)
        subLin = mswClamp(subLin + dt / 0.25 * (hold != nil ? 1 : -1))
    }

    // MARK: grid

    func gridImage(size: CGSize, ox: Double, dy: Double, scale: CGFloat) -> CGImage? {
        let k = "\(Int(size.width))x\(Int(size.height))@\(scale)/\(Int(ox * 10))/\(Int(dy * 10))"
        if k == gridKey, let g = grid { return g }
        let wpx = Int((size.width * scale).rounded(.up)), hpx = Int((size.height * scale).rounded(.up))
        guard wpx > 0, hpx > 0, wpx <= 8192, hpx <= 8192,
              let g = CGContext(data: nil, width: wpx, height: hpx, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        g.translateBy(x: 0, y: CGFloat(hpx))
        g.scaleBy(x: scale, y: -scale)
        g.setFillColor(CGColor(srgbRed: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 0.07))
        for r in rMin...rMax {
            for c in cMin...cMax {
                let X = ox + px(c), Y = dy + px(r)
                g.addEllipse(in: CGRect(x: X - 1.2, y: Y - 1.2, width: 2.4, height: 2.4))
            }
        }
        g.fillPath()
        grid = g.makeImage()
        gridKey = k
        return grid
    }
}

// MARK: - Layout and timing shared by canvas and overlays

private struct MSWLayout {
    let ox: Double
    let dy: Double
    init(_ f: HomeWorkoutFrame) {
        ox = (Double(f.size.width) - MSW.designW) / 2
        dy = f.safeTop > 20 ? Double(f.safeTop) - MSW.designSafeTop : 0
    }

    /// Setup copy group opacity and offset while the screen morphs into the timer.
    static func setupGroup(_ f: HomeWorkoutFrame) -> (opacity: Double, offset: Double) {
        guard f.phase == .running else { return (1, 0) }
        let o = 1 - mswEase(mswClamp(f.runAge / 0.2))
        return (o, f.reduceMotion ? 0 : -14 * mswSettle(mswClamp(f.runAge / 0.3)))
    }

    /// Timer copy group (label and beat) comes in 150 ms later.
    static func timerGroup(_ f: HomeWorkoutFrame) -> (opacity: Double, offset: Double) {
        guard f.phase == .running else { return (0, 0) }
        let a = f.runAge - 0.15
        let o = mswEase(mswClamp(a / 0.42))
        return (o, f.reduceMotion ? 0 : 14 * (1 - mswSettle(mswClamp(a / 0.55))))
    }

    /// One setup line's entrance (opacity, y offset), delayed by `delay` seconds.
    static func enter(_ f: HomeWorkoutFrame, delay: Double) -> (opacity: Double, offset: Double) {
        guard f.phase == .setup else { return (1, 0) }
        let p = mswSettle(mswClamp((f.setupAge - delay) / 0.7))
        return (p, f.reduceMotion ? 0 : 22 * (1 - p))
    }

    // Prototype positions (css top of each box), before the safe-top shift.
    static let streakRowTop: Double = 546
    static let rowGap: Double = 9
    static let rowDelay: Double = 0.76
}

// MARK: - Text helper

private func mswText(
    _ ctx: GraphicsContext, _ s: String, size: CGFloat, weight: Font.Weight, track: CGFloat,
    color: Color, x: CGFloat, cy: CGFloat, opacity: Double, dy: CGFloat = 0,
    scale: CGFloat = 1, clip: CGRect? = nil, maxWidth: CGFloat? = nil
) {
    guard opacity > 0.003 else { return }
    var c = ctx
    if let clip { c.clip(to: Path(clip)) }
    c.opacity = opacity
    func make(_ fs: CGFloat) -> GraphicsContext.ResolvedText {
        c.resolve(Text(s).font(.system(size: fs, weight: weight)).monospacedDigit().tracking(track * fs / size).foregroundStyle(color))
    }
    var fs = size
    var rt = make(fs)
    if let mw = maxWidth {
        let w = rt.measure(in: CGSize(width: 2000, height: 400)).width
        if w > mw { fs = size * mw / w; rt = make(fs) }
    }
    c.translateBy(x: x, y: cy + dy)
    if scale != 1 { c.scaleBy(x: scale, y: scale) }
    c.draw(rt, at: .zero, anchor: UnitPoint(x: 0, y: 0.5))
}

// MARK: - The look

struct MatrixSwarmLook: View {
    let frame: HomeWorkoutFrame

    @State private var sim = MSWSim()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let lay = MSWLayout(frame)
        let f = frame
        ZStack(alignment: .topLeading) {
            Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, size in
                render(&ctx, size: size, lay: lay)
            }
            .contentShape(Rectangle())
            .gesture(
                // Under the host's buttons (they sit above this view); a zero-distance drag
                // just moves the pointer the dots flee from.
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        sim.ptr = CGPoint(x: v.location.x - lay.ox, y: v.location.y - lay.dy)
                    }
                    .onEnded { _ in sim.ptr = nil }
            )
            .accessibilityHidden(true)

            if f.phase == .setup || f.runAge < 0.5, f.facts.streakWeeks > 0 {
                streakFlame(lay)
            }

            Color.clear
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(f.isRunning ? "workout time" : "home workout")
                .accessibilityValue(f.isRunning
                    ? "\(HomeWorkoutClock.format(f.elapsed)), \(HomeWorkoutClock.label(f.elapsed))"
                    : "20 min. that's it. go longer if you want.")
        }
        .frame(width: f.size.width, height: f.size.height, alignment: .topLeading)
    }

    /// The app's real flame, in the streak row.
    private func streakFlame(_ lay: MSWLayout) -> some View {
        let g = MSWLayout.setupGroup(frame)
        let e = MSWLayout.enter(frame, delay: MSWLayout.rowDelay)
        let cy = lay.dy + MSWLayout.streakRowTop + 11 + e.offset + g.offset
        return FlameFigure(visibleHeight: 20, isAnimating: !frame.reduceMotion)
            .frame(width: 22, height: 22)
            .position(x: 28 + 11, y: cy)
            .opacity(e.opacity * g.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: drawing

    private func render(_ ctx: inout GraphicsContext, size: CGSize, lay: MSWLayout) {
        let f = frame
        let ox = lay.ox, dy = lay.dy
        sim.advance(f, ox: ox, dy: dy)

        // background and the dim dot field
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.canvas))
        if let g = sim.gridImage(size: size, ox: ox, dy: dy, scale: displayScale) {
            ctx.draw(Image(decorative: g, scale: displayScale), in: CGRect(origin: .zero, size: size))
        }

        drawParticles(&ctx, lay: lay)
        drawSetupCopy(ctx, lay: lay)
        drawTimerCopy(ctx, lay: lay)
    }

    private func drawParticles(_ ctx: inout GraphicsContext, lay: MSWLayout) {
        let f = frame
        let s = sim
        let now = f.now, ox = lay.ox, dy = lay.dy
        let rm = f.reduceMotion
        let isClock = s.form == .clock
        let amp: Double = rm ? 0 : (isClock ? 0.25 + 1.4 * pow(HomeWorkoutClock.spurt(f.elapsed), 1.4) : 0.15)
        let drift: Double = rm ? 0 : 3
        let blink: Double = (isClock && f.elapsed < 1200) ? mswClamp(1 - (f.elapsed - f.elapsed.rounded(.down)) * 1.7) : 0

        var loose = Path(), ink = Path(), coral = Path(), mix = Path()
        for i in 0..<s.n {
            let c = s.col[i]
            if c == 2 {
                let px = ox + s.x[i] + sin(now * 0.7 + s.ph1[i]) * drift
                let py = dy + s.y[i] + cos(now * 0.6 + s.ph2[i]) * drift
                loose.addEllipse(in: CGRect(x: px - 1.5, y: py - 1.5, width: 3, height: 3))
            } else {
                let px = ox + s.x[i] + sin(now * 31 + s.ph1[i]) * amp
                let py = dy + s.y[i] + cos(now * 27 + s.ph2[i]) * amp
                let r = CGRect(x: px - 2.6, y: py - 2.6, width: 5.2, height: 5.2)
                switch c {
                case 0: ink.addEllipse(in: r)
                case 1: coral.addEllipse(in: r)
                default: mix.addEllipse(in: r)
                }
            }
        }
        ctx.fill(loose, with: .color(Theme.ink.opacity(0.11)))
        ctx.fill(ink, with: .color(Theme.ink))
        ctx.fill(coral, with: .color(Theme.accent))
        // colon: ink (26,26,26) to coral (232,93,78) as it blinks
        let mr = (26 + (232 - 26) * blink) / 255, mg = (26 + (93 - 26) * blink) / 255, mb = (26 + (78 - 26) * blink) / 255
        ctx.fill(mix, with: .color(Color(.sRGB, red: mr, green: mg, blue: mb, opacity: 1)))
    }

    private func drawSetupCopy(_ ctx: GraphicsContext, lay: MSWLayout) {
        let f = frame
        let g = MSWLayout.setupGroup(f)
        guard g.opacity > 0.003 else { return }
        let dy = lay.dy

        func line(_ s: String, size: CGFloat, weight: Font.Weight, track: CGFloat, color: Color, x: CGFloat, top: Double, lh: Double, delay: Double) {
            let e = MSWLayout.enter(f, delay: delay)
            mswText(ctx, s, size: size, weight: weight, track: track, color: color,
                    x: x, cy: CGFloat(dy + top + lh / 2), opacity: e.opacity * g.opacity, dy: CGFloat(e.offset + g.offset))
        }

        line("20 min.", size: 46, weight: .heavy, track: -0.035 * 46, color: Theme.ink, x: 28, top: 384, lh: 46, delay: 0.52)
        line("that's it.", size: 46, weight: .heavy, track: -0.035 * 46, color: Theme.ink, x: 28, top: 430, lh: 46, delay: 0.52)
        line("go longer if you want.", size: 17, weight: .regular, track: 0, color: Theme.inkSecondary, x: 28, top: 486, lh: 22, delay: 0.64)

        var top = MSWLayout.streakRowTop
        var i = 0
        if f.facts.streakWeeks > 0 {
            line(HomeWorkoutCopy.streak(f.facts.streakWeeks), size: 17, weight: .bold, track: 0, color: Theme.ink, x: 28 + 22 + 8,
                 top: top, lh: 22, delay: MSWLayout.rowDelay + Double(i) * 0.09)
            top += 22 + MSWLayout.rowGap
            i += 1
        }
        let rows: [(String, Color)] = [
            (HomeWorkoutCopy.stake(f.facts), Theme.ink),
            (HomeWorkoutCopy.check(f.facts), Theme.inkSecondary),
            (HomeWorkoutCopy.quota(f.facts), Theme.inkSecondary)
        ]
        for (s, c) in rows {
            line(s, size: 15, weight: .regular, track: 0, color: c, x: 28, top: top, lh: 20, delay: MSWLayout.rowDelay + Double(i) * 0.09)
            top += 20 + MSWLayout.rowGap
            i += 1
        }
    }

    private func drawTimerCopy(_ ctx: GraphicsContext, lay: MSWLayout) {
        let f = frame
        guard f.isRunning else { return }
        let g = MSWLayout.timerGroup(f)
        guard g.opacity > 0.003 else { return }
        let dy = lay.dy
        let e = f.elapsed
        let rm = f.reduceMotion

        // rolling label: new text slides up from below, old slides out the top (500 ms settle);
        // Reduce Motion cross-fades in 300 ms
        let cur = HomeWorkoutClock.label(e)
        let tc = (e / 60).rounded(.down) * 60
        let age = e - tc
        var prev: String?
        if tc > 0 && age < (rm ? 0.3 : 0.5) {
            let p = HomeWorkoutClock.label(tc - 0.001)
            if p != cur { prev = p }
        }
        let subOp = (1 - mswEase(sim.subLin)) * g.opacity
        let boxTop = dy + 380
        let clip = CGRect(x: 28, y: boxTop + g.offset, width: 334, height: 30)
        let cy = CGFloat(boxTop + 15 + g.offset)
        func label(_ s: String, op: Double, off: Double) {
            mswText(ctx, s, size: 22, weight: .semibold, track: -0.01 * 22, color: Theme.inkSecondary,
                    x: 28, cy: cy, opacity: op * subOp, dy: CGFloat(off), clip: clip)
        }
        if let prev {
            if rm {
                let p = age / 0.3
                label(prev, op: 1 - p, off: 0)
                label(cur, op: p, off: 0)
            } else {
                let p = mswSettle(age / 0.5)
                label(prev, op: 1 - p, off: -30 * p)
                label(cur, op: p, off: 30 * (1 - p))
            }
        } else {
            label(cur, op: 1, off: 0)
        }

        // checkpoint text: scales in from 1.3, holds, fades; "+5." is the half-size soft one
        if let b = f.beat {
            let soft = b.checkpointIndex == nil
            let dur = soft ? 1.2 : (b.isTwenty ? 1.6 : 1.5)
            let hold = soft ? 0.75 : 0.8
            let u = b.age / dur
            guard u < 1 else { return }
            let rise = 0.55 / dur
            var op = 1.0, sc = 1.0
            if rm {
                op = u < 0.25 ? u / 0.25 : (u < hold ? 1 : 1 - (u - hold) / (1 - hold))
            } else if u < rise {
                let p = mswSettle(u / rise)
                op = p; sc = 1.3 - 0.3 * p
            } else if u >= hold {
                op = 1 - (u - hold) / (1 - hold)
            }
            let size: CGFloat = soft ? 28 : 56
            mswText(ctx, b.text, size: size, weight: .heavy, track: -0.04 * size, color: Theme.ink,
                    x: 28, cy: CGFloat(dy + 536 + Double(size) / 2 + g.offset), opacity: op * g.opacity,
                    scale: CGFloat(sc), maxWidth: 334)
        }
    }
}
