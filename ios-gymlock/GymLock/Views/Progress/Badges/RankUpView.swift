//
//  RankUpView.swift
//  GymLock — Badges
//
//  CS:GO-style rank-up, native SwiftUI (TimelineView + Canvas).
//  1:1 port of the approved animation: same 30-fps-unit timeline, same springs, same
//  deterministic random() (so every particle lands in the same place), same layout in a
//  1080×1920 design box that adapts to any screen shape.
//
//  The old emblem (previous rung, or the badge itself locked) charges up, spins twice and
//  turns into the new one, which lands with a flash, a hex shockwave, sparks and light rays;
//  then RANK UP / name / rule / tier chip. Idles until tapped.
//

import SwiftUI

// MARK: - timeline constants (30-fps units)

enum RankUpTiming {
    static let spinStart = 38.0
    static let impact = 60.0
    static let name = 70.0
    static let revealDone = 96.0
    static let tapReady = 100.0
}

// MARK: - helpers shared with the web version

/// Remotion's random(): mulberry32 over a 32-bit string hash. Bit-exact port.
enum RemotionRandom {
    static func random(_ seed: String) -> Double {
        var hash: Int32 = 0
        for unit in seed.utf16 {
            hash = (hash &<< 5) &- hash &+ Int32(unit)
        }
        var t = UInt32(bitPattern: hash) &+ 0x6d2b79f5
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

/// Closed-form damped spring, identical to Remotion's spring() (zeta ≥ 1 → critically damped).
func springValue(frame: Double, fps: Double, damping: Double = 10, stiffness: Double = 100, mass: Double = 1) -> Double {
    if frame <= 0 { return 0 }
    let t = frame / fps
    let w0 = (stiffness / mass).squareRoot()
    let zeta = damping / (2 * (stiffness * mass).squareRoot())
    if zeta < 1 {
        let wd = w0 * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * w0 * t) * (cos(wd * t) + (zeta * w0 / wd) * sin(wd * t))
    }
    return 1 - exp(-w0 * t) * (1 + w0 * t)
}

@inline(__always) private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
@inline(__always) private func easeInOutCubic(_ u: Double) -> Double { u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2 }

/// CSS hsl(h, s%, l%) → Color.
private func hsl(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> Color {
    let s = s / 100, l = l / 100
    let c = (1 - abs(2 * l - 1)) * s
    let hp = (h.truncatingRemainder(dividingBy: 360)) / 60
    let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
    var (r, g, b) = (0.0, 0.0, 0.0)
    switch hp {
    case 0..<1: (r, g, b) = (c, x, 0)
    case 1..<2: (r, g, b) = (x, c, 0)
    case 2..<3: (r, g, b) = (0, c, x)
    case 3..<4: (r, g, b) = (0, x, c)
    case 4..<5: (r, g, b) = (x, 0, c)
    default: (r, g, b) = (c, 0, x)
    }
    let m = l - c / 2
    return Color(.sRGB, red: r + m, green: g + m, blue: b + m, opacity: a)
}

// MARK: - layout (design box 1080×1920, fitted to the screen's shape)

struct RankUpLayout {
    static let designW = 1080.0
    static let designH = 1920.0
    static let badgeX = 540.0
    static let badgeY = 790.0
    static let badgeW = 600.0

    let size: CGSize
    let compW: Double
    let compH: Double
    let scale: Double   // screen points per composition px
    let ox: Double      // design box offset inside the composition
    let oy: Double

    init(size: CGSize) {
        self.size = size
        let a = Double(size.width / max(1, size.height))
        if a < Self.designW / Self.designH {
            compW = Self.designW
            compH = (Self.designW / a / 2).rounded() * 2
        } else {
            compW = (Self.designH * a / 2).rounded() * 2
            compH = Self.designH
        }
        scale = Double(size.width) / compW
        ox = (compW - Self.designW) / 2
        oy = (compH - Self.designH) / 2
    }

    /// Where the badge sits on screen (for the fly-to-slot hand-off).
    var badgeFrame: CGRect {
        let w = Self.badgeW * scale
        let h = w * 1.1
        let cx = (ox + Self.badgeX) * scale
        let cy = (oy + Self.badgeY) * scale
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }
}

// hex outline of the baked badge (R = 248 of 600 px → 82.67 in the 200×220 badge space)
private let hexOuter: [CGPoint] = (0..<6).map { i in
    let a = (-90.0 + Double(i) * 60.0) * .pi / 180
    let r = 248.0 / 3.0
    return CGPoint(x: 100 + r * cos(a), y: 110 + r * sin(a))
}

// MARK: - the view

struct RankUpView: View {
    let to: BadgeDefinition
    /// Previous rung (ladders) — nil = start from the locked version of `to`.
    let from: BadgeDefinition?
    /// 1 = normal, 0.35 = slow-mo (for reviewing).
    var playbackRate: Double = 1
    /// Called when the user taps after the reveal.
    var onContinue: () -> Void = {}

    @State private var start = Date()

    init(to: BadgeDefinition, from: BadgeDefinition?, playbackRate: Double = 1, onContinue: @escaping () -> Void = {}) {
        self.to = to
        self.from = from
        self.playbackRate = playbackRate
        self.onContinue = onContinue
        GymLockFonts.register()
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let f = max(0, timeline.date.timeIntervalSince(start)) * 30 * playbackRate
                Canvas(rendersAsynchronously: false) { ctx, size in
                    RankUpRenderer(to: to, from: from, f: f, layout: RankUpLayout(size: size)).draw(&ctx)
                } symbols: {
                    RankUpRuleText(badge: to).tag(RankUpSymbol.rule)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let f = Date().timeIntervalSince(start) * 30 * playbackRate
                if f >= RankUpTiming.tapReady { onContinue() }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            GymLockFonts.register()
            start = Date()
            BadgeHaptics.shared.playRankUp(tier: to.tier, rate: playbackRate)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(to.isLadder ? "Rank up" : "Badge unlocked"): \(to.name). \(to.rule)"))
        .accessibilityAddTraits(.isButton)
        // VoiceOver's double tap continues at once; the reveal is not
        // something it can watch.
        .accessibilityAction { onContinue() }
    }
}

// MARK: - renderer (pure function of the frame)

private struct RankUpRenderer {
    let to: BadgeDefinition
    let from: BadgeDefinition?
    let f: Double
    let layout: RankUpLayout

    private func sp(_ x: Double, damping: Double = 10, stiffness: Double = 100, mass: Double = 1) -> Double {
        // the web version scales frames by K = fps/30 and passes fps; time is identical → use fps 30 here
        springValue(frame: x, fps: 30, damping: damping, stiffness: stiffness, mass: mass)
    }

    func draw(_ ctx: inout GraphicsContext) {
        let L = layout
        let W = RankUpLayout.designW
        let BX = RankUpLayout.badgeX, BY = RankUpLayout.badgeY, BADGE_W = RankUpLayout.badgeW
        let tier = to.tier
        let acc = tier.accentRGB
        func A(_ o: Double) -> Color { Color(.sRGB, red: acc.r / 255, green: acc.g / 255, blue: acc.b / 255, opacity: o) }
        let rank = Double(tier.rank)
        let I = 0.45 + 0.55 * rank / 9
        let prism = tier.isPrism
        let ladder = to.isLadder

        // ---------- timeline ----------
        let bgIn = clamp01(f / 10)
        let enter = sp(f - 4, damping: 13, stiffness: 140)
        let charge = clamp01((f - 14) / 26)
        let u = clamp01((f - RankUpTiming.spinStart) / (RankUpTiming.impact - RankUpTiming.spinStart))
        let theta = easeInOutCubic(u) * .pi * 4
        let spinning = f >= RankUpTiming.spinStart && f < RankUpTiming.impact
        let swapped = f >= RankUpTiming.spinStart && theta >= .pi / 2
        let scaleX = spinning ? max(0.04, abs(cos(theta))) : 1
        let spinFlash = spinning ? pow(1 - abs(cos(theta)), 3) * 0.85 : 0
        let ti = f - RankUpTiming.impact
        let impacted = ti >= 0
        let punch = impacted ? 1.32 - 0.32 * sp(ti, damping: 9, stiffness: 180) : 1
        let tremble = f < RankUpTiming.impact ? 8 * pow(charge, 1.6) : 0
        let tx = tremble * sin(f * 7.3)
        let tyT = tremble * 0.6 * cos(f * 9.1)
        let float = f > 90 ? 7 * sin((f - 90) / 14) : 0
        let shineT = f >= 88 ? (f - 88).truncatingRemainder(dividingBy: 100) / 30 : 9
        let shine = shineT <= 1 ? -0.3 + shineT * 1.6 : -1

        var sx = 0.0, sy = 0.0
        if impacted {
            let e = exp(-ti / 5) * 18 * I
            sx += e * sin(ti * 2.3)
            sy += e * cos(ti * 2.9)
        }
        let nameQ = f - RankUpTiming.name
        if nameQ >= 6 {
            let e = exp(-(nameQ - 6) / 4) * 9
            sy += e * cos((nameQ - 6) * 2.5)
        }

        let glowLevel = (impacted ? 0.75 + 0.6 * exp(-ti / 8) : 0.15 + 0.45 * charge) * (0.9 + 0.1 * sin(f / 9))
        let raysOn = impacted ? clamp01(ti / 10) * (0.85 + 0.15 * sin(f / 11)) : 0.18 * charge
        let flash = impacted ? max(0, ti < 1 ? ti * 0.9 : 0.9 * (1 - (ti - 1) / 11)) : 0

        ctx.opacity = bgIn
        let full = CGRect(origin: .zero, size: L.size)

        // ---------- backdrop ----------
        ctx.fill(Path(full), with: .color(Color(.sRGB, red: 4 / 255, green: 5 / 255, blue: 10 / 255, opacity: 0.94)))
        let tintC = CGPoint(x: L.size.width / 2, y: (L.oy + BY) * L.scale)
        let tintR = farthestCorner(from: tintC, in: full)
        ctx.fill(Path(full), with: .radialGradient(
            Gradient(stops: [.init(color: A(0.42 * glowLevel), location: 0), .init(color: A(0.1 * glowLevel), location: 0.34), .init(color: A(0), location: 0.62)]),
            center: tintC, startRadius: 0, endRadius: tintR))

        // ---------- design box (with screen shake) ----------
        var d = ctx
        d.translateBy(x: (L.ox + sx) * L.scale, y: (L.oy + sy) * L.scale)
        d.scaleBy(x: L.scale, y: L.scale)

        // light rays (radially faded)
        if raysOn > 0.001 {
            d.drawLayer { layer in
                layer.opacity *= raysOn
                let c = CGPoint(x: BX, y: BY)
                let maskR = 1300.0 * 2.0.squareRoot()
                layer.clipToLayer { m in
                    m.fill(Path(CGRect(x: BX - 1300, y: BY - 1300, width: 2600, height: 2600)), with: .radialGradient(
                        Gradient(stops: [.init(color: .black, location: 0.08), .init(color: .black.opacity(0.5), location: 0.24), .init(color: .black.opacity(0), location: 0.46)]),
                        center: c, startRadius: 0, endRadius: maskR))
                }
                let rayCount = Int((14 + 12 * I).rounded())
                drawRays(&layer, center: c, count: rayCount, width: 0.42, rotationDeg: f * 0.4, color: A(1), opacity: 0.55)
                drawRays(&layer, center: c, count: Int((Double(rayCount) * 0.7).rounded()), width: 0.3, rotationDeg: -f * 0.25 + 7, color: .white, opacity: 0.28)
            }
        }

        // glow behind the badge
        let glowR = 460 * 2.0.squareRoot()
        d.drawLayer { g in
            g.opacity *= glowLevel
            g.clip(to: Path(ellipseIn: CGRect(x: BX - 460, y: BY - 460, width: 920, height: 920)))
            g.fill(Path(CGRect(x: BX - 460, y: BY - 460, width: 920, height: 920)), with: .radialGradient(
                Gradient(stops: [.init(color: A(0.75), location: 0), .init(color: A(0.25), location: 0.32), .init(color: A(0), location: 0.66)]),
                center: CGPoint(x: BX, y: BY), startRadius: 0, endRadius: glowR))
        }

        // charge streaks
        if f >= 14 && f < RankUpTiming.impact + 2 {
            let N = Int((24 + 30 * I).rounded())
            for i in 0..<N {
                let a0 = RemotionRandom.random("ca-\(i)") * .pi * 2
                let r0 = 380 + RemotionRandom.random("cr-\(i)") * 380
                let delay = RemotionRandom.random("cd-\(i)") * 14
                let p = clamp01((f - 14 - delay) / 18)
                if p <= 0 || p >= 1 { continue }
                let e = p * p
                let r = r0 * (1 - e)
                let a = a0 + e * 1.8
                let x = BX + cos(a) * r, y = BY + sin(a) * r
                let tail = 14 + 40 * e
                let col: Color = prism ? hsl(Double((i * 47) % 360), 90, 70) : (i % 3 != 0 ? A(1) : .white)
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + cos(a) * tail, y: y + sin(a) * tail))
                var l = d
                l.opacity *= sin(p * .pi)
                l.stroke(path, with: .color(col), style: StrokeStyle(lineWidth: 3.5 - 2 * e, lineCap: .round))
            }
        }

        // hex shockwaves
        struct Wave { let start: Double; let len: Double; let max: Double; let color: Color; let w: Double }
        var waves = [Wave(start: 0, len: 24, max: 3.4, color: A(1), w: 9), Wave(start: 4, len: 26, max: 2.8, color: .white, w: 4)]
        if I > 0.7 { waves.append(Wave(start: 9, len: 30, max: 4.2, color: A(1), w: 5)) }
        for wv in waves {
            let t = (ti - wv.start) / wv.len
            if t < 0 || t > 1 { continue }
            let s = 1 + (wv.max - 1) * (1 - pow(1 - t, 2))
            let k = s * BADGE_W / 200
            var path = Path()
            for (j, p) in hexOuter.enumerated() {
                let q = CGPoint(x: BX + (p.x - 100) * k, y: BY + (p.y - 110) * k)
                if j == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            path.closeSubpath()
            var l = d
            l.opacity *= 1 - t
            // stroke width is defined in badge space then scaled → (w(1-t)+0.6) × 3 in design px
            l.stroke(path, with: .color(wv.color), lineWidth: (wv.w * (1 - t) + 0.6) / s * k)
        }

        // ---------- the badge ----------
        let shown = (swapped || impacted) ? to : (from ?? to)
        let shownLocked = !(swapped || impacted) && from == nil
        if let ui = BadgeImages.image(for: shown.id) {
            var b = d
            b.opacity *= clamp01(enter * 1.4)
            b.translateBy(x: BX + tx, y: BY + tyT + float)
            let S = (0.55 + 0.45 * enter) * punch
            b.scaleBy(x: S * scaleX, y: S)
            let rect = CGRect(x: -BADGE_W / 2, y: -BADGE_W * 1.1 / 2, width: BADGE_W, height: BADGE_W * 1.1)
            let img = b.resolve(Image(uiImage: ui))
            b.drawLayer { l in
                if shownLocked { l.addFilter(.colorMatrix(BadgeLockedFilter.matrix)) }
                l.draw(img, in: rect)
            }
            // white flash while edge-on during the spin (masked to the badge)
            if spinFlash > 0.01 {
                b.drawLayer { l in
                    l.draw(img, in: rect)
                    l.blendMode = .sourceAtop
                    l.fill(Path(rect), with: .color(.white.opacity(spinFlash)))
                }
            }
            // sweeping shine (masked to the badge) — CSS linear-gradient(112deg …)
            if impacted && shine > -0.4 && shine < 1.4 {
                b.drawLayer { l in
                    l.draw(img, in: rect)
                    l.blendMode = .sourceAtop
                    let ang = 112.0 * .pi / 180
                    let dir = CGPoint(x: sin(ang), y: -cos(ang))
                    let len = abs(rect.width * sin(ang)) + abs(rect.height * cos(ang))
                    let c = CGPoint(x: rect.midX, y: rect.midY)
                    let g0 = CGPoint(x: c.x - dir.x * len / 2, y: c.y - dir.y * len / 2)
                    let p0 = CGPoint(x: g0.x + dir.x * len * (shine - 0.14), y: g0.y + dir.y * len * (shine - 0.14))
                    let p1 = CGPoint(x: g0.x + dir.x * len * (shine + 0.14), y: g0.y + dir.y * len * (shine + 0.14))
                    l.fill(Path(rect), with: .linearGradient(
                        Gradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.75), location: 0.5), .init(color: .white.opacity(0), location: 1)]),
                        startPoint: p0, endPoint: p1))
                }
            }
        }

        // sparks
        if impacted && ti < 48 {
            let N = Int((36 + 50 * I).rounded())
            for k in 0..<N {
                let a = RemotionRandom.random("sa-\(k)") * .pi * 2
                let v0 = 14 + RemotionRandom.random("sv-\(k)") * 34
                let drag = 0.9
                let travel = v0 * (1 - pow(drag, ti)) / (1 - drag)
                let vNow = v0 * pow(drag, ti)
                let x = BX + cos(a) * (120 + travel)
                let y = BY + sin(a) * (120 + travel) + 0.22 * ti * ti
                let life = 1 - ti / (26 + RemotionRandom.random("sl-\(k)") * 22)
                if life <= 0 { continue }
                let tail = max(5, vNow * 2.4)
                let col: Color = prism ? hsl(Double((k * 53) % 360), 95, 72) : (k % 3 == 0 ? .white : A(1))
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - cos(a) * tail, y: y - sin(a) * tail - 0.5 * ti))
                var l = d
                l.opacity *= life
                l.stroke(path, with: .color(col), style: StrokeStyle(lineWidth: k % 3 == 0 ? 3 : 4, lineCap: .round))
            }
        }

        // twinkling glints
        if impacted {
            let N = Int((8 + 14 * I).rounded())
            for k in 0..<N {
                let a = RemotionRandom.random("ga-\(k)") * .pi * 2
                let r = 300 + RemotionRandom.random("gr-\(k)") * 260
                let ph = RemotionRandom.random("gp-\(k)") * 60
                let t = (f - RankUpTiming.impact + ph).truncatingRemainder(dividingBy: 60) / 60
                let tw = sin(t * .pi)
                let x = BX + cos(a) * r
                let y = BY + sin(a) * r * 0.85 - t * 30
                let s = (6 + RemotionRandom.random("gs-\(k)") * 10) * tw
                let col: Color = prism ? hsl(Double((k * 61) % 360), 95, 80) : (k % 2 != 0 ? .white : A(1))
                var path = Path()
                path.move(to: CGPoint(x: x, y: y - s)); path.addLine(to: CGPoint(x: x + s * 0.28, y: y)); path.addLine(to: CGPoint(x: x, y: y + s)); path.addLine(to: CGPoint(x: x - s * 0.28, y: y)); path.closeSubpath()
                path.move(to: CGPoint(x: x - s, y: y)); path.addLine(to: CGPoint(x: x, y: y + s * 0.28)); path.addLine(to: CGPoint(x: x + s, y: y)); path.addLine(to: CGPoint(x: x, y: y - s * 0.28)); path.closeSubpath()
                var l = d
                l.opacity *= tw * clamp01(ti / 10)
                l.fill(path, with: .color(col))
            }
        }

        // ---------- text ----------
        // Oswald metrics: line box = 1.482 em (ascent 1.193 + descent 0.289), like CSS line-height: normal.

        // old rank caption (fades during the charge)
        let oldCaption = f < 40 ? clamp01((f - 6) / 8) * (1 - clamp01((f - 30) / 10)) : 0
        if oldCaption > 0 {
            let txt = Text((from?.name ?? "LOCKED").uppercased())
                .font(.custom(GymLockFonts.semiBold, fixedSize: 52)).tracking(52 * 0.12).foregroundColor(.white)
            var l = d
            l.opacity *= oldCaption * 0.6
            drawText(&l, txt, centerX: W / 2, top: 1150)
        }

        // RANK UP / BADGE UNLOCKED with lines either side
        let labelIn = clamp01((f - 64) / 14)
        if labelIn > 0 {
            let spacingEm = 0.8 - 0.4 * labelIn
            let label = Text(ladder ? "RANK UP" : "BADGE UNLOCKED")
                .font(.custom(GymLockFonts.semiBold, fixedSize: 40)).tracking(40 * spacingEm).foregroundColor(A(1))
            var l = d
            l.opacity *= labelIn
            let resolved = l.resolve(label)
            let ts = resolved.measure(in: CGSize(width: 2000, height: 400))
            let pad = 40 * spacingEm                       // CSS padding-left = letter-spacing (centres the glyphs)
            let textW = Double(ts.width) + pad
            let lineW = 140 * labelIn
            let total = lineW + 26 + textW + 26 + lineW
            let left = W / 2 - total / 2
            let rowH = 40 * 1.482
            let midY = 1110 + rowH / 2
            l.fill(Path(CGRect(x: left, y: midY - 1.5, width: lineW, height: 3)), with: .linearGradient(
                Gradient(colors: [A(0), A(1)]), startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + lineW, y: 0)))
            let rx = left + lineW + 26 + textW + 26
            l.fill(Path(CGRect(x: rx, y: midY - 1.5, width: lineW, height: 3)), with: .linearGradient(
                Gradient(colors: [A(1), A(0)]), startPoint: CGPoint(x: rx, y: 0), endPoint: CGPoint(x: rx + lineW, y: 0)))
            var tl = l
            tl.addFilter(.shadow(color: A(0.8), radius: 9))
            tl.draw(resolved, at: CGPoint(x: left + lineW + 26 + pad, y: 1110), anchor: .topLeading)
        }

        // name slam
        let nameLen = to.name.count
        let nameSize: Double = nameLen > 13 ? 88 : (nameLen > 10 ? 100 : 116)
        var nScale = 1.0, nSy = 1.0, nBlur = 0.0, nOp = 0.0
        if nameQ >= 0 {
            if nameQ < 6 {
                let e = pow(nameQ / 6, 2.2)
                nScale = 2.4 - 1.4 * e
                nBlur = 6 * (1 - e)
                nOp = min(1, nameQ / 2 + 0.2)
            } else {
                let w = exp(-(nameQ - 6) / 3) * cos((nameQ - 6) * 0.95)
                nSy = 1 - 0.12 * w
                nScale = 1 + 0.05 * w
                nOp = 1
            }
        }
        if nOp > 0 {
            let txt = Text(to.name.uppercased())
                .font(.custom(GymLockFonts.bold, fixedSize: nameSize)).tracking(nameSize * 0.04).foregroundColor(.white)
            var l = d
            l.opacity *= nOp
            // CSS: line-height 1.15, transform-origin 50% 80% of the line box
            let boxTop = 1175.0
            let origin = CGPoint(x: W / 2, y: boxTop + 0.8 * 1.15 * nameSize)
            l.translateBy(x: origin.x, y: origin.y)
            l.scaleBy(x: nScale, y: nScale * nSy)
            l.translateBy(x: -origin.x, y: -origin.y)
            if nBlur > 0.05 { l.addFilter(.blur(radius: nBlur)) }
            l.addFilter(.shadow(color: A(0.65), radius: 14))
            l.addFilter(.shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 4))
            let glyphTop = boxTop + (1.15 - 1.482) / 2 * nameSize
            drawText(&l, txt, centerX: W / 2, top: glyphTop)
        }

        // rule line (CSS: top 1330, width 800 centred, line-height 1.35)
        let subIn = clamp01((f - 84) / 12)
        if subIn > 0, let sym = d.resolveSymbol(id: RankUpSymbol.rule) {
            let size: Double = ladder ? 36 : 38
            let halfLeading = (1.35 - 1.193) / 2 * size
            var l = d
            l.opacity *= subIn
            l.draw(sym, at: CGPoint(x: W / 2, y: 1330 + (1 - subIn) * 16 + halfLeading), anchor: .top)
        }

        // tier chip
        let tierIn = clamp01((f - 92) / 12)
        if tierIn > 0 {
            let txt = Text(tier.rawValue.uppercased())
                .font(.custom(GymLockFonts.semiBold, fixedSize: 26)).tracking(26 * 0.3).foregroundColor(A(1))
            var l = d
            l.opacity *= tierIn
            let resolved = l.resolve(txt)
            let ts = resolved.measure(in: CGSize(width: 1000, height: 200))
            let w = Double(ts.width) + 28 + 20 + 4
            let h = 26 * 1.482 + 20 + 4
            let top = ladder ? 1418.0 : 1460.0
            let c = CGPoint(x: W / 2, y: top + h / 2)
            let sc = 0.9 + 0.1 * tierIn
            l.translateBy(x: c.x, y: c.y)
            l.scaleBy(x: sc, y: sc)
            let pill = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: h / 2)
            l.fill(pill, with: .color(A(0.1)))
            l.stroke(Path(roundedRect: CGRect(x: -w / 2 + 1, y: -h / 2 + 1, width: w - 2, height: h - 2), cornerRadius: h / 2 - 1), with: .color(A(0.6)), lineWidth: 2)
            l.draw(resolved, at: CGPoint(x: -w / 2 + 30, y: -h / 2 + 12), anchor: .topLeading)
        }

        // tap hint
        let tapIn = clamp01((f - 112) / 10) * (0.45 + 0.35 * (0.5 + 0.5 * sin(f / 8)))
        if tapIn > 0 {
            let txt = Text("TAP TO CONTINUE").font(.custom(GymLockFonts.semiBold, fixedSize: 30)).tracking(30 * 0.32).foregroundColor(.white)
            var l = d
            l.opacity *= tapIn
            drawText(&l, txt, centerX: W / 2, top: 1640)
        }

        // ---------- impact flash (screen space) ----------
        if flash > 0 {
            var l = ctx
            l.opacity *= flash
            l.fill(Path(full), with: .radialGradient(
                Gradient(stops: [.init(color: .white, location: 0), .init(color: A(0.7), location: 0.3), .init(color: A(0), location: 0.7)]),
                center: tintC, startRadius: 0, endRadius: tintR))
        }
    }

    // MARK: drawing helpers

    private func farthestCorner(from c: CGPoint, in r: CGRect) -> CGFloat {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            .map { hypot($0.x - c.x, $0.y - c.y) }.max() ?? 0
    }

    private func drawRays(_ ctx: inout GraphicsContext, center c: CGPoint, count n: Int, width: Double, rotationDeg: Double, color: Color, opacity: Double) {
        var path = Path()
        let R = 1300.0
        let rot = rotationDeg * .pi / 180
        for i in 0..<n {
            let a = Double(i) / Double(n) * .pi * 2 + rot
            let w = width * .pi / Double(n)
            path.move(to: c)
            path.addLine(to: CGPoint(x: c.x + cos(a - w) * R, y: c.y + sin(a - w) * R))
            path.addLine(to: CGPoint(x: c.x + cos(a + w) * R, y: c.y + sin(a + w) * R))
            path.closeSubpath()
        }
        var l = ctx
        l.opacity *= opacity
        l.fill(path, with: .color(color))
    }

    /// Single-line text, horizontally centred, top of the line box at `top`.
    private func drawText(_ ctx: inout GraphicsContext, _ text: Text, centerX: Double, top: Double) {
        let r = ctx.resolve(text)
        ctx.draw(r, at: CGPoint(x: centerX, y: top), anchor: .top)
    }

}

enum RankUpSymbol { static let rule = 1 }

/// The rule line under the name (wraps for long achievement rules), drawn by the Canvas as a symbol.
struct RankUpRuleText: View {
    let badge: BadgeDefinition
    var body: some View {
        let size: CGFloat = badge.isLadder ? 36 : 38
        Text(badge.rule)
            .font(.system(size: size, weight: badge.isLadder ? .semibold : .medium))
            .tracking(size * (badge.isLadder ? 0.2 : 0.01))
            .foregroundColor(.white.opacity(0.72))
            .lineSpacing((1.35 - 1.193) * size)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 800)
    }
}
