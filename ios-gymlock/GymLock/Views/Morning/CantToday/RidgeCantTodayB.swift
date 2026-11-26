//
//  RidgeCantTodayB.swift
//  GymLock · the "can't today" screen · Ridge look (b)
//
//  Port of the approved prototype v-ridge-b.html: a sky clock dial over the painted range with seven
//  day peaks below it. Drag the sun (or the arch) to set the time, spin the reel panel, swipe the
//  peaks to pick the day. The sun is clipped behind the ridge and rises with a soft sunrise light
//  (skyGlow). Skipping is a hold when the week is at risk (input.data.skipNeedsHold), else a tap.
//
//  Everything shown is real: heading, doors and their order, targets, allowed times, week, costs.
//  The painted world, palette and image helper are the Ridge pause's (RidgeAssets, ridgeWorldDawn).
//
//  The 30 second wait of the prototype is the pause screen's job, not this one: this screen opens
//  straight on the live view (the camera still glides in from the pause framing unless the screen
//  opens on the reschedule picker or Reduce Motion is on).
//

import SwiftUI
import UIKit
import QuartzCore

// MARK: - Palette

private let rcbInk = Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)
private let rcbGround = Color(red: 18 / 255, green: 18 / 255, blue: 20 / 255)

private func rcbC(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255).opacity(a)
}

// MARK: - Math

private enum RCBM {
    static func cl(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, x)) }

    static func ease(_ x: Double) -> Double {
        let k = cl(x)
        return k < 0.5 ? 2 * k * k : 1 - pow(-2 * k + 2, 2) / 2
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

    static func modD(_ a: Double, _ n: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: n)
        return r < 0 ? r + n : r
    }

    static func rub(_ x: Double) -> Double { (x * 1.5 * 0.55) / (1.5 + 0.55 * abs(x)) }

    /// rubber band past the first and last peak
    static func bound(_ p: Double) -> Double {
        if p < 0 { return -rub(-p) }
        if p > 6 { return 6 + rub(p - 6) }
        return p
    }
}

/// skyline of the painted range, one sample per 10 image px (x 0 to 900, y in image px)
private let rcbRidge: [Double] = [
    1266, 1262, 1259, 1259, 1259, 1257, 1246, 1239, 1239, 1239, 1232, 1232, 1232, 1251, 1253, 1253, 1259, 1261, 1270, 1289,
    1310, 1292, 1292, 1292, 1299, 1299, 1279, 1278, 1278, 1278, 1291, 1291, 1263, 1247, 1230, 1230, 1230, 1239, 1232, 1232,
    1232, 1193, 1163, 1104, 1104, 1096, 1096, 1096, 1091, 1071, 1071, 1071, 1077, 1089, 1102, 1142, 1136, 1136, 1136, 1179,
    1219, 1230, 1226, 1226, 1226, 1227, 1250, 1262, 1285, 1286, 1286, 1283, 1283, 1283, 1286, 1240, 1240, 1240, 1243, 1257,
    1275, 1257, 1257, 1257, 1272, 1293, 1295, 1286, 1262, 1262, 1262
]

private func rcbRidgeY(_ x: Double) -> Double {
    let f = RCBM.cl(x / 10, 0, 90)
    let i = Int(f.rounded(.down))
    let j = min(90, i + 1)
    return rcbRidge[i] + (rcbRidge[j] - rcbRidge[i]) * (f - Double(i))
}

// MARK: - The sun's day (6:00 am to 6:00 pm)

private struct RCBTime {
    /// The sun's day is the one people picture: it comes over the mountains at 6:00 am on the
    /// left, is highest at noon, and goes down behind the mountains at 6:00 pm on the right.
    /// Before 6:00 am and after 6:00 pm it is below the horizon and the sky is night.
    static let sunrise = 6 * 60
    static let sunset = 18 * 60

    let aStart = Double(RCBTime.sunrise)
    let aLen = Double(RCBTime.sunset - RCBTime.sunrise)
    /// Where on the arc the sun meets the horizon. The arc runs on below the mountains, so
    /// 6:00 am and 6:00 pm sit at this point, not at the arc's ends.
    let edge: Double

    init(edge: Double) {
        self.edge = RCBM.cl(edge, 0, 0.4)
    }

    /// 0 at 6:00 am, 1 at 6:00 pm, outside the day below 0 or above 1.
    func dayFraction(_ t: Double) -> Double {
        let rel = RCBM.modD(t - aStart, 1440)
        if rel <= aLen { return rel / aLen }
        let nl = 1440 - aLen
        return (rel - aLen < nl / 2) ? 1 + (rel - aLen) / aLen : -(1440 - rel) / aLen
    }

    /// Position on the arc: `edge` at 6:00 am (sunrise), 0.5 at noon, 1 - edge at 6:00 pm (sunset).
    func u(_ t: Double) -> Double {
        edge + (1 - 2 * edge) * dayFraction(t)
    }

    func minOfU(_ x: Double) -> Int {
        let f = (x - edge) / (1 - 2 * edge)
        return Int(RCBM.modD(((aStart + aLen * f) / 5).rounded() * 5, 1440))
    }
}

private struct RCBSky {
    let cool: Double
    let warm: Double
    let night: Double

    /// `day` is the time as a share of the sun's day: 0 at 6:00 am, 1 at 6:00 pm. Warm light
    /// near sunrise and sunset, the clearest sky at noon, night within 45 minutes either side.
    init(day f: Double) {
        let ex = f < 0 ? -f : (f > 1 ? f - 1 : 0)
        let el = sin(Double.pi * RCBM.cl(f))
        let day = 1 - RCBM.cl(ex * 16)
        cool = RCBM.cl((el - 0.1) / 0.6) * day
        warm = RCBM.cl(1 - el / 0.6) * day
        night = RCBM.cl(ex * 16)
    }
}

// MARK: - Camera and geometry

private struct RCBCam: Equatable {
    var s: CGFloat
    var tx: CGFloat
    var ty: CGFloat

    func mixed(_ b: RCBCam, _ t: Double) -> RCBCam {
        let f = CGFloat(t)
        return RCBCam(s: s + (b.s - s) * f, tx: tx + (b.tx - tx) * f, ty: ty + (b.ty - ty) * f)
    }
}

private struct RCBGeo: Equatable {
    static let worldW: CGFloat = 900
    static let worldH: CGFloat = 1948
    static let apex = CGPoint(x: 500, y: 1072)
    static let sunD: CGFloat = 42
    static let farScale: CGFloat = 1.3
    static let peakJitter: [CGFloat] = [14, 0, 20, 6, 22, 2, 12]

    let vw: CGFloat
    let vh: CGFloat
    let k: CGFloat
    let iw: CGFloat
    let ih: CGFloat
    let ox: CGFloat
    let oy: CGFloat
    let off: CGFloat
    let rowTop: CGFloat
    let goTop: CGFloat
    let hdTop: CGFloat
    let hdBottom: CGFloat
    let rx: CGFloat
    let ry: CGFloat
    let apexC: CGFloat
    let hyS: CGFloat
    let cx: CGFloat
    let peakTop: CGFloat
    let labelY: CGFloat
    let p: CGFloat
    let rh: CGFloat
    let panelH: CGFloat
    let panelTop: CGFloat
    let cwH: CGFloat
    let cwM: CGFloat
    let cwA: CGFloat
    /// Width of the ":" column in the time panel.
    let colon: CGFloat

    /// Column widths for the time panel at row height `rh`, measured with the fonts the reels use.
    static func columns(_ rh: CGFloat) -> (h: CGFloat, m: CGFloat, a: CGFloat, colon: CGFloat, total: CGFloat) {
        let digits = UIFont.monospacedDigitSystemFont(ofSize: rh * 1.02, weight: .bold)
        let small = UIFont.systemFont(ofSize: rh * 0.6, weight: .bold)
        let colonFont = UIFont.systemFont(ofSize: (rh * 0.95).rounded(), weight: .bold)
        func width(_ text: String, _ font: UIFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let two = max(width("12", digits), width("00", digits))
        let h = two + 6
        let m = two + 6
        let a = max(width("am", small), width("pm", small)) + 10
        let colon = width(":", colonFont) + 8
        // 8 pt before am/pm, 14 pt either side inside the glass
        let total = h + colon + m + 8 + a + 28
        return (h, m, a, colon, total)
    }
    let pw: CGFloat
    let sb: CGFloat
    let rys: CGFloat
    let farTY: CGFloat

    init(layout: CantTodayLayout, heading: String) {
        let vw = max(1, layout.size.width)
        let vh = max(1, layout.size.height)
        let k = max(vw / Self.worldW, vh / Self.worldH)
        let iw = Self.worldW * k
        let ih = Self.worldH * k
        let ox = (vw - iw) / 2
        let oy = -(ih - vh) * 0.1
        let off = max(vh >= 780 ? CGFloat(58) : CGFloat(28), layout.safeArea.bottom + 14)
        let rowTop = vh - off - 44
        let goTop = rowTop - 10 - 52
        let hdTop = layout.contentTop + 2

        let font = UIFont.systemFont(ofSize: 30, weight: .bold)
        let rect = (heading as NSString).boundingRect(
            with: CGSize(width: max(40, vw - 40), height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil)
        let lines = max(1, min(3, Int((rect.height / 36).rounded())))
        let hdBottom = hdTop + CGFloat(lines) * 36

        let rx = min(vw / 2 - 24, 190)
        // Scales with the screen (212 on the 874 pt reference phone) instead of two fixed steps.
        let ry: CGFloat = min(240, max(140, (vh * 0.2426).rounded()))
        let apexC = hdBottom + 24 + Self.sunD / 2
        let hyS = apexC + ry
        let peakTop = hyS + 40
        // The time panel is sized from the real glyph widths, so "12:55 pm" always fits its columns,
        // and the whole panel shrinks if it would not fit the screen width.
        var rh: CGFloat = min(50, max(34, (vh * 0.0526).rounded()))
        var cols = RCBGeo.columns(rh)
        let maxW = vw - 48
        if cols.total > maxW {
            rh = max(28, (rh * maxW / cols.total).rounded(.down))
            cols = RCBGeo.columns(rh)
        }
        let panelH = rh * 3
        let panelBot = hyS - 12
        let cwH = cols.h
        let cwM = cols.m
        let cwA = cols.a
        let sb = peakTop + 64
        let farTY = (hyS + 30) - 8 - oy - Self.farScale * k * 1300

        self.vw = vw
        self.vh = vh
        self.k = k
        self.iw = iw
        self.ih = ih
        self.ox = ox
        self.oy = oy
        self.off = off
        self.rowTop = rowTop
        self.goTop = goTop
        self.hdTop = hdTop
        self.hdBottom = hdBottom
        self.rx = rx
        self.ry = ry
        self.apexC = apexC
        self.hyS = hyS
        self.cx = vw / 2
        self.peakTop = peakTop
        self.labelY = goTop - 32
        self.p = max(96, min(118, vw * 0.28))
        self.rh = rh
        self.panelH = panelH
        self.panelTop = panelBot - panelH
        self.cwH = cwH
        self.cwM = cwM
        self.cwA = cwA
        self.colon = cols.colon
        self.pw = cols.total
        self.sb = sb
        self.rys = sb - apexC
        self.farTY = farTY
    }

    var nearW: CGFloat { vw + 6 * p }
    var nearTop: CGFloat { peakTop - 40 }

    func xc(_ i: Int) -> CGFloat { vw / 2 + CGFloat(i) * p }
    func apexY(_ i: Int) -> CGFloat { peakTop + Self.peakJitter[i] }

    func clampCam(_ c: RCBCam) -> RCBCam {
        RCBCam(s: c.s,
               tx: min(-ox, max(vw - ox - iw * c.s, c.tx)),
               ty: min(-oy, c.ty))
    }

    /// the painted range as a parallax backdrop, following the swipe
    func farCam(_ pos: Double) -> RCBCam {
        let slack = (Self.farScale - 1) * iw / 2
        let tx = -(Self.farScale - 1) * iw / 2 + CGFloat((pos - 3) / 3) * slack * 0.9
        return clampCam(RCBCam(s: Self.farScale, tx: tx, ty: farTY))
    }

    /// where the pause left the camera (1.07 push, slight drift up)
    var pauseCam: RCBCam {
        let s: CGFloat = 1.07
        let tx = min(-ox, max(vw - ox - iw * s, 0))
        let ty = min(min(-oy, max(vh - oy - ih * s, -14)), -oy)
        return RCBCam(s: s, tx: tx, ty: ty)
    }

    /// the sun at the end of the pause, in world units
    var pauseSun: CGPoint {
        CGPoint(x: Self.apex.x, y: Self.apex.y + (-52 / 1.07) / k)
    }

    func arc(_ u: Double) -> CGPoint {
        let uc = RCBM.cl(u)
        let ex = u < 0 ? -u : (u > 1 ? u - 1 : 0)
        return CGPoint(x: cx - rx * CGFloat(cos(Double.pi * uc)),
                       y: sb - rys * CGFloat(sin(Double.pi * uc)) + CGFloat(ex) * rys * 5)
    }

    func uFromPoint(_ x: CGFloat, _ y: CGFloat) -> Double {
        var th = atan2(Double(-(y - sb) / rys), Double((x - cx) / rx))
        if th < -Double.pi / 2 { th += 2 * Double.pi }
        return 1 - th / Double.pi
    }
}

// MARK: - Static shapes

private enum RCBShapes {
    /// the sky above the painted ridge, in world units
    static let sky: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 900, y: 0))
        var i = 90
        while i >= 0 {
            p.addLine(to: CGPoint(x: CGFloat(i * 10), y: CGFloat(rcbRidge[i])))
            i -= 1
        }
        p.closeSubpath()
        return p
    }()

    struct Star {
        let x: CGFloat
        let y: CGFloat
        let r: CGFloat
        let a: Double
    }

    static let stars: [Star] = {
        var s = 7
        func rnd() -> Double {
            s = (s * 16807) % 2147483647
            return Double(s) / 2147483647
        }
        var out: [Star] = []
        for _ in 0..<80 {
            let x = 20 + rnd() * 860
            let y = 60 + rnd() * 1130
            let r = 1.6 + rnd() * 2.2
            let a = 0.45 + rnd() * 0.5
            out.append(Star(x: CGFloat(x), y: CGFloat(y), r: CGFloat(r), a: a))
        }
        return out
    }()

    /// the faint fan of light: repeating 15 degree wedges
    static let rays: Gradient = {
        var stops: [Gradient.Stop] = []
        for rep in 0..<24 {
            let base = Double(rep) * 15 / 360
            stops.append(Gradient.Stop(color: rcbC(255, 226, 192, 0.5), location: base))
            stops.append(Gradient.Stop(color: rcbC(255, 226, 192, 0.12), location: base + 4 / 360))
            stops.append(Gradient.Stop(color: rcbC(255, 226, 192, 0), location: base + 8 / 360))
            stops.append(Gradient.Stop(color: rcbC(255, 226, 192, 0), location: base + 14.9 / 360))
        }
        stops.append(Gradient.Stop(color: rcbC(255, 226, 192, 0), location: 1))
        return Gradient(stops: stops)
    }()
}

// MARK: - Fades (driven by the timeline, no implicit animation)

private struct RCBFade {
    var from = 0.0
    var to = 0.0
    var t0 = 0.0
    var dur = 0.3

    init(_ v: Double = 0) {
        from = v
        to = v
    }

    func at(_ now: Double) -> Double {
        if dur <= 0 { return to }
        let q = RCBM.cl((now - t0) / dur)
        return RCBM.lerp(from, to, RCBM.ease(q))
    }

    mutating func go(_ target: Double, now: Double, dur d: Double, delay: Double = 0) {
        from = at(now)
        to = target
        t0 = now + delay
        dur = d
    }
}

// MARK: - Sim (mutable per-frame state that never needs a view update)

private final class RCBSim {
    let t0 = CACurrentMediaTime()
    var now: Double { CACurrentMediaTime() - t0 }
    var lastNow = 0.0

    var fades: [String: RCBFade] = [:]

    var live = false
    var settled = false
    var wasCalm = false
    var enterT = 0.0
    var contT0 = -10.0
    var camFrom = RCBCam(s: 1, tx: 0, ty: 0)
    var camT0 = 0.0
    var camMoving = false

    // the peaks
    var pos = 0.0
    var posRaw = 0.0
    var posTarget: Double? = nil
    var posV = 0.0
    var panPhase = 0          // 0 idle, 1 dragging, 2 ignored
    var panMoved = false
    var panP0 = 0.0
    var panDragging = false

    // the sun
    var w = 0.0
    var sunV = 0.0
    var blk = 0.0
    var dialPhase = 0         // 0 idle, 1 dragging, 2 ignored
    var dialDU0 = 0.0
    var dialLastQ = -1

    // skip
    var tapStart = -1.0
    var skipDoneAt = -1.0
    var skipDoneBase = 0.0
    var tapCommitPending = false

    // flags
    var finished = false
    var ended = false
    var quietUntil = 0.0
    var progrUntil = 0.0
    var pendingCheck = false
    var lastChange = 0.0
    var noteHideAt = 0.0
    var allowCache: [Int: Bool] = [:]
    var nudgeIds: Set<String> = []

    func fade(_ k: String, _ n: Double) -> Double { fades[k]?.at(n) ?? 0 }

    func setFade(_ k: String, _ v: Double, _ dur: Double, delay: Double = 0) {
        var f = fades[k] ?? RCBFade(0)
        f.go(v, now: now, dur: dur, delay: delay)
        fades[k] = f
    }

    func jumpFade(_ k: String, _ v: Double) { fades[k] = RCBFade(v) }

    func springPos(to target: Double, v0: Double, reduce: Bool) {
        if reduce {
            pos = target
            posRaw = target
            posTarget = nil
            posV = 0
            return
        }
        posTarget = target
        posV = v0
    }

    func stepPos(dt: Double) {
        guard let tg = posTarget else { return }
        let kk = 150.0
        let c = 2 * kk.squareRoot() * 0.96
        posV += (-kk * (pos - tg) - c * posV) * dt
        pos += posV * dt
        posRaw = pos
        if abs(pos - tg) < 0.002 && abs(posV) < 0.02 {
            pos = tg
            posRaw = tg
            posV = 0
            posTarget = nil
        }
    }
}

// MARK: - One frame, as numbers

private struct RCBFrame {
    var n = 0.0
    var cam = RCBCam(s: 1, tx: 0, ty: 0)
    var u = 0.0
    var sunX = 0.0
    var sunY = 0.0
    var sunScreenR = 21.0
    var sunOpacity = 1.0
    var sunBright = 0.0
    var ringOpacity = 0.0
    var ringScale = 1.0
    var night = 0.0
    var cool = 0.0
    var warm = 0.0
    var glowX = 0.0
    var glowY = 0.0
    var dayOp = 0.0
    var dawn = 0.0
    var halo = 0.0
    var lift = 0.0
    var rayOp = 0.0
    var rayAngle = 0.0
    var ridgeAtSun = 0.0
    var holdP = 0.0
    var hp = 0.0
    var swipeX = 0.0
    var swipeV = 0.0
    var reel: [Double] = [0, 0, 0]
    var reelPulse = 0.0
    var homeV = 0.0
    var skipV = 0.0
    var sunV = 0.0
    var nudgeU = 0.0
    var selOK = true
    var dotsFrom = 0.0
}

// MARK: - World drawing

private enum RCBDraw {
    static func world(_ ctx: inout GraphicsContext, size: CGSize, g: RCBGeo, f: RCBFrame, image: CGImage?) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(rcbInk))
        ctx.drawLayer { c in
            c.translateBy(x: g.ox + f.cam.tx, y: g.oy + f.cam.ty)
            c.scaleBy(x: f.cam.s * g.k, y: f.cam.s * g.k)
            let wr = CGRect(x: 0, y: 0, width: RCBGeo.worldW, height: RCBGeo.worldH)
            c.fill(Path(CGRect(x: 0, y: RCBGeo.worldH, width: RCBGeo.worldW, height: RCBGeo.worldH)), with: .color(rcbGround))
            if let image {
                let resolved = c.resolve(Image(decorative: image, scale: 1).interpolation(.medium))
                c.draw(resolved, in: wr)
            }
            if f.night > 0.001 {
                c.fill(Path(wr), with: .color(rcbC(5, 8, 22, 0.66 * f.night)))
            }
            c.drawLayer { s in
                sky(&s, g: g, f: f)
            }
        }
    }

    private static func sky(_ s: inout GraphicsContext, g: RCBGeo, f: RCBFrame) {
        s.clip(to: RCBShapes.sky)
        let wr = CGRect(x: 0, y: 0, width: RCBGeo.worldW, height: RCBGeo.worldH)
        let gx = CGFloat(f.glowX)
        let gy = CGFloat(f.glowY)

        // a faint blurred fan, only while the sun is behind or just clearing the edge
        if f.rayOp > 0.004 {
            s.drawLayer { l1 in
                l1.opacity = f.rayOp
                l1.blendMode = .screen
                l1.drawLayer { l2 in
                    l2.fill(Path(wr), with: .conicGradient(RCBShapes.rays, center: CGPoint(x: gx, y: gy), angle: .degrees(f.rayAngle)))
                    l2.blendMode = .destinationIn
                    let mask = Gradient(stops: [
                        Gradient.Stop(color: Color.black.opacity(0.9), location: 0),
                        Gradient.Stop(color: Color.black.opacity(0.35), location: 0.35),
                        Gradient.Stop(color: Color.black.opacity(0), location: 1)
                    ])
                    l2.fill(Path(wr), with: .radialGradient(mask, center: CGPoint(x: gx, y: gy), startRadius: 0, endRadius: 430))
                }
            }
        }

        // the sunrise light: horizon warmth, halo around the sun, the sky lifting
        if f.dayOp > 0.002 {
            s.blendMode = .screen
            let op = f.dayOp
            let farX = max(f.glowX, 900 - f.glowX)
            let farY = max(f.glowY, 1948 - f.glowY)
            let r0 = CGFloat((farX * farX + farY * farY).squareRoot())
            let halo = Gradient(stops: [
                Gradient.Stop(color: rcbC(255, 236, 210, 0.7 * f.halo * op), location: 0),
                Gradient.Stop(color: rcbC(255, 214, 176, 0.32 * f.halo * op), location: 0.06),
                Gradient.Stop(color: rcbC(255, 204, 166, 0.1 * f.halo * op), location: 0.18),
                Gradient.Stop(color: rcbC(255, 204, 166, 0), location: 0.34)
            ])
            s.fill(Path(wr), with: .radialGradient(halo, center: CGPoint(x: gx, y: gy), startRadius: 0, endRadius: r0))

            var e = s
            e.translateBy(x: gx, y: CGFloat(f.ridgeAtSun))
            e.scaleBy(x: 414, y: 175.32)
            let horizon = Gradient(stops: [
                Gradient.Stop(color: rcbC(255, 196, 150, 0.5 * f.dawn * op), location: 0),
                Gradient.Stop(color: rcbC(255, 196, 150, 0), location: 1)
            ])
            e.fill(Path(CGRect(x: -1, y: -1, width: 2, height: 2)),
                   with: .radialGradient(horizon, center: .zero, startRadius: 0, endRadius: 1))

            let lift = Gradient(stops: [
                Gradient.Stop(color: rcbC(160, 190, 230, 0.46 * f.lift * op), location: 0),
                Gradient.Stop(color: rcbC(232, 214, 194, 0.28 * f.lift * op), location: 0.66)
            ])
            s.fill(Path(wr), with: .linearGradient(lift, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: RCBGeo.worldH)))
            s.blendMode = .normal
        }

        if f.cool > 0.002 {
            let grad = Gradient(stops: [
                Gradient.Stop(color: rcbC(110, 140, 185, 0.62 * f.cool * 0.9), location: 0),
                Gradient.Stop(color: rcbC(170, 188, 205, 0.42 * f.cool * 0.9), location: 0.6),
                Gradient.Stop(color: rcbC(228, 214, 198, 0.34 * f.cool * 0.9), location: 1)
            ])
            s.fill(Path(wr), with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: RCBGeo.worldH)))
        }
        if f.warm > 0.002 {
            let grad = Gradient(stops: [
                Gradient.Stop(color: rcbC(90, 70, 110, 0), location: 0),
                Gradient.Stop(color: rcbC(160, 96, 112, 0.34 * f.warm), location: 0.55),
                Gradient.Stop(color: rcbC(255, 164, 112, 0.62 * f.warm), location: 1)
            ])
            s.fill(Path(wr), with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: RCBGeo.worldH)))
        }
        if f.night > 0.01 {
            for st in RCBShapes.stars {
                let dot = CGRect(x: st.x - st.r, y: st.y - st.r, width: st.r * 2, height: st.r * 2)
                s.fill(Path(ellipseIn: dot), with: .color(Color.white.opacity(st.a * f.night)))
            }
        }

        // the sun, clipped behind the ridge by the sky path
        if f.sunOpacity > 0.001 {
            let unit = Double(f.cam.s * g.k)
            let r = CGFloat(f.sunScreenR / unit)
            let c = CGPoint(x: f.sunX, y: f.sunY)
            let dot = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            let base = Theme.accent.opacity(f.sunOpacity)
            s.fill(Path(ellipseIn: dot), with: .color(base))
            if f.sunBright > 0.001 {
                s.fill(Path(ellipseIn: dot), with: .color(Color.white.opacity(0.3 * f.sunBright * f.sunOpacity)))
            }
            if f.ringOpacity > 0.01 {
                let rr = CGFloat(26.5 * f.ringScale * (f.sunScreenR / 21) / unit)
                let ring = CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)
                s.stroke(Path(ellipseIn: ring), with: .color(Color.white.opacity(0.9 * f.ringOpacity)), lineWidth: CGFloat(3 / unit))
            }
        }
    }
}

// MARK: - The seven peaks (drawn once, moved by offset)

private enum RCBPeaksDraw {
    static let order = [1, 3, 5, 0, 2, 4, 6]

    static func shape(_ i: Int, _ g: RCBGeo) -> (all: Path, shade: Path) {
        let pp = g.p
        let x = g.xc(i)
        let a = g.apexY(i)
        let bot = g.vh + 4
        let sl: CGFloat = 1.12
        var seed = 11 + i * 977
        func r() -> CGFloat {
            seed = (seed * 16807) % 2147483647
            return CGFloat(seed) / 2147483647
        }
        func edge(_ sgn: CGFloat) -> [CGPoint] {
            var pts: [CGPoint] = []
            var dx: CGFloat = 0
            for j in 1...9 {
                dx += pp * (0.1 + r() * 0.12)
                let jit = (r() - 0.5) * 15
                let extra: CGFloat = j == 1 ? 6 : 0
                pts.append(CGPoint(x: x + sgn * dx, y: a + sl * dx + jit + extra))
            }
            if let l = pts.last {
                pts.append(CGPoint(x: l.x + sgn * 200, y: l.y + 200 * sl))
            }
            return pts
        }
        let lp = edge(-1)
        let rp = edge(1)
        var ar: [CGPoint] = [CGPoint(x: x, y: a)]
        for j in 1...7 {
            let ax = x + (r() - 0.35) * 16
            let ay = a + CGFloat(j) * 46 + r() * 10
            ar.append(CGPoint(x: ax, y: ay))
        }
        ar.append(CGPoint(x: x + 6, y: bot))

        var all = Path()
        all.move(to: CGPoint(x: x, y: a))
        for q in lp { all.addLine(to: q) }
        all.addLine(to: CGPoint(x: x - 3 * pp, y: bot))
        all.addLine(to: CGPoint(x: x + 3 * pp, y: bot))
        for q in rp.reversed() { all.addLine(to: q) }
        all.closeSubpath()

        var shade = Path()
        shade.move(to: CGPoint(x: x, y: a))
        for q in ar { shade.addLine(to: q) }
        shade.addLine(to: CGPoint(x: x + 3 * pp, y: bot))
        for q in rp.reversed() { shade.addLine(to: q) }
        shade.closeSubpath()
        return (all, shade)
    }

    static func draw(_ ctx: inout GraphicsContext, g: RCBGeo, image: CGImage?) {
        let pp = g.p
        let kT = g.k * 1.5
        let iwT = RCBGeo.worldW * kT
        let ihT = RCBGeo.worldH * kT
        var resolved: GraphicsContext.ResolvedImage? = nil
        if let image {
            resolved = ctx.resolve(Image(decorative: image, scale: 1).interpolation(.medium))
        }
        let fadeGrad = Gradient(stops: [
            Gradient.Stop(color: rcbGround.opacity(0), location: 0),
            Gradient.Stop(color: rcbGround.opacity(0.35), location: 0.35),
            Gradient.Stop(color: rcbGround.opacity(0.92), location: 0.8),
            Gradient.Stop(color: rcbGround, location: 1)
        ])
        for i in order {
            let sh = shape(i, g)
            let x = g.xc(i)
            let a = g.apexY(i)
            let flip: CGFloat = i % 2 == 1 ? -1 : 1
            let depth = Double(i % 3) * 0.08
            let box = CGRect(x: x - 3 * pp, y: a - 40, width: 6 * pp, height: g.vh)
            let fadeBox = CGRect(x: x - 3 * pp, y: a - 40, width: 6 * pp, height: g.vh - a + 44)
            ctx.drawLayer { c in
                c.clip(to: sh.all)
                c.fill(Path(box), with: .color(rcbC(34, 34, 40)))
                if let resolved {
                    c.drawLayer { t in
                        t.translateBy(x: x, y: a)
                        t.scaleBy(x: flip, y: 1)
                        t.translateBy(x: -RCBGeo.apex.x * kT, y: -RCBGeo.apex.y * kT)
                        t.draw(resolved, in: CGRect(x: 0, y: 0, width: iwT, height: ihT))
                    }
                }
                c.fill(Path(box), with: .color(rcbC(12, 12, 16, 0.16 + depth)))
                c.fill(sh.shade, with: .color(rcbC(10, 10, 14, 0.34)))
                c.fill(Path(fadeBox), with: .linearGradient(fadeGrad,
                                                           startPoint: CGPoint(x: 0, y: fadeBox.minY),
                                                           endPoint: CGPoint(x: 0, y: fadeBox.maxY)))
            }
            ctx.stroke(sh.all, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
        }
    }
}

private struct RCBPeaks: View, Equatable {
    let g: RCBGeo
    let image: CGImage?

    static func == (a: RCBPeaks, b: RCBPeaks) -> Bool {
        a.g == b.g && (a.image == nil) == (b.image == nil)
    }

    var body: some View {
        Canvas { ctx, _ in
            RCBPeaksDraw.draw(&ctx, g: g, image: image)
        }
        .frame(width: g.nearW, height: g.vh)
    }
}

// MARK: - Peak icons and labels

private enum RCBKind {
    case done, today, planned, free, past
}

private struct RCBPeakDay {
    let i: Int
    let kind: RCBKind
    let name: String
    let caption: String?
}

private struct RCBPeakIcon: View {
    let kind: RCBKind
    let ring: Double

    var body: some View {
        Canvas { ctx, _ in
            let white = Color.white
            switch kind {
            case .done:
                var pole = Path()
                pole.move(to: CGPoint(x: 22, y: 26))
                pole.addLine(to: CGPoint(x: 22, y: 10))
                ctx.stroke(pole, with: .color(white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                var flag = Path()
                flag.move(to: CGPoint(x: 22, y: 10))
                flag.addLine(to: CGPoint(x: 33, y: 10))
                flag.addLine(to: CGPoint(x: 29.5, y: 14.2))
                flag.addLine(to: CGPoint(x: 33, y: 18.4))
                flag.addLine(to: CGPoint(x: 22, y: 18.4))
                flag.closeSubpath()
                ctx.fill(flag, with: .color(white))
            case .planned:
                if ring > 0.01 {
                    ctx.stroke(Path(ellipseIn: CGRect(x: 11, y: 15, width: 22, height: 22)),
                               with: .color(white.opacity(ring)), lineWidth: 1.6)
                }
                ctx.fill(Path(ellipseIn: CGRect(x: 16, y: 20, width: 12, height: 12)), with: .color(white))
            case .free:
                if ring > 0.01 {
                    let rc = CGRect(x: 10, y: 14, width: 24, height: 24)
                    ctx.fill(Path(ellipseIn: rc), with: .color(white.opacity(0.18 * ring)))
                    ctx.stroke(Path(ellipseIn: rc), with: .color(white.opacity(ring)), lineWidth: 1.6)
                }
                let body = CGRect(x: 15.5, y: 19.5, width: 13, height: 13)
                ctx.fill(Path(ellipseIn: body), with: .color(white.opacity(0.1)))
                ctx.stroke(Path(ellipseIn: body), with: .color(white), lineWidth: 1.9)
            case .today:
                if ring > 0.01 {
                    ctx.stroke(Path(ellipseIn: CGRect(x: 11, y: 21, width: 22, height: 10)),
                               with: .color(white.opacity(ring)), lineWidth: 1.6)
                }
                var pin = Path()
                pin.move(to: CGPoint(x: 22, y: 26))
                pin.addCurve(to: CGPoint(x: 14, y: 12.5), control1: CGPoint(x: 22, y: 26), control2: CGPoint(x: 14, y: 18.5))
                pin.addCurve(to: CGPoint(x: 22, y: 4.5), control1: CGPoint(x: 14, y: 8.08), control2: CGPoint(x: 17.58, y: 4.5))
                pin.addCurve(to: CGPoint(x: 30, y: 12.5), control1: CGPoint(x: 26.42, y: 4.5), control2: CGPoint(x: 30, y: 8.08))
                pin.addCurve(to: CGPoint(x: 22, y: 26), control1: CGPoint(x: 30, y: 18.5), control2: CGPoint(x: 22, y: 26))
                pin.closeSubpath()
                ctx.fill(pin, with: .color(white))
                ctx.fill(Path(ellipseIn: CGRect(x: 19, y: 9.5, width: 6, height: 6)), with: .color(rcbC(58, 58, 64)))
            case .past:
                ctx.fill(Path(ellipseIn: CGRect(x: 19.4, y: 23.4, width: 5.2, height: 5.2)), with: .color(white.opacity(0.45)))
            }
        }
        .frame(width: 44, height: 44)
    }
}

private struct RCBNearLayer: View {
    let g: RCBGeo
    let image: CGImage?
    let days: [RCBPeakDay]
    let selIdx: Int
    let rings: [Double]
    let others: Double
    let hideSel: Double
    let hm: Double
    let shiftX: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RCBPeaks(g: g, image: image).equatable()
            ForEach(days, id: \.i) { d in
                let sel = d.i == selIdx
                let dim = 1 - 0.7 * hm
                RCBPeakIcon(kind: d.kind, ring: rings[d.i])
                    .opacity((sel ? 1 - hideSel : 1 - others) * dim)
                    .offset(x: g.xc(d.i) - 22, y: g.apexY(d.i) - 26)
                VStack(spacing: 0) {
                    Text(d.name)
                        .font(.system(size: sel ? 26 : 12, weight: sel ? .bold : .semibold))
                        .foregroundStyle(Color.white.opacity(sel ? 1 : 0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: Color.black.opacity(0.5), radius: 6, x: 0, y: 1)
                    if let cap = d.caption {
                        Text(cap)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .frame(width: 120)
                .opacity((sel ? 1 : 1 - others) * dim)
                .offset(x: g.xc(d.i) - 60, y: g.labelY - 8 - (sel ? 8 : 0))
            }
        }
        .frame(width: g.nearW, height: g.vh, alignment: .topLeading)
        .offset(x: shiftX, y: -g.nearTop)
        .allowsHitTesting(false)
    }
}

// MARK: - Small pieces

private enum RCBMode: Equatable {
    case time, home, skipOnly, confirm
}

private struct RCBGlass<S: Shape>: ViewModifier {
    let shape: S
    var dark = false

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                shape.fill(dark ? rcbC(14, 14, 18, 0.34) : Color.white.opacity(0.16))
                shape.stroke(Color.white.opacity(0.25), lineWidth: 1)
            }
        }
    }
}

private struct RCBHouse: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 26 * rect.width, y: rect.minY + y / 22 * rect.height)
        }
        var p = Path()
        p.move(to: pt(2, 21))
        p.addLine(to: pt(2, 10))
        p.addLine(to: pt(13, 2))
        p.addLine(to: pt(24, 10))
        p.addLine(to: pt(24, 21))
        p.closeSubpath()
        return p
    }
}

private struct RCBPressStyle: ButtonStyle {
    var onDown: () -> Void = {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { onDown() }
            }
    }
}

private struct RCBCostIcon: View {
    let kind: CantTodayCost.Kind

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: 22.0 / 24.0, y: 22.0 / 24.0)
            let white = Color.white
            switch kind {
            case .week:
                ctx.stroke(Path(roundedRect: CGRect(x: 4, y: 5.5, width: 16, height: 14), cornerRadius: 3),
                           with: .color(white), lineWidth: 1.8)
                var line = Path()
                line.move(to: CGPoint(x: 4, y: 10))
                line.addLine(to: CGPoint(x: 20, y: 10))
                ctx.stroke(line, with: .color(white), lineWidth: 1.8)
            case .row:
                var chev = Path()
                chev.move(to: CGPoint(x: 6, y: 6))
                chev.addLine(to: CGPoint(x: 12, y: 12))
                chev.addLine(to: CGPoint(x: 6, y: 18))
                chev.move(to: CGPoint(x: 13, y: 6))
                chev.addLine(to: CGPoint(x: 19, y: 12))
                chev.addLine(to: CGPoint(x: 13, y: 18))
                ctx.stroke(chev, with: .color(white), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case .streak:
                var fl = Path()
                fl.move(to: CGPoint(x: 12, y: 2))
                fl.addCurve(to: CGPoint(x: 17, y: 13), control1: CGPoint(x: 13, y: 6), control2: CGPoint(x: 17, y: 8))
                fl.addCurve(to: CGPoint(x: 12, y: 18), control1: CGPoint(x: 17, y: 15.76), control2: CGPoint(x: 14.76, y: 18))
                fl.addCurve(to: CGPoint(x: 7, y: 13), control1: CGPoint(x: 9.24, y: 18), control2: CGPoint(x: 7, y: 15.76))
                fl.addCurve(to: CGPoint(x: 9, y: 9), control1: CGPoint(x: 7, y: 11), control2: CGPoint(x: 8, y: 10))
                fl.addCurve(to: CGPoint(x: 11, y: 12), control1: CGPoint(x: 9, y: 11), control2: CGPoint(x: 10, y: 12))
                fl.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 11, y: 8), control2: CGPoint(x: 10, y: 6))
                fl.closeSubpath()
                ctx.fill(fl, with: .color(Theme.accent))
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct RCBPlant: View {
    let pole: Double
    let pen: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 22, y: 46))
                p.addLine(to: CGPoint(x: 22, y: 20))
            }
            .trimmedPath(from: 0, to: CGFloat(pole))
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 22, y: 20))
                p.addLine(to: CGPoint(x: 36, y: 20))
                p.addLine(to: CGPoint(x: 31.5, y: 25.5))
                p.addLine(to: CGPoint(x: 36, y: 31))
                p.addLine(to: CGPoint(x: 22, y: 31))
                p.closeSubpath()
            }
            .fill(Color.white)
            .scaleEffect(x: max(0.001, CGFloat(pen)), y: 1, anchor: UnitPoint(x: 22.0 / 44.0, y: 20.0 / 64.0))
        }
        .frame(width: 44, height: 64, alignment: .topLeading)
    }
}

private struct RCBReelRow: View {
    let text: String
    let d: CGFloat
    let rh: CGFloat
    let blocked: Bool
    let align: Alignment
    let anchor: UnitPoint
    let small: Bool
    let peek: Double
    let width: CGFloat

    var body: some View {
        let th = max(-1.5, min(1.5, Double(d) * 0.5))
        let a = abs(Double(d))
        let sc = RCBM.lerp(1, 0.56, min(a, 1))
        let op = RCBM.cl(1 - a * 0.42) * (blocked ? 0.34 : 1)
        let radius = Double(rh) / 0.5
        let yOff = radius * sin(th) - Double(d) * Double(rh)
        Text(text)
            .font(.system(size: rh * (small ? 0.6 : 1.02), weight: .bold))
            .monospacedDigit()
            .tracking(-0.5)
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, height: rh, alignment: align)
            .scaleEffect(CGFloat(sc), anchor: anchor)
            .rotation3DEffect(.radians(-th), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.4)
            .offset(y: CGFloat(yOff) - CGFloat(peek) * rh)
            .opacity(op)
    }
}

// MARK: - The look

struct RidgeCantTodayB: View {
    let input: CantTodayInput

    @State private var sim = RCBSim()
    @State private var nudger: CantTodayNudger
    @State private var world: CGImage? = nil
    @State private var mode: RCBMode
    @State private var selIdx = -1
    @State private var hIdx = 0
    @State private var mIdx = 0
    @State private var aIdx = 0
    @State private var memo: [String: Int] = [:]
    @State private var hBusy = false
    @State private var mBusy = false
    @State private var aBusy = false
    @State private var holdProgress = 0.0
    @State private var isHolding = false
    @State private var noteText = ""
    @State private var bigTitle = ""
    @State private var bigSub = ""
    @State private var endText = ""
    @State private var finished = false
    @State private var ended = false

    private let tm: RCBTime
    private let canReschedule: Bool
    private let hasHome: Bool
    private let todayEarliest: Int?

    init(input: CantTodayInput) {
        self.input = input
        let d = input.data
        let can = d.order.contains(.reschedule) && !d.targets.isEmpty
        let home = d.order.contains(.home) && d.homeMinutes != nil
        canReschedule = can
        hasHome = home
        // the sun meets the horizon where the arc crosses the mountains' line
        let g0 = RCBGeo(layout: input.layout, heading: d.heading)
        // 12 pt above the horizon line, so at 6:00 am about half the sun shows over the ridge
        let drop = Double(g0.sb - (g0.hyS - 12)) / Double(max(1, g0.rys))
        tm = RCBTime(edge: asin(RCBM.cl(drop, 0, 1)) / Double.pi)
        var earliest: Int? = nil
        if let t = d.targets.first(where: { $0.isToday }) {
            var m = (d.nowMinutes / 5 + 1) * 5
            var tries = 0
            while tries < 288 {
                if case .ok = d.allowed(t, minutes: m) {
                    earliest = CantTodayClock.wrap(m)
                    break
                }
                m += 5
                tries += 1
            }
        }
        todayEarliest = earliest
        _mode = State(initialValue: can ? .time : (home ? .home : .skipOnly))
        _nudger = State(initialValue: CantTodayNudger(haptics: input.haptics, reduceMotion: input.reduceMotion))
    }

    // MARK: Derived

    private var data: CantTodayData { input.data }
    private var reduce: Bool { input.reduceMotion }

    private var selMin: Int { rcbMinutes(hIdx, mIdx, aIdx) }

    private func rcbMinutes(_ h: Int, _ m: Int, _ a: Int) -> Int {
        (((h + 1) % 12) + (a == 1 ? 12 : 0)) * 60 + m * 5
    }

    private var curTarget: CantTodayTarget? {
        data.targets.first { $0.weekIndex == selIdx }
    }

    private func target(at idx: Int) -> CantTodayTarget? {
        data.targets.first { $0.weekIndex == idx }
    }

    private func isOK(_ minutes: Int) -> Bool {
        guard let t = curTarget else { return true }
        let key = CantTodayClock.wrap(minutes) + 1440 * t.weekIndex
        if let hit = sim.allowCache[key] { return hit }
        let ok = data.allowed(t, minutes: minutes).isOK
        sim.allowCache[key] = ok
        return ok
    }

    private func blockedText(_ minutes: Int) -> String {
        guard let t = curTarget else { return "" }
        if case .blocked(let why) = data.allowed(t, minutes: minutes) {
            return why.replacingOccurrences(of: "inside your ", with: "")
        }
        return ""
    }

    private func nearestAllowed(_ minutes: Int) -> Int {
        var d = 0
        while d <= 720 {
            if isOK(minutes + d) { return CantTodayClock.wrap(minutes + d) }
            if isOK(minutes - d) { return CantTodayClock.wrap(minutes - d) }
            d += 5
        }
        return minutes
    }

    private func nearestWeekIndex(_ p: Double) -> Int? {
        var best: Int? = nil
        var bd = 1e9
        for t in data.targets {
            let d = abs(Double(t.weekIndex) - p)
            if d < bd {
                bd = d
                best = t.weekIndex
            }
        }
        return best
    }

    private var firstTarget: CantTodayTarget? {
        data.targets.first(where: { $0.isToday }) ?? data.targets.first
    }

    private var dyName: String {
        guard let t = curTarget else { return "" }
        return t.isToday ? "today" : t.short
    }

    private var days: [RCBPeakDay] {
        let names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        var out: [RCBPeakDay] = []
        for (i, d) in data.week.enumerated() where i < 7 {
            let tg = target(at: i)
            let kind: RCBKind
            switch d.state {
            case .done: kind = .done
            case .today: kind = .today
            case .planned: kind = .planned
            case .missed, .rest: kind = tg != nil ? .free : .past
            }
            let name = kind == .today ? "today" : (tg?.short ?? names[i])
            var cap: String? = nil
            if kind == .done { cap = "done" }
            if kind == .planned { cap = "planned" }
            out.append(RCBPeakDay(i: i, kind: kind, name: name, caption: cap))
        }
        return out
    }

    // MARK: Body

    var body: some View {
        let g = RCBGeo(layout: input.layout, heading: data.heading)
        ZStack(alignment: .topLeading) {
            rcbInk
            TimelineView(.animation) { tl in
                scene(g, tl.date)
            }
        }
        .frame(width: g.vw, height: g.vh, alignment: .topLeading)
        .clipped()
        .onAppear { enterLive(g) }
        .task { await loadWorld() }
        .onChange(of: selMin) { _, new in selMinChanged(new) }
    }

    private func loadWorld() async {
        if world != nil { return }
        let cg = await Task.detached(priority: .userInitiated) { RidgeAssets.shared.image(.worldDawn) }.value
        world = cg
    }

    // MARK: Scene

    @ViewBuilder
    private func scene(_ g: RCBGeo, _ date: Date) -> some View {
        let f = makeFrame(g)
        ZStack(alignment: .topLeading) {
            worldLayer(g, f)
            nearLayer(g, f)
            hudLayer(g, f)
            controlsLayer(g, f)
            overlayLayer(g, f)
        }
        .frame(width: g.vw, height: g.vh, alignment: .topLeading)
        .onChange(of: date) { _, _ in tick(g) }
    }

    // MARK: World

    private func worldLayer(_ g: RCBGeo, _ f: RCBFrame) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                RCBDraw.world(&ctx, size: size, g: g, f: f, image: world)
            }
            .frame(width: g.vw, height: g.vh)
            LinearGradient(colors: [rcbInk.opacity(0.35), rcbInk.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(width: g.vw, height: g.vh * 0.58)
            LinearGradient(colors: [rcbInk.opacity(0), rcbInk.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .frame(width: g.vw, height: g.vh * 0.38)
                .offset(y: g.vh * 0.62)
                .opacity(sim.fade("scrimb", f.n))
        }
        .frame(width: g.vw, height: g.vh, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Peaks

    private func nearLayer(_ g: RCBGeo, _ f: RCBFrame) -> some View {
        let n = f.n
        var rings: [Double] = []
        for i in 0..<7 { rings.append(sim.fade("ring\(i)", n)) }
        let ui = sim.fade("ui", n)
        let on = canReschedule && !finished && !ended
        let shift = -CGFloat(sim.pos) * g.p + CGFloat(f.swipeX)
        let name = curTarget?.name ?? ""
        return RCBNearLayer(g: g, image: world, days: days, selIdx: selIdx, rings: rings,
                            others: sim.fade("others", n), hideSel: sim.fade("hideSel", n),
                            hm: sim.fade("hm", n), shiftX: shift)
            .frame(width: g.vw, height: g.vh - g.nearTop, alignment: .topLeading)
            .clipped()
            .brightness(reduce ? 0.12 * f.swipeV : 0)
            .opacity(sim.fade("near", n) * ui)
            .contentShape(Rectangle())
            .gesture(panGesture(g), including: on ? .all : .none)
            .offset(y: g.nearTop)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("day")
            .accessibilityValue(name)
            .accessibilityAdjustableAction { dir in
                guard on else { return }
                let step = dir == .increment ? 1 : -1
                var p = selIdx + step
                while p >= 0 && p <= 6 {
                    if target(at: p) != nil {
                        sim.springPos(to: Double(p), v0: 0, reduce: reduce)
                        break
                    }
                    p += step
                }
            }
    }

    // MARK: Dial dots, dim, heading, dial gesture, plant

    private func hudLayer(_ g: RCBGeo, _ f: RCBFrame) -> some View {
        let n = f.n
        let ui = sim.fade("ui", n)
        let appear = reduce ? 1.0 : RCBM.cl((n - sim.contT0 - 0.15) / 0.5)
        let nightTop = rcbC(5, 8, 22, 0.5 * f.night * 0.8)
        let hdV = sim.fade("hd", n)
        let hdOff: CGFloat = reduce ? 0 : (mode == .confirm ? CGFloat(-12 * (1 - hdV)) : CGFloat(10 * (1 - hdV)))
        let on = (mode == .time || mode == .home) && canReschedule && !finished && !ended
        let plantOp = sim.fade("plant", n)
        let ptY = g.peakTop + RCBGeo.peakJitter[max(0, min(6, selIdx))] - 44
        return ZStack(alignment: .topLeading) {
            nightTop
                .frame(width: g.vw, height: g.vh)
                .allowsHitTesting(false)
            Canvas { ctx, _ in
                if sim.live && !finished {
                    drawDots(&ctx, g: g, f: f, appear: appear * ui * sim.fade("dots", n))
                }
            }
            .frame(width: g.vw, height: g.vh)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            rcbInk.opacity(f.hp * 0.62)
                .frame(width: g.vw, height: g.vh)
                .allowsHitTesting(false)
            Text(data.heading)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 1)
                .frame(width: max(40, g.vw - 40))
                .offset(x: 20, y: g.hdTop + hdOff)
                .opacity(hdV * ui)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
            Color.clear
                .frame(width: g.vw, height: max(0, g.peakTop - 30))
                .contentShape(Rectangle())
                .gesture(dialGesture(g), including: on ? .all : .none)
                .accessibilityHidden(true)
            RCBPlant(pole: sim.fade("pole", n), pen: sim.fade("pen", n))
                .offset(x: g.cx - 22, y: ptY)
                .opacity(plantOp)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: g.vw, height: g.vh, alignment: .topLeading)
    }

    private func drawDots(_ ctx: inout GraphicsContext, g: RCBGeo, f: RCBFrame, appear: Double) {
        let u = RCBM.cl(f.u + f.nudgeU)
        let sp = g.arc(u)
        let rr = Double((g.rx * g.rx + g.rys * g.rys) / 2).squareRoot()
        let count = max(8, Int((Double.pi * rr / 8.5).rounded()))
        let e = RCBM.ease(appear)
        for i in 0...count {
            let uu = Double(i) / Double(count)
            let p = g.arc(uu)
            if hypot(p.x - sp.x, p.y - sp.y) < 26 { continue }
            if p.y > g.hyS + 26 { continue }
            var a = uu <= u ? 0.85 : 0.34
            if uu < f.dotsFrom { a = 0.12 }
            let r: CGFloat = uu <= u ? 1.9 : 1.5
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color.white.opacity(a * e)))
        }
    }

    // MARK: Controls

    private func controlsLayer(_ g: RCBGeo, _ f: RCBFrame) -> some View {
        let n = f.n
        let ui = sim.fade("ui", n)
        let rm = reduce
        let rowV = sim.fade("row", n)
        let goV = sim.fade("go", n)
        let panelV = sim.fade("panel", n)
        let costV = sim.fade("cost", n)
        let dimV = sim.fade("dimPanel", n)
        let rowOff: CGFloat = rm ? 0 : CGFloat(14 * (1 - rowV))
        let goOff: CGFloat = rm ? 0 : CGFloat(14 * (1 - goV))
        let panelOff: CGFloat = rm ? 0 : CGFloat(10 * (1 - panelV))
        let isHome = mode == .home
        let goBlocked = mode == .time && !f.selOK
        let live = !finished && !ended

        return ZStack(alignment: .topLeading) {
            panel(g, f)
                .frame(width: g.pw, height: g.panelH)
                .brightness(rm ? 0.12 * f.reelPulse : 0)
                .opacity(panelV * (1 - 0.7 * dimV) * ui)
                .offset(x: g.cx - g.pw / 2, y: g.panelTop + panelOff)
                .allowsHitTesting(live && (mode == .time || mode == .home) && canReschedule)

            // cost, in place of the main button while the skip is held
            HStack(spacing: 22) {
                ForEach(data.cost) { c in
                    VStack(spacing: 1) {
                        HStack(spacing: 6) {
                            RCBCostIcon(kind: c.kind)
                            Text(c.big)
                                .font(.system(size: 19, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text(costLabel(c.kind))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(c.text)
                }
            }
            .frame(width: g.vw - 40, height: 52)
            .offset(x: 20, y: g.goTop)
            .opacity(costV * ui)
            .allowsHitTesting(false)

            goButton(g, blocked: goBlocked)
                .frame(width: g.vw - 40, height: 56)
                .offset(x: 20, y: g.goTop + 52 - 56 + goOff)
                .opacity(goV * ui)
                .allowsHitTesting(live && (mode == .time || mode == .home) && goV > 0.5)

            HStack(spacing: 10) {
                if skipFirst {
                    skipButton(f)
                    if hasHome { homeButton(f, active: isHome) }
                } else {
                    if hasHome { homeButton(f, active: isHome) }
                    skipButton(f)
                }
            }
            .frame(width: g.vw - 40, height: 44)
            .offset(x: 20, y: g.rowTop + rowOff)
            .opacity(rowV * ui)
            .allowsHitTesting(live && rowV > 0.5)
        }
        .frame(width: g.vw, height: g.vh, alignment: .topLeading)
    }

    private var skipFirst: Bool {
        guard let s = data.order.firstIndex(of: .skip) else { return false }
        guard hasHome, let h = data.order.firstIndex(of: .home) else { return true }
        return s < h
    }

    private func costLabel(_ k: CantTodayCost.Kind) -> String {
        switch k {
        case .week: return "this week"
        case .row: return "in a row"
        case .streak: return "weeks"
        }
    }

    // MARK: Panel (the reels)

    private func panel(_ g: RCBGeo, _ f: RCBFrame) -> some View {
        let rh = g.rh
        let mask = LinearGradient(stops: [
            Gradient.Stop(color: Color.clear, location: 0),
            Gradient.Stop(color: Color.black, location: 0.24),
            Gradient.Stop(color: Color.black, location: 0.76),
            Gradient.Stop(color: Color.clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(height: rh + 2)
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                CantTodayDrum(
                    count: 12,
                    selection: $hIdx,
                    rowHeight: rh,
                    visibleRows: 3,
                    wraps: true,
                    isBlocked: { _ in false },
                    onBlocked: { _ in },
                    onDetent: { detent() },
                    isInteracting: $hBusy
                ) { idx, dist in
                    RCBReelRow(text: "\(idx + 1)", d: dist, rh: rh,
                               blocked: !isOK(selMin),
                               align: .trailing, anchor: .trailing, small: false, peek: f.reel[0], width: g.cwH)
                }
                .frame(width: g.cwH, height: rh * 3)
                .mask(mask)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("hour")
                .accessibilityValue("\(hIdx + 1)")
                .accessibilityAdjustableAction { dir in adjust(0, dir) }

                Text(":")
                    .font(.system(size: (rh * 0.95).rounded(), weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: g.colon)
                    .offset(y: -2)
                    .accessibilityHidden(true)

                CantTodayDrum(
                    count: 12,
                    selection: $mIdx,
                    rowHeight: rh,
                    visibleRows: 3,
                    wraps: true,
                    isBlocked: { _ in false },
                    onBlocked: { _ in },
                    onDetent: { detent() },
                    isInteracting: $mBusy
                ) { idx, dist in
                    RCBReelRow(text: minuteText(idx), d: dist, rh: rh,
                               blocked: !isOK(selMin),
                               align: .leading, anchor: .leading, small: false, peek: f.reel[1], width: g.cwM)
                }
                .frame(width: g.cwM, height: rh * 3)
                .mask(mask)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("minutes")
                .accessibilityValue(minuteText(mIdx))
                .accessibilityAdjustableAction { dir in adjust(1, dir) }

                CantTodayDrum(
                    count: 2,
                    selection: $aIdx,
                    rowHeight: rh,
                    visibleRows: 3,
                    wraps: false,
                    isBlocked: { _ in false },
                    onBlocked: { _ in },
                    onDetent: { detent() },
                    isInteracting: $aBusy
                ) { idx, dist in
                    RCBReelRow(text: idx == 1 ? "pm" : "am", d: dist, rh: rh,
                               blocked: !isOK(selMin),
                               align: .center, anchor: .center, small: true, peek: f.reel[2], width: g.cwA)
                }
                .frame(width: g.cwA, height: rh * 3)
                .mask(mask)
                .padding(.leading, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("am or pm")
                .accessibilityValue(aIdx == 1 ? "pm" : "am")
                .accessibilityAdjustableAction { dir in adjust(2, dir) }
            }
        }
        .modifier(RCBGlass(shape: RoundedRectangle(cornerRadius: 28, style: .continuous), dark: true))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in panelTouched() }
                .onEnded { _ in nudger.rest(at: sim.now) }
        )
    }

    private func minuteText(_ i: Int) -> String {
        let m = i * 5
        return m < 10 ? "0\(m)" : "\(m)"
    }

    private func adjust(_ which: Int, _ dir: AccessibilityAdjustmentDirection) {
        let up = dir == .increment
        var h = hIdx
        var m = mIdx
        var a = aIdx
        switch which {
        case 0: h = RCBM.mod(h + (up ? 1 : -1), 12)
        case 1: m = RCBM.mod(m + (up ? 1 : -1), 12)
        default: a = RCBM.mod(a + (up ? 1 : -1), 2)
        }
        hIdx = h
        mIdx = m
        aIdx = a
        let total = rcbMinutes(h, m, a)
        if !isOK(total) { blockedTapped(total) }
    }

    private func detent() {
        if CACurrentMediaTime() < sim.quietUntil { return }
        input.haptics.play(.light)
    }

    private func panelTouched() {
        nudger.touched(kind: "reel")
        nudger.cancel()
        if mode == .home && canReschedule {
            input.haptics.play(.rigid)
            setMode(.time)
        }
    }

    private func blockedTapped(_ minutes: Int) {
        input.haptics.play(.soft)
        showNote(blockedText(minutes))
    }

    private func showNote(_ text: String) {
        if text.isEmpty { return }
        noteText = text
        sim.setFade("note", 1, 0.2)
        sim.noteHideAt = sim.now + 1.7
    }

    // MARK: Buttons

    private func goButton(_ g: RCBGeo, blocked: Bool) -> some View {
        let label = mode == .home ? "start \(data.homeMinutes ?? 0) min" : "set alarm"
        return Button {
            goTapped()
        } label: {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(blocked ? Color.white.opacity(0.6) : Color(white: 0.1))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(blocked ? Color.white.opacity(0.28) : Color.white))
        }
        .buttonStyle(RCBPressStyle())
        .accessibilityLabel(label)
    }

    private func homeButton(_ f: RCBFrame, active: Bool) -> some View {
        let act = sim.fade("homeAct", f.n)
        let fg = Color(white: 1 - 0.9 * act)
        let v = f.homeV
        let left = data.homeLeft
        let total = data.homeOf
        let minutes = data.homeMinutes ?? 0
        return Button {
            homeTapped()
        } label: {
            HStack(spacing: 8) {
                RCBHouse().fill(fg).frame(width: 17, height: 15)
                Text("\(minutes)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(fg)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    ForEach(0..<max(0, total), id: \.self) { i in
                        Circle()
                            .strokeBorder(Color(white: 1 - 0.9 * act).opacity(0.75 + 0.25 * act), lineWidth: 1.2)
                            .background(Circle().fill(i < left ? fg : Color.clear))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(Color.white.opacity(act))
                    Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
            }
            .overlay(Capsule().stroke(Color.white.opacity(0.5 * v), lineWidth: 1.5))
            .shadow(color: Color.white.opacity(0.25 * v), radius: 16, x: 0, y: 0)
            .brightness(reduce ? 0.12 * v : 0)
            .scaleEffect(reduce ? 1 : 1 + 0.04 * CGFloat(v))
            .offset(y: reduce ? 0 : CGFloat(-4 * v))
        }
        .buttonStyle(RCBPressStyle(onDown: {
            nudger.touched(kind: "home")
            nudger.cancel()
        }))
        .accessibilityLabel("home workout, \(minutes) minutes, \(left) of \(total) left")
    }

    @ViewBuilder
    private func skipButton(_ f: RCBFrame) -> some View {
        let needsHold = data.skipNeedsHold
        let v = f.skipV
        let fill = max(f.holdP, needsHold && !reduce ? v * 0.25 : 0)
        let label = needsHold ? "hold to skip" : "skip"
        let pill = Text(label)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    Capsule().fill(Color.white.opacity(0.16))
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: geo.size.width * CGFloat(fill))
                    }
                    .clipShape(Capsule())
                    Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
            }
            .overlay(Capsule().stroke(Color.white.opacity(0.5 * v), lineWidth: 1.5))
            .shadow(color: Color.white.opacity(0.25 * v), radius: 16, x: 0, y: 0)
            .brightness(reduce ? 0.12 * v : 0)
            .scaleEffect(reduce ? 1 : 1 + 0.04 * CGFloat(v))
            .offset(y: reduce ? 0 : CGFloat(-4 * v))

        if needsHold {
            pill
                .contentShape(Capsule())
                .cantTodayHold(duration: 1.5,
                               progress: $holdProgress,
                               isHolding: $isHolding,
                               onBegan: { holdBegan() },
                               onComplete: { commitSkip() },
                               onCancel: { costOff() })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "skip") { commitSkip() }
        } else {
            Button {
                skipTapped()
            } label: {
                pill
            }
            .buttonStyle(RCBPressStyle(onDown: {
                input.haptics.play(.soft)
                nudger.touched(kind: "skip")
                nudger.cancel()
            }))
            .accessibilityLabel(label)
        }
    }

    // MARK: Overlay layer (confirm, note, close, entry)

    private func overlayLayer(_ g: RCBGeo, _ f: RCBFrame) -> some View {
        let n = f.n
        let bigV = sim.fade("big", n)
        let noteV = sim.fade("note", n)
        let endV = sim.fade("end", n)
        let entry = input.startsOnReschedule ? 0 : 1 - RCBM.cl(n / 0.6)
        let top = input.layout.safeArea.top + 6
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                Text(bigTitle)
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 1)
                if !bigSub.isEmpty {
                    Text(bigSub)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .frame(width: g.vw - 40)
            .offset(x: 20, y: max(112, g.vh * 0.16))
            .opacity(bigV)
            .allowsHitTesting(false)

            Text(endText)
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: g.vw - 64)
                .offset(x: 32, y: g.vh * 0.42)
                .opacity(endV)
                .allowsHitTesting(false)

            Text(noteText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .modifier(RCBGlass(shape: Capsule(), dark: true))
                .frame(width: g.vw - 128)
                .offset(x: 64, y: top + 5)
                .opacity(noteV * sim.fade("ui", n))
                .allowsHitTesting(false)
                .accessibilityHidden(noteV < 0.5)

            Button {
                closeTapped()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 36, height: 36)
                        .modifier(RCBGlass(shape: Circle()))
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(RCBPressStyle())
            .accessibilityLabel("close")
            .offset(x: g.vw - 12 - 44, y: top)
            .disabled(finished || ended)

            rcbInk.opacity(entry)
                .frame(width: g.vw, height: g.vh)
                .allowsHitTesting(false)
        }
        .frame(width: g.vw, height: g.vh, alignment: .topLeading)
    }

    // MARK: Frame (called once per timeline tick)

    private func makeFrame(_ g: RCBGeo) -> RCBFrame {
        let n = sim.now
        let dt = min(0.05, max(0.001, n - sim.lastNow))
        sim.lastNow = n
        let rm = reduce
        var f = RCBFrame()
        f.n = n

        // the nudge wave: stops at any touch or transition, restarts after the interaction
        let busy = hBusy || mBusy || aBusy
        let calm = sim.live && mode == .time && !sim.panDragging && sim.dialPhase != 1 && !isHolding
            && sim.tapStart < 0 && !sim.finished && !sim.ended && sim.posTarget == nil && !sim.camMoving
            && holdProgress == 0 && !busy
        if !calm {
            nudger.cancel()
            sim.wasCalm = false
        } else {
            if !sim.wasCalm {
                sim.wasCalm = true
                if sim.settled { nudger.rest(at: n) }
            }
            if !sim.settled && n - sim.enterT > 0.5 {
                sim.settled = true
                nudger.settle(at: n)
            }
        }
        func amt(_ id: String) -> Double {
            sim.nudgeIds.contains(id) ? nudger.amount(id, at: n) : 0
        }
        let vSun = amt("sun")
        let vReel0 = amt("reel0")
        let vReel1 = amt("reel1")
        let vReel2 = amt("reel2")
        let vSwipe = amt("swipe")
        let vHome = amt("home")
        let vSkip = amt("skip")
        f.sunV = vSun
        f.swipeV = vSwipe
        f.homeV = vHome
        f.skipV = vSkip
        f.reel = rm ? [0, 0, 0] : [vReel0 * 0.6, vReel1 * 0.6, vReel2 * 0.6]
        f.reelPulse = max(vReel0, max(vReel1, vReel2))
        let sel = max(0, selIdx)
        let tIdx = data.targets.map { $0.weekIndex }.sorted()
        let lastSel = tIdx.last == sel
        f.swipeX = rm ? 0 : vSwipe * 28 * (lastSel ? 1 : -1)
        f.nudgeU = rm ? 0 : vSun * 0.056

        // peaks
        sim.stepPos(dt: min(dt, 0.032))

        // camera: glide in from the pause framing, then follow the swipe
        let farTarget = g.farCam(sim.pos)
        var cam = farTarget
        if sim.camMoving {
            let q = RCBM.cl((n - sim.camT0) / 0.48)
            cam = sim.camFrom.mixed(farTarget, RCBM.ease(q))
            if q >= 1 { sim.camMoving = false }
        }
        f.cam = cam

        // time -> sun
        let usual = Double(data.usualMinutes)
        let usesSel = (mode == .time || mode == .confirm) && canReschedule
        let base = usesSel ? Double(selMin) : usual
        let wT = base + 1440 * ((sim.w - base) / 1440).rounded()
        if rm {
            sim.w = wT
        } else {
            let om = sim.dialPhase == 1 ? 44.0 : 22.0
            let x = sim.w - wT
            sim.sunV += (-om * om * x - 2 * om * sim.sunV) * dt
            sim.w += sim.sunV * dt
            if abs(sim.w - wT) < 0.05 && abs(sim.sunV) < 0.5 {
                sim.w = wT
                sim.sunV = 0
            }
        }
        let u = tm.u(sim.w)
        f.u = u
        f.selOK = mode == .time ? isOK(selMin) : true
        let bt = (mode == .time && !f.selOK) ? 1.0 : 0.0
        sim.blk += (bt - sim.blk) * (rm ? 1 : RCBM.cl(dt * 9))

        // hold / tap to skip
        var holdP = holdProgress
        if sim.tapStart >= 0 {
            let tp = RCBM.cl((n - sim.tapStart) / 0.6)
            holdP = max(holdP, tp)
            if tp >= 1 && !sim.finished {
                sim.tapStart = -1
                sim.tapCommitPending = true
            }
        }
        if sim.skipDoneAt >= 0 {
            holdP = max(holdP, RCBM.cl(sim.skipDoneBase + (n - sim.skipDoneAt) / 0.9))
        }
        f.holdP = holdP
        let hp = rm ? (holdP > 0.02 ? 1.0 : 0.0) : RCBM.ease(holdP)
        f.hp = hp

        let sky = RCBSky(day: tm.dayFraction(sim.w))
        f.cool = sky.cool * 0.9
        f.warm = sky.warm
        f.night = sky.night

        // sun: screen arc -> image px, sunk behind the ridge while holding
        let ap = g.arc(u + f.nudgeU)
        let s = Double(cam.s * g.k)
        var sx = (Double(ap.x) - Double(g.ox) - Double(cam.tx)) / s
        var sy = (Double(ap.y) - Double(g.oy) - Double(cam.ty)) / s
        let rImg = (Double(RCBGeo.sunD) / 2) / s
        let sunk = max(sy, rcbRidgeY(sx) + rImg * 2.3)
        sy += (sunk - sy) * hp
        let q = rm ? 1.0 : RCBM.ease(RCBM.cl((n - sim.contT0) / 0.5))
        let pauseSun = g.pauseSun
        sx = RCBM.lerp(Double(pauseSun.x), sx, q)
        sy = RCBM.lerp(Double(pauseSun.y), sy, q)
        f.sunX = sx
        f.sunY = sy
        f.sunScreenR = 21 * RCBM.lerp(26.0 / 42.0, 1, q)
        f.sunOpacity = 1
        f.sunBright = rm ? vSun : 0
        f.ringOpacity = rm ? 0 : vSun
        f.ringScale = 1 + 0.9 * (rm ? 0 : vSun)

        // the soft sunrise light (skyGlow)
        let fade = 1 - hp
        let rY = rcbRidgeY(sx)
        let d = rY - sy
        let alt = RCBM.cl(d / 280)
        let dawn = exp(-pow((d + 30) / 140, 2))
        let halo = RCBM.cl((d + 20) / 120)
        f.glowX = sx
        f.glowY = sy
        f.ridgeAtSun = rY
        f.dawn = dawn
        f.halo = halo
        f.lift = alt
        f.dayOp = RCBM.cl(dawn * 0.9 + halo * 0.9) * fade
        let fan = RCBM.cl(exp(-pow((d + 25) / 75, 2))) * fade
        f.rayOp = fan * 0.32
        f.rayAngle = rm ? 0 : n * 0.8

        // dial dots dim before the first time that can be chosen today
        if let t = curTarget, t.isToday, let e = todayEarliest {
            f.dotsFrom = tm.u(Double(e))
        }
        return f
    }

    // MARK: Per tick (state changes that follow the frame)

    private func tick(_ g: RCBGeo) {
        let n = sim.now

        if sim.tapCommitPending {
            sim.tapCommitPending = false
            commitSkip()
        }

        // swipe position -> selected day
        if sim.live && canReschedule && (mode == .time || mode == .home) && !sim.finished {
            if let ns = nearestWeekIndex(RCBM.cl(sim.pos, 0, 6)), ns != selIdx {
                if selIdx >= 0 && sim.panDragging { input.haptics.play(.light) }
                selectTarget(ns)
                if !sim.panDragging { input.haptics.play(.rigid) }
            }
        }

        // a time that landed somewhere blocked glides to the nearest one that is not
        if sim.pendingCheck && n - sim.lastChange > 0.16 && !(hBusy || mBusy || aBusy)
            && sim.dialPhase != 1 && mode == .time && sim.posTarget == nil {
            sim.pendingCheck = false
            // The time stays where the user put it (Rishi, 2026-11-25). If it can't be an alarm,
            // it stays dim, the note says why, and "set alarm" waits for a valid time.
            if curTarget != nil && !isOK(selMin) {
                input.haptics.play(.soft)
                showNote(blockedText(selMin))
            }
        }

        if sim.noteHideAt > 0 && n > sim.noteHideAt {
            sim.noteHideAt = 0
            sim.setFade("note", 0, 0.2)
        }
    }

    // MARK: Entering

    private func enterLive(_ g: RCBGeo) {
        guard !sim.live else { return }
        sim.live = true
        let n = sim.now
        let skipIntro = input.startsOnReschedule || reduce
        sim.enterT = n

        if let t = firstTarget, canReschedule {
            sim.pos = Double(t.weekIndex)
            sim.posRaw = sim.pos
            selectTarget(t.weekIndex)
            sim.pendingCheck = false
        }
        let usual = Double(data.usualMinutes)
        sim.w = (skipIntro && canReschedule) ? Double(selMin) : usual
        if skipIntro {
            sim.camMoving = false
            sim.contT0 = -10
        } else {
            sim.camFrom = g.pauseCam
            sim.camT0 = n
            sim.camMoving = true
            sim.contT0 = n
        }

        // what is visible, per mode
        let main = mode == .time || mode == .home
        let items: [(String, Double)] = [
            ("hd", 1), ("row", 1), ("go", main ? 1 : 0), ("panel", main ? 1 : 0),
            ("near", main ? 1 : 0), ("dots", 1), ("ui", 1), ("scrimb", 1),
            ("hm", mode == .home ? 1 : 0), ("dimPanel", mode == .home ? 1 : 0),
            ("homeAct", mode == .home ? 1 : 0)
        ]
        for (k, v) in items {
            if skipIntro {
                sim.jumpFade(k, v)
            } else {
                sim.jumpFade(k, 0)
                sim.setFade(k, v, k == "near" ? 0.45 : (k == "scrimb" ? 0.5 : 0.35))
            }
        }
        if skipIntro { sim.jumpFade("scrimb", 1) }
        if !canReschedule { sim.jumpFade("near", 0) }

        // the wave: items top to bottom
        var list: [(id: String, kind: String, y: CGFloat)] = []
        if canReschedule {
            list.append(("sun", "sun", g.arc(tm.u(usual)).y))
            for i in 0..<3 { list.append(("reel\(i)", "reel", g.panelTop)) }
            if data.targets.count > 1 { list.append(("swipe", "swipe", g.nearTop)) }
        }
        if hasHome { list.append(("home", "home", g.rowTop)) }
        list.append(("skip", "skip", g.rowTop))
        let ordered = list.enumerated().sorted { a, b in
            a.element.y != b.element.y ? a.element.y < b.element.y : a.offset < b.offset
        }.map { $0.element }
        var kinds: [String: String] = [:]
        for it in ordered { kinds[it.id] = it.kind }
        sim.nudgeIds = Set(ordered.map { $0.id })
        nudger.setItems(ordered.map { $0.id }, kinds: kinds)
    }

    // MARK: Modes

    private func setMode(_ m: RCBMode) {
        mode = m
        nudger.cancel()
        let main = m == .time || m == .home
        sim.setFade("go", main ? 1 : 0, 0.3)
        sim.setFade("panel", main ? 1 : 0, 0.35)
        sim.setFade("near", (main && canReschedule) ? 1 : 0, 0.45)
        sim.setFade("hm", m == .home ? 1 : 0, 0.3)
        sim.setFade("dimPanel", m == .home ? 1 : 0, 0.3)
        sim.setFade("homeAct", m == .home ? 1 : 0, 0.15)
        if m != .time { sim.setFade("note", 0, 0.2) }
    }

    private func toTime() {
        if mode == .home && canReschedule {
            input.haptics.play(.rigid)
            setMode(.time)
        }
    }

    // MARK: Time and day

    private func setTime(_ minutes: Int) {
        sim.quietUntil = CACurrentMediaTime() + 0.7
        let mm = RCBM.mod(minutes, 1440)
        let hh = mm / 60
        let mi = Int((Double(mm % 60) / 5).rounded()) % 12
        hIdx = (hh % 12 == 0 ? 12 : hh % 12) - 1
        mIdx = mi
        aIdx = hh >= 12 ? 1 : 0
    }

    /// The time the reels open on for a day (the default, or the nearest valid one).
    private func rcbOpenedMinutes(_ m: Int) -> Int {
        isOK(m) ? m : nearestAllowed(m)
    }

    private func selectTarget(_ idx: Int) {
        guard idx != selIdx, let t = target(at: idx) else { return }
        selIdx = idx
        let m = memo[t.id] ?? t.defaultMinutes
        sim.progrUntil = CACurrentMediaTime() + 0.65
        setTime(m)
        if !isOK(m) { setTime(nearestAllowed(m)) }
        let opened = rcbOpenedMinutes(m)
        if !isOK(opened) { showNote(blockedText(opened)) }
        for d in 0..<7 { sim.setFade("ring\(d)", d == idx ? 1 : 0, 0.2) }
    }

    private func selMinChanged(_ new: Int) {
        sim.lastChange = sim.now
        sim.pendingCheck = true
        if CACurrentMediaTime() > sim.progrUntil, let t = curTarget {
            memo[t.id] = new
        }
    }

    // MARK: Gestures

    private func panGesture(_ g: RCBGeo) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if sim.panPhase == 0 {
                    guard canReschedule, mode == .time || mode == .home, !sim.finished, !sim.ended else {
                        sim.panPhase = 2
                        return
                    }
                    sim.panPhase = 1
                    sim.panMoved = false
                    toTime()
                    sim.panP0 = sim.pos
                    sim.posTarget = nil
                    sim.panDragging = true
                    nudger.touched(kind: "swipe")
                    nudger.cancel()
                }
                guard sim.panPhase == 1 else { return }
                let dx = Double(v.translation.width)
                if abs(dx) > 4 { sim.panMoved = true }
                guard sim.panMoved else { return }
                sim.posRaw = sim.panP0 - dx / Double(g.p)
                sim.pos = RCBM.bound(sim.posRaw)
            }
            .onEnded { v in
                let phase = sim.panPhase
                let moved = sim.panMoved
                sim.panPhase = 0
                sim.panDragging = false
                guard phase == 1 else { return }
                nudger.rest(at: sim.now)
                if !moved {
                    // tap on a peak: roll to it
                    let lx = Double(v.location.x) + sim.pos * Double(g.p) - Double(g.vw) / 2
                    let idx = Int((lx / Double(g.p)).rounded())
                    if idx >= 0 && idx <= 6 && target(at: idx) != nil && abs(lx - Double(idx) * Double(g.p)) < Double(g.p) * 0.5 {
                        sim.springPos(to: Double(idx), v0: 0, reduce: reduce)
                    }
                    return
                }
                let vel = -Double(v.velocity.width) / Double(g.p)
                let proj = vel * 0.2
                let tgt = nearestWeekIndex(RCBM.cl(sim.pos + proj, 0, 6)) ?? 0
                sim.springPos(to: Double(tgt), v0: RCBM.cl(vel, -12, 12), reduce: reduce)
            }
    }

    private func dialGesture(_ g: RCBGeo) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if sim.dialPhase == 0 {
                    guard canReschedule, mode == .time || mode == .home, !sim.finished, !sim.ended else {
                        sim.dialPhase = 2
                        return
                    }
                    let x = v.startLocation.x
                    let y = v.startLocation.y
                    let nx = (x - g.cx) / g.rx
                    let ny = (y - g.hyS) / g.ry
                    let rr = Double(hypot(nx, ny))
                    let uSun = tm.u(sim.w)
                    let sp = g.arc(uSun)
                    let nearSun = hypot(x - sp.x, y - sp.y) < 34
                    let onArch = abs(rr - 1) < Double(40 / min(g.rx, g.ry)) && y < g.hyS + 28
                    if !nearSun && !onArch {
                        sim.dialPhase = 2
                        return
                    }
                    sim.dialPhase = 1
                    toTime()
                    sim.posTarget = nil
                    let up = g.uFromPoint(x, y)
                    sim.dialDU0 = nearSun ? up - uSun : 0
                    sim.dialLastQ = -1
                    nudger.touched(kind: "sun")
                    nudger.cancel()
                }
                guard sim.dialPhase == 1 else { return }
                dialMove(g, v.location.x, v.location.y)
            }
            .onEnded { _ in
                let phase = sim.dialPhase
                sim.dialPhase = 0
                if phase == 1 {
                    sim.lastChange = sim.now
                    sim.pendingCheck = true
                    nudger.rest(at: sim.now)
                }
            }
    }

    private func dialMove(_ g: RCBGeo, _ x: CGFloat, _ y: CGFloat) {
        let u = g.uFromPoint(x, y) - sim.dialDU0
        let t = tm.minOfU(u)
        setTime(t)
        sim.lastChange = sim.now
        sim.pendingCheck = true
        let q = t / 15
        if q != sim.dialLastQ {
            if sim.dialLastQ != -1 { input.haptics.play(.light) }
            sim.dialLastQ = q
        }
    }

    // MARK: Doors

    private func goTapped() {
        if sim.finished || sim.ended { return }
        if mode == .time {
            guard canReschedule, curTarget != nil else { return }
            if !isOK(selMin) {
                input.haptics.play(.rigid)
                return
            }
            answerReschedule()
        } else if mode == .home {
            answerHome()
        }
    }

    private func homeTapped() {
        if sim.finished || sim.ended { return }
        input.haptics.play(.rigid)
        if mode == .home {
            if canReschedule { setMode(.time) }
        } else {
            setMode(.home)
        }
    }

    private func skipTapped() {
        if sim.finished || sim.ended || sim.tapStart >= 0 { return }
        sim.tapStart = sim.now
        nudger.cancel()
    }

    private func holdBegan() {
        if sim.finished || sim.ended { return }
        input.haptics.play(.soft)
        nudger.touched(kind: "skip")
        nudger.cancel()
        sim.setFade("cost", 1, 0.22)
        sim.setFade("go", 0, 0.3)
    }

    private func costOff() {
        sim.setFade("cost", 0, 0.22)
        if !sim.finished && !sim.ended && (mode == .time || mode == .home) {
            sim.setFade("go", 1, 0.3)
        }
    }

    private func later(_ seconds: Double, _ work: @escaping () -> Void) {
        if seconds <= 0 {
            work()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { work() }
        }
    }

    /// everything that is on screen leaves, the world stays
    private func clearChrome() {
        sim.setFade("hd", 0, 0.25)
        sim.setFade("row", 0, 0.3)
        sim.setFade("go", 0, 0.3)
        sim.setFade("panel", 0, 0.35)
        sim.setFade("note", 0, 0.2)
        sim.setFade("cost", 0, 0.2)
    }

    private func answerReschedule() {
        guard !sim.finished, let t = curTarget else { return }
        let minutes = selMin
        guard isOK(minutes) else { return }
        sim.finished = true
        finished = true
        input.haptics.play(.heavy)
        nudger.cancel()
        mode = .confirm
        clearChrome()
        let rm = reduce
        sim.setFade("others", 1, 0.3)
        let label = "\(dyName) · \(CantTodayClock.text(minutes))"
        later(rm ? 0 : 0.42) {
            sim.setFade("hideSel", 1, 0.3)
            sim.jumpFade("plant", 1)
            sim.setFade("pole", 1, rm ? 0.01 : 0.26)
            sim.setFade("pen", 1, rm ? 0.01 : 0.26, delay: rm ? 0 : 0.22)
            input.haptics.play(.soft)
        }
        later(rm ? 0 : 0.56) {
            bigTitle = label
            bigSub = "alarm set"
            sim.setFade("big", 1, 0.45)
        }
        let day = t.day
        later(0.45) {
            input.actions.reschedule(day, CantTodayClock.timeOfDay(minutes))
        }
    }

    private func answerHome() {
        guard !sim.finished else { return }
        sim.finished = true
        finished = true
        input.haptics.play(.heavy)
        nudger.cancel()
        mode = .confirm
        clearChrome()
        sim.setFade("near", 0, 0.35)
        let minutes = data.homeMinutes ?? 0
        later(0.2) {
            bigTitle = "home workout"
            bigSub = "\(minutes) min"
            sim.setFade("big", 1, 0.45)
        }
        later(0.45) {
            input.actions.homeWorkout()
        }
    }

    private func commitSkip() {
        guard !sim.finished, !sim.ended else { return }
        sim.finished = true
        finished = true
        input.haptics.play(.heavy)
        nudger.cancel()
        mode = .confirm
        sim.skipDoneBase = max(holdProgress, 0)
        sim.skipDoneAt = sim.now
        clearChrome()
        sim.setFade("near", 0, 0.35)
        later(0.35) {
            bigTitle = "skipped"
            bigSub = ""
            sim.setFade("big", 1, 0.45)
        }
        later(0.45) {
            input.actions.skip()
        }
    }

    private func closeTapped() {
        if sim.finished || sim.ended { return }
        sim.ended = true
        ended = true
        input.haptics.play(.heavy)
        nudger.cancel()
        sim.setFade("ui", 0, 0.4)
        endText = "closed. still going."
        sim.setFade("end", 1, 0.5)
        later(0.45) {
            input.actions.close()
        }
    }
}
