//
//  RidgeCardView.swift
//  GymLock · Ridge hero card (native port)
//
//  Native port of web/hero13/card13.tsx: the day's painted watercolour world with the moment's own
//  props played over it, a camera move, and the copy column on the left.
//
//  Composition (1000 x 488 design space, scaled uniformly to the card width):
//    1. the painting, rendered into one CGImage per frame by RidgeFrameRenderer
//       (Painter2/3 world + overlay3 + paintShapes, the camera matrix from build + clampCam)
//    2. the paper fade on the left (0%: 1, 32%: .96, 44%: .70, 55%: .30, 66%: 0)
//    3. the copy column (x 52, width 470), shared with the Matrix card in the Ridge look
//
//  Bitmap size: one design unit is one bitmap pixel at pxScale = width px / 1000. pxScale is capped
//  at 0.76 (760 x 371 px) so a full repaint stays well inside a 60 Hz frame on CPU CoreGraphics;
//  the cached layers (sky, mountains, mist, paper) are painted once per key.
//

import SwiftUI
import UIKit

// MARK: - Look

extension MatrixLook {
    /// card13.tsx: paper rgb(246,246,244) / rgb(14,14,16), ink #0E0E10 / #F4F4F2, ink2 at 72%.
    static let ridgeLight = MatrixLook(card: MatrixRGB(0xF6F6F4), ink: MatrixRGB(0x0E0E10), ink2: MatrixRGB(0x0E0E10, alpha: 0.72), isDark: false)
    static let ridgeDark = MatrixLook(card: MatrixRGB(0x0E0E10), ink: MatrixRGB(0xF4F4F2), ink2: MatrixRGB(0xF4F4F2, alpha: 0.72), isDark: true)

    static func ridge(_ scheme: ColorScheme) -> MatrixLook { scheme == .dark ? .ridgeDark : .ridgeLight }
}

// MARK: - Frame renderer

/// Owns the painters and the reusable frame bitmap. Not thread-safe: main actor only.
@MainActor
final class RidgeFrameRenderer {
    static let maxPxScale: Double = 0.76

    private let painter = RPainter2()
    private var bitmap: (w: Int, h: Int, cg: CGContext)?

    /// The pixel scale for a card `pointWidth` wide on a screen of `displayScale`.
    static func pxScale(pointWidth: Double, displayScale: Double) -> Double {
        min(maxPxScale, max(0.2, pointWidth * displayScale / 1000))
    }

    /// card13.tsx useLayoutEffect: one frame of the painting.
    func frame(moment: String, day: Int, pos: String, c: RPC, theme: String, t: Double, pxScale: Double, reduceMotion: Bool) -> CGImage? {
        let cw = Int(JSMath.round(1000 * pxScale)), ch = Int(JSMath.round(488 * pxScale))
        guard cw > 0, ch > 0 else { return nil }
        if bitmap?.w != cw || bitmap?.h != ch {
            guard let cg = C2D.makeBitmap(cw, ch) else { return nil }
            bitmap = (cw, ch, cg)
        }
        guard let bm = bitmap else { return nil }
        let ctx = C2D(bm.cg, width: cw, height: ch)
        bm.cg.saveGState()
        defer { bm.cg.restoreGState() }

        let B = RW.build(moment, day, c)
        let S = B.scene
        let cam = reduceMotion ? RW.CAM0 : RW.clampCam(B.cam)
        painter.xf = RW.camMatrix(cam, pxScale)
        let pal = RW.palette(theme, JSMath.round(S.night * 4) / 4)
        let shapes = reduceMotion ? B.shapes.filter { $0.k != "flash" } : B.shapes
        let w = Double(cw), h = Double(ch)
        painter.render(ctx, w, h, S, theme, t) {
            RW.overlay3(ctx, w, h, S, theme, t)
            RW.paintShapes(ctx, shapes, pxScale, pal, theme, w, h)
        }
        ctx.setTransform(1, 0, 0, 1, 0, 0)
        return bm.cg.makeImage()
    }
}

// MARK: - Runtime (clock + haptics + renderer)

@MainActor
final class RidgeCardRuntime {
    private static let epochLead: TimeInterval = 2

    let haptics = HeroHapticScheduler()
    let renderer = RidgeFrameRenderer()
    private var epoch: Date?
    private var stateKey = ""
    private var stateStart: Double = 0
    private var last: (key: String, image: CGImage)?

    struct Clock {
        var t: Double
        var T: Double
        var live: MatrixLiveData
    }

    func sync(_ input: MatrixCardInput, _ date: Date) -> Clock {
        let ep = epoch ?? date.addingTimeInterval(-Self.epochLead)
        epoch = ep
        let t = date.timeIntervalSince(ep)
        if input.stateKey != stateKey {
            stateKey = input.stateKey
            switch input.entrance {
            case .onAppear: stateStart = t
            case .since(let d): stateStart = min(t, d.timeIntervalSince(ep))
            }
            haptics.reset(cues: RW.hapFor(input.moment.rawValue, Double(max(0, min(6, input.day)))), at: t - stateStart)
        }
        return Clock(t: t, T: t - stateStart, live: input.clock.data(at: date))
    }

    static func context(_ input: MatrixCardInput, t: Double, T: Double, live: MatrixLiveData) -> RPC {
        let dd = input.dayData
        return RPC(
            t: t, T: T, at: t - T, d: live, day: Double(input.day), pos: input.pos.rawValue,
            n: Double(live.setupDone.filter { $0 }.count),
            D: RData(day: Double(dd.day), week: Double(dd.week), sessions: Double(dd.sessions)),
            N: Double(MatrixContext.taps(day: input.day, pos: input.pos)), matrix: false
        )
    }

    func image(_ input: MatrixCardInput, clock: Clock, scheme: ColorScheme, pxScale: Double, reduceMotion: Bool) -> CGImage? {
        let c = Self.context(input, t: clock.t, T: clock.T, live: clock.live)
        haptics.isActive = input.hapticsEnabled
        haptics.allowsSuccess = HeroHapticPolicy.allowsSuccess(input.moment)
        haptics.tick(clock.T)
        let img = renderer.frame(moment: input.moment.rawValue, day: input.day, pos: input.pos.rawValue, c: c, theme: scheme == .dark ? "dark" : "light", t: clock.t, pxScale: pxScale, reduceMotion: reduceMotion)
        if let img { last = (stateKey, img) }
        return img ?? last?.image
    }
}

// MARK: - The card

public struct RidgeCardView: View {
    public var input: MatrixCardInput

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @Environment(\.heroMotionPaused) private var externallyPaused
    @State private var runtime = RidgeCardRuntime()
    @State private var onScreen = false

    public init(input: MatrixCardInput) {
        self.input = input
    }

    private var paused: Bool { !onScreen || scenePhase != .active || externallyPaused }

    public var body: some View {
        let look = MatrixLook.ridge(scheme)
        GeometryReader { proxy in
            let k = Double(proxy.size.width) / MatrixCardGeometry.W
            let px = RidgeFrameRenderer.pxScale(pointWidth: Double(proxy.size.width), displayScale: Double(displayScale))
            TimelineView(.animation(minimumInterval: HeroMotion.minimumInterval, paused: paused)) { tl in
                let clock = runtime.sync(input, tl.date)
                ZStack(alignment: .topLeading) {
                    if let img = runtime.image(input, clock: clock, scheme: scheme, pxScale: px, reduceMotion: reduceMotion) {
                        Image(decorative: img, scale: 1)
                            .resizable()
                            .interpolation(.medium)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .accessibilityHidden(true)
                    }
                    RidgePaperFade(paper: look.card.color)
                        .accessibilityHidden(true)
                    MatrixCardCopyLayer(copy: input.copy, look: look, k: k, f: clock.T * 30, t: clock.t, live: clock.live, reduceMotion: reduceMotion)
                }
            }
        }
        .aspectRatio(MatrixCardGeometry.aspect, contentMode: .fit)
        .background(look.card.color)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onScrollVisibilityChange(threshold: 0.1) { visible in onScreen = visible }
    }
}

/// card13.tsx: the print bleeding off the page on the copy side.
struct RidgePaperFade: View {
    let paper: Color

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: paper, location: 0),
                .init(color: paper.opacity(0.96), location: 0.32),
                .init(color: paper.opacity(0.70), location: 0.44),
                .init(color: paper.opacity(0.30), location: 0.55),
                .init(color: paper.opacity(0), location: 0.66),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Motion policy (spec §5)

enum HeroMotion {
    /// 30 Hz in Low Power Mode or under serious thermal pressure, otherwise the display's rate.
    static var minimumInterval: Double? {
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { return 1.0 / 30 }
        switch info.thermalState {
        case .serious, .critical: return 1.0 / 30
        default: return nil
        }
    }
}

private struct HeroMotionPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by hosts when an overlay or a large sheet covers the hero, so the card stops animating.
    var heroMotionPaused: Bool {
        get { self[HeroMotionPausedKey.self] }
        set { self[HeroMotionPausedKey.self] = newValue }
    }
}
