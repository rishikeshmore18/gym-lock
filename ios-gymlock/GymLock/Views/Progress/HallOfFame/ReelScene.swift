import SwiftUI
import QuartzCore

// MARK: - Public contract (CONTRACT.md section B)

/// Intro timeline in seconds from open. Values copied from src.html
/// (`T_YAW0`, `T_ROLL0`, `T_BL0`, `INTRO`, `T0`, `GL0`, `REV + OUTR`).
nonisolated enum ReelTimeline {
    static let rollInEnd: Double = 1.02        // T_YAW0: 2D roll-in settled, hand-off to the 3D scene
    static let yawEnd: Double = 1.67           // T_ROLL0: yaw + pitch finished, roll toward camera begins
    static let rollEnd: Double = 2.70          // T_BL0: constant-deceleration blend to scroll 0 begins
    static let blendEnd: Double = 3.50         // INTRO: strip is live after this
    static let titleStart: Double = 1.0        // T0
    static let titleGlideStart: Double = 2.7   // GL0
    static let total: Double = blendEnd
    static let closeTotal: Double = 2.3        // REV 1700 ms + OUTR 600 ms
}

nonisolated struct ReelLayout: Equatable, Sendable {
    let size: CGSize                      // screen
    let safeTop: CGFloat
    let stripWidth: CGFloat               // min(330, size.width * 0.84), even-pixel rule from src
    let stripTop: CGFloat                 // scroll-0 top of the film, under the title (src `S`)
}

nonisolated struct ReelEvents: OptionSet, Sendable {
    let rawValue: Int
    static let reelLanded = ReelEvents(rawValue: 1 << 0)
    static let titleComplete = ReelEvents(rawValue: 1 << 1)
    static let revolution1 = ReelEvents(rawValue: 1 << 2)
    static let revolution2 = ReelEvents(rawValue: 1 << 3)
    static let revolution3 = ReelEvents(rawValue: 1 << 4)
    static let stripSeated = ReelEvents(rawValue: 1 << 5)
}

nonisolated struct ReelPose: Sendable {
    let t: Double
    let reelVisible: Bool
    /// Applied to the strip content (a view the size of the stage, origin top-left, e.g. `.transformEffect`).
    /// Matrix order, CATransform3D row-vector convention (`Concat(a, b)` = a first, then b), which is the
    /// CSS chain `perspective(900) @ (cx,cy)` of the parent and `translate3d(0,AY,AZ) rotateX(pi/2-al) translate3d(0,-S,0)`
    /// of the scroller (transform-origin 0 0), applied right to left on a point:
    ///   1. translate(0, -S, 0)
    ///   2. rotateX(pi/2 - al)
    ///   3. translate(0, AY, AZ)
    ///   4. translate(-cx, -cy, 0)
    ///   5. perspective, m34 = -1/900
    ///   6. translate(cx, cy, 0)
    /// Identity when t >= blendEnd.
    let floorTransform: ProjectionTransform
    /// Laid film length in strip points, clipped from the top (src `Lc`). 0 = hidden, .infinity = live.
    let filmClipLength: CGFloat
    /// 0...1 linear over [titleStart, 1.73 s] (src `T0`...`TDONE`). In `closePose` it runs 1 -> 0 over 0.3 s (the src title fade).
    let titleProgress: Double
    /// 0...1, ALREADY eased with src `settle` over 0.5 s from `titleGlideStart`. Use as is.
    let titleGlide: Double
    let chromeOpacity: Double
    let events: ReelEvents
}

nonisolated enum ReelScene {
    static func pose(at t: Double, layout: ReelLayout) -> ReelPose {
        let g = ReelGeo(layout)
        let tm = max(0, t) * 1000
        let tr = g.revolutionTimes
        var ev: ReelEvents = []
        if tm >= ReelMath.landedMs { ev.insert(.reelLanded) }
        if tm >= ReelMath.titleDoneMs { ev.insert(.titleComplete) }
        if tr.0 <= tm { ev.insert(.revolution1) }
        if tr.1 <= tm { ev.insert(.revolution2) }
        if tr.2 <= tm { ev.insert(.revolution3) }
        if tm >= ReelMath.intro { ev.insert(.stripSeated) }
        let (ft, clip) = ReelMath.floorState(atMs: tm, geo: g)
        let tp = ReelMath.clamp((tm - ReelMath.t0) / (ReelMath.titleDoneMs - ReelMath.t0), 0, 1)
        let gl = ReelMath.settle(ReelMath.clamp((tm - ReelMath.gl0) / 500, 0, 1))
        return ReelPose(t: t, reelVisible: tm < ReelMath.intro, floorTransform: ft, filmClipLength: clip,
                        titleProgress: tp, titleGlide: gl,
                        chromeOpacity: tm >= ReelMath.intro ? 1 : 0, events: ev)
    }

    /// Height the strip box must have while it lies on the floor (src `HBOX`).
    /// The laid film is far longer than the screen during the intro, and a
    /// ScrollView clips to its own frame, so the screen enlarges the box to
    /// this height until the strip is live, then restores the screen height.
    static func introBoxHeight(layout: ReelLayout) -> CGFloat {
        CGFloat(ReelGeo(layout).hbox)
    }

    /// Exact reverse (smoothstep over 1.7 s from the live strip back to the pre-yaw state), then the 2D roll-out (0.6 s).
    static func closePose(at t: Double, layout: ReelLayout) -> ReelPose {
        let g = ReelGeo(layout)
        let tm = max(0, t) * 1000
        let tf = ReelMath.reverseTime(tm)
        let (ft, clip) = ReelMath.floorState(atMs: tf, geo: g)
        let fade = 1 - ReelMath.clamp(tm / 300, 0, 1)
        let chrome = 1 - ReelMath.clamp(tm / 200, 0, 1)
        return ReelPose(t: t, reelVisible: true, floorTransform: ft, filmClipLength: clip,
                        titleProgress: fade, titleGlide: 1, chromeOpacity: chrome, events: [])
    }
}

// MARK: - Internal engine shared with ReelCanvas (not part of the contract)

nonisolated struct Bez: Sendable {
    let ax, bx, cx, ay, by, cy: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }
    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<10 {
            let e = ((ax * t + bx) * t + cx) * t - x
            if abs(e) < 1e-5 { break }
            let d = (3 * ax * t + 2 * bx) * t + cx
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        return ((ay * t + by) * t + cy) * t
    }
}

nonisolated enum ReelMath {
    static let p3 = 900.0
    static let r = 95.0                       // 2D reel radius
    static let alpha0 = 26.0 * Double.pi / 180
    static let psi1 = 84.0 * Double.pi / 180
    static let tYaw0 = 1020.0, tRoll0 = 1670.0, tBl0 = 2700.0, intro = 3500.0, bld = 800.0, xf = 80.0
    static let rev = 1700.0, outr = 600.0
    static let tb = tYaw0 - xf
    static let t0 = 1000.0, gl0 = 2700.0, titleDoneMs = 1730.0, landedMs = 900.0
    static let settle = Bez(0.22, 0.9, 0.24, 1)
    static let turn = Bez(0.2, 0.85, 0.2, 1)
    static let easeIn = Bez(0.5, 0, 0.9, 0.6)
    static let ble = Bez(0.42, 0, 0.2, 1)
    static let lv: (Double, Double, Double) = {
        let x = -0.35, y = -0.75, z = 0.55, n = (x * x + y * y + z * z).squareRoot()
        return (x / n, y / n, z / n)
    }()

    static func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { v < a ? a : (v > b ? b : v) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Forward time (ms) that the close reverse maps onto. t >= rev: roll-out, returns `tb`.
    static func reverseTime(_ tm: Double) -> Double {
        if tm >= rev { return tb }
        let u = tm / rev, e = u * u * (3 - 2 * u)
        return intro - (intro - tb) * e
    }

    static func rollX(_ t: Double, _ g: ReelGeo) -> Double {
        let u = clamp(t / 900, 0, 1)
        var x = lerp(g.startX, g.cx, settle(u))
        if t > 420 { x -= 6 * sin(Double.pi * clamp((t - 420) / 600, 0, 1)) }
        return x
    }

    /// Distance rolled along the floor (src `d`).
    static func travel(_ t: Double, _ g: ReelGeo) -> Double {
        if t <= tRoll0 { return 0 }
        let u = clamp((t - tRoll0) / (tBl0 - tRoll0), 0, 1)
        var d = g.d1 * u * u
        if t > tBl0 {
            let tau = t - tBl0, v0 = 2 * g.d1 / (tBl0 - tRoll0)
            d = g.d1 + v0 * tau - 0.5 * (v0 * 0.4 / bld) * tau * tau
        }
        return d
    }

    /// Floor transform and clip length for a forward time (ms).
    static func floorState(atMs t: Double, geo g: ReelGeo) -> (ProjectionTransform, CGFloat) {
        if t >= intro { return (ProjectionTransform(CATransform3DIdentity), .infinity) }
        let s = ReelScene3D.at(t, g)
        var m = CATransform3DMakeTranslation(0, -g.s, 0)
        m = CATransform3DConcat(m, CATransform3DMakeRotation(CGFloat(Double.pi / 2 - s.al), 1, 0, 0))
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(0, CGFloat(s.ay), CGFloat(s.az)))
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(CGFloat(-g.cx), CGFloat(-g.cy), 0))
        var persp = CATransform3DIdentity
        persp.m34 = CGFloat(-1 / p3)
        m = CATransform3DConcat(m, persp)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(CGFloat(g.cx), CGFloat(g.cy), 0))
        return (ProjectionTransform(m), s.lc > 0.5 ? CGFloat(s.lc) : 0)
    }
}

/// Geometry constants for a layout (src `geo()`, `measure()`).
nonisolated struct ReelGeo: Sendable {
    let w, h, cx, cy, s, stripW: Double
    let rr, hhw, th, s0, zc0, ay0, az0, sa0, ayp0, d1, hbox, startX: Double

    init(_ l: ReelLayout) {
        let P3 = ReelMath.p3, R = ReelMath.r
        w = Double(l.size.width); h = Double(l.size.height)
        cx = w / 2; cy = h / 2
        s = Double(l.stripTop); stripW = Double(l.stripWidth)
        let RR = 1.8 * stripW
        rr = RR
        hhw = stripW / 2 + 3
        th = 0.054 * stripW
        let S0 = R / RR
        s0 = S0
        let ZC0 = (P3 - P3 / S0) - (hhw + th)
        zc0 = ZC0
        let ca = cos(ReelMath.alpha0), sa = sin(ReelMath.alpha0)
        let AY0 = cy + RR * ca, AZ0 = ZC0 - RR * sa
        ay0 = AY0; az0 = AZ0
        let SA0 = P3 / (P3 - AZ0)
        sa0 = SA0
        ayp0 = cy + (AY0 - cy) * SA0
        var lo = 0.0, hi = (P3 - 250 - AZ0) / ca
        for _ in 0..<40 {
            let m = (lo + hi) / 2
            let y = cy + (RR * ca + m * sa) * P3 / (P3 - (AZ0 + m * ca))
            if y < h { lo = m } else { hi = m }
        }
        d1 = lo
        hbox = s + lo * 1.12 + 160
        startX = w + R + 60
    }

    /// Times (ms) at which the reel has turned 1, 2, 3 full revolutions while rolling toward the camera (infinity: never).
    var revolutionTimes: (Double, Double, Double) {
        func solve(_ k: Double) -> Double {
            let target = 2 * Double.pi * k * rr
            if ReelMath.travel(ReelMath.intro, self) < target { return .infinity }
            var lo = ReelMath.tRoll0, hi = ReelMath.intro
            for _ in 0..<40 {
                let m = (lo + hi) / 2
                if ReelMath.travel(m, self) < target { lo = m } else { hi = m }
            }
            return hi
        }
        return (solve(1), solve(2), solve(3))
    }
}

/// 3D reel state (src `SC`, `sceneAt`).
nonisolated struct ReelScene3D: Sendable {
    var psi = 0.0, d = 0.0, al = 0.0, rw = 78.0, spin = 0.0, ay = 0.0, az = 0.0, lc = 0.0
    var cX = 0.0, cY = 0.0, cZ = 0.0, dx = 0.0
    var cp = 1.0, sp = 0.0, ca = 1.0, sa = 0.0
    var m00 = 1.0, m01 = 0.0, m02 = 0.0, m10 = 0.0, m11 = 1.0, m12 = 0.0, m20 = 0.0, m21 = 0.0, m22 = 1.0

    static func at(_ t: Double, _ g: ReelGeo) -> ReelScene3D {
        var s = ReelScene3D()
        let M = ReelMath.self
        let ys = M.settle(M.clamp((t - M.tYaw0) / (M.tRoll0 - M.tYaw0), 0, 1))
        var e = 0.0
        s.psi = M.psi1 * ys
        let alp = M.alpha0 * ys
        let d = M.travel(t, g)
        if t > M.tBl0 { e = M.ble(M.clamp((t - M.tBl0) / M.bld, 0, 1)) }
        s.d = d
        let dxs = t < M.tYaw0 ? M.rollX(t, g) - g.cx : 0
        s.al = alp + (Double.pi / 2 - alp) * e
        let ca = cos(s.al), sa = sin(s.al)
        let AY: Double, AZ: Double
        if e > 0 {
            let sA = g.sa0 * pow(1 / g.sa0, e)
            let ayp = M.lerp(g.ayp0, g.s, e)
            AZ = M.p3 - M.p3 / sA
            AY = g.cy + (ayp - g.cy) / sA
        } else {
            AY = g.cy + g.rr * cos(alp)
            AZ = g.zc0 - g.rr * sin(alp)
        }
        s.ay = AY; s.az = AZ; s.dx = dxs / g.s0
        s.rw = g.rr * max(0.16, 0.6724 - d * 0.000134).squareRoot()
        s.spin = -(g.startX - (g.cx + dxs)) / M.r - d / g.rr
        let cp = cos(s.psi), sp = sin(s.psi)
        s.cp = cp; s.sp = sp; s.ca = ca; s.sa = sa
        s.m00 = cp; s.m01 = 0; s.m02 = sp
        s.m10 = -sa * sp; s.m11 = ca; s.m12 = sa * cp
        s.m20 = -ca * sp; s.m21 = -sa; s.m22 = ca * cp
        s.cX = g.cx + s.dx; s.cY = AY - g.rr * ca + d * sa; s.cZ = AZ + g.rr * sa + d * ca
        s.lc = min(d, g.hbox - g.s - 6, s.al > 1.5 ? 1e9 : (850 - AZ) / max(ca, 0.02))
        return s
    }
}
