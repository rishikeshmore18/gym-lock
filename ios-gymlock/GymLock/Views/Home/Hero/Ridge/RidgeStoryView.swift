//
//  RidgeStoryView.swift
//  GymLock · Ridge done flow (native port)
//
//  Native port of web/hero12/story12.tsx: paper at the top for the words and numbers, the day's
//  painted world below. Driven by the same MatrixStoryModel as the Matrix flow (style .ridge), so
//  taps, the seal, haptics (CFG_R), the count and the collapse share one state machine.
//
//  The world:
//    - `RidgeStoryRuntime.scene` is story12.tsx `sceneAt`, fed with real values: the user's day of
//      the habit, total sessions and this week's sessions (never the prototype's samples).
//    - Painted by RPainter2.render3 into one bitmap per frame. The bitmap is capped (pxScale <= 0.5,
//      about 330k pixels) so a portrait repaint stays inside a frame on CPU CoreGraphics; the world is
//      soft watercolour, so the upscale reads as paper, not blur.
//    - Day 1 (the rock): chips on every hit and on the break (wash.ts drawChips).
//  Motion: every screen opens on a pull-back; each tap on the finish punches in and rings out; the
//  seal flashes. Reduce Motion drops the camera, the shake, the ring and the flash.
//
//  Copy: everything comes from MatrixStoryCopy (real figures only). Heart rate, energy, the session
//  chart and "+6:10" from the prototype are not ported; a figure GymLock did not measure is absent.
//

import SwiftUI
import UIKit

// MARK: - The worlds' finish copy (days12.ts WORLDS[].climax)

struct RidgeClimaxCopy {
    let eyebrow: String
    let lastEyebrow: String
    let title: String
    let sub: (Int) -> String
    let idle: String
    let mid: String
    let end: String

    static let byDay: [RidgeClimaxCopy] = [
        RidgeClimaxCopy(eyebrow: "TODAY'S SUN", lastEyebrow: "THE WEEK'S LAST SUNRISE", title: "Raise it.", sub: { "Tap **\($0) times** to lift the sun clear of the clouds." }, idle: "Tap to raise the sun", mid: "Higher", end: "The sun is up, and so is the count."),
        RidgeClimaxCopy(eyebrow: "TODAY'S ROCK", lastEyebrow: "THE WEEK'S LAST ROCK", title: "Break it.", sub: { "Tap the rock **\($0) times** to put today on the count." }, idle: "Tap the rock to break it", mid: "Keep going", end: "Another one in pieces. Every session breaks one."),
        RidgeClimaxCopy(eyebrow: "THE LAKE", lastEyebrow: "THE WEEK'S LAST THROW", title: "Skip it.", sub: { "Every tap is a skip. **\($0)** gets it to the far shore." }, idle: "Tap to skip the stone", mid: "Again", end: "All the way across. Today made it to the other side."),
        RidgeClimaxCopy(eyebrow: "THE PINE", lastEyebrow: "THE WEEK'S LAST GROWTH", title: "Grow it.", sub: { "Tap **\($0) times.** Today goes into the pine." }, idle: "Tap to grow the pine", mid: "Taller", end: "Taller than this morning. That's what a session does."),
        RidgeClimaxCopy(eyebrow: "THE SUMMIT", lastEyebrow: "THE WEEK'S LAST CLIMB", title: "Light it.", sub: { "Climb with **\($0) taps,** then the beacon at the top is yours." }, idle: "Tap to climb", mid: "Keep climbing", end: "Lit from the top. Everyone below can see it."),
        RidgeClimaxCopy(eyebrow: "THE SHORE", lastEyebrow: "THE WEEK'S LAST LIGHTS", title: "Let them go.", sub: { "One lantern for every tap. **\($0)** to send up." }, idle: "Tap to light a lantern", mid: "Another", end: "Up and away. Today is done and drifting."),
        RidgeClimaxCopy(eyebrow: "TONIGHT'S SKY", lastEyebrow: "THE WEEK, IN STARS", title: "Connect it.", sub: { "**\($0) stars,** one for every session. Light them all." }, idle: "Tap to light a star", mid: "Next star", end: "One shape for the whole week. It's written in the sky."),
    ]

    /// screens12.ts TALLY: what each world counts.
    static let tally = ["SUNRISES", "ROCKS BROKEN", "CROSSINGS", "RINGS GROWN", "SUMMITS LIT", "LANTERNS SENT", "STARS LIT"]

    static func of(_ day: Int) -> RidgeClimaxCopy { byDay[max(0, min(6, day))] }
}

// MARK: - Runtime (painter + bitmap; not observable)

@MainActor
final class RidgeStoryRuntime {
    /// The paper-top fade's design-space focus for the collapse (the world's middle band).
    static let collapseFocus: Double = 1250

    private let painter = RPainter2()
    private var bitmap: (w: Int, h: Int, cg: CGContext)?
    private var last: CGImage?

    /// Capped bitmap scale for a composition `comp` shown `pointWidth` wide.
    static func pxScale(comp: CGSize, pointWidth: Double, displayScale: Double) -> Double {
        let W = Double(comp.width), H = Double(comp.height)
        guard W > 0, H > 0 else { return 0.3 }
        let budget = (330_000 / (W * H)).squareRoot()
        return max(0.2, min(0.5, budget, pointWidth * displayScale / W))
    }

    private static func ease(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }
    private static func q(_ x: Double, _ k: Double) -> Double { JSMath.round(x * k) / k }

    /// story12.tsx `hv`: how far the finish has got, the newest tap easing in.
    private static func hv(_ m: MatrixStoryModel, _ t: Double) -> Double {
        if m.sealT != nil { return 1 }
        guard let tapAt = m.tapTimes.last else { return 0 }
        return (Double(m.tapTimes.count - 1) + ease((t - tapAt) / 0.35)) / Double(max(1, m.N))
    }

    /// story12.tsx `sceneAt`, with the user's real day, sessions and week.
    static func scene(_ m: MatrixStoryModel, t: Double) -> RScene {
        let day = max(0, min(6, m.day))
        let lt = m.lt(t)
        let D = m.dayData
        let g = RW.grow(Double(D.day))
        let weekDone = Double(max(1, m.weekDone))
        let base = RScene.make { o in
            o.kind = "ridge"; o.seed = RW.WSEED[day]; o.tree = g; o.cracks = 0; o.broken = 0
            o.rubble = min(7, (Double(D.sessions) / 3).rounded(.down)); o.sun = 0.5; o.night = 0; o.mist = 0.8
            o.rain = 0; o.peak = 1; o.birds = 0
        }
        func S(_ f: (RScene) -> Void) -> RScene { RScene.make([base], f) }
        let last = m.pos == .last
        // this week's count, today's arriving
        let done = weekDone - 1 + ease((lt - 0.4) / 0.7)
        let start = t - lt

        switch m.screen {
        case .verified:
            switch day {
            case 0: return S { $0.kind = "sunrise"; $0.sun = -0.15 + 0.25 * ease(lt / 2); $0.birds = 3 }
            case 1: return S { $0.kind = "ridge"; $0.cracks = 4; $0.sun = 0.5; $0.mist = 0.7 }
            case 2: return S { $0.kind = "lake"; $0.sun = 0.5; $0.mist = 0.8; $0.ripples = 1 }
            case 3: return S { $0.kind = "ridge"; $0.noRock = true; $0.tree = max(0.3, g - 0.2); $0.sun = 0.45; $0.mist = 0.8 }
            case 4: return S { $0.kind = "path"; $0.trail = 0.6 + 0.21 * ease((lt - 0.2) / 1.6); $0.sun = 0.5; $0.birds = 2 }
            case 5: return S { $0.kind = "sunset"; $0.sun = 0.35; $0.birds = 2 }
            default: return S { $0.kind = "night"; $0.night = 1; $0.charge = 0.98; $0.stars = 0; $0.mist = 0.5 }
            }
        case .today:
            switch day {
            case 0: return S { $0.kind = "sunrise"; $0.sun = 0.4; $0.mist = 1.1; $0.birds = 2 }
            case 1: return S { $0.kind = "cairn"; $0.stones = weekDone - 1; $0.sun = 0.5 }
            case 2: return S { $0.kind = "lake"; $0.drip = true; $0.sun = 0.45; $0.mist = 0.9 }
            case 3: return S { $0.kind = "fog"; $0.mist = 1; $0.peak = 0.5 }
            case 4: return S { $0.kind = "path"; $0.trail = 0.5; $0.sun = 0.5 }
            case 5: return S { $0.kind = "beach"; $0.steps = 0.6; $0.sun = 0.4 }
            default: return S { $0.kind = "night"; $0.night = 1; $0.charge = 0.6; $0.stars = 3; $0.mist = 0.5 }
            }
        case .week:
            switch day {
            case 0: return S { $0.kind = "sunrise"; $0.sun = -0.25 + 0.17 * done; $0.birds = JSMath.round(done) }
            case 1: return S { $0.kind = "cairn"; $0.stones = done; $0.sun = last ? 0.6 : 0.5; $0.birds = last ? 5 : 0 }
            case 2: return S { $0.kind = "lake"; $0.sun = 0.5; $0.mist = 0.8; $0.ripples = JSMath.round(done) }
            case 3: return S { $0.kind = "ridge"; $0.noRock = true; $0.night = 0.5; $0.sun = 0.1; $0.mist = 0.8; $0.fireflies = JSMath.round(done * 2) }
            case 4: return S { $0.kind = "path"; $0.trail = 0.81 * min(1, done / 5); $0.sun = 0.5 }
            case 5:
                let n = Int(weekDone)
                return S { $0.kind = "sunset"; $0.sun = 0.15; $0.night = 0.25; $0.lanterns = (0..<n).map { start + 0.4 + Double($0) * 0.25 } }
            default: return S { $0.kind = "night"; $0.night = 1; $0.charge = 0.98; $0.stars = min(7, done); $0.mist = 0.5 }
            }
        case .month:
            if m.monthPos == .first {
                switch day {
                case 0: return S { $0.kind = "sunrise"; $0.sun = 0.05; $0.birds = 2 }
                case 1: return S { $0.kind = "cairn"; $0.stones = 0; $0.sun = 0.35; $0.mist = 0.9 }
                case 2: return S { $0.kind = "lake"; $0.sun = 0.25; $0.mist = 1.1 }
                case 3: return S { $0.kind = "ridge"; $0.noRock = true; $0.sun = 0.3; $0.mist = 1.2 }
                case 4: return S { $0.kind = "path"; $0.trail = 0.02; $0.sun = 0.35 }
                case 5: return S { $0.kind = "beach"; $0.sun = 0.3; $0.birds = 2 }
                default: return S { $0.kind = "night"; $0.night = 1; $0.charge = 0.1; $0.stars = 0; $0.shoot = start + 1.2; $0.mist = 0.5 }
                }
            }
            switch day {
            case 0: return S { $0.kind = "sunrise"; $0.sun = 0.6; $0.birds = 6 }
            case 1: return S { $0.kind = "cairn"; $0.stones = 5; $0.sun = 0.55 }
            case 2: return S { $0.kind = "lake"; $0.sun = 0.55; $0.mist = 0.7; $0.ripples = 5 }
            case 3: return S { $0.kind = "ridge"; $0.noRock = true; $0.tree = min(1, g + 0.1); $0.sun = 0.5 }
            case 4: return S { $0.kind = "path"; $0.trail = 1; $0.beacon = 0.5; $0.sun = 0.45 }
            case 5: return S { $0.kind = "sunset"; $0.sun = 0.08; $0.night = 0.25 }
            default: return S { $0.kind = "night"; $0.night = 1; $0.charge = 0.98; $0.stars = 7; $0.starLines = 1; $0.mist = 0.5 }
            }
        case .far:
            let p = ease((lt - 0.2) / 1.6)
            let k = min(1, Double(D.day) / 66)
            switch day {
            case 0: return S { $0.kind = "sunrise"; $0.sun = -0.3 + 0.9 * k * p; $0.birds = 3 }
            case 1: return S { $0.kind = "ridge"; $0.sun = 0.55; $0.mist = 0.7; $0.rubble = JSMath.round(7 * p); $0.cracks = 0 }
            case 2: return S { $0.kind = "lake"; $0.boatX = 0.12 + 0.76 * k * p; $0.sun = 0.5; $0.mist = 0.7 }
            case 3: return S { $0.kind = "ridge"; $0.noRock = true; $0.tree = q(0.12 + (g - 0.12) * p, 20); $0.sun = 0.5; $0.mist = 0.7 }
            case 4:
                let tr = 0.81 * ease((lt - 0.2) / 1.6) + (lt > 1.8 ? 0.19 * k * ease((lt - 1.8) / 0.8) : 0)
                return S { $0.kind = "path"; $0.trail = tr; $0.sun = 0.5; $0.birds = 3 }
            case 5: return S { $0.kind = "beach"; $0.steps = k * p; $0.sun = 0.4 }
            default: return S { $0.kind = "night"; $0.night = 1; $0.charge = 0.98; $0.stars = 7 * k * p; $0.mist = 0.5 }
            }
        case .climax:
            let h = hv(m, t)
            let s = m.sealT
            let since = s.map { t - $0 } ?? -1
            switch day {
            case 0:
                return S { o in
                    o.kind = "sunrise"; o.sun = s != nil ? 0.45 + 0.25 * ease(since / 0.8) : -0.35 + 0.8 * h
                    o.birds = s != nil ? 5 : 2; o.flash = s; o.burst = s; o.burstAt = "sun"
                }
            case 1:
                return S { o in
                    o.kind = "ridge"; o.cracks = s != nil ? 5 : h * 5; o.broken = s != nil ? ease(min(1, since / 0.55)) : 0
                    o.sun = last ? 0.6 : 0.5; o.mist = 0.8
                }
            case 2:
                return S { o in
                    o.kind = "lake"; o.sun = 0.5; o.mist = 0.8; o.skipN = Double(m.N); o.skips = m.tapTimes
                    o.skipDone = s.map { $0 + 0.35 }
                }
            case 3:
                let g0 = max(0.3, g - 0.2), g1 = min(1, g + 0.08)
                return S { o in
                    o.kind = "ridge"; o.noRock = true; o.tree = q(g0 + (g1 - g0) * h, 50); o.sun = 0.5; o.mist = 0.75
                    o.burst = s; o.burstAt = "tree"; o.flash = s
                }
            case 4:
                return S { o in
                    o.kind = "path"; o.trail = 0.81 + 0.19 * h; o.sun = 0.45; o.beacon = s != nil ? ease(since / 1) : 0
                    o.flash = s.map { $0 + 0.1 }
                }
            case 5:
                return S { o in
                    o.kind = "sunset"; o.sun = 0.12; o.night = 0.25
                    o.lanterns = s.map { m.tapTimes + [$0 + 0.25, $0 + 0.5] } ?? m.tapTimes
                    o.flash = s
                }
            default:
                let lit: Double = {
                    if s != nil { return 7 }
                    guard let tapAt = m.tapTimes.last else { return 0 }
                    return min(7, Double(m.tapTimes.count - 1) + ease((t - tapAt) / 0.3))
                }()
                return S { o in
                    o.kind = "night"; o.night = 1; o.charge = 0.98; o.stars = lit
                    o.starLines = s != nil ? ease(since / 1) : 0; o.shoot = s.map { $0 + 0.7 }; o.mist = 0.5
                }
            }
        }
    }

    /// story12.tsx useLayoutEffect: one frame of the world (plus the rock's chips on day 1).
    func frame(_ m: MatrixStoryModel, t: Double, comp: CGSize, pxScale: Double, theme: String, reduceMotion: Bool) -> CGImage? {
        let cw = Int(JSMath.round(Double(comp.width) * pxScale)), ch = Int(JSMath.round(Double(comp.height) * pxScale))
        guard cw > 0, ch > 0 else { return last }
        if bitmap?.w != cw || bitmap?.h != ch {
            guard let cg = C2D.makeBitmap(cw, ch) else { return last }
            bitmap = (cw, ch, cg)
        }
        guard let bm = bitmap else { return last }
        let ctx = C2D(bm.cg, width: cw, height: ch)
        bm.cg.saveGState()
        defer { bm.cg.restoreGState() }
        let S = Self.scene(m, t: t)
        if reduceMotion { S.flash = nil }
        let w = Double(cw), h = Double(ch)
        painter.render3(ctx, w, h, S, theme, t)
        if m.screen == .climax && m.day == 1 {
            let B = RW.boulderGeom(w, h, S.seed)
            let taps = Double(m.tapTimes.count)
            if let sealT = m.sealT {
                RW.drawChips(ctx, w, h, S.seed, (B.cx, B.by - B.bh * 0.6), t - sealT, theme)
                RW.drawChips(ctx, w, h, S.seed + 4, (B.cx - B.bw * 0.2, B.by - B.bh * 0.35), t - sealT - 0.06, theme)
                RW.drawChips(ctx, w, h, S.seed + 9, (B.cx + B.bw * 0.22, B.by - B.bh * 0.3), t - sealT - 0.1, theme)
            } else if let tapAt = m.tapTimes.last {
                let side: Double = m.tapTimes.count % 2 == 1 ? -1 : 1
                RW.drawChips(ctx, w, h, S.seed + taps * 3, (B.cx + side * B.bw * 0.15, B.by - B.bh * 0.55), (t - tapAt) * 1.6, theme)
            }
        }
        ctx.setTransform(1, 0, 0, 1, 0, 0)
        if let img = bm.cg.makeImage() { last = img }
        return last
    }
}

// MARK: - Look

struct RidgeStoryLook {
    let paper: Color
    let ink: Color
    let ink2: Color
    let line: Color
    let chip: Color
    let dark: Bool

    init(_ scheme: ColorScheme) {
        dark = scheme == .dark
        let p = dark ? MatrixRGB(0x0E0E10) : MatrixRGB(0xF6F6F4)
        paper = p.color
        ink = dark ? MatrixRGB(0xF4F4F2).color : MatrixRGB(0x0E0E10).color
        ink2 = ink.opacity(0.66)
        line = dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1)
        chip = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}

// MARK: - The view

/// Full-screen Ridge done flow. Present it like MatrixStoryView: an overlay above Home (ignoring
/// safe areas) with the hero card's frame as `cardFrame` so the collapse lands in the card.
struct RidgeStoryView: View {
    let model: MatrixStoryModel
    var cardFrame: CGRect?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var runtime = RidgeStoryRuntime()

    init(model: MatrixStoryModel, cardFrame: CGRect? = nil) {
        self.model = model
        self.cardFrame = cardFrame
    }

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }

    var body: some View {
        let look = RidgeStoryLook(scheme)
        GeometryReader { proxy in
            let size = proxy.size
            let comp = MatrixStoryRuntime.composition(size)
            let s0 = Double(size.width) / max(1, Double(comp.width))
            let oy = (Double(comp.height) - MatrixStoryRuntime.BOX_H) / 2
            let px = RidgeStoryRuntime.pxScale(comp: comp, pointWidth: Double(size.width), displayScale: Double(displayScale))
            TimelineView(.animation(minimumInterval: HeroMotion.minimumInterval, paused: scenePhase != .active)) { tl in
                let t = model.time(tl.date)
                let cp = model.collapse(t)
                let lt = model.lt(t)
                let dz = model.dynamic && !reduceMotion
                let id = model.screen
                let tapAt = model.tapTimes.last
                let sealT = model.sealT
                ZStack(alignment: .topLeading) {
                    look.paper
                    if let img = runtime.frame(model, t: t, comp: comp, pxScale: px, theme: look.dark ? "dark" : "light", reduceMotion: reduceMotion) {
                        Image(decorative: img, scale: 1)
                            .resizable()
                            .interpolation(.medium)
                            .frame(width: size.width, height: size.height)
                            .offset(Self.shake(model, t: t, dz: dz, s0: s0))
                            .scaleEffect(Self.camera(model, t: t, lt: lt, dz: dz), anchor: UnitPoint(x: 0.5, y: 0.75))
                            .accessibilityHidden(true)
                    }
                    // the tap rings out from the world
                    if dz, id == .climax, let tapAt, t - tapAt < 0.7, t - tapAt >= 0 {
                        let k = (t - tapAt) / 0.7
                        let d = (t - tapAt) * 1500 * s0
                        let sealedNow = sealT.map { t - $0 < 0.7 } ?? false
                        Circle()
                            .strokeBorder(sealedNow ? MatrixRGB.coral.color : look.ink, lineWidth: max(1, 6 * (1 - k)) * s0 * 2)
                            .frame(width: d, height: d)
                            .position(x: size.width / 2, y: size.height * 0.72)
                            .opacity(0.5 * (1 - k))
                            .allowsHitTesting(false)
                    }
                    // the seal lands hard
                    if dz, id == .climax, let sealT, t - sealT < 0.6, t >= sealT {
                        Color.white.opacity(0.55 * (1 - (t - sealT) / 0.6)).allowsHitTesting(false)
                    }
                    // paper at the top for the words
                    LinearGradient(stops: [
                        .init(color: look.paper, location: 0),
                        .init(color: look.paper, location: 0.62),
                        .init(color: look.paper.opacity(0.75), location: 0.8),
                        .init(color: look.paper.opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(width: size.width, height: max(0, (oy + (id == .month ? 1500 : 1240)) * s0))
                    .allowsHitTesting(false)
                    RidgeStoryCopyLayer(model: model, t: t, size: size, look: look, reduceMotion: reduceMotion)
                    if id == .month && model.monthPick && model.collapseAt == nil {
                        RidgeMonthPicker(model: model, t: t, size: size, look: look)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .modifier(StoryCollapseModifier(cp: cp, size: size, cardFrame: cardFrame, focus: RidgeStoryRuntime.collapseFocus))
                .onChange(of: tl.date) { _, d in model.advance(to: model.time(d)) }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                guard size.width > 0 else { return }
                model.tap(xFraction: Double(loc.x / size.width), at: model.time(Date()))
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(model.isLast ? "Tap to build today's finish" : "Tap to continue")
    }

    /// story12.tsx camS: a pull-back on every screen, a punch on each tap, a hard landing on the seal.
    private static func camera(_ m: MatrixStoryModel, t: Double, lt: Double, dz: Bool) -> Double {
        guard dz else { return 1 }
        var s = 1 + 0.1 * (1 - eo(lt / 0.9))
        if m.screen == .climax, let tapAt = m.tapTimes.last, m.sealT == nil { s += 0.035 * exp(-(t - tapAt) * 7) }
        if m.screen == .climax, let sealT = m.sealT, t >= sealT { s += 0.07 * exp(-(t - sealT) * 4) }
        return s
    }

    /// story12.tsx shake: the rock jolts on each hit; the rock and the summit settle hard on the seal.
    private static func shake(_ m: MatrixStoryModel, t: Double, dz: Bool, s0: Double) -> CGSize {
        guard dz, m.screen == .climax else { return .zero }
        if m.day == 1, m.sealT == nil, let tapAt = m.tapTimes.last, t >= tapAt {
            let x = exp(-(t - tapAt) * 9) * sin((t - tapAt) * 70) * (6 + Double(m.tapTimes.count) * 2)
            return CGSize(width: x * s0 * 2, height: 0)
        }
        if let sealT = m.sealT, m.day == 1 || m.day == 4, t >= sealT {
            let y = exp(-(t - sealT) * 6) * sin((t - sealT) * 50) * (m.day == 1 ? 14 : 6)
            return CGSize(width: 0, height: y * s0 * 2)
        }
        return .zero
    }
}

// MARK: - Copy layer (story12.tsx HTML side)

private struct RidgeStoryCopyLayer: View {
    let model: MatrixStoryModel
    let t: Double
    let size: CGSize
    let look: RidgeStoryLook
    let reduceMotion: Bool

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }
    private static func eo5(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 5) }

    private static func icon(_ id: MatrixStoryScreen, mp: MatrixMonthPos, sealed: Bool) -> String {
        switch id {
        case .verified: return "checkmark"
        case .today: return "clock.fill"
        case .week: return "flame.fill"
        case .month: return mp == .first ? "sun.max.fill" : "flame.fill"
        case .far: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .climax: return sealed ? "checkmark" : "circle.fill"
        }
    }

    var body: some View {
        let comp = MatrixStoryRuntime.composition(size)
        let cw = Double(comp.width), ch = Double(comp.height)
        let s0 = Double(size.width) / cw
        let ox = (cw - MatrixStoryRuntime.BOX_W) / 2, oy = (ch - MatrixStoryRuntime.BOX_H) / 2
        let u = { (v: Double) -> Double in v * s0 }
        let lt = model.lt(t)
        let id = model.screen
        let sealT = model.sealT
        let sealed = sealT != nil
        let leaving = model.collapseAt.map { t >= $0 } ?? false
        let a = { (at: Double, d: Double) -> Double in Self.eo((lt - at) / d) }
        let dz = model.dynamic && !reduceMotion
        let world = RidgeClimaxCopy.of(model.day)
        let copy = model.copy
        let N = model.N, taps = model.tapTimes.count
        let tapAt = model.tapTimes.last
        let monthFlourish = model.monthPos == .last && model.pos == .last

        let head: (eyebrow: String, title: String, sub: String) = {
            switch id {
            case .climax:
                if sealed { return (model.pos == .last ? "WEEK COMPLETE" : "SESSIONS", "", copy.endSub) }
                return (model.pos == .last ? world.lastEyebrow : world.eyebrow, world.title, world.sub(N))
            case .today:
                let h = copy.headers[.today]
                return (h?.eyebrow ?? "TODAY'S SESSION", h?.title ?? "", copy.today?.caption ?? copy.captions[.today] ?? "")
            default:
                let h = copy.headers[id]
                return (h?.eyebrow ?? "", h?.title ?? "", copy.captions[id] ?? "")
            }
        }()
        let titleS = dz ? 1 + 0.22 * exp(-lt * 6) * cos(lt * 14) : 1
        let midTop: Double = id == .today ? 700 : id == .month ? 560 : 660

        ZStack(alignment: .topLeading) {
            // progress, one segment per screen
            HStack(spacing: u(12)) {
                ForEach(Array(model.ids.enumerated()), id: \.offset) { i, sid in
                    let fill = i < model.idx ? 1 : i > model.idx ? 0 : MX.cl(lt / model.cfg(sid).settle)
                    Capsule().fill(look.line)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in Capsule().fill(look.ink).frame(width: g.size.width * fill) }
                        }
                        .frame(height: max(2, u(6)))
                }
            }
            .frame(width: u(cw - 120))
            .offset(x: u(60), y: u(max(oy, 0) + 90))
            .opacity(leaving ? 0 : 1)

            // the header: eyebrow with its icon, the title, the line under it
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: u(16)) {
                    Image(systemName: Self.icon(id, mp: model.monthPos, sealed: sealed))
                        .font(.system(size: u(18), weight: .black))
                        .foregroundStyle(look.paper)
                        .frame(width: u(40), height: u(40))
                        .background(Circle().fill(look.ink))
                    Text(head.eyebrow)
                        .font(.system(size: u(30), weight: .heavy))
                        .tracking((0.06 + (1 - a(0.05, 0.35)) * 0.2) * u(30))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(look.ink)
                .opacity(a(0.05, 0.35))

                RidgeTitle(model: model, t: t, lt: lt, title: head.title, u: u, look: look, reduceMotion: reduceMotion)
                    .padding(.top, u(14))
                    .scaleEffect(titleS, anchor: UnitPoint(x: 0, y: 0.8))

                if !head.sub.isEmpty {
                    MatrixRich.text(head.sub, size: u(44), weight: .regular, color: look.ink2, boldColor: look.ink, boldWeight: .bold)
                        .lineSpacing(u(6))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .padding(.top, u(14))
                        .opacity(a(0.45, 0.35))
                        .offset(y: (1 - a(0.45, 0.35)) * u(16))
                }
            }
            .frame(width: u(920), alignment: .leading)
            .offset(x: u(ox + 80), y: u(oy + 210))
            .id("t" + id.rawValue)

            // the middle: figures, the week, the month, the long run, the finish
            RidgeMiddle(model: model, t: t, lt: lt, u: u, look: look, world: world, tapAt: tapAt, taps: taps, N: N)
                .frame(width: u(920), alignment: .leading)
                .offset(x: u(ox + 80), y: u(oy + midTop))
                .id("m" + id.rawValue)

            // the month's last session: the month closes in marker on the paper
            if id == .climax, let sealT, monthFlourish, let cal = model.cal, let name = copy.monthName {
                let since = t - sealT
                let line = cal.sessions >= cal.target ? "\(name), done." : "\(name): \(cal.sessions) of \(cal.target)."
                VStack(alignment: .leading, spacing: u(6)) {
                    Text(line.uppercased())
                        .font(.system(size: u(84), weight: .black, design: .rounded).italic())
                        .foregroundStyle(look.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    RidgeSwoosh(p: Self.eo((since - 1.5) / 0.5))
                        .stroke(MatrixRGB.coral.color, style: StrokeStyle(lineWidth: u(10), lineCap: .round))
                        .frame(width: u(360), height: u(30))
                }
                .frame(width: u(900), alignment: .leading)
                .scaleEffect(1 + 0.4 * (1 - Self.eo((since - 1.2) / 0.5)), anchor: .leading)
                .opacity(Self.eo(since / 0.4 - 3))
                .rotationEffect(.degrees(-5), anchor: .topLeading)
                .offset(x: u(ox + 80), y: u(oy + 1190))
            }

            // the foot: the hint, or the finish's button filling with each tap
            Group {
                if !model.isLast {
                    let show = model.settled(t)
                    Text(id == .month && model.monthPick && !model.picked ? "Pick a target" : "Tap to continue \u{203A}")
                        .font(.system(size: u(28), weight: .bold))
                        .foregroundStyle(Color.white.opacity(show ? 0.75 + 0.2 * sin(lt * 4) : 0))
                        .padding(.vertical, u(14))
                        .padding(.horizontal, u(28))
                        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .environment(\.colorScheme, .dark)
                        .opacity(show ? 1 : 0)
                } else {
                    let fill = sealed ? 1 : min(1, Double(taps) / Double(max(1, N)))
                    let label = sealed ? copy.endButton : taps > 0 ? (taps >= N - 1 ? "One more" : world.mid) : world.idle
                    Text(label)
                        .font(.system(size: u(34), weight: .heavy))
                        .foregroundStyle(look.paper)
                        .padding(.vertical, u(28))
                        .padding(.horizontal, u(50))
                        .background {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    look.ink
                                    MatrixRGB.coral.color.frame(width: g.size.width * fill)
                                }
                            }
                        }
                        .clipShape(Capsule())
                        .opacity(a(0.4, 0.35))
                }
            }
            .frame(width: size.width, height: u(250))
            .offset(y: Double(size.height) - u(250))
            .opacity(leaving ? 0 : 1)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([head.eyebrow.capitalized, head.title, head.sub.replacingOccurrences(of: "**", with: "")].filter { !$0.isEmpty }.joined(separator: ". "))
    }
}

/// The big line: the title rising word by word, the session's length rolling up on Today, or the
/// count rolling over after the seal.
private struct RidgeTitle: View {
    let model: MatrixStoryModel
    let t: Double
    let lt: Double
    let title: String
    let u: (Double) -> Double
    let look: RidgeStoryLook
    let reduceMotion: Bool

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }
    private static func eo5(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 5) }

    var body: some View {
        let id = model.screen
        if id == .climax, let sealT = model.sealT {
            let n = model.copy.sessions > 0 ? model.copy.sessions : model.dayData.sessions
            let roll = Self.eo((t - sealT - 0.45) / 0.5)
            let size = u(158)
            let lineH = size * 1.2
            HStack(alignment: .bottom, spacing: u(24)) {
                VStack(spacing: 0) {
                    Text(String(max(0, n - 1))).frame(height: lineH)
                    Text(String(n)).frame(height: lineH)
                }
                .font(.system(size: size, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(look.ink)
                .fixedSize()
                .offset(y: -roll * lineH)
                .frame(height: lineH, alignment: .top)
                .clipped()
                Text(model.pos == .last ? "sessions. Week done." : "and counting.")
                    .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                    .foregroundStyle(look.ink)
                    .opacity(Self.eo((t - sealT - 0.8) / 0.4))
                    .padding(.bottom, lineH * 0.18)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(n) sessions")
        } else if id == .today {
            Group {
                if let mins = model.copy.today?.minutes, mins > 0 {
                    let s = Int((Self.eo5((lt - 0.15) / 1.2) * Double(mins * 60)).rounded(.down))
                    Text(String(format: "%02d:%02d", s / 60, s % 60))
                } else if let td = model.copy.today {
                    Text(td.end.map { "\(td.start)\u{2013}\($0)" } ?? td.start)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: u(210), weight: .black, design: .rounded))
            .monospacedDigit()
            .tracking(-0.035 * u(150))
            .foregroundStyle(look.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.35)
            .opacity(MX.cl(lt * 6))
        } else if !title.isEmpty {
            let rise = reduceMotion ? 1 : Self.eo((lt - 0.1) / 0.45)
            Text(title)
                .font(.system(size: u(158), weight: .black, design: .rounded))
                .tracking(-0.035 * u(158))
                .foregroundStyle(look.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .offset(y: (1 - rise) * u(60))
                .opacity(rise)
        }
    }
}

/// The block under the header (story12.tsx `key={'m' + id}`), real figures only.
private struct RidgeMiddle: View {
    let model: MatrixStoryModel
    let t: Double
    let lt: Double
    let u: (Double) -> Double
    let look: RidgeStoryLook
    let world: RidgeClimaxCopy
    let tapAt: Double?
    let taps: Int
    let N: Int

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }

    private func a(_ at: Double, _ d: Double = 0.35) -> Double { Self.eo((lt - at) / d) }

    var body: some View {
        let copy = model.copy
        VStack(alignment: .leading, spacing: 0) {
            switch model.screen {
            case .verified:
                if let stats = copy.today?.stats, !stats.isEmpty {
                    RidgeStatsRow(stats: stats, at: 0.5, lt: lt, u: u, look: look)
                }
                if let n = copy.appsUnlocked, n > 0 {
                    RidgeChip(text: n == 1 ? "1 app unlocked" : "\(n) apps unlocked", u: u, look: look, coralDot: true)
                        .padding(.top, u(30))
                        .modifier(RidgeUp(p: a(0.9)))
                }
                if let r = copy.research[.verified] {
                    RidgeNote(text: r, u: u, look: look).padding(.top, u(34)).modifier(RidgeUp(p: a(1.2)))
                }
            case .today:
                if let td = copy.today {
                    if !td.stats.isEmpty {
                        RidgeStatsRow(stats: td.stats, at: 0.6, lt: lt, u: u, look: look)
                    }
                    RidgeChip(text: td.end.map { "\(td.start) to \($0)" } ?? "In at \(td.start)", u: u, look: look, coralDot: false)
                        .padding(.top, u(30))
                        .modifier(RidgeUp(p: a(1.1)))
                }
                if let r = copy.research[.today] {
                    RidgeNote(text: r, u: u, look: look).padding(.top, u(30)).modifier(RidgeUp(p: a(1.3)))
                }
            case .week:
                if !copy.weekDays.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(copy.weekDays.enumerated()), id: \.offset) { k, d in
                            let lit = d.done && a(0.5 + Double(k) * 0.08, 0.3) > 0.5
                            VStack(spacing: u(8)) {
                                RidgePebble(s: u(86), on: lit, ink: d.isToday && lit ? MatrixRGB.coral.color : look.ink, line: look.line, k: k)
                                Text(d.done ? d.minutes.map { "\($0)m" } ?? "\u{2713}" : "\u{00B7}")
                                    .font(.system(size: u(30), weight: .heavy, design: .rounded))
                                    .foregroundStyle(d.done ? look.ink : look.ink2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(d.label)
                                    .font(.system(size: u(22), weight: .heavy))
                                    .tracking(0.1 * u(22))
                                    .foregroundStyle(d.isToday ? look.ink : look.ink2)
                                    .underline(d.isToday)
                            }
                            .frame(maxWidth: .infinity)
                            .modifier(RidgeUp(p: a(0.3 + Double(k) * 0.06)))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(d.label), \(d.done ? "trained" : "no session")")
                        }
                    }
                }
                if !copy.weekStats.isEmpty {
                    RidgeStatsRow(stats: copy.weekStats, at: 0.9, lt: lt, u: u, look: look).padding(.top, u(36))
                }
                if let r = copy.research[.week] {
                    RidgeNote(text: r, u: u, look: look).padding(.top, u(34)).modifier(RidgeUp(p: a(1.3)))
                }
            case .month:
                if !model.monthPick {
                    RidgeMonthBlock(model: model, lt: lt, u: u, look: look, picker: nil)
                }
            case .far:
                if copy.farWeeks.count >= 2 {
                    Text("TIME EACH WEEK")
                        .font(.system(size: u(24), weight: .bold))
                        .tracking(0.1 * u(24))
                        .foregroundStyle(look.ink2)
                        .modifier(RidgeUp(p: a(0.2)))
                    RidgeWeeksChart(weeks: copy.farWeeks, p: Self.eo((lt - 0.3) / 1.2), u: u, look: look)
                        .frame(width: u(920), height: u(250))
                        .padding(.top, u(10))
                }
                if !copy.farStats.isEmpty {
                    RidgeStatsRow(stats: copy.farStats, at: 0.8, lt: lt, u: u, look: look).padding(.top, u(30))
                }
                if let r = copy.research[.far] {
                    RidgeNote(text: r, u: u, look: look).padding(.top, u(30)).modifier(RidgeUp(p: a(1.4)))
                }
            case .climax:
                if let sealT = model.sealT {
                    let sealAt = sealT - (t - lt)
                    RidgeNote(text: [world.end, MatrixClimaxCopy.posTail(model.pos)].filter { !$0.isEmpty }.joined(separator: " "), u: u, look: look)
                        .modifier(RidgeUp(p: a(0.9 + sealAt)))
                } else {
                    HStack(spacing: u(16)) {
                        ForEach(0..<N, id: \.self) { k in
                            let pop = k == taps - 1 && tapAt != nil ? 1 + 0.4 * max(0, 1 - (t - (tapAt ?? t)) * 4) : 1
                            Circle()
                                .fill(k < taps ? look.ink : .clear)
                                .overlay { if k >= taps { Circle().strokeBorder(look.ink2, lineWidth: u(3)) } }
                                .frame(width: u(34), height: u(34))
                                .scaleEffect(pop)
                        }
                    }
                    .modifier(RidgeUp(p: a(0.5)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(taps) of \(N) taps")
                }
            }
        }
    }
}

/// The month screen (story12.tsx `id === 'month'`): the calendar, then the target buttons or the
/// month's figures, then the research note.
private struct RidgeMonthBlock: View {
    let model: MatrixStoryModel
    let lt: Double
    let u: (Double) -> Double
    let look: RidgeStoryLook
    let picker: ((Int) -> Void)?

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }
    private func a(_ at: Double, _ d: Double = 0.35) -> Double { Self.eo((lt - at) / d) }

    var body: some View {
        let copy = model.copy
        VStack(alignment: .leading, spacing: 0) {
            if let cal = model.cal {
                let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                let showPlan = model.picked || model.monthPos == .last || !model.monthPick
                let planned: [Bool] = {
                    var fut = 0
                    return cal.cells.map { c in
                        if c == "future" { fut += 1 }
                        return c == "future" && showPlan && cal.sessions + fut <= cal.target
                    }
                }()
                LazyVGrid(columns: cols, spacing: u(4)) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                        Text(d)
                            .font(.system(size: u(20), weight: .heavy))
                            .tracking(0.1 * u(20))
                            .foregroundStyle(look.ink2)
                    }
                    ForEach(0..<cal.lead, id: \.self) { _ in Color.clear.frame(height: u(10)) }
                    ForEach(Array(cal.cells.enumerated()), id: \.offset) { i, c in
                        let on = a(0.25 + Double(i) * 0.022, 0.25)
                        VStack(spacing: u(2)) {
                            if c == "today" {
                                Capsule().fill(MatrixRGB.coral.color)
                                    .frame(width: u(46), height: u(34))
                                    .scaleEffect(1 + 0.08 * sin(lt * 4))
                            } else {
                                RidgePebble(s: u(46), on: c == "done", ink: c == "miss" ? look.ink2 : look.ink, line: look.line, k: i)
                                    .frame(height: u(34))
                            }
                            Text("\(i + 1)")
                                .font(.system(size: u(15), weight: .bold))
                                .foregroundStyle(c == "today" || planned[i] ? look.ink : look.ink2)
                                .opacity(c == "future" && !planned[i] ? 0.5 : 1)
                        }
                        .opacity(0.25 + 0.75 * on)
                    }
                }
                .modifier(RidgeUp(p: a(0.15)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(cal.sessions) sessions this month, target \(cal.target)")
            }
            if let picker {
                HStack(spacing: u(16)) {
                    ForEach(copy.monthTargets, id: \.n) { m in
                        let sel = model.picked && model.cal?.target == m.n
                        Button {
                            picker(m.n)
                        } label: {
                            VStack(spacing: u(6)) {
                                Text("\(m.n)")
                                    .font(.system(size: u(64), weight: .black, design: .rounded))
                                Text(m.label.uppercased())
                                    .font(.system(size: u(20), weight: .heavy))
                                    .tracking(0.12 * u(20))
                                    .opacity(0.75)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .foregroundStyle(sel ? look.paper : look.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.top, u(18))
                            .padding(.bottom, u(16))
                            .background {
                                RoundedRectangle(cornerRadius: u(28), style: .continuous)
                                    .fill(sel ? look.ink : .clear)
                                    .overlay {
                                        if !sel { RoundedRectangle(cornerRadius: u(28), style: .continuous).strokeBorder(look.line, lineWidth: u(3)) }
                                    }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: u(28), style: .continuous))
                        }
                        .buttonStyle(RidgePressStyle())
                        .accessibilityLabel("\(m.n) sessions, \(m.label)")
                        .accessibilityAddTraits(sel ? .isSelected : [])
                    }
                }
                .padding(.top, u(26))
                .modifier(RidgeUp(p: a(0.9)))
            } else if !copy.monthStats.isEmpty {
                RidgeStatsRow(stats: copy.monthStats, at: 0.8, lt: lt, u: u, look: look).padding(.top, u(26))
            }
            if let r = copy.research[.month] {
                RidgeNote(text: r, u: u, look: look).padding(.top, u(26)).modifier(RidgeUp(p: a(1.2)))
            }
        }
    }
}

/// The month screen with a target to pick: the same block, but its buttons take taps.
private struct RidgeMonthPicker: View {
    let model: MatrixStoryModel
    let t: Double
    let size: CGSize
    let look: RidgeStoryLook

    var body: some View {
        let comp = MatrixStoryRuntime.composition(size)
        let cw = Double(comp.width), ch = Double(comp.height)
        let s0 = Double(size.width) / cw
        let ox = (cw - MatrixStoryRuntime.BOX_W) / 2, oy = (ch - MatrixStoryRuntime.BOX_H) / 2
        let u = { (v: Double) -> Double in v * s0 }
        RidgeMonthBlock(model: model, lt: model.lt(t), u: u, look: look) { n in
            model.pickTarget(n, at: model.time(Date()))
        }
        .frame(width: u(920), alignment: .leading)
        .offset(x: u(ox + 80), y: u(oy + 560))
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - Pieces

private struct RidgeUp: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content.opacity(p).offset(y: (1 - p) * 16)
    }
}

/// story12.tsx statRow: label over the figure, columns split by hairlines; counts roll up.
private struct RidgeStatsRow: View {
    let stats: [MatrixStoryCopy.Stat]
    let at: Double
    let lt: Double
    let u: (Double) -> Double
    let look: RidgeStoryLook

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }
    private static func eo5(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 5) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { k, s in
                let v: String = s.roll.map { n in String(Int(JSMath.round(Self.eo5((lt - at) / 1.1) * Double(n)))) } ?? s.value
                let p = Self.eo((lt - at - Double(k) * 0.12) / 0.35)
                VStack(alignment: .leading, spacing: u(4)) {
                    Text(s.label.uppercased())
                        .font(.system(size: u(24), weight: .bold))
                        .tracking(0.1 * u(24))
                        .foregroundStyle(look.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: u(6)) {
                        Text(v)
                            .font(.system(size: u(76), weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(s.coral ? MatrixRGB.coral.color : look.ink)
                        if let unit = s.unit {
                            Text(unit)
                                .font(.system(size: u(28), weight: .heavy, design: .rounded))
                                .foregroundStyle(look.ink2)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                }
                .padding(.leading, k > 0 ? u(26) : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    if k > 0 { Rectangle().fill(look.line).frame(width: max(1, u(2))) }
                }
                .opacity(p)
                .offset(y: (1 - p) * 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(s.value)\(s.unit.map { " \($0)" } ?? ""), \(s.label.lowercased())")
            }
        }
    }
}

/// story12.tsx note: a quiet line with an ink rule on the left.
private struct RidgeNote: View {
    let text: String
    let u: (Double) -> Double
    let look: RidgeStoryLook

    var body: some View {
        MatrixRich.text(text, size: u(31), weight: .medium, color: look.ink2, boldColor: look.ink, boldWeight: .bold)
            .lineSpacing(u(8))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, u(24))
            .overlay(alignment: .leading) { Rectangle().fill(look.ink).frame(width: max(2, u(4))) }
            .frame(maxWidth: u(900), alignment: .leading)
    }
}

private struct RidgeChip: View {
    let text: String
    let u: (Double) -> Double
    let look: RidgeStoryLook
    let coralDot: Bool

    var body: some View {
        HStack(spacing: u(10)) {
            if coralDot {
                Circle().fill(MatrixRGB.coral.color).frame(width: u(14), height: u(14))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: u(14), weight: .black))
                    .foregroundStyle(look.paper)
                    .frame(width: u(30), height: u(30))
                    .background(Circle().fill(look.ink))
            }
            Text(text)
                .font(.system(size: u(28), weight: .bold))
                .foregroundStyle(look.ink)
                .monospacedDigit()
        }
        .padding(.vertical, u(14))
        .padding(.horizontal, u(22))
        .background(Capsule().fill(look.chip))
    }
}

/// card12.tsx Pebble: a river stone, filled when the day counted.
private struct RidgePebble: View {
    let s: Double
    let on: Bool
    let ink: Color
    let line: Color
    let k: Int

    var body: some View {
        let rot = Double((k * 37) % 23) - 11
        let squash = 0.74 + Double((k * 13) % 7) * 0.02
        Ellipse()
            .fill(on ? ink : .clear)
            .overlay { if !on { Ellipse().strokeBorder(line, lineWidth: max(1, s * 0.045)) } }
            .frame(width: s, height: s * squash)
            .rotationEffect(.degrees(rot))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
    }
}

/// story12.tsx far chart: minutes per week, the newest week in coral.
private struct RidgeWeeksChart: View {
    let weeks: [Int]
    let p: Double
    let u: (Double) -> Double
    let look: RidgeStoryLook

    var body: some View {
        Canvas { ctx, size in
            let W = Double(size.width), H = Double(size.height)
            guard weeks.count >= 2, W > 0 else { return }
            let k = W / 920
            let top = max(1, Double(weeks.max() ?? 1)) * 1.1
            let pts: [CGPoint] = weeks.enumerated().map { i, m in
                CGPoint(x: (30 + Double(i) / Double(weeks.count - 1) * 860) * k, y: (210 - Double(m) / top * 190) * k)
            }
            let n = max(1, Int((Double(weeks.count) * p).rounded(.up)))
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: 212 * k)); $0.addLine(to: CGPoint(x: W, y: 212 * k)) }, with: .color(look.line), lineWidth: 2 * k)
            var path = Path()
            for (i, q) in pts.prefix(n).enumerated() { if i == 0 { path.move(to: q) } else { path.addLine(to: q) } }
            ctx.stroke(path, with: .color(look.ink), style: StrokeStyle(lineWidth: 4 * k, lineJoin: .round))
            for (i, q) in pts.prefix(n).enumerated() {
                let last = i == weeks.count - 1
                let r = (last ? 12 : 8) * k
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)), with: .color(last ? MatrixRGB.coral.color : look.ink))
            }
            for (i, q) in pts.enumerated() {
                let label = i == weeks.count - 1 ? "NOW" : "W\(i + 1)"
                ctx.draw(Text(label).font(.system(size: 22 * k, weight: .bold)).foregroundStyle(look.ink2), at: CGPoint(x: q.x, y: 238 * k))
            }
            _ = H
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minutes each week, from \(weeks.first ?? 0) to \(weeks.last ?? 0)")
    }
}

/// card8.tsx Swoosh: a marker underline drawn left to right.
private struct RidgeSwoosh: Shape {
    var p: Double
    func path(in r: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.2))
        path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY - r.height * 0.15), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.2))
        return path.trimmedPath(from: 0, to: MX.cl(p))
    }
}

private struct RidgePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
