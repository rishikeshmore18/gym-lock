//
//  MissionRidgeBandView.swift
//  GymLock
//
//  The dark strip under the camera controls: stars twinkling, mist, a faint trail. `.found` brightens
//  the horizon; `.done` crossfades to first light over 1.6 s (sun, rays, the mist lifts 10 pt).
//  The top edge dissolves into the page.
//

import SwiftUI

/// One frame of the band, copied out of view state.
nonisolated struct MissionRidgeBandRenderer: Sendable {
    static let dawnDuration: CGFloat = 1.6
    static let easeSeconds: CGFloat = 0.2083   // 1 / (0.08 * 60): the found glow's approach rate

    let loaded: MissionRidgeLoaded
    let reduced: Bool
    let t: CGFloat
    let foundFrom: CGFloat
    let foundTarget: CGFloat
    let foundT: CGFloat
    let dawnT0: CGFloat?        // nil: not in first light
    /// `Theme.ink`, handed in by the view: the renderer runs inside a Canvas and reads no main-actor state.
    let ink: Color

    func foundK() -> CGFloat {
        let k = CGFloat(exp(Double(-(t - foundT) / MissionRidgeBandRenderer.easeSeconds)))
        return foundTarget + (foundFrom - foundTarget) * k
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1,
              let night = loaded.sets["night"], let dawn = loaded.sets["dawn"],
              let trail = loaded.data.trails["band"] else { return }
        let geo = MissionRidgeGeometry(size: size, data: loaded.data)
        let tm: CGFloat = reduced ? 2.2 : t
        var cam = geo.clampCam(MissionRidgeCam(cx: 0.5, cy: 0.46, z: 1))
        if !reduced { cam = geo.breathe(cam, t: tm) }

        var d: CGFloat = 0
        if let t0 = dawnT0 { d = MissionRidgeMath.easeInOut((t - t0) / MissionRidgeBandRenderer.dawnDuration) }
        let lift = 10 * d

        if d < 1 {
            let painter = MissionRidgePainter(geo: geo, set: night, trail: trail, cam: cam, t: tm, reduced: reduced, fade: 1, mistScale: 0.75, ink: ink)
            painter.paintWorld(ctx, sunK: foundK() * 0.5, lift: 0, birds: false)
            paintStars(ctx, painter: painter, tm: tm, k: 1 - d)
            paintTrail(ctx, painter: painter, k: 1 - d * 0.4)
        }
        if d > 0 {
            let painter = MissionRidgePainter(geo: geo, set: dawn, trail: trail, cam: cam, t: tm, reduced: reduced, fade: d, mistScale: 0.75, ink: ink)
            painter.paintWorld(ctx, sunK: d, lift: lift, birds: false)
            paintTrail(ctx, painter: painter, k: 0.7 * d)
        }
    }

    private func paintStars(_ ctx: GraphicsContext, painter: MissionRidgePainter, tm: CGFloat, k: CGFloat) {
        if k <= 0.01 { return }
        let tf = painter.plane(.sky)
        for s in loaded.data.stars {
            let tw: CGFloat = reduced ? 0.8 : 0.62 + 0.38 * sin(tm * s.f + s.p)
            let x = tf.tx + s.x * tf.w
            let y = tf.ty + s.y * tf.h
            let a = s.a * tw * k * 0.8
            let dot = Path(ellipseIn: CGRect(x: x - s.r, y: y - s.r, width: s.r * 2, height: s.r * 2))
            ctx.fill(dot, with: .color(Color(red: 1, green: 252.0 / 255.0, blue: 246.0 / 255.0).opacity(Double(a))))
        }
    }

    /// The faint trail. The web draws it as 240 near-touching dots; a few round-capped strokes read the same.
    private func paintTrail(_ ctx: GraphicsContext, painter: MissionRidgePainter, k: CGFloat) {
        let trail = painter.trail
        let tf = painter.plane(.near)
        let n = trail.n
        let color = Color(red: 236.0 / 255.0, green: 236.0 / 255.0, blue: 238.0 / 255.0).opacity(Double(0.14 * k))
        var i = 0
        while i < n {
            let end = min(n, i + 6)
            var p = Path()
            p.move(to: CGPoint(x: tf.tx + trail.x[i] * tf.w, y: tf.ty + trail.y[i] * tf.h))
            var j = i + 1
            while j <= end {
                p.addLine(to: CGPoint(x: tf.tx + trail.x[j] * tf.w, y: tf.ty + trail.y[j] * tf.h))
                j += 1
            }
            let wd = MissionRidgeMath.clamp(trail.w[i] * tf.w * 0.1, 0.7, 1.8)
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: wd, lineCap: .round, lineJoin: .round))
            i = end
        }
    }
}

struct MissionRidgeBandView: View {
    let phase: MissionCameraPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var loaded: MissionRidgeLoaded?
    @State private var epoch = Date()
    @State private var appearT: Double = 0
    @State private var busy = true
    @State private var foundFrom: Double
    @State private var foundT: Double = -10
    @State private var dawnT0: Double?
    @State private var calmTask: Task<Void, Never>?

    init(phase: MissionCameraPhase) {
        self.phase = phase
        _foundFrom = State(initialValue: MissionRidgeBandView.foundTarget(for: phase))
        _dawnT0 = State(initialValue: phase == .done ? -100 : nil)
    }

    /// The horizon glows from `.found` on and holds through the check.
    private static func foundTarget(for phase: MissionCameraPhase) -> Double {
        switch phase {
        case .aim: return 0
        case .found: return 1
        case .checking: return 1
        case .done: return 0
        }
    }

    var body: some View {
        let paused = scenePhase != .active || (reduceMotion && !busy)
        TimelineView(.animation(minimumInterval: busy ? nil : 1.0 / 30.0, paused: paused)) { timeline in
            frameView(t: CGFloat(timeline.date.timeIntervalSince(epoch)))
        }
        .clipped()
        .mask {
            // the top edge dissolves into the page (web: destination-out over the top 46 %)
            LinearGradient(stops: [
                Gradient.Stop(color: Color.black.opacity(0), location: 0),
                Gradient.Stop(color: Color.black.opacity(0.38), location: 0.207),
                Gradient.Stop(color: Color.black, location: 0.46),
                Gradient.Stop(color: Color.black, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .onAppear { MissionRidgeStore.shared.acquire() }
        .onDisappear {
            MissionRidgeStore.shared.release()
            calmTask?.cancel()
        }
        .task { await loadWorld() }
        .onChange(of: phase) { old, new in
            phaseChanged(from: old, to: new)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func frameView(t: CGFloat) -> some View {
        let renderer = loaded.map {
            MissionRidgeBandRenderer(loaded: $0, reduced: reduceMotion, t: t, foundFrom: CGFloat(foundFrom),
                                     foundTarget: CGFloat(MissionRidgeBandView.foundTarget(for: phase)),
                                     foundT: CGFloat(foundT), dawnT0: dawnT0.map { CGFloat($0) }, ink: Theme.ink)
        }
        let fadeIn = MissionRidgeMath.easeOut((t - CGFloat(appearT)) / 0.4)
        Canvas { ctx, size in
            renderer?.draw(&ctx, size: size)
        }
        .opacity(Double(fadeIn))
    }

    private func loadWorld() async {
        let result = await MissionRidgeStore.shared.load(sets: ["night", "dawn"])
        if Task.isCancelled { return }
        appearT = Date().timeIntervalSince(epoch)
        loaded = result
        busy = true
        try? await Task.sleep(for: .seconds(1.4))
        if Task.isCancelled { return }
        busy = false
    }

    private func phaseChanged(from old: MissionCameraPhase, to new: MissionCameraPhase) {
        let now = Date().timeIntervalSince(epoch)
        // continue the glow from where it is now
        let k = exp(-(now - foundT) / Double(MissionRidgeBandRenderer.easeSeconds))
        let target = MissionRidgeBandView.foundTarget(for: old)
        foundFrom = target + (foundFrom - target) * k
        foundT = now
        dawnT0 = (new == .done) ? now : nil
        busy = true
        calmTask?.cancel()
        calmTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if Task.isCancelled { return }
            busy = false
        }
    }
}
