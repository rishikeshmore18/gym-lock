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
public nonisolated struct MatrixLiveData: Sendable, Equatable {
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
    /// `mxScene(state, theme)`: seven scenes per moment, indexed by the theme of the day
    /// (0 radiant, 1 tiles, 2 signal, 3 levels, 4 vectors, 5 loops, 6 week).
    /// All 133 are machine-translated from web-reference/hero13/mx/*.ts (Matrix/Scenes/MX*.swift).
    private static let table: [MatrixMoment: [MatrixScene]] = [
        .setup: MX.Setup.SCENES,
        .firstnight: MX.Firstnight.SCENES,
        .bedtime: MX.Bedtime.SCENES,
        .wake: MX.Wake.SCENES,
        .countdown: MX.Countdown.SCENES,
        .ready: MX.Ready.SCENES,
        .commute: MX.Commute.SCENES,
        .atgym: MX.Atgym.SCENES,
        .verified: MX.Verified.SCENES,
        .stilltime: MX.Stilltime.SCENES,
        .rest: MX.Rest.SCENES,
        .paused: MX.Paused.SCENES,
        .freshstart: MX.Freshstart.SCENES,
        .missed: MX.Missed.SCENES,
        .weekkept: MX.Weekkept.SCENES,
        .comeback: MX.Comeback.SCENES,
        .drift: MX.Drift.SCENES,
        .halfway: MX.Halfway.SCENES,
        .automatic: MX.Automatic.SCENES,
    ]

    public static func scene(_ moment: MatrixMoment, day: Int) -> MatrixScene {
        guard day >= 0, day < 7, let row = table[moment], day < row.count else { return .empty }
        return row[day]
    }

    public static func isPorted(_ moment: MatrixMoment, day: Int) -> Bool {
        guard day >= 0, day < 7, let row = table[moment], day < row.count else { return false }
        return true
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
            ("verifiedWed", MX.Verified.SCENES[2], 0.5, 277, 13553.262875),
            ("verifiedWed", MX.Verified.SCENES[2], 1.0, 396, 20611.7731124),
            ("verifiedWed", MX.Verified.SCENES[2], 2.0, 396, 20766.1413505),
            ("wakeMon", MX.Wake.SCENES[0], 0.4, 137, 6414.69079125),
            ("wakeMon", MX.Wake.SCENES[0], 3.0, 137, 6618.57780901),
            ("wakeMon", MX.Wake.SCENES[0], 6.0, 137, 6450.72674053),
            ("countdownWed", MX.Countdown.SCENES[2], 0.3, 132, 6604.98403189),
            ("countdownWed", MX.Countdown.SCENES[2], 2.0, 177, 8780.82567354),
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
            let o = MX.Verified.SCENES[2].draw(&g, ctx(1.0))
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
            let o = MX.Verified.SCENES[2].draw(&g, ctx(t, t: t))
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

    /// All 133 generated scenes against `allGolden` (MatrixParityAll.swift), replayed in the
    /// golden script's order. setup.ts remembers per-day state between draws, so its memory is
    /// cleared first, exactly like a fresh Node run.
    public static func runAll() -> [String] {
        var fail: [String] = []
        MX.Setup.MEM.clear()
        for (m, theme, k, n, sum, ph, flash, shake) in allGolden {
            guard let moment = MatrixMoment(rawValue: m) else {
                fail.append("unknown moment \(m)")
                continue
            }
            var g = MatrixBoard()
            let o = MatrixSceneRegistry.scene(moment, day: theme).draw(&g, allContexts[k])
            let out = g.out()
            let what = "\(m)[\(theme)] ctx \(k)"
            if out.count != n { fail.append("\(what): \(out.count) targets, want \(n)") }
            let cs = checksum(out)
            if !(abs(cs - sum) <= 1e-9 * max(1, abs(sum))) { fail.append("\(what) checksum: got \(cs), want \(sum)") }
            if o.phase != ph { fail.append("\(what) phase: got \(o.phase ?? "nil"), want \(ph ?? "nil")") }
            if !(abs(o.flash - flash) <= 1e-9) { fail.append("\(what) flash: got \(o.flash), want \(flash)") }
            if !(abs(o.shake - shake) <= 1e-9) { fail.append("\(what) shake: got \(o.shake), want \(shake)") }
        }
        MX.Setup.MEM.clear()
        return fail
    }
}
#endif
