//
//  MatrixScene.swift
//  GymLock · Matrix hero (native port)
//
//  The scene contract (mxlib.ts types MC / MOut / MHap / MScn), the shared helpers every scene file
//  imports (mx/common.ts), the registry (mx13.ts), and three scenes ported line by line to show the
//  pattern:
//
//    - verified, Wednesday: BATTERY        (web/hero13/mx/verified.ts, `battery`)
//    - wake, Monday:        THE BELL       (web/hero13/mx/wake.ts, SCENES[0])
//    - countdown, Wednesday: WATER CLOCK   (web/hero13/mx/countdown.ts, SCENES[2])
//
//  Porting pattern (PORTING-GUIDE.md has the full rules):
//    - Every scene file becomes `extension MX { enum <Moment> { ... } }`, so `cl`, `ez`, `g.on`, `CX`
//      resolve unqualified exactly like the TS imports.
//    - Module-level `const` tables become `static let` (computed once, Sendable).
//    - `draw: (g, c) => {...}` becomes a `@Sendable (inout MatrixBoard, MatrixContext) -> SceneOut`
//      closure, statement for statement, keeping every push in the same order and count.
//    - `return {o, flash, shake, ph}` becomes `SceneOut(...)`; `void` / `{}` becomes `.none`.
//
//  Depends on: MatrixEngine.swift, MatrixBoard.swift, HeroHaptics.swift (HapticCue / HapticKind).
//

import Foundation

// MARK: - Context (TS type MC)

public enum MatrixWeekPos: String, Sendable, CaseIterable {
    case first, middle, last
}

/// `MC.d`: the live numbers of the day.
public struct MatrixLiveData: Sendable, Equatable {
    /// The three setup items, done or not.
    public var setupDone: [Bool]
    /// Seconds left before leaving (countdown state).
    public var countdown: Double
    /// Seconds on the gym floor (proof at MX.PROOF = 1200).
    public var atgym: Double
    /// Seconds left this evening (stilltime state).
    public var stillLeft: Double

    public init(setupDone: [Bool] = [false, false, false], countdown: Double = 0, atgym: Double = 0, stillLeft: Double = 0) {
        self.setupDone = setupDone
        self.countdown = countdown
        self.atgym = atgym
        self.stillLeft = stillLeft
    }
}

/// `MC.D`: where the user is in the 66 days.
public struct MatrixDayData: Sendable, Equatable {
    public var day: Int
    public var week: Int
    public var sessions: Int
    public init(day: Int, week: Int, sessions: Int) {
        self.day = day
        self.week = week
        self.sessions = sessions
    }
}

/// TS `MC`, the input of every scene's draw.
public struct MatrixContext: Sendable {
    /// Global seconds (the engine's clock). Use for idle motion that should not restart with the state.
    public var t: Double
    /// Seconds since the card entered this state. Use for beats.
    public var T: Double
    public var d: MatrixLiveData
    /// 0 = Monday ... 6 = Sunday.
    public var day: Int
    public var pos: MatrixWeekPos
    /// Taps in today's finish: 5, or 7 for the week's last session and every Sunday.
    public var N: Int
    public var D: MatrixDayData

    public init(t: Double, T: Double, d: MatrixLiveData, day: Int, pos: MatrixWeekPos, N: Int, D: MatrixDayData) {
        self.t = t
        self.T = T
        self.d = d
        self.day = day
        self.pos = pos
        self.N = N
        self.D = D
    }

    /// days12.ts `tapsFor12(day, pos)`.
    public static func taps(day: Int, pos: MatrixWeekPos) -> Int { day == 6 || pos == .last ? 7 : 5 }
}

// MARK: - Output (TS type MOut)

public struct SceneOut: Sendable, Equatable {
    /// `ph`: a new value re-deals every dot (they fly to the next form). nil == the web's `0`.
    public var phase: String?
    /// `o`: how the dots fly on a deal. nil == the card default `{stagger: 0.25}`.
    public var opts: MatrixDealOptions?
    /// Board-wide flash, 0...0.3 (drawn at min(0.3, flash * 0.6) of ink).
    public var flash: Double
    /// Shake, in cells (multiplied by the pitch), 0...0.4.
    public var shake: Double

    public init(phase: String? = nil, opts: MatrixDealOptions? = nil, flash: Double = 0, shake: Double = 0) {
        self.phase = phase
        self.opts = opts
        self.flash = flash
        self.shake = shake
    }

    public static let none = SceneOut()
}

// MARK: - Scene (TS type MScn)

public struct MatrixScene: Sendable {
    public typealias Draw = @Sendable (inout MatrixBoard, MatrixContext) -> SceneOut
    public let draw: Draw
    /// `hap`: cues in scene seconds (T). Empty == no Matrix-specific haptics (the web then falls back
    /// to the Ridge table `hapFor(state, day)` in props13.ts; port that table if you need it).
    public let haptics: [HapticCue]

    public init(haptics: [HapticCue] = [], draw: @escaping Draw) {
        self.draw = draw
        self.haptics = haptics
    }

    /// Placeholder for scenes not ported yet: an empty board (dots fade out), no haptics.
    public static let empty = MatrixScene { _, _ in .none }
}

// MARK: - Registry (mx13.ts)

/// The moments of the day, same raw values as the web state names (S4 in card4.tsx).
public enum MatrixMoment: String, Sendable, CaseIterable {
    case setup, firstnight, bedtime, wake, countdown, ready, commute, atgym, verified, stilltime
    case rest, paused, freshstart, missed, weekkept, comeback, drift, halfway, automatic

    /// Night states use the dark "night" look even in light mode (card13m.tsx `lookFor`).
    public var isNight: Bool { self == .firstnight || self == .bedtime }
}

public enum MatrixSceneRegistry {
    /// `mxScene(state, day)`: one scene per moment per day (index 0 = Monday).
    /// Unported entries are nil and resolve to `MatrixScene.empty`.
    private static let table: [MatrixMoment: [MatrixScene?]] = [
        .wake: [MX.Wake.bell, nil, nil, nil, nil, nil, nil],
        .countdown: [nil, nil, MX.Countdown.waterClock, nil, nil, nil, nil],
        .verified: [nil, nil, MX.Verified.battery, nil, nil, nil, nil],
        // TODO: port the remaining 130 scenes from web/hero13/mx/*.ts with the same pattern.
    ]

    public static func scene(_ moment: MatrixMoment, day: Int) -> MatrixScene {
        guard day >= 0, day < 7, let row = table[moment], day < row.count, let s = row[day] else { return .empty }
        return s
    }

    public static func isPorted(_ moment: MatrixMoment, day: Int) -> Bool {
        guard day >= 0, day < 7, let row = table[moment], day < row.count else { return false }
        return row[day] != nil
    }

    /// `mxHap(state, day)`.
    public static func haptics(_ moment: MatrixMoment, day: Int) -> [HapticCue] {
        scene(moment, day: day).haptics
    }
}

// MARK: - mx/common.ts

extension MX {
    /// The first five rings: heavy, medium, heavy, medium, heavy.
    public static let ringHap: [HapticCue] = RINGS.enumerated().map { i, t in HapticCue(t: t, kind: i % 2 != 0 ? .medium : .heavy) }

    public static func charge(_ t: Double) -> Double { min(0.98, 0.18 + JSMath.rem(t * 0.02, 0.8)) }

    public static func twinkle(_ g: inout MatrixBoard, _ n: Int, _ seed: Double, _ t: Double, _ x0: Double = 4, _ x1: Double = 37, _ y0: Double = 1, _ y1: Double = 33, _ b: Double = 0.7) {
        for ii in 0..<max(0, n) {
            let i = Double(ii)
            let w = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * (1 + rnd(i + seed) * 2) + i * 2.3))
            g.on(x0 + rnd(seed + i) * (x1 - x0), y0 + rnd(seed + i + 50) * (y1 - y0), b * w)
        }
    }

    public static func twinkleB(_ g: inout MatrixBoard, _ n: Int, _ seed: Double, _ t: Double, _ b: Double = 0.6) {
        for ii in 0..<max(0, n) {
            let i = Double(ii)
            let w = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * (1 + rnd(i + seed) * 2) + i * 2.3))
            g.on(4 + rnd(seed + i) * 33, 1 + rnd(seed + i + 50) * 32, b * w)
        }
    }

    public enum ChevronDir: Sendable { case up, down, right }

    public static func chevron(_ g: inout MatrixBoard, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ dir: ChevronDir, _ b: Double, _ c: Int = 0) {
        switch dir {
        case .up:
            g.line(x - w, y + h, x, y, b, c)
            g.line(x, y, x + w, y + h, b, c)
        case .down:
            g.line(x - w, y, x, y + h, b, c)
            g.line(x, y + h, x + w, y, b, c)
        case .right:
            g.line(x, y - h, x + w, y, b, c)
            g.line(x + w, y, x, y + h, b, c)
        }
    }

    public static func chevronUp(_ g: inout MatrixBoard, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ b: Double, _ c: Int = 0) {
        g.line(x - w, y + h, x, y, b, c)
        g.line(x, y, x + w, y + h, b, c)
    }

    /// live session progress 0...1 (20 minutes)
    public static func liveP(_ c: MatrixContext) -> Double { cl(c.d.atgym / PROOF) }
    /// whole minutes done at the gym, 0...20
    public static func mins(_ c: MatrixContext) -> Double { min(20, (c.d.atgym / 60).rounded(.down)) }
    /// a flare at the start of every new minute
    public static func flare(_ c: MatrixContext) -> Double { exp(-((JSMath.rem(c.d.atgym / 60, 1) * 60) / 0.9)) }
    /// seconds since the 20-minute proof was reached, or -1
    public static func hitAge(_ c: MatrixContext) -> Double { c.d.atgym >= PROOF ? c.d.atgym - PROOF : -1 }
    /// evening time left, 0...1 of six hours
    public static func slP(_ c: MatrixContext) -> Double { cl(c.d.stillLeft / (6 * 3600)) }

    /// Seven day squares; `lit(i) < 0` draws an empty outline.
    public static func weekRow(_ g: inout MatrixBoard, _ y: Double, _ lit: (Int) -> Double, _ coral: Int = -1) {
        for i in 0..<7 {
            let b = lit(i)
            let x = 7 + Double(i) * 4.3
            if b < 0 {
                g.rect(x, y - 1, 3, 3, 0.35)
            } else {
                g.rect(x, y - 1, 3, 3, b, true)
                if i == coral { g.on(8 + Double(i) * 4.3, y, 1, 1) }
            }
        }
    }

    public static func rot(_ x: Double, _ y: Double, _ a: Double) -> (Double, Double) {
        (x * cos(a) - y * sin(a), x * sin(a) + y * cos(a))
    }

    public static func starPts(_ cx: Double, _ cy: Double, _ R: Double, _ r: Double, _ per: Int = 6) -> [(Double, Double)] {
        var V: [(Double, Double)] = []
        for k in 0..<10 {
            let a = (Double(k) / 10) * TAU, rr = k % 2 != 0 ? r : R
            V.append((cx + sin(a) * rr, cy - cos(a) * rr))
        }
        var o: [(Double, Double)] = []
        for k in 0..<10 {
            let (x0, y0) = V[k], (x1, y1) = V[(k + 1) % 10]
            for i in 0..<per {
                let u = Double(i) / Double(per)
                o.append((lerp(x0, x1, u), lerp(y0, y1, u)))
            }
        }
        return o
    }
}

// MARK: - verified.ts (Wednesday: BATTERY)

extension MX {
    public enum Verified {
        /// a decaying flash that starts at age 0
        static func fl(_ a: Double, _ d: Double = 0.15, _ k: Double = 0.3) -> Double { a >= 0 ? exp(-a / d) * k : 0 }
        /// taps in the done flow: five, seven for the week's last (`c.N || 5`, clamped 3...7)
        static func nOf(_ c: MatrixContext) -> Int { max(3, min(7, c.N != 0 ? c.N : 5)) }
        /// a soft band of light that crosses a coordinate every P seconds, after `from`
        static func sweep(_ T: Double, _ from: Double, _ P: Double, _ pos: Double, _ lo: Double, _ hi: Double, _ w: Double = 2.5) -> Double {
            if T < from { return 0 }
            let q = JSMath.rem((T - from) / P, 1) * (hi - lo + 2 * w * 3) + lo - w * 3
            let z = (pos - q) / w
            return exp(-(z * z)) * cl((T - from) / 0.6)
        }

        // ---- Wed: BATTERY ----
        static let BOLT = PixelRows(["....#####", "...#####.", "..#####..", ".#####...", "#########", "#########", "....####.", "...####..", "..####...", ".####....", "###......", "#........"])
        // body 9..33 x 18..29, terminal 34..35
        static let BX: Double = 9, BW: Double = 25, BY: Double = 18, BH: Double = 12
        static func segT(_ N: Int, _ k: Int) -> Double { 0.35 + Double(k) * (0.7 / Double(N)) }
        static func FULL(_ N: Int) -> Double { segT(N, N - 1) + 0.16 }

        public static let battery = MatrixScene(
            haptics: (0..<4).map { HapticCue(t: segT(5, $0) + 0.16, kind: .light) }
                + [HapticCue(t: FULL(5), kind: .heavy), HapticCue(t: FULL(5) + 0.07, kind: .success)]
        ) { g, c in
            let T = c.T, N = nOf(c), full = FULL(N), done = T > full + 0.04
            g.rect(BX, BY, BW, BH, 0.8)
            g.rect(BX + BW, BY + 3, 2, BH - 6, 0.8, true)
            if done {
                g.on(BX + BW + 1, BY + 5, 1, 1)
                g.on(BX + BW + 1, BY + 6, 1, 1)
            }
            // cells fill one after another, an anti-aliased edge sweeping left to right
            var lv = 0.0
            for k in 0..<N { lv += ez((T - segT(N, k)) / 0.16) }
            let IW = BW - 4
            let fx = (lv / Double(N)) * IW
            for ii in 0..<Int(IW) {
                let i = Double(ii)
                let f = cl(fx - i)
                let b = f * (0.86 + 0.14 * sweep(T, full + 0.6, 3.2, i, 0, IW, 2.2))
                var y = BY + 2
                while y < BY + BH - 2 {
                    if f > 0.01 { g.on(BX + 2 + i, y, b) }
                    y += 1
                }
            }
            for k in stride(from: 1, to: N, by: 1) {
                let i = JSMath.round((Double(k) / Double(N)) * IW)
                if i > fx {
                    var y = BY + 3
                    while y < BY + BH - 3 {
                        g.on(BX + 2 + i, y, 0.22)
                        y += 2
                    }
                }
            }
            // the bolt flickers up with each cell, then holds at full
            var pop = 0.0
            for k in 0..<N { pop = max(pop, fl(T - segT(N, k) - 0.16, 0.22, 0.45)) }
            let bb = done ? 1 : 0.28 + pop
            g.glyph(BOLT, CX - 4, 4, 1, bb)
            // two rings go out at full charge
            for r in 0..<2 {
                let a = T - full - 0.05 - Double(r) * 0.2
                let R = 15 + a * 22
                let lit = a > 0 && a < 0.75 ? (1 - a / 0.75) * 0.75 : 0
                for k in 0..<44 {
                    let q = (Double(k) / 44) * TAU
                    g.fr(CX + 0.5 + sin(q) * R, BY + BH / 2 - cos(q) * R * 0.55, lit)
                }
            }
            var tick = 0.0
            for k in stride(from: 0, to: N - 1, by: 1) { tick += fl(T - segT(N, k) - 0.16, 0.08, 0.06) }
            return SceneOut(
                opts: MatrixDealOptions(stagger: 0.3),
                flash: tick + fl(T - full, 0.15, 0.28),
                shake: T > full && T < full + 0.14 ? 0.25 : 0
            )
        }
    }
}

// MARK: - wake.ts (Monday: THE BELL)

extension MX {
    public enum Wake {
        // ---- the alarm's clock (own copy: mxlib's lastRing jumped back between 2.6 s and 2.85 s) ----
        static func ringT(_ k: Int) -> Double { k < 6 ? 0.35 + Double(k) * 0.5 : 2.85 + Double(k - 5) * 2.5 }
        static func ringK(_ T: Double) -> Int {
            if T < 0.35 { return -1 }
            if T < 2.85 { return Int(((T - 0.35) / 0.5 + 1e-6).rounded(.down)) }
            return 5 + Int(((T - 2.85) / 2.5 + 1e-6).rounded(.down))
        }
        static func ringAge(_ T: Double) -> Double {
            let k = ringK(T)
            return k < 0 ? 99 : T - ringT(k)
        }
        /// a sharp hit on every ring
        static func hit(_ T: Double, _ w: Double = 0.12) -> Double { exp(-ringAge(T) / w) }
        /// age of the latest ring with this parity: effects that alternate between two particle slots
        static func slotAge(_ T: Double, _ s: Int) -> Double {
            var k = ringK(T)
            if k >= 0 && k % 2 != s { k -= 1 }
            return k < 0 ? 99 : T - ringT(k)
        }
        /// ringHap covers the first five rings; the sixth and the slow rings get theirs too
        static let HAP: [HapticCue] = ringHap + [HapticCue(t: 2.85, kind: .medium)] + (0..<24).map { HapticCue(t: 5.35 + Double($0) * 2.5, kind: .heavy) }

        /// '#' lit (0), 'o' coral (1), '+' dim (2)
        static func bmp(_ rows: [String]) -> [(x: Double, y: Double, k: Int)] {
            var o: [(x: Double, y: Double, k: Int)] = []
            for (j, r) in rows.enumerated() {
                for (i, ch) in r.unicodeScalars.enumerated() {
                    let k: Int
                    switch ch {
                    case "#": k = 0
                    case "o": k = 1
                    case "+": k = 2
                    default: continue
                    }
                    o.append((x: Double(i), y: Double(j), k: k))
                }
            }
            return o
        }
        static func rotP(_ x: Double, _ y: Double, _ px: Double, _ py: Double, _ a: Double) -> (Double, Double) {
            let c = cos(a), s = sin(a), dx = x - px, dy = y - py
            return (px + dx * c - dy * s, py + dx * s + dy * c)
        }

        // ---- Mon: the bell ----
        static let BELL = bmp([
            "........#........",
            "......#####......",
            ".....##...##.....",
            "....#.......#....",
            "....#.......#....",
            "....#.......#....",
            "...#.........#...",
            "...#.........#...",
            "...#.........#...",
            "..#...........#..",
            "..#...........#..",
            ".#.............#.",
            "#...............#",
            "#################",
            "#################",
        ])
        /// the bell's tilt: a 1 Hz pendulum through the fast rings (fully over on every ring), then one swing per slow ring
        static func bellSwing(_ T: Double) -> Double {
            let A = 0.2
            if T < 0.1 { return 0 }
            if T < 0.35 { return A * sin((Double.pi / 2) * ((T - 0.1) / 0.25)) }
            if T < 2.85 { return A * cos((Double.pi * (T - 0.35)) / 0.5) }
            let k = ringK(T), R = ringT(k), s: Double = k % 2 != 0 ? -1 : 1
            var th = s * A * cos(2 * Double.pi * (T - R)) * exp(-(T - R) / 0.45)
            let nx = ringT(k + 1)
            if T > nx - 0.25 { th += -s * A * sin((Double.pi / 2) * ((T - (nx - 0.25)) / 0.25)) }
            return th
        }

        /// Mon: THE BELL. It swings over on every ring; the clapper strikes and sound arcs radiate out both sides.
        public static let bell = MatrixScene(haptics: HAP) { g, c in
            let T = c.T, h = hit(T), th = bellSwing(T)
            let px = 22.5, py = 8.5
            for p in BELL {
                let (X, Y) = rotP(14.5 + p.x, 9.5 + p.y, px, py, th)
                g.fr(X, Y, 0.82 + 0.18 * h)
            }
            let (kx, ky) = rotP(px, py + 17, px, py, th * 0.35)
            g.fr(kx, ky, 1, 1)
            // two slots of arcs, so a new ring never takes the dots of one still in flight
            for s in 0..<2 {
                let a = slotAge(T, s), live = a < 0.65
                for w in 0..<2 {
                    let wd = Double(w)
                    let r = live ? 11.5 - wd * 2.2 + 4 * ez(a / 0.55) : 11.5 - wd * 2.2
                    let b = live ? pow(1 - a / 0.65, 1.3) * (w != 0 ? 0.6 : 1) : 0
                    for side in [-1.0, 1.0] {
                        for i in 0..<9 {
                            let ang = side * (Double.pi / 2 + (Double(i) / 8 - 0.5) * (w != 0 ? 0.75 : 0.95))
                            g.fr(22.5 + sin(ang) * r, 17.5 - cos(ang) * r, b)
                        }
                    }
                }
            }
            return SceneOut(opts: MatrixDealOptions(stagger: 0.12), flash: 0.1 * h, shake: 0.16 * h)
        }
    }
}

// MARK: - countdown.ts (Wednesday: THE WATER CLOCK)

extension MX {
    public enum Countdown {
        /// K = whole seconds left (what the clock shows), q = seconds since the last flip (0...1)
        static func tick(_ c: MatrixContext) -> (s: Double, K: Double, q: Double) {
            let s = max(0, c.d.countdown), K = s.rounded(.down)
            return (s, K, 1 - (s - K))
        }
        /// cell-centre coordinates of the board's centre
        static let OX = CX + 0.5, OY = CY + 0.5
        static func polar(_ r: Double, _ a: Double, _ ox: Double = OX, _ oy: Double = OY) -> (Double, Double) {
            (ox + sin(a) * r, oy - cos(a) * r)
        }

        /// Wed: THE WATER CLOCK. The tank holds the time left (full is two hours). Every second a drop
        /// swells at the spout, lets go and lands on the flip; the surface barely moves.
        public static let waterClock = MatrixScene { g, c in
            let (s, K, q) = tick(c)
            // `floor` in the TS; renamed so it does not shadow the function
            let L = cl(s / 7200), top = 5.0, bend = 20.0, flr = 25.0, xl = 14.0, xr = 30.0
            let rise = ez((c.T - 0.1) / 0.7)
            // the vessel: open top, straight sides, a funnel down to the spout
            var yy = top
            while yy <= bend {
                g.on(xl, yy, 0.55)
                g.on(xr, yy, 0.55)
                yy += 1
            }
            g.line(xl, bend, CX - 1, flr + 1, 0.55)
            g.line(xr, bend, CX + 1, flr + 1, 0.55)
            g.on(CX - 1, flr + 2, 0.4)
            g.on(CX + 1, flr + 2, 0.4)
            // half the inside width at a row
            let span = { (y: Double) -> Double in y <= bend ? 7.5 : 7.5 - ((y - bend) / (flr + 1 - bend)) * 6.6 }
            // graduations every half hour, the hours longer
            var m = 30.0
            while m <= 120 {
                let y = flr + 0.5 - (m / 120) * (flr - top)
                g.on(xl - 2, y, 0.32)
                if JSMath.rem(m, 60) == 0 { g.on(xl - 3, y, 0.32) }
                m += 30
            }
            // the water: a quiet surface over a dim body
            let sy = flr + 0.5 - L * (flr - top - 0.5) * rise
            var y = (sy + 0.6).rounded(.up)
            while y <= flr {
                let hw = span(y + 0.5)
                var x = xl + 1
                while x < xr {
                    if abs(x + 0.5 - OX) < hw { g.on(x, y, 0.36) }
                    x += 1
                }
                y += 1
            }
            var x = xl + 1
            while x < xr {
                let inside: Double = abs(x + 0.5 - OX) < span(sy) ? 1 : 0
                g.fr(x + 0.5, sy + 0.22 * sin(x * 0.55 - c.t * 1.1) + 0.12 * sin(x * 1.3 + c.t * 0.7), 0.95 * rise * inside)
                x += 1
            }
            // two drops take turns: one swells and falls this second, the other has just landed
            let spout = flr + 2.3, land = 32.5
            for p in 0..<2 {
                if JSMath.rem(K, 2) == Double(p) {
                    if q < 0.56 {
                        g.fr(OX, spout + 0.5 * ez(q / 0.56), 0.3 + 0.7 * ez(q / 0.5), 1)
                    } else {
                        let a = q - 0.56
                        g.fr(OX, spout + 0.5 + 0.5 * ((land - spout - 0.5) / (0.44 * 0.44)) * a * a, 1, 1)
                    }
                } else if q < 0.14 {
                    g.fr(OX, land, 1 - q / 0.14)
                } else {
                    g.fr(OX, spout, 0)
                }
            }
            // the splash on the flip
            for k in 0..<4 {
                let sd: Double = k % 2 != 0 ? 1 : -1, far = k < 2 ? 1.0 : 0.55, a = cl(q / 0.42)
                g.fr(OX + sd * (0.4 + 3.2 * far * ez(a)), land + 0.3 - 1.5 * far * sin(Double.pi * a), q < 0.42 ? 0.7 * (1 - a) : 0)
            }
            var xx = CX - 4
            while xx <= CX + 4 {
                g.on(xx, 33, 0.22 + 0.4 * exp(-q / 0.25) * (1 - abs(xx - CX) / 5))
                xx += 1
            }
            return SceneOut(opts: MatrixDealOptions(stagger: 0.3))
        }
    }
}

// MARK: - Parity self-test (golden values from the web sources)

#if DEBUG
/// Golden values produced by running the TypeScript sources under Node (see PORTING-GUIDE.md §6).
/// Call `MatrixParity.run()` from a unit test (Swift Testing: `#expect(MatrixParity.run().isEmpty)`).
/// Returns a list of failures; empty means the port matches the web.
public enum MatrixParity {
    /// Same checksum as the golden script: x*1.3 + y*0.7 + b*5 + (c ? 11 : 0) + (id % 9973) * 0.001.
    public static func checksum(_ o: ContiguousArray<MatrixTarget>) -> Double {
        o.reduce(0) { $0 + $1.x * 1.3 + $1.y * 0.7 + $1.b * 5 + ($1.c != 0 ? 11 : 0) + Double($1.id % 9973) * 0.001 }
    }

    static func ctx(_ T: Double, t: Double? = nil, countdown: Double = 3725.3) -> MatrixContext {
        MatrixContext(t: t ?? 100 + T, T: T, d: MatrixLiveData(setupDone: [true, true, true], countdown: countdown, atgym: 0, stillLeft: 0), day: 2, pos: .middle, N: 5, D: MatrixDayData(day: 23, week: 3, sessions: 14))
    }

    public static func run() -> [String] {
        var fail: [String] = []
        func near(_ a: Double, _ b: Double, _ tol: Double, _ what: String) {
            if !(abs(a - b) <= tol * max(1, abs(b))) { fail.append("\(what): got \(a), want \(b)") }
        }
        // hash: exact integer math
        let hv: [(Double, Double, Double)] = [(0, 1, 0.768274554284), (1, 1, 0.663851173595), (5, 2, 0.116751558613), (719, 8, 0.808725735871), (1399, 10, 0.0856040625367), (-3, 7, 0.0310087276157)]
        for (i, k, want) in hv { near(MatrixHash.hash(i, k), want, 1e-11, "hash(\(i),\(k))") }
        let rv: [(Double, Double)] = [(0, 0.768274554284), (123, 0.424398674164), (-7, 0.578166699503), (2.5, 0.410041970666), (1e6, 0.623192857252)]
        for (i, want) in rv { near(MX.rnd(i), want, 1e-11, "rnd(\(i))") }
        near(MX.back(0.5), 1.0875, 1e-12, "back")
        near(MX.spr(0.3), 1.16197739129, 1e-10, "spr")
        near(MX.eio(0.3), 0.108, 1e-12, "eio")
        near(MX.pulse(3.1, 2.5, 0.13, 0.35), 0.146156557072, 1e-10, "pulse")
        // rings (lastRing is the FIXED one: 2.7 -> 2.35, the web said 0.35)
        near(MX.lastRingWeb(2.7), 0.35, 0, "lastRingWeb(2.7)")
        near(MX.lastRing(2.7), 2.35, 0, "lastRing(2.7)")
        near(MX.lastRing(5.4), 5.35, 1e-12, "lastRing(5.4)")
        if MX.ringIndex(2.7) != 4 || MX.ringIndex(2.86) != 5 || MX.ringIndex(5.4) != 6 { fail.append("ringIndex") }
        near(MX.ringBeat(2.86), 0.925961078642, 1e-9, "ringBeat(2.86)")

        // scenes: target count, checksum, and the first target
        let cases: [(String, MatrixScene, Double, Int, Double)] = [
            ("verifiedWed", MX.Verified.battery, 0.5, 277, 13553.262875),
            ("verifiedWed", MX.Verified.battery, 1.0, 396, 20611.7731124),
            ("verifiedWed", MX.Verified.battery, 2.0, 396, 20766.1413505),
            ("wakeMon", MX.Wake.bell, 0.4, 137, 6414.69079125),
            ("wakeMon", MX.Wake.bell, 3.0, 137, 6618.57780901),
            ("wakeMon", MX.Wake.bell, 6.0, 137, 6450.72674053),
            ("countdownWed", MX.Countdown.waterClock, 0.3, 132, 6604.98403189),
            ("countdownWed", MX.Countdown.waterClock, 2.0, 177, 8780.82567354),
        ]
        for (name, scene, T, n, sum) in cases {
            var g = MatrixBoard()
            _ = scene.draw(&g, ctx(T))
            let out = g.out()
            if out.count != n { fail.append("\(name) T=\(T): \(out.count) targets, want \(n)") }
            near(checksum(out), sum, 1e-9, "\(name) T=\(T) checksum")
        }
        do {
            var g = MatrixBoard()
            let o = MX.Verified.battery.draw(&g, ctx(1.0))
            near(o.flash, 0.03024464460440257, 1e-12, "battery flash T=1")
            if g.out().first != MatrixTarget(x: 9.5, y: 18.5, b: 0.8, c: 0, id: 4617) { fail.append("battery first target") }
        }

        // engine: constructor positions are exact; a 1.5 s run at 60 fps within libm tolerance
        let e = MatrixEngine(n: 720, cols: 38, rows: 35)
        e.brightnessMode = .perFrame
        if e.x[0] != Float(29.194433212280273) || e.y[0] != Float(18.778684616088867) || e.x[2] != Float(37.191436767578125) {
            fail.append("engine init positions")
        }
        for k in 0...90 {
            let t = Double(k) / 60
            var g = MatrixBoard()
            let o = MX.Verified.battery.draw(&g, ctx(t, t: t))
            e.update(key: "verified:2:middle:\(o.phase ?? "0")", targets: g.out(), t: t, options: o.opts ?? MatrixDealOptions(stagger: 0.25))
        }
        var bs = 0.0, xs = 0.0
        for i in 0..<720 {
            bs += Double(e.b[i])
            xs += Double(e.x[i]) * Double(i % 7 + 1)
        }
        near(bs, 302.036830505, 1e-5, "engine brightness sum")
        near(xs, 60301.9963509, 1e-5, "engine x sum")
        return fail
    }
}
#endif
