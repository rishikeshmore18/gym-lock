//
//  RidgeWakeStage.swift
//  GymLock
//
//  The Ridge concepts of the "I'm up" wake page (web/morning2 ridge.tsx RidgeStage + RidgeCard), native.
//  One continuous painted world shot with a camera:
//
//    greet    night; first light grows behind the ridge; the camera settles on the mountain
//    commit   the camera pushes in on the gym: a coral mark lands where the trail meets the mountain
//    leave    A: the trail lights from your door to the gym while the camera follows it
//    mission  A: low on the near path, footsteps appear one by one
//    day      B: the camera climbs the switchbacks, 66 marks to the summit, today in coral
//    week     B: the camera pulls back over the mountain (the page draws the week's flames)
//    condense the world shrinks into the home card, peak to peak, and the card's painting takes over
//    idle     the card breathes (slow zoom), its mist sways, light moves over the peak, the gym pulses
//
//  Baked (Assets.xcassets/WakeRidge, tools/bake-ridge/bake.py, from the prototype's own painters):
//  the world at night and at first light, a 2x-density crop of it for the strongest push-ins, the
//  card's painting in the night and day looks, the card's mist sheets.
//  Drawn live: route ribbon and trail dashes, birds, stars and their twinkle, first light, the trail
//  lighting, footsteps, the 66 marks, the gym mark, its drop and ring, the summit ring, the card's
//  own marks, and the paper fade that keeps the card's copy column readable.
//
//  The page (WakeIntroView) clips to frame.stageRect, fills the stage colour, applies Reduce Motion's
//  crossfades, draws every word (placing the trail tags with `WakeStageAnchoring` below), the lift,
//  the hairline and the light wipe (a second pass with `frame.dark == false`, the card's day look).
//
//  Space: the painting is aspect-fill, top-aligned, and always covers the whole screen (full-bleed on
//  every device, iPad included). The page's words, tags and flames use the shared fit (WakeLayout.fit:
//  min(width/390, height/844, 1.25), centred column); the anchors below are Canvas (page) coordinates
//  of the objects on the painting, so the tags follow the art whatever the fit.
//  Time: seconds; the prototype's 30 fps frame offsets are converted. Everything is a function of
//  frame.t, so any time can be drawn, twice per frame if the page asks.
//

import SwiftUI

final class RidgeWakeStage: WakeStageRenderer {
    /// release the stage world's images (about 44 MB decoded) once the card has settled
    var releasesWorldWhenSettled = true

    private let world: RidgeWorld?

    // SwiftUI Images wrapping the cached CGImages, by layer slot (cheap value handles; resolved against
    // the drawing context on every use, because a ResolvedImage is tied to that context's environment).
    // Rebuilt when the canvas size or the cache generation changes.
    private var resolved: [Image?] = Array(repeating: nil, count: RidgeLayer.allCases.count)
    private var resolvedSize: CGSize = .zero
    private var resolvedGeneration = -1
    private var worldReleased = false

    // geometry, rebuilt only when a size or the step count changes
    private var stageGeo: StageGeometry?
    private var cardGeo: CardGeometry?
    private var steps: Footsteps?
    private var cardClip: (rect: CGRect, path: Path)?
    private var shadeCache: (height: Double, path: Path)?

    // shapes and paints made once
    private let unitCircle = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
    private let unitSquare = Path(CGRect(x: -1, y: -1, width: 2, height: 2))
    private let paints: Paints

    init() {
        let w = RidgeWorld.shared
        world = w
        paints = Paints(w)
        RidgeAssets.shared.prewarm()
    }

    // MARK: - Frame

    func draw(_ ctx: inout GraphicsContext, size: CGSize, frame: WakeFrame) {
        guard let world, size.width > 1, size.height > 1 else { return }
        let plan = frame.plan, t = frame.t, rm = plan.reduceMotion
        let fps = RidgeMath.fps
        let R = frame.stageRect
        let A = frame.concept == .ridgeA
        let loopT = Self.loopTime(plan, t)
        resolveImages(size: size)

        // light appearance's second pass: the card's day look, in the card's slot
        guard frame.dark else {
            drawCard(&ctx, world: world, rect: R, light: true, A: A, frame: frame, loopT: loopT)
            return
        }

        let M = Metrics(world, size)
        let k = RidgeMath.cl(plan.condenseProgress(at: t))
        let fr = t * fps, cond = plan.condenseAt * fps
        // the card's painting fades in over the contracting world (RidgeCard opacity); under Reduce
        // Motion the page fades the whole pass, so it simply replaces the stage once that is empty
        let cardOp = rm
            ? (fr >= cond + 3 ? 1.0 : 0.0)
            : RidgeMath.eio((fr - (cond + 15)) / max(1, plan.landAt * fps - (cond + 15))) * (k > 0 ? 1 : 0)
        let stageVisible = rm ? fr < cond + 3 : cardOp < 0.999

        if stageVisible {
            var c = ctx
            if let cx = Self.condenseTransform(world, M: M, size: size, rect: R, k: k, rm: rm) {
                c.translateBy(x: cx.tx, y: cx.ty)
                c.scaleBy(x: cx.s, y: cx.s)
            }
            drawStage(&c, world: world, M: M, frame: frame, A: A, loopT: loopT)
        }
        if fr >= cond - 2 && cardOp > 0 {
            // the slot the stage rect is heading for (the page lerps it from the screen by k)
            let card: CGRect
            if k >= 0.999 || k <= 0.05 {
                card = R
            } else {
                let W = Double(size.width), H = Double(size.height)
                card = CGRect(x: Double(R.minX) / k, y: Double(R.minY) / k,
                              width: W + (Double(R.width) - W) / k, height: H + (Double(R.height) - H) / k)
            }
            var c = ctx
            c.opacity = ctx.opacity * cardOp
            drawCard(&c, world: world, rect: card, light: false, A: A, frame: frame, loopT: loopT)
        }

        // the stage's world is not needed once the card has settled; it reloads if t goes back
        if stageVisible {
            worldReleased = false
        } else if releasesWorldWhenSettled && !worldReleased && t > max(plan.landAt, plan.condenseAt + 0.5) + 0.5 {
            worldReleased = true
            for layer in RidgeLayer.stage { resolved[layer.slot] = nil }
            RidgeAssets.shared.purge(RidgeLayer.stage)
            resolvedGeneration = RidgeAssets.shared.currentGeneration
        }
    }

    /// condense: the stage contracts into the slot, always covering it, the peak drifting to where the
    /// card's own painting has it (frame space to screen; nil while the stage is full screen)
    private static func condenseTransform(_ world: RidgeWorld, M: Metrics, size: CGSize, rect R: CGRect, k: Double, rm: Bool) -> (s: Double, tx: Double, ty: Double)? {
        guard !rm && k > 0 else { return nil }
        let W = Double(size.width), H = Double(size.height)
        let sc = max(Double(R.width) / W, Double(R.height) / H)
        let fx = Double(world.stage.peak.x) * M.Ww + M.ox
        let fy = RidgeMath.lerp(0.5 * H, (Double(world.stage.peak.y) + 0.1) * M.Hw, k)
        var tx = Double(R.minX) + Double(R.width) * RidgeMath.lerp(0.5, 0.66, k) - sc * fx
        var ty = Double(R.minY) + Double(R.height) * 0.5 - sc * fy
        tx = min(Double(R.minX), max(Double(R.maxX) - sc * M.Fw, tx))
        ty = min(Double(R.minY), max(Double(R.maxY) - sc * M.Fh, ty))
        return (sc, tx, ty)
    }

    /// seconds into the idle loop, continuous across the intro's end (the prototype's
    /// ((f - intro) mod IDLE) / FPS, which also drives the birds during the chapters)
    private static func loopTime(_ plan: WakePlan, _ t: Double) -> Double {
        let len = plan.idleLength > 0 ? plan.idleLength : 12
        let x = (t - plan.introEnd).truncatingRemainder(dividingBy: len)
        return x < 0 ? x + len : x
    }

    /// the stage's frame on this screen: aspect-fill, the screen's width and at least its height,
    /// top-aligned (a short phone shows the top of a taller frame), and the world filling it. It covers
    /// the full Canvas; only the overlays follow WakeLayout.fit
    private struct Metrics {
        /// the design frame
        let Fw, Fh: Double
        /// the world at zoom 1, and its left edge in the frame (0 unless the frame is unusually tall)
        let Ww, Hw, ox: Double

        init(_ world: RidgeWorld, _ size: CGSize) {
            let dw = Double(world.stageSize.width), dh = Double(world.stageSize.height)
            let W = Double(size.width), H = Double(size.height)
            Fw = W
            Fh = max(dh * W / dw, H)
            let aspect = dw / dh
            Ww = max(Fw, Fh * aspect)
            Hw = Ww / aspect
            ox = (Fw - Ww) / 2
        }

        /// the camera as a translate and scale of world points (ridge.tsx xfOf: the painting always
        /// covers the frame)
        func transform(_ cam: RidgeCam) -> (s: Double, tx: Double, ty: Double) {
            let s = max(1, cam.s)
            let tx = min(0, max(Fw - s * Ww, cam.ax * Fw - s * cam.cx * Ww))
            let ty = min(0, max(Fh - s * Hw, cam.ay * Fh - s * cam.cy * Hw))
            return (s, tx, ty)
        }
    }

    // MARK: - Images

    private func resolveImages(size: CGSize) {
        let gen = RidgeAssets.shared.currentGeneration
        if size != resolvedSize || gen != resolvedGeneration {
            for i in resolved.indices { resolved[i] = nil }
            resolvedSize = size
            resolvedGeneration = gen
        }
    }

    /// the layer's image resolved in THIS context (resolved per use: it is tied to the context's
    /// environment); the Image and its decoded CGImage are cached
    private func image(_ layer: RidgeLayer, _ ctx: inout GraphicsContext) -> GraphicsContext.ResolvedImage? {
        if let img = resolved[layer.slot] { return ctx.resolve(img) }
        guard let cg = RidgeAssets.shared.image(layer) else { return nil }
        let img = Image(decorative: cg, scale: 1).interpolation(.medium)
        resolved[layer.slot] = img
        return ctx.resolve(img)
    }

    // MARK: - The stage world (RidgeStage)

    private func drawStage(_ c: inout GraphicsContext, world: RidgeWorld, M: Metrics, frame: WakeFrame, A: Bool, loopT: Double) {
        let plan = frame.plan, t = frame.t
        let G = stageGeometry(world, Ww: M.Ww, Hw: M.Hw)
        let dawn = world.dawnProgress(plan: plan, at: t)
        let xf = M.transform(world.camera(plan: plan, at: t))
        let worldRect = CGRect(x: 0, y: 0, width: M.Ww, height: M.Hw)
        let base = c.opacity

        var w = c
        w.translateBy(x: xf.tx, y: xf.ty)
        w.scaleBy(x: xf.s, y: xf.s)
        // night and first light are two paintings crossfaded, so light rises smoothly
        if dawn < 0.999 {
            if let img = image(.worldNight, &w) { w.draw(img, in: worldRect) }
            drawRoute(&w, G.route, paints.night)
        }
        if dawn > 0.001 {
            w.opacity = base * dawn
            if let img = image(.worldDawn, &w) { w.draw(img, in: worldRect) }
            if xf.s > 1.2, let r = world.rects[.worldDawnHi], let hi = image(.worldDawnHi, &w) {
                w.draw(hi, in: CGRect(x: Double(r.minX) * M.Ww, y: Double(r.minY) * M.Hw, width: Double(r.width) * M.Ww, height: Double(r.height) * M.Hw))
            }
            drawRoute(&w, G.route, paints.dawn)
            drawBirds(&w, width: M.Ww, height: M.Hw, horizon: world.stage.horizon, count: world.idle.birdsStage, shading: paints.dawn.bird, t: loopT)
            w.opacity = base
        }
        drawOverlays(&w, world: world, G: G, frame: frame, A: A, dawn: dawn, cs: xf.s)

        // the top of the sky darkens a touch so the words always read (frame space)
        let shadeH = M.Fh * 0.42
        if shadeCache?.height != shadeH { shadeCache = (shadeH, Path(CGRect(x: 0, y: 0, width: M.Fw, height: shadeH))) }
        if let shade = shadeCache?.path {
            c.fill(shade, with: .linearGradient(paints.topShade, startPoint: .zero, endPoint: CGPoint(x: 0, y: shadeH)))
        }
    }

    private func drawRoute(_ c: inout GraphicsContext, _ r: RouteGeometry, _ p: LookPaints) {
        // the walked path: a pale band narrowing with distance, one stroke per segment as the painter does
        for i in r.ribbon.indices {
            c.stroke(r.ribbon[i], with: p.ribbon, style: StrokeStyle(lineWidth: r.ribbonWidths[i], lineCap: .round, lineJoin: .round))
        }
        // the trail up the mountain: dashes
        c.stroke(r.dashes, with: p.dash, style: r.dashStyle)
    }

    /// wash2.ts birds: n strokes crossing the sky (one small Path a frame)
    private func drawBirds(_ c: inout GraphicsContext, width ww: Double, height hh: Double, horizon: Double, count: Int, shading: GraphicsContext.Shading, t: Double) {
        guard count > 0 else { return }
        let top = horizon * hh
        var p = Path()
        for i in 0..<count {
            let sp = 0.012 + Double(i % 3) * 0.004
            let x = (0.35 + Double(i) * 0.07 + t * sp).truncatingRemainder(dividingBy: 1.1) * ww
            let y = top * (0.35 + 0.18 * sin(Double(i) * 2.3)) + sin(t * 0.8 + Double(i)) * hh * 0.01
            let s = hh * (0.012 + Double(i % 2) * 0.004)
            let flap = sin(t * 6 + Double(i) * 1.7) * 0.5
            p.move(to: CGPoint(x: x - s, y: y - s * (0.3 + flap * 0.4)))
            p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - s * 0.4, y: y - s * 0.1))
            p.addQuadCurve(to: CGPoint(x: x + s, y: y - s * (0.3 + flap * 0.4)), control: CGPoint(x: x + s * 0.4, y: y - s * 0.1))
        }
        c.stroke(p, with: shading, style: StrokeStyle(lineWidth: max(0.34, ww / 700), lineCap: .round))
    }

    /// what each chapter adds to the world (ridge.tsx overlays), in world points under the camera
    private func drawOverlays(_ c: inout GraphicsContext, world: RidgeWorld, G: StageGeometry, frame: WakeFrame, A: Bool, dawn: Double, cs: Double) {
        let plan = frame.plan, t = frame.t, rm = plan.reduceMotion, F = frame.facts
        let fps = RidgeMath.fps
        let fr = t * fps, cond = plan.condenseAt * fps
        let w = Double(G.size.width), h = Double(G.size.height), s = G.s
        let base = c.opacity

        // first light: a pale band of light behind the ridge
        if dawn > 0.01 {
            let center = CGPoint(x: Double(G.peak.x), y: Double(G.peak.y) + h * 0.02)
            c.blendMode = .screen
            c.opacity = base * dawn
            c.fill(G.worldRect, with: .radialGradient(paints.firstLight, center: center, startRadius: 0, endRadius: w * 0.9))
            c.opacity = base
            c.blendMode = .normal
        }
        // stars, going out as the light comes
        if dawn < 0.98 {
            for i in G.stars.indices {
                let tw = 0.75 + 0.25 * sin(fr * 0.07 + Double(i) * 1.7)
                c.opacity = base * G.starAlpha[i] * (1 - dawn) * tw
                c.fill(G.stars[i], with: paints.white)
            }
            c.opacity = base
        }

        let commit = RidgeWorld.find(plan, .commit)
        let lb = RidgeWorld.find(plan, .leave), mb = RidgeWorld.find(plan, .mission), db = RidgeWorld.find(plan, .day)

        // the trail lighting from your door to the gym (A: leave; it stays lit after)
        if let lb {
            let trail = rm ? (t >= lb.start ? 1.0 : 0.0) : RidgeMath.ez2((fr - (lb.start * fps + 4)) / 46)
            let dim = mb.map { 1 - 0.55 * RidgeMath.settle((fr - $0.start * fps) / 12) } ?? 1
            if trail > 0 {
                let n = StageGeometry.trailN
                let u0 = world.leaveU, uEnd = RidgeMath.lerp(u0, 1, trail)
                let i0 = Int((Double(n) * u0).rounded(.down))
                let blur = s * 0.02 / cs // the web's shadowBlur is in screen space
                let endPt = scaled(world.stage.walkPoly.at(uEnd), w, h)
                var partial: Path?
                // a glow (standing in for the web's shadowBlur), then the line
                for pass in 0..<3 {
                    var i = i0
                    while i < n && Double(i) < Double(n) * uEnd {
                        let al = (0.75 + 0.25 * Double(i) / Double(n)) * dim
                        let wd = G.trailWidths[i]
                        let seg: Path
                        if Double(i + 1) / Double(n) <= uEnd {
                            seg = G.trailSegs[i]
                        } else {
                            if partial == nil {
                                var p = Path()
                                p.move(to: G.trailPts[i])
                                p.addLine(to: endPt)
                                partial = p
                            }
                            seg = partial ?? G.trailSegs[i]
                        }
                        switch pass {
                        case 0:
                            c.opacity = base * 0.1 * al
                            c.stroke(seg, with: paints.glow, style: StrokeStyle(lineWidth: wd + blur * 1.6, lineCap: .round))
                        case 1:
                            c.opacity = base * 0.16 * al
                            c.stroke(seg, with: paints.glow, style: StrokeStyle(lineWidth: wd + blur * 0.7, lineCap: .round))
                        default:
                            c.opacity = base * al
                            c.stroke(seg, with: paints.white, style: StrokeStyle(lineWidth: wd, lineCap: .round))
                        }
                        i += 1
                    }
                }
                c.opacity = base
                // the leave point: a bright tick near your door
                let tk = RidgeMath.ez((fr - lb.start * fps - 30) / 10)
                if tk > 0 {
                    c.opacity = base * tk
                    circle(&c, G.leave, s * 0.016 * tk, fill: paints.white)
                    c.opacity = base * 0.5 * tk
                    ring(&c, G.leave, s * 0.032, width: s * 0.003, paints.white)
                    c.opacity = base
                }
            }
        }

        // footsteps on the near path (A: mission), one per step of the mission (6 to 24)
        if let mb, fr >= mb.start * fps - 2, fr < cond + 20 {
            let N = min(24, max(6, F.missionSteps > 0 ? F.missionSteps : 12))
            let prints = footsteps(world, G: G, n: N).prints
            let ml = t - mb.start
            let lit = rm ? N : min(N, Int((Double(N) * RidgeMath.cl((ml - 0.35) / 1.4)).rounded(.down)) + (ml > 0.35 ? 1 : 0))
            let fade = 1 - RidgeMath.cl((fr - cond) / 12)
            for k in 0..<min(N, prints.count) {
                if k == lit - 1 {
                    c.opacity = base * fade
                    c.fill(prints[k], with: paints.coral)
                } else {
                    c.opacity = base * (k < lit ? 0.95 : 0.18) * fade
                    c.fill(prints[k], with: paints.white)
                }
            }
            c.opacity = base
        }

        // 66 marks up the switchbacks to the summit (B: day), today in coral
        if let db, fr >= db.start * fps - 2 {
            let dl = t - db.start
            let day = F.habitDay
            let lived = min(66, day - 1), todayK = min(66, day) - 1
            let n = rm ? lived : Int((Double(lived) * RidgeMath.ez((dl - 0.25) / 1.5)).rounded(.down))
            let todayOn = rm || dl > 1.8
            let fade = fr >= cond ? 1 - RidgeMath.cl((fr - cond) / 12) : 1
            for k in 0..<min(66, G.marks.count) {
                if k == todayK && day <= 66 {
                    guard todayOn else { continue }
                    let r = s * 0.0085
                    let pp = rm ? 1 : RidgeMath.spr(dl - 1.8, 14, 8)
                    c.opacity = base * 0.5 * fade
                    glow(&c, G.marks[k], r * 5, paints.coralGlow)
                    c.opacity = base * fade
                    circle(&c, G.marks[k], r * max(0.2, pp), fill: paints.coral)
                    continue
                }
                c.opacity = base * (k < n || day > 66 ? 0.95 : 0.22) * fade
                c.fill(G.markDots[k], with: paints.white)
            }
            c.opacity = base * 0.9 * fade
            c.stroke(G.summitRing, with: paints.white, lineWidth: s * 0.0035)
            c.opacity = base
        }

        // the gym: a coral mark where the trail meets the mountain (B: it turns light once the run takes coral)
        if let commit {
            let tGym = t - commit.start - 13 / fps
            if tGym > -0.05 {
                let isCoral = A || db == nil || fr < (db?.start ?? 0) * fps + 40
                let fill = isCoral ? paints.coral : paints.white
                let fade = fr >= cond ? 1 - RidgeMath.cl((fr - cond) / 14) : 1
                let drop = rm ? 1 : RidgeMath.spr(tGym, 12, 7)
                let r = s * 0.011
                c.opacity = base * 0.4 * fade
                glow(&c, G.foot, r * 4.5, isCoral ? paints.coralGlow : paints.whiteGlow)
                c.opacity = base * fade
                circle(&c, CGPoint(x: Double(G.foot.x), y: Double(G.foot.y) - (1 - min(1, drop)) * h * 0.06), r * max(0.3, drop), fill: fill)
                // one ring as it lands
                if !rm && tGym > 0.12 && tGym < 0.9 {
                    let q = (tGym - 0.12) / 0.78
                    c.opacity = base * 0.7 * (1 - q) * fade
                    ring(&c, G.foot, r * (1.5 + 7 * RidgeMath.ez(q)), width: s * 0.004 * (1 - q) + 0.34, fill)
                }
                c.opacity = base
            }
        }
    }

    // MARK: - The home card (card13 RidgeCard)

    private func drawCard(_ ctx: inout GraphicsContext, world: RidgeWorld, rect: CGRect, light: Bool, A: Bool, frame: WakeFrame, loopT t: Double) {
        let w = Double(rect.width), h = Double(rect.height)
        guard w > 1, h > 1 else { return }
        let G = cardGeometry(world, w: w, h: h)
        let rm = frame.plan.reduceMotion
        let loop = frame.plan.idleLength > 0 ? frame.plan.idleLength : 12
        let look = light ? paints.cardLight : paints.cardDark
        let base = ctx.opacity
        var c = ctx
        if cardClip?.rect != rect { cardClip = (rect, Path(roundedRect: rect, cornerRadius: WakeLayout.cardRadius, style: .continuous)) }
        if let clip = cardClip?.path { c.clip(to: clip) }
        c.translateBy(x: Double(rect.minX), y: Double(rect.minY))
        c.fill(G.box, with: light ? paints.paperLight : paints.paperDark)

        // idle: the card's camera breathes in and out once a loop
        let phase = t / loop * 2 * Double.pi
        let zs = rm ? 1.0 : 1.03 + 0.03 * sin(phase)
        var p = c
        p.concatenate(CGAffineTransform(a: zs, b: 0, c: 0, d: zs, tx: -(zs - 1) * w * 0.7, ty: -(zs - 1) * h * 0.4))
        if let img = image(light ? .cardLight : .cardDark, &p) { p.draw(img, in: G.rect) }
        // the painter's mist sheets sway across the valley, once a loop
        let mistLayer: RidgeLayer = light ? .cardMistLight : .cardMistDark
        if !rm, world.idle.cardMistAlpha > 0, let mr = world.rects[mistLayer], let mist = image(mistLayer, &p) {
            let sway = world.idle.mistSway * w * sin(phase)
            p.opacity = base * world.idle.cardMistAlpha
            p.draw(mist, in: CGRect(x: -w * 0.5 + sway, y: Double(mr.minY) * h, width: Double(mr.width) * w, height: Double(mr.height) * h))
            p.opacity = base
        }
        // light moves over the peak
        if !rm, world.idle.lightSweep > 0 {
            let lx = (Double(world.card.peak.x) + 0.08 * sin(phase)) * w
            let ly = (Double(world.card.peak.y) + 0.12) * h
            if !light { p.blendMode = .screen }
            p.opacity = base * world.idle.lightSweep
            p.fill(G.box, with: .radialGradient(look.sunGlow, center: CGPoint(x: lx, y: ly), startRadius: 0, endRadius: w * 0.35))
            p.opacity = base
            p.blendMode = .normal
        }
        drawRoute(&p, G.route, look)
        drawBirds(&p, width: w, height: h, horizon: world.card.horizon, count: world.idle.birdsCard, shading: look.bird, t: t)

        // the card's own marks: A the walk and the gym in coral; B the 66 with today in coral
        let ws = min(w, h)
        let ink = light ? paints.inkLight : paints.white
        if A {
            p.opacity = base * 0.8
            p.stroke(G.walkLine, with: ink, style: StrokeStyle(lineWidth: max(0.4, ws * 0.007), lineCap: .round, lineJoin: .round))
            p.opacity = base * (rm ? 1.0 : 0.85 + 0.15 * cos(t / 3 * 2 * Double.pi))
            circle(&p, G.gym, ws * 0.03, fill: paints.coral)
            p.opacity = base
        } else {
            let day = frame.facts.habitDay
            let lived = min(66, day - 1), todayK = min(66, day) - 1
            for i in 0..<min(66, G.marks.count) {
                if i == todayK && day <= 66 {
                    p.opacity = base
                    circle(&p, G.marks[i], ws * 0.02, fill: paints.coral)
                } else {
                    p.opacity = base * (i < lived || day > 66 ? 0.85 : 0.22)
                    p.fill(G.markDots[i], with: ink)
                }
            }
            p.opacity = base
        }
        // paper bleeds in from the left so the copy column reads
        c.fill(G.box, with: .linearGradient(light ? paints.fadeLight : paints.fadeDark, startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
    }

    // MARK: - Small shapes (unit shapes under a transform: no per-frame paths)

    private func circle(_ ctx: inout GraphicsContext, _ p: CGPoint, _ r: Double, fill: GraphicsContext.Shading) {
        guard r > 0 else { return }
        let saved = ctx.transform
        ctx.translateBy(x: p.x, y: p.y)
        ctx.scaleBy(x: r, y: r)
        ctx.fill(unitCircle, with: fill)
        ctx.transform = saved
    }

    private func ring(_ ctx: inout GraphicsContext, _ p: CGPoint, _ r: Double, width: Double, _ shading: GraphicsContext.Shading) {
        guard r > 0 else { return }
        let saved = ctx.transform
        ctx.translateBy(x: p.x, y: p.y)
        ctx.scaleBy(x: r, y: r)
        ctx.stroke(unitCircle, with: shading, lineWidth: width / r)
        ctx.transform = saved
    }

    /// a radial glow from full at p to clear at radius r (the context's opacity carries its strength)
    private func glow(_ ctx: inout GraphicsContext, _ p: CGPoint, _ r: Double, _ g: Gradient) {
        guard r > 0 else { return }
        let saved = ctx.transform
        ctx.translateBy(x: p.x, y: p.y)
        ctx.scaleBy(x: r, y: r)
        ctx.fill(unitSquare, with: .radialGradient(g, center: .zero, startRadius: 0, endRadius: 1))
        ctx.transform = saved
    }

    @inline(__always) private func scaled(_ p: CGPoint, _ w: Double, _ h: Double) -> CGPoint {
        CGPoint(x: Double(p.x) * w, y: Double(p.y) * h)
    }

    // MARK: - Geometry caches

    private struct RouteGeometry {
        let ribbon: [Path]
        let ribbonWidths: [Double]
        let dashes: Path
        let dashStyle: StrokeStyle

        init(_ r: RidgeRoute, w: Double, h: Double) {
            var segs: [Path] = []
            var widths: [Double] = []
            segs.reserveCapacity(r.walk.count)
            widths.reserveCapacity(r.walk.count)
            if r.walk.count > 1 {
                for i in 0..<(r.walk.count - 1) {
                    var p = Path()
                    p.move(to: CGPoint(x: Double(r.walk[i].x) * w, y: Double(r.walk[i].y) * h))
                    p.addLine(to: CGPoint(x: Double(r.walk[i + 1].x) * w, y: Double(r.walk[i + 1].y) * h))
                    segs.append(p)
                    widths.append((i < r.walkWidths.count ? r.walkWidths[i] : 0.004) * w)
                }
            }
            ribbon = segs
            ribbonWidths = widths
            var d = Path()
            for (i, q) in r.climb.enumerated() {
                let pt = CGPoint(x: Double(q.x) * w, y: Double(q.y) * h)
                if i == 0 { d.move(to: pt) } else { d.addLine(to: pt) }
            }
            dashes = d
            dashStyle = StrokeStyle(lineWidth: CGFloat(max(0.34, r.dashWidth * w)), lineCap: .round, lineJoin: .round,
                                    dash: [CGFloat(r.dash.on * w), CGFloat(r.dash.off * w)])
        }
    }

    private struct StageGeometry {
        static let trailN = 70
        let size: CGSize
        let s: Double
        let worldRect: Path
        let route: RouteGeometry
        let stars: [Path]
        let starAlpha: [Double]
        let trailPts: [CGPoint]
        let trailSegs: [Path]
        let trailWidths: [Double]
        let marks: [CGPoint]
        let markDots: [Path]
        let summitRing: Path
        let foot: CGPoint
        let leave: CGPoint
        let peak: CGPoint

        init(_ world: RidgeWorld, w: Double, h: Double) {
            size = CGSize(width: w, height: h)
            let s = min(w, h)
            self.s = s
            worldRect = Path(CGRect(x: 0, y: 0, width: w, height: h))
            route = RouteGeometry(world.stage, w: w, h: h)
            stars = world.stars.map { st -> Path in
                let r = max(0.27, s * 0.0016 * st.m)
                return Path(ellipseIn: CGRect(x: st.x * w - r, y: st.y * h - r, width: r * 2, height: r * 2))
            }
            starAlpha = world.stars.map { $0.a }
            let n = Self.trailN
            let pts: [CGPoint] = (0...n).map { i in
                let p = world.stage.walkPoly.at(Double(i) / Double(n))
                return CGPoint(x: Double(p.x) * w, y: Double(p.y) * h)
            }
            trailPts = pts
            var segs: [Path] = []
            var widths: [Double] = []
            segs.reserveCapacity(n)
            widths.reserveCapacity(n)
            for i in 0..<n {
                var p = Path()
                p.move(to: pts[i])
                p.addLine(to: pts[i + 1])
                segs.append(p)
                let u = Double(i) / Double(n)
                widths.append(max(0.4, w * 0.0055 * pow(1 - u, 1.2) + w * 0.002))
            }
            trailSegs = segs
            trailWidths = widths
            let mk = world.stage.marks66.map { CGPoint(x: Double($0.x) * w, y: Double($0.y) * h) }
            marks = mk
            let mr = s * 0.0042
            markDots = mk.map { Path(ellipseIn: CGRect(x: Double($0.x) - mr, y: Double($0.y) - mr, width: mr * 2, height: mr * 2)) }
            let top = CGPoint(x: Double(world.summit.x) * w, y: Double(world.summit.y) * h)
            let rr = s * 0.012
            summitRing = Path(ellipseIn: CGRect(x: Double(top.x) - rr, y: Double(top.y) - rr, width: rr * 2, height: rr * 2))
            foot = CGPoint(x: Double(world.foot.x) * w, y: Double(world.foot.y) * h)
            leave = CGPoint(x: Double(world.leavePoint.x) * w, y: Double(world.leavePoint.y) * h)
            peak = CGPoint(x: Double(world.stage.peak.x) * w, y: Double(world.stage.peak.y) * h)
        }
    }

    private struct CardGeometry {
        let size: CGSize
        let rect: CGRect
        let box: Path
        let route: RouteGeometry
        let walkLine: Path
        let marks: [CGPoint]
        let markDots: [Path]
        let gym: CGPoint

        init(_ world: RidgeWorld, w: Double, h: Double) {
            size = CGSize(width: w, height: h)
            rect = CGRect(x: 0, y: 0, width: w, height: h)
            box = Path(CGRect(x: 0, y: 0, width: w, height: h))
            route = RouteGeometry(world.card, w: w, h: h)
            var line = Path()
            for (i, q) in world.card.walk.enumerated() {
                let pt = CGPoint(x: Double(q.x) * w, y: Double(q.y) * h)
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            walkLine = line
            let mk = world.card.marks66.map { CGPoint(x: Double($0.x) * w, y: Double($0.y) * h) }
            marks = mk
            let r = min(w, h) * 0.004
            markDots = mk.map { Path(ellipseIn: CGRect(x: Double($0.x) - r, y: Double($0.y) - r, width: r * 2, height: r * 2)) }
            gym = CGPoint(x: Double(world.cardGym.x) * w, y: Double(world.cardGym.y) * h)
        }
    }

    private struct Footsteps {
        let n: Int
        let size: CGSize
        let prints: [Path]
    }

    private func stageGeometry(_ world: RidgeWorld, Ww: Double, Hw: Double) -> StageGeometry {
        if let g = stageGeo, abs(Double(g.size.width) - Ww) < 0.001, abs(Double(g.size.height) - Hw) < 0.001 { return g }
        let g = StageGeometry(world, w: Ww, h: Hw)
        stageGeo = g
        return g
    }

    /// cached for the last card size (the condense resizes it every frame; settled it stays put)
    private func cardGeometry(_ world: RidgeWorld, w: Double, h: Double) -> CardGeometry {
        if let g = cardGeo, abs(Double(g.size.width) - w) < 0.01, abs(Double(g.size.height) - h) < 0.01 { return g }
        let g = CardGeometry(world, w: w, h: h)
        cardGeo = g
        return g
    }

    /// footprints along the near path, alternating sides, smaller with distance (rebuilt when N changes)
    private func footsteps(_ world: RidgeWorld, G: StageGeometry, n: Int) -> Footsteps {
        if let f = steps, f.n == n, f.size == G.size { return f }
        let w = Double(G.size.width), h = Double(G.size.height), s = G.s
        var prints: [Path] = []
        prints.reserveCapacity(n)
        for k in 0..<n {
            let u = world.leaveU + 0.01 + Double(k) / Double(max(1, n - 1)) * 0.3
            let p = scaled(world.stage.walkPoly.at(u), w, h), q = scaled(world.stage.walkPoly.at(u + 0.004), w, h)
            let ang = atan2(Double(q.y - p.y), Double(q.x - p.x))
            let side = k % 2 == 1 ? 1.0 : -1.0
            let wd = w * 0.011 * pow(1 - u, 1.4) + w * 0.003
            let x = Double(p.x) + cos(ang + .pi / 2) * side * wd * 0.55
            let y = Double(p.y) + sin(ang + .pi / 2) * side * wd * 0.55
            let sz = s * (0.0085 * (1 - u * 0.7) + 0.0022)
            var fp = Path(ellipseIn: CGRect(x: -sz * 0.55, y: -sz, width: sz * 1.1, height: sz * 2))
            fp.addEllipse(in: CGRect(x: -sz * 0.42, y: sz * 1.55 - sz * 0.45, width: sz * 0.84, height: sz * 0.9))
            prints.append(fp.applying(CGAffineTransform(rotationAngle: ang + .pi / 2).concatenating(CGAffineTransform(translationX: x, y: y))))
        }
        let f = Footsteps(n: n, size: G.size, prints: prints)
        steps = f
        return f
    }

    // MARK: - Paints (made once)

    private struct LookPaints {
        let ribbon: GraphicsContext.Shading
        let dash: GraphicsContext.Shading
        let bird: GraphicsContext.Shading
        let sunGlow: Gradient
        init(_ l: RidgeLook?) {
            let fallback = RidgeRGBA([128, 128, 128], 0.8)
            ribbon = .color((l?.ribbon ?? fallback).color)
            dash = .color((l?.dash ?? fallback).color)
            bird = .color((l?.bird ?? fallback).color)
            let sun = l?.sun ?? RidgeRGBA([230, 230, 232])
            sunGlow = Gradient(stops: [.init(color: Color(.sRGB, red: sun.r, green: sun.g, blue: sun.b, opacity: 1), location: 0),
                                       .init(color: Color(.sRGB, red: sun.r, green: sun.g, blue: sun.b, opacity: 0), location: 1)])
        }
    }

    private struct Paints {
        let night, dawn, cardDark, cardLight: LookPaints
        let white, coral, glow, inkLight, paperDark, paperLight: GraphicsContext.Shading
        let firstLight, topShade, coralGlow, whiteGlow, fadeDark, fadeLight: Gradient

        init(_ world: RidgeWorld?) {
            func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
            night = LookPaints(world?.night)
            dawn = LookPaints(world?.dawn)
            cardDark = LookPaints(world?.cardDark)
            cardLight = LookPaints(world?.cardLight)
            white = .color(rgb(255, 252, 246))
            coral = .color(rgb(232, 93, 78))
            glow = .color(rgb(255, 250, 240))
            inkLight = .color(rgb(20, 20, 22))
            paperDark = .color(rgb(14, 14, 16))
            paperLight = .color(rgb(246, 246, 244))
            firstLight = Gradient(stops: [.init(color: rgb(255, 250, 240, 0.3), location: 0), .init(color: rgb(255, 250, 240, 0.1), location: 0.4), .init(color: rgb(255, 250, 240, 0), location: 1)])
            topShade = Gradient(stops: [.init(color: rgb(8, 8, 9, 0.55), location: 0), .init(color: rgb(8, 8, 9, 0), location: 1)])
            coralGlow = Gradient(stops: [.init(color: rgb(232, 93, 78, 1), location: 0), .init(color: rgb(232, 93, 78, 0), location: 1)])
            whiteGlow = Gradient(stops: [.init(color: rgb(255, 252, 246, 1), location: 0), .init(color: rgb(255, 252, 246, 0), location: 1)])
            func fade(_ r: Double, _ g: Double, _ b: Double) -> Gradient {
                Gradient(stops: [.init(color: rgb(r, g, b, 1), location: 0), .init(color: rgb(r, g, b, 0.96), location: 0.32), .init(color: rgb(r, g, b, 0.7), location: 0.44),
                                 .init(color: rgb(r, g, b, 0.3), location: 0.55), .init(color: rgb(r, g, b, 0), location: 0.66)])
            }
            fadeDark = fade(14, 14, 16)
            fadeLight = fade(246, 246, 244)
        }
    }
}

// MARK: - Where the page's words go

extension RidgeWakeStage: WakeStageAnchoring {
    /// The trail's objects on screen this frame, after the camera (ridge.tsx ridgeLabels' `at`).
    func anchor(_ anchor: WakeAnchor, size: CGSize, frame: WakeFrame) -> CGPoint? {
        guard let world, size.width > 1, size.height > 1 else { return nil }
        let p: CGPoint
        switch anchor {
        case .ridgeLeave: p = world.leavePoint
        case .ridgeGym: p = world.foot
        case .ridgeSummit: p = world.summit
        default: return nil
        }
        let M = Metrics(world, size)
        let xf = M.transform(world.camera(plan: frame.plan, at: frame.t))
        // frame space, then the condense move (the page keeps a chapter's tags for a few frames into it)
        var q = CGPoint(x: xf.tx + xf.s * Double(p.x) * M.Ww, y: xf.ty + xf.s * Double(p.y) * M.Hw)
        let k = RidgeMath.cl(frame.plan.condenseProgress(at: frame.t))
        if let cx = Self.condenseTransform(world, M: M, size: size, rect: frame.stageRect, k: k, rm: frame.plan.reduceMotion) {
            q = CGPoint(x: cx.tx + cx.s * Double(q.x), y: cx.ty + cx.s * Double(q.y))
        }
        return q
    }
}

private extension RidgeLayer {
    /// index into the renderer's resolved-image table
    var slot: Int {
        switch self {
        case .worldNight: return 0
        case .worldDawn: return 1
        case .worldDawnHi: return 2
        case .cardDark: return 3
        case .cardLight: return 4
        case .cardMistDark: return 5
        case .cardMistLight: return 6
        }
    }
}
