//
//  MissionRidgeWorld.swift
//  GymLock
//
//  The data, the image cache, the camera maths and the shared painter of the Ridge mission scenes.
//  The painted layers are BAKED (tools/bake-ridge-missions) into Assets.xcassets/MissionRidge; this file
//  only reads them back and composites them: a handful of drawImage calls per frame.
//
//  Geometry is in "world fractions": x of the world width, y of the world height. The world is
//  `aspect` (1.25) wide:high and is aspect-FILLED into whatever size the view has.
//

import SwiftUI
import UIKit

// MARK: - Math

nonisolated enum MissionRidgeMath {
    static let tau: CGFloat = CGFloat.pi * 2

    static func clamp(_ v: CGFloat, _ a: CGFloat = 0, _ b: CGFloat = 1) -> CGFloat {
        return min(b, max(a, v))
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }

    static func easeInOut(_ x: CGFloat) -> CGFloat {
        let c = clamp(x)
        if c < 0.5 { return 4 * c * c * c }
        let q = -2 * c + 2
        return 1 - (q * q * q) / 2
    }

    static func easeOut(_ x: CGFloat) -> CGFloat {
        let q = 1 - clamp(x)
        return 1 - q * q * q
    }

    static func mod(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let r = a.truncatingRemainder(dividingBy: b)
        return r < 0 ? r + b : r
    }
}

// MARK: - Codable world (Resources/MissionRidgeWorld.json)

nonisolated struct MissionRidgeFrame: Codable, Sendable {
    let u: CGFloat
    let z: CGFloat
    let ax: CGFloat
    let ay: CGFloat
}

nonisolated struct MissionRidgeStar: Codable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let r: CGFloat
    let a: CGFloat
    let f: CGFloat
    let p: CGFloat
}

nonisolated struct MissionRidgeTrail: Codable, Sendable {
    let n: Int
    let x: [CGFloat]
    let y: [CGFloat]
    let w: [CGFloat]
    let length: CGFloat
    let sun: [CGFloat]

    nonisolated struct Sample: Sendable {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
    }

    /// Arc-length sample: u = 0 is the start of the trail, 1 is the gym.
    func sample(at u: CGFloat) -> Sample {
        let k = MissionRidgeMath.clamp(u) * CGFloat(n)
        let i = min(n - 1, Int(k))
        let f = k - CGFloat(i)
        return Sample(x: MissionRidgeMath.lerp(x[i], x[i + 1], f),
                      y: MissionRidgeMath.lerp(y[i], y[i + 1], f),
                      w: MissionRidgeMath.lerp(w[i], w[i + 1], f))
    }

    var sunPoint: CGPoint {
        return CGPoint(x: sun.count > 0 ? sun[0] : 0.3, y: sun.count > 1 ? sun[1] : 0.3)
    }

    /// Every array must hold n + 1 samples.
    var isValid: Bool {
        return n > 1 && x.count == n + 1 && y.count == n + 1 && w.count == n + 1
    }
}

nonisolated struct MissionRidgeLayerSpec: Codable, Sendable {
    let plane: String
    let image: String
    let yOff: CGFloat
    let height: CGFloat
}

nonisolated struct MissionRidgeMistSpec: Codable, Sendable {
    let plane: String
    let image: String
    let y: CGFloat
    let heightFrac: CGFloat
    let speed: CGFloat
    let alpha: CGFloat
    let phase: CGFloat
    let dir: CGFloat
}

nonisolated struct MissionRidgeSetSpec: Codable, Sendable {
    let layers: [MissionRidgeLayerSpec]
    let mist: [MissionRidgeMistSpec]
    let baked: Bool
    let dark: Bool
}

nonisolated struct MissionRidgeSunSpec: Codable, Sendable {
    let glow: String
    let disc: String
    let rays: String
}

nonisolated struct MissionRidgeWorldData: Codable, Sendable {
    let version: Int
    let aspect: CGFloat
    let frames: [String: MissionRidgeFrame]
    let parallax: [String: CGFloat]
    let baseZoom: CGFloat
    let pad: CGFloat
    let badgeRadius: CGFloat
    let stepCount: Int
    let stars: [MissionRidgeStar]
    let trails: [String: MissionRidgeTrail]
    let sets: [String: MissionRidgeSetSpec]
    let sunSprites: [String: MissionRidgeSunSpec]

    /// The framing of a figure. The two helper figures have none of their own: `check` rests at the
    /// gym end of the trail (door) and `camera` at the start (shoes).
    func frame(for figure: MissionFigure) -> MissionRidgeFrame {
        let key: String
        switch figure {
        case .shoes: key = "shoes"
        case .shoesOn: key = "shoesOn"
        case .steps: key = "steps"
        case .water: key = "water"
        case .bag: key = "bag"
        case .door: key = "door"
        case .mirror: key = "mirror"
        case .check: key = "door"
        case .camera: key = "shoes"
        }
        return frames[key] ?? MissionRidgeFrame(u: 0.16, z: 1.32, ax: 0.5, ay: 0.66)
    }
}

// MARK: - Loaded images

nonisolated enum MissionRidgePlane: String, Sendable, CaseIterable {
    case sky, far, peak, mid, near, fg
}

nonisolated struct MissionRidgeLayer: @unchecked Sendable {
    let plane: MissionRidgePlane
    let image: Image
    let yOff: CGFloat
    let height: CGFloat
}

nonisolated struct MissionRidgeMistStrip: @unchecked Sendable {
    let plane: MissionRidgePlane
    let image: Image
    let y: CGFloat
    let heightFrac: CGFloat
    let speed: CGFloat
    let alpha: CGFloat
    let phase: CGFloat
    let dir: CGFloat
}

nonisolated struct MissionRidgeSunImages: @unchecked Sendable {
    let glow: Image
    let disc: Image
    let rays: Image
}

nonisolated struct MissionRidgeSet: @unchecked Sendable {
    let layers: [MissionRidgeLayer]
    let mist: [MissionRidgeMistStrip]
    let baked: Bool
    let dark: Bool
    let sun: MissionRidgeSunImages

    func layer(_ plane: MissionRidgePlane) -> MissionRidgeLayer? {
        return layers.first(where: { $0.plane == plane })
    }
}

nonisolated struct MissionRidgeLoaded: @unchecked Sendable {
    let data: MissionRidgeWorldData
    let sets: [String: MissionRidgeSet]
}

// MARK: - Cache

/// Loads the JSON and the baked images once, decoded off the main thread, and drops the images
/// 30 s after the last Ridge view left the screen.
nonisolated final class MissionRidgeStore: @unchecked Sendable {
    static let shared = MissionRidgeStore()
    static let releaseDelay: Double = 30

    private let lock = NSLock()
    private var data: MissionRidgeWorldData?
    private var images: [String: Image] = [:]
    private var viewers = 0
    private var releaseTask: Task<Void, Never>?

    private init() {}

    /// A Ridge view appeared.
    func acquire() {
        lock.withLock {
            viewers += 1
            releaseTask?.cancel()
            releaseTask = nil
        }
    }

    /// A Ridge view disappeared; the cache is purged after `releaseDelay` seconds without viewers.
    func release() {
        lock.withLock {
            viewers = max(0, viewers - 1)
            if viewers == 0 {
                releaseTask?.cancel()
                releaseTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(MissionRidgeStore.releaseDelay))
                    if Task.isCancelled { return }
                    self?.purgeIfIdle()
                }
            }
        }
    }

    private func purgeIfIdle() {
        lock.withLock {
            if viewers == 0 {
                images.removeAll()
                releaseTask = nil
            }
        }
    }

    /// Loads the named sets ("day", "night", "dawn"); nil if an asset or the JSON is missing or malformed.
    func load(sets keys: [String]) async -> MissionRidgeLoaded? {
        return await Task.detached(priority: .userInitiated) { [self] in
            return self.prepare(sets: keys)
        }.value
    }

    private func prepare(sets keys: [String]) -> MissionRidgeLoaded? {
        guard let data = loadData() else { return nil }
        for trail in data.trails.values where !trail.isValid { return nil }
        var names: [String] = []
        for key in keys {
            guard let spec = data.sets[key] else { return nil }
            names.append(contentsOf: spec.layers.map { $0.image })
            names.append(contentsOf: spec.mist.map { $0.image })
            guard let sun = data.sunSprites[spec.dark ? "dark" : "light"] else { return nil }
            names.append(contentsOf: [sun.glow, sun.disc, sun.rays])
        }
        decode(names)
        var built: [String: MissionRidgeSet] = [:]
        for key in keys {
            guard let spec = data.sets[key], let sunSpec = data.sunSprites[spec.dark ? "dark" : "light"] else { return nil }
            var layers: [MissionRidgeLayer] = []
            for l in spec.layers {
                guard let plane = MissionRidgePlane(rawValue: l.plane), let img = cached(l.image) else { return nil }
                layers.append(MissionRidgeLayer(plane: plane, image: img, yOff: l.yOff, height: l.height))
            }
            var mist: [MissionRidgeMistStrip] = []
            for m in spec.mist {
                guard let plane = MissionRidgePlane(rawValue: m.plane), let img = cached(m.image) else { return nil }
                mist.append(MissionRidgeMistStrip(plane: plane, image: img, y: m.y, heightFrac: m.heightFrac, speed: m.speed,
                                                  alpha: m.alpha, phase: m.phase, dir: m.dir))
            }
            guard let glow = cached(sunSpec.glow), let disc = cached(sunSpec.disc), let rays = cached(sunSpec.rays) else { return nil }
            built[key] = MissionRidgeSet(layers: layers, mist: mist, baked: spec.baked, dark: spec.dark,
                                         sun: MissionRidgeSunImages(glow: glow, disc: disc, rays: rays))
        }
        return MissionRidgeLoaded(data: data, sets: built)
    }

    private func loadData() -> MissionRidgeWorldData? {
        if let d = lock.withLock({ data }) { return d }
        guard let url = Bundle.main.url(forResource: "MissionRidgeWorld", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MissionRidgeWorldData.self, from: raw) else { return nil }
        lock.withLock { data = decoded }
        return decoded
    }

    private func cached(_ name: String) -> Image? {
        return lock.withLock { images[name] }
    }

    private func decode(_ names: [String]) {
        for name in names {
            if cached(name) != nil { continue }
            guard let ui = UIImage(named: name) else { continue }
            let prepared = ui.preparingForDisplay() ?? ui
            let image = Image(uiImage: prepared)
            lock.withLock { images[name] = image }
        }
    }
}

// MARK: - Camera

nonisolated struct MissionRidgeCam: Sendable, Equatable {
    var cx: CGFloat
    var cy: CGFloat
    var z: CGFloat
}

/// Where a plane's bitmap lands: top-left and size in points.
nonisolated struct MissionRidgePlaneTf: Sendable {
    let tx: CGFloat
    let ty: CGFloat
    let w: CGFloat
    let h: CGFloat
}

/// Camera maths for one view size. The world (aspect `aspect`) is scaled to FILL the view, so the framing
/// holds at any aspect from 300x250 to 600x500 (and the band's 390 x 220...360).
nonisolated struct MissionRidgeGeometry: Sendable {
    let size: CGSize
    let baseZoom: CGFloat
    let pad: CGFloat
    let parallax: [String: CGFloat]
    let ww: CGFloat   // world width in points at zoom 1
    let wh: CGFloat   // world height in points at zoom 1

    init(size: CGSize, data: MissionRidgeWorldData) {
        self.size = size
        self.baseZoom = data.baseZoom
        self.pad = data.pad
        self.parallax = data.parallax
        let a = max(0.1, data.aspect)
        let w = max(size.width, size.height * a)
        self.ww = w
        self.wh = w / a
    }

    func factor(_ plane: MissionRidgePlane) -> CGFloat {
        return parallax[plane.rawValue] ?? 1
    }

    func clampCam(_ c: MissionRidgeCam) -> MissionRidgeCam {
        let zl = baseZoom + (c.z - 1)
        let mx = (size.width / 2 + pad) / (ww * zl)
        let my = (size.height / 2 + pad) / (wh * zl)
        func fix(_ v: CGFloat, _ m: CGFloat) -> CGFloat {
            return m >= 0.5 ? 0.5 : MissionRidgeMath.clamp(v, m, 1 - m)
        }
        return MissionRidgeCam(cx: fix(c.cx, mx), cy: fix(c.cy, my), z: c.z)
    }

    /// The camera that puts the frame's trail position at its screen anchor.
    func camera(for frame: MissionRidgeFrame, trail: MissionRidgeTrail) -> MissionRidgeCam {
        let p = trail.sample(at: frame.u)
        let zl = baseZoom + (frame.z - 1)
        let cx = p.x + (0.5 - frame.ax) * size.width / (ww * zl)
        let cy = p.y + (0.5 - frame.ay) * size.height / (wh * zl)
        return clampCam(MissionRidgeCam(cx: cx, cy: cy, z: frame.z))
    }

    /// Camera between two cameras; a small pull-back mid-move shows the depth between the layers.
    func mix(_ a: MissionRidgeCam, _ b: MissionRidgeCam, _ e: CGFloat) -> MissionRidgeCam {
        let L = MissionRidgeMath.lerp
        let z = L(a.z, b.z, e) - 0.07 * sin(CGFloat.pi * e)
        return clampCam(MissionRidgeCam(cx: L(a.cx, b.cx, e), cy: L(a.cy, b.cy, e), z: z))
    }

    /// The camera is never quite still.
    func breathe(_ c: MissionRidgeCam, t: CGFloat) -> MissionRidgeCam {
        let tau = MissionRidgeMath.tau
        return clampCam(MissionRidgeCam(cx: c.cx + 0.0035 * sin(t / 23 * tau),
                                        cy: c.cy + 0.003 * sin(t / 17 * tau + 1),
                                        z: c.z + 0.014 * sin(t / 13 * tau + 2)))
    }

    /// Transform of a plane: nearer planes move more than far ones (parallax).
    func plane(_ p: MissionRidgePlane, cam: MissionRidgeCam) -> MissionRidgePlaneTf {
        let par = factor(p)
        let zl = baseZoom + (cam.z - 1) * par
        let pw = ww * zl
        let ph = wh * zl
        let cx = 0.5 + (cam.cx - 0.5) * par
        let cy = 0.5 + (cam.cy - 0.5) * par
        var tx = size.width / 2 - cx * pw
        var ty = size.height / 2 - cy * ph
        if par <= 1 {
            tx = MissionRidgeMath.clamp(tx, size.width + pad - pw, -pad)
            ty = MissionRidgeMath.clamp(ty, size.height + pad - ph, -pad)
        } else {
            ty = max(ty, size.height + 3 - ph)
        }
        return MissionRidgePlaneTf(tx: tx, ty: ty, w: pw, h: ph)
    }
}

// MARK: - Shared painter (layers, mist, sun, rays, birds)

/// Draws the depth layers of one baked set. Everything is a plain value: safe to build outside the Canvas.
nonisolated struct MissionRidgePainter: Sendable {
    let geo: MissionRidgeGeometry
    let set: MissionRidgeSet
    let trail: MissionRidgeTrail
    let cam: MissionRidgeCam
    let t: CGFloat
    let reduced: Bool
    let fade: CGFloat
    let mistScale: CGFloat
    /// `Theme.ink`, handed in by the view: a painter runs inside a Canvas and reads no main-actor state.
    let ink: Color

    func plane(_ p: MissionRidgePlane) -> MissionRidgePlaneTf {
        return geo.plane(p, cam: cam)
    }

    /// Resolve per draw (never cached across frames) and draw.
    static func blit(_ ctx: GraphicsContext, _ image: Image, in rect: CGRect, alpha: CGFloat) {
        let a = MissionRidgeMath.clamp(alpha)
        if a < 0.003 { return }
        var c = ctx
        c.opacity = Double(a)
        c.draw(c.resolve(image), in: rect)
    }

    func drawLayer(_ ctx: GraphicsContext, _ p: MissionRidgePlane) {
        guard let l = set.layer(p) else { return }
        let tf = plane(p)
        let rect = CGRect(x: tf.tx, y: tf.ty + l.yOff * tf.h, width: tf.w, height: l.height * tf.h)
        MissionRidgePainter.blit(ctx, l.image, in: rect, alpha: fade)
    }

    /// sky, far range, massif, ridges, near hills, mist and light. `sunK` is the sun strength, `lift` the points the mist rises.
    func paintWorld(_ ctx: GraphicsContext, sunK: CGFloat, lift: CGFloat, birds: Bool) {
        drawLayer(ctx, .sky)
        paintSun(ctx, sunK: sunK)
        drawLayer(ctx, .far)
        paintMist(ctx, index: 0, lift: lift)
        if birds { paintBirds(ctx) }
        drawLayer(ctx, .peak)
        paintRays(ctx, sunK: sunK)
        paintMist(ctx, index: 1, lift: lift)
        drawLayer(ctx, .mid)
        paintMist(ctx, index: 2, lift: lift)
        drawLayer(ctx, .near)
    }

    func paintMist(_ ctx: GraphicsContext, index i: Int, lift: CGFloat) {
        guard i < set.mist.count else { return }
        let m = set.mist[i]
        let tf = plane(m.plane)
        let fi = CGFloat(i)
        let s: CGFloat = reduced ? 0.37 + fi * 0.21 : MissionRidgeMath.mod(m.phase + m.dir * t * m.speed, 1)
        let h = m.heightFrac * tf.h
        let y = tf.ty + m.y * tf.h - h / 2 - lift * (1 - fi * 0.2)
        let breath: CGFloat = reduced ? 1 : 0.88 + 0.12 * sin(t / 11 * MissionRidgeMath.tau + fi * 2)
        let alpha = MissionRidgeMath.clamp(m.alpha * breath * mistScale) * fade
        let x0 = tf.tx + (s - 1) * tf.w
        MissionRidgePainter.blit(ctx, m.image, in: CGRect(x: x0, y: y, width: tf.w, height: h), alpha: alpha)
        if x0 + tf.w < geo.size.width {
            MissionRidgePainter.blit(ctx, m.image, in: CGRect(x: x0 + tf.w, y: y, width: tf.w, height: h), alpha: alpha)
        }
    }

    func paintSun(_ ctx: GraphicsContext, sunK: CGFloat) {
        if sunK <= 0.003 { return }
        let tf = plane(.sky)
        let sp = trail.sunPoint
        let x = tf.tx + sp.x * tf.w
        let y = tf.ty + sp.y * tf.h
        let br: CGFloat = reduced ? 0.8 : 0.5 + 0.5 * sin(t / 8 * MissionRidgeMath.tau - 1.2)   // 8 s breath
        let dark = set.dark
        let spread: CGFloat = set.baked ? 0.17 : 0.4
        let R: CGFloat = tf.w * spread * (0.94 + 0.06 * br)
        let a: CGFloat
        if set.baked {
            a = sunK * (dark ? 0.1 : 0.3) * (0.5 + br)
        } else {
            a = sunK * (dark ? 0.2 + 0.07 * br : 0.62 + 0.2 * br)
        }
        MissionRidgePainter.blit(ctx, set.sun.glow, in: CGRect(x: x - R, y: y - R, width: R * 2, height: R * 2), alpha: a * fade)
        let dr = tf.w * 0.016 * (0.96 + 0.06 * br)
        MissionRidgePainter.blit(ctx, set.sun.disc, in: CGRect(x: x - dr, y: y - dr, width: dr * 2, height: dr * 2),
                                 alpha: sunK * (dark ? 0.12 : 0.5) * fade)
    }

    func paintRays(_ ctx: GraphicsContext, sunK: CGFloat) {
        if sunK <= 0.003 { return }
        let tf = plane(.peak)
        let sp = trail.sunPoint
        let x = tf.tx + sp.x * tf.w
        let y = tf.ty + sp.y * tf.h
        let drift: CGFloat = reduced ? 0 : 0.03 * sin(t / 21 * MissionRidgeMath.tau)   // about 1.7 deg over 21 s
        let base: CGFloat = 0.62 + drift
        let len = tf.w * 0.85
        let pulse: CGFloat = reduced ? 1 : 0.88 + 0.12 * sin(t / 8 * MissionRidgeMath.tau)
        var c = ctx
        c.translateBy(x: x, y: y)
        c.rotate(by: .radians(Double(base)))
        MissionRidgePainter.blit(c, set.sun.rays, in: CGRect(x: 0, y: -len * 0.32, width: len, height: len * 0.64), alpha: sunK * pulse * fade)
    }

    /// Three ink birds crossing the far range every 9.2 s.
    func paintBirds(_ ctx: GraphicsContext) {
        if reduced { return }
        let tf = plane(.far)
        let tau = MissionRidgeMath.tau
        let per: CGFloat = 9.2
        let offs: [CGFloat] = [0.0, 3.1, 6.0]
        let ys: [CGFloat] = [0.2, 0.27, 0.17]
        let scales: [CGFloat] = [1, 0.8, 0.9]
        let phases: [CGFloat] = [0, 1.7, 3.1]
        for b in 0..<3 {
            let ph = MissionRidgeMath.mod((t + offs[b]) / per, 1)
            let span: CGFloat = 0.82
            if ph > span { continue }
            let u = ph / span
            let x = MissionRidgeMath.lerp(-18, geo.size.width + 18, u)
            let wave: CGFloat = sin(u * tau * 1.3 + phases[b]) * 3
            let y: CGFloat = tf.ty + ys[b] * tf.h + wave - u * 6
            let edge = min(1, u / 0.1, (1 - u) / 0.1)
            let sz = 4.2 * scales[b]
            let burst = MissionRidgeMath.clamp(sin(t / 3.4 * tau + phases[b]) * 2 + 0.6, 0, 1)   // flap in bursts, glide between
            let fl = 0.35 + burst * sin(t * tau * 1.7 + phases[b]) * 0.55
            var p = Path()
            p.move(to: CGPoint(x: x - sz, y: y - sz * 0.15 - fl * sz * 0.8))
            p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - sz * 0.5, y: y - sz * 0.5 - fl * sz * 0.1))
            p.addQuadCurve(to: CGPoint(x: x + sz, y: y - sz * 0.15 - fl * sz * 0.8), control: CGPoint(x: x + sz * 0.5, y: y - sz * 0.5 - fl * sz * 0.1))
            ctx.stroke(p, with: .color(ink.opacity(Double(0.72 * edge * fade))),
                       style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
        }
    }
}
