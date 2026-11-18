//
//  RidgeWorld.swift
//  GymLock
//
//  The Ridge wake world as data: the baked layers (Assets.xcassets/WakeRidge), their placements, the
//  route, the 66 marks, the stars, the live colours and the camera per chapter, all read from
//  Resources/WakeRidgeWorld.json (written by tools/bake-ridge/bake.py from the approved prototype's
//  own painters). Also the shared image cache and the camera.
//
//  Units: world positions are fractions of the world (x of its width, y of its height). The world is
//  the 390 x 844 stage design; RidgeWakeStage maps it onto the screen by aspect fill. Times are
//  seconds, as WakePlan carries them; the prototype's frame offsets are converted at 30 fps.
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit

// MARK: - Easing (web/morning2/plan.ts)

nonisolated enum RidgeMath {
    static let fps: Double = 30
    @inline(__always) static func cl(_ x: Double) -> Double { min(1, max(0, x)) }
    @inline(__always) static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    /// ease out cubic
    @inline(__always) static func ez(_ x: Double) -> Double { let k = 1 - cl(x); return 1 - k * k * k }
    /// ease out quadratic
    @inline(__always) static func ez2(_ x: Double) -> Double { let k = 1 - cl(x); return 1 - k * k }
    /// ease in-out cubic
    @inline(__always) static func eio(_ x: Double) -> Double {
        let k = cl(x)
        if k < 0.5 { return 4 * k * k * k }
        let m = -2 * k + 2
        return 1 - m * m * m / 2
    }
    /// Theme.settle, approximated as the prototype does
    @inline(__always) static func settle(_ x: Double) -> Double { 1 - pow(1 - cl(x), 3.6) }
    /// a spring 0 to 1 starting at x = 0 (seconds), small overshoot
    @inline(__always) static func spr(_ x: Double, _ w: Double = 13, _ z: Double = 7) -> Double {
        x <= 0 ? 0 : 1 - exp(-x * z) * cos(x * w)
    }
}

nonisolated enum RidgeEase: String, Decodable, Sendable {
    case ez, eio
    @inline(__always) func callAsFunction(_ x: Double) -> Double {
        switch self {
        case .ez: return RidgeMath.ez(x)
        case .eio: return RidgeMath.eio(x)
        }
    }
}

// MARK: - The JSON as written by the bake

nonisolated struct RidgeWorldFile: Decodable, Sendable {
    nonisolated struct Reference: Decodable, Sendable {
        let stage: [Double]
        let card: [Double]
        let fps: Double
        let arcYScale: Double
    }
    nonisolated struct Layer: Decodable, Sendable {
        let asset: String
        let pixels: [Int]
        let rect: [Double]
    }
    nonisolated struct WorldGeo: Decodable, Sendable {
        let walk: [[Double]]
        let walkWidths: [Double]
        let climb: [[Double]]
        let peak: [Double]
        let foot: [Double]
        let summit: [Double]
        let horizon: Double
        let leaveU: Double
        let leavePoint: [Double]
        let marks66: [[Double]]
        let dash: [Double]
        let dashWidth: Double
    }
    nonisolated struct CardGeo: Decodable, Sendable {
        let walk: [[Double]]
        let walkWidths: [Double]
        let climb: [[Double]]
        let peak: [Double]
        let gym: [Double]
        let horizon: Double
        let marks66: [[Double]]
        let dash: [Double]
        let dashWidth: Double
    }
    nonisolated struct Look: Decodable, Sendable {
        let ribbon: [Double]
        let ribbonAlpha: Double
        let dash: [Double]
        let dashAlpha: Double
        let bird: [Double]
        let birdAlpha: Double
        let mist: [Double]
        let sun: [Double]
    }
    nonisolated struct Colours: Decodable, Sendable {
        let night: Look
        let dawn: Look
        let cardDark: Look
        let cardLight: Look
    }
    nonisolated struct Cam: Decodable, Sendable {
        let s, cx, cy, ax, ay: Double
    }
    nonisolated struct Zoom: Decodable, Sendable {
        let to, start, dur: Double
        let ease: RidgeEase
    }
    nonisolated struct Follow: Decodable, Sendable {
        let path: String
        let u0, u1, start, dur: Double
        let ease: RidgeEase
    }
    nonisolated struct Pull: Decodable, Sendable {
        let cam: Cam
        let start, dur: Double
        let ease: RidgeEase
    }
    nonisolated struct CameraSpec: Decodable, Sendable {
        let base: Cam
        let zoom: Zoom?
        let follow: Follow?
        let pull: Pull?
    }
    nonisolated struct Idle: Decodable, Sendable {
        /// the card's mist sways this fraction of the card's width, once per idle loop
        let mistSway: Double
        let cardMistAlpha: Double
        let lightSweep: Double
        let birdsStage: Int
        let birdsCard: Int
    }
    let version: Int
    let reference: Reference
    let layers: [String: Layer]
    let world: WorldGeo
    let card: CardGeo
    let stars: [[Double]]
    let colours: Colours
    let cameras: [String: CameraSpec]
    let idle: Idle
}

// MARK: - Layers

/// The baked images. Raw values are the asset names in Assets.xcassets/WakeRidge.
nonisolated enum RidgeLayer: String, CaseIterable, Sendable {
    case worldNight = "ridgeWorldNight"
    case worldDawn = "ridgeWorldDawn"
    case worldDawnHi = "ridgeWorldDawnHi"
    case cardDark = "ridgeCardDark"
    case cardLight = "ridgeCardLight"
    case cardMistDark = "ridgeCardMistDark"
    case cardMistLight = "ridgeCardMistLight"

    /// the stage's layers: only needed until the card has landed
    static let stage: [RidgeLayer] = [.worldNight, .worldDawn, .worldDawnHi]
    static let card: [RidgeLayer] = [.cardDark, .cardLight, .cardMistDark, .cardMistLight]
}

/// Decoded, display-ready CGImages, loaded once and shared by every renderer. Thread safe (a lock
/// around a small table), so the stage can prewarm off the main thread.
nonisolated final class RidgeAssets: @unchecked Sendable {
    static let shared = RidgeAssets()

    private let lock = NSLock()
    private var images: [RidgeLayer: CGImage] = [:]
    private var generation = 0
    /// bumped by every purge; a prewarm that started before a purge must not re-cache what it dropped
    private var epoch = 0
    private var purgedAt: [RidgeLayer: Int] = [:]

    /// bumped whenever images are dropped, so renderers know to re-resolve
    var currentGeneration: Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    /// the image for a layer, decoding it now if it is not cached yet (prefer `prewarm` early). A
    /// draw asking for a layer always caches it, even one that was purged earlier (a scrub back).
    func image(_ layer: RidgeLayer) -> CGImage? {
        lock.lock()
        if let cached = images[layer] { lock.unlock(); return cached }
        lock.unlock()
        guard let decoded = Self.decode(layer) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let raced = images[layer] { return raced }
        images[layer] = decoded
        return decoded
    }

    /// decode layers in the background so the first frame does not pay for it. A page that settles at
    /// once (VoiceOver, a skipped intro) purges the stage world while this is still running; the
    /// epoch check keeps the late decode from putting those 44 MB back.
    func prewarm(_ layers: [RidgeLayer] = RidgeLayer.allCases) {
        lock.lock()
        let started = epoch
        lock.unlock()
        Task.detached(priority: .userInitiated) { [self] in
            for layer in layers { self.warm(layer, startedAtEpoch: started) }
        }
    }

    private func warm(_ layer: RidgeLayer, startedAtEpoch started: Int) {
        lock.lock()
        let skip = images[layer] != nil || (purgedAt[layer] ?? 0) > started
        lock.unlock()
        if skip { return }
        guard let decoded = Self.decode(layer) else { return }
        lock.lock(); defer { lock.unlock() }
        if images[layer] != nil || (purgedAt[layer] ?? 0) > started { return }
        images[layer] = decoded
    }

    /// release decoded layers (the stage world is about 44 MB decoded; the card layers about 7 MB)
    func purge(_ layers: [RidgeLayer]) {
        lock.lock(); defer { lock.unlock() }
        epoch += 1
        var dropped = false
        for layer in layers {
            purgedAt[layer] = epoch
            if images.removeValue(forKey: layer) != nil { dropped = true }
        }
        if dropped { generation &+= 1 }
    }

    private static func decode(_ layer: RidgeLayer) -> CGImage? {
        guard let ui = UIImage(named: layer.rawValue, in: .main, compatibleWith: nil) else { return nil }
        // decode now (HEIC and PNG decode lazily on first draw otherwise)
        let ready = ui.preparingForDisplay() ?? ui
        return ready.cgImage ?? ui.cgImage
    }
}

// MARK: - Geometry

/// A polyline measured by arc length the prototype's way (y weighted by the stage's aspect, 2.16), so
/// a fraction u lands where the web puts it.
nonisolated struct RidgePolyline: Sendable {
    let points: [CGPoint]
    private let acc: [Double]
    private let length: Double

    init(_ pts: [CGPoint], arcYScale: Double) {
        points = pts
        var a: [Double] = [0]
        a.reserveCapacity(pts.count)
        if pts.count > 1 {
            for i in 1..<pts.count {
                let dx = Double(pts[i].x - pts[i - 1].x), dy = Double(pts[i].y - pts[i - 1].y) * arcYScale
                a.append(a[i - 1] + (dx * dx + dy * dy).squareRoot())
            }
        }
        acc = a
        length = a.last ?? 0
    }

    /// the point at fraction u (clamped) of the way, in the polyline's own units
    func at(_ u: Double) -> CGPoint {
        guard points.count > 1 else { return points.first ?? .zero }
        let d = RidgeMath.cl(u) * length
        var i = 1
        while i < acc.count - 1 && acc[i] < d { i += 1 }
        let t = (d - acc[i - 1]) / max(1e-9, acc[i] - acc[i - 1])
        let a = points[i - 1], b = points[i]
        return CGPoint(x: Double(a.x) + Double(b.x - a.x) * t, y: Double(a.y) + Double(b.y - a.y) * t)
    }
}

/// The camera: the world point (cx, cy) held at the screen point (ax, ay) (fractions), zoom s.
nonisolated struct RidgeCam: Sendable {
    var s, cx, cy, ax, ay: Double

    func mixed(_ b: RidgeCam, _ t: Double) -> RidgeCam {
        RidgeCam(s: RidgeMath.lerp(s, b.s, t), cx: RidgeMath.lerp(cx, b.cx, t), cy: RidgeMath.lerp(cy, b.cy, t),
                 ax: RidgeMath.lerp(ax, b.ax, t), ay: RidgeMath.lerp(ay, b.ay, t))
    }
}

/// One chapter's camera move, evaluated from the JSON's keyframes.
nonisolated struct RidgeCameraMove: Sendable {
    nonisolated struct Zoom: Sendable { let to, start, dur: Double; let ease: RidgeEase }
    nonisolated struct Follow: Sendable { let climb: Bool; let u0, u1, start, dur: Double; let ease: RidgeEase }
    nonisolated struct Pull: Sendable { let cam: RidgeCam; let start, dur: Double; let ease: RidgeEase }
    let base: RidgeCam
    let zoom: Zoom?
    let follow: Follow?
    let pull: Pull?

    init(_ spec: RidgeWorldFile.CameraSpec?) {
        let b = spec?.base
        base = RidgeCam(s: b?.s ?? 1, cx: b?.cx ?? 0.5, cy: b?.cy ?? 0.5, ax: b?.ax ?? 0.5, ay: b?.ay ?? 0.5)
        if let z = spec?.zoom {
            zoom = Zoom(to: z.to, start: z.start, dur: max(1e-6, z.dur), ease: z.ease)
        } else {
            zoom = nil
        }
        if let fo = spec?.follow {
            follow = Follow(climb: fo.path == "climb", u0: fo.u0, u1: fo.u1, start: fo.start, dur: max(1e-6, fo.dur), ease: fo.ease)
        } else {
            follow = nil
        }
        if let pl = spec?.pull {
            pull = Pull(cam: RidgeCam(s: pl.cam.s, cx: pl.cam.cx, cy: pl.cam.cy, ax: pl.cam.ax, ay: pl.cam.ay), start: pl.start, dur: max(1e-6, pl.dur), ease: pl.ease)
        } else {
            pull = nil
        }
    }
}

/// A live colour from the bake (0-255 RGB + alpha).
nonisolated struct RidgeRGBA: Sendable {
    let r, g, b, a: Double
    init(_ c: [Double], _ a: Double = 1) {
        r = (c.count > 0 ? c[0] : 0) / 255
        g = (c.count > 1 ? c[1] : 0) / 255
        b = (c.count > 2 ? c[2] : 0) / 255
        self.a = a
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

nonisolated struct RidgeLook: Sendable {
    let ribbon: RidgeRGBA
    let dash: RidgeRGBA
    let bird: RidgeRGBA
    let mist: RidgeRGBA
    let sun: RidgeRGBA
    init(_ l: RidgeWorldFile.Look) {
        ribbon = RidgeRGBA(l.ribbon, l.ribbonAlpha)
        dash = RidgeRGBA(l.dash, l.dashAlpha)
        bird = RidgeRGBA(l.bird, l.birdAlpha)
        mist = RidgeRGBA(l.mist)
        sun = RidgeRGBA(l.sun)
    }
}

/// The route of one painting (the stage's tall world or the card's wide one), in fractions.
nonisolated struct RidgeRoute: Sendable {
    let walk: [CGPoint]
    let walkWidths: [Double] // ribbon width per walk segment, as a fraction of the painting's width
    let climb: [CGPoint]
    let walkPoly: RidgePolyline
    let climbPoly: RidgePolyline
    let marks66: [CGPoint]
    let peak: CGPoint
    let horizon: Double
    let dash: (on: Double, off: Double)
    let dashWidth: Double
}

// MARK: - The world

/// The world, read once. Default-isolated (it reads WakePlan, a default-isolated contract type); the
/// pieces above are nonisolated so the image cache can decode off the main thread.
struct RidgeWorld: Sendable {
    /// the stage design the world was painted for (points)
    let stageSize: CGSize
    let arcYScale: Double
    let stage: RidgeRoute
    let foot: CGPoint
    let summit: CGPoint
    let leaveU: Double
    let leavePoint: CGPoint
    let card: RidgeRoute
    let cardGym: CGPoint
    /// x, y (fractions), brightness, size factor
    let stars: [(x: Double, y: Double, a: Double, m: Double)]
    let night: RidgeLook
    let dawn: RidgeLook
    let cardDark: RidgeLook
    let cardLight: RidgeLook
    let idle: RidgeWorldFile.Idle
    /// layer placements in fractions of the painting (x, y, w, h)
    let rects: [RidgeLayer: CGRect]
    let cameras: [RidgeCameraMove] // indexed by `cameraIndex`
    let cardCamera: RidgeCam

    /// the shared world, read once from the app bundle
    static let shared: RidgeWorld? = RidgeWorld.load()

    static func load(bundle: Bundle = .main) -> RidgeWorld? {
        guard let url = bundle.url(forResource: "WakeRidgeWorld", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(RidgeWorldFile.self, from: data) else { return nil }
        return RidgeWorld(file)
    }

    init(_ f: RidgeWorldFile) {
        let pt: ([Double]) -> CGPoint = { v in CGPoint(x: v.count > 0 ? v[0] : 0, y: v.count > 1 ? v[1] : 0) }
        let arc = f.reference.arcYScale
        arcYScale = arc
        stageSize = CGSize(width: f.reference.stage.first ?? 390, height: f.reference.stage.count > 1 ? f.reference.stage[1] : 844)
        func route(walk: [[Double]], widths: [Double], climb: [[Double]], marks: [[Double]], peak: [Double], horizon: Double, dash: [Double], dashWidth: Double) -> RidgeRoute {
            let w = walk.map(pt), c = climb.map(pt)
            return RidgeRoute(walk: w, walkWidths: widths, climb: c, walkPoly: RidgePolyline(w, arcYScale: arc), climbPoly: RidgePolyline(c, arcYScale: arc),
                              marks66: marks.map(pt), peak: pt(peak), horizon: horizon,
                              dash: (dash.count > 0 ? dash[0] : 0.006, dash.count > 1 ? dash[1] : 0.008), dashWidth: dashWidth)
        }
        let g = f.world
        stage = route(walk: g.walk, widths: g.walkWidths, climb: g.climb, marks: g.marks66, peak: g.peak, horizon: g.horizon, dash: g.dash, dashWidth: g.dashWidth)
        foot = pt(g.foot)
        summit = pt(g.summit)
        leaveU = g.leaveU
        leavePoint = pt(g.leavePoint)
        let c = f.card
        card = route(walk: c.walk, widths: c.walkWidths, climb: c.climb, marks: c.marks66, peak: c.peak, horizon: c.horizon, dash: c.dash, dashWidth: c.dashWidth)
        cardGym = pt(c.gym)
        stars = f.stars.map { v -> (x: Double, y: Double, a: Double, m: Double) in
            (x: v.count > 0 ? v[0] : 0, y: v.count > 1 ? v[1] : 0, a: v.count > 2 ? v[2] : 0, m: v.count > 3 ? v[3] : 1)
        }
        night = RidgeLook(f.colours.night)
        dawn = RidgeLook(f.colours.dawn)
        cardDark = RidgeLook(f.colours.cardDark)
        cardLight = RidgeLook(f.colours.cardLight)
        idle = f.idle
        var r: [RidgeLayer: CGRect] = [:]
        for layer in RidgeLayer.allCases {
            let v = f.layers[layer.rawValue]?.rect ?? [0, 0, 1, 1]
            r[layer] = v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        rects = r
        cameras = Self.cameraKeys.map { RidgeCameraMove(f.cameras[$0]) }
        let cc = RidgeCameraMove(f.cameras["card"]).base
        cardCamera = cc
    }

    // MARK: Camera

    private static let cameraKeys = ["greet", "commit", "leave", "mission", "day", "week"]
    @inline(__always) private static func cameraIndex(_ id: WakeBeatID) -> Int {
        switch id {
        case .greet: return 0
        case .commit: return 1
        case .leave: return 2
        case .mission: return 3
        case .day: return 4
        case .week: return 5
        }
    }

    /// one chapter's camera, lt seconds into it (ridge.tsx camFor)
    func camera(_ id: WakeBeatID, _ lt: Double) -> RidgeCam {
        let m = cameras[Self.cameraIndex(id)]
        var c = m.base
        if let z = m.zoom { c.s = RidgeMath.lerp(m.base.s, z.to, z.ease((lt - z.start) / z.dur)) }
        if let fo = m.follow {
            let poly = fo.climb ? stage.climbPoly : stage.walkPoly
            let p = poly.at(fo.u0 + (fo.u1 - fo.u0) * fo.ease((lt - fo.start) / fo.dur))
            c.cx = Double(p.x)
            c.cy = Double(p.y)
        }
        if let pl = m.pull { c = c.mixed(pl.cam, pl.ease((lt - pl.start) / pl.dur)) }
        return c
    }

    /// the camera at time t: each chapter's move, blended in from the last chapter's pose over 0.8 s;
    /// once condensing, from the last pose to the card's framing over 14 frames (ridge.tsx ridgeCam)
    func camera(plan: WakePlan, at t: Double) -> RidgeCam {
        let beats = plan.beats
        guard let last = beats.last else { return cardCamera }
        let current = Self.beat(plan, t)
        if plan.reduceMotion {
            guard let current else { return cardCamera }
            return camera(current.id, 2.2)
        }
        guard let b = current else {
            return camera(last.id, last.end - last.start).mixed(cardCamera, RidgeMath.eio((t - plan.condenseAt) / (14 / RidgeMath.fps)))
        }
        let lt = t - b.start
        let cur = camera(b.id, lt)
        guard b.index > 0, b.index - 1 < beats.count else { return cur }
        let pv = beats[b.index - 1]
        return camera(pv.id, pv.end - pv.start).mixed(cur, RidgeMath.eio(lt / 0.8))
    }

    /// how far first light has come (0 night, 1 dawn) (ridge.tsx dawnOf)
    func dawnProgress(plan: WakePlan, at t: Double) -> Double {
        if plan.reduceMotion { return 1 }
        guard let g = plan.beats.first else { return 1 }
        if g.id != .greet { return RidgeMath.eio((t - (g.start - 6 / RidgeMath.fps)) / (36 / RidgeMath.fps)) }
        return RidgeMath.eio((t - (g.start + 8 / RidgeMath.fps)) / (50 / RidgeMath.fps))
    }

    /// the chapter on screen at t, nil once condensing (plan.ts beatAt). Kept here rather than calling
    /// WakePlan.beat(at:) so the camera, overlays and words agree on the boundary.
    static func beat(_ plan: WakePlan, _ t: Double) -> WakeBeat? {
        guard t < plan.condenseAt, var b = plan.beats.first else { return nil }
        for x in plan.beats where t >= x.start { b = x }
        return b
    }

    static func find(_ plan: WakePlan, _ id: WakeBeatID) -> WakeBeat? {
        for b in plan.beats where b.id == id { return b }
        return nil
    }
}
