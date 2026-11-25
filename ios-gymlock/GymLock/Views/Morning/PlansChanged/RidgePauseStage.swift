//
//  RidgePauseStage.swift
//  GymLock · the "plans changed" pause · Ridge look
//
//  Port of the approved prototype (v-ridge.html, "keep ridge as is"). The baked dawn world
//  (Assets.xcassets/WakeRidge/ridgeWorldDawn, 1290 x 2792 px) is drawn full bleed with a camera that
//  is a pure function of `input.t` and `input.phase`: a slow push while the 30 seconds run, then one
//  framing per door.
//
//  Coordinates: the prototype's jpg was a 900 x 1948 thumbnail of the same image (same aspect), so
//  every geometry number here (peak tip, sun clip polygon, trail paths, mist top) is kept in that
//  900 x 1948 "world" space exactly as the prototype has it. The Canvas scales world space onto the
//  1290 x 2792 asset by drawing the image into the 900 x 1948 rect (a 1.4333 factor, applied by the
//  draw), so there is one coordinate system and nothing is converted twice. Screen mapping is the
//  prototype's: aspect fill (k = max(w / 900, h / 1948)), anchored 10% from the top, then the camera
//  (scale s, translate tx, ty) on top. Trails, hut, sun and mist are drawn inside that same transform,
//  so they follow the slope under every framing on every iPhone.
//
//  Owner-approved for this screen (the painted world, the sky wash and the bottom scrim); one coral
//  element only: the sun.
//

import SwiftUI

// MARK: - Math

private enum RidgePauseMath {
    static func cl(_ x: Double) -> Double { min(1, max(0, x)) }
    /// ease in-out quad (the prototype's `ease`)
    static func ease(_ x: Double) -> Double {
        let k = cl(x)
        return k < 0.5 ? 2 * k * k : 1 - pow(-2 * k + 2, 2) / 2
    }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

// MARK: - Camera and screen mapping

private struct RidgeCamState {
    var s: CGFloat
    var tx: CGFloat
    var ty: CGFloat

    func mixed(_ b: RidgeCamState, _ t: Double) -> RidgeCamState {
        let f = CGFloat(t)
        return RidgeCamState(s: s + (b.s - s) * f, tx: tx + (b.tx - tx) * f, ty: ty + (b.ty - ty) * f)
    }
}

private struct RidgePauseGeo {
    /// the prototype's baked image size; all geometry below is in these units
    static let worldW: CGFloat = 900
    static let worldH: CGFloat = 1948
    /// the main peak's tip
    static let apex = CGPoint(x: 500, y: 1072)

    let w: CGFloat
    let h: CGFloat
    let k: CGFloat
    let iw: CGFloat
    let ih: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    init(size: CGSize) {
        let width = max(1, size.width)
        let height = max(1, size.height)
        let scale = max(width / Self.worldW, height / Self.worldH)
        let imageW = Self.worldW * scale
        let imageH = Self.worldH * scale
        w = width
        h = height
        k = scale
        iw = imageW
        ih = imageH
        ox = (width - imageW) / 2
        oy = -(imageH - height) * 0.1
    }

    /// keeps the image covering the screen
    func clamped(_ s: CGFloat, _ tx: CGFloat, _ ty: CGFloat) -> RidgeCamState {
        let minTx = w - ox - iw * s, maxTx = -ox
        let minTy = h - oy - ih * s, maxTy = -oy
        return RidgeCamState(s: s,
                             tx: min(maxTx, max(minTx, tx)),
                             ty: min(maxTy, max(minTy, ty)))
    }

    /// world point (fx, fy) lands on screen point (sx, sy)
    func focal(_ s: CGFloat, _ fx: CGFloat, _ fy: CGFloat, _ sx: CGFloat, _ sy: CGFloat) -> RidgeCamState {
        clamped(s, sx - ox - s * fx * k, sy - oy - s * fy * k)
    }

    /// the slow push while the 30 seconds run: 1.00 to 1.07 with a slight upward drift
    func waitingCam(t: Double, reduceMotion: Bool) -> RidgeCamState {
        let e = reduceMotion ? 0 : RidgePauseMath.ease(t / PauseScript.wait)
        return clamped(1 + 0.07 * CGFloat(e), 0, -14 * CGFloat(e))
    }

    /// one framing per door
    func cam(_ key: PauseChoice.Key) -> RidgeCamState {
        switch key {
        case .gym:
            return focal(1.32, Self.apex.x, Self.apex.y, w * 0.5, min(h * 0.585, h - 300))
        case .home:
            return focal(1.0, Self.apex.x, 1300, w * 0.5, min(h * 0.70, h - 250))
        case .cant:
            return focal(1.3, 790, 1330, w * 0.42, min(h * 0.68, h - 290))
        }
    }

    /// where the peak's tip is on screen under a camera
    func tipY(_ c: RidgeCamState) -> CGFloat {
        oy + c.ty + c.s * Self.apex.y * k
    }
}

// MARK: - The two trails (SVG paths of the prototype, flattened once)

private struct RidgePausePath {
    let pts: [CGPoint]
    let cum: [CGFloat]
    var length: CGFloat { cum.last ?? 0 }
    var end: CGPoint { pts.last ?? .zero }

    /// `segments` are cubic Beziers, four points each
    init(segments: [[CGPoint]]) {
        var p: [CGPoint] = []
        var c: [CGFloat] = []
        let steps = 48
        for (si, seg) in segments.enumerated() where seg.count == 4 {
            let start = si == 0 ? 0 : 1
            for i in start...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let m = 1 - t
                let a = m * m * m, b = 3 * m * m * t, d = 3 * m * t * t, e = t * t * t
                let x = a * seg[0].x + b * seg[1].x + d * seg[2].x + e * seg[3].x
                let y = a * seg[0].y + b * seg[1].y + d * seg[2].y + e * seg[3].y
                let pt = CGPoint(x: x, y: y)
                if let last = p.last, let lc = c.last {
                    c.append(lc + hypot(pt.x - last.x, pt.y - last.y))
                } else {
                    c.append(0)
                }
                p.append(pt)
            }
        }
        pts = p
        cum = c
    }

    /// the point `d` along the path (clamped), like SVG getPointAtLength
    func point(at d: CGFloat) -> CGPoint {
        guard pts.count > 1 else { return pts.first ?? .zero }
        let dd = min(length, max(0, d))
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] < dd { lo = mid } else { hi = mid }
        }
        let span = max(0.0001, cum[hi] - cum[lo])
        let f = (dd - cum[lo]) / span
        return CGPoint(x: pts[lo].x + (pts[hi].x - pts[lo].x) * f,
                       y: pts[lo].y + (pts[hi].y - pts[lo].y) * f)
    }
}

private enum RidgePauseShapes {
    /// 'M444 1400 C 444 1370, 448 1350, 452 1320 S 480 1200, 497 1100'
    static let gymTrail = RidgePausePath(segments: [
        [CGPoint(x: 444, y: 1400), CGPoint(x: 444, y: 1370), CGPoint(x: 448, y: 1350), CGPoint(x: 452, y: 1320)],
        [CGPoint(x: 452, y: 1320), CGPoint(x: 456, y: 1290), CGPoint(x: 480, y: 1200), CGPoint(x: 497, y: 1100)]
    ])
    /// 'M520 1445 C 560 1430, 600 1405, 610 1378 S 618 1352, 620 1338'
    static let homeTrail = RidgePausePath(segments: [
        [CGPoint(x: 520, y: 1445), CGPoint(x: 560, y: 1430), CGPoint(x: 600, y: 1405), CGPoint(x: 610, y: 1378)],
        [CGPoint(x: 610, y: 1378), CGPoint(x: 620, y: 1351), CGPoint(x: 618, y: 1352), CGPoint(x: 620, y: 1338)]
    ])

    /// the sky above the ridge line (the prototype's clip-path, percent of the image)
    static let skyClip: Path = {
        let pct: [(Double, Double)] = [
            (0, 0), (100, 0), (100, 59.6), (62.2, 59.6), (60.6, 58), (57.8, 55.7),
            (55.6, 54.9), (54.2, 55.7), (52.8, 56), (50.6, 57), (48.9, 59.6), (0, 59.6)
        ]
        var p = Path()
        for (i, v) in pct.enumerated() {
            let pt = CGPoint(x: v.0 / 100 * 900, y: v.1 / 100 * 1948)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }()

    static let warm = Gradient(stops: [
        Gradient.Stop(color: Color(red: 150 / 255, green: 140 / 255, blue: 130 / 255).opacity(0), location: 0.36),
        Gradient.Stop(color: Color(red: 150 / 255, green: 140 / 255, blue: 130 / 255), location: 0.52),
        Gradient.Stop(color: Color(red: 150 / 255, green: 140 / 255, blue: 130 / 255).opacity(0), location: 0.58)
    ])

    static let mist = Gradient(stops: [
        Gradient.Stop(color: Color(red: 150 / 255, green: 150 / 255, blue: 158 / 255).opacity(0), location: 0),
        Gradient.Stop(color: Color(red: 150 / 255, green: 150 / 255, blue: 153 / 255), location: 0.35),
        Gradient.Stop(color: Color(red: 150 / 255, green: 150 / 255, blue: 153 / 255), location: 0.65),
        Gradient.Stop(color: Color(red: 150 / 255, green: 150 / 255, blue: 158 / 255).opacity(0), location: 1)
    ])
}

private let ridgePauseInk = Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)

// MARK: - One frame, as numbers

private struct RidgePauseFrame {
    var cam: RidgeCamState
    /// screen points of the sun's centre below the tip (negative = above)
    var sunOffset: CGFloat
    var warmOpacity: Double
    var sunOpacity: Double
    var dimOpacity: Double
    var scrimOpacity: Double
    var mistOpacity: Double
    var mistShift: CGFloat
    var trailKey: PauseChoice.Key?
    var trailProgress: Double
    var trailOpacity: Double
    var outKey: PauseChoice.Key?
    var outOpacity: Double

    init(input: PauseStageInput, geo: RidgePauseGeo) {
        typealias M = RidgePauseMath
        let t = input.t
        let rm = input.reduceMotion
        let p = M.cl(t / PauseScript.wait)

        sunOffset = CGFloat(21 + (-35 - 21) * p)
        warmOpacity = 0.32 * p

        var camera = geo.waitingCam(t: t, reduceMotion: rm)
        var sun = 1.0
        var dim = 0.0
        var scrim = 0.0
        var mist = 0.0
        var shift: CGFloat = 0
        var tKey: PauseChoice.Key? = nil
        var tProg = 0.0
        var tOp = 0.0
        var oKey: PauseChoice.Key? = nil
        var oOp = 0.0

        if let ch = input.choice {
            let key = ch.choice.key
            let age = ch.age
            var fromKey: PauseChoice.Key? = nil
            if let fi = ch.from, fi >= 0, fi < input.script.choices.count {
                fromKey = input.script.choices[fi].key
            }

            // camera: 700 ms ease in-out from the previous framing (or the end of the wait)
            let target = geo.cam(key)
            var start = geo.waitingCam(t: PauseScript.wait, reduceMotion: rm)
            if let fk = fromKey { start = geo.cam(fk) }
            let q = rm ? 1.0 : M.cl(age / 0.7)
            camera = start.mixed(target, M.ease(q))

            // the sun stays for "still going" only (400 ms fade)
            let sunTo = key == .gym ? 1.0 : 0.0
            var sunFrom = 1.0
            if let fk = fromKey { sunFrom = fk == .gym ? 1.0 : 0.0 }
            sun = M.lerp(sunFrom, sunTo, M.ease(age / 0.4))

            // "can't today" dims the world 20% (700 ms)
            let dimTo = key == .cant ? 0.2 : 0.0
            var dimFrom = 0.0
            if let fk = fromKey { dimFrom = fk == .cant ? 0.2 : 0.0 }
            dim = M.lerp(dimFrom, dimTo, M.ease(age / 0.7))

            // the dark scrim behind the buttons fades in with the first door, then stays
            scrim = fromKey == nil ? M.ease(age / 0.5) : 1

            if key == .cant {
                let e = rm ? M.cl(age / 0.35) : M.ease((age - 0.3) / 1.2)
                mist = 0.5 * e
                shift = rm ? 0 : CGFloat(-180 * (1 - e))
            } else if fromKey == .cant {
                mist = 0.5 * (1 - M.cl(age / 0.3))
            }

            if key != .cant {
                tKey = key
                tProg = rm ? 1 : M.cl((age - 0.7) / 0.9)
                tOp = M.cl(age / (rm ? 0.35 : 0.3))
            }
            if let fk = fromKey, fk != .cant, fk != key {
                oKey = fk
                oOp = 1 - M.cl(age / 0.3)
            }
        }

        cam = camera
        sunOpacity = sun
        dimOpacity = dim
        scrimOpacity = scrim
        mistOpacity = mist
        mistShift = shift
        trailKey = tKey
        trailProgress = tProg
        trailOpacity = tOp
        outKey = oKey
        outOpacity = oOp
    }
}

// MARK: - Drawing

private enum RidgePauseDraw {
    static func draw(_ ctx: inout GraphicsContext, image: CGImage?, geo: RidgePauseGeo, f: RidgePauseFrame, size: CGSize) {
        let screen = CGRect(origin: .zero, size: size)
        ctx.fill(Path(screen), with: .color(ridgePauseInk))

        // the world, under the camera
        ctx.drawLayer { c in
            c.translateBy(x: geo.ox + f.cam.tx, y: geo.oy + f.cam.ty)
            c.scaleBy(x: f.cam.s * geo.k, y: f.cam.s * geo.k)
            let world = CGRect(x: 0, y: 0, width: RidgePauseGeo.worldW, height: RidgePauseGeo.worldH)

            if let image {
                let resolved = c.resolve(Image(decorative: image, scale: 1).interpolation(.medium))
                c.draw(resolved, in: world)
            }

            // warm-grey sky wash, rising with time
            if f.warmOpacity > 0.001 {
                c.drawLayer { cc in
                    cc.opacity = f.warmOpacity
                    cc.fill(Path(world),
                            with: .linearGradient(RidgePauseShapes.warm,
                                                  startPoint: CGPoint(x: 0, y: 0),
                                                  endPoint: CGPoint(x: 0, y: RidgePauseGeo.worldH)))
                }
            }

            // the sun: 14 pt on screen at any camera scale, clipped by the ridge line
            if f.sunOpacity > 0.001 {
                let unit = geo.k * f.cam.s
                let r = 7 / unit
                let cy = RidgePauseGeo.apex.y + f.sunOffset / unit
                c.drawLayer { cc in
                    cc.clip(to: RidgePauseShapes.skyClip)
                    let dot = CGRect(x: RidgePauseGeo.apex.x - r, y: cy - r, width: 2 * r, height: 2 * r)
                    cc.fill(Path(ellipseIn: dot), with: .color(Theme.accent.opacity(f.sunOpacity)))
                }
            }

            // mist band over the peak base ("can't today")
            if f.mistOpacity > 0.001 {
                c.drawLayer { cc in
                    cc.opacity = f.mistOpacity
                    let rect = CGRect(x: f.mistShift, y: 1230, width: 900, height: 230)
                    cc.fill(Path(rect),
                            with: .linearGradient(RidgePauseShapes.mist,
                                                  startPoint: CGPoint(x: 0, y: 1230),
                                                  endPoint: CGPoint(x: 0, y: 1460)))
                }
            }

            // trails (and the hut), sized in screen points at their own settled framing
            if let key = f.outKey, f.outOpacity > 0.001 {
                trail(&c, key: key, geo: geo, progress: 1, opacity: f.outOpacity)
            }
            if let key = f.trailKey, f.trailOpacity > 0.001 {
                trail(&c, key: key, geo: geo, progress: f.trailProgress, opacity: f.trailOpacity)
            }
        }

        // soft dark top so the words sit on a calm sky
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.58)),
                 with: .linearGradient(Gradient(colors: [ridgePauseInk.opacity(0.35), ridgePauseInk.opacity(0)]),
                                       startPoint: CGPoint(x: 0, y: 0),
                                       endPoint: CGPoint(x: 0, y: size.height * 0.58)))

        // "can't today" dims the world
        if f.dimOpacity > 0.001 {
            ctx.fill(Path(screen), with: .color(ridgePauseInk.opacity(f.dimOpacity)))
        }

        // flat dark scrim behind the buttons: solid ink, 0 to 70%, over the bottom 30%
        if f.scrimOpacity > 0.001 {
            let top = size.height * 0.70
            ctx.drawLayer { c in
                c.opacity = f.scrimOpacity
                c.fill(Path(CGRect(x: 0, y: top, width: size.width, height: size.height - top)),
                       with: .linearGradient(Gradient(colors: [ridgePauseInk.opacity(0), ridgePauseInk.opacity(0.7)]),
                                             startPoint: CGPoint(x: 0, y: top),
                                             endPoint: CGPoint(x: 0, y: size.height)))
            }
        }
    }

    /// dots every 8 pt (3.2 pt across) from the foreground up; home ends in a small hut
    private static func trail(_ c: inout GraphicsContext, key: PauseChoice.Key, geo: RidgePauseGeo, progress: Double, opacity: Double) {
        guard key != .cant else { return }
        let path = key == .home ? RidgePauseShapes.homeTrail : RidgePauseShapes.gymTrail
        // one screen point in world units at that door's settled camera
        let u = 1 / (geo.k * geo.cam(key).s)
        let step = 8 * u
        let r = 1.6 * u
        let n = max(1, Int(path.length / step) + 1)

        var dots = Path()
        for i in 0..<n {
            if Double(i) / Double(n) > progress { break }
            let pt = path.point(at: CGFloat(i) * step)
            dots.addEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r))
        }
        c.fill(dots, with: .color(Color.white.opacity(0.95 * opacity)))

        if key == .home {
            let hut = RidgePauseMath.cl((progress - 0.98) * 50) * opacity
            if hut > 0.001 {
                let e = path.end
                let w = 11 * u, h = 7 * u, roof = 5 * u
                let x0 = e.x - w / 2
                let yb = e.y + 1 * u
                var body = Path()
                body.move(to: CGPoint(x: x0, y: yb))
                body.addLine(to: CGPoint(x: x0, y: yb - h))
                body.addLine(to: CGPoint(x: e.x, y: yb - h - roof))
                body.addLine(to: CGPoint(x: x0 + w, y: yb - h))
                body.addLine(to: CGPoint(x: x0 + w, y: yb))
                body.closeSubpath()
                c.fill(body, with: .color(Color.white.opacity(hut)))
                let door = CGRect(x: e.x - 1.6 * u, y: yb - 4 * u, width: 3.2 * u, height: 4 * u)
                c.fill(Path(door), with: .color(Color(red: 42 / 255, green: 42 / 255, blue: 44 / 255).opacity(hut)))
            }
        }
    }
}

// MARK: - Layouts

/// Flows per-word views into centred lines. The whole line is laid out up front (unrevealed words
/// are just transparent), so wrapping never changes while the words appear.
private struct RidgeWordFlow: Layout {
    var space: CGFloat
    var lineGap: CGFloat

    private struct Row {
        var items: [Int] = []
        var widths: [CGFloat] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var result: [Row] = []
        var cur = Row()
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let added = cur.items.isEmpty ? s.width : cur.width + space + s.width
            if added > maxWidth && !cur.items.isEmpty {
                result.append(cur)
                cur = Row(items: [i], widths: [s.width], width: s.width, height: s.height)
            } else {
                cur.items.append(i)
                cur.widths.append(s.width)
                cur.width = added
                cur.height = max(cur.height, s.height)
            }
        }
        if !cur.items.isEmpty { result.append(cur) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? 10_000
        let r = rows(subviews, maxWidth: maxWidth)
        let height = r.reduce(CGFloat(0)) { $0 + $1.height } + lineGap * CGFloat(max(0, r.count - 1))
        let width = proposal.width ?? (r.map { $0.width }.max() ?? 0)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let r = rows(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in r {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for (n, i) in row.items.enumerated() {
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                x += row.widths[n] + space
            }
            y += row.height + lineGap
        }
    }
}

/// Places its one child centred vertically between `top` and `bottom` (never above `top`).
private struct RidgeBand: Layout {
    var top: CGFloat
    var bottom: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard let v = subviews.first else { return }
        let size = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let y = max(top, top + (bottom - top - size.height) / 2)
        v.place(at: CGPoint(x: bounds.minX, y: bounds.minY + y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}

// MARK: - Words

private struct RidgeLineView: View {
    let line: PauseLine
    let t: Double
    let isLast: Bool
    let reduceMotion: Bool
    let fs: CGFloat

    var body: some View {
        let words = line.words
        let n = words.count
        let stagger = n > 1 ? max(0, 0.4 * line.duration - 0.2) / Double(n - 1) : 0
        let leave = isLast ? 0 : RidgePauseMath.cl((t - line.end) / 0.24)
        let isQuote = line.kind == .quote
        let size: CGFloat = (isQuote ? 26 : 24) * fs
        let font: Font = isQuote
            ? Font.system(size: size, weight: .regular, design: .serif).italic()
            : Font.system(size: size, weight: .semibold)

        VStack(spacing: 10) {
            RidgeWordFlow(space: size * 0.27, lineGap: 1) {
                ForEach(0..<n, id: \.self) { j in
                    let a = RidgePauseMath.cl((t - line.start - Double(j) * stagger) / 0.2)
                    Text(words[j])
                        .font(font)
                        .tracking(isQuote ? 0 : -0.2)
                        .foregroundStyle(Color.white)
                        .fixedSize()
                        .opacity(a)
                        .offset(y: reduceMotion ? 0 : CGFloat(3 * (1 - a)))
                }
            }
            if let src = line.source {
                Text(src)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Theme.pageMargin)
        .opacity(1 - leave)
        .offset(y: reduceMotion ? 0 : CGFloat(-8 * leave))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.source.map { line.text + ". " + $0 } ?? line.text)
    }
}

private struct RidgeChoiceBlock: View {
    let choice: PauseChoice
    /// seconds since this door entered (large = fully in)
    let age: Double
    let reduceMotion: Bool
    let fs: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(choice.title)
                .font(.system(size: 32 * fs, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(choice.lead)
                .font(.system(size: 17 * fs, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .padding(.top, 10)
            VStack(spacing: 6) {
                ForEach(0..<choice.perks.count, id: \.self) { i in
                    let a = RidgePauseMath.ease((age - (0.2 + 0.06 * Double(i))) / 0.3)
                    Text(choice.perks[i])
                        .font(.system(size: 16 * fs, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .opacity(a)
                        .offset(y: reduceMotion ? 0 : CGFloat(8 * (1 - a)))
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.pageMargin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([choice.title, choice.lead] + choice.perks).joined(separator: ". "))
    }
}

// MARK: - The stage

struct RidgePauseStage: View {
    let input: PauseStageInput

    /// the decoded dawn world, loaded once off the main thread (shared cache with the wake intro)
    @State private var world: CGImage?

    var body: some View {
        let layout = input.layout
        let size = layout.size
        let geo = RidgePauseGeo(size: size)
        let frame = RidgePauseFrame(input: input, geo: geo)
        let fs = min(1, max(0.88, size.height / 760))
        let _ = cueHaptics()

        ZStack(alignment: .topLeading) {
            ridgePauseInk

            Canvas { ctx, canvasSize in
                RidgePauseDraw.draw(&ctx, image: world, geo: geo, f: frame, size: canvasSize)
            }
            .accessibilityHidden(true)

            ZStack(alignment: .topLeading) {
                linesLayer(fs: fs)
                choiceLayer(geo: geo, fs: fs)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)

            // fade in from the night ink over 600 ms
            if input.t < 0.6 {
                ridgePauseInk.opacity(1 - RidgePauseMath.cl(input.t / 0.6))
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

    /// one soft tap when a line starts (plays once per line id)
    private func cueHaptics() -> Bool {
        if let line = input.currentLine {
            input.haptics.cue("ridge.line.\(line.id)", .soft)
        }
        return true
    }

    // MARK: Lines (the 30 seconds)

    private func linesOpacity() -> Double {
        switch input.phase {
        case .waiting:
            return 1
        case .choosing(_, _, let from):
            if from != nil { return 0 }
            let age = input.choice?.age ?? 1
            return 1 - RidgePauseMath.cl(age / 0.35)
        case .committed:
            return 0
        }
    }

    private func visibleLines() -> [PauseLine] {
        let lines = input.script.lines
        guard let last = lines.last else { return [] }
        if case .waiting = input.phase {
            let t = input.t
            return lines.filter { l in
                t >= l.start && (l.id == last.id || t < l.end + 0.24)
            }
        }
        return [last]
    }

    @ViewBuilder
    private func linesLayer(fs: CGFloat) -> some View {
        let size = input.layout.size
        let top = max(input.layout.contentTop, size.height * 0.165)
        let lastID = input.script.lines.last?.id
        let opacity = linesOpacity()
        if opacity > 0.001 {
            ZStack(alignment: .top) {
                ForEach(visibleLines()) { line in
                    RidgeLineView(line: line,
                                  t: input.t,
                                  isLast: line.id == lastID,
                                  reduceMotion: input.reduceMotion,
                                  fs: fs)
                }
            }
            .frame(width: size.width, alignment: .top)
            .padding(.top, top)
            .opacity(opacity)
        }
    }

    // MARK: Doors

    @ViewBuilder
    private func choiceLayer(geo: RidgePauseGeo, fs: CGFloat) -> some View {
        if let ch = input.choice {
            let fade = input.committedAge.map { 1 - RidgePauseMath.cl($0 / 0.25) } ?? 1
            ZStack(alignment: .topLeading) {
                if let fromIndex = ch.from, ch.age < 0.7, input.committedAge == nil,
                   fromIndex >= 0, fromIndex < input.script.choices.count {
                    band(input.script.choices[fromIndex], age: ch.age, leaving: true, geo: geo, fs: fs)
                }
                band(ch.choice, age: ch.age, leaving: false, geo: geo, fs: fs)
            }
            .opacity(fade)
        }
    }

    /// a door's words, centred in the sky between the top of the content area and its peak
    private func band(_ choice: PauseChoice, age: Double, leaving: Bool, geo: RidgePauseGeo, fs: CGFloat) -> some View {
        let size = input.layout.size
        let c = geo.cam(choice.key)
        let bottom = geo.tipY(c) - (choice.key == .gym ? 62 : 28)
        let rm = input.reduceMotion
        let fadeIn = RidgePauseMath.ease(age / 0.35)
        let move = RidgePauseMath.ease(age / 0.7)
        let opacity = leaving ? 1 - fadeIn : fadeIn
        let dy: CGFloat = rm ? 0 : CGFloat(leaving ? -12 * move : 12 * (1 - move))
        return RidgeBand(top: input.layout.contentTop, bottom: bottom) {
            RidgeChoiceBlock(choice: choice, age: leaving ? 10 : age, reduceMotion: rm, fs: fs)
                .opacity(opacity)
                .offset(y: dy)
                .accessibilityHidden(leaving)
        }
        .frame(width: size.width, height: size.height)
    }
}
