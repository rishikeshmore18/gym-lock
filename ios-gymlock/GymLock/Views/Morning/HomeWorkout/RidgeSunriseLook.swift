//
//  RidgeSunriseLook.swift
//  GymLock · home workout look "Ridge B, first light"
//
//  A 20 minute sunrise over the painted ridge. The night overlay lifts, the stars fade, and a
//  coral sun climbs from behind the skyline with the giant clock rising beside it (both clipped
//  by the ridge, so they come up from behind it). Each checkpoint drops a light ring on the sun,
//  20:00 fans rays and leaves a soft halo, and the last 60 s before any moment swell the glow.
//  Setup is deep night with "bring the sun up." and the streak flame as the only coral.
//
//  Approved prototype: docs/prototypes/home-workout-variations.html (ridge b, first light)
//

import SwiftUI

struct RidgeSunriseLook: View {
    let frame: HomeWorkoutFrame

    @State private var world: CGImage?

    var body: some View {
        let size = frame.size
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                RSUDraw.scene(&ctx, frame: frame, world: world)
            }
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)

            RSUSetupLayer(frame: frame)

            if frame.isRunning {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("workout time")
                    .accessibilityValue("\(HomeWorkoutClock.format(frame.elapsed)), \(HomeWorkoutClock.label(frame.elapsed))")
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .task { await loadWorld() }
    }

    // Decoded once off the main thread; the same baked world the other Ridge screens use.
    private func loadWorld() async {
        if world != nil { return }
        let cg = await Task.detached(priority: .userInitiated) { RidgeAssets.shared.image(.worldDawn) }.value
        world = cg
    }
}

// MARK: - Maths

private func rsuClamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { max(lo, min(hi, x)) }
private func rsuLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func rsuEaseOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
private func rsuEaseIO(_ x: Double) -> Double { x * x * (3 - 2 * x) }

/// cubic-bezier(.22, .9, .24, 1), the app's settle curve (UI-RULES), solved by bisection.
private func rsuSettle(_ x: Double) -> Double {
    let x = rsuClamp(x)
    func bez(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }
    var lo = 0.0, hi = 1.0
    for _ in 0..<24 {
        let mid = (lo + hi) / 2
        if bez(mid, 0.22, 0.24) < x { lo = mid } else { hi = mid }
    }
    return bez((lo + hi) / 2, 0.9, 1)
}

// MARK: - Constants

private struct RSUStar {
    let x: Double, y: Double, r: Double, a: Double, d: Double
}

/// 60 stars from the prototype's seeded generator, so the sky matches the approved shots.
private let rsuStars: [RSUStar] = {
    var s: Double = 19
    func rnd() -> Double {
        s = (s * 16807).truncatingRemainder(dividingBy: 2147483647)
        return s / 2147483647
    }
    var out: [RSUStar] = []
    for _ in 0..<60 {
        let x = 10 + rnd() * 370, y = 20 + rnd() * 420, r = 0.7 + rnd() * 1.2
        let a = 0.45 + rnd() * 0.55, d = rnd()
        out.append(RSUStar(x: x, y: y, r: r, a: a, d: d))
    }
    return out
}()

private let rsuNight = Color(red: 5 / 255, green: 8 / 255, blue: 22 / 255)
// Sunlight tints from the prototype. Not in Theme because they only exist on this scene.
private let rsuWarm = Color(red: 255 / 255, green: 236 / 255, blue: 214 / 255)
private let rsuWarmHi = Color(red: 255 / 255, green: 240 / 255, blue: 222 / 255)
private let rsuRing = Color(red: 255 / 255, green: 244 / 255, blue: 230 / 255)

// MARK: - Scene

private enum RSUDraw {
    static func scene(_ ctx: inout GraphicsContext, frame f: HomeWorkoutFrame, world: CGImage?) {
        let size = f.size
        let full = CGRect(origin: .zero, size: size)
        let rm = f.reduceMotion
        let running = f.isRunning
        let t = running ? max(0, f.elapsed) : 0
        let mp = running ? rsuEaseIO(rsuClamp(f.runAge / (rm ? 0.2 : 0.95))) : 0

        let fit = HomeWorkoutRidge.Fit(size: size)
        let apex = fit.point(HomeWorkoutRidge.apex)
        let sunX = apex.x

        let p = min(t / 1200, 1)
        let e = 1 - pow(1 - p, 1.5)

        // World + night overlay
        ctx.fill(Path(full), with: .color(Theme.logoBackdrop))
        if let world {
            let img = ctx.resolve(Image(decorative: world, scale: 1).interpolation(.medium))
            let r = CGRect(x: fit.ox, y: fit.oy,
                           width: HomeWorkoutRidge.worldW * fit.k, height: HomeWorkoutRidge.worldH * fit.k)
            ctx.draw(img, in: r)
        }
        ctx.fill(Path(full), with: .color(rsuNight.opacity(0.75 * pow(1 - p, 1.3))))

        // Vertical anchors are apex-relative so they hold on any screen height (390x844: apex y 464.5).
        let ce = 1 - pow(1 - p, 1.8)
        let cb0 = rsuLerp(Double(apex.y) + 120.5, Double(apex.y) - 250.5, ce)
        let sy = max(rsuLerp(Double(apex.y) + 75.5, Double(apex.y) - 64.5, e), cb0 + 70)
        let sun = CGPoint(x: sunX, y: sy)

        let dt3 = (running && t >= 1200) ? t - 1200 : -1
        let spurt = running ? HomeWorkoutClock.spurt(t) : 0

        ctx.drawLayer { s in
            // Everything here is behind the ridge
            if HomeWorkoutRidge.skyline.count == 91 {
                let xf = CGAffineTransform(translationX: fit.ox, y: fit.oy).scaledBy(x: fit.k, y: fit.k)
                s.clip(to: HomeWorkoutRidge.skyPath().applying(xf))
            }

            glow(&s, size: size, sun: sun, e: e, mp: mp, spurt: spurt, dt3: dt3, rm: rm)
            stars(&s, f: f, t: t, mp: mp)

            if t >= 1200 { halo(&s, size: size, sun: sun) }
            if dt3 >= 0 && dt3 < 1.5 { rays(&s, size: size, sun: sun, dt3: dt3, rm: rm) }

            // Rings at 5, 10, 15
            if let b = f.beat, let i = b.checkpointIndex, i < 3 {
                let d = b.age / 0.9
                if d >= 0 && d < 1 {
                    let k = rm ? 1 : 1 + 1.2 * rsuEaseOut(d)
                    let r = 26 * k
                    let ring = Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2))
                    s.stroke(ring, with: .color(rsuRing.opacity(0.5 * (1 - d))), lineWidth: 2.5)
                }
            }

            // The sun. Hidden on setup, where the flame is the coral element.
            if running {
                let sp = Path(ellipseIn: CGRect(x: sun.x - 26, y: sun.y - 26, width: 52, height: 52))
                s.fill(sp, with: .color(Theme.accent))
            }

            // The clock rises with the sun
            if mp > 0 {
                let cb = cb0 + (1 - mp) * (rm ? 0 : 70)
                clock(&s, str: HomeWorkoutClock.format(t), cx: size.width / 2, baseline: cb,
                      alpha: rm ? mp : min(1, mp * 1.6) * 0.97)
            }
        }

        // Soft shade under the buttons
        let shadeTop = size.height - 244
        ctx.fill(Path(CGRect(x: 0, y: shadeTop, width: size.width, height: size.height - shadeTop)),
                 with: .linearGradient(Gradient(colors: [rsuNight.opacity(0), rsuNight.opacity(0.6)]),
                                       startPoint: CGPoint(x: 0, y: shadeTop),
                                       endPoint: CGPoint(x: 0, y: size.height)))

        // Label and beat follow the clock baseline (in the prototype they are DOM)
        if running {
            let cb = cb0 + (1 - mp) * (rm ? 0 : 70)
            let gIn = rsuClamp((f.runAge - 0.15) / 0.42)
            let lift = rm ? 0 : 14 * (1 - rsuSettle(rsuClamp((f.runAge - 0.15) / 0.55)))
            var g = ctx
            g.translateBy(x: 0, y: lift)
            g.opacity = gIn
            label(&g, f: f, t: t, top: (cb + 16).rounded(), width: size.width)
            if let b = f.beat { beat(&g, b: b, top: (cb + 16).rounded() + 44, width: size.width, rm: rm) }
        }
    }

    // MARK: Glow, stars, halo, rays

    static func glow(_ s: inout GraphicsContext, size: CGSize, sun: CGPoint, e: Double, mp: Double,
                     spurt: Double, dt3: Double, rm: Bool) {
        let ga = (0.2 + 0.8 * e) * rsuLerp(0.55, 1, mp)
        var r = 150 + 150 * e + spurt * 70
        if dt3 >= 0 && dt3 < 1.5 && !rm { r += 90 * sin(Double.pi * rsuClamp(dt3 / 1.5)) }
        let grad = Gradient(stops: [
            .init(color: rsuWarm.opacity(0.55 * ga), location: 0),
            .init(color: rsuWarm.opacity(0.2 * ga), location: 0.3),
            .init(color: Theme.accent.opacity(0.09 * ga), location: 0.6),
            .init(color: Theme.accent.opacity(0), location: 1),
        ])
        s.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(grad, center: sun, startRadius: 0, endRadius: r))
    }

    static func stars(_ s: inout GraphicsContext, f: HomeWorkoutFrame, t: Double, mp: Double) {
        let dx = (f.size.width - 390) / 2
        let setup = !f.isRunning
        for st in rsuStars {
            var a = st.a
            if setup {
                a *= rsuEaseOut(rsuClamp((f.setupAge * 1000 - 80 - st.d * 600) / 450))
            } else {
                a *= rsuClamp(1 - t / 600)
            }
            if a <= 0.01 { continue }
            let r = st.r
            s.fill(Path(ellipseIn: CGRect(x: st.x + dx - r, y: st.y - r, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(a)))
        }
    }

    static func halo(_ s: inout GraphicsContext, size: CGSize, sun: CGPoint) {
        let grad = Gradient(colors: [rsuWarmHi.opacity(0.2), rsuWarmHi.opacity(0)])
        s.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(grad, center: sun, startRadius: 10, endRadius: 230))
    }

    static func rays(_ s: inout GraphicsContext, size: CGSize, sun: CGPoint, dt3: Double, rm: Bool) {
        let env = 0.2 * sin(Double.pi * rsuClamp(dt3 / 1.5)) * (rm ? 0.6 : 1)
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [rsuWarmHi.opacity(env), rsuWarmHi.opacity(0)]),
            center: sun, startRadius: 20, endRadius: 460)
        for i in 0..<12 {
            let ang = -Double.pi * (0.04 + 0.92 * Double(i) / 11)
            let w = 0.06 + Double(i % 2) * 0.03
            var path = Path()
            path.move(to: sun)
            path.addLine(to: CGPoint(x: sun.x + cos(ang - w) * 480, y: sun.y + sin(ang - w) * 480))
            path.addLine(to: CGPoint(x: sun.x + cos(ang + w) * 480, y: sun.y + sin(ang + w) * 480))
            path.closeSubpath()
            s.fill(path, with: shading)
        }
    }

    // MARK: Clock

    /// Digits on a fixed pitch (colon at 0.9 of a digit-width glyph) like the prototype's drawClock,
    /// so the clock never jiggles as digits change. Fits 330 pt wide at 124 pt.
    static func clock(_ s: inout GraphicsContext, str: String, cx: CGFloat, baseline: Double,
                      alpha: Double) {
        func resolved(_ ch: String, _ fs: CGFloat) -> GraphicsContext.ResolvedText {
            s.resolve(Text(ch).font(.system(size: fs, weight: .heavy)).monospacedDigit())
        }
        let probe = CGSize(width: 1000, height: 1000)
        var fs: CGFloat = 124
        var dw = resolved("0", fs).measure(in: probe).width
        var cw = resolved(":", fs).measure(in: probe).width * 0.9
        let tot = 4 * dw + cw
        if tot > 330 {
            fs = fs * 330 / tot
            dw = resolved("0", fs).measure(in: probe).width
            cw = resolved(":", fs).measure(in: probe).width * 0.9
        }
        var total: CGFloat = 0
        for ch in str { total += ch == ":" ? cw : dw }
        var x = cx - total / 2
        for ch in str {
            let w = ch == ":" ? cw : dw
            var r = resolved(String(ch), fs)
            r.shading = .color(.white.opacity(alpha))
            let base = r.firstBaseline(in: probe)
            s.draw(r, at: CGPoint(x: x + w / 2, y: baseline - Double(base)), anchor: .top)
            x += w
        }
    }

    // MARK: Label (rolls on each new minute) and beat

    static func label(_ s: inout GraphicsContext, f: HomeWorkoutFrame, t: Double, top: Double, width: CGFloat) {
        let font = Font.system(size: 22, weight: .semibold)
        func draw(_ txt: String, dy: Double, alpha: Double, _ c: inout GraphicsContext) {
            if alpha <= 0.002 { return }
            var r = c.resolve(Text(txt).font(font).tracking(-0.22))
            r.shading = .color(.white.opacity(0.64 * alpha))
            c.draw(r, at: CGPoint(x: width / 2, y: top + 15 + dy), anchor: .center)
        }
        let now = HomeWorkoutClock.label(t)
        // The text changes on every minute edge, so the roll is a pure function of time.
        let edge = (t / 60).rounded(.down) * 60
        let age = t - edge
        let dur = f.reduceMotion ? 0.3 : 0.5
        s.drawLayer { c in
            c.clip(to: Path(CGRect(x: 0, y: top, width: width, height: 30)))
            if edge > 0 && age < dur {
                let old = HomeWorkoutClock.label(edge - 0.01)
                if f.reduceMotion {
                    let k = age / dur
                    draw(old, dy: 0, alpha: 1 - k, &c)
                    draw(now, dy: 0, alpha: k, &c)
                } else {
                    let k = rsuSettle(age / dur)
                    draw(old, dy: -30 * k, alpha: 1 - k, &c)
                    draw(now, dy: 30 * (1 - k), alpha: k, &c)
                }
            } else {
                draw(now, dy: 0, alpha: 1, &c)
            }
        }
    }

    static func beat(_ s: inout GraphicsContext, b: HomeWorkoutClock.Beat, top: Double, width: CGFloat, rm: Bool) {
        let soft = b.checkpointIndex == nil
        let dur = soft ? 1.2 : 1.6
        let hold = soft ? 0.75 : 0.8
        let a = b.age
        if a >= dur { return }
        let inEnd = 0.55 / dur
        let k = a / dur
        var alpha: Double
        var scale = 1.0
        if rm {
            if k < 0.25 { alpha = k / 0.25 } else if k < hold { alpha = 1 } else { alpha = 1 - (k - hold) / (1 - hold) }
        } else {
            if k < inEnd {
                let q = rsuSettle(k / inEnd)
                alpha = q
                scale = 1.3 - 0.3 * q
            } else if k < hold {
                alpha = 1
            } else {
                alpha = 1 - (k - hold) / (1 - hold)
            }
        }
        if alpha <= 0.002 { return }

        // Shrink to fit 334 pt, like the prototype
        var fs: CGFloat = soft ? 28 : 56
        func make(_ size: CGFloat) -> Text {
            Text(b.text).font(.system(size: size, weight: .heavy)).tracking(-0.04 * size)
        }
        let probe = CGSize(width: 2000, height: 200)
        let w0 = s.resolve(make(fs)).measure(in: probe).width
        if w0 > 334 { fs = fs * 334 / w0 }
        var r = s.resolve(make(fs))
        r.shading = .color(.white.opacity(0.96 * alpha))

        var c = s
        c.translateBy(x: width / 2, y: top + Double(fs) / 2)
        c.scaleBy(x: scale, y: scale)
        c.draw(r, at: .zero, anchor: .center)
    }
}

// MARK: - Setup copy (SwiftUI text; the flame is the app's real one)

private struct RSUSetupLayer: View {
    let frame: HomeWorkoutFrame

    var body: some View {
        let f = frame
        // The group leaves up and out when start is tapped (200 ms fade, 300 ms rise)
        let out = f.isRunning ? rsuClamp(f.runAge / 0.2) : 0
        if out < 1 {
            let size = f.size
            let dy = max(0, f.safeTop - 54)
            let rise = f.reduceMotion ? 0 : -14 * rsuSettle(rsuClamp(f.runAge / 0.3))
            let infoTop = 586 + (size.height - 844)
            let facts = f.facts

            ZStack(alignment: .topLeading) {
                // Headline
                entrance(450) {
                    VStack(spacing: 0) {
                        headline("bring the")
                        headline("sun up.")
                    }
                    .frame(width: size.width)
                }
                .position(x: size.width / 2, y: 112 + dy + 66)

                // Sub
                entrance(600) {
                    VStack(spacing: 0) {
                        ForEach(Array(subLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 17))
                                .foregroundStyle(.white.opacity(0.64))
                                .frame(height: 22)
                        }
                    }
                    .frame(width: size.width)
                }
                .position(x: size.width / 2, y: 262 + dy + 22)

                // Streak, stake, check, quota
                VStack(spacing: 9) {
                    if facts.streakWeeks > 0 {
                        entrance(700) {
                            HStack(spacing: 8) {
                                FlameFigure(visibleHeight: 20, isAnimating: !f.reduceMotion)
                                Text(HomeWorkoutCopy.streak(facts.streakWeeks))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.96))
                            }
                            .frame(height: 22)
                        }
                    }
                    row(HomeWorkoutCopy.stake(facts), 0.96, delay: facts.streakWeeks > 0 ? 790 : 700)
                    row(HomeWorkoutCopy.check(facts), 0.64, delay: facts.streakWeeks > 0 ? 880 : 790)
                    row(HomeWorkoutCopy.quota(facts), 0.64, delay: facts.streakWeeks > 0 ? 970 : 880)
                }
                .frame(width: size.width)
                .position(x: size.width / 2, y: infoTop + (facts.streakWeeks > 0 ? 109 : 78) / 2)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .opacity(1 - out)
            .offset(y: rise)
            .allowsHitTesting(false)
        }
    }

    private var subLines: [String] {
        let s = HomeWorkoutCopy.sub
        if let r = s.range(of: ". ") {
            return [String(s[..<r.upperBound]).trimmingCharacters(in: .whitespaces), String(s[r.upperBound...])]
        }
        return [s]
    }

    private func headline(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 68, weight: .heavy))
            .tracking(-0.035 * 68)
            .foregroundStyle(.white.opacity(0.96))
            .frame(height: 66)
    }

    private func row(_ s: String, _ a: Double, delay: Double) -> some View {
        entrance(delay) {
            Text(s)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(a))
                .frame(height: 20)
        }
    }

    /// One-time entrance: rise 22 pt and fade over 700 ms on the settle curve, staggered by `delay` ms.
    private func entrance<Content: View>(_ delay: Double, @ViewBuilder _ content: () -> Content) -> some View {
        let p = rsuClamp((frame.setupAge * 1000 - delay) / 700)
        let k = rsuSettle(p)
        return content()
            .opacity(frame.reduceMotion ? p : k)
            .offset(y: frame.reduceMotion ? 0 : 22 * (1 - k))
    }
}
