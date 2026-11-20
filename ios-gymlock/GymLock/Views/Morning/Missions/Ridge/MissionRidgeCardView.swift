//
//  MissionRidgeCardView.swift
//  GymLock
//
//  The living hero card of the Ridge look (light dawn): baked painted layers under a slowly breathing
//  camera, drifting mist, a breathing sun, god-rays, birds, footsteps walking the trail to the coral gym
//  dot, and the mission's badge on the trail. Changing `mission` pans/zooms the camera to its framing.
//

import SwiftUI

/// A camera move to a new mission. Value type: the Canvas gets a copy.
nonisolated struct MissionRidgeMove: Sendable {
    let from: MissionRidgeCam
    let fromMission: MissionFigure
    let outPoint: CGPoint      // where the leaving badge sat, in points
    let t0: CGFloat            // seconds on the view's clock
    let crossfade: Bool        // Reduce Motion: 250 ms crossfade instead of a pan
}

/// Everything one frame needs, copied out of view state so the Canvas closure touches no isolated state.
nonisolated struct MissionRidgeCardRenderer: Sendable {
    static let panDuration: CGFloat = 0.9
    static let fadeDuration: CGFloat = 0.25
    static let badgeRadius: CGFloat = 22

    let loaded: MissionRidgeLoaded
    let mission: MissionFigure
    let move: MissionRidgeMove?
    let reduced: Bool
    let t: CGFloat             // seconds on the view's clock
    let appearT: CGFloat       // when the scene became ready
    /// `Theme.ink` and `Theme.accent`, handed in by the view: the renderer runs inside a Canvas and
    /// reads no main-actor state.
    let ink: Color
    let coral: Color

    /// The camera of `mission` at time t, before breathing, and whether a pan is under way.
    static func baseCamera(geo: MissionRidgeGeometry, data: MissionRidgeWorldData, trail: MissionRidgeTrail,
                           mission: MissionFigure, move: MissionRidgeMove?, t: CGFloat) -> (cam: MissionRidgeCam, panning: Bool) {
        let target = geo.camera(for: data.frame(for: mission), trail: trail)
        if let mv = move, !mv.crossfade {
            let p = (t - mv.t0) / panDuration
            if p < 1 {
                return (geo.mix(mv.from, target, MissionRidgeMath.easeInOut(p)), true)
            }
        }
        return (target, false)
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1,
              let set = loaded.sets["day"], let trail = loaded.data.trails["card"] else { return }
        let geo = MissionRidgeGeometry(size: size, data: loaded.data)
        let tm: CGFloat = reduced ? 2.2 : t
        let base = MissionRidgeCardRenderer.baseCamera(geo: geo, data: loaded.data, trail: trail, mission: mission, move: move, t: t)
        let cam = reduced ? base.cam : geo.breathe(base.cam, t: tm)

        // badge state
        var inT: CGFloat = appearT + 0.35
        if let mv = move { inT = mv.crossfade ? mv.t0 + 0.1 : mv.t0 + 0.8 }
        let bt = t - inT
        let badge = (!base.panning && bt > 0) ? bt : -1

        compose(ctx, geo: geo, set: set, trail: trail, cam: cam, mission: mission, tm: tm, fade: 1, badgeTime: badge, outBadge: true)

        // Reduce Motion: the previous picture dissolves away over the new one
        if let mv = move, mv.crossfade {
            let q = (t - mv.t0) / MissionRidgeCardRenderer.fadeDuration
            if q < 1 {
                let oldCam = reduced ? mv.from : geo.breathe(mv.from, t: tm)
                compose(ctx, geo: geo, set: set, trail: trail, cam: oldCam, mission: mv.fromMission, tm: tm,
                        fade: 1 - MissionRidgeMath.easeInOut(q), badgeTime: 10, outBadge: false)
            }
        }
    }

    private func compose(_ ctx: GraphicsContext, geo: MissionRidgeGeometry, set: MissionRidgeSet, trail: MissionRidgeTrail,
                         cam: MissionRidgeCam, mission: MissionFigure, tm: CGFloat, fade: CGFloat, badgeTime: CGFloat, outBadge: Bool) {
        let painter = MissionRidgePainter(geo: geo, set: set, trail: trail, cam: cam, t: tm, reduced: reduced, fade: fade, mistScale: 1, ink: ink)
        painter.paintWorld(ctx, sunK: 1, lift: 0, birds: true)
        let near = painter.plane(.near)
        let frame = loaded.data.frame(for: mission)
        paintTrail(ctx, tf: near, trail: trail, upTo: Int((frame.u * CGFloat(trail.n)).rounded()), fade: fade)
        if !reduced { paintFootsteps(ctx, tf: near, trail: trail, tm: tm, fade: fade) }
        paintGym(ctx, tf: near, trail: trail, tm: tm, fade: fade)
        painter.drawLayer(ctx, .fg)

        // the badge leaving pops out, the new one springs in
        if outBadge, let mv = move, !mv.crossfade {
            let p = (t - mv.t0) / 0.12
            if p < 1.2 {
                let e = MissionRidgeMath.easeInOut(p)
                drawBadge(ctx, figure: mv.fromMission, at: mv.outPoint, scale: MissionRidgeMath.lerp(1, 0.6, e), alpha: (1 - e) * fade)
            }
        }
        if badgeTime > 0 {
            let s = trail.sample(at: frame.u)
            let bx = near.tx + s.x * near.w
            let by = near.ty + s.y * near.h
            let decay = CGFloat(exp(Double(-8 * badgeTime)))
            let spring = 1 - decay * cos(12 * badgeTime)
            let sc = 0.6 + 0.4 * spring
            let center = CGPoint(x: bx, y: by)
            drawBadge(ctx, figure: mission, at: center, scale: sc, alpha: MissionRidgeMath.clamp(badgeTime / 0.1) * fade)
            // "you are here": a ring ripples out every 4 s
            if !reduced && badgeTime > 0.5 {
                let rp = MissionRidgeMath.mod(tm / 4, 1)
                if rp < 0.62 {
                    let q = rp / 0.62
                    let r = MissionRidgeCardRenderer.badgeRadius + MissionRidgeMath.easeOut(q) * 17
                    let ring = Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2))
                    ctx.stroke(ring, with: .color(ink.opacity(Double(0.3 * (1 - q) * fade))), lineWidth: 1.4)
                }
            }
        }
    }

    private func drawBadge(_ ctx: GraphicsContext, figure: MissionFigure, at p: CGPoint, scale: CGFloat, alpha: CGFloat) {
        let a = MissionRidgeMath.clamp(alpha)
        if a <= 0.01 { return }
        guard let sym = ctx.resolveSymbol(id: figure) else { return }
        var c = ctx
        c.opacity = Double(a)
        c.translateBy(x: p.x, y: p.y)
        c.scaleBy(x: scale, y: scale)
        c.draw(sym, at: .zero, anchor: .center)
    }

    /// The trail in ink: solid where you have come from, dotted ahead to the gym.
    private func paintTrail(_ ctx: GraphicsContext, tf: MissionRidgePlaneTf, trail: MissionRidgeTrail, upTo im: Int, fade: CGFloat) {
        let n = trail.n
        let ink = self.ink
        func pt(_ i: Int) -> CGPoint {
            return CGPoint(x: tf.tx + trail.x[i] * tf.w, y: tf.ty + trail.y[i] * tf.h)
        }
        func wk(_ i: Int) -> CGFloat {
            return trail.w[i] * tf.w
        }
        // the stub running off the bottom edge
        var stub = Path()
        let p0 = pt(0)
        stub.move(to: p0)
        stub.addLine(to: CGPoint(x: p0.x - tf.w * 0.03, y: tf.ty + 1.1 * tf.h))
        ctx.stroke(stub, with: .color(ink.opacity(Double(0.82 * fade))),
                   style: StrokeStyle(lineWidth: MissionRidgeMath.clamp(wk(0) * 0.17, 0.9, 2.6), lineCap: .round, lineJoin: .round))

        func seg(_ a: Int, _ b: Int, dotted: Bool) {
            var i = a
            while i < b {
                let wd = MissionRidgeMath.clamp(wk(i) * 0.17, dotted ? 1.3 : 0.9, 2.6)
                let m = min(n, i + 3)
                let k = (m - 1 > i + 1) ? (m - 1) : (i + 1)
                var p = Path()
                p.move(to: pt(i))
                p.addLine(to: pt(i + 1))
                p.addLine(to: pt(k))
                p.addLine(to: pt(m))
                let style: StrokeStyle
                if dotted {
                    style = StrokeStyle(lineWidth: wd, lineCap: .round, lineJoin: .round, dash: [0.01, wd * 3.2])
                } else {
                    style = StrokeStyle(lineWidth: wd, lineCap: .round, lineJoin: .round)
                }
                ctx.stroke(p, with: .color(ink.opacity(Double((dotted ? 0.7 : 0.82) * fade))), style: style)
                i += 3
            }
        }
        seg(0, min(n, max(0, im)), dotted: false)
        seg(min(n, max(0, im)), n, dotted: true)
    }

    /// Footstep pairs walking toward the gym, one pair every 0.5 s, each fading over 8 s.
    private func paintFootsteps(_ ctx: GraphicsContext, tf: MissionRidgePlaneTf, trail: MissionRidgeTrail, tm: CGFloat, fade: CGFloat) {
        let n = trail.n
        let steps = max(1, loaded.data.stepCount)
        let cyc = CGFloat(steps) * 0.5 + 3
        for i in 0..<steps {
            let age = MissionRidgeMath.mod(tm - CGFloat(i) * 0.5, cyc)
            if age > 8 { continue }
            let rise: CGFloat = min(1, age / 0.18)
            let fall = CGFloat(pow(Double(1 - age / 8), 1.4))
            let a: CGFloat = rise * fall * 0.78
            if a < 0.02 { continue }
            let s = (CGFloat(i) + 0.5) / CGFloat(steps)
            let u = 1 - CGFloat(pow(Double(1 - s), 1.35))
            let k = MissionRidgeMath.clamp(u) * CGFloat(n)
            let j = min(n - 1, Int(k))
            let ff = k - CGFloat(j)
            let x0 = tf.tx + trail.x[j] * tf.w
            let y0 = tf.ty + trail.y[j] * tf.h
            let x1 = tf.tx + trail.x[j + 1] * tf.w
            let y1 = tf.ty + trail.y[j + 1] * tf.h
            let px = MissionRidgeMath.lerp(x0, x1, ff)
            let py = MissionRidgeMath.lerp(y0, y1, ff)
            let dl = max(0.0001, hypot(x1 - x0, y1 - y0))
            let tx = (x1 - x0) / dl
            let ty = (y1 - y0) / dl        // tangent, toward the gym
            let nx = -ty
            let ny = tx
            let wd = MissionRidgeMath.lerp(trail.w[j], trail.w[j + 1], ff) * tf.w
            let r = MissionRidgeMath.clamp(wd * 0.055, 0.8, 2.3)
            let side = MissionRidgeMath.clamp(wd * 0.14, 1.2, 4.2)
            let par: CGFloat = (i % 2 == 1) ? 1 : -1
            let ang = atan2(ty, tx) + CGFloat.pi / 2
            let color = ink.opacity(Double(a * fade))
            for sd in [CGFloat(-1), CGFloat(1)] {
                let lead: CGFloat = (sd == par) ? r * 1.6 : -r * 1.6
                let cx = px + nx * side * sd + tx * lead
                let cy = py + ny * side * sd + ty * lead
                let foot = Path(ellipseIn: CGRect(x: -r, y: -r * 1.35, width: r * 2, height: r * 2.7))
                    .applying(CGAffineTransform(translationX: cx, y: cy).rotated(by: ang))
                ctx.fill(foot, with: .color(color))
            }
        }
    }

    /// The gym: the one coral mark, a halo pulsing every 3 s.
    private func paintGym(_ ctx: GraphicsContext, tf: MissionRidgePlaneTf, trail: MissionRidgeTrail, tm: CGFloat, fade: CGFloat) {
        let n = trail.n
        let g = CGPoint(x: tf.tx + trail.x[n] * tf.w, y: tf.ty + trail.y[n] * tf.h)
        let ph: CGFloat = reduced ? 0.3 : MissionRidgeMath.mod(tm / 3, 1)
        let breath: CGFloat = reduced ? 0.5 : 0.5 + 0.5 * sin(tm * (MissionRidgeMath.tau / 3) - 1.5)
        let coral = self.coral
        let halo = Gradient(stops: [
            Gradient.Stop(color: coral.opacity(Double((0.34 + 0.12 * breath) * fade)), location: 0),
            Gradient.Stop(color: coral.opacity(0), location: 1)
        ])
        let haloPath = Path(ellipseIn: CGRect(x: g.x - 15, y: g.y - 15, width: 30, height: 30))
        ctx.fill(haloPath, with: .radialGradient(halo, center: g, startRadius: 0, endRadius: 15))
        let pr = 4.5 + MissionRidgeMath.easeOut(ph) * 13
        let pulse = Path(ellipseIn: CGRect(x: g.x - pr, y: g.y - pr, width: pr * 2, height: pr * 2))
        ctx.stroke(pulse, with: .color(coral.opacity(Double(0.5 * (1 - ph) * fade))), lineWidth: 1.2)
        let dot = Path(ellipseIn: CGRect(x: g.x - 4.4, y: g.y - 4.4, width: 8.8, height: 8.8))
        ctx.fill(dot, with: .color(coral.opacity(Double(fade))))
        ctx.stroke(dot, with: .color(Color.white.opacity(Double(0.9 * fade))), lineWidth: 1.2)
    }
}

/// The white mission badge: disc, soft shadow, hairline and the line icon. Resolved once as a Canvas symbol.
private struct MissionRidgeBadgeSymbol: View {
    let figure: MissionFigure

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.20), radius: 6.5, x: 0, y: 4)
            Circle()
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75)
                .frame(width: 44, height: 44)
            MissionRidgeIcon(figure: figure, size: 22, color: Theme.ink)
        }
        .frame(width: 76, height: 76)
    }
}

struct MissionRidgeCardView: View {
    let mission: MissionFigure
    let onLand: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var loaded: MissionRidgeLoaded?
    @State private var epoch = Date()
    @State private var appearT: Double = 0
    @State private var viewSize: CGSize = .zero
    @State private var move: MissionRidgeMove?
    @State private var busy = true          // a pan, a pop or the first fade is under way: run every frame
    @State private var landTask: Task<Void, Never>?

    init(mission: MissionFigure, onLand: (() -> Void)? = nil) {
        self.mission = mission
        self.onLand = onLand
    }

    var body: some View {
        let paused = scenePhase != .active || (reduceMotion && !busy)
        TimelineView(.animation(minimumInterval: busy ? nil : 1.0 / 30.0, paused: paused)) { timeline in
            frameView(t: CGFloat(timeline.date.timeIntervalSince(epoch)))
        }
        .clipped()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            viewSize = newSize
        }
        .onAppear { MissionRidgeStore.shared.acquire() }
        .onDisappear {
            MissionRidgeStore.shared.release()
            landTask?.cancel()
        }
        .task { await loadWorld() }
        .onChange(of: mission) { old, new in
            missionChanged(from: old, to: new)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func frameView(t: CGFloat) -> some View {
        // copy what the Canvas needs: its closure must not touch view state
        let renderer = loaded.map {
            MissionRidgeCardRenderer(loaded: $0, mission: mission, move: move, reduced: reduceMotion, t: t,
                                     appearT: CGFloat(appearT), ink: Theme.ink, coral: Theme.accent)
        }
        let fadeIn = MissionRidgeMath.easeOut((t - CGFloat(appearT)) / 0.4)
        Canvas { ctx, size in
            renderer?.draw(&ctx, size: size)
        } symbols: {
            ForEach(MissionFigure.allCases, id: \.self) { figure in
                MissionRidgeBadgeSymbol(figure: figure).tag(figure)
            }
        }
        .opacity(Double(fadeIn))
    }

    private func loadWorld() async {
        let result = await MissionRidgeStore.shared.load(sets: ["day"])
        if Task.isCancelled { return }
        appearT = Date().timeIntervalSince(epoch)
        loaded = result
        busy = true
        try? await Task.sleep(for: .seconds(1.4))
        if Task.isCancelled { return }
        busy = false
    }

    private func missionChanged(from old: MissionFigure, to new: MissionFigure) {
        landTask?.cancel()
        guard let loaded, let trail = loaded.data.trails["card"], viewSize.width > 1, viewSize.height > 1 else {
            move = nil
            return
        }
        let t = CGFloat(Date().timeIntervalSince(epoch))
        let geo = MissionRidgeGeometry(size: viewSize, data: loaded.data)
        let cur = MissionRidgeCardRenderer.baseCamera(geo: geo, data: loaded.data, trail: trail, mission: old, move: move, t: t).cam
        let near = geo.plane(.near, cam: cur)
        let s = trail.sample(at: loaded.data.frame(for: old).u)
        let out = CGPoint(x: near.tx + s.x * near.w, y: near.ty + s.y * near.h)
        let reduced = reduceMotion
        move = MissionRidgeMove(from: cur, fromMission: old, outPoint: out, t0: t, crossfade: reduced)
        busy = true
        let delay: Double = reduced ? 0.25 : Double(MissionRidgeCardRenderer.panDuration)
        landTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            onLand?()
            try? await Task.sleep(for: .seconds(1.2))
            if Task.isCancelled { return }
            busy = false
        }
    }
}
