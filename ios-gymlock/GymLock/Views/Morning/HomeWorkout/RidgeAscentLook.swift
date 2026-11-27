//
//  RidgeAscentLook.swift
//  GymLock · home workout look "Ridge A, ascent"
//
//  The painted ridge world with a camera that climbs it as the minutes pass: setup is zoomed on
//  the valley, the summit is reached at 20:00, then a wide pull-back reveal with light rays, and
//  a slow rise into a few stars. A dotted trail with camps at 5/10/15 and a flag at the apex, a
//  hiker pin on the trail, and a giant white clock clipped to the sky so it sits behind the ridge.
//  Pure function of HomeWorkoutFrame (the host rebuilds the frame every tick).
//
//  Approved prototype: docs/prototypes/home-workout-variations.html (variation "ridge a")
//  Geometry is authored in the prototype's 390 x 844 design space and scaled to the real screen.
//

import SwiftUI

// MARK: - Maths

private let rhaW: Double = 390
private let rhaH: Double = 844
private let rhaNight = Color(red: 5 / 255, green: 8 / 255, blue: 22 / 255)

private func rhaClamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { max(a, min(b, x)) }
private func rhaLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func rhaEaseOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
private func rhaEaseIO(_ x: Double) -> Double { x * x * (3 - 2 * x) }

/// cubic-bezier(.22,.9,.24,1), the app's settle curve, solved for y at a given x.
private func rhaSettle(_ x: Double) -> Double {
    let x = rhaClamp(x)
    if x == 0 || x == 1 { return x }
    let x1 = 0.22, y1 = 0.9, x2 = 0.24, y2 = 1.0
    func bez(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }
    var lo = 0.0, hi = 1.0
    for _ in 0..<24 {
        let mid = (lo + hi) / 2
        if bez(x1, x2, mid) < x { lo = mid } else { hi = mid }
    }
    return bez(y1, y2, (lo + hi) / 2)
}

// MARK: - Static geometry (computed once)

private enum RHAGeo {
    static let fit = HomeWorkoutRidge.Fit(size: CGSize(width: rhaW, height: rhaH))
    static let apex: CGPoint = fit.point(HomeWorkoutRidge.apex)
    static let imageRect = CGRect(
        x: fit.ox, y: fit.oy,
        width: HomeWorkoutRidge.worldW * fit.k, height: HomeWorkoutRidge.worldH * fit.k
    )
}

private struct RHATrail {
    struct Seg { let a: CGPoint; let b: CGPoint; let d: Double; let s: Double }
    struct Dot { let d: Double; let p: CGPoint }

    let segs: [Seg]
    let length: Double
    let dots: [Dot]
    /// Camp distances along the trail at 25 / 50 / 75 / 100 %.
    let camps: [Double]

    static let shared = RHATrail()

    init() {
        let apex = RHAGeo.apex
        let pts: [CGPoint] = [
            CGPoint(x: 35, y: 640), CGPoint(x: 150, y: 618), CGPoint(x: 60, y: 596),
            CGPoint(x: 150, y: 572), CGPoint(x: 95, y: 552), CGPoint(x: 170, y: 545),
            CGPoint(x: 186, y: 512), CGPoint(x: 200, y: 486), CGPoint(x: apex.x, y: apex.y + 2)
        ]
        var total = 0.0
        var s: [Seg] = []
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let d = Double(hypot(b.x - a.x, b.y - a.y))
            s.append(Seg(a: a, b: b, d: d, s: total))
            total += d
        }
        segs = s
        length = total
        var ds: [Dot] = []
        var d = 0.0
        while d <= total + 0.1 {
            ds.append(Dot(d: d, p: RHATrail.point(s, total, d)))
            d += 4.5
        }
        dots = ds
        camps = [0.25, 0.5, 0.75, 1].map { $0 * total }
    }

    private static func point(_ segs: [Seg], _ length: Double, _ dist: Double) -> CGPoint {
        let d = rhaClamp(dist, 0, length)
        for sg in segs where d <= sg.s + sg.d {
            let f = sg.d > 0 ? (d - sg.s) / sg.d : 0
            return CGPoint(x: sg.a.x + (sg.b.x - sg.a.x) * f, y: sg.a.y + (sg.b.y - sg.a.y) * f)
        }
        return segs[segs.count - 1].b
    }

    func at(_ dist: Double) -> CGPoint { RHATrail.point(segs, length, dist) }
}

private struct RHAStar { let x: Double; let y: Double; let r: Double; let a: Double }

/// 56 stars from the prototype's seeded generator, so the sky is the same every time.
private let rhaStars: [RHAStar] = {
    var seed = 7
    func rnd() -> Double {
        seed = (seed * 16807) % 2147483647
        return Double(seed) / 2147483647
    }
    var out: [RHAStar] = []
    for _ in 0..<56 {
        let x = rnd() * rhaW
        let y = 14 + rnd() * 400
        let r = 0.7 + rnd() * 1.1
        let a = 0.4 + rnd() * 0.6
        out.append(RHAStar(x: x, y: y, r: r, a: a))
    }
    return out
}()

// MARK: - Camera

private struct RHACam {
    var s: Double, fx: Double, fy: Double, ax: Double, ay: Double
    /// Reveal progress after 20:00 (0 before, 1 fully pulled back).
    var r: Double

    func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (Double(p.x) - fx) * s + ax, y: (Double(p.y) - fy) * s + ay)
    }

    /// Image px to design-space screen px.
    var imageTransform: CGAffineTransform {
        let k = Double(RHAGeo.fit.k)
        return CGAffineTransform(
            a: s * k, b: 0, c: 0, d: s * k,
            tx: (Double(RHAGeo.fit.ox) - fx) * s + ax,
            ty: (Double(RHAGeo.fit.oy) - fy) * s + ay
        )
    }
}

private func rhaReveal(_ t: Double, rm: Bool) -> Double {
    if t < 1200 { return 0 }
    if rm { return 1 }
    // Wall-clock 1.4 s after 20:00, derived from elapsed so a resumed app lands on the end state.
    return rhaClamp((t - 1200) / 1.4)
}

private func rhaCamera(t: Double, setup: Bool, ent: Double, mp: Double, rm: Bool) -> RHACam {
    let p = min(t / 1200, 1)
    let e = p * 0.55 + rhaEaseIO(p) * 0.45
    var c = RHACam(
        s: rhaLerp(2.2, 1.9, e), fx: rhaLerp(89, 217, e), fy: rhaLerp(640, 468, e),
        ax: 195, ay: rhaLerp(545, 540, e), r: 0
    )
    let pe = 1 - rhaEaseOut(ent)
    if setup && !rm {
        c.s *= 1 + 0.2 * pe
    } else if mp < 1 && !rm {
        c.s *= 1 + 0.2 * pe * (1 - mp)
    }
    let r = rhaReveal(t, rm: rm)
    if r > 0 {
        let u = rhaClamp((t - 1200) / 480) * 0.92
        let ws = 1 + 0.2 * u
        let rr = rm ? 1 : rhaEaseIO(r)
        c.s = rhaLerp(c.s, ws, rr)
        c.fx = rhaLerp(c.fx, 195, rr)
        c.fy = rhaLerp(c.fy, 422 / ws + 0.5, rr)
        c.ax = rhaLerp(c.ax, 195, rr)
        c.ay = rhaLerp(c.ay, 422, rr)
    }
    c.r = r
    return c
}

// MARK: - Canvas drawing

private enum RHADraw {
    static func scene(_ ctx: inout GraphicsContext, size: CGSize, f: HomeWorkoutFrame, world: CGImage?) {
        let sc = Double(size.width) / rhaW
        let yoff = (Double(size.height) - rhaH * sc) / 2
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.logoBackdrop))
        ctx.translateBy(x: 0, y: yoff)
        ctx.scaleBy(x: sc, y: sc)
        let bottomY = (Double(size.height) - yoff) / sc

        let rm = f.reduceMotion
        let timer = f.isRunning
        let t = timer ? f.elapsed : 0
        let mp = timer ? rhaEaseIO(rhaClamp(f.runAge / (rm ? 0.2 : 0.95))) : 0
        let ent = rhaClamp(f.setupAge / 1.2)
        let cam = rhaCamera(t: t, setup: !timer, ent: ent, mp: mp, rm: rm)

        // World under the camera.
        ctx.drawLayer { c in
            c.translateBy(x: cam.ax, y: cam.ay)
            c.scaleBy(x: cam.s, y: cam.s)
            c.translateBy(x: -cam.fx, y: -cam.fy)
            if let world {
                let img = c.resolve(Image(decorative: world, scale: 1).interpolation(.medium))
                c.draw(img, in: RHAGeo.imageRect)
            }
        }
        // Night overlay lightens as the sky opens up.
        let ovA = 0.26 - 0.12 * cam.r
        ctx.fill(
            Path(CGRect(x: -400, y: -400, width: rhaW + 800, height: bottomY + 800)),
            with: .color(rhaNight.opacity(ovA))
        )

        // Sky layer: stars, rays and the clock, all clipped to the sky so the ridge covers them.
        ctx.drawLayer { l in
            let sky = HomeWorkoutRidge.skyline
            if sky.count == 91 {
                l.clip(to: HomeWorkoutRidge.skyPath().applying(cam.imageTransform))
            }
            let u2 = t >= 1200 ? rhaClamp((t - 1200) / 90) * cam.r : 0
            if u2 > 0 {
                for st in rhaStars {
                    let rect = CGRect(x: st.x - st.r, y: st.y - st.r, width: st.r * 2, height: st.r * 2)
                    l.fill(Path(ellipseIn: rect), with: .color(.white.opacity(st.a * u2)))
                }
            }
            if cam.r > 0 { rays(&l, cam: cam) }
            if mp > 0 { clock(&l, t: t, mp: mp, rm: rm) }
        }

        // Bottom shade for legibility of the copy and the host button.
        let shadeA = (timer && mp > 0.5) ? 0.5 : 0.62
        ctx.fill(
            Path(CGRect(x: -400, y: 560, width: rhaW + 800, height: bottomY - 560 + 400)),
            with: .linearGradient(
                Gradient(colors: [rhaNight.opacity(0), rhaNight.opacity(shadeA)]),
                startPoint: CGPoint(x: 0, y: 560), endPoint: CGPoint(x: 0, y: rhaH)
            )
        )

        trail(&ctx, f: f, cam: cam, t: t, mp: mp, timer: timer)
    }

    // MARK: Rays

    private static func rays(_ l: inout GraphicsContext, cam: RHACam) {
        let ap = cam.toScreen(RHAGeo.apex)
        let env = 0.07 + 0.17 * sin(Double.pi * min(cam.r, 1))
        let n = 12
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [.white.opacity(env), .white.opacity(0)]),
            center: ap, startRadius: 10, endRadius: 520
        )
        for i in 0..<n {
            let ang = -Double.pi * (0.08 + 0.84 * Double(i) / Double(n - 1))
            let w = 0.045 + Double(i % 2) * 0.025
            var p = Path()
            p.move(to: ap)
            p.addLine(to: CGPoint(x: ap.x + cos(ang - w) * 560, y: ap.y + sin(ang - w) * 560))
            p.addLine(to: CGPoint(x: ap.x + cos(ang + w) * 560, y: ap.y + sin(ang + w) * 560))
            p.closeSubpath()
            l.fill(p, with: shading)
        }
    }

    // MARK: Clock

    private static func cellFont(_ fs: Double) -> Font { .system(size: fs, weight: .heavy) }

    private static func clock(_ l: inout GraphicsContext, t: Double, mp: Double, rm: Bool) {
        let str = HomeWorkoutClock.format(t)
        let room = CGSize(width: 2000, height: 2000)
        let base: Double = 132
        let dw0 = Double(l.resolve(Text("0").font(cellFont(base)).monospacedDigit()).measure(in: room).width)
        let cw0 = Double(l.resolve(Text(":").font(cellFont(base))).measure(in: room).width) * 0.9
        let digits = Double(str.count - 1)
        let tot0 = digits * dw0 + cw0
        let fs = tot0 > 312 ? base * 312 / tot0 : base
        let k = fs / base
        let dw = dw0 * k, cw = cw0 * k

        let off = (1 - mp) * (rm ? 0 : 150)
        let alpha = rm ? mp : min(1, mp * 2.2)
        let grad = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [.white.opacity(0.98), .white.opacity(0.62)]),
            startPoint: CGPoint(x: 0, y: 215 + off), endPoint: CGPoint(x: 0, y: 320 + off)
        )
        let baseline = 316 + off
        var sx = 28.0
        l.drawLayer { c in
            c.opacity = alpha
            for ch in str {
                let isColon = ch == ":"
                let w = isColon ? cw : dw
                var r = c.resolve(
                    isColon ? Text(":").font(cellFont(fs)) : Text(String(ch)).font(cellFont(fs)).monospacedDigit()
                )
                r.shading = grad
                c.draw(r, at: CGPoint(x: sx + w / 2, y: baseline - Double(r.firstBaseline(in: room))), anchor: .top)
                sx += w
            }
        }
    }

    // MARK: Trail, camps, pin

    private static func dot(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func trail(_ ctx: inout GraphicsContext, f: HomeWorkoutFrame, cam: RHACam, t: Double, mp: Double, timer: Bool) {
        let tr = RHATrail.shared
        let rm = f.reduceMotion
        let cps = HomeWorkoutClock.checkpoints
        let dist = min(t / 1200, 1) * tr.length
        let nc = timer ? (t < 1200 ? (cps.firstIndex { $0 > t } ?? -1) : -1) : -1
        let segA = nc > 0 ? tr.camps[nc - 1] : 0
        let segB = nc >= 0 ? tr.camps[nc] : 0
        let sp = nc >= 0 ? HomeWorkoutClock.spurt(t) : 0
        let entering = !timer || mp < 1
        let trailRaw = rhaEaseOut(rhaClamp((f.setupAge - 0.25) / 0.9))
        let trailIn = entering ? trailRaw : 1
        // Reduce Motion: the whole trail fades in instead of drawing outward.
        let trailAlpha = (rm && entering) ? trailRaw : 1
        let reach = rm ? 1.0 : trailIn

        for q in tr.dots {
            if q.d > tr.length * reach + 1 { break }
            let p = cam.toScreen(q.p)
            if p.y < -10 || p.y > rhaH + 10 { continue }
            var a = q.d <= dist ? 0.95 : 0.3
            var r = 1.7
            if nc >= 0 && q.d > segA && q.d <= segB && q.d > dist {
                a = 0.3 + 0.65 * sp
                if !rm {
                    let ph = q.d / 22 - f.now / 0.42
                    let w = max(0, sin(ph * 2 * Double.pi))
                    r = 1.7 + 1.6 * sp * w
                    a = min(1, a + 0.3 * sp * w)
                }
            }
            ctx.fill(dot(Double(p.x), Double(p.y), r), with: .color(.white.opacity(a * trailAlpha)))
        }

        for i in 0..<4 {
            let wp = i == 3 ? CGPoint(x: RHAGeo.apex.x, y: RHAGeo.apex.y + 2) : tr.at(tr.camps[i])
            let p = cam.toScreen(wp)
            let reached = timer && t >= cps[i]
            let inA = entering ? rhaEaseOut(rhaClamp((f.setupAge - 0.5 - Double(i) * 0.14) / 0.5)) : 1
            var sc = rm ? 1 : inA
            let dt = t - cps[i]
            if reached && !rm && dt >= 0 && dt < 0.6 {
                sc = 1 + 0.7 * sin(Double.pi * dt / 0.6) * (1 - dt / 0.6)
            }
            let x = Double(p.x), y = Double(p.y)
            if i < 3 {
                ctx.stroke(
                    dot(x, y, 5.5 * sc),
                    with: .color(.white.opacity((reached ? 1 : 0.7) * inA)), lineWidth: 1.5
                )
                ctx.fill(
                    dot(x, y, (reached ? 4.2 : 3.2) * sc),
                    with: .color(.white.opacity(reached ? 0.98 : 0.18 * inA))
                )
            } else {
                ctx.drawLayer { c in
                    c.translateBy(x: x, y: y)
                    c.scaleBy(x: sc, y: sc)
                    let fa = (reached ? 1 : 0.7) * inA
                    var pole = Path()
                    pole.move(to: .zero)
                    pole.addLine(to: CGPoint(x: 0, y: -30))
                    c.stroke(pole, with: .color(.white.opacity(fa)), lineWidth: 1.8)
                    var flag = Path()
                    flag.move(to: CGPoint(x: 0, y: -30))
                    flag.addLine(to: CGPoint(x: 19, y: -23))
                    flag.addLine(to: CGPoint(x: 0, y: -16))
                    flag.closeSubpath()
                    c.fill(flag, with: .color(.white.opacity(reached ? 1 : 0.28 * inA)))
                    if !reached {
                        c.stroke(flag, with: .color(.white.opacity(0.7 * inA)), lineWidth: 1.2)
                    }
                }
            }
        }

        // Hiker pin rides the trail until the reveal takes over.
        if t < 1200 || cam.r < 1 {
            let q = cam.toScreen(tr.at(dist))
            let pa = timer ? 1 - cam.r : rhaEaseOut(rhaClamp((f.setupAge - 0.7) / 0.5))
            pin(&ctx, x: Double(q.x), y: Double(q.y), alpha: rhaClamp(pa))
        }
    }

    private static func pin(_ ctx: inout GraphicsContext, x: Double, y: Double, alpha: Double) {
        guard alpha > 0 else { return }
        ctx.drawLayer { c in
            c.translateBy(x: x, y: y)
            c.opacity = alpha
            c.stroke(
                Path(ellipseIn: CGRect(x: -10, y: -3.8, width: 20, height: 7.6)),
                with: .color(.white.opacity(0.55)), lineWidth: 1.2
            )
            var body = Path()
            body.move(to: .zero)
            body.addCurve(to: CGPoint(x: -8, y: -17), control1: CGPoint(x: -3, y: -7), control2: CGPoint(x: -8, y: -10))
            // Top semicircle as two cubic quarter arcs (avoids addArc's flipped clockwise flag).
            body.addCurve(to: CGPoint(x: 0, y: -25), control1: CGPoint(x: -8, y: -21.418), control2: CGPoint(x: -4.418, y: -25))
            body.addCurve(to: CGPoint(x: 8, y: -17), control1: CGPoint(x: 4.418, y: -25), control2: CGPoint(x: 8, y: -21.418))
            body.addCurve(to: .zero, control1: CGPoint(x: 8, y: -10), control2: CGPoint(x: 3, y: -7))
            body.closeSubpath()
            c.fill(body, with: .color(.white))
            c.fill(
                Path(ellipseIn: CGRect(x: -2.8, y: -19.8, width: 5.6, height: 5.6)),
                with: .color(Theme.logoBackdrop)
            )
        }
    }
}

// MARK: - Text pieces

/// The small label under the clock, rolling up at each change (500 ms settle, 300 ms fade in Reduce Motion).
private struct RHALabel: View {
    let cur: String
    let prev: String?
    let p: Double
    let rm: Bool

    private func line(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 22, weight: .semibold))
            .tracking(-0.22)
            .foregroundStyle(Color.white.opacity(0.64))
            .lineLimit(1)
            .fixedSize()
            .frame(height: 30, alignment: .leading)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let prev {
                line(prev)
                    .offset(y: rm ? 0 : -30 * p)
                    .opacity(1 - p)
            }
            line(cur)
                .offset(y: (rm || prev == nil) ? 0 : 30 * (1 - p))
                .opacity(prev == nil ? 1 : p)
        }
        .frame(width: 300, height: 30, alignment: .topLeading)
        .clipped()
    }
}

// MARK: - The look

struct RidgeAscentLook: View {
    let frame: HomeWorkoutFrame

    @State private var world: CGImage?

    var body: some View {
        let size = frame.size
        let sc = Double(size.width) / rhaW
        let yoff = (Double(size.height) - rhaH * sc) / 2

        ZStack(alignment: .topLeading) {
            Canvas { ctx, sz in
                RHADraw.scene(&ctx, size: sz, f: frame, world: world)
            }
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)

            if !(frame.isRunning && frame.runAge >= 0.45) {
                setupLayer(size: size)
            }
            if frame.isRunning {
                timerLayer(size: size, sc: sc, yoff: yoff)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .task { await loadWorld() }
    }

    private func loadWorld() async {
        if world != nil { return }
        let cg = await Task.detached(priority: .userInitiated) { RidgeAssets.shared.image(.worldDawn) }.value
        world = cg
    }

    // MARK: Setup copy

    /// One-time entrance: rises 22 pt and fades in on the settle curve, after a delay.
    private func enter(_ delay: Double) -> (opacity: Double, dy: Double) {
        let p = rhaSettle((frame.setupAge - delay) / 0.7)
        return (p, frame.reduceMotion ? 0 : 22 * (1 - p))
    }

    @ViewBuilder
    private func setupLayer(size: CGSize) -> some View {
        let rm = frame.reduceMotion
        let out = frame.isRunning ? rhaEaseIO(rhaClamp(frame.runAge / 0.2)) : 0
        let outY = (frame.isRunning && !rm) ? -14 * rhaSettle(frame.runAge / 0.3) : 0
        let facts = frame.facts
        let head = enter(0.45)
        let sub = enter(0.6)
        let hasStreak = facts.streakWeeks > 0

        ZStack(alignment: .topLeading) {
            // Headline.
            VStack(alignment: .leading, spacing: 0) {
                Text("climb").frame(height: 68)
                Text("to 20.").frame(height: 68)
            }
            .font(.system(size: 72, weight: .heavy))
            .tracking(-2.52)
            .foregroundStyle(Color.white.opacity(0.96))
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("climb to 20.")
            .opacity(head.opacity)
            .offset(x: 26, y: frame.safeTop + 30 + head.dy)

            // Sub line.
            Text(HomeWorkoutCopy.sub)
                .font(.system(size: 17))
                .foregroundStyle(Color.white.opacity(0.64))
                .frame(width: 340, alignment: .leading)
                .opacity(sub.opacity)
                .offset(x: 28, y: frame.safeTop + 184 + sub.dy)

            // Streak flame row, then the stake, check and quota lines, bottom aligned above the button.
            VStack(alignment: .leading, spacing: 9) {
                if hasStreak {
                    let e = enter(0.7)
                    HStack(spacing: 8) {
                        FlameFigure(visibleHeight: 20, isAnimating: !rm)
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text(HomeWorkoutCopy.streak(facts.streakWeeks))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.96))
                    }
                    .frame(height: 22, alignment: .leading)
                    .opacity(e.opacity)
                    .offset(y: e.dy)
                }
                infoLine(HomeWorkoutCopy.stake(facts), strong: true, delay: 0.7 + (hasStreak ? 0.09 : 0))
                infoLine(HomeWorkoutCopy.check(facts), strong: false, delay: 0.7 + (hasStreak ? 0.18 : 0.09))
                infoLine(HomeWorkoutCopy.quota(facts), strong: false, delay: 0.7 + (hasStreak ? 0.27 : 0.18))
            }
            .frame(width: size.width - 52, alignment: .leading)
            .padding(.leading, 28)
            .padding(.bottom, frame.safeBottom + HomeWorkoutLayout.bottomReserved)
            .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(1 - out)
        .offset(y: outY)
    }

    private func infoLine(_ s: String, strong: Bool, delay: Double) -> some View {
        let e = enter(delay)
        return Text(s)
            .font(.system(size: 15))
            .foregroundStyle(Color.white.opacity(strong ? 0.96 : 0.64))
            .frame(height: 20, alignment: .leading)
            .opacity(e.opacity)
            .offset(y: e.dy)
    }

    // MARK: Timer copy

    @ViewBuilder
    private func timerLayer(size: CGSize, sc: Double, yoff: Double) -> some View {
        let rm = frame.reduceMotion
        let e = frame.elapsed
        let gIn = rhaEaseIO(rhaClamp((frame.runAge - 0.15) / 0.42))
        let gY = rm ? 0 : 14 * (1 - rhaSettle((frame.runAge - 0.15) / 0.55))
        let roll = Self.roll(e, rm: rm)
        let pulse = rm ? 1 : 0.55 + 0.45 * abs(sin(frame.now * 2))
        let labelY = yoff + 334 * sc
        let dotY = yoff + 344 * sc

        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 9, height: 9)
                .opacity(pulse)
                .offset(x: 28, y: dotY)
                .accessibilityHidden(true)

            RHALabel(cur: roll.cur, prev: roll.prev, p: roll.p, rm: rm)
                .offset(x: 46, y: labelY)
                .accessibilityHidden(true)

            if let beat = frame.beat {
                beatText(beat, rm: rm)
                    .offset(x: 28, y: yoff + 384 * sc)
                    .accessibilityHidden(true)
            }

            // The clock is drawn in the canvas; this is its one accessibility element.
            Color.clear
                .frame(width: 312, height: 150)
                .offset(x: 28, y: yoff + 200 * sc)
                .accessibilityElement()
                .accessibilityLabel("workout time")
                .accessibilityValue("\(HomeWorkoutClock.format(e)), \(roll.cur)")
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(gIn)
        .offset(y: gY)
    }

    private static func roll(_ e: Double, rm: Bool) -> (cur: String, prev: String?, p: Double) {
        let cur = HomeWorkoutClock.label(e)
        let b = (e / 60).rounded(.down) * 60
        let dur = rm ? 0.3 : 0.5
        guard b > 0, e - b < dur else { return (cur, nil, 1) }
        let prev = HomeWorkoutClock.label(b - 0.001)
        guard prev != cur else { return (cur, nil, 1) }
        let x = (e - b) / dur
        return (cur, prev, rm ? x : rhaSettle(x))
    }

    /// Checkpoint slam: scales 1.3 to 1 on the settle curve, holds, then fades. "+5." is the soft, half size one.
    private func beatText(_ b: HomeWorkoutClock.Beat, rm: Bool) -> some View {
        let soft = b.checkpointIndex == nil
        let dur = soft ? 1.2 : (b.isTwenty ? 1.6 : 1.5)
        let hold = soft ? 0.75 : 0.8
        let u = b.age / dur
        let inEnd = 0.55 / dur
        var op = 0.0
        var scale = 1.0
        if u < 0 || u >= 1 {
            op = 0
        } else if rm {
            op = u < 0.25 ? u / 0.25 : (u < hold ? 1 : 1 - (u - hold) / (1 - hold))
        } else if u < inEnd {
            let q = rhaSettle(u / inEnd)
            op = q
            scale = 1.3 - 0.3 * q
        } else if u < hold {
            op = 1
        } else {
            op = 1 - (u - hold) / (1 - hold)
        }
        let fs: Double = soft ? 29 : 58
        return Text(b.text)
            .font(.system(size: fs, weight: .heavy))
            .tracking(-0.04 * fs)
            .foregroundStyle(Color.white.opacity(0.96))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: 334, height: fs, alignment: .leading)
            .scaleEffect(scale, anchor: .leading)
            .opacity(op)
    }
}
