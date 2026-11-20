import SwiftUI

/// Draws the reel (2D roll-in reel, its trailing tail, the 3D reel, the floor shadow) for a time.
/// Ridge: smooth vector shapes (even-odd cut-outs, painter's order). Matrix: dot board sampled from the same geometry, dot count capped ~3000.
/// The canvas is `layout.size` points, origin at the stage's top-left (it ignores safe areas, so place it on a full-screen stage).
struct ReelCanvas: View {
    let t: Double
    let isClosing: Bool
    let style: HeroCardStyle
    let layout: ReelLayout

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            ReelDrawer.draw(&context, t: t, isClosing: isClosing, style: style, layout: layout)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Palette (light theme only)

private nonisolated enum ReelPalette {
    static let on = (26.0, 26.0, 26.0)
    static let off = (226.0, 224.0, 219.0)
    static let buckets = 6                       // brightness buckets: indices 0...5

    static func grey(_ g: Double) -> Color {
        let v = g < 0 ? 0 : (g > 255 ? 255 : g.rounded(.down))
        return Color(white: v / 255)
    }
    /// Dot colour for bucket `l` of 0...5 (src `C.lv`, 7 levels folded to 6).
    static func level(_ l: Int) -> Color {
        let k = Double(l) / Double(buckets - 1)
        func m(_ a: Double, _ b: Double) -> Double { (a + (b - a) * k).rounded() / 255 }
        return Color(red: m(off.0, on.0), green: m(off.1, on.1), blue: m(off.2, on.2))
    }
    static let levels: [Color] = (0..<buckets).map { level($0) }
    static let shade = Color.black.opacity(0.30)
    @MainActor static let ink = Theme.ink
    @MainActor static let bg = Theme.canvas
    static let outline = grey(42)                // reel outline (src `ol`, light)
    static let reelLine = grey(42)               // --reel-line, light (#2a2a2a)
}

/// Unit geometry computed once (src `HOLES`, `HUB`, ring radii).
private nonisolated enum ReelUnit {
    static let holes: [(Double, Double)] = (0..<6).map { k in
        let a = Double(k) * Double.pi / 3 + Double.pi / 6
        return (cos(a) * 57, sin(a) * 57)
    }
    static let hub: [(Double, Double)] = (0..<6).map { k in
        let a = Double(k) * Double.pi / 3 + Double.pi / 6
        return (cos(a + Double.pi / 6) * 16.5, sin(a + Double.pi / 6) * 16.5)
    }
    static let holeAngle: [Double] = holes.map { atan2($0.1, $0.0) }

    static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    /// Six cut-outs of the 2D reel (r 19.5) for clipping.
    static let holeClip: Path = {
        var p = Path()
        for h in holes { p.addEllipse(in: CGRect(x: h.0 - 19.5, y: h.1 - 19.5, width: 39, height: 39)) }
        return p
    }()
    static let rim2D: [Path] = holes.map { circle($0.0, $0.1, 21) }
    static let hubHoles2D: [Path] = hub.map { circle($0.0, $0.1, 3.6) }
    static let disc94 = circle(0, 0, 94)
    static let disc85 = circle(0, 0, 85)
    static let disc78 = circle(0, 0, 78)
    static let disc31 = circle(0, 0, 31)
    static let disc5_6 = circle(0, 0, 5.6)
    static let wallRect = Path(CGRect(x: -90, y: -90, width: 180, height: 180))
    /// Ring radii with their shade (src: i from 36 to 78 step 2.6).
    static let rings: [(r: Double, dark: Bool)] = {
        var out: [(Double, Bool)] = []
        var i = 36.0
        while i <= 78.0001 {
            out.append((i, (Int((i / 2.6).rounded()) % 2) == 0))   // odd -> #3b3b3b, even -> #0e0e0e
            i += 2.6
        }
        return out.map { (r: $0.0, dark: $0.1) }
    }()
    static let ringPaths: [Path] = rings.map { circle(0, 0, $0.r) }
}

// MARK: - Drawer

nonisolated enum ReelDrawer {
    typealias M = ReelMath

    static func draw(_ ctx: inout GraphicsContext, t: Double, isClosing: Bool, style: HeroCardStyle, layout: ReelLayout) {
        let g = ReelGeo(layout)
        let tm = max(0, t) * 1000
        if !isClosing {
            if tm >= M.intro { return }
            frame(&ctx, tm, g, style)
        } else if tm < M.rev {
            frame(&ctx, M.reverseTime(tm), g, style)
        } else {
            let tt = tm - M.rev
            let x = M.lerp(g.cx, g.startX, M.easeIn(M.clamp(tt / M.outr, 0, 1)))
            let x8 = M.lerp(g.cx, g.startX, M.easeIn(M.clamp((tt + 8) / M.outr, 0, 1)))
            let vx = (x8 - x) / 8 * 1000
            roll2D(&ctx, x: x, op: 1, g: g, style: style)
            tail(&ctx, x: x, vx: vx, t: tt, alpha: 1, dir: -1, g: g, style: style)
        }
    }

    /// src `renderFrame`.
    static func frame(_ ctx: inout GraphicsContext, _ t: Double, _ g: ReelGeo, _ style: HeroCardStyle) {
        let ramp = M.clamp((t - (M.tYaw0 - M.xf)) / M.xf, 0, 1)
        if ramp < 1 {
            let x = M.rollX(min(t, M.tYaw0), g)
            let vx = (M.rollX(t + 8, g) - M.rollX(t, g)) / 8 * 1000
            roll2D(&ctx, x: x, op: 1 - ramp, g: g, style: style)
            tail(&ctx, x: x, vx: vx, t: t, alpha: 1 - ramp, dir: 1, g: g, style: style)
        }
        if ramp > 0 { render3D(&ctx, t, g, style) }
    }

    // MARK: 2D roll-in reel + shadow (src `set2D`)

    static func roll2D(_ ctx: inout GraphicsContext, x: Double, op: Double, g: ReelGeo, style: HeroCardStyle) {
        let ang = -(g.startX - x) / M.r
        ctx.drawLayer { l in
            l.opacity = op
            // Floor shadow: 190 x 22 ellipse, radial shade -> clear at 70 %.
            var sh = l
            sh.translateBy(x: x, y: g.cy + M.r + 1)
            sh.scaleBy(x: 1, y: 22.0 / 190.0)
            let rad = 95.0 * 2.0.squareRoot()
            sh.fill(Path(ellipseIn: CGRect(x: -rad, y: -rad, width: 2 * rad, height: 2 * rad)),
                    with: .radialGradient(Gradient(stops: [.init(color: ReelPalette.shade, location: 0),
                                                           .init(color: ReelPalette.shade.opacity(0), location: 0.7)]),
                                          center: .zero, startRadius: 0, endRadius: rad))
            if style == .matrix { matrix2D(&l, x: x, cy: g.cy, angle: ang) }
            else { ridge2D(&l, x: x, cy: g.cy, angle: ang) }
        }
    }

    /// src `reelBright`.
    static func reelBright(_ lx: Double, _ ly: Double, _ gx: Double, _ gy: Double, rw: Double) -> Double {
        let R = M.r
        let r = (lx * lx + ly * ly).squareRoot()
        let sh = 0.5 + 0.5 * M.clamp((-gx - gy) / (R * 1.3), -1, 1)
        if r > R - 0.5 { return 0 }
        if r < 30 {
            if r < 6 { return 0.04 }
            for k in 0..<6 where hypot(lx - ReelUnit.hub[k].0, ly - ReelUnit.hub[k].1) < 3.8 { return 0.06 }
            return 0.86 + 0.14 * sh
        }
        if r < 33 { return 0.3 }
        for k in 0..<6 {
            let d = hypot(lx - ReelUnit.holes[k].0, ly - ReelUnit.holes[k].1)
            if d < 20.5 {
                if d > 18.2 { return 0.62 }
                if r > rw { return 0 }
                return (Int(floor(r / 3.4)) % 2 != 0) ? 0.2 : 0.05
            }
        }
        if r > 87 { return 0.98 }
        if r > 82 { return 0.4 }
        return 0.8 + 0.2 * sh
    }

    /// src `drawMatrix(angle, 1, 0, 0, true, 78)`: dot lattice, one Path per brightness bucket.
    static func matrix2D(_ ctx: inout GraphicsContext, x: Double, cy: Double, angle: Double) {
        let R = M.r, c = 6.0, n = Int(ceil(R / c)) + 1
        let ca = cos(angle), sa = sin(angle)
        let lim = (R + 1.5) * (R + 1.5)
        var paths = [Path](repeating: Path(), count: ReelPalette.buckets)
        let top = Double(ReelPalette.buckets - 1)
        for iy in -n...n {
            for ix in -n...n {
                let gx = Double(ix) * c, gy = Double(iy) * c
                if gx * gx + gy * gy > lim { continue }
                let lx = gx * ca + gy * sa, ly = -gx * sa + gy * ca
                let b = reelBright(lx, ly, gx, gy, rw: 78)
                let idx = Int((b * top).rounded())
                let rad = 1.25 + 0.85 * Double(idx) / top
                paths[idx].addEllipse(in: CGRect(x: x + gx - rad, y: cy + gy - rad, width: 2 * rad, height: 2 * rad))
            }
        }
        ctx.fill(ReelUnit.circle(x, cy, R + 3), with: .color(ReelPalette.bg))
        for l in 0..<paths.count where !paths[l].isEmpty { ctx.fill(paths[l], with: .color(ReelPalette.levels[l])) }
    }

    /// src SVG reel (`reelR`) without the turbulence wash; the edge is softened with a 0.6 blur on the outlines.
    static func ridge2D(_ ctx: inout GraphicsContext, x: Double, cy: Double, angle: Double) {
        var l = ctx
        l.translateBy(x: x, y: cy)
        l.rotate(by: .radians(angle))
        let mt = Gradient(stops: [.init(color: ReelPalette.grey(243), location: 0), .init(color: ReelPalette.grey(188), location: 0.42),
                                  .init(color: ReelPalette.grey(228), location: 0.72), .init(color: ReelPalette.grey(140), location: 1)])
        let mw = Gradient(stops: [.init(color: Color.white.opacity(0.55), location: 0), .init(color: Color.black.opacity(0.12), location: 1)])
        l.fill(ReelUnit.disc94, with: .linearGradient(mt, startPoint: CGPoint(x: -94, y: -94), endPoint: CGPoint(x: 94, y: 94)))
        l.fill(ReelUnit.disc94, with: .radialGradient(mw, center: CGPoint(x: -28.2, y: -37.6), startRadius: 0, endRadius: 150.4))
        l.stroke(ReelUnit.disc85, with: .color(ReelPalette.grey(123).opacity(0.55)), lineWidth: 1.2)
        for p in ReelUnit.rim2D {
            l.fill(p, with: .color(ReelPalette.grey(189)))
            l.stroke(p, with: .color(ReelPalette.grey(111)), lineWidth: 1)
        }
        l.drawLayer { h in
            h.clip(to: ReelUnit.holeClip)
            h.fill(ReelUnit.wallRect, with: .color(ReelPalette.grey(180)))
            h.clip(to: ReelUnit.disc78)
            h.fill(ReelUnit.wallRect, with: .color(ReelPalette.grey(20)))
            for (i, ring) in ReelUnit.rings.enumerated() {
                h.stroke(ReelUnit.ringPaths[i], with: .color(ReelPalette.grey(ring.dark ? 14 : 59)), lineWidth: 1.5)
            }
        }
        l.fill(ReelUnit.disc31, with: .linearGradient(mt, startPoint: CGPoint(x: -31, y: -31), endPoint: CGPoint(x: 31, y: 31)))
        l.fill(ReelUnit.disc31, with: .radialGradient(mw, center: CGPoint(x: -9.3, y: -12.4), startRadius: 0, endRadius: 49.6))
        for p in ReelUnit.hubHoles2D { l.fill(p, with: .color(ReelPalette.grey(29))) }
        l.fill(ReelUnit.disc5_6, with: .color(ReelPalette.grey(34)))
        l.drawLayer { e in
            e.addFilter(.blur(radius: 0.6))
            e.stroke(ReelUnit.disc94, with: .color(ReelPalette.reelLine), lineWidth: 2.4)
            e.stroke(ReelUnit.disc31, with: .color(ReelPalette.reelLine), lineWidth: 2)
        }
    }

    // MARK: Tail (src `drawTail`)

    static func tail(_ ctx: inout GraphicsContext, x: Double, vx: Double, t: Double, alpha: Double, dir: Double, g: ReelGeo, style: HeroCardStyle) {
        if alpha < 0.02 { return }
        let TY = 60.0, L = 118.0, N = 26
        let amp = 1.1 + min(1, abs(vx) / 1400) * 5.5
        var pts: [CGPoint] = []
        pts.reserveCapacity(N + 1)
        for k in 0...N {
            let s = Double(k) * L / Double(N)
            let px = x + dir * (12 + s)
            let py = TY - 4.5 - sin(s / 17 - t / 85) * amp * (s / L) - max(0, 1 - s / 28) * 1.5
            pts.append(CGPoint(x: px, y: py))
        }
        ctx.drawLayer { l in
            l.opacity = alpha
            l.translateBy(x: 0, y: g.cy + M.r - TY)
            if style == .matrix {
                var dots = Path()
                var acc = 0.0
                for i in 1..<pts.count {
                    let p0 = pts[i - 1], p1 = pts[i]
                    let seg = hypot(p1.x - p0.x, p1.y - p0.y)
                    while acc < seg {
                        let u = acc / seg
                        let px = M.lerp(p0.x, p1.x, u), py = M.lerp(p0.y, p1.y, u)
                        for row in [-1.0, 1.0] {
                            dots.addEllipse(in: CGRect(x: px - 1.6, y: py + row * 3.4 - 1.6, width: 3.2, height: 3.2))
                        }
                        acc += 6
                    }
                    acc -= seg
                }
                l.fill(dots, with: .color(ReelPalette.ink))
            } else {
                var p = Path()
                p.move(to: pts[0])
                for j in 1..<(pts.count - 1) {
                    let mid = CGPoint(x: (pts[j].x + pts[j + 1].x) / 2, y: (pts[j].y + pts[j + 1].y) / 2)
                    p.addQuadCurve(to: mid, control: pts[j])
                }
                p.addLine(to: pts[pts.count - 1])
                let round = StrokeStyle(lineWidth: 11.5, lineCap: .round, lineJoin: .round)
                l.stroke(p, with: .color(Color(white: 150.0 / 255).opacity(0.55)), style: round)
                l.stroke(p, with: .color(ReelPalette.grey(27)), style: StrokeStyle(lineWidth: 9.5, lineCap: .round, lineJoin: .round))
                l.stroke(p, with: .color(Color(white: 215.0 / 255).opacity(0.7)),
                         style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [3, 6]))
            }
        }
    }

    // MARK: 3D (src `render3D`)

    static func render3D(_ ctx: inout GraphicsContext, _ t: Double, _ g: ReelGeo, _ style: HeroCardStyle) {
        var rig = ReelRig(g: g, s: ReelScene3D.at(t, g))
        rig.drawShadow(&ctx, 1 - M.clamp((rig.s.al - M.alpha0) / 0.9, 0, 1))
        guard let bb = rig.projBB() else { return }
        rig.eyeLocal()
        if style == .matrix { rig.drawSceneMatrix(&ctx, bb) } else { rig.drawReelRidge(&ctx) }
    }
}

// MARK: - 3D rig

private nonisolated struct ReelRig {
    let g: ReelGeo
    let s: ReelScene3D
    var lp = [Double](repeating: 0, count: 3 * 300)
    var wa = [Double](repeating: 0, count: 3 * 300)
    var wb = [Double](repeating: 0, count: 6 * 300)
    var bx0 = 1e9, by0 = 1e9, bx1 = -1e9, by1 = -1e9
    var ro = (0.0, 0.0, 0.0)
    var mcell = 6.0
    typealias M = ReelMath
    static let nb = 96

    init(g: ReelGeo, s: ReelScene3D) { self.g = g; self.s = s }

    mutating func eyeLocal() {
        let ex = g.cx - s.cX, ey = g.cy - s.cY, ez = M.p3 - s.cZ
        ro = (s.m00 * ex + s.m10 * ey + s.m20 * ez,
              s.m01 * ex + s.m11 * ey + s.m21 * ez,
              s.m02 * ex + s.m12 * ey + s.m22 * ez)
    }

    func lamOf(_ nx: Double, _ ny: Double, _ nz: Double) -> Double {
        let fx = s.cp * nx + s.sp * nz, fz = -s.sp * nx + s.cp * nz
        let l = fx * M.lv.0 + ny * M.lv.1 + fz * M.lv.2
        return l < 0 ? 0 : l
    }

    mutating func resetBB() { bx0 = 1e9; by0 = 1e9; bx1 = -1e9; by1 = -1e9 }

    /// Local loop (lp, n points) -> world -> near-plane clip -> same projection as CSS; appended to `p`.
    mutating func addLoop(_ p: inout Path, _ n: Int) -> Bool {
        let ZN = M.p3 - 30
        var k = 0, m = 0, pi = n - 1
        for i in 0..<n {
            let x = lp[i * 3], y = lp[i * 3 + 1], z = lp[i * 3 + 2]
            wa[k] = s.cX + s.m00 * x + s.m01 * y + s.m02 * z; k += 1
            wa[k] = s.cY + s.m10 * x + s.m11 * y + s.m12 * z; k += 1
            wa[k] = s.cZ + s.m20 * x + s.m21 * y + s.m22 * z; k += 1
        }
        for i in 0..<n {
            let bx = wa[i * 3], by = wa[i * 3 + 1], bz = wa[i * 3 + 2]
            let ax = wa[pi * 3], ay = wa[pi * 3 + 1], az = wa[pi * 3 + 2]
            let inb = bz <= ZN, ina = az <= ZN
            if inb {
                if !ina {
                    let t = (ZN - az) / (bz - az)
                    wb[m] = ax + (bx - ax) * t; wb[m + 1] = ay + (by - ay) * t; wb[m + 2] = ZN; m += 3
                }
                wb[m] = bx; wb[m + 1] = by; wb[m + 2] = bz; m += 3
            } else if ina {
                let t = (ZN - az) / (bz - az)
                wb[m] = ax + (bx - ax) * t; wb[m + 1] = ay + (by - ay) * t; wb[m + 2] = ZN; m += 3
            }
            pi = i
        }
        if m < 9 { return false }
        var i = 0
        while i < m {
            let f = M.p3 / (M.p3 - wb[i + 2])
            let X = g.cx + (wb[i] - g.cx) * f, Y = g.cy + (wb[i + 1] - g.cy) * f
            if X < bx0 { bx0 = X }; if X > bx1 { bx1 = X }
            if Y < by0 { by0 = Y }; if Y > by1 { by1 = Y }
            if i > 0 { p.addLine(to: CGPoint(x: X, y: Y)) } else { p.move(to: CGPoint(x: X, y: Y)) }
            i += 3
        }
        p.closeSubpath()
        return true
    }

    mutating func circL(_ cxl: Double, _ cyl: Double, _ zl: Double, _ r: Double, _ n: Int) {
        for i in 0..<n {
            let a = Double(i) / Double(n) * 6.283185
            lp[i * 3] = cxl + r * cos(a); lp[i * 3 + 1] = cyl + r * sin(a); lp[i * 3 + 2] = zl
        }
    }
    @discardableResult
    mutating func circ(_ p: inout Path, _ cxl: Double, _ cyl: Double, _ zl: Double, _ r: Double, _ n: Int) -> Bool {
        circL(cxl, cyl, zl, r, n)
        return addLoop(&p, n)
    }
    mutating func qd(_ p: inout Path, _ r: Double, _ a0: Double, _ a1: Double, _ z0: Double, _ z1: Double) -> Bool {
        let c0 = cos(a0), s0 = sin(a0), c1 = cos(a1), s1 = sin(a1)
        lp[0] = r * c0; lp[1] = r * s0; lp[2] = z0
        lp[3] = r * c1; lp[4] = r * s1; lp[5] = z0
        lp[6] = r * c1; lp[7] = r * s1; lp[8] = z1
        lp[9] = r * c0; lp[10] = r * s0; lp[11] = z1
        return addLoop(&p, 4)
    }

    // MARK: shadow (src `drawShadow`)

    func drawShadow(_ ctx: inout GraphicsContext, _ k: Double) {
        if k <= 0.01 { return }
        let n = 26
        for j in 0..<10 {
            let kk = 1 - Double(j) * 0.085
            let aa = (g.hhw + g.th) * kk + 24, bb = g.rr * 0.95 * kk + 14
            var p = Path()
            for i in 0..<n {
                let a = Double(i) / Double(n) * 6.2832
                let ua = cos(a) * aa, ub = sin(a) * bb
                let fx = s.sp * ua + s.cp * ub, fz = s.cp * ua - s.sp * ub
                let v = s.d + fz
                let wx = s.cX + fx, wy = s.ay + v * s.sa, wz = min(s.az + v * s.ca, M.p3 - 40)
                let f = M.p3 / (M.p3 - wz)
                let pt = CGPoint(x: g.cx + (wx - g.cx) * f, y: g.cy + (wy - g.cy) * f)
                if i > 0 { p.addLine(to: pt) } else { p.move(to: pt) }
            }
            p.closeSubpath()
            ctx.fill(p, with: .color(Color.black.opacity(0.30 * 0.12 * k)))
        }
    }

    // MARK: bounding box (src `projBB`)

    func projBB() -> (x0: Double, y0: Double, x1: Double, y1: Double)? {
        var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        var near = false
        let zo = g.hhw + g.th
        for fl in [-1.0, 1.0] {
            for i in 0..<28 {
                let a = Double(i) / 28 * 6.283185
                let lx = g.rr * cos(a), ly = g.rr * sin(a), lz = fl * zo
                let z = s.cZ + s.m20 * lx + s.m21 * ly + s.m22 * lz
                if z > M.p3 - 60 { near = true; continue }
                let f = M.p3 / (M.p3 - z)
                let x = g.cx + (s.cX + s.m00 * lx + s.m01 * ly + s.m02 * lz - g.cx) * f
                let y = g.cy + (s.cY + s.m10 * lx + s.m11 * ly + s.m12 * lz - g.cy) * f
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        if near { x0 = 0; y0 = 0; x1 = g.w; y1 = g.h }
        x0 = max(0, floor(x0) - 6); y0 = max(0, floor(y0) - 6)
        x1 = min(g.w, ceil(x1) + 6); y1 = min(g.h, ceil(y1) + 6)
        if x1 <= x0 || y1 <= y0 { return nil }
        return (x0, y0, x1, y1)
    }

    // MARK: Ridge: vector reel (src `drawReel`, mt = 0)

    mutating func drawReelRidge(_ ctx: inout GraphicsContext) {
        let KR = g.rr / 95
        let fn = ro.2 >= 0 ? 1.0 : -1.0, ff = -fn
        let zi = g.hhw, zo = g.hhw + g.th, rw = s.rw
        let ex = ro.0, ey = ro.1, dn = 2 * Double.pi / Double(Self.nb)
        let lamN = min(1, lamOf(0, 0, fn) / 0.8)
        rimRidge(&ctx, ff, zi, zo, ex, ey, dn)
        faceRidge(&ctx, ff * zi, lamN, 26, KR)
        for i in 0..<Self.nb {
            let a0 = Double(i) * dn, c = cos(a0 + dn / 2), sn = sin(a0 + dn / 2)
            if c * ex + sn * ey <= rw { continue }
            let lm = min(1, lamOf(c, sn, 0) / 0.8)
            let fl = (i % 24) < 2
            var p = Path()
            if qd(&p, rw, a0, a0 + dn * 1.4, -zi, zi) { ctx.fill(p, with: .color(ReelPalette.grey((fl ? 64 : 34) + 72 * lm))) }
            var sp = Path()
            for j in 0..<2 {
                let o = Double(j) * 0.5
                _ = qd(&sp, rw * 1.002, a0 + dn * (0.12 + o), a0 + dn * (0.38 + o), -zi + 12, -zi + 30)
                _ = qd(&sp, rw * 1.002, a0 + dn * (0.12 + o), a0 + dn * (0.38 + o), zi - 30, zi - 12)
            }
            if !sp.isEmpty { ctx.fill(sp, with: .color(ReelPalette.grey(188))) }
        }
        var cap = Path()
        if circ(&cap, 0, 0, fn * zi, rw, 72) { ctx.fill(cap, with: .color(ReelPalette.grey(22))) }
        for j in 0..<22 {
            let rr = rw - Double(j) * 3.4 * KR
            if rr < 30 * KR { break }
            var p = Path()
            if circ(&p, 0, 0, fn * zi, rr, 60) { ctx.fill(p, with: .color(ReelPalette.grey((j & 1) != 0 ? 24 : 56))) }
        }
        rimRidge(&ctx, fn, zi, zo, ex, ey, dn)
        faceRidge(&ctx, fn * zo, lamN, 0, KR)
    }

    mutating func rimRidge(_ ctx: inout GraphicsContext, _ fl: Double, _ zi: Double, _ zo: Double, _ ex: Double, _ ey: Double, _ dn: Double) {
        for i in 0..<Self.nb {
            let a0 = Double(i) * dn, c = cos(a0 + dn / 2), sn = sin(a0 + dn / 2)
            if c * ex + sn * ey <= g.rr { continue }
            let lm = min(1, lamOf(c, sn, 0) / 0.8)
            var p = Path()
            if qd(&p, g.rr, a0, a0 + dn * 1.4, fl * zi, fl * zo) {
                ctx.fill(p, with: .color(ReelPalette.grey((105 + 115 * lm) * 0.78)))
            }
        }
    }

    mutating func faceRidge(_ ctx: inout GraphicsContext, _ zf: Double, _ lamF: Double, _ dim: Double, _ KR: Double) {
        let hr = 18.2 * KR, hR = 20.5 * KR
        let spin = s.spin
        resetBB()
        var outer = Path()
        circL(0, 0, zf, g.rr, 72); _ = addLoop(&outer, 72)
        for k in 0..<6 {
            let ang = ReelUnit.holeAngle[k] + spin
            circ(&outer, cos(ang) * 57 * KR, sin(ang) * 57 * KR, zf, hr, 36)
        }
        let gx0 = bx0, gy0 = by0, gx1 = bx1, gy1 = by1
        let gl = 118 + 112 * lamF - dim
        let grad = Gradient(stops: [.init(color: ReelPalette.grey(gl + 50), location: 0), .init(color: ReelPalette.grey(gl - 8), location: 0.42),
                                    .init(color: ReelPalette.grey(gl + 30), location: 0.72), .init(color: ReelPalette.grey(gl - 52), location: 1)])
        let shading = GraphicsContext.Shading.linearGradient(grad, startPoint: CGPoint(x: gx0, y: gy0), endPoint: CGPoint(x: gx1, y: gy1))
        if (gx1 - gx0) * (gy1 - gy0) < 260000 {
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: Color.black.opacity(0.34), radius: 2.5, x: 0, y: 0))
                l.fill(outer, with: shading, style: FillStyle(eoFill: true))
            }
        } else {
            ctx.fill(outer, with: shading, style: FillStyle(eoFill: true))
        }
        var groove = Path()
        circ(&groove, 0, 0, zf, 85 * KR, 72)
        ctx.stroke(groove, with: .color(ReelPalette.grey(123).opacity(0.55)), lineWidth: 1.2)
        for k in 0..<6 {
            let ang = ReelUnit.holeAngle[k] + spin
            let hx = cos(ang) * 57 * KR, hy = sin(ang) * 57 * KR
            var ring = Path()
            circ(&ring, hx, hy, zf, hR, 40); circ(&ring, hx, hy, zf, hr, 40)
            ctx.fill(ring, with: .color(ReelPalette.grey(189)), style: FillStyle(eoFill: true))
            var edge = Path()
            circ(&edge, hx, hy, zf, hR, 40)
            ctx.stroke(edge, with: .color(ReelPalette.grey(111)), lineWidth: 1)
        }
        var hub = Path()
        circ(&hub, 0, 0, zf, 31 * KR, 48)
        let hg = Gradient(stops: [.init(color: ReelPalette.grey(236), location: 0), .init(color: ReelPalette.grey(190), location: 0.5),
                                  .init(color: ReelPalette.grey(140), location: 1)])
        ctx.fill(hub, with: .linearGradient(hg, startPoint: CGPoint(x: gx0 + (gx1 - gx0) * 0.35, y: gy0 + (gy1 - gy0) * 0.35),
                                            endPoint: CGPoint(x: gx0 + (gx1 - gx0) * 0.65, y: gy0 + (gy1 - gy0) * 0.65)))
        ctx.stroke(hub, with: .color(ReelPalette.outline), lineWidth: 1.3)
        for k in 0..<6 {
            let ang = Double(k) * Double.pi / 3 + Double.pi / 3 * 0.5 + Double.pi / 6 + spin
            var p = Path()
            if circ(&p, cos(ang) * 16.5 * KR, sin(ang) * 16.5 * KR, zf, 3.7 * KR, 16) { ctx.fill(p, with: .color(ReelPalette.grey(29))) }
        }
        var centre = Path()
        if circ(&centre, 0, 0, zf, 5.6 * KR, 16) { ctx.fill(centre, with: .color(ReelPalette.grey(34))) }
        var sil = Path()
        circ(&sil, 0, 0, zf, g.rr, 72)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 0.6))
            l.stroke(sil, with: .color(ReelPalette.outline), lineWidth: 1.9)
        }
    }

    // MARK: Matrix: dot lattice sampling the same geometry (src `drawSceneMatrix`, ray cast instead of an offscreen mask)

    mutating func drawSceneMatrix(_ ctx: inout GraphicsContext, _ bb: (x0: Double, y0: Double, x1: Double, y1: Double)) {
        let area = (bb.x1 - bb.x0) * (bb.y1 - bb.y0)
        let c = M.clamp(ceil((area / 3000).squareRoot()), 6, 11)
        mcell = c
        let i0 = Int(floor((bb.x0 - g.cx) / c + 0.5)), i1 = Int(ceil((bb.x1 - g.cx) / c - 0.5))
        let j0 = Int(floor((bb.y0 - g.cy) / c + 0.5)), j1 = Int(ceil((bb.y1 - g.cy) / c - 0.5))
        if i1 < i0 || j1 < j0 { return }
        let top = Double(ReelPalette.buckets - 1)
        var backing = Path()
        var paths = [Path](repeating: Path(), count: ReelPalette.buckets)
        let sc = c / 6
        let caster = RayCaster(rig: self, c: c)
        for j in j0...j1 {
            for i in i0...i1 {
                let X = g.cx + Double(i) * c, Y = g.cy + Double(j) * c
                guard let b = caster.cast(X, Y) else { continue }
                backing.addRect(CGRect(x: X - c / 2 - 0.4, y: Y - c / 2 - 0.4, width: c + 0.8, height: c + 0.8))
                let idx = Int((M.clamp(b, 0, 1) * top).rounded())
                let rad = (1.25 + 0.85 * Double(idx) / top) * sc
                paths[idx].addEllipse(in: CGRect(x: X - rad, y: Y - rad, width: 2 * rad, height: 2 * rad))
            }
        }
        ctx.fill(backing, with: .color(ReelPalette.bg))
        for l in 0..<paths.count where !paths[l].isEmpty { ctx.fill(paths[l], with: .color(ReelPalette.levels[l])) }
    }
}

/// Analytic ray cast of the reel (flange faces with cut-outs, rims, wound film, end cap); nearest surface wins.
private nonisolated struct RayCaster {
    let g: ReelGeo
    let s: ReelScene3D
    let ro: (Double, Double, Double)
    let c: Double
    let KR: Double, zi: Double, zo: Double, rw: Double
    let fn: Double, ff: Double, spin: Double
    let rr: Double
    let holeC: [(Double, Double)]
    let smallC: [(Double, Double)]
    let faceBB: [(Double, Double, Double, Double)]   // [near, far]: bbox x0,y0,x1,y1 for the base gradient
    let rig: ReelRig
    typealias M = ReelMath

    init(rig: ReelRig, c: Double) {
        self.rig = rig
        g = rig.g; s = rig.s; ro = rig.ro; self.c = c
        KR = g.rr / 95; zi = g.hhw; zo = g.hhw + g.th; rw = s.rw; rr = g.rr
        fn = ro.2 >= 0 ? 1 : -1; ff = -fn; spin = s.spin
        var hc: [(Double, Double)] = [], sm: [(Double, Double)] = []
        for k in 0..<6 {
            let a = ReelUnit.holeAngle[k] + spin
            hc.append((cos(a) * 57 * KR, sin(a) * 57 * KR))
            let b = Double(k) * Double.pi / 3 + Double.pi / 6 + Double.pi / 6 + spin
            sm.append((cos(b) * 16.5 * KR, sin(b) * 16.5 * KR))
        }
        holeC = hc; smallC = sm
        var bbs: [(Double, Double, Double, Double)] = []
        for zf in [fn * zo, ff * zi] {
            var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
            for i in 0..<72 {
                let a = Double(i) / 72 * 6.283185
                let lx = rr * cos(a), ly = rr * sin(a)
                let wx = s.cX + s.m00 * lx + s.m01 * ly + s.m02 * zf
                let wy = s.cY + s.m10 * lx + s.m11 * ly + s.m12 * zf
                let wz = s.cZ + s.m20 * lx + s.m21 * ly + s.m22 * zf
                let f = M.p3 / (M.p3 - min(wz, M.p3 - 30))
                let X = g.cx + (wx - g.cx) * f, Y = g.cy + (wy - g.cy) * f
                x0 = min(x0, X); x1 = max(x1, X); y0 = min(y0, Y); y1 = max(y1, Y)
            }
            bbs.append((x0, y0, x1, y1))
        }
        faceBB = bbs
    }

    func lamOf(_ nx: Double, _ ny: Double) -> Double {
        let fx = s.cp * nx, fz = -s.sp * nx
        let l = fx * M.lv.0 + ny * M.lv.1 + fz * M.lv.2
        return l < 0 ? 0 : l
    }

    /// 0 none, 1 border ring, 2 cut-out.
    func holeState(_ x: Double, _ y: Double) -> Int {
        let hr = 18.2 * KR, hR = 20.5 * KR
        for k in 0..<6 {
            let d = hypot(x - holeC[k].0, y - holeC[k].1)
            if d < hr { return 2 }
            if d < hR { return 1 }
        }
        return 0
    }

    func faceBrightness(_ x: Double, _ y: Double, _ X: Double, _ Y: Double, _ face: Int) -> Double {
        let r = hypot(x, y)
        if r >= 87 * KR { return 0.98 }
        if r >= 82 * KR { return 0.4 }
        if r < 33 * KR {
            if r < 5.6 * KR { return 0.04 }
            if r < 30 * KR {
                for k in 0..<6 where hypot(x - smallC[k].0, y - smallC[k].1) < 3.7 * KR { return 0.06 }
                return 0.9
            }
            return 0.3
        }
        let b = faceBB[face]
        let dx = b.2 - b.0, dy = b.3 - b.1
        let len2 = dx * dx + dy * dy
        let u = len2 > 0 ? M.clamp(((X - b.0) * dx + (Y - b.1) * dy) / len2, 0, 1) : 0
        return 1 - 0.2 * u
    }

    /// Brightness 0...1 of the nearest surface along the eye ray through screen point (X, Y); nil: empty.
    func cast(_ X: Double, _ Y: Double) -> Double? {
        let dx = X - g.cx, dy = Y - g.cy, dz = -M.p3
        let lx = s.m00 * dx + s.m10 * dy + s.m20 * dz
        let ly = s.m01 * dx + s.m11 * dy + s.m21 * dz
        let lz = s.m02 * dx + s.m12 * dy + s.m22 * dz
        let ox = ro.0, oy = ro.1, oz = ro.2
        var bestT = Double.infinity, best = 0.0
        let eps = 1e-6
        let hasZ = abs(lz) > 1e-9

        if hasZ {
            // near flange outer face (with cut-outs)
            var t = (fn * zo - oz) / lz
            if t > eps && t < bestT {
                let x = ox + t * lx, y = oy + t * ly
                if x * x + y * y <= rr * rr {
                    let hs = holeState(x, y)
                    if hs == 1 { bestT = t; best = 0.62 }
                    else if hs == 0 { bestT = t; best = faceBrightness(x, y, X, Y, 0) }
                }
            }
            // wound film end cap
            t = (fn * zi - oz) / lz
            if t > eps && t < bestT {
                let x = ox + t * lx, y = oy + t * ly
                let r = hypot(x, y)
                if r <= rw {
                    let step = 3.4 * KR
                    var j = Int(ceil((rw - r) / step)) - 1
                    if j < 0 { j = 0 }
                    let jmax = Int(floor((rw - 30 * KR) / step))
                    if j > jmax { j = max(0, jmax) }
                    bestT = t; best = (j & 1) != 0 ? 0.05 : 0.2
                }
            }
            // far flange inner face (with cut-outs)
            t = (ff * zi - oz) / lz
            if t > eps && t < bestT {
                let x = ox + t * lx, y = oy + t * ly
                if x * x + y * y <= rr * rr {
                    let hs = holeState(x, y)
                    if hs == 1 { bestT = t; best = 0.62 }
                    else if hs == 0 { bestT = t; best = faceBrightness(x, y, X, Y, 1) }
                }
            }
        }
        // cylinders: flange rims at RR (|z| in [zi, zo]) and wound film at rw (|z| < zi); entering root only
        let a = lx * lx + ly * ly
        if a > 1e-12 {
            let b = ox * lx + oy * ly
            for kind in 0..<2 {
                let rho = kind == 0 ? rr : rw
                let cc = ox * ox + oy * oy - rho * rho
                let disc = b * b - a * cc
                if disc <= 0 { continue }
                let t = (-b - disc.squareRoot()) / a
                if t <= eps || t >= bestT { continue }
                let z = oz + t * lz
                let az = abs(z)
                let x = ox + t * lx, y = oy + t * ly
                let nx = x / rho, ny = y / rho
                let lm = min(1, lamOf(nx, ny) / 0.8)
                if kind == 0 {
                    if az >= zi && az <= zo { bestT = t; best = 0.98 * (0.55 + 0.45 * lm) }
                } else if az < zi {
                    var th = atan2(y, x)
                    if th < 0 { th += 2 * Double.pi }
                    let dn = 2 * Double.pi / 96
                    let seg = floor(th / dn), fr = th / dn - seg
                    let fl = (Int(seg) % 24) < 2
                    let spr = (z >= -zi + 12 && z <= -zi + 30) || (z >= zi - 30 && z <= zi - 12)
                    if spr && ((fr >= 0.12 && fr <= 0.38) || (fr >= 0.62 && fr <= 0.88)) { best = 0.08 }
                    else { best = (fl ? 1 : 0.8) * (0.5 + 0.5 * lm) }
                    bestT = t
                }
            }
        }
        return bestT.isFinite ? best : nil
    }
}
