//
//  RidgeRuntime.swift
//  GymLock · Ridge hero
//
//  The hand-written half of the Ridge port (RIDGE-PORT.md): the RW namespace and its non-generated
//  statics (rng, grain, palette, seeds), the scene/camera/shape builders the generated code uses,
//  the layer-caching painters (wash.ts Painter, wash2.ts Painter2, wash3.ts Painter3) and
//  props13.ts build/frameOf, plus card13's clampCam.
//

import CoreGraphics
import Foundation

/// Namespace for everything Ridge (generated code lives in `extension RW` under Gen/).
nonisolated enum RW {}

// MARK: - Array helpers the generated code relies on

nonisolated extension Array where Element == Double {
    /// `[...pt(x, y)]`: a Pt tuple spread into a flat number list.
    init(_ t: (Double, Double)) { self = [t.0, t.1] }

    /// `a.push(...pt(x, y))`.
    mutating func append(contentsOf t: (Double, Double)) {
        append(t.0)
        append(t.1)
    }
}

nonisolated extension Array {
    /// JS Array.prototype.splice (integral start and count, negative start from the end).
    @discardableResult
    mutating func splice(_ start: Double, _ deleteCount: Double, _ items: Element...) -> [Element] {
        var s = Int(start)
        if s < 0 { s = Swift.max(0, count + s) }
        s = Swift.min(s, count)
        let d = Swift.max(0, Swift.min(Int(deleteCount), count - s))
        let removed = Array(self[s..<(s + d)])
        replaceSubrange(s..<(s + d), with: items)
        return removed
    }
}

// MARK: - JS helpers the Ridge sources need on top of JSRuntime

nonisolated extension JS {
    @inline(__always) static func imul(_ a: Double, _ b: Double) -> Double {
        Double(Int32(bitPattern: JSMath.toUint32(a) &* JSMath.toUint32(b)))
    }
    @inline(__always) static func bitXor(_ a: Double, _ b: Double) -> Double { bxor(a, b) }
    @inline(__always) static func bitOr(_ a: Double, _ b: Double) -> Double { bor(a, b) }
    @inline(__always) static func bitAnd(_ a: Double, _ b: Double) -> Double { band(a, b) }
}

// MARK: - Statics (wash.ts / scenes11.ts / scenes12.ts)

nonisolated extension RW {
    static let PROOF: Double = 20 * 60
    static let TAU: Double = Double.pi * 2

    /// scenes12.ts WSEED: the painting seed of each day's world.
    static let WSEED: [Double] = [17, 3, 8, 11, 5, 14, 19]

    /// scenes11.ts grow: the pine's growth over the 66 days.
    static func grow(_ day: Double) -> Double { 0.1 + 0.9 * pow(min(66, day) / 66, 0.75) }

    /// wash.ts rng (mulberry32-style, exact uint32 maths).
    static func rng(_ seed: Double) -> () -> Double {
        var s = JSMath.toUint32(seed * 2654435761)
        if s == 0 { s = 1 }
        return {
            s = s &+ 0x6D2B_79F5
            var t = s
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    private static func pal(_ v: [[Double]]) -> Pal {
        func c(_ i: Int) -> (Double, Double, Double) { (v[i][0], v[i][1], v[i][2]) }
        return Pal(paper: c(0), sky0: c(1), sky1: c(2), far: c(3), farShade: c(4), snow: c(5), mid: c(6), mid2: c(7), near: c(8), rock: c(9), rockLight: c(10), rockDark: c(11), mist: c(12), crack: c(13), sun: c(14))
    }

    // wash.ts P (paper, sky0, sky1, far, farShade, snow, mid, mid2, near, rock, rockLight, rockDark, mist, crack, sun)
    private static let lightDay = pal([[246, 246, 244], [214, 214, 213], [246, 246, 244], [176, 176, 176], [140, 140, 142], [244, 244, 242], [126, 126, 128], [92, 92, 95], [24, 24, 26], [92, 92, 95], [160, 160, 162], [38, 38, 41], [250, 250, 248], [16, 16, 18], [255, 255, 253]])
    private static let lightNight = pal([[246, 246, 244], [96, 96, 101], [168, 168, 172], [128, 128, 132], [104, 104, 108], [190, 190, 194], [84, 84, 88], [62, 62, 66], [16, 16, 18], [70, 70, 74], [112, 112, 116], [30, 30, 33], [200, 200, 204], [10, 10, 12], [236, 236, 238]])
    private static let darkDay = pal([[14, 14, 16], [26, 26, 29], [70, 70, 74], [88, 88, 92], [66, 66, 70], [150, 150, 154], [48, 48, 52], [34, 34, 37], [7, 7, 8], [74, 74, 78], [122, 122, 126], [30, 30, 33], [128, 128, 132], [6, 6, 7], [230, 230, 232]])
    private static let darkNight = pal([[14, 14, 16], [9, 9, 11], [30, 30, 34], [44, 44, 48], [34, 34, 38], [86, 86, 90], [26, 26, 29], [18, 18, 20], [4, 4, 5], [50, 50, 54], [84, 84, 88], [20, 20, 22], [64, 64, 68], [3, 3, 4], [200, 200, 204]])

    /// Guards the three mutable caches below: the hero card paints on its render thread while the
    /// done flow's story paints on main. Held only around the dictionary reads and writes, never
    /// while painting, so it cannot nest.
    static let cacheLock = NSLock()

    nonisolated(unsafe) private static var palCache: [String: Pal] = [:]

    /// wash.ts palette: day and night mixed by `night`.
    static func palette(_ theme: String, _ night: Double) -> Pal {
        let key = "\(theme):\(night)"
        if let hit = cacheLock.withLock({ palCache[key] }) { return hit }
        let a = theme == "light" ? lightDay : darkDay
        let b = theme == "light" ? lightNight : darkNight
        let m = { (x: (Double, Double, Double), y: (Double, Double, Double)) in mixc(x, y, night) }
        let p = Pal(paper: m(a.paper, b.paper), sky0: m(a.sky0, b.sky0), sky1: m(a.sky1, b.sky1), far: m(a.far, b.far), farShade: m(a.farShade, b.farShade), snow: m(a.snow, b.snow), mid: m(a.mid, b.mid), mid2: m(a.mid2, b.mid2), near: m(a.near, b.near), rock: m(a.rock, b.rock), rockLight: m(a.rockLight, b.rockLight), rockDark: m(a.rockDark, b.rockDark), mist: m(a.mist, b.mist), crack: m(a.crack, b.crack), sun: m(a.sun, b.sun))
        cacheLock.withLock {
            if palCache.count > 64 { palCache.removeAll() }
            palCache[key] = p
        }
        return p
    }

    nonisolated(unsafe) private static var grainTex: C2DSurface?

    /// wash.ts grain: the paper texture tile (noise plus a few fibres), made once.
    static func grain() -> C2DSurface {
        if let g = cacheLock.withLock({ grainTex }) { return g }
        let s = C2DSurface(width: 256, height: 256)
        let r = rng(99)
        if let cg = s.context, let data = cg.data {
            let bpr = cg.bytesPerRow
            let p = data.bindMemory(to: UInt8.self, capacity: bpr * 256)
            for i in 0..<(256 * 256) {
                let v = r()
                let a = v > 0.9 ? floor((v - 0.9) * 300) : floor(v * 10)
                let o = (i / 256) * bpr + (i % 256) * 4
                p[o] = 0
                p[o + 1] = 0
                p[o + 2] = 0
                p[o + 3] = UInt8(max(0, min(255, a)))
            }
        }
        if let x = C2D(surface: s) {
            x.strokeStyle = "rgba(0,0,0,0.035)"
            for _ in 0..<70 {
                x.beginPath()
                let a = r() * Double.pi, l = 6 + r() * 20, px = r() * 256, py = r() * 256
                x.moveTo(px, py)
                let cx = px + cos(a) * l * 0.5 + r() * 4
                x.quadraticCurveTo(cx, py + sin(a) * l * 0.5, px + cos(a) * l, py + sin(a) * l)
                x.stroke()
            }
        }
        s.seal()
        return cacheLock.withLock {
            if let g = grainTex { return g }
            grainTex = s
            return s
        }
    }

    /// props13.ts FIX: shapes `embolden` leaves alone.
    @discardableResult
    static func fx(_ q: RShape) -> RShape {
        q.fixed = true
        return q
    }

    @discardableResult
    static func fx(_ q: [RShape]) -> [RShape] {
        for s in q { s.fixed = true }
        return q
    }
}

// MARK: - Builders (TS object literals and spreads)

/// Scene3: the painted world's knobs. Required fields read 0 (kind: "sunrise") when unset.
nonisolated final class RScene {
    var _seed: Double?, _tree: Double?, _cracks: Double?, _broken: Double?, _rubble: Double?
    var _sun: Double?, _night: Double?, _mist: Double?, _rain: Double?, _peak: Double?
    var _kind: String?

    var seed: Double { get { _seed ?? 0 } set { _seed = newValue } }
    var tree: Double { get { _tree ?? 0 } set { _tree = newValue } }
    var cracks: Double { get { _cracks ?? 0 } set { _cracks = newValue } }
    var broken: Double { get { _broken ?? 0 } set { _broken = newValue } }
    var rubble: Double { get { _rubble ?? 0 } set { _rubble = newValue } }
    var sun: Double { get { _sun ?? 0 } set { _sun = newValue } }
    var night: Double { get { _night ?? 0 } set { _night = newValue } }
    var mist: Double { get { _mist ?? 0 } set { _mist = newValue } }
    var rain: Double { get { _rain ?? 0 } set { _rain = newValue } }
    var peak: Double { get { _peak ?? 0 } set { _peak = newValue } }
    var kind: String { get { _kind ?? "sunrise" } set { _kind = newValue } }

    var rockIn: Double?, noRock: Bool?, noYou: Bool?, hgBg: String?, prop: String?, candle: Double?
    var moonX: Double?, moonY: Double?, boatX: Double?, sand: Double?, charge: Double?, stones: Double?
    var trail: Double?, birds: Double?, chipsAt: Double?, snow: Double?, frozen: Bool?, fireflies: Double?
    var drip: Bool?, tide: Double?, steps: Double?, beacon: Double?, lanterns: [Double]?, stars: Double?
    var starLines: Double?, shoot: Double?, skips: [Double]?, skipN: Double?, skipDone: Double?
    var burst: Double?, burstAt: String?, flash: Double?, ripples: Double?

    init() {}

    /// `{...a, ...b, ...}` then the literal's own fields.
    static func make(_ bases: [RScene] = [], _ f: (RScene) -> Void) -> RScene {
        let o = RScene()
        for b in bases { o.merge(b) }
        f(o)
        return o
    }

    private func merge(_ b: RScene) {
        if let v = b._seed { _seed = v }
        if let v = b._tree { _tree = v }
        if let v = b._cracks { _cracks = v }
        if let v = b._broken { _broken = v }
        if let v = b._rubble { _rubble = v }
        if let v = b._sun { _sun = v }
        if let v = b._night { _night = v }
        if let v = b._mist { _mist = v }
        if let v = b._rain { _rain = v }
        if let v = b._peak { _peak = v }
        if let v = b._kind { _kind = v }
        if let v = b.rockIn { rockIn = v }
        if let v = b.noRock { noRock = v }
        if let v = b.noYou { noYou = v }
        if let v = b.hgBg { hgBg = v }
        if let v = b.prop { prop = v }
        if let v = b.candle { candle = v }
        if let v = b.moonX { moonX = v }
        if let v = b.moonY { moonY = v }
        if let v = b.boatX { boatX = v }
        if let v = b.sand { sand = v }
        if let v = b.charge { charge = v }
        if let v = b.stones { stones = v }
        if let v = b.trail { trail = v }
        if let v = b.birds { birds = v }
        if let v = b.chipsAt { chipsAt = v }
        if let v = b.snow { snow = v }
        if let v = b.frozen { frozen = v }
        if let v = b.fireflies { fireflies = v }
        if let v = b.drip { drip = v }
        if let v = b.tide { tide = v }
        if let v = b.steps { steps = v }
        if let v = b.beacon { beacon = v }
        if let v = b.lanterns { lanterns = v }
        if let v = b.stars { stars = v }
        if let v = b.starLines { starLines = v }
        if let v = b.shoot { shoot = v }
        if let v = b.skips { skips = v }
        if let v = b.skipN { skipN = v }
        if let v = b.skipDone { skipDone = v }
        if let v = b.burst { burst = v }
        if let v = b.burstAt { burstAt = v }
        if let v = b.flash { flash = v }
        if let v = b.ripples { ripples = v }
    }
}

/// stage13.ts Cam: scale, offset (stage units), roll, and an optional pivot.
nonisolated final class RCam {
    var _s: Double?, _x: Double?, _y: Double?, _r: Double?
    var s: Double { get { _s ?? 0 } set { _s = newValue } }
    var x: Double { get { _x ?? 0 } set { _x = newValue } }
    var y: Double { get { _y ?? 0 } set { _y = newValue } }
    var r: Double { get { _r ?? 0 } set { _r = newValue } }
    var px: Double?
    var py: Double?

    init() {}

    static func make(_ bases: [RCam] = [], _ f: (RCam) -> Void) -> RCam {
        let o = RCam()
        for b in bases {
            if let v = b._s { o._s = v }
            if let v = b._x { o._x = v }
            if let v = b._y { o._y = v }
            if let v = b._r { o._r = v }
            if let v = b.px { o.px = v }
            if let v = b.py { o.py = v }
        }
        f(o)
        return o
    }
}

/// stage13.ts Shape: one prop drawn over the world.
nonisolated final class RShape {
    var k: String = ""
    var x: Double = 0
    var y: Double = 0
    var r: Double = 0
    var p: [Double] = []
    var m: String = "light"
    var a: Double?
    var ry: Double?
    var w: Double?
    var a0: Double?
    var a1: Double?
    var dash: Double?
    var soft: Bool?
    /// props13.ts FIX membership. Never copied by `make` (a spread makes a new, unfixed object).
    var fixed = false

    init() {}

    static func make(_ bases: [RShape] = [], _ f: (RShape) -> Void) -> RShape {
        let o = RShape()
        for b in bases {
            o.k = b.k
            o.x = b.x
            o.y = b.y
            o.r = b.r
            o.p = b.p
            o.m = b.m
            if let v = b.a { o.a = v }
            if let v = b.ry { o.ry = v }
            if let v = b.w { o.w = v }
            if let v = b.a0 { o.a0 = v }
            if let v = b.a1 { o.a1 = v }
            if let v = b.dash { o.dash = v }
            if let v = b.soft { o.soft = v }
        }
        f(o)
        return o
    }
}

/// scenes11.ts Data11: the user's real numbers for the scene.
nonisolated struct RData {
    var day: Double
    var week: Double
    var sessions: Double
    var icon: String = ""
    var live: Bool?
}

/// props13.ts PC: everything a scene reads for one frame.
nonisolated struct RPC {
    var t: Double
    var T: Double
    var at: Double
    var d: MatrixLiveData
    var day: Double
    var pos: String
    var n: Double
    var D: RData
    var N: Double
    var matrix: Bool
}

// MARK: - build / frameOf (props13.ts 2639-2751) and clampCam (card13.tsx)

nonisolated extension RW {
    struct Built {
        var scene: RScene
        var shapes: [RShape]
        var cam: RCam
        var type: String
    }

    private struct Frame {
        var px: Double
        var py: Double
        var s: Double
        var x0: Double?
        var x1: Double?
        var y0: Double?
        var y1: Double?
    }

    nonisolated(unsafe) private static var FRAME: [String: Frame] = [:]

    private static func frameOf(_ key: String, _ sc: Scn, _ c: RPC) -> Frame {
        if let hit = cacheLock.withLock({ FRAME[key] }) { return hit }
        var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
        func add(_ x: Double, _ y: Double) {
            if x < -5 || x > 105 || y < -5 || y > 97 { return }
            x0 = min(x0, x)
            x1 = max(x1, x)
            y0 = min(y0, y)
            y1 = max(y1, y)
        }
        for T in [1.2, 2.4, 3.6] {
            var c2 = c
            c2.T = T
            c2.t = 100 + T
            c2.at = 100
            c2.d.atgym = min(c.d.atgym, PROOF - 30)
            for q in embolden(sc.draw(c2)) {
                if q.k == "flash" || q.k == "glow" { continue }
                if q.k == "disc" || q.k == "ring" {
                    let r = q.r
                    if r > 30 { continue }
                    let ry = q.k == "ring" ? (q.ry ?? r) : r
                    add(q.x - r, q.y - ry)
                    add(q.x + r, q.y + ry)
                    continue
                }
                var a0 = Double.infinity, a1 = -Double.infinity
                var i = 0
                while i < q.p.count {
                    a0 = min(a0, q.p[i])
                    a1 = max(a1, q.p[i])
                    i += 2
                }
                if q.k != "dots" && a1 - a0 > 70 { continue }
                i = 0
                while i + 1 < q.p.count {
                    add(q.p[i], q.p[i + 1])
                    i += 2
                }
            }
        }
        var f = Frame(px: 55, py: 46, s: 1)
        if x0 < x1 {
            let size = max(x1 - x0, (y1 - y0) * 1.15, 1)
            f = Frame(px: (x0 + x1) / 2, py: (y0 + y1) / 2, s: min(sc.zoom ?? 1.85, max(1, 46 / size)), x0: x0, x1: x1, y0: y0, y1: y1)
        }
        cacheLock.withLock { FRAME[key] = f }
        return f
    }

    /// props13.ts build: the moment's scene over the day's world, its props, and the camera move.
    static func build(_ s: String, _ day: Int, _ c: RPC) -> Built {
        let d = max(0, min(6, day))
        let sc = scnFor(s, Double(d))
        let light: RScene = d == 6 ? RScene.make([]) { $0.sun = 0.1 } : (LIGHT[s] ?? RScene())
        let base = RScene.make([]) { o in
            o.kind = "sunrise"
            o.seed = WSEED[d]
            o.tree = grow(c.D.day)
            o.cracks = 0
            o.broken = 0
            o.rubble = min(7, floor(c.D.sessions / 3))
            o.sun = 0.4
            o.night = 0
            o.mist = 0.8
            o.rain = 0
            o.peak = 1
            o.birds = 0
        }
        var parts: [RScene] = [base, light, BASE[d](s)]
        if let bd = sc.bd { parts.append(bd(c)) }
        let scene = RScene.make(parts) { _ in }

        var cams: [RCam] = [RCam.make([]) { o in o.s = 1; o.x = 0; o.y = 0; o.r = 0 }]
        if let def = CAM_DEF[s] { cams.append(def(c)) }
        if let own = sc.cam { cams.append(own(c)) }
        let mv = RCam.make(cams) { _ in }

        let fr = frameOf("\(s):\(d):\(c.pos)", sc, c)
        let k = ez(c.T / 1.3)
        let push = 1 + (fr.s - 1) * k
        let cam = RCam.make([mv]) { o in
            o.s = mv.s * push
            o.px = mv.px ?? fr.px
            o.py = mv.py ?? fr.py
            o.x = mv.x + (mv.px == nil ? (64 - fr.px) * 0.8 * k * (fr.s - 1) : 0)
            o.y = mv.y + (mv.py == nil ? (42 - fr.py) * 0.6 * k * (fr.s - 1) : 0)
        }
        if let fy0 = fr.y0, let fy1 = fr.y1, let fx0 = fr.x0, let fx1 = fr.x1 {
            let px = cam.px ?? 55, py = cam.py ?? 46, sc2 = cam.s
            func ty(_ y: Double) -> Double { py + (y - py) * sc2 + cam.y }
            func tx(_ x: Double) -> Double { px + (x - px) * sc2 + cam.x }
            if ty(fy0) < -1.5 {
                cam.y += -1.5 - ty(fy0)
            } else if ty(fy1) > 95 {
                cam.y -= min(ty(fy1) - 95, ty(fy0) + 1.5)
            }
            if tx(fx1) > 104 { cam.x -= tx(fx1) - 104 }
            if tx(fx0) < 3 { cam.x += 3 - tx(fx0) }
        }
        return Built(scene: scene, shapes: embolden(sc.draw(c)), cam: cam, type: sc.type ?? TYPE_DEF[s] ?? "rise")
    }

    /// card13.tsx clampCam: keep the painted backdrop covering the card while the camera moves.
    static func clampCam(_ c: RCam) -> RCam {
        let s = max(1, c.s, 1 + abs(c.r) * 0.9)
        let pxs = 492 + (c.px ?? 55) * 4.75, pys = 26 + (c.py ?? 46) * 4.75
        let lo = (-(1000 - pxs) * (s - 1)) / 4.75, hi = (pxs * (s - 1)) / 4.75
        let loY = (-(488 - pys) * (s - 1)) / 4.75, hiY = (pys * (s - 1)) / 4.75
        return RCam.make([c]) { o in
            o.s = s
            o.x = min(hi, max(lo, c.x))
            o.y = min(hiY, max(loY, c.y))
        }
    }
}

// MARK: - Painters

/// wash.ts Painter: the ridge world in cached layers.
nonisolated final class RPainter {
    var xf: (Double, Double, Double, Double, Double, Double) = (1, 0, 0, 1, 0, 0)
    private var slots: [String: (key: String, s: C2DSurface)] = [:]

    func layer(_ slot: String, _ key: String, _ w: Double, _ h: Double, _ paint: (C2D) -> Void) -> C2DSurface {
        RLayerCache.layer(&slots, slot, key, w, h, paint)
    }

    func render(_ ctx: C2D, _ w: Double, _ h: Double, _ S: RScene, _ theme: String, _ t: Double) {
        let night = JSMath.round(S.night * 4) / 4
        let pal = RW.palette(theme, night)
        let L = RW.layoutFor(w, h)
        let base = "\(JS.str(w))x\(JS.str(h)):\(theme):\(JS.str(S.seed)):\(JS.str(night))"
        let sky = layer("sky", base, w, h) { c in RW.paintSky(c, w, h, L, pal, RW.rng(S.seed)) }
        let far = layer("far", "\(base):\(JS.toFixed(S.peak, 2))", w, h) { c in RW.paintFar(c, w, h, L, pal, RW.rng(S.seed + 1), S.seed, S) }
        let near = layer("near", "\(base):\(JS.toFixed(S.tree, 3)):\(JS.str(S.rubble))", w, h) { c in RW.paintNear(c, w, h, L, pal, RW.rng(S.seed + 2), S.seed, S) }
        let rock = layer("rock", "\(base):\(JS.toFixed(S.cracks, 3)):\(JS.toFixed(S.broken, 3)):\(JS.toFixed(S.rockIn ?? 1, 3))", w, h) { c in RW.paintBoulder(c, w, h, L, pal, S.seed, S) }
        let mistKey = "\(JS.str(w))x\(JS.str(h)):\(theme):\(JS.str(night))"
        let mist = layer("mist", mistKey, w * 2, h) { c in RW.paintMist(c, w * 2, h, [L.horizon, L.ridgeY + h * 0.1], pal, RW.rng(7)) }
        let front = layer("front", mistKey, w * 2, h) { c in RW.paintMist(c, w * 2, h, [L.ledgeTop + h * 0.1, h * 0.98], pal, RW.rng(8)) }
        let paper = layer("paper", "\(JS.str(w))x\(JS.str(h))", w, h) { c in
            c.fillStyle = c.createPattern(RW.grain(), "repeat")
            c.fillRect(0, 0, w, h)
        }

        ctx.setTransform(xf)
        let px = sin(t * 0.12) * w * 0.004
        ctx.drawImage(sky, 0, 0)
        // the sun (or moon), low behind the peak
        let sy = L.horizon - (S.sun + 0.15) * (L.horizon - L.peakTop) * 0.9
        let sr = min(w, h) * (L.tall ? 0.05 : 0.07)
        let glow = ctx.createRadialGradient(L.sunX, sy, 0, L.sunX, sy, sr * 6)
        glow.addColorStop(0, RW.css(pal.sun, 0.55 * (1 - night * 0.5)))
        glow.addColorStop(1, RW.css(pal.sun, 0))
        ctx.fillStyle = C2DStyle(glow)
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = C2DStyle(RW.css(pal.sun, 0.92))
        ctx.beginPath()
        ctx.arc(L.sunX, sy, sr * (night > 0.5 ? 0.45 : 0.55), 0, Double.pi * 2)
        ctx.fill()
        ctx.drawImage(far, px * 0.4, 0)
        let mo = S.mist
        if mo > 0.01 {
            let off = JSMath.rem(t * w * 0.006, w) - w
            ctx.globalAlpha = min(1, mo)
            ctx.drawImage(mist, off, 0)
            ctx.globalAlpha = 1
        }
        ctx.drawImage(near, px, 0)
        if !(S.noRock ?? false) { ctx.drawImage(rock, px, 0) }
        if mo > 0.6 {
            let off = JSMath.rem(t * w * 0.012, w) - w
            ctx.globalAlpha = min(1, (mo - 0.6) * 1.5)
            ctx.drawImage(front, off, 0)
            ctx.globalAlpha = 1
        }
        if S.rain > 0.01 {
            ctx.strokeStyle = C2DStyle(RW.css(pal.mist, 0.35 * S.rain))
            ctx.lineWidth = max(1, w / 1200)
            ctx.beginPath()
            let rr = RW.rng(3)
            for _ in 0..<160 {
                let x = JSMath.rem(rr() * w * 1.2 + t * w * 0.05, w * 1.2) - w * 0.1
                let y = JSMath.rem(rr() * h + t * h * 1.6 * (0.7 + rr() * 0.6), h)
                let l = h * 0.04
                ctx.moveTo(x, y)
                ctx.lineTo(x - l * 0.25, y + l)
            }
            ctx.stroke()
        }
        ctx.globalAlpha = theme == "light" ? 0.55 : 0.3
        ctx.globalCompositeOperation = theme == "light" ? "multiply" : "screen"
        ctx.drawImage(paper, 0, 0)
        ctx.globalCompositeOperation = "source-over"
        ctx.globalAlpha = 1
    }
}

/// The shared layer cache (wash.ts / wash2.ts `layer`): repaint only when the key changes.
nonisolated enum RLayerCache {
    static func layer(_ slots: inout [String: (key: String, s: C2DSurface)], _ slot: String, _ key: String, _ w: Double, _ h: Double, _ paint: (C2D) -> Void) -> C2DSurface {
        let cur = slots[slot]
        if let cur, cur.key == key { return cur.s }
        let wi = max(1, Int(w.rounded())), hi = max(1, Int(h.rounded()))
        let s = (cur.map { $0.s.width == wi && $0.s.height == hi && $0.s.context != nil } ?? false) ? cur!.s : C2DSurface(width: wi, height: hi)
        if let c = C2D(surface: s) {
            c.cg.saveGState()
            c.setTransform(1, 0, 0, 1, 0, 0)
            c.globalAlpha = 1
            c.globalCompositeOperation = "source-over"
            c.clearRect(0, 0, w, h)
            paint(c)
            c.cg.restoreGState()
        }
        s.seal()
        slots[slot] = (key, s)
        return s
    }
}

/// wash2.ts Painter2 (+ wash3.ts Painter3.render3): the other day worlds, birds, extras, paper.
nonisolated final class RPainter2 {
    let ridge = RPainter()
    var xf: (Double, Double, Double, Double, Double, Double) = (1, 0, 0, 1, 0, 0)
    private var caches: [String: (key: String, s: C2DSurface)] = [:]

    func layer(_ slot: String, _ key: String, _ w: Double, _ h: Double, _ paint: (C2D) -> Void) -> C2DSurface {
        RLayerCache.layer(&caches, slot, key, w, h, paint)
    }

    func render(_ ctx: C2D, _ w: Double, _ h: Double, _ S: RScene, _ theme: String, _ t: Double, _ extra: (() -> Void)? = nil) {
        let L = RW.layoutFor(w, h)
        if S.kind == "ridge" {
            ridge.xf = xf
            ridge.render(ctx, w, h, S, theme, t)
        } else {
            let night = JSMath.round(S.night * 4) / 4
            let pal = RW.palette(theme, night)
            let key = "\(S.kind):\(JS.str(w))x\(JS.str(h)):\(theme):\(JS.str(S.seed)):\(JS.str(night)):\(JS.toFixed(S.peak, 2))"
            ctx.setTransform(xf)
            ctx.globalAlpha = 1
            RW.kindDispatch(self, S.kind, ctx, w, h, L, pal, S, theme, t, key)
        }
        if let b = S.birds, b != 0, !b.isNaN { RW.birds(ctx, w, h, t, RW.palette(theme, S.night), b, L.horizon) }
        extra?()
        // paper
        let paper = layer("paper", "\(JS.str(w))x\(JS.str(h))", w, h) { c in
            c.fillStyle = c.createPattern(RW.grain(), "repeat")
            c.fillRect(0, 0, w, h)
        }
        ctx.globalAlpha = theme == "light" ? 0.55 : 0.3
        ctx.globalCompositeOperation = theme == "light" ? "multiply" : "screen"
        ctx.drawImage(paper, 0, 0)
        ctx.globalCompositeOperation = "source-over"
        ctx.globalAlpha = 1
    }

    /// wash3.ts Painter3.render3.
    func render3(_ ctx: C2D, _ w: Double, _ h: Double, _ S: RScene, _ theme: String, _ t: Double) {
        render(ctx, w, h, S, theme, t) { RW.overlay3(ctx, w, h, S, theme, t) }
    }
}
