//
//  MatrixWakeStage.swift
//  GymLock · Wake intro, Matrix concepts (native port)
//
//  The Matrix renderer for the wake stage: the dot visuals of morning2 (matrix.tsx MatrixCanvas,
//  board.ts Sim and drawDots, the camera and Reduce Motion crossfades of stage.tsx), drawn into
//  `frame.stageRect`. Copy, labels, the stage background and the card chrome are drawn by others.
//
//  Determinism: the engine ticks on the web's 30 fps grid exactly like board.ts `Sim` (one scene frame
//  per tick, engine time k / 30, 1/120 s physics substeps, dt clamped to 0.1 s, a re-deal whenever the
//  chapter key changes, snapshots every second). A render at time t draws the engine states of ticks
//  floor(t * 30) and +1, interpolated, so a frame at time t is the same on every device, at 60 or
//  120 Hz, after a scrub, and equal to the web at every whole frame. Once the intro is over the engine
//  time loops over the 12 s idle (all idle motions divide it), so memory and work stay bounded.
//
//  Mapping: the web page is 390 x 844 design points. The design rect of the stage at condense
//  progress k, lerp(page, card slot, k), is mapped onto `frame.stageRect` (uniform scale,
//  top-aligned): the full screen during chapters, the card slot when settled. On a 390 x 844
//  screen with the web's card slot this is the identity, i.e. pixel-for-pixel the web.
//
//  Looks: `draw` paints exactly the look `frame.dark` asks for. The page clips, fills the stage colour,
//  applies Reduce Motion's content fades and runs the light wipe between its two passes.
//
//  Cost per frame: at most one tick (scene + engine, ~0.1 to 0.2 ms) every other frame at 60 Hz,
//  then one pass over 1,500 dots into 7 brightness paths + 1 coral path (built once per frame, reused
//  by the light appearance's second pass), 8 fills per pass, and one or two cached grid images.
//

import SwiftUI

// MARK: - Sim (board.ts Sim)

/// Steps the engine one web frame at a time from the scene, with snapshots, so any frame can be
/// reached deterministically. A value type: copying it copies the whole simulation (copy-on-write).
public struct MatrixWakeSim: Sendable {
    public let scene: MatrixWakeScene
    public private(set) var eng: MatrixWakeEngine
    /// The tick the engine is at (-1: fresh).
    public private(set) var at: Int = -1
    private var snaps: [Int: MatrixWakeEngine] = [:]
    private var full: MatrixWakeBoard
    private var card: MatrixWakeBoard
    private var T = ContiguousArray<MatrixWakeTarget>()
    private let introTick: Int
    // the state one tick before `at`, for interpolation
    public private(set) var prevTick: Int = .min
    public private(set) var prevX: ContiguousArray<Float>
    public private(set) var prevY: ContiguousArray<Float>
    public private(set) var prevB: ContiguousArray<Float>

    public init(scene: MatrixWakeScene) {
        self.scene = scene
        eng = MatrixWakeEngine(n: MatrixWakeGeo.N_DOTS, cols: MatrixWakeGeo.COLS, rows: MatrixWakeGeo.ROWS)
        eng.brightnessMode = .perFrame
        let boards = MatrixWakeScene.makeBoards()
        full = boards.full
        card = boards.card
        T.reserveCapacity(MatrixWakeGeo.FULL_CAP + MatrixWakeGeo.CARD_CAP)
        let it = scene.timeline.intro.rounded(.down)
        introTick = it.isFinite && it >= 0 && it < 1_000_000 ? Int(it) : 0
        let z = ContiguousArray<Float>(repeating: 0, count: MatrixWakeGeo.N_DOTS)
        prevX = z; prevY = z; prevB = z
    }

    private mutating func step(_ k: Int) {
        let out = scene.frame(Double(k), full: &full, card: &card)
        MatrixWakeScene.targets(full: full, card: card, hasCard: out.hasCard, into: &T)
        eng.update(key: out.key, targets: T, t: Double(k) / MatrixWakeGeo.FPS, options: out.opts ?? MatrixWakeDealOptions(stagger: 0.25))
        // first frame, and every change under Reduce Motion: dots are where they belong, no flight
        let rm = scene.timeline.rm
        if k == 0 || rm { eng.snapToTargets(brightnessToTarget: rm) }
        at = k
        if (k % 30 == 0 || k == introTick) && snaps[k] == nil { snaps[k] = eng }
    }

    /// board.ts `Sim.to(frame)`.
    public mutating func to(_ frame: Int) {
        let frame = max(0, frame)
        if frame == at { return }
        if frame < at || frame - at > 40 {
            var best = -1
            for k in snaps.keys where k <= frame && k > best { best = k }
            if best >= 0, let s = snaps[best] {
                eng = s
                at = best
            } else {
                eng = MatrixWakeEngine(n: MatrixWakeGeo.N_DOTS, cols: MatrixWakeGeo.COLS, rows: MatrixWakeGeo.ROWS)
                eng.brightnessMode = .perFrame
                at = -1
            }
        }
        var k = at + 1
        while k <= frame {
            step(k)
            k += 1
        }
    }

    /// Leaves the engine at tick k0 + 1 with the state of tick k0 in prevX / prevY / prevB.
    public mutating func preparePair(_ k0: Int) {
        let k0 = max(0, k0)
        if at == k0 + 1 && prevTick == k0 { return }
        to(k0)
        // once per 30 Hz tick; plain indexed copies (no closures over inout self). Scoped so the extra
        // reference to the particle buffer is gone before step() mutates it (no copy-on-write copy).
        do {
            let src = eng.p
            for i in 0..<min(src.count, prevX.count, prevY.count, prevB.count) {
                let q = src[i]
                prevX[i] = q.x
                prevY[i] = q.y
                prevB[i] = q.b
            }
        }
        prevTick = k0
        step(k0 + 1)
    }
}

// MARK: - Colours

enum MatrixWakeInk {
    /// stage ink (#F4F4F2), the day card's ink (#1A1A1A), coral (#E85D4E)
    static let night = Color(.sRGB, red: 0xF4 / 255.0, green: 0xF4 / 255.0, blue: 0xF2 / 255.0, opacity: 1)
    static let day = Color(.sRGB, red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0, opacity: 1)
    static let coral = Color(.sRGB, red: 0xE8 / 255.0, green: 0x5D / 255.0, blue: 0x4E / 255.0, opacity: 1)
    static let white = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
    /// the seven brightness levels' alphas: 0.12 + 0.88 * ((k + 0.5) / 7)
    static let levelAlpha: [Double] = (0..<7).map { 0.12 + 0.88 * ((Double($0) + 0.5) / 7) }
}

// MARK: - Grid bitmaps (hero4/dots.ts gridBitmap, matrix.tsx cardGrid)

enum MatrixWakeGrid {
    struct RGB: Equatable { var r, g, b: Double }

    /// Unlit dots on a lattice, painted once: `cols x rows` cells of `pitch` units; the image covers
    /// exactly those cells (origin = the first cell's corner). Optionally the card's destination-out fades:
    /// left edge erased fully at x = 0 to none at `fadeLeft`, top and bottom 0.6 to none at 15% / 85%.
    static func make(cols: Int, rows: Int, pitch: Double, radius: Double, color: RGB, alpha: Double, pxScale: Double, fadeLeft: Double?, vignette: Bool) -> CGImage? {
        let bw = Double(cols) * pitch, bh = Double(rows) * pitch
        let wpx = Int((bw * pxScale).rounded(.up)), hpx = Int((bh * pxScale).rounded(.up))
        guard cols > 0, rows > 0, wpx > 0, hpx > 0, wpx <= 8192, hpx <= 8192 else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let g = CGContext(data: nil, width: wpx, height: hpx, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // canvas convention: origin top-left, y down, units = design units
        g.translateBy(x: 0, y: CGFloat(hpx))
        g.scaleBy(x: CGFloat(pxScale), y: -CGFloat(pxScale))
        g.setFillColor(CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: alpha))
        for i in 0..<cols {
            for j in 0..<rows {
                let cx = (Double(i) + 0.5) * pitch, cy = (Double(j) + 0.5) * pitch
                g.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            }
        }
        g.fillPath()
        let clear = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
        func black(_ a: Double) -> CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: a) }
        g.setBlendMode(.destinationOut)
        if let fadeLeft, let grad = CGGradient(colorsSpace: space, colors: [black(1), clear] as CFArray, locations: [0, 1]) {
            g.saveGState()
            g.clip(to: CGRect(x: 0, y: 0, width: fadeLeft, height: bh))
            g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: fadeLeft, y: 0), options: [])
            g.restoreGState()
        }
        if vignette, let grad = CGGradient(colorsSpace: space, colors: [black(0.6), clear, clear, black(0.6)] as CFArray, locations: [0, 0.15, 0.85, 1]) {
            g.saveGState()
            g.clip(to: CGRect(x: 0, y: 0, width: bw, height: bh))
            g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: bh), options: [])
            g.restoreGState()
        }
        return g.makeImage()
    }
}

// MARK: - The renderer

final class MatrixWakeStage: WakeStageRenderer {
    private var sim: MatrixWakeSim?
    /// The scene and the inputs it was built from. The page's facts, plan and concept are fixed for its
    /// life, so this is built once (the facts' clock formatting is not per-frame work).
    private var built: (facts: WakeFacts, plan: WakePlan, concept: WakeConcept, scene: MatrixWakeScene)?
    /// The last frame's dots. In light appearance the page draws the same `t` twice (the night pass and
    /// the day pass inside the card), so the second pass reuses them.
    private var dotCache: (key: DotKey, paths: DotPaths)?
    private var fullGrid: (key: GridKey, image: Image, rect: CGRect)?
    private var cardGrids: [Bool: (key: GridKey, image: Image)] = [:]

    private struct GridKey: Equatable {
        var w: Double
        var h: Double
        var px: Double
    }

    private struct DotKey: Equatable {
        var fE: Double
        var bx: Double
        var by: Double
        var mm: Double
        var r: Double
        var cull: CGRect
        var rm: Bool

        /// Same tick position and the same mapping to within 1/100 pt (the card slot reaches the night
        /// pass through a lerp, the day pass directly).
        func matches(_ o: DotKey) -> Bool {
            fE == o.fE && rm == o.rm && abs(bx - o.bx) < 0.01 && abs(by - o.by) < 0.01 && abs(mm - o.mm) < 1e-6
                && abs(r - o.r) < 1e-4 && abs(cull.minX - o.cull.minX) < 0.01 && abs(cull.minY - o.cull.minY) < 0.01
                && abs(cull.width - o.cull.width) < 0.01 && abs(cull.height - o.cull.height) < 0.01
        }
    }

    init() {}

    // MARK: inputs from the shared contract

    static func variant(_ c: WakeConcept) -> MatrixWakeVariant? {
        switch c {
        case .matrixA: return .a
        case .matrixB: return .b
        case .ridgeA, .ridgeB: return nil
        }
    }

    static func facts(_ f: WakeFacts) -> MatrixWakeFacts {
        let time = MatrixWakeFacts.ledClock(f.gymClock) ?? MatrixWakeFacts.ledClock(f.gymTime)
        var leave: String?
        if let lc = f.leaveClock, let c = MatrixWakeFacts.ledClock(lc) {
            leave = c
        } else if let d = f.leaveBy {
            leave = MatrixWakeFacts.ledClock(d)
        }
        let mission: MatrixWakeFacts.Mission
        switch f.missionKind {
        case .steps: mission = .steps
        case .bag: mission = .bag
        case .water: mission = .water
        case .shoe: mission = .shoe
        }
        return MatrixWakeFacts(time: time, leave: leave, mission: mission, steps: f.missionSteps, goal: f.weekGoal, done: f.weekDone, day: f.habitDay, streak: f.streakWeeks, isFirst: f.isFirst,
                                shoeArt: f.shoeArt == .laceUp ? .laceUp : .profile)
    }

    static func timeline(_ p: WakePlan) -> MatrixWakeTimeline {
        typealias TL = MatrixWakeTimeline
        let beats = p.beats.map { b -> TL.Beat in
            let id: MatrixWakeBeat
            switch b.id {
            case .greet: id = .greet
            case .commit: id = .commit
            case .leave: id = .leave
            case .mission: id = .mission
            case .day: id = .day
            case .week: id = .week
            }
            return TL.Beat(id: id, at: TL.frames(b.start), end: TL.frames(b.end), i: b.index)
        }
        return TL(beats: beats, condense: TL.frames(p.condenseAt), land: TL.frames(p.landAt), wipe0: TL.frames(p.wipe.lowerBound), wipe1: TL.frames(p.wipe.upperBound), intro: TL.frames(p.introEnd), rm: p.reduceMotion)
    }

    /// The scene for this frame's inputs, rebuilt only when they change.
    private func scene(for frame: WakeFrame) -> MatrixWakeScene? {
        if let b = built, b.concept == frame.concept, b.plan == frame.plan, b.facts == frame.facts { return b.scene }
        guard let variant = Self.variant(frame.concept) else { return nil }
        let scene = MatrixWakeScene(facts: Self.facts(frame.facts), timeline: Self.timeline(frame.plan), variant: variant)
        built = (frame.facts, frame.plan, frame.concept, scene)
        dotCache = nil
        return scene
    }

    // MARK: the stage mapping (shared by draw and anchor)

    /// The design rect of the stage at condense progress k, lerp(page, card slot, k), mapped onto
    /// `frame.stageRect` (uniform scale, top-aligned), then the camera.
    private struct Mapping {
        /// The web frame (continuous, 30 fps).
        let f: Double
        /// Condense progress, 0 to 1.
        let k: Double
        /// Native points per design point, before the camera.
        let sc: Double
        let cam: Double
        /// Where design (0, 0) lands after the camera, and native points per design point.
        let bx: Double
        let by: Double
        let m: Double

        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: bx + Double(r.minX) * m, y: by + Double(r.minY) * m, width: Double(r.width) * m, height: Double(r.height) * m)
        }

        /// A full-screen board cell position (cells, 7.5 design points each) on screen.
        func cell(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: bx + x * MatrixWakeGeo.PITCH * m, y: by + y * MatrixWakeGeo.PITCH * m)
        }
    }

    private static func mapping(_ scene: MatrixWakeScene, frame: WakeFrame, size: CGSize) -> Mapping? {
        let sr = frame.stageRect
        guard frame.t.isFinite, sr.width > 0.5, sr.height > 0.5, size.width > 0, size.height > 0 else { return nil }
        let G = MatrixWakeGeo.self
        let f = max(0, frame.t * G.FPS)
        let k = MXW.cl(frame.plan.condenseProgress(at: frame.t))
        let Dx = MXW.lerp(0, G.CARD_X, k), Dy = MXW.lerp(0, G.CARD_Y, k)
        let Dw = MXW.lerp(G.W, G.CARD_W, k), Dh = MXW.lerp(G.H, G.CARD_H, k)
        // Uniform scale, top-aligned and centred horizontally, exactly the page's words
        // (`WakeLayout.fit` at k = 0: scale and originX are the same numbers). Inside the card (k = 1)
        // it is the card's own fit, uncapped. In between, the cap eases from the page's scale to the
        // card's, so an iPad's 1.25 cap does not jump when the stage starts to condense.
        let sc0 = Double(WakeLayout.fit(size).scale)
        let natural = min(Double(sr.width) / Dw, Double(sr.height) / Dh)
        let sc = min(natural, MXW.lerp(sc0, max(natural, sc0), k))
        let ox = Double(sr.minX) + (Double(sr.width) - Dw * sc) / 2 - Dx * sc
        let oy = Double(sr.minY) - Dy * sc
        // the camera (matrix.tsx mxCam), scaling about 50% 58% of the page
        let cam = scene.cam(f)
        let camX = G.W * 0.5, camY = G.H * 0.58
        return Mapping(f: f, k: k, sc: sc, cam: cam, bx: ox + sc * camX * (1 - cam), by: oy + sc * camY * (1 - cam), m: sc * cam)
    }

    // MARK: draw

    /// Draws exactly the look `frame.dark` asks for. The page owns the clip to `frame.stageRect`, the
    /// stage colour, Reduce Motion's content fades and the light wipe between the two passes.
    func draw(_ ctx: inout GraphicsContext, size: CGSize, frame: WakeFrame) {
        guard size.width > 0, size.height > 0, let scene = self.scene(for: frame), let map = Self.mapping(scene, frame: frame, size: size) else { return }
        if sim?.scene != scene { sim = MatrixWakeSim(scene: scene) }
        let tl = scene.timeline
        let rm = tl.rm
        let G = MatrixWakeGeo.self

        // the engine's frame: the idle loops after the intro
        let f = map.f
        var fE = f
        if f >= tl.intro { fE = tl.intro + MatrixWakeJS.rem(f - tl.intro, G.IDLE_FRAMES) }
        let k0d = fE.rounded(.down)
        guard k0d < 10_000_000 else { return }
        let k0 = Int(k0d)
        let a = Float(fE - k0d)
        // idempotent per tick: the second pass of a frame (same t) neither steps nor copies
        sim?.preparePair(k0)
        guard let s = sim else { return }

        let k = map.k
        let sr = frame.stageRect
        let r = (2.65 + (4.6 * G.CARD_S - 2.65) * k) * map.sc * map.cam
        let key = DotKey(fE: fE, bx: map.bx, by: map.by, mm: map.m * G.PITCH, r: r, cull: sr, rm: rm)
        let paths: DotPaths
        if let c = dotCache, c.key.matches(key) {
            paths = c.paths
        } else {
            paths = buildDots(s, a: a, rm: rm, bx: map.bx, by: map.by, mm: key.mm, r: r, cull: sr)
            dotCache = (key, paths)
        }

        let scale = Double(ctx.environment.displayScale)
        if frame.dark {
            // night: the faint full-screen grid hands over to the card's grid as the stage condenses
            if k < 1, let fg = fullGridImage(size: size, scale: scale) {
                var g = ctx
                g.opacity *= 1 - k
                g.draw(fg.image, in: map.rect(fg.rect))
            }
            if k > 0, let cg = cardGridImage(dark: true, size: size, scale: scale) {
                var g = ctx
                g.opacity *= k
                g.draw(cg, in: map.rect(Self.cardGridRect))
            }
            fill(&ctx, paths, ink: MatrixWakeInk.night)
            let fl = scene.flash(f)
            if !rm && fl > 0.01 {
                ctx.fill(Path(sr), with: .color(MatrixWakeInk.white.opacity(min(0.22, fl))))
            }
        } else {
            // day: the card's look in light appearance (ink on Theme.surface)
            if k > 0, let cg = cardGridImage(dark: false, size: size, scale: scale) {
                var g = ctx
                g.opacity *= k
                g.draw(cg, in: map.rect(Self.cardGridRect))
            }
            fill(&ctx, paths, ink: MatrixWakeInk.day)
        }
    }

    // MARK: pieces

    private struct DotPaths {
        var levels: [Path]
        var coral: Path?
    }

    /// matrix.tsx / board.ts `drawDots`, between two engine ticks: brightness lerps, positions lerp
    /// (except for a dot that was dark at the first tick, which was re-placed, and under Reduce Motion,
    /// where nothing travels).
    private func buildDots(_ s: MatrixWakeSim, a: Float, rm: Bool, bx: Double, by: Double, mm: Double, r: Double, cull: CGRect) -> DotPaths {
        let LV = 7
        let lv0 = CGMutablePath(), lv1 = CGMutablePath(), lv2 = CGMutablePath(), lv3 = CGMutablePath()
        let lv4 = CGMutablePath(), lv5 = CGMutablePath(), lv6 = CGMutablePath()
        let lvs = [lv0, lv1, lv2, lv3, lv4, lv5, lv6]
        let cp = CGMutablePath()
        var anyC = false
        let ad = Double(a)
        let x0 = Double(cull.minX) - 2 * r, x1 = Double(cull.maxX) + 2 * r
        let y0 = Double(cull.minY) - 2 * r, y1 = Double(cull.maxY) + 2 * r
        s.eng.p.withUnsafeBufferPointer { P in
            s.prevX.withUnsafeBufferPointer { px in
                s.prevY.withUnsafeBufferPointer { py in
                    s.prevB.withUnsafeBufferPointer { pb in
                        let n = min(P.count, pb.count)
                        for i in 0..<n {
                            let q = P[i]
                            let b0 = Double(pb[i]), b1 = Double(q.b)
                            let b = b0 + (b1 - b0) * ad
                            if !(b >= 0.03) { continue } // also skips NaN
                            var x = Double(q.x), y = Double(q.y)
                            if !rm && b0 > 0.03 {
                                let xp = Double(px[i]), yp = Double(py[i])
                                x = xp + (x - xp) * ad
                                y = yp + (y - yp) * ad
                            }
                            let X = bx + x * mm, Y = by + y * mm
                            if X < x0 || X > x1 || Y < y0 || Y > y1 { continue }
                            let rr = r * (0.42 + 0.58 * min(1, b))
                            if q.c != 0 && b > 0.3 {
                                let rc = rr * 1.08
                                cp.addEllipse(in: CGRect(x: X - rc, y: Y - rc, width: rc * 2, height: rc * 2))
                                anyC = true
                                continue
                            }
                            let lv = min(LV - 1, Int(b * Double(LV)))
                            lvs[lv].addEllipse(in: CGRect(x: X - rr, y: Y - rr, width: rr * 2, height: rr * 2))
                        }
                    }
                }
            }
        }
        return DotPaths(levels: lvs.map { $0.isEmpty ? Path() : Path($0) }, coral: anyC ? Path(cp) : nil)
    }

    private func fill(_ g: inout GraphicsContext, _ d: DotPaths, ink: Color) {
        for (k, p) in d.levels.enumerated() where !p.isEmpty {
            g.fill(p, with: .color(ink.opacity(MatrixWakeInk.levelAlpha[k])))
        }
        if let c = d.coral { g.fill(c, with: .color(MatrixWakeInk.coral)) }
    }

    /// matrix.tsx: the card grid's rect in design points.
    private static let cardGridRect: CGRect = {
        let G = MatrixWakeGeo.self
        return CGRect(x: G.CARD_X + G.COX * G.CARD_S, y: G.CARD_Y + G.COY * G.CARD_S, width: Double(G.CCOLS) * G.CPITCH * G.CARD_S, height: Double(G.CROWS) * G.CPITCH * G.CARD_S)
    }()

    /// The full-screen board's faint grid (white 7.5%), covering the screen at k = 0, once per size.
    private func fullGridImage(size: CGSize, scale: Double) -> (image: Image, rect: CGRect)? {
        let G = MatrixWakeGeo.self
        // the k = 0 mapping (see `mapping`): the shared fit, top-aligned, centred horizontally
        let fit = WakeLayout.fit(size)
        let s0 = Double(fit.scale)
        let key = GridKey(w: Double(size.width), h: Double(size.height), px: scale)
        if let fg = fullGrid, fg.key == key { return (fg.image, fg.rect) }
        guard s0 > 0 else { return nil }
        let ox0 = Double(fit.originX)
        let i0 = Int((-ox0 / s0 / G.PITCH).rounded(.down))
        let i1 = Int(((Double(size.width) - ox0) / s0 / G.PITCH).rounded(.up))
        let j1 = Int((Double(size.height) / s0 / G.PITCH).rounded(.up))
        let cols = max(1, i1 - i0), rows = max(1, j1)
        guard let cg = MatrixWakeGrid.make(cols: cols, rows: rows, pitch: G.PITCH, radius: 1.05, color: .init(r: 1, g: 1, b: 1), alpha: 0.075, pxScale: s0 * scale, fadeLeft: nil, vignette: false) else { return nil }
        let img = Image(decorative: cg, scale: 1)
        let rect = CGRect(x: Double(i0) * G.PITCH, y: 0, width: Double(cols) * G.PITCH, height: Double(rows) * G.PITCH)
        fullGrid = (key, img, rect)
        return (img, rect)
    }

    /// The home card's grid (matrix.tsx cardGrid): fades out under the copy column and at the top and
    /// bottom. Night: stage ink at 16%; day: card ink at 10%. Rendered 1.25x oversampled, once per size.
    private func cardGridImage(dark: Bool, size: CGSize, scale: Double) -> Image? {
        let G = MatrixWakeGeo.self
        let px = scale * G.CARD_S * Double(WakeLayout.fit(size).scale) * 1.25
        let key = GridKey(w: Double(size.width), h: 0, px: px)
        if let c = cardGrids[dark], c.key == key { return c.image }
        let color: MatrixWakeGrid.RGB = dark ? .init(r: 0xF4 / 255.0, g: 0xF4 / 255.0, b: 0xF2 / 255.0) : .init(r: 0x1A / 255.0, g: 0x1A / 255.0, b: 0x1A / 255.0)
        guard let cg = MatrixWakeGrid.make(cols: G.CCOLS, rows: G.CROWS, pitch: G.CPITCH, radius: 1.7, color: color, alpha: dark ? 0.16 : 0.1, pxScale: px, fadeLeft: 190, vignette: true) else { return nil }
        let img = Image(decorative: cg, scale: 1)
        cardGrids[dark] = (key, img)
        return img
    }
}

// MARK: - Where the page's words go

extension MatrixWakeStage: WakeStageAnchoring {
    /// The board objects the page labels, through the same mapping and camera as the dots (mx2.ts
    /// NODES / TRACK, STEP_COUNTER, the run's count, WEEK_ROW). The board is top-aligned like the words;
    /// on screens shorter than 19.5:9 it is also shrunk to fit the height, so these points (not the
    /// prototype's fixed offsets) are what keeps the labels on their objects.
    func anchor(_ anchor: WakeAnchor, size: CGSize, frame: WakeFrame) -> CGPoint? {
        guard let scene = self.scene(for: frame), let map = Self.mapping(scene, frame: frame, size: size) else { return nil }
        typealias C = MatrixWakeChapters
        switch anchor {
        case .trackNode(let i):
            guard C.NODES.indices.contains(i) else { return nil }
            return map.cell(C.NODES[i] + 0.5, C.TRACK + 4.2)
        case .stepCounter:
            return map.cell(C.STEP_COUNTER.cx, C.STEP_COUNTER.y + 15.5)
        case .runCaption:
            return map.cell(C.CX, 76 + 15.5)
        case .weekRow:
            return map.cell(C.CX, C.WEEK_ROW + 9)
        case .ridgeLeave, .ridgeGym, .ridgeSummit:
            return nil
        }
    }
}

// MARK: - DEBUG parity self-test

#if DEBUG
/// Engine and chapter parity with the web prototype. Golden values come from
/// tools/matrix-wake-golden.ts (run under node against web/morning2). Wire into a test:
///
///     @Test func matrixWakeParity() { #expect(MatrixWakeParity.run() == []) }
///
/// Tolerances: hash, init positions exact; frame checksums 1e-9 relative (libm vs V8 last-bit
/// differences in sin/cos/pow); engine runs 1e-4 relative (an atan2 tie in a deal can swap two dots).
enum MatrixWakeParity {
    enum V: Sendable { case base, alt, shoe, steps7 }

    static func facts(_ v: V) -> MatrixWakeFacts {
        switch v {
        case .base: return MatrixWakeFacts(time: "7:05", leave: "6:50", mission: .steps, steps: 20, goal: 4, done: 2, day: 23, streak: 3)
        case .alt: return MatrixWakeFacts(time: "10:30", leave: nil, mission: .bag, steps: 0, goal: 6, done: 5, day: 80, streak: 0)
        case .shoe: return MatrixWakeFacts(time: "5:45", leave: "5:20", mission: .shoe, steps: 0, goal: 3, done: 0, day: 66, streak: 3)
        case .steps7: return MatrixWakeFacts(time: "7:05", leave: "6:50", mission: .steps, steps: 7, goal: 7, done: 6, day: 1, streak: 3)
        }
    }

    /// plan.ts buildPlan for these inputs (not snoozed), in frames.
    static func timeline(_ c: MatrixWakeVariant, rm: Bool) -> MatrixWakeTimeline {
        typealias B = MatrixWakeTimeline.Beat
        let third: MatrixWakeBeat = c == .a ? .leave : .day
        let fourth: MatrixWakeBeat = c == .a ? .mission : .week
        if rm {
            return MatrixWakeTimeline(beats: [B(id: .commit, at: 0, end: 36, i: 0), B(id: third, at: 36, end: 72, i: 1)], condense: 72, land: 75, wipe0: 75, wipe1: 81, intro: 93, rm: true)
        }
        let last: Double = c == .a ? 278 : 280
        return MatrixWakeTimeline(beats: [B(id: .greet, at: 6, end: 72, i: 0), B(id: .commit, at: 72, end: 144, i: 1), B(id: third, at: 144, end: 212, i: 2), B(id: fourth, at: 212, end: last, i: 3)],
                                  condense: last, land: last + 24, wipe0: last + 24, wipe1: last + 36, intro: last + 62, rm: false)
    }

    struct FrameRow: Sendable {
        let v: V, c: MatrixWakeVariant, rm: Bool, f: Int, key: String
        let fullN: Int, fullSum: Double, cardN: Int, cardSum: Double, flash: Double, cam: Double
    }
    struct SimRow: Sendable {
        let v: V, c: MatrixWakeVariant, rm: Bool, f: Int
        let bs: Double, xs: Double, ys: Double, cs: Int, key: String
    }
    static func F(_ v: V, _ c: MatrixWakeVariant, _ rm: Bool, _ f: Int, _ key: String, _ fn: Int, _ fs: Double, _ cn: Int, _ cs: Double, _ flash: Double, _ cam: Double) -> FrameRow {
        FrameRow(v: v, c: c, rm: rm, f: f, key: key, fullN: fn, fullSum: fs, cardN: cn, cardSum: cs, flash: flash, cam: cam)
    }
    static func S(_ v: V, _ c: MatrixWakeVariant, _ rm: Bool, _ f: Int, _ bs: Double, _ xs: Double, _ ys: Double, _ cs: Int, _ key: String) -> SimRow {
        SimRow(v: v, c: c, rm: rm, f: f, bs: bs, xs: xs, ys: ys, cs: cs, key: key)
    }

    // FRAME <variant> <concept> <rm> <frame> <key> <full n> <full sum> <card n> <card sum> <flash> <cam>
    static let frameRows: [FrameRow] = [
        F(.base, .a, false, 0, "greet", 674, 64202.877, 0, 0, 0, 1.05),
        F(.base, .a, false, 10, "greet", 726, 71507.083, 0, 0, 0, 1.04995547764),
        F(.base, .a, false, 30, "greet", 668, 62721.1581257, 0, 0, 0, 1.04038317055),
        F(.base, .a, false, 80, "commit", 556, 51188.4479259, 0, 0, 0, 1),
        F(.base, .a, false, 92, "commit", 556, 51326.022, 0, 0, 0.0299222650533, 1.03382829939),
        F(.base, .a, false, 120, "commit", 556, 51326.022, 0, 0, 0.0000125356972598, 1.00000174045),
        F(.base, .a, false, 160, "commit", 512, 48362.830963, 0, 0, 0, 1),
        F(.base, .a, false, 175, "commit", 563, 54720.8602484, 0, 0, 0, 1),
        F(.base, .a, false, 200, "commit", 565, 54998.6025468, 0, 0, 0, 1),
        F(.base, .a, false, 230, "mission", 320, 28920.777, 0, 0, 0, 1),
        F(.base, .a, false, 250, "mission", 460, 44548.527, 0, 0, 0, 1),
        F(.base, .a, false, 281, "card", 0, 0, 186, 9335.66652792, 0, 1),
        F(.base, .a, false, 302, "card", 0, 0, 186, 9334.87522905, 0, 1),
        F(.base, .a, false, 347, "card", 0, 0, 186, 9319.96797553, 0, 1),
        F(.base, .a, false, 540, "card", 0, 0, 186, 9318.176, 0, 1),
        F(.base, .a, true, 0, "commit", 556, 51326.022, 0, 0, 1.49285453631e-21, 1),
        F(.base, .a, true, 20, "commit", 556, 51326.022, 0, 0, 1.49285453631e-21, 1),
        F(.base, .a, true, 40, "commit", 565, 54998.299, 0, 0, 0, 1),
        F(.base, .a, true, 74, "card", 0, 0, 186, 9316.8261072, 0, 1),
        F(.base, .a, true, 98, "card", 0, 0, 186, 9320.00840728, 0, 1),
        F(.base, .b, false, 0, "greet", 674, 64202.877, 0, 0, 0, 1.05),
        F(.base, .b, false, 10, "greet", 726, 71507.083, 0, 0, 0, 1.04995547764),
        F(.base, .b, false, 30, "greet", 668, 62721.1581257, 0, 0, 0, 1.04038317055),
        F(.base, .b, false, 80, "commit", 556, 51188.4479259, 0, 0, 0, 1),
        F(.base, .b, false, 92, "commit", 556, 51326.022, 0, 0, 0.0299222650533, 1.03382829939),
        F(.base, .b, false, 120, "commit", 556, 51326.022, 0, 0, 0.0000125356972598, 1.00000174045),
        F(.base, .b, false, 160, "day", 890, 73817.108, 0, 0, 0, 1),
        F(.base, .b, false, 175, "day", 890, 74268.708, 0, 0, 0, 1),
        F(.base, .b, false, 200, "day", 890, 74573.9746667, 0, 0, 0.0378241566667, 1.02766472897),
        F(.base, .b, false, 230, "week", 178, 15019.511611, 0, 0, 0, 1.00479458959),
        F(.base, .b, false, 250, "week", 178, 15063.5160534, 0, 0, 0, 1.00000371352),
        F(.base, .b, false, 283, "card", 0, 0, 112, 5295.46340599, 0, 1),
        F(.base, .b, false, 304, "card", 0, 0, 112, 5275.10179023, 0, 1),
        F(.base, .b, false, 349, "card", 0, 0, 112, 5278.17997553, 0, 1),
        F(.base, .b, false, 542, "card", 0, 0, 112, 5276.388, 0, 1),
        F(.base, .b, true, 0, "commit", 556, 51326.022, 0, 0, 1.49285453631e-21, 1),
        F(.base, .b, true, 20, "commit", 556, 51326.022, 0, 0, 1.49285453631e-21, 1),
        F(.base, .b, true, 40, "day", 890, 74535.308, 0, 0, 4.15658914645e-17, 1),
        F(.base, .b, true, 74, "card", 0, 0, 112, 5274.92454955, 0, 1),
        F(.base, .b, true, 98, "card", 0, 0, 112, 5278.22040728, 0, 1),
        F(.alt, .a, false, 0, "greet", 674, 64202.877, 0, 0, 0, 1.05),
        F(.alt, .a, false, 10, "greet", 726, 71507.083, 0, 0, 0, 1.04995547764),
        F(.alt, .a, false, 30, "greet", 668, 62721.1581257, 0, 0, 0, 1.04038317055),
        F(.alt, .a, false, 80, "commit", 696, 64150.9159259, 0, 0, 0, 1),
        F(.alt, .a, false, 92, "commit", 696, 64396.49, 0, 0, 0.0299222650533, 1.03382829939),
        F(.alt, .a, false, 120, "commit", 696, 64396.49, 0, 0, 0.0000125356972598, 1.00000174045),
        F(.alt, .a, false, 160, "commit", 652, 61361.298963, 0, 0, 0, 1),
        F(.alt, .a, false, 175, "commit", 699, 67293.1642484, 0, 0, 0, 1),
        F(.alt, .a, false, 200, "commit", 700, 67459.5855468, 0, 0, 0, 1),
        F(.alt, .a, false, 230, "mission", 944, 88538.968, 0, 0, 0, 1),
        F(.alt, .a, false, 250, "mission", 944, 89815.768, 0, 0, 0, 1),
        F(.alt, .a, false, 281, "card", 0, 0, 184, 9223.08452792, 0, 1),
        F(.alt, .a, false, 302, "card", 0, 0, 184, 9222.29322905, 0, 1),
        F(.alt, .a, false, 347, "card", 0, 0, 184, 9207.38597553, 0, 1),
        F(.alt, .a, false, 540, "card", 0, 0, 184, 9205.594, 0, 1),
        F(.alt, .b, false, 0, "greet", 674, 64202.877, 0, 0, 0, 1.05),
        F(.alt, .b, false, 10, "greet", 726, 71507.083, 0, 0, 0, 1.04995547764),
        F(.alt, .b, false, 30, "greet", 668, 62721.1581257, 0, 0, 0, 1.04038317055),
        F(.alt, .b, false, 80, "commit", 696, 64150.9159259, 0, 0, 0, 1),
        F(.alt, .b, false, 92, "commit", 696, 64396.49, 0, 0, 0.0299222650533, 1.03382829939),
        F(.alt, .b, false, 120, "commit", 696, 64396.49, 0, 0, 0.0000125356972598, 1.00000174045),
        F(.alt, .b, false, 160, "day", 890, 75949.308, 0, 0, 0, 1),
        F(.alt, .b, false, 175, "day", 890, 76990.308, 0, 0, 0, 1),
        F(.alt, .b, false, 200, "day", 890, 77195.5746667, 0, 0, 0.0378241566667, 1.02766472897),
        F(.alt, .b, false, 230, "week", 144, 13044.1501216, 0, 0, 0, 1.00479458959),
        F(.alt, .b, false, 250, "week", 144, 13293.9060534, 0, 0, 0, 1.00000371352),
        F(.alt, .b, false, 283, "card", 0, 0, 151, 7781.10589818, 0, 1),
        F(.alt, .b, false, 304, "card", 0, 0, 151, 7753.34521512, 0, 1),
        F(.alt, .b, false, 349, "card", 0, 0, 151, 7735.669, 0, 1),
        F(.alt, .b, false, 542, "card", 0, 0, 151, 7735.669, 0, 1),
        F(.shoe, .a, false, 0, "greet", 674, 64202.877, 0, 0, 0, 1.05),
        F(.shoe, .a, false, 10, "greet", 726, 71507.083, 0, 0, 0, 1.04995547764),
        F(.shoe, .a, false, 30, "greet", 668, 62721.1581257, 0, 0, 0, 1.04038317055),
        F(.shoe, .a, false, 80, "commit", 556, 51206.4479259, 0, 0, 0, 1),
        F(.shoe, .a, false, 92, "commit", 556, 51344.022, 0, 0, 0.0299222650533, 1.03382829939),
        F(.shoe, .a, false, 120, "commit", 556, 51344.022, 0, 0, 0.0000125356972598, 1.00000174045),
        F(.shoe, .a, false, 160, "commit", 512, 48344.830963, 0, 0, 0, 1),
        F(.shoe, .a, false, 175, "commit", 563, 54702.8602484, 0, 0, 0, 1),
        F(.shoe, .a, false, 200, "commit", 565, 54980.6025468, 0, 0, 0, 1),
        F(.shoe, .a, false, 230, "mission", 444, 41526.77, 0, 0, 0, 1),
        F(.shoe, .a, false, 250, "mission", 444, 41929.97, 0, 0, 0, 1),
        F(.shoe, .a, false, 281, "card", 0, 0, 186, 9335.66652792, 0, 1),
        F(.shoe, .a, false, 302, "card", 0, 0, 186, 9334.87522905, 0, 1),
        F(.shoe, .a, false, 347, "card", 0, 0, 186, 9319.96797553, 0, 1),
        F(.shoe, .a, false, 540, "card", 0, 0, 186, 9318.176, 0, 1),
        F(.shoe, .b, false, 0, "greet", 674, 64202.877, 0, 0, 0, 1.05),
        F(.shoe, .b, false, 10, "greet", 726, 71507.083, 0, 0, 0, 1.04995547764),
        F(.shoe, .b, false, 30, "greet", 668, 62721.1581257, 0, 0, 0, 1.04038317055),
        F(.shoe, .b, false, 80, "commit", 556, 51206.4479259, 0, 0, 0, 1),
        F(.shoe, .b, false, 92, "commit", 556, 51344.022, 0, 0, 0.0299222650533, 1.03382829939),
        F(.shoe, .b, false, 120, "commit", 556, 51344.022, 0, 0, 0.0000125356972598, 1.00000174045),
        F(.shoe, .b, false, 160, "day", 890, 75818.508, 0, 0, 0, 1),
        F(.shoe, .b, false, 175, "day", 890, 76933.108, 0, 0, 0, 1),
        F(.shoe, .b, false, 200, "day", 890, 77184.1746667, 0, 0, 0.0378241566667, 1.02766472897),
        F(.shoe, .b, false, 230, "week", 60, 5190.00372545, 0, 0, 0, 1.00479458959),
        F(.shoe, .b, false, 250, "week", 60, 5191.12305343, 0, 0, 0, 1.00000371352),
        F(.shoe, .b, false, 283, "card", 0, 0, 94, 4406.90491028, 0, 1),
        F(.shoe, .b, false, 304, "card", 0, 0, 94, 4386.28555708, 0, 1),
        F(.shoe, .b, false, 349, "card", 0, 0, 94, 4388.04097553, 0, 1),
        F(.shoe, .b, false, 542, "card", 0, 0, 94, 4386.249, 0, 1),
        F(.steps7, .a, false, 0, "greet", 674, 64202.877, 0, 0, 0, 1.05),
        F(.steps7, .a, false, 10, "greet", 726, 71507.083, 0, 0, 0, 1.04995547764),
        F(.steps7, .a, false, 30, "greet", 668, 62721.1581257, 0, 0, 0, 1.04038317055),
        F(.steps7, .a, false, 80, "commit", 556, 51188.4479259, 0, 0, 0, 1),
        F(.steps7, .a, false, 92, "commit", 556, 51326.022, 0, 0, 0.0299222650533, 1.03382829939),
        F(.steps7, .a, false, 120, "commit", 556, 51326.022, 0, 0, 0.0000125356972598, 1.00000174045),
        F(.steps7, .a, false, 160, "commit", 512, 48362.830963, 0, 0, 0, 1),
        F(.steps7, .a, false, 175, "commit", 563, 54720.8602484, 0, 0, 0, 1),
        F(.steps7, .a, false, 200, "commit", 565, 54998.6025468, 0, 0, 0, 1),
        F(.steps7, .a, false, 230, "mission", 203, 19169.029, 0, 0, 0, 1),
        F(.steps7, .a, false, 250, "mission", 203, 19337.629, 0, 0, 0, 1),
        F(.steps7, .a, false, 281, "card", 0, 0, 186, 9335.66652792, 0, 1),
        F(.steps7, .a, false, 302, "card", 0, 0, 186, 9334.87522905, 0, 1),
        F(.steps7, .a, false, 347, "card", 0, 0, 186, 9319.96797553, 0, 1),
        F(.steps7, .a, false, 540, "card", 0, 0, 186, 9318.176, 0, 1),
    ]
    // SIM <variant> <concept> <rm> <frame> <sum b> <sum x*(i%7+1)> <sum y*(i%5+1)> <sum c*(i%11)> <key>
    static let simRows: [SimRow] = [
        S(.base, .a, false, 1, 11.9339997768, 154833.203099, 312957.696532, 0, "greet"),
        S(.base, .a, false, 45, 369.255533444, 156242.361166, 343550.108026, 0, "greet"),
        S(.base, .a, false, 100, 329.100622153, 158357.354467, 330835.939451, 26, "commit"),
        S(.base, .a, false, 150, 253.133806244, 156730.4659, 331489.386427, 17, "commit"),
        S(.base, .a, false, 220, 46.1336109447, 155958.293072, 335105.223539, 17, "mission"),
        S(.base, .a, false, 290, 139.930547184, 177339.56994, 304782.606151, 0, "card"),
        S(.base, .a, false, 370, 133.995894551, 177085.040041, 305288.233776, 2, "card"),
        S(.base, .a, true, 0, 0.10000000149, 155653.528044, 255756.432301, 0, "commit"),
        S(.base, .a, true, 40, 318.589999706, 156820.265243, 290333.23854, 20, "commit"),
        S(.base, .a, true, 82, 134.175667286, 167265.157434, 264896.342942, 30, "card"),
        S(.base, .b, false, 1, 11.9339997768, 154833.203099, 312957.696532, 0, "greet"),
        S(.base, .b, false, 45, 369.255533444, 156242.361166, 343550.108026, 0, "greet"),
        S(.base, .b, false, 100, 329.100622153, 158357.354467, 330835.939451, 26, "commit"),
        S(.base, .b, false, 150, 61.9464338154, 143879.97855, 318715.965391, 26, "day"),
        S(.base, .b, false, 220, 43.4085076586, 158449.866872, 289686.513113, 38, "week"),
        S(.base, .b, false, 292, 64.1738877021, 164372.455807, 276205.800892, 29, "card"),
        S(.base, .b, false, 372, 61.4598932415, 164190.577492, 276471.40142, 29, "card"),
        S(.base, .b, true, 0, 0.10000000149, 155653.528044, 255756.432301, 0, "commit"),
        S(.base, .b, true, 40, 204.63999936, 142733.071704, 282383.866892, 60, "day"),
        S(.base, .b, true, 82, 61.6396669447, 159656.587924, 262091.854558, 37, "card"),
        S(.alt, .a, false, 1, 11.9339997768, 154833.203099, 312957.696532, 0, "greet"),
        S(.alt, .a, false, 45, 369.255533444, 156242.361166, 343550.108026, 0, "greet"),
        S(.alt, .a, false, 100, 400.661256179, 158387.44197, 324189.473707, 23, "commit"),
        S(.alt, .a, false, 150, 322.53222011, 157442.892105, 324104.520574, 27, "commit"),
        S(.alt, .a, false, 220, 104.322020603, 153715.774913, 319308.451109, 0, "mission"),
        S(.alt, .a, false, 290, 139.882256368, 169157.137278, 280685.009762, 15, "card"),
        S(.alt, .a, false, 370, 133.195895314, 168901.056773, 281157.469482, 17, "card"),
        S(.alt, .b, false, 1, 11.9339997768, 154833.203099, 312957.696532, 0, "greet"),
        S(.alt, .b, false, 45, 369.255533444, 156242.361166, 343550.108026, 0, "greet"),
        S(.alt, .b, false, 100, 400.661256179, 158387.44197, 324189.473707, 23, "commit"),
        S(.alt, .b, false, 150, 72.0189201778, 142892.456728, 312689.700506, 0, "day"),
        S(.alt, .b, false, 220, 40.1438837172, 161373.351311, 289954.390859, 16, "week"),
        S(.alt, .b, false, 292, 133.081681192, 167405.048514, 270550.492952, 0, "card"),
        S(.alt, .b, false, 372, 125.380003572, 167218.177019, 270912.048651, 0, "card"),
        S(.shoe, .a, false, 1, 11.9339997768, 154833.203099, 312957.696532, 0, "greet"),
        S(.shoe, .a, false, 45, 369.255533444, 156242.361166, 343550.108026, 0, "greet"),
        S(.shoe, .a, false, 100, 332.698289393, 158357.354467, 330835.939451, 26, "commit"),
        S(.shoe, .a, false, 150, 254.189865485, 156730.4659, 331489.386427, 17, "commit"),
        S(.shoe, .a, false, 220, 50.9016028687, 154889.78655, 336965.986219, 0, "mission"),
        S(.shoe, .a, false, 290, 140.258911794, 167072.66117, 306710.739662, 0, "card"),
        S(.shoe, .a, false, 370, 133.995895267, 166821.836894, 307208.01021, 5, "card"),
        S(.shoe, .b, false, 1, 11.9339997768, 154833.203099, 312957.696532, 0, "greet"),
        S(.shoe, .b, false, 45, 369.255533444, 156242.361166, 343550.108026, 0, "greet"),
        S(.shoe, .b, false, 100, 332.698289393, 158357.354467, 330835.939451, 26, "commit"),
        S(.shoe, .b, false, 150, 63.7112733957, 145310.345875, 318605.543299, 26, "day"),
        S(.shoe, .b, false, 220, 16.1735100429, 160233.326615, 288099.700643, 51, "week"),
        S(.shoe, .b, false, 292, 74.0139216455, 165745.132462, 276691.478016, 37, "card"),
        S(.shoe, .b, false, 372, 71.5598920584, 165610.438039, 276905.551121, 37, "card"),
        S(.steps7, .a, false, 1, 11.9339997768, 154833.203099, 312957.696532, 0, "greet"),
        S(.steps7, .a, false, 45, 369.255533444, 156242.361166, 343550.108026, 0, "greet"),
        S(.steps7, .a, false, 100, 329.100622153, 158357.354467, 330835.939451, 26, "commit"),
        S(.steps7, .a, false, 150, 253.133806244, 156730.4659, 331489.386427, 17, "commit"),
        S(.steps7, .a, false, 220, 35.2130562452, 156178.94322, 333869.907152, 17, "mission"),
        S(.steps7, .a, false, 290, 139.44287543, 168827.050115, 310367.324379, 17, "card"),
        S(.steps7, .a, false, 370, 133.995894313, 168663.526642, 310789.444479, 22, "card"),
        S(.steps7, .b, false, 1, 11.9339997768, 154833.203099, 312957.696532, 0, "greet"),
        S(.steps7, .b, false, 45, 369.255533444, 156242.361166, 343550.108026, 0, "greet"),
        S(.steps7, .b, false, 100, 329.100622153, 158357.354467, 330835.939451, 26, "commit"),
        S(.steps7, .b, false, 150, 61.9568181117, 144585.446627, 317815.113565, 26, "day"),
        S(.steps7, .b, false, 220, 39.9620585305, 163583.723467, 301431.846288, 58, "week"),
        S(.steps7, .b, false, 292, 84.7559658763, 169580.668295, 283525.646562, 46, "card"),
        S(.steps7, .b, false, 372, 81.61989443, 169401.021168, 283875.861585, 46, "card"),
    ]

    static func checksum(_ o: ContiguousArray<MatrixWakeTarget>) -> Double {
        var a = 0.0
        for q in o { a = a + q.x * 1.3 + q.y * 0.7 + q.b * 5 + (q.c != 0 ? 11 : 0) + Double(q.id % 9973) * 0.001 }
        return a
    }

    static func close(_ a: Double, _ b: Double, _ rel: Double) -> Bool { abs(a - b) <= rel * max(1, abs(b)) }

    /// Returns the failures (empty when the port matches the web).
    static func run() -> [String] {
        var fails: [String] = []
        // hash (mdots.ts), exact to 12 digits
        let hashIn: [(Int, Int)] = [(0, 1), (1, 1), (5, 2), (719, 8), (1499, 10), (-3, 7)]
        let hashOut: [Double] = [0.768274554284, 0.663851173595, 0.116751558613, 0.808725735871, 0.762215872062, 0.0310087276157]
        for (n, (i, k)) in hashIn.enumerated() where !close(MatrixWakeHash.hash(i, k), hashOut[n], 1e-11) {
            fails.append("hash(\(i),\(k)) = \(MatrixWakeHash.hash(i, k)), web \(hashOut[n])")
        }
        // the engine's start positions (Float32, exact)
        let e0 = MatrixWakeEngine(n: 1500, cols: 52, rows: 113)
        let initWeb: [(Int, Float, Float)] = [(0, 39.95027542114258, 60.628326416015625), (1, 34.520259857177734, 99.78868103027344), (1499, 47.42951583862305, 4.61575984954834)]
        for (i, x, y) in initWeb where e0.p[i].x != x || e0.p[i].y != y {
            fails.append("init \(i): \(e0.p[i].x),\(e0.p[i].y) web \(x),\(y)")
        }
        // cardCell
        let cc: [(Double, Double, Double, Double)] = [(0, 0, 25.9174, 15.9222), (37, 34, 47.7474, 35.9822), (12.25, 3.5, 33.1449, 17.9872)]
        for (i, j, x, y) in cc {
            let p = MatrixWakeGeo.cardCell(i, j)
            if !close(p.x, x, 1e-9) || !close(p.y, y, 1e-9) { fails.append("cardCell(\(i),\(j)) = \(p), web \(x),\(y)") }
        }
        // whole frames
        var (full, card) = MatrixWakeScene.makeBoards()
        for row in frameRows {
            let scene = MatrixWakeScene(facts: facts(row.v), timeline: timeline(row.c, rm: row.rm), variant: row.c)
            let out = scene.frame(Double(row.f), full: &full, card: &card)
            let fo = full.out(), co = out.hasCard ? card.out() : []
            let tag = "frame \(row.v) \(row.c) rm=\(row.rm) f=\(row.f)"
            if out.key != row.key { fails.append("\(tag): key \(out.key), web \(row.key)") }
            if fo.count != row.fullN || co.count != row.cardN { fails.append("\(tag): counts \(fo.count)/\(co.count), web \(row.fullN)/\(row.cardN)") }
            if !close(checksum(fo), row.fullSum, 1e-9) { fails.append("\(tag): full sum \(checksum(fo)), web \(row.fullSum)") }
            if !close(checksum(co), row.cardSum, 1e-9) { fails.append("\(tag): card sum \(checksum(co)), web \(row.cardSum)") }
            if !close(out.flash, row.flash, 1e-9) { fails.append("\(tag): flash \(out.flash), web \(row.flash)") }
            if !close(scene.cam(Double(row.f)), row.cam, 1e-9) { fails.append("\(tag): cam \(scene.cam(Double(row.f))), web \(row.cam)") }
        }
        // engine runs (board.ts Sim.to, probes in order on one sim per case)
        var sims: [String: MatrixWakeSim] = [:]
        for row in simRows {
            let id = "\(row.v)-\(row.c)-\(row.rm)"
            var sim = sims[id] ?? MatrixWakeSim(scene: MatrixWakeScene(facts: facts(row.v), timeline: timeline(row.c, rm: row.rm), variant: row.c))
            sim.to(row.f)
            var bs = 0.0, xs = 0.0, ys = 0.0, cs = 0
            for (i, q) in sim.eng.p.enumerated() {
                bs += Double(q.b)
                xs += Double(q.x) * Double(i % 7 + 1)
                ys += Double(q.y) * Double(i % 5 + 1)
                cs += Int(q.c) * (i % 11)
            }
            let tag = "sim \(id) f=\(row.f)"
            if sim.eng.key != row.key { fails.append("\(tag): key \(sim.eng.key), web \(row.key)") }
            if !close(bs, row.bs, 1e-4) || !close(xs, row.xs, 1e-4) || !close(ys, row.ys, 1e-4) {
                fails.append("\(tag): sums \(bs) \(xs) \(ys), web \(row.bs) \(row.xs) \(row.ys)")
            }
            if cs != row.cs { fails.append("\(tag): coral \(cs), web \(row.cs)") }
            sims[id] = sim
        }
        // determinism: any path to a frame gives the same state (continuous, scrubbed, restored)
        let scene = MatrixWakeScene(facts: facts(.base), timeline: timeline(.b, rm: false), variant: .b)
        var s1 = MatrixWakeSim(scene: scene)
        for f in 0...230 { s1.to(f) }
        var s2 = MatrixWakeSim(scene: scene)
        s2.to(120); s2.to(15); s2.to(300); s2.to(229); s2.preparePair(229)
        if s1.eng.p != s2.eng.p || s1.eng.key != s2.eng.key { fails.append("determinism: scrubbed state differs from continuous at f=230") }
        return fails
    }
}
#endif
