//
//  MatrixCardView.swift
//  GymLock · Matrix hero card (native port)
//
//  Native port of web/hero13/card13m.tsx: the home hero card in its Matrix Dynamic look.
//
//  Composition (all in a fixed 1000 x 488 design space, scaled uniformly to the card width, so an SE
//  and a Pro Max show exactly the same picture):
//    1. card colour                                   (look.card)
//    2. the dim dot grid, 38 x 35 at (492, 26), pitch 12.5, faded out under the copy and at the
//       top/bottom edges; rendered ONCE per (size, look, displayScale) into a CGImage
//    3. the particles (MatrixEngine.draw), radius 4.6, batched by 7 brightness levels + coral,
//       multiplied by the left clip fade clamp01((X - 492 + 40) / 120)
//    4. the scene's flash over the board rectangle, min(0.3, flash * 0.6) of ink
//    5. the copy column on the left (x 52, width 470): eyebrow, kinetic headline or flip clock,
//       support line, live progress bar
//    Shake offsets layers 3 (dots) only, like the web: dx = sin(t * 97) * s, dy = cos(t * 83) * s * 0.6.
//
//  Clock: TimelineView(.animation) drives everything. `t` = seconds since the runtime's epoch (kept
//  small so the engine's Float timestamps stay precise), `T` = seconds since the card entered the
//  current state. The engine clamps dt to 0.1 s, so a hitch or a resume never teleports dots.
//
//  State changes: the engine key is "<moment>:<day>:<pos>:<phase>", exactly like the web. When the
//  host passes a new moment/day/pos, T restarts at 0, the new scene draws, the key differs, and the
//  engine re-deals: every dot flies from the old scene to the new one. Scenes can also change
//  `phase` mid-scene (verified Friday: chevrons -> "+1") for the same effect.
//
//  Pausing: the timeline pauses when the card is off screen (onScrollVisibilityChange / onDisappear)
//  or the app is not active. On resume the dt clamp and the haptic stale window keep it calm.
//
//  120 Hz: add `CADisableMinimumFrameDurationOnPhone = YES` to Info.plist, or ProMotion iPhones cap
//  TimelineView at 60 Hz. The physics (1/120 s substeps) and the time-based brightness easing make
//  60 and 120 Hz render the same motion.
//
//  Depends on: MatrixEngine.swift, MatrixBoard.swift, MatrixScene.swift, HeroHaptics.swift.
//

import SwiftUI
import UIKit

// MARK: - Geometry and colours

public enum MatrixCardGeometry {
    public static let W: Double = 1000
    public static let H: Double = 488
    public static let OX: Double = 492
    public static let OY: Double = 26
    public static let PITCH: Double = 12.5
    public static let COLS = 38
    public static let ROWS = 35
    public static let boardW = Double(COLS) * PITCH   // 475
    public static let boardH = Double(ROWS) * PITCH   // 437.5
    public static let dotRadius: Double = 4.6
    public static let gridRadius: Double = 1.7
    /// Width (design units, from the board's left edge) over which the grid fades out under the copy.
    public static let gridFade: Double = 190
    /// card13m.tsx: the dots fade in from 40 units left of the board over 120 units.
    public static func clip(_ X: Double) -> Double { MX.cl((X - OX + 40) / 120) }
    public static let aspect = W / H
}

/// An sRGB colour usable both as a SwiftUI Color and a CGColor (for the cached grid bitmap).
public struct MatrixRGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }
    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public static let coral = MatrixRGB(0xE85D4E)   // Theme.accent
}

/// hero2/paint.ts LOOKS (light / dark / night), the parts the Matrix card uses.
public struct MatrixLook: Equatable, Sendable {
    public var card: MatrixRGB
    public var ink: MatrixRGB
    public var ink2: MatrixRGB
    public var isDark: Bool

    /// Theme.surface / Theme.ink / Theme.inkSecondary in the app.
    public static let light = MatrixLook(card: MatrixRGB(0xFFFFFF), ink: MatrixRGB(0x1A1A1A), ink2: MatrixRGB(0x6B6B6B), isDark: false)
    public static let dark = MatrixLook(card: MatrixRGB(0x151517), ink: MatrixRGB(0xF2F2F0), ink2: MatrixRGB(0xA3A3A3), isDark: true)
    public static let night = MatrixLook(card: MatrixRGB(0x111113), ink: MatrixRGB(0xF2F2F0), ink2: MatrixRGB(0xF2F2F0, alpha: 0.66), isDark: true)

    /// card13m.tsx `lookFor`: night moments are dark even in light mode.
    public static func resolve(_ moment: MatrixMoment, _ scheme: ColorScheme) -> MatrixLook {
        if moment.isNight { return .night }
        return scheme == .dark ? .dark : .light
    }

    /// Grid dot alpha: 0.16 on dark, 0.1 on light.
    public var gridAlpha: Double { isDark ? 0.16 : 0.1 }
}

// MARK: - Inputs

/// The live numbers, as reference dates, so every frame derives them from the timeline's date.
public struct MatrixLiveClock: Equatable, Sendable {
    public var setupDone: [Bool]
    /// When the countdown reaches zero (countdown state).
    public var countdownEnd: Date?
    /// When the 20 minutes on the gym floor started (atgym state).
    public var gymStart: Date?
    /// When the evening window closes (stilltime state).
    public var eveningEnd: Date?

    public init(setupDone: [Bool] = [false, false, false], countdownEnd: Date? = nil, gymStart: Date? = nil, eveningEnd: Date? = nil) {
        self.setupDone = setupDone
        self.countdownEnd = countdownEnd
        self.gymStart = gymStart
        self.eveningEnd = eveningEnd
    }

    public func data(at date: Date) -> MatrixLiveData {
        MatrixLiveData(
            setupDone: setupDone,
            countdown: countdownEnd.map { max(0, $0.timeIntervalSince(date)) } ?? 0,
            atgym: gymStart.map { max(0, date.timeIntervalSince($0)) } ?? 0,
            stillLeft: eveningEnd.map { max(0, $0.timeIntervalSince(date)) } ?? 0
        )
    }
}

/// kin13.tsx TypeStyle: how the headline arrives.
public enum MatrixKineticStyle: String, Sendable, CaseIterable {
    case slam, rise, track, type, blur, wipe, drop, stamp, jolt
}

/// The words on the card. Derive them from the app's copy tables (copy12.ts in the prototype).
/// Support and headline accept **bold** markup. `{left}` in `support` is replaced every frame with
/// mm:ss to the 20-minute proof (the atgym support line).
public struct MatrixCardCopy: Equatable, Sendable {
    public enum Headline: Equatable, Sendable {
        /// A sentence that arrives with a kinetic style.
        case text(String, MatrixKineticStyle)
        /// The countdown as a flip clock (hh:mm:ss of `MatrixLiveData.countdown`).
        case countdownClock
        /// A plain headline that fades in (atgym), e.g. "AT THE GYM" state's mm:ss.
        case plain(String)
    }
    public var eyebrow: String
    public var headline: Headline
    public var support: String
    /// The pulsing coral dot before the eyebrow (atgym, stilltime).
    public var liveDot: Bool
    /// The 20-minute bar under the support line (atgym).
    public var showsProofBar: Bool

    public init(eyebrow: String, headline: Headline, support: String, liveDot: Bool = false, showsProofBar: Bool = false) {
        self.eyebrow = eyebrow
        self.headline = headline
        self.support = support
        self.liveDot = liveDot
        self.showsProofBar = showsProofBar
    }
}

public struct MatrixCardInput: Equatable, Sendable {
    public enum Entrance: Equatable, Sendable {
        /// T starts when the card first shows this state: the entrance (dots flying in, the beat,
        /// the headline arriving) plays. This is what the web does on every state change.
        case onAppear
        /// T counts from a real moment (e.g. when the countdown began). The card warms up
        /// deterministically and shows the frame the web would show at that T, without replaying.
        case since(Date)
    }

    public var moment: MatrixMoment
    /// 0 = Monday ... 6 = Sunday (the day's world).
    public var day: Int
    public var pos: MatrixWeekPos
    public var dayData: MatrixDayData
    public var clock: MatrixLiveClock
    public var copy: MatrixCardCopy
    public var entrance: Entrance
    /// Off while the full-screen done flow is up (the web silences card haptics under the overlay).
    public var hapticsEnabled: Bool

    public init(moment: MatrixMoment, day: Int, pos: MatrixWeekPos, dayData: MatrixDayData, clock: MatrixLiveClock, copy: MatrixCardCopy, entrance: Entrance = .onAppear, hapticsEnabled: Bool = true) {
        self.moment = moment
        self.day = day
        self.pos = pos
        self.dayData = dayData
        self.clock = clock
        self.copy = copy
        self.entrance = entrance
        self.hapticsEnabled = hapticsEnabled
    }

    var stateKey: String { "\(moment.rawValue):\(day):\(pos.rawValue)" }
}

// MARK: - Grid bitmap (hero4/dots.ts gridBitmap + the card's destination-out fades)

public enum MatrixGridRenderer {
    /// Paints the unlit dot grid once. Coordinates follow canvas conventions (origin top-left).
    /// - Parameters:
    ///   - pxScale: device pixels per design unit (card scale x displayScale).
    ///   - fadeLeft: if set, erase from full at x = 0 to none at x = fadeLeft (the card's copy side).
    ///   - vignette: erase 0.6 at the top and bottom edges, none between 15% and 85% (the card).
    public static func makeImage(cols: Int, rows: Int, pitch: Double, radius: Double, color: MatrixRGB, alpha: Double, pxScale: Double, fadeLeft: Double? = nil, vignette: Bool = false) -> CGImage? {
        let bw = Double(cols) * pitch, bh = Double(rows) * pitch
        let wpx = Int((bw * pxScale).rounded(.up)), hpx = Int((bh * pxScale).rounded(.up))
        guard wpx > 0, hpx > 0, wpx <= 8192, hpx <= 8192 else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let g = CGContext(data: nil, width: wpx, height: hpx, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        g.translateBy(x: 0, y: CGFloat(hpx))
        g.scaleBy(x: CGFloat(pxScale), y: -CGFloat(pxScale))
        g.setFillColor(CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: alpha))
        for i in 0..<cols {
            for j in 0..<rows {
                let cx = (Double(i) + 0.5) * pitch, cy = (Double(j) + 0.5) * pitch
                g.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            }
        }
        g.fillPath()

        let clear = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
        func black(_ a: Double) -> CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: a) }
        g.setBlendMode(.destinationOut)
        if let fadeLeft, let grad = CGGradient(colorsSpace: space, colors: [black(1), clear] as CFArray, locations: [0, 1]) {
            g.saveGState()
            g.clip(to: CGRect(x: 0, y: 0, width: fadeLeft, height: bh))
            g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: fadeLeft, y: 0), options: [])
            g.restoreGState()
        }
        if vignette, let grad = CGGradient(colorsSpace: space, colors: [black(0.6), clear, clear, black(0.6)] as CFArray, locations: [0, 0.15, 0.85, 1]) {
            g.saveGState()
            g.clip(to: CGRect(x: 0, y: 0, width: bw, height: bh))
            g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: bh), options: [])
            g.restoreGState()
        }
        return g.makeImage()
    }
}

// MARK: - Runtime (engine + clock + haptics; not observable, stepped from the Canvas)

@MainActor
final class MatrixCardRuntime {
    /// Headroom so the warm-up's earlier timestamps stay positive (the engine uses t < 0 as "unset").
    private static let epochLead: TimeInterval = 2
    /// How much history the warm-up simulates. Dots settle in well under a second.
    static let warmUpWindow: Double = 1.5

    private var engine: MatrixEngine?
    private var board = MatrixBoard()
    let haptics = HeroHapticScheduler()
    private var epoch: Date?
    private var stateKey = ""
    private var stateStart: Double = 0
    private var scene = MatrixScene.empty
    private var needsWarmUp = true
    private var grid: (key: String, image: Image)?

    struct Clock {
        var t: Double
        var T: Double
        var live: MatrixLiveData
    }

    /// Cheap and idempotent: resolves the clock for a date and notices state changes.
    /// Called from the view body (for the copy layer) and from the Canvas renderer.
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
            scene = MatrixSceneRegistry.scene(input.moment, day: input.day)
            haptics.reset(cues: scene.haptics, at: t - stateStart)
        }
        return Clock(t: t, T: t - stateStart, live: input.clock.data(at: date))
    }

    private func context(_ input: MatrixCardInput, t: Double, T: Double, live: MatrixLiveData) -> MatrixContext {
        MatrixContext(t: t, T: T, d: live, day: input.day, pos: input.pos, N: MatrixContext.taps(day: input.day, pos: input.pos), D: input.dayData)
    }

    /// One scene frame into the engine. Returns the scene's output (flash, shake, phase).
    private func stepScene(_ engine: MatrixEngine, _ input: MatrixCardInput, t: Double, T: Double, live: MatrixLiveData) -> SceneOut {
        board.reset()
        let out = scene.draw(&board, context(input, t: t, T: T, live: live))
        engine.update(key: "\(stateKey):\(out.phase ?? "0")", targets: board.out(), t: t, options: out.opts ?? MatrixDealOptions(stagger: 0.25))
        return out
    }

    /// Re-run the last `warmUpWindow` seconds of the scene at a fixed 60 fps from a clean engine, so
    /// a card that appears mid-state shows the same settled frame on every device and on the web.
    private func warmUp(_ engine: MatrixEngine, _ input: MatrixCardInput, date: Date, clock: Clock) {
        guard clock.T > 1.0 / 60 else { return }
        engine.reset(cols: MatrixCardGeometry.COLS, rows: MatrixCardGeometry.ROWS)
        let k1 = Int((clock.T * 60).rounded(.down))
        let k0 = max(0, k1 - Int(Self.warmUpWindow * 60))
        var k = k0
        while k <= k1 {
            let Tk = Double(k) / 60
            if Tk >= clock.T { break }
            let back = clock.T - Tk
            _ = stepScene(engine, input, t: clock.t - back, T: Tk, live: input.clock.data(at: date.addingTimeInterval(-back)))
            k += 1
        }
        haptics.reset(cues: scene.haptics, at: clock.T)
    }

    private func gridImage(_ look: MatrixLook, pxScale: Double) -> Image? {
        let key = "\(Int((pxScale * 1000).rounded())):\(look.ink.r):\(look.isDark)"
        if let grid, grid.key == key { return grid.image }
        let G = MatrixCardGeometry.self
        guard let cg = MatrixGridRenderer.makeImage(cols: G.COLS, rows: G.ROWS, pitch: G.PITCH, radius: G.gridRadius, color: look.ink, alpha: look.gridAlpha, pxScale: pxScale, fadeLeft: G.gridFade, vignette: true) else { return nil }
        let img = Image(decorative: cg, scale: 1)
        grid = (key, img)
        return img
    }

    func setPointer(_ cell: SIMD2<Double>?) { engine?.pointer = cell }

    /// The whole board for one frame.
    func render(_ ctx: inout GraphicsContext, size: CGSize, date: Date, input: MatrixCardInput, look: MatrixLook, reduceMotion: Bool, displayScale: CGFloat) {
        let G = MatrixCardGeometry.self
        let k = Double(size.width) / G.W
        guard k > 0, k.isFinite else { return }
        let clock = sync(input, date)
        let engine: MatrixEngine
        if let e = self.engine {
            engine = e
        } else {
            engine = MatrixEngine(n: 720, cols: G.COLS, rows: G.ROWS)
            self.engine = engine
        }
        if needsWarmUp {
            needsWarmUp = false
            warmUp(engine, input, date: date, clock: clock)
        }

        ctx.scaleBy(x: k, y: k)
        let boardRect = CGRect(x: G.OX, y: G.OY, width: G.boardW, height: G.boardH)
        if let img = gridImage(look, pxScale: k * Double(displayScale)) {
            ctx.draw(img, in: boardRect)
        }

        let out = stepScene(engine, input, t: clock.t, T: clock.T, live: clock.live)
        haptics.isActive = input.hapticsEnabled
        haptics.tick(clock.T)

        let sh = reduceMotion ? 0 : out.shake * G.PITCH
        let dx = sh != 0 ? sin(clock.t * 97) * sh : 0
        let dy = sh != 0 ? cos(clock.t * 83) * sh * 0.6 : 0
        engine.draw(in: ctx, ox: G.OX + dx, oy: G.OY + dy, pitch: G.PITCH, ink: look.ink.color, coral: MatrixRGB.coral.color, radius: G.dotRadius, clip: G.clip)

        // a flash of light, when the scene calls for one
        let fa = reduceMotion ? 0 : out.flash
        if fa > 0.01 {
            ctx.fill(Path(boardRect), with: .color(look.ink.color.opacity(min(0.3, fa * 0.6))))
        }
    }
}

// MARK: - The card

public struct MatrixCardView: View {
    public var input: MatrixCardInput
    /// Drag a finger across the dots to push them (the web's pointer repel). Off by default: a
    /// zero-distance drag inside a ScrollView can steal the scroll; test on device before enabling.
    public var interactive: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var runtime = MatrixCardRuntime()
    @State private var onScreen = false
    @State private var lastTouchCell: SIMD2<Double>?

    public init(input: MatrixCardInput, interactive: Bool = false) {
        self.input = input
        self.interactive = interactive
    }

    private var paused: Bool { !onScreen || scenePhase != .active }

    public var body: some View {
        let look = MatrixLook.resolve(input.moment, scheme)
        GeometryReader { proxy in
            let k = Double(proxy.size.width) / MatrixCardGeometry.W
            TimelineView(.animation(minimumInterval: nil, paused: paused)) { tl in
                let clock = runtime.sync(input, tl.date)
                ZStack(alignment: .topLeading) {
                    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, size in
                        runtime.render(&ctx, size: size, date: tl.date, input: input, look: look, reduceMotion: reduceMotion, displayScale: displayScale)
                    }
                    .accessibilityHidden(true)

                    MatrixCardCopyLayer(copy: input.copy, look: look, k: k, f: clock.T * 30, t: clock.t, live: clock.live, reduceMotion: reduceMotion)
                }
            }
            .contentShape(Rectangle())
            .gesture(pointerGesture(k: k), including: interactive ? .all : .subviews)
        }
        .aspectRatio(MatrixCardGeometry.aspect, contentMode: .fit)
        .background(look.card.color)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onScrollVisibilityChange(threshold: 0.05) { visible in onScreen = visible }
    }

    private func pointerGesture(k: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard k > 0 else { return }
                let G = MatrixCardGeometry.self
                let cx = (Double(v.location.x) / k - G.OX) / G.PITCH
                let cy = (Double(v.location.y) / k - G.OY) / G.PITCH
                if cx < -2 {
                    runtime.setPointer(nil)
                    return
                }
                let cell = SIMD2(cx, cy)
                runtime.setPointer(cell)
                if let l = lastTouchCell {
                    if hypot(cx - l.x, cy - l.y) > 3.2 {
                        runtime.haptics.playNow(.light)
                        lastTouchCell = cell
                    }
                } else {
                    lastTouchCell = cell
                }
            }
            .onEnded { _ in
                runtime.setPointer(nil)
                lastTouchCell = nil
            }
    }
}

// MARK: - Copy layer (card13m.tsx left column)

struct MatrixCardCopyLayer: View {
    let copy: MatrixCardCopy
    let look: MatrixLook
    /// points per design unit
    let k: Double
    /// frames at 30 fps since the state began (the web's `f`)
    let f: Double
    let t: Double
    let live: MatrixLiveData
    let reduceMotion: Bool

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }

    var body: some View {
        let lab = Self.eo((f - 2) / 7)
        let sub = Self.eo((f - 9) / 12)
        let proofHit = copy.showsProofBar && live.atgym >= MX.PROOF
        let eSize = min(30, (30 * 450) / max(1, MatrixTextMeasure.width(copy.eyebrow, size: 30, rounded: true) * 1.25))
        let hSize = headlineSize()

        VStack(alignment: .leading, spacing: 0) {
            MatrixEyebrow(text: copy.eyebrow, f: f, size: eSize * k, color: look.ink2.color, reduceMotion: reduceMotion, dot: copy.liveDot ? (proofHit ? 1 : 0.5 + 0.5 * sin(t * 9)) : nil, k: k)
                .opacity(lab)

            headline(size: hSize * k)
                .padding(.top, 6 * k)

            if !copy.support.isEmpty {
                MatrixRich.text(supportText(), size: 35 * k, weight: .medium, color: look.ink2.color, boldColor: look.ink.color, boldWeight: .bold)
                    .lineSpacing(0.05 * 35 * k)
                    .frame(maxWidth: 430 * k, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10 * k)
                    .opacity(sub)
                    .offset(y: (1 - sub) * 10 * k)
            }

            if copy.showsProofBar {
                ZStack(alignment: .leading) {
                    Capsule().fill(look.ink.color.opacity(look.isDark ? 0.14 : 0.08))
                    Capsule()
                        .fill(proofHit ? MatrixRGB.coral.color : look.ink.color)
                        .frame(width: 380 * k * MX.cl(live.atgym / MX.PROOF))
                }
                .frame(width: 380 * k, height: 10 * k)
                .padding(.top, 16 * k)
                .opacity(sub)
            }
        }
        .frame(width: 470 * k, height: MatrixCardGeometry.H * k, alignment: .leading)
        .offset(x: 52 * k)
        .accessibilityElement(children: .combine)
    }

    /// card13m.tsx: shrink the headline so it fits 440 design units (430 in setup).
    private func headlineSize() -> Double {
        let sample: String
        switch copy.headline {
        case .countdownClock: sample = "00:00:00"
        case .plain: sample = "00:00"
        case .text(let s, _): sample = s
        }
        return min(88, (88 * 440) / max(1, MatrixTextMeasure.width(sample, size: 88, rounded: true)))
    }

    @ViewBuilder
    private func headline(size: Double) -> some View {
        switch copy.headline {
        case .countdownClock:
            let s = live.countdown
            MatrixFlipClock(text: Self.clock(s), frac: 1 - (s - s.rounded(.down)), size: size, color: look.ink.color, up: false)
        case .plain(let s):
            Text(s)
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(-0.02 * size)
                .foregroundStyle(look.ink.color)
                .lineLimit(1)
                .opacity(MX.cl((f - 4) / 3))
        case .text(let s, let style):
            MatrixKineticHeadline(text: s, style: style, f: f, size: size, color: look.ink.color, tracking: -0.02, reduceMotion: reduceMotion)
        }
    }

    private func supportText() -> String {
        guard copy.support.contains("{left}") else { return copy.support }
        let left = max(0, MX.PROOF - live.atgym)
        let mm = Int((left / 60).rounded(.down)), ss = Int(left.rounded(.down)) % 60
        return copy.support.replacingOccurrences(of: "{left}", with: String(format: "%02d:%02d", mm, ss))
    }

    /// hero2/card.tsx `clock`: hh:mm:ss of the seconds left, rounded UP.
    static func clock(_ s: Double) -> String {
        let t = Int(max(0, s.rounded(.up)))
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}

// MARK: - Text helpers

@MainActor
enum MatrixTextMeasure {
    private static var cache: [String: Double] = [:]

    /// Width of a single line in SF (or SF Rounded) bold, like the web's canvas measureText, with the
    /// same `* 0.98 + 1` the card applies.
    static func width(_ s: String, size: Double, rounded: Bool, weight: UIFont.Weight = .bold) -> Double {
        let key = "\(rounded ? "r" : "s"):\(weight.rawValue):\(size):\(s)"
        if let w = cache[key] { return w }
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        if rounded, let d = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: d, size: size) }
        let w = Double((s as NSString).size(withAttributes: [.font: font]).width) * 0.98 + 1
        if cache.count > 256 { cache.removeAll() }
        cache[key] = w
        return w
    }
}

/// `**bold**` markup, as the web's `split('**')`: odd parts are emphasised.
enum MatrixRich {
    static func text(_ s: String, size: Double, weight: Font.Weight, color: Color, boldColor: Color, boldWeight: Font.Weight, design: Font.Design = .default) -> Text {
        var out = Text("")
        for (i, part) in s.components(separatedBy: "**").enumerated() {
            let bold = i % 2 == 1
            out = out + Text(part)
                .font(.system(size: size, weight: bold ? boldWeight : weight, design: design))
                .foregroundStyle(bold ? boldColor : color)
        }
        return out
    }
}

// MARK: - kin13.tsx: Eyebrow, Kinetic, FlipClock

/// The eyebrow: a short rule draws out, then the words slide in after it.
struct MatrixEyebrow: View {
    let text: String
    let f: Double
    let size: Double
    let color: Color
    let reduceMotion: Bool
    /// Opacity of the coral live dot, or nil for none.
    let dot: Double?
    let k: Double

    private static func ez(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }

    var body: some View {
        let line = reduceMotion ? 1 : Self.ez((f - 1) / 6)
        let tx = reduceMotion ? 1 : Self.ez((f - 4) / 8)
        HStack(spacing: 0) {
            if let dot {
                Circle().fill(MatrixRGB.coral.color).frame(width: 14 * k, height: 14 * k).opacity(dot)
                    .padding(.trailing, 12 * k)
            }
            RoundedRectangle(cornerRadius: 2 * k)
                .fill(color.opacity(0.85))
                .frame(width: 26 * k * line, height: 3 * k)
                .padding(.trailing, max(0, (12 + 2 - 14 * (1 - line)) * k))
            Text(text)
                .font(.system(size: size, weight: .bold))
                .tracking((0.06 + (1 - tx) * 0.22) * size)
                .foregroundStyle(color)
                .lineLimit(1)
                .opacity(tx)
                .offset(x: (1 - tx) * -10 * k)
        }
    }
}

/// Each headline arrives with a motion that matches what it says (kin13.tsx `Kinetic`).
/// Sizes are in points (already scaled); `tracking` is in em like the web.
struct MatrixKineticHeadline: View {
    let text: String
    let style: MatrixKineticStyle
    let f: Double
    let size: Double
    let color: Color
    let tracking: Double
    let reduceMotion: Bool

    private static func cl(_ x: Double) -> Double { MX.cl(x) }
    private static func ez(_ x: Double) -> Double { 1 - pow(1 - cl(x), 3) }
    private static func back(_ x: Double, _ k: Double = 1.7) -> Double {
        let t = cl(x) - 1
        return 1 + (k + 1) * t * t * t + k * t * t
    }
    /// kin13's spring has z = 6 (mxlib's has 5).
    private static func spr(_ x: Double, _ w: Double = 13, _ z: Double = 6) -> Double { x <= 0 ? 0 : 1 - exp(-x * z) * cos(x * w) }

    private var font: Font { .system(size: size, weight: .bold, design: .rounded).monospacedDigit() }

    private func base(_ s: String, em: Double? = nil) -> Text {
        Text(s).font(font).tracking((em ?? tracking) * size).foregroundStyle(color)
    }

    var body: some View {
        let x = (f - 3) / 30
        let chars = text.map { String($0) }
        Group {
            if reduceMotion {
                base(text).opacity(Self.cl((f - 3) / 6))
            } else {
                switch style {
                case .slam:
                    let s = 1.6 - 0.6 * Self.spr(x * 1.2)
                    base(text, em: tracking + 0.12 * (1 - Self.ez(x * 3)))
                        .opacity(Self.cl((f - 3) / 2.5))
                        .scaleEffect(s, anchor: UnitPoint(x: 0, y: 0.8))
                case .stamp:
                    let p = Self.ez((f - 3) / 6)
                    base(text)
                        .opacity(Self.cl((f - 3) / 2))
                        .scaleEffect(1.28 - 0.28 * p, anchor: UnitPoint(x: 0, y: 0.6))
                        .rotationEffect(.degrees(-3 * (1 - p)), anchor: UnitPoint(x: 0, y: 0.6))
                case .blur:
                    let p = Self.ez((f - 3) / 20)
                    base(text)
                        .opacity(p)
                        .blur(radius: (1 - p) * 14 * size / 88)
                        .scaleEffect(1.06 - 0.06 * p, anchor: UnitPoint(x: 0, y: 0.6))
                case .wipe:
                    let p = Self.ez((f - 3) / 14)
                    base(text)
                        .mask(alignment: .leading) {
                            GeometryReader { g in Rectangle().frame(width: g.size.width * p) }
                        }
                        .overlay(alignment: .leading) {
                            if p < 1 {
                                GeometryReader { g in
                                    Capsule()
                                        .fill(MatrixRGB.coral.color)
                                        .frame(width: 6 * size / 88, height: g.size.height * 0.84)
                                        .offset(x: g.size.width * p - 3 * size / 88, y: g.size.height * 0.08)
                                        .opacity(1 - p * 0.6)
                                }
                            }
                        }
                case .type:
                    let n = max(0, Int(((f - 3) / 1.6).rounded(.down)))
                    let done = n >= chars.count
                    let caretOn = done ? (Int((f / 15).rounded(.down)) % 2 != 0 ? 0.0 : 1.0) : 1.0
                    HStack(spacing: 0) {
                        base(chars.prefix(n).joined())
                        Rectangle().fill(color).frame(width: 0.08 * size, height: 0.82 * size).opacity(caretOn).padding(.leading, 0.04 * size)
                        base(chars.dropFirst(n).joined()).opacity(0)
                    }
                case .jolt:
                    let kk = max(0, f - 3)
                    let dx = sin(kk * 1.9) * 22 * exp(-kk / 6) * size / 88
                    ZStack(alignment: .leading) {
                        if kk < 10 { base(text).opacity(0.25 * (1 - kk / 10)).offset(x: -dx * 0.6) }
                        base(text).opacity(Self.cl(kk / 2)).offset(x: dx)
                    }
                case .rise:
                    let words = text.components(separatedBy: " ")
                    HStack(spacing: 0.24 * size) {
                        ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                            let p = Self.back((f - 3 - Double(i) * 3) / 11, 1.3)
                            base(w)
                                .offset(y: (1 - p) * 1.1 * size * 1.02)
                                .padding(.bottom, 0.12 * size)
                                .clipped()
                                .padding(.bottom, -0.12 * size)
                        }
                    }
                case .drop:
                    HStack(spacing: 0) {
                        ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                            let d = f - 3 - Double(i) * 1.3
                            let p = Self.back(d / 11, 2.2)
                            base(ch).opacity(Self.cl(d / 2)).offset(y: -(1 - p) * size * 0.7)
                        }
                    }
                case .track:
                    let sp = tracking + 0.55 * (1 - Self.ez((f - 3) / 18))
                    chars.enumerated().reduce(Text("")) { acc, e in
                        acc + Text(e.element).foregroundStyle(color.opacity(Self.cl((f - 3 - Double(e.offset) * 0.9) / 6)))
                    }
                    .font(font)
                    .tracking(sp * size)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Digits that flip in when they change (kin13.tsx `FlipClock`): only the last digit moves.
struct MatrixFlipClock: View {
    let text: String
    /// 0 right after the last digit changed, 1 just before the next change.
    let frac: Double
    let size: Double
    let color: Color
    let up: Bool

    var body: some View {
        let p = 1 - pow(1 - MX.cl(frac / 0.22), 3)
        let chars = text.map { String($0) }
        HStack(spacing: 0) {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                let last = i == chars.count - 1
                Text(ch)
                    .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(-0.03 * size)
                    .foregroundStyle(color)
                    .offset(y: last ? (1 - p) * (up ? 0.6 : -0.6) * size * 1.02 : 0)
                    .opacity(last ? 0.3 + 0.7 * p : 1)
                    .frame(height: 1.02 * size)
                    .clipped()
            }
        }
        .fixedSize()
    }
}

// MARK: - Parity harness (mirrors web/hero13/test/hcore.ts)

#if DEBUG
/// Renders ONE card frame exactly the way the web harness does (web/hero13/test/hcore.ts
/// `window.paint(day, T, dd, theme, pos)`), for side-by-side image diffs:
///   - canvas 600 x 293 px (the card at scale 0.6), card colour, the grid WITHOUT the fades
///   - a fresh engine stepped from T = 0 at 30 fps with t = 100 + T1 and per-frame brightness
///   - N = 5, live data starting from the harness defaults and advancing with T1
///   - shake and flash as the card draws them; no copy (the harness copy is a rough guide only)
/// Render with `ImageRenderer(content: MatrixHarnessFrame(...))` at `scale = 1` and diff against a
/// PNG of the web canvas (`document.getElementById('c').toDataURL()`).
public struct MatrixHarnessFrame: View {
    public var moment: MatrixMoment
    public var day: Int
    public var T: Double
    public var look: MatrixLook
    public var pos: MatrixWeekPos
    public var dayData: MatrixDayData
    public var live0: MatrixLiveData

    public init(moment: MatrixMoment, day: Int, T: Double, look: MatrixLook = .dark, pos: MatrixWeekPos = .middle, dayData: MatrixDayData, live0: MatrixLiveData = MatrixLiveData(setupDone: [true, true, false], countdown: 2412.4, atgym: 570, stillLeft: 2.4 * 3600)) {
        self.moment = moment
        self.day = day
        self.T = T
        self.look = look
        self.pos = pos
        self.dayData = dayData
        self.live0 = live0
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, size in
            let G = MatrixCardGeometry.self
            let S = Double(size.width) / G.W
            ctx.scaleBy(x: S, y: S)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: G.W, height: G.H)), with: .color(look.card.color))
            if let cg = MatrixGridRenderer.makeImage(cols: G.COLS, rows: G.ROWS, pitch: G.PITCH, radius: G.gridRadius, color: look.ink, alpha: look.gridAlpha, pxScale: S) {
                ctx.draw(Image(decorative: cg, scale: 1), in: CGRect(x: G.OX, y: G.OY, width: G.boardW, height: G.boardH))
            }
            let eng = MatrixEngine(n: 720, cols: G.COLS, rows: G.ROWS)
            eng.brightnessMode = .perFrame
            let scene = MatrixSceneRegistry.scene(moment, day: day)
            var out = SceneOut.none
            let t0 = 100.0
            let n = Int(JSMath.round(T * 30))
            var g = MatrixBoard()
            for k in 0...max(0, n) {
                let T1 = Double(k) / 30
                let d = MatrixLiveData(setupDone: live0.setupDone, countdown: max(0, live0.countdown - T1), atgym: live0.atgym + T1, stillLeft: max(0, live0.stillLeft - T1))
                g.reset()
                out = scene.draw(&g, MatrixContext(t: t0 + T1, T: T1, d: d, day: day, pos: pos, N: 5, D: dayData))
                eng.update(key: "\(moment.rawValue):\(day):\(pos.rawValue):\(out.phase ?? "0")", targets: g.out(), t: t0 + T1, options: out.opts ?? MatrixDealOptions(stagger: 0.25))
            }
            let sh = out.shake * G.PITCH, tt = t0 + T
            eng.draw(in: ctx, ox: G.OX + (sh != 0 ? sin(tt * 97) * sh : 0), oy: G.OY + (sh != 0 ? cos(tt * 83) * sh * 0.6 : 0), pitch: G.PITCH, ink: look.ink.color, coral: MatrixRGB.coral.color, radius: G.dotRadius, clip: G.clip)
            if out.flash > 0.01 {
                ctx.fill(Path(CGRect(x: G.OX, y: G.OY, width: G.boardW, height: G.boardH)), with: .color(look.ink.color.opacity(min(0.3, out.flash * 0.6))))
            }
        }
        .frame(width: 600, height: 293)
    }
}
#endif
