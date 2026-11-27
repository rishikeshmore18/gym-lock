//
//  MatrixStackLook.swift
//  GymLock · home workout look "Matrix B, the stack"
//
//  A light screen. The week is seven towers of dots. Every minute one floor (5x1 dots) drops onto
//  today's tower with gravity and a small bounce; at 20 the goal line snaps solid, the towers
//  ripple, and the big week result takes the clock's place for 2.5 s. One coral element only:
//  the hovering "charging" block that fills one dot per 12 s.
//
//  Everything is a pure function of the frame (no integrated physics): a drop is derived from the
//  time since its minute began, so a resumed app lands on the right frame.
//
//  Approved prototype: docs/prototypes/home-workout-variations.html
//

import SwiftUI

// MARK: - Geometry (card space, same numbers as the prototype)

private enum MSTG {
    static let w: Double = 334
    static let h: Double = 392
    static let rowPitch: Double = 10.2
    static let dotPitch: Double = 8
    static let base: Double = 352
    static let hover: Double = 22
    static let goalY: Double = base - 20 * rowPitch
    static let visualCap = 30

    static func cx(_ d: Int) -> Double { 31 + Double(d) * ((w - 24 - 38) / 6) }
    static func fy(_ f: Int) -> Double { base - (Double(f) - 0.5) * rowPitch }
}

// MARK: - Small maths

private func mstClamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { max(a, min(b, x)) }
private func mstEaseOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

/// CSS cubic-bezier(x1, y1, x2, y2) evaluated at time fraction t (bisection on x).
private func mstBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
    let t = mstClamp(t)
    if t == 0 || t == 1 { return t }
    func curve(_ a: Double, _ b: Double, _ s: Double) -> Double {
        let m = 1 - s
        return 3 * m * m * s * a + 3 * m * s * s * b + s * s * s
    }
    var lo = 0.0, hi = 1.0
    for _ in 0..<24 {
        let mid = (lo + hi) / 2
        if curve(x1, x2, mid) < t { lo = mid } else { hi = mid }
    }
    return curve(y1, y2, (lo + hi) / 2)
}

/// The app's settle curve (0.22, 0.9, 0.24, 1).
private func mstSettle(_ t: Double) -> Double { mstBezier(0.22, 0.9, 0.24, 1, t) }

/// y of a dropping floor `age` seconds after its minute began, nil once it has come to rest.
/// Gravity 2600, bounce keeps 30% of the speed, stops below 170 (prototype numbers).
private func mstDropY(age: Double, target: Double) -> Double? {
    guard age >= 0 else { return MSTG.hover }
    let g = 2600.0
    let fall = max(0, target - MSTG.hover)
    let t1 = (2 * fall / g).squareRoot()
    if age < t1 { return MSTG.hover + 0.5 * g * age * age }
    var a = age - t1
    var v = g * t1
    for _ in 0..<6 {
        guard v > 170 else { return nil }
        let u = 0.3 * v
        let dur = 2 * u / g
        if a < dur { return target - (u * a - 0.5 * g * a * a) }
        a -= dur
        v = u
    }
    return nil
}

private func mstRow(_ p: inout Path, _ cx: Double, _ y: Double, _ r: Double) {
    for c in 0..<5 {
        let x = cx - 16 + Double(c) * MSTG.dotPitch
        p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
}

// MARK: - Card art

private enum MSTArt {
    static func draw(_ ctx: inout GraphicsContext, f: HomeWorkoutFrame) {
        let e = f.elapsed
        let running = f.isRunning
        let rm = f.reduceMotion
        let m = running ? min(Int(e / 60), MSTG.visualCap) : 0
        let done = running && e >= HomeWorkoutClock.minimum
        let dtp = e - HomeWorkoutClock.minimum
        let spurt = running ? HomeWorkoutClock.spurt(e) : 0

        drawLines(&ctx, e: e, running: running, spurt: spurt, done: done, dtp: dtp)

        // The floor that is falling right now (not part of the standing stack).
        var dropY: Double?
        if running, !rm, m >= 1, m < 31 {
            dropY = mstDropY(age: e - Double(m) * 60, target: MSTG.fy(m))
        }

        let week = f.facts.week
        let todayX = MSTG.cx(f.facts.todayIndex ?? 3)
        for d in 0..<min(7, week.count) {
            drawTower(&ctx, f: f, d: d, state: week[d].state, letter: week[d].letter,
                      m: m, dropping: dropY != nil, done: done, dtp: dtp)
        }

        if let y = dropY {
            var p = Path()
            mstRow(&p, todayX, y, 3.2)
            ctx.fill(p, with: .color(Theme.ink))
        }

        if running, m < MSTG.visualCap {
            drawHover(&ctx, x: todayX, e: e, rm: rm, spurt: spurt)
        }
    }

    // Checkpoint lines and the goal line.
    private static func drawLines(_ ctx: inout GraphicsContext, e: Double, running: Bool,
                                  spurt: Double, done: Bool, dtp: Double) {
        let cps = HomeWorkoutClock.checkpoints
        var pulseFor = -1
        var pu = 0.0
        if running, e < 1200, spurt > 0, let nk = cps.firstIndex(where: { $0 > e }) {
            pulseFor = nk
            pu = max(0, 1 - (e - (cps[nk] - 60)) / 0.7)
        }
        for k in 0..<3 {
            let y = MSTG.base - Double(k + 1) * 5 * MSTG.rowPitch
            var a = 0.09
            if pulseFor == k { a += 0.5 * pu }
            var p = Path()
            p.move(to: CGPoint(x: 12, y: y))
            p.addLine(to: CGPoint(x: MSTG.w - 12, y: y))
            ctx.stroke(p, with: .color(Theme.ink.opacity(a)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        }
        var a = 0.32
        var lw = 1.2
        var dash: [CGFloat] = [5, 4]
        if pulseFor == 3 { a += 0.5 * pu }
        if done {
            dash = []
            a = 0.9
            lw = 1.6
            if dtp >= 0, dtp < 0.45 { lw = 1.6 + 2.4 * (1 - dtp / 0.45) }
        }
        var g = Path()
        g.move(to: CGPoint(x: 12, y: MSTG.goalY))
        g.addLine(to: CGPoint(x: MSTG.w - 12, y: MSTG.goalY))
        ctx.stroke(g, with: .color(Theme.ink.opacity(a)), style: StrokeStyle(lineWidth: lw, dash: dash))
        ctx.draw(Text("20").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.inkTertiary),
                 at: CGPoint(x: MSTG.w - 12, y: MSTG.goalY - 4), anchor: .bottomTrailing)
    }

    private static func drawTower(_ ctx: inout GraphicsContext, f: HomeWorkoutFrame, d: Int,
                                  state: PauseWeekDay.State, letter: String, m: Int,
                                  dropping: Bool, done: Bool, dtp: Double) {
        let cx = MSTG.cx(d)
        let e = f.elapsed
        let running = f.isRunning
        let rm = f.reduceMotion
        let isToday = state == .today
        let full = state == .done
        let ghosted = state == .planned || isToday

        // Entrance: towers rise in a stagger on setup; reduce motion fades them.
        let ms = f.setupAge * 1000
        let ent: Double
        if running { ent = 1 }
        else if rm { ent = mstClamp(f.setupAge / 0.5) }
        else { ent = mstEaseOut(mstClamp((ms - 150 - Double(d) * 90) / 700)) }

        // Goal ripple: a damped bounce, staggered by 40 ms per day.
        var off = 0.0
        if done, !rm, dtp >= 0 {
            let tau = dtp - Double(d) * 0.04
            if tau > 0 { off = -7 * exp(-5 * tau) * sin(22 * tau) }
        }

        if !full && !ghosted {
            let r = CGRect(x: cx - 8, y: MSTG.base - 4, width: 16, height: 2.5)
            ctx.fill(Path(r), with: .color(Theme.inkTertiary.opacity(0.7 * ent)))
        } else {
            if !full {
                var ga = 0.13 * ent
                if isToday, !running, !rm {
                    let s = (ms - 1000) / 500
                    ga = s < 0 ? 0 : (s < 1 ? (Int(s * 5) % 2 == 0 ? 0.5 : 0.13) : 0.13)
                }
                var p = Path()
                for fl in 1...20 {
                    let y = MSTG.fy(fl) + off
                    if fl == 1 || fl == 20 { mstRow(&p, cx, y, 2.3) }
                    else {
                        for c in [0, 4] {
                            let x = cx - 16 + Double(c) * MSTG.dotPitch
                            p.addEllipse(in: CGRect(x: x - 2.3, y: y - 2.3, width: 4.6, height: 4.6))
                        }
                    }
                }
                ctx.fill(p, with: .color(Theme.ink.opacity(ga)))
            }
            let nF = full ? Int((20 * ent).rounded(.up)) : (isToday ? m : 0)
            if nF > 0 {
                var p = Path()
                let cps = HomeWorkoutClock.checkpoints
                for fl in 1...nF {
                    if isToday, dropping, fl == m { continue }
                    var r = 3.2
                    if isToday, running {
                        for k in 0..<4 where Double(fl) <= cps[k] / 60 {
                            let l = (e - cps[k]) - Double(fl) * 0.012
                            if l > 0, l < 0.4 { r += 1.5 * sin(Double.pi * l / 0.4) }
                        }
                    }
                    mstRow(&p, cx, MSTG.fy(fl) + off, r)
                }
                ctx.fill(p, with: .color(Theme.ink))
            }
        }

        ctx.draw(Text(letter)
                    .font(.system(size: 12, weight: isToday ? .bold : .semibold))
                    .foregroundColor(isToday ? Theme.ink : Theme.inkTertiary),
                 at: CGPoint(x: cx, y: 377), anchor: .bottom)
    }

    // The hovering charging block: the one coral element.
    private static func drawHover(_ ctx: inout GraphicsContext, x tcx: Double, e: Double,
                                  rm: Bool, spurt: Double) {
        let sec = e.truncatingRemainder(dividingBy: 60)
        let ha = mstClamp(sec / 0.35)
        for i in 0..<5 {
            let fill = mstClamp((sec - Double(i) * 12) / 12)
            let x = tcx - 16 + Double(i) * MSTG.dotPitch
            var r = 4.2 * (1 + 0.16 * spurt)
            if spurt > 0, fill >= 1 {
                let since = sec - Double(i + 1) * 12
                if since >= 0, since < 0.45 { r += 1.8 * spurt * (1 - since / 0.45) }
            }
            let y = MSTG.hover + (rm ? 0 : (1 - ha) * -10)
            let alpha = (0.2 + 0.8 * fill) * ha
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Theme.accent.opacity(alpha)))
        }
    }
}

// MARK: - Rolling text slot

/// Clips its content to a fixed-height window and offsets / fades it like the prototype's roll.
private struct MSTSlot<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let yFraction: Double
    let opacity: Double
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: width, height: height, alignment: .leading)
            .offset(y: height * yFraction)
            .opacity(opacity)
    }
}

// MARK: - Look

struct MatrixStackLook: View {
    let frame: HomeWorkoutFrame

    private var side: CGFloat { HomeWorkoutLayout.margin }
    private var boxW: CGFloat { frame.size.width - 2 * side }

    var body: some View {
        let size = frame.size
        ZStack(alignment: .topLeading) {
            Theme.canvas

            Group {
                if showSetup { setupGroup }
                if frame.isRunning { timerGroup }
                card
            }
            .accessibilityHidden(true)

            if frame.isRunning {
                Color.clear
                    .frame(width: boxW, height: 112 + 30)
                    .offset(x: side, y: frame.safeTop + 44)
                    .accessibilityElement()
                    .accessibilityLabel("workout time")
                    .accessibilityValue("\(HomeWorkoutClock.format(frame.elapsed)), \(HomeWorkoutClock.label(frame.elapsed))")
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var showSetup: Bool { !frame.isRunning || frame.runAge < 0.5 }

    // MARK: Card

    private var cardGeometry: (s: Double, top: CGFloat, h: CGFloat) {
        let bottom = frame.size.height - frame.safeBottom - HomeWorkoutLayout.bottomReserved
        let limit = frame.safeTop + 252
        let s = max(0.6, min(1, Double(bottom - limit) / MSTG.h))
        let h = CGFloat(MSTG.h * s)
        return (s, bottom - h, h)
    }

    private var card: some View {
        let g = cardGeometry
        let w = boxW
        let dx = (Double(w) / g.s - MSTG.w) / 2
        let f = frame
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.05), radius: 9, x: 0, y: 6)
            Canvas { ctx, _ in
                ctx.scaleBy(x: g.s, y: g.s)
                ctx.translateBy(x: dx, y: 0)
                MSTArt.draw(&ctx, f: f)
            }
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(width: w, height: g.h)
        .offset(x: side, y: g.top)
    }

    // MARK: Setup

    /// Entrance: rises 22 pt and fades over 0.7 s after `delay` ms. Reduce motion: fade only.
    private func entrance(_ delay: Double) -> (y: CGFloat, o: Double) {
        let p = mstSettle(mstClamp((frame.setupAge * 1000 - delay) / 700))
        return (frame.reduceMotion ? 0 : CGFloat(22 * (1 - p)), p)
    }

    private var setupGroup: some View {
        let ra = frame.runAge
        let out = frame.isRunning ? 1 - mstClamp(ra / 0.2) : 1
        let lift: CGFloat = frame.reduceMotion ? 0 : CGFloat(-14 * mstClamp(ra / 0.3))
        let f = frame.facts
        let head = entrance(300)
        let sub = entrance(420)
        var rows: [(text: String, strong: Bool, delay: Double)] = []
        var i = 0.0
        let hasStreak = f.streakWeeks > 0
        if hasStreak { i += 1 }
        rows.append((HomeWorkoutCopy.stake(f), true, 1250 + i * 90)); i += 1
        rows.append((HomeWorkoutCopy.check(f), false, 1250 + i * 90)); i += 1
        rows.append((HomeWorkoutCopy.quota(f), false, 1250 + i * 90))
        let lines = rows
        let streakE = entrance(1250)

        return ZStack(alignment: .topLeading) {
            Text("build today.")
                .font(.system(size: 44, weight: .heavy))
                .tracking(-1.54)
                .foregroundColor(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: boxW, height: 48, alignment: .leading)
                .offset(x: side, y: frame.safeTop + 34 + head.y)
                .opacity(head.o)

            Text(HomeWorkoutCopy.sub)
                .font(.system(size: 17))
                .foregroundColor(Theme.inkSecondary)
                .frame(width: boxW, height: 22, alignment: .leading)
                .offset(x: side, y: frame.safeTop + 94 + sub.y)
                .opacity(sub.o)

            VStack(alignment: .leading, spacing: 7) {
                if hasStreak {
                    HStack(spacing: 8) {
                        FlameFigure(visibleHeight: 20, isAnimating: !frame.reduceMotion)
                        Text(HomeWorkoutCopy.streak(f.streakWeeks))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Theme.ink)
                    }
                    .frame(height: 22, alignment: .leading)
                    .offset(y: streakE.y)
                    .opacity(streakE.o)
                }
                ForEach(0..<lines.count, id: \.self) { n in
                    let r = lines[n]
                    let en = entrance(r.delay)
                    Text(r.text)
                        .font(.system(size: 15))
                        .foregroundColor(r.strong ? Theme.ink : Theme.inkSecondary)
                        .frame(height: 20, alignment: .leading)
                        .offset(y: en.y)
                        .opacity(en.o)
                }
            }
            .frame(width: boxW, alignment: .leading)
            .offset(x: side, y: frame.safeTop + 134)
        }
        .offset(y: lift)
        .opacity(out)
    }

    // MARK: Timer

    private var timerGroup: some View {
        let ra = frame.runAge
        let p = mstClamp((ra - 0.15) / 0.55)
        let o = mstSettle(mstClamp((ra - 0.15) / 0.42))
        let lift: CGFloat = frame.reduceMotion ? 0 : CGFloat(14 * (1 - mstSettle(p)))
        return ZStack(alignment: .topLeading) {
            clockBlock
            labelBlock
            beatBlock
        }
        .offset(y: lift)
        .opacity(o)
    }

    // Big clock, swapped for the week result during the 20:00 moment.
    private var clockBlock: some View {
        let e = frame.elapsed
        let rm = frame.reduceMotion
        let dur = HomeWorkoutClock.bigMomentDuration
        // (clock y, clock opacity, result y, result opacity), y as a fraction of the box height.
        var ck: (y: Double, o: Double) = (0, 1)
        var rs: (y: Double, o: Double) = (1, 0)
        if frame.isDone {
            let into = e - HomeWorkoutClock.minimum
            if into < dur {
                let a = rm ? mstClamp(into / 0.3) : mstSettle(mstClamp(into / 0.55))
                ck = (rm ? 0 : -a, 1 - a)
                rs = (rm ? 0 : 1 - a, a)
            } else {
                let b = rm ? mstClamp((into - dur) / 0.3) : mstSettle(mstClamp((into - dur) / 0.55))
                ck = (rm ? 0 : 1 - b, b)
                rs = (rm ? 0 : -b, 1 - b)
            }
        }
        let h: CGFloat = 112
        return ZStack(alignment: .topLeading) {
            MSTSlot(width: boxW, height: h, yFraction: ck.y, opacity: ck.o) {
                Text(HomeWorkoutClock.format(e))
                    .font(.system(size: 112, weight: .heavy))
                    .monospacedDigit()
                    .tracking(-5.04)
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            MSTSlot(width: boxW, height: h, yFraction: rs.y, opacity: rs.o) {
                Text(HomeWorkoutCopy.weekResult(frame.facts))
                    .font(.system(size: 68, weight: .heavy))
                    .tracking(-2.72)
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: boxW, height: h, alignment: .topLeading)
        .clipped()
        .offset(x: side, y: frame.safeTop + 44)
    }

    // Small label under the clock; rolls when the text changes (always on a whole minute).
    private var labelBlock: some View {
        let e = frame.elapsed
        let rm = frame.reduceMotion
        let minute = (e / 60).rounded(.down)
        let age = e - minute * 60
        let now = HomeWorkoutClock.label(e)
        var old: String?
        var p = 1.0
        if minute >= 1, age < 0.5 {
            let prev = HomeWorkoutClock.label(minute * 60 - 0.001)
            if prev != now {
                old = prev
                p = rm ? mstClamp(age / 0.3) : mstSettle(mstClamp(age / 0.5))
            }
        }
        let h: CGFloat = 30
        func text(_ s: String) -> some View {
            Text(s)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.22)
                .foregroundColor(Theme.inkSecondary)
                .lineLimit(1)
        }
        return ZStack(alignment: .topLeading) {
            if let old {
                MSTSlot(width: boxW, height: h, yFraction: rm ? 0 : -p, opacity: 1 - p) { text(old) }
            }
            MSTSlot(width: boxW, height: h, yFraction: rm ? 0 : 1 - p, opacity: old == nil ? 1 : p) { text(now) }
        }
        .frame(width: boxW, height: h, alignment: .topLeading)
        .clipped()
        .offset(x: side, y: frame.safeTop + 154)
    }

    private func beatStyle(u: Double, dur: Double, hold: Double, rm: Bool) -> (opacity: Double, scale: Double) {
        let fade = u < hold ? 1 : 1 - (u - hold) / (1 - hold)
        if rm { return (u < 0.25 ? u / 0.25 : fade, 1) }
        let rise = 0.55 / dur
        if u < rise {
            let k = mstSettle(u / rise)
            return (k, 1.3 - 0.3 * k)
        }
        return (fade, 1)
    }

    // Checkpoint beat text: scales 1.3 to 1 with the settle curve, holds, fades.
    @ViewBuilder
    private var beatBlock: some View {
        if let b = frame.beat {
            let soft = b.checkpointIndex == nil
            let dur = soft ? 1.2 : (b.isTwenty ? 1.6 : 1.5)
            let hold = soft ? 0.75 : 0.8
            let u = b.age / dur
            if u < 1 {
                let st = beatStyle(u: u, dur: dur, hold: hold, rm: frame.reduceMotion)
                Text(b.text)
                    .font(.system(size: soft ? 23 : 46, weight: .heavy))
                    .tracking(soft ? -0.92 : -1.84)
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .scaleEffect(st.scale, anchor: .leading)
                    .frame(width: boxW, height: 46, alignment: .leading)
                    .opacity(st.opacity)
                    .offset(x: side, y: frame.safeTop + 192)
            }
        }
    }
}
