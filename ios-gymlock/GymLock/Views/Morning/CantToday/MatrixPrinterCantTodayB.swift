//
//  MatrixPrinterCantTodayB.swift
//  GymLock · the "can't today" screen · Matrix printer look (b)
//
//  Port of the approved prototype (docs/prototypes: v-mprinter-b.html, the part after "continue").
//  The same dot-matrix receipt printer as the pause prints the doors onto one slip:
//
//    heading, then the doors in FLOW order (input.data.order):
//      reschedule  a departure board of split-flap rows, one per place the workout can move to.
//                  Tapping a row opens it: three drum reels (hour, minute, am/pm) sit inside the
//                  open row, and "set alarm" confirms.
//      home        a boxed row with the house icon, the minutes and the 3 monthly dots
//      skip        a boxed "skip today" row (plain tap), or, when skipping costs the week, the real
//                  costs and "hold to skip": a long press that tears the slip along the
//                  perforation, and a "skipped" slip feeds out.
//
//  The paper, the carriage, the knobs and the keys are drawn on two Canvases (same look and palette
//  as the pause's MatrixPrinterPauseStage, copied here as private MPB* helpers). The reels are the
//  shared CantTodayDrum views laid over the open row, the long press is the shared cantTodayHold,
//  and the "touch me" wave is the shared CantTodayNudger.
//
//  Not in this port (not in the prototype's menu either): the receipt and its week strip. The
//  pause already showed them.
//

import SwiftUI

// MARK: - View

struct MatrixPrinterCantTodayB: View {
    let input: CantTodayInput

    /// Built layout, the paper job and the interaction state. Never drives a redraw by itself:
    /// the timeline below asks it for a fresh frame every tick.
    @State private var engine = MPBEngine()
    @State private var holdProgress: Double = 0
    @State private var holding = false
    @State private var closed = false
    @State private var acted = false

    var body: some View {
        let size = input.layout.size
        return ZStack(alignment: .topLeading) {
            TimelineView(.animation(paused: closed)) { tl in
                let fr = engine.frame(input: input, date: tl.date, holdProgress: holdProgress)
                stage(fr)
            }
            .opacity(closed ? 0 : 1)
            .animation(.easeOut(duration: 0.3), value: closed)
            .allowsHitTesting(!closed)

            chrome
                .opacity(closed ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: closed)

            Text("closed. still going.")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)
                .frame(width: size.width, height: size.height)
                .opacity(closed ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.15), value: closed)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Chrome

    private var chrome: some View {
        let layout = input.layout
        return ZStack {
            MorningHeader()
            HStack {
                Spacer()
                GlassCircleButton(symbol: "xmark", label: "Close, keep going", diameter: 44) {
                    close()
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 44)
        .padding(.top, layout.safeArea.top + 6)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
    }

    // MARK: Stage

    @ViewBuilder
    private func stage(_ fr: MPBFrame) -> some View {
        let sc = fr.scene
        let colors = MPBColors(
            ink: Theme.ink,
            paper: Theme.surface,
            canvas: Theme.canvas,
            border: Theme.border,
            accent: Theme.accent,
            muted: Theme.surfaceMuted
        )
        let reduce = input.reduceMotion
        let w = input.layout.size.width
        let h = input.layout.size.height

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                MPBDraw.paper(&context, scene: sc, s: fr.sheet, reduce: reduce, colors: colors)
            }
            .frame(width: w, height: sc.paperWin)
            .clipped()
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(30, sc.paperWin))
                    Rectangle().fill(Color.black)
                }
            }
            .offset(y: sc.groupTop)
            .accessibilityHidden(true)

            Canvas { context, _ in
                MPBDraw.machine(&context, scene: sc, fr: fr, reduce: reduce, colors: colors)
            }
            .frame(width: w, height: sc.groupH)
            .offset(y: sc.groupTop)
            .accessibilityHidden(true)

            if let tf = fr.tear {
                Canvas { context, _ in
                    let sym = context.resolveSymbol(id: 0)
                    MPBDraw.tear(&context, scene: sc, tf: tf, sym: sym, reduce: reduce, colors: colors)
                } symbols: {
                    Canvas { context, _ in
                        MPBDraw.sheet(&context, scene: sc, s: tf.frozen, reduce: reduce, colors: colors)
                    }
                    .frame(width: w, height: sc.paperWin)
                    .tag(0)
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            if fr.accessibleHeading {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(input.data.heading))
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(fr.hits) { hit in
                hitView(hit)
            }
            ForEach(fr.drums) { drum in
                drumView(drum, fr)
            }

            goButton(fr)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    // MARK: Hit areas

    @ViewBuilder
    private func hitView(_ hit: MPBHit) -> some View {
        switch hit.kind {
        case .row:
            Color.clear
                .contentShape(Rectangle())
                .frame(width: hit.rect.width, height: hit.rect.height)
                .offset(x: hit.rect.minX, y: hit.rect.minY)
                .onTapGesture { engine.userSelectRow(hit.index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(hit.label))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { engine.userSelectRow(hit.index) }
        case .home:
            MPBPressTarget(
                rect: hit.rect,
                label: hit.label,
                onDown: { engine.pressBegan(.home) },
                onCancel: { engine.pressEnded() },
                onFire: { engine.pressEnded(); takeDoor(.home) }
            )
            .offset(x: hit.rect.minX, y: hit.rect.minY)
        case .skip:
            MPBPressTarget(
                rect: hit.rect,
                label: hit.label,
                onDown: { engine.pressBegan(.skip) },
                onCancel: { engine.pressEnded() },
                onFire: { engine.pressEnded(); takeDoor(.skip) }
            )
            .offset(x: hit.rect.minX, y: hit.rect.minY)
        case .hold:
            Color.clear
                .contentShape(Rectangle())
                .frame(width: hit.rect.width, height: hit.rect.height)
                .offset(x: hit.rect.minX, y: hit.rect.minY)
                .cantTodayHold(
                    duration: 1.5,
                    progress: $holdProgress,
                    isHolding: $holding,
                    onBegan: {
                        engine.holdBegan()
                        input.haptics.play(.soft)
                    },
                    onComplete: { finishHold() },
                    onCancel: { engine.holdEnded() }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(hit.label))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("skip today")) { finishHold() }
        }
    }

    // MARK: Reels

    private func drumView(_ d: MPBDrumRect, _ fr: MPBFrame) -> some View {
        let k = d.k
        let sc = fr.scene
        let pitch = sc.pitch
        let p = sc.p1 * (k == 2 ? 0.75 : 1)
        let counts = [12, 12, 2]
        let names = ["hour", "minute", "am or pm"]
        let peek = CGFloat(fr.peek[k]) * pitch
        let value = fr.reelValue[k]
        let colors = MPBColors(
            ink: Theme.ink,
            paper: Theme.surface,
            canvas: Theme.canvas,
            border: Theme.border,
            accent: Theme.accent,
            muted: Theme.surfaceMuted
        )
        let reducePulse = fr.reelPulse
        return CantTodayDrum(
            count: counts[k],
            selection: Binding(get: { engine.reel[k] }, set: { engine.reel[k] = $0 }),
            rowHeight: pitch,
            visibleRows: 3,
            wraps: k < 2,
            isBlocked: { idx in !engine.cellAllowed(k, idx) },
            onBlocked: { idx in
                engine.cellBlocked(k, idx)
                input.haptics.play(.soft)
            },
            onDetent: { input.haptics.play(.light) },
            isInteracting: Binding(get: { engine.drumTouch[k] }, set: { engine.setDrumTouch(k, $0) })
        ) { index, distance in
            MPBDrumCell(
                text: MPBFormat.reel(k, index),
                dim: !engine.cellAllowed(k, index),
                distance: distance,
                width: d.rect.width,
                pitch: pitch,
                p: p,
                ink: colors.canvas
            )
        }
        .offset(y: -peek)
        .frame(width: d.rect.width, height: d.rect.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .opacity(reducePulse)
        .offset(x: d.rect.minX, y: d.rect.minY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(names[k]))
        .accessibilityValue(Text(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: engine.step(k, 1)
            case .decrement: engine.step(k, -1)
            @unknown default: break
            }
        }
    }

    // MARK: Set alarm

    private func goButton(_ fr: MPBFrame) -> some View {
        let size = input.layout.size
        let top = size.height - input.layout.safeArea.bottom - 12 - 56
        return Button {
            setAlarm()
        } label: {
            Text("set alarm")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.surface)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(Theme.ink))
                .contentShape(Capsule())
        }
        .buttonStyle(MPBPressStyle(reduceMotion: input.reduceMotion))
        .frame(width: size.width - Theme.pageMargin * 2, height: 56)
        .opacity(fr.goVisible ? (fr.goEnabled ? 1 : 0.3) : 0)
        .animation(.easeOut(duration: 0.15), value: fr.goVisible)
        .animation(.easeOut(duration: 0.15), value: fr.goEnabled)
        .allowsHitTesting(fr.goVisible && fr.goEnabled)
        .accessibilityHidden(!fr.goVisible)
        .offset(x: Theme.pageMargin, y: top)
    }

    // MARK: Actions

    /// A door is taken: a heavy tap, a beat for the paper to answer, then the real action.
    private func takeDoor(_ kind: MPBConfirm) {
        guard !acted, !closed, engine.canTake(kind) else { return }
        acted = true
        engine.commit(kind)
        input.haptics.play(.heavy)
        let actions = input.actions
        switch kind {
        case .home:
            finish(afterMilliseconds: 450) { actions.homeWorkout() }
        case .skip:
            finish(afterMilliseconds: 450) { actions.skip() }
        case .alarm:
            break
        }
    }

    private func setAlarm() {
        guard !acted, !closed, let choice = engine.alarmChoice() else { return }
        acted = true
        engine.commit(.alarm)
        input.haptics.play(.heavy)
        let actions = input.actions
        finish(afterMilliseconds: 450) { actions.reschedule(choice.day, choice.time) }
    }

    /// The hold finished: the slip tears at the perforation and the "skipped" slip feeds out.
    private func finishHold() {
        guard !acted, !closed else { return }
        acted = true
        engine.finishHold(holdProgress: holdProgress)
        input.haptics.play(.heavy)
        holdProgress = 0
        holding = false
        let actions = input.actions
        // A little longer than a tap, so the tear can be seen.
        finish(afterMilliseconds: 900) { actions.skip() }
    }

    private func close() {
        guard !acted else { return }
        acted = true
        closed = true
        engine.closing()
        let actions = input.actions
        finish(afterMilliseconds: 450) { actions.close() }
    }

    private func finish(afterMilliseconds ms: Int, _ action: @escaping () -> Void) {
        let reduce = input.reduceMotion
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduce ? 150 : ms))
            action()
        }
    }
}

// MARK: - Small views

/// A press that fires on lift when it is still on the row (same as a tap with a pressed look).
private struct MPBPressTarget: View {
    let rect: CGRect
    let label: String
    let onDown: () -> Void
    let onCancel: () -> Void
    let onFire: () -> Void

    @State private var isDown = false

    var body: some View {
        let area = CGRect(x: -12, y: -12, width: rect.width + 24, height: rect.height + 24)
        return Color.clear
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDown && area.contains(value.location) {
                            isDown = true
                            onDown()
                        } else if isDown && !area.contains(value.location) {
                            isDown = false
                            onCancel()
                        }
                    }
                    .onEnded { value in
                        let was = isDown
                        isDown = false
                        if was && area.contains(value.location) {
                            onFire()
                        } else {
                            onCancel()
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onFire() }
    }
}

private struct MPBPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// One row of a drum reel: dot-matrix text that squashes and fades away from the centre line,
/// as if it wrapped round a cylinder.
private struct MPBDrumCell: View {
    let text: String
    let dim: Bool
    let distance: CGFloat
    let width: CGFloat
    let pitch: CGFloat
    let p: CGFloat
    let ink: Color

    var body: some View {
        let d = Double(distance)
        let canvasH = pitch * 2
        return Canvas { context, size in
            let th = d * 0.66
            if abs(th) > 0.95 { return }
            let s = cos(th)
            let curve = CGFloat(sin(th) / sin(0.66) * 0.98) * pitch - CGFloat(d) * pitch
            let cy = size.height / 2 + curve
            let px = p * CGFloat(0.55 + 0.45 * s)
            let py = px * CGFloat(s)
            let bold = abs(d) < 0.5
            var path = Path()
            mpbAddText(
                &path, text,
                x0: size.width / 2 - mpbStrW(text, px) / 2,
                y0: cy - 3.5 * py,
                px: px, py: py,
                r: px * (bold ? 0.4 : 0.37),
                bold: bold
            )
            let alpha = pow(max(0, s), 2.2) * (dim ? 0.22 : 1)
            context.fill(path, with: .color(ink.opacity(alpha)))
        }
        .frame(width: width, height: canvasH)
        .frame(width: width, height: pitch)
    }
}

// MARK: - Plain values

private nonisolated struct MPBColors {
    let ink: Color
    let paper: Color
    let canvas: Color
    let border: Color
    let accent: Color
    let muted: Color
}

private nonisolated enum MPBDoor {
    case reschedule, home, skip
}

private nonisolated enum MPBCostKind {
    case week, row, streak
}

private nonisolated enum MPBConfirm {
    case alarm, skip, home
}

private nonisolated enum MPBTag {
    case none, board, note, home, skip, hold, flap, tail
}

private nonisolated enum MPBHitKind {
    case row, home, skip, hold
}

private nonisolated struct MPBHit: Identifiable {
    let id: String
    let kind: MPBHitKind
    let index: Int
    let rect: CGRect
    let label: String
}

private nonisolated struct MPBDrumRect: Identifiable {
    let k: Int
    let rect: CGRect
    var id: Int { k }
}

/// What the printer prints, copied out of the contract once (the contract types are main-actor;
/// the drawing is not).
private nonisolated struct MPBContent {
    struct Target {
        let short: String
        let name: String
        let defaultMin: Int
        /// The three tile texts of the closed row (hour, minute, am/pm).
        let tiles: [String]
    }
    struct Cost {
        let kind: MPBCostKind
        let big: String
        let hot: Bool
    }

    var heading: String
    var doors: [MPBDoor]
    var targets: [Target]
    var cost: [Cost]
    var homeMinutes: Int?
    var homeLeft: Int
    var homeOf: Int
    var skipNeedsHold: Bool

    static let empty = MPBContent(
        heading: "", doors: [], targets: [], cost: [], homeMinutes: nil, homeLeft: 0, homeOf: 3, skipNeedsHold: false
    )
}

private nonisolated enum MPBFormat {
    static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Text of a reel value: hour 1...12, minute 00...55, am/pm.
    static func reel(_ k: Int, _ v: Int) -> String {
        switch k {
        case 0: return "\(v + 1)"
        case 1: return pad2(v * 5)
        default: return v == 1 ? "pm" : "am"
        }
    }

    static func minutes(h: Int, m: Int, a: Int) -> Int {
        (((h + 1) % 12) + (a == 1 ? 12 : 0)) * 60 + m * 5
    }

    static func indices(_ minutes: Int) -> (h: Int, m: Int, a: Int) {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        let hh = wrapped / 60
        let mm = wrapped % 60
        let h12 = hh % 12 == 0 ? 12 : hh % 12
        return (h12 - 1, Int((Double(mm) / 5).rounded()) % 12, hh >= 12 ? 1 : 0)
    }
}

private nonisolated func mpbClamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T {
    return min(max(x, lo), hi)
}

private nonisolated func mpbEase(_ x: Double) -> Double {
    return 1 - pow(1 - x, 3)
}

private nonisolated func mpbSmooth(_ x: Double) -> Double {
    let u = mpbClamp(x, 0, 1)
    return u * u * (3 - 2 * u)
}

/// Line feed with a small overshoot (0.5 pt on any row height).
private nonisolated func mpbEase1(_ p: Double, _ h: Double) -> Double {
    if p >= 1 { return 1 }
    if p <= 0 { return 0 }
    let c1 = mpbClamp(0.5 / h / 0.059, 0.15, 1.2)
    let c3 = c1 + 1
    let q = p - 1
    return 1 + c3 * q * q * q + c1 * q * q
}

private nonisolated func mpbHash(_ i: Int, _ k: Int) -> Double {
    let a = UInt32(truncatingIfNeeded: i) &* 374761393
    let b = UInt32(truncatingIfNeeded: k) &* 668265263
    var h = a &+ b
    h = (h ^ (h >> 13)) &* 1274126177
    return Double(h ^ (h >> 16)) / 4294967296.0
}

private nonisolated func mpbDot(_ path: inout Path, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

/// Points along a rounded rectangle's outline, `step` apart.
private nonisolated func mpbRRPoints(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, step: CGFloat) -> [CGPoint] {
    struct Part {
        let isArc: Bool
        let a: CGPoint
        let b: CGPoint
        let center: CGPoint
        let start: CGFloat
        let len: CGFloat
    }
    func line(_ a: CGPoint, _ b: CGPoint) -> Part {
        return Part(isArc: false, a: a, b: b, center: .zero, start: 0, len: hypot(b.x - a.x, b.y - a.y))
    }
    func arc(_ c: CGPoint, _ start: CGFloat) -> Part {
        return Part(isArc: true, a: .zero, b: .zero, center: c, start: start, len: CGFloat.pi / 2 * r)
    }
    let parts: [Part] = [
        line(CGPoint(x: x + r, y: y), CGPoint(x: x + w - r, y: y)),
        arc(CGPoint(x: x + w - r, y: y + r), -CGFloat.pi / 2),
        line(CGPoint(x: x + w, y: y + r), CGPoint(x: x + w, y: y + h - r)),
        arc(CGPoint(x: x + w - r, y: y + h - r), 0),
        line(CGPoint(x: x + w - r, y: y + h), CGPoint(x: x + r, y: y + h)),
        arc(CGPoint(x: x + r, y: y + h - r), CGFloat.pi / 2),
        line(CGPoint(x: x, y: y + h - r), CGPoint(x: x, y: y + r)),
        arc(CGPoint(x: x + r, y: y + r), CGFloat.pi)
    ]
    var total: CGFloat = 0
    for p in parts { total += p.len }
    let count = max(1, Int((total / step).rounded()))
    var pts: [CGPoint] = []
    for k in 0..<count {
        var d = CGFloat(k) * total / CGFloat(count)
        for p in parts {
            if d <= p.len {
                if p.isArc {
                    let ang = p.start + d / p.len * CGFloat.pi / 2
                    pts.append(CGPoint(x: p.center.x + cos(ang) * r, y: p.center.y + sin(ang) * r))
                } else {
                    let u: CGFloat = p.len > 0 ? d / p.len : 0
                    pts.append(CGPoint(x: p.a.x + (p.b.x - p.a.x) * u, y: p.a.y + (p.b.y - p.a.y) * u))
                }
                break
            }
            d -= p.len
        }
    }
    return pts
}

// MARK: Dot text

private nonisolated enum MPBFont {
    /// The two glyphs the prototype adds to the shared font.
    static let extra: [Character: PrinterDotGlyph] = [
        "×": PrinterDotGlyph(
            rows: ["00000", "10001", "01010", "00100", "01010", "10001", "00000"].map { row in row.map { $0 == "1" } },
            width: 5
        ),
        "<": PrinterDotGlyph(
            rows: ["00001", "00010", "00100", "01000", "00100", "00010", "00001"].map { row in row.map { $0 == "1" } },
            width: 5
        )
    ]

    static func glyph(_ ch: Character) -> PrinterDotGlyph? {
        if let g = PrinterDotFont.glyph(ch) { return g }
        return extra[ch]
    }
}

private nonisolated func mpbStrW(_ s: String, _ p: CGFloat) -> CGFloat {
    return CGFloat(s.count) * 6 * p - p
}

/// Pushes the dots of one string into `path`. A cell is 6 dots wide.
private nonisolated func mpbAddText(_ path: inout Path, _ str: String, x0: CGFloat, y0: CGFloat, px: CGFloat, py: CGFloat, r: CGFloat, bold: Bool) {
    var cx = x0
    for ch in str {
        if let gl = MPBFont.glyph(ch) {
            let off = (5 - gl.width) / 2
            for (j, row) in gl.rows.enumerated() {
                for (i, lit) in row.enumerated() where lit {
                    let x = cx + (CGFloat(off + i) + 0.5) * px
                    let y = y0 + (CGFloat(j) + 0.5) * py
                    mpbDot(&path, x, y, r)
                    if bold { mpbDot(&path, x + px * 0.42, y, r) }
                }
            }
        }
        cx += 6 * px
    }
}

// MARK: - Paper rows and the job

private nonisolated struct MPBLayer {
    var path: Path
    var alpha: Double
    var coral = false
    var stroke: CGFloat? = nil
    var evenOdd = false
}

private nonisolated struct MPBRow {
    var tag: MPBTag = .none
    var isText = false
    var h: CGFloat
    var py: CGFloat = 0
    var layers: [MPBLayer] = []
    // text
    var chars: [Character] = []
    var len = 0
    var cw: CGFloat = 0
    var p: CGFloat = 0
    var x0: CGFloat = 0
    var endX: CGFloat = 0
    // graphic
    var gdur: Double = 0.2
    // pressed highlight (home and skip rows)
    var hl: CGRect = .zero
    var hlR: CGFloat = 0
    var pad: CGFloat = 0
    // board
    var f: CGFloat = 1
    var p1: CGFloat = 3
    // flap row
    var flapText = ""
    var flapP: CGFloat = 0
    // feed
    var fdur: Double? = nil
    var smoothFeed = false
    var noCar = false
    // timeline (seconds on the job's clock)
    var s: Double = .infinity
    var dur: Double = 0
    var e: Double = 0
    var fs: Double = .infinity
    var cs: Double = .infinity

    var isLive: Bool { tag == .board || tag == .note || tag == .flap }
}

private nonisolated struct MPBFibre {
    let i: Int
    let len: CGFloat
    let ang: CGFloat
    let a: Double
    let white: Bool
}

/// The torn edge of the paper that stays in the printer.
private nonisolated struct MPBRag {
    var n: Int
    var step: CGFloat
    var rel: [CGFloat]
    var fib: [MPBFibre]
    var dir: CGFloat
    var front: CGFloat

    static func make(seed: Int, pw: CGFloat, dir: CGFloat) -> MPBRag {
        let n = Int(ceil(pw / 2.2)) + 1
        var rel: [CGFloat] = []
        var fib: [MPBFibre] = []
        for i in 0..<n {
            let a = sin(Double(i) * 0.23 + Double(seed) * 7) * 1.4
            let b = sin(Double(i) * 0.071 + Double(seed) * 3) * 1.2
            let c = (mpbHash(i, seed) - 0.5) * 2.4
            rel.append(CGFloat(a + b + c))
            if mpbHash(i, seed + 9) < 0.62 {
                fib.append(MPBFibre(
                    i: i,
                    len: CGFloat(2 + mpbHash(i, seed + 5) * 4.4),
                    ang: CGFloat((mpbHash(i, seed + 3) - 0.5) * 2.0),
                    a: 0.25 + mpbHash(i, seed + 1) * 0.4,
                    white: mpbHash(i, seed + 2) > 0.5
                ))
            }
        }
        return MPBRag(n: n, step: pw / CGFloat(n - 1), rel: rel, fib: fib, dir: dir, front: 0)
    }
}

private nonisolated struct MPBJob {
    var rows: [MPBRow]
    var total: CGFloat
    var stub: CGFloat
    var adv: Double
    /// The row whose bottom edge is the perforation, or -1.
    var perfIdx: Int
    /// Engine time at which this job's own clock reads 0.
    var t0: Double
    /// Job time at which the torn stub starts to settle (bob), or nil.
    var bobAfter: Double?

    static let empty = MPBJob(rows: [], total: 0, stub: 0, adv: 0.035, perfIdx: -1, t0: 0, bobAfter: nil)

    /// How far the paper has been fed by time `t`.
    func feed(at t: Double, reduce: Bool) -> CGFloat {
        var feed: CGFloat = 0
        for r in rows {
            if t < r.fs { break }
            if reduce {
                feed += r.h
            } else {
                let fd = r.fdur ?? adv
                let u = (t - r.fs) / fd
                let k = r.smoothFeed ? mpbSmooth(u) : mpbEase1(u, Double(r.h))
                feed += r.h * CGFloat(k)
            }
        }
        return feed
    }

    /// Where the print head is along the row, relative to the paper's inner left edge.
    func carriageX(at t: Double, reduce: Bool, inw: CGFloat) -> CGFloat {
        if reduce { return 0 }
        var cur: MPBRow? = nil
        var prev: MPBRow? = nil
        for r in rows {
            if !r.s.isFinite { continue }
            if r.cs <= t {
                prev = cur
                cur = r
            } else {
                break
            }
        }
        guard let a = cur else { return 0 }
        if a.noCar { return 0 }
        let x0: CGFloat = a.isText ? a.x0 : 0
        if t < a.s {
            let u = mpbClamp((t - a.cs) / max(0.001, a.s - a.cs), 0, 1)
            var px: CGFloat = 0
            if let prev, t - prev.e < 0.12 { px = prev.endX }
            if u < 0.55 { return px * CGFloat(1 - mpbEase(u / 0.55)) }
            return x0 * CGFloat(mpbEase((u - 0.55) / 0.45))
        }
        if t <= a.e {
            if a.isText {
                let travelled = CGFloat((t - a.s) * (Double(a.len) / max(0.001, a.dur))) * a.cw
                return min(a.endX + a.p, a.x0 + travelled)
            }
            return inw * CGFloat((t - a.s) / max(0.001, a.dur))
        }
        let ret = mpbClamp((t - a.e) / 0.14, 0, 1)
        return a.endX * CGFloat(1 - mpbEase(ret))
    }

    /// How far down each key is (0 to 1): one press per printed character, 90 ms each.
    func keyDepths(at t: Double, keyCount: Int, pool: [Int], space: Int) -> [Double] {
        var dep = [Double](repeating: 0, count: keyCount)
        if pool.isEmpty { return dep }
        let win = 0.09
        for (ri, r) in rows.enumerated() {
            if r.tag == .tail || !r.s.isFinite || t < r.s || t > r.e + win + 0.01 { continue }
            if r.isText {
                if r.len == 0 || r.dur <= 0 { continue }
                let d = r.dur / Double(r.len)
                let hi = min(r.len - 1, Int(floor((t - r.s) / d)) - 1)
                let lo = max(0, Int(ceil((t - win - r.s) / d)) - 1)
                if lo > hi { continue }
                for q in lo...hi {
                    let tp = r.s + Double(q + 1) * d
                    var k = pool[Int(mpbHash(ri * 977 + q, 3) * Double(pool.count)) % pool.count]
                    if q < r.chars.count && r.chars[q] == " " && space >= 0 { k = space }
                    dep[k] = max(dep[k], MPBJob.keyShape(t - tp))
                }
            } else {
                if r.dur <= 0 { continue }
                let step = 0.07
                let hi = Int(floor((t - r.s) / step))
                let lo = max(0, Int(ceil((t - win - r.s) / step)))
                if lo > hi { continue }
                for kc in lo...hi {
                    let tp = r.s + Double(kc) * step
                    if tp >= r.s + r.dur { continue }
                    let k = pool[Int(mpbHash(ri * 31 + kc, 5) * Double(pool.count)) % pool.count]
                    dep[k] = max(dep[k], MPBJob.keyShape(t - tp))
                }
            }
        }
        return dep
    }

    static func keyShape(_ age: Double) -> Double {
        let a = age / 0.09
        if a < 0 || a >= 1 { return 0 }
        return a < 0.4 ? a / 0.4 : 1 - (a - 0.4) / 0.6
    }
}

// MARK: - Metrics, geometry, scene

private nonisolated struct MPBMetrics {
    let f: CGFloat
    let u: CGFloat
    let inw: CGFloat
    let tail: CGFloat
    let stub0: CGFloat

    init(inw: CGFloat, scale: CGFloat) {
        f = scale
        u = 1.6 * scale
        self.inw = inw
        tail = 16 * scale
        stub0 = 22 * scale
    }
}

private nonisolated struct MPBGeom {
    static let sp: CGFloat = 22

    let w: CGFloat
    let h: CGFloat
    let short: Bool
    let pw: CGFloat
    let px: CGFloat
    let inw: CGFloat
    let bx0: CGFloat
    let bx1: CGFloat
    let bodyH: CGFloat
    let keyRows: Int
    let keyH: CGFloat
    let gapK: CGFloat
    let keysH: CGFloat
    let regionTop: CGFloat
    let avail: CGFloat

    var fixed: CGFloat { bodyH + gapK + keysH }

    init(width: CGFloat, height: CGFloat, contentTop: CGFloat, contentBottom: CGFloat) {
        w = width
        h = height
        let isShort = height < 720
        short = isShort
        pw = max(160, min(width - 72, 320))
        px = ((width - pw) / 2).rounded()
        inw = pw - 2 * MPBGeom.sp
        let bw = min(width - 32, pw + 40)
        bx0 = ((width - bw) / 2).rounded()
        bx1 = bx0 + bw
        let rowsOfKeys = isShort ? 1 : 2
        let capH: CGFloat = isShort ? 17 : 19
        bodyH = isShort ? 50 : 68
        keyRows = rowsOfKeys
        keyH = capH
        gapK = isShort ? 6 : 12
        keysH = CGFloat(rowsOfKeys) * capH + CGFloat(rowsOfKeys - 1) * 4 + 3
        regionTop = contentTop
        avail = max(0, contentBottom - contentTop)
    }
}

private nonisolated struct MPBKey {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
    let isSpace: Bool
}

private nonisolated struct MPBScene {
    let g: MPBGeom
    let paperWin: CGFloat
    let groupH: CGFloat
    let groupTop: CGFloat
    let keys: [MPBKey]
    let pool: [Int]
    let space: Int
    let body: [MPBLayer]
    let coverRects: [CGRect]
    let coverDots: Path
    /// Drum row height (same for every reel).
    var pitch: CGFloat = 20
    /// Dot pitch of the open board row's text.
    var p1: CGFloat = 3
}

// MARK: - Board geometry

private nonisolated struct MPBTileGeo {
    var i: Int
    var y: CGFloat
    var h: CGFloat
    var a: CGFloat
    var P: CGFloat
    var lp: CGFloat
    var tx: [CGFloat]
    var tw: [CGFloat]
    var ty: CGFloat
    var th: CGFloat
    var colX: CGFloat
}

/// The departure board: every row is 30 tall except the open one (84). `selA` is how open each is.
private nonisolated func mpbBoardGeo(n: Int, f: CGFloat, hb: CGFloat, p1: CGFloat, inw: CGFloat, selA: [Double]) -> [MPBTileGeo] {
    if n == 0 { return [] }
    let hS = 84 * f
    let kk: CGFloat = n > 1 ? CGFloat(n - 1) * hS / max(1, hb - hS) : 1
    var ws: [CGFloat] = []
    var sum: CGFloat = 0
    for i in 0..<n {
        let a = CGFloat(i < selA.count ? selA[i] : 0)
        let w = 1 + (kk - 1) * a
        ws.append(w)
        sum += w
    }
    let p0 = 2.1 * f
    var out: [MPBTileGeo] = []
    var yy: CGFloat = 0
    for i in 0..<n {
        let h = hb * ws[i] / sum
        let a = CGFloat(i < selA.count ? selA[i] : 0)
        let P = p0 + (p1 - p0) * a
        let pad = 5 * f
        let gap = 3 * f
        let wA = 8.25 * P + 2 * pad
        let wM = 11 * P + 2 * pad
        let wH = 11 * P + 2 * pad
        let colW = 3.2 * P
        let xA = inw - wA
        let xM = xA - gap - wM
        let xH = xM - colW - wH
        out.append(MPBTileGeo(
            i: i, y: yy, h: h, a: a, P: P, lp: (1.9 + 0.5 * a) * f,
            tx: [xH, xM, xA], tw: [wH, wM, wA],
            ty: yy + 3 * f, th: h - 6 * f, colX: xM - colW / 2
        ))
        yy += h
    }
    return out
}

// MARK: - Building the paper

private nonisolated struct MPBMenu {
    var rows: [MPBRow]
    var total: CGFloat
    var f: CGFloat
    var hb: CGFloat
    var p1: CGFloat
    var boardIdx = -1
    var noteIdx = -1
    var homeIdx = -1
    var skipIdx = -1
    var holdIdx = -1
}

private nonisolated enum MPBBuild {
    static let rate = 300.0
    static let adv = 0.035

    // MARK: Row makers

    static func wrap(_ s: String, _ n: Int) -> [String] {
        var out: [String] = []
        var line = ""
        for word in s.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let w = String(word)
            if line.isEmpty {
                line = w
            } else if line.count + 1 + w.count <= n {
                line += " " + w
            } else {
                out.append(line)
                line = w
            }
        }
        if !line.isEmpty { out.append(line) }
        return out
    }

    static func textRow(_ str: String, _ m: MPBMetrics, p: CGFloat, bold: Bool, top: CGFloat, bot: CGFloat? = nil) -> MPBRow {
        let len = str.count
        let cw = 6 * p
        var row = MPBRow(h: top + 9 * p + (bot ?? 3.4 * m.f))
        row.isText = true
        row.chars = Array(str)
        row.len = len
        row.cw = cw
        row.p = p
        row.x0 = 0
        row.endX = CGFloat(len) * cw - p
        var path = Path()
        mpbAddText(&path, str, x0: 0, y0: top, px: p, py: p, r: p * (bold ? 0.4 : 0.37), bold: bold)
        row.layers = [MPBLayer(path: path, alpha: 1)]
        return row
    }

    static func rule(top: CGFloat, _ m: MPBMetrics) -> MPBRow {
        var row = MPBRow(h: top + 7 * m.f)
        row.gdur = 0.28
        var path = Path()
        let y = top + 3 * m.f
        var x: CGFloat = 1
        while x < m.inw {
            mpbDot(&path, x, y, 0.9)
            x += 4.4 * m.f + 1.2
        }
        row.layers = [MPBLayer(path: path, alpha: 0.3)]
        return row
    }

    static func dotRect(_ path: inout Path, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rad: CGFloat, f: CGFloat) {
        for pt in mpbRRPoints(x: x, y: y, w: w, h: h, r: rad, step: 3.3 * f) {
            mpbDot(&path, pt.x, pt.y, 0.95 * f)
        }
    }

    static func boardRow(hb: CGFloat, f: CGFloat, p1: CGFloat) -> MPBRow {
        var row = MPBRow(h: hb)
        row.tag = .board
        row.gdur = 0.3
        row.f = f
        row.p1 = p1
        return row
    }

    static func noteRow(_ m: MPBMetrics) -> MPBRow {
        let np = 1.9 * m.f
        var row = MPBRow(h: 2 * m.f + 9 * np + 2 * m.f)
        row.tag = .note
        row.gdur = 0.02
        row.p = np
        row.f = m.f
        return row
    }

    static func homeRow(minutes: Int, left: Int, of total: Int, top: CGFloat, _ m: MPBMetrics) -> MPBRow {
        let f = m.f
        let hh = 34 * f
        var row = MPBRow(h: top + hh + 4 * f)
        row.tag = .home
        row.gdur = 0.2
        row.pad = top
        row.hl = CGRect(x: -4, y: top, width: m.inw + 8, height: hh)
        row.hlR = 7 * f

        var box = Path()
        dotRect(&box, x: 0, y: top, w: m.inw, h: hh, rad: 7 * f, f: f)
        var layers: [MPBLayer] = [MPBLayer(path: box, alpha: 0.85)]

        let cp = 2.2 * f
        let hw = 9 * cp
        let ox = 12 * f
        let oy = top + (hh - 9 * cp) / 2
        let r = cp * 0.4
        var icon = Path()
        for (j, line) in PrinterDotIcons.house.enumerated() {
            for (i, ch) in line.enumerated() {
                if ch == "." { continue }
                let x = ox + (CGFloat(i) + 0.5) * cp
                let y = oy + (CGFloat(j) + 0.5) * cp
                if ch == "o" {
                    mpbDot(&icon, x, y, r * 1.45)
                    mpbDot(&icon, x, y, r * 0.55)
                } else {
                    mpbDot(&icon, x, y, r)
                }
            }
        }
        var iconLayer = MPBLayer(path: icon, alpha: 1)
        iconLayer.evenOdd = true
        layers.append(iconLayer)

        let tp = 2.4 * f
        var txt = Path()
        mpbAddText(&txt, "\(minutes) min", x0: ox + hw + 12 * f, y0: top + (hh - 9 * tp) / 2 + tp, px: tp, py: tp, r: tp * 0.4, bold: true)
        layers.append(MPBLayer(path: txt, alpha: 1))

        let pr = 4.4 * f
        let stepX = pr * 2 + 6 * f
        let px0 = m.inw - 14 * f - CGFloat(max(0, total - 1)) * stepX - pr
        var filled = Path()
        var ring = Path()
        for i in 0..<max(0, total) {
            let x = px0 + CGFloat(i) * stepX
            let y = top + hh / 2
            if i < left {
                filled.addEllipse(in: CGRect(x: x - pr, y: y - pr, width: pr * 2, height: pr * 2))
            } else {
                ring.addEllipse(in: CGRect(x: x - pr, y: y - pr, width: pr * 2, height: pr * 2))
            }
        }
        layers.append(MPBLayer(path: filled, alpha: 1))
        var ringLayer = MPBLayer(path: ring, alpha: 0.4)
        ringLayer.stroke = 1.2
        layers.append(ringLayer)

        row.layers = layers
        return row
    }

    static func skipRow(top: CGFloat, _ m: MPBMetrics) -> MPBRow {
        let f = m.f
        let hh = 34 * f
        var row = MPBRow(h: top + hh + 4 * f)
        row.tag = .skip
        row.gdur = 0.2
        row.pad = top
        row.hl = CGRect(x: -4, y: top, width: m.inw + 8, height: hh)
        row.hlR = 7 * f
        var box = Path()
        dotRect(&box, x: 0, y: top, w: m.inw, h: hh, rad: 7 * f, f: f)
        let tp = 2.4 * f
        let s = "skip today"
        var txt = Path()
        mpbAddText(&txt, s, x0: (m.inw - mpbStrW(s, tp)) / 2, y0: top + (hh - 9 * tp) / 2 + tp, px: tp, py: tp, r: tp * 0.4, bold: true)
        row.layers = [MPBLayer(path: box, alpha: 0.85), MPBLayer(path: txt, alpha: 1)]
        return row
    }

    static func costRow(_ cost: [MPBContent.Cost], top: CGFloat, _ m: MPBMetrics) -> MPBRow {
        let f = m.f
        let bp = 3.3 * f
        let lp = 1.25 * f
        var row = MPBRow(h: top + 9 * bp + 4 * f + 9 * lp + 3 * f)
        row.gdur = 0.2
        var layers: [MPBLayer] = []
        let n = max(1, cost.count)
        for (i, q) in cost.enumerated() {
            let cx = (CGFloat(i) + 0.5) * m.inw / CGFloat(n)
            var big = Path()
            mpbAddText(&big, q.big, x0: cx - mpbStrW(q.big, bp) / 2, y0: top, px: bp, py: bp, r: bp * 0.4, bold: true)
            var bl = MPBLayer(path: big, alpha: 1)
            bl.coral = q.hot
            layers.append(bl)
            let lab: String
            switch q.kind {
            case .week: lab = "this week"
            case .row: lab = "in a row"
            case .streak: lab = "streak"
            }
            var lp2 = Path()
            mpbAddText(&lp2, lab, x0: cx - mpbStrW(lab, lp) / 2, y0: top + 9 * bp + 4 * f, px: lp, py: lp, r: lp * 0.37, bold: false)
            layers.append(MPBLayer(path: lp2, alpha: 0.66))
        }
        row.layers = layers
        return row
    }

    static func holdRow(_ m: MPBMetrics) -> MPBRow {
        let f = m.f
        let tp = 2.2 * f
        var row = MPBRow(h: 6 * f + 9 * tp + 12 * f)
        row.tag = .hold
        row.gdur = 0.2
        row.f = f
        let s = "hold to skip"
        var txt = Path()
        mpbAddText(&txt, s, x0: (m.inw - mpbStrW(s, tp)) / 2, y0: 6 * f, px: tp, py: tp, r: tp * 0.4, bold: true)
        row.layers = [MPBLayer(path: txt, alpha: 1)]
        return row
    }

    static func tailRow(_ m: MPBMetrics) -> MPBRow {
        var row = MPBRow(h: m.tail)
        row.tag = .tail
        row.gdur = 0
        row.noCar = true
        return row
    }

    static func feedOutRow(paperWin: CGFloat) -> MPBRow {
        var row = MPBRow(h: paperWin)
        row.gdur = 0.2
        row.fdur = 0.34
        row.smoothFeed = true
        row.noCar = true
        return row
    }

    static func stampRow(_ text: String, p: CGFloat, _ m: MPBMetrics) -> MPBRow {
        let f = m.f
        let w = mpbStrW(text, p) + 24 * f
        let bh = 9 * p + 16 * f
        var row = MPBRow(h: bh + 14 * f)
        row.gdur = 0.16
        let x = (m.inw - w) / 2
        let y = 6 * f
        var outer = Path()
        dotRect(&outer, x: x, y: y, w: w, h: bh, rad: 6 * f, f: f)
        var inner = Path()
        dotRect(&inner, x: x + 3.5 * f, y: y + 3.5 * f, w: w - 7 * f, h: bh - 7 * f, rad: 4 * f, f: f)
        var txt = Path()
        mpbAddText(&txt, text, x0: x + 12 * f, y0: y + 8 * f, px: p, py: p, r: p * 0.4, bold: true)
        row.layers = [MPBLayer(path: outer, alpha: 1), MPBLayer(path: inner, alpha: 0.5), MPBLayer(path: txt, alpha: 1)]
        return row
    }

    static func flapRow(_ str: String, maxP: CGFloat, _ m: MPBMetrics) -> MPBRow {
        let f = m.f
        let count = max(1, str.count)
        let P = min(maxP * f, (m.inw / CGFloat(count) - 13 * f) / 5)
        let th = 7 * P + 12 * f
        var row = MPBRow(h: th + 8 * f)
        row.tag = .flap
        row.gdur = 0.02
        row.flapText = str
        row.flapP = P
        row.f = f
        return row
    }

    // MARK: Layout and schedule

    @discardableResult
    static func layOut(_ rows: inout [MPBRow], from: Int = 0, startY: CGFloat = 0) -> CGFloat {
        var y = startY
        var i = from
        while i < rows.count {
            rows[i].py = y
            y += rows[i].h
            i += 1
        }
        return y
    }

    /// Row times: each row prints for its duration, then the paper advances `adv` before the next.
    static func schedule(_ rows: inout [MPBRow], from: Int, s0: Double) {
        var t = s0
        var i = from
        while i < rows.count {
            var r = rows[i]
            r.s = t
            r.dur = r.isText ? Double(r.len) / rate : r.gdur
            r.e = r.s + r.dur
            r.fs = r.s - adv
            r.cs = r.s - adv
            t = r.e + adv
            rows[i] = r
            i += 1
        }
    }

    // MARK: Menu

    static func menu(_ c: MPBContent, inw: CGFloat, f: CGFloat) -> MPBMenu {
        let m = MPBMetrics(inw: inw, scale: f)
        var rows: [MPBRow] = []
        let hp = 2.2 * f
        let hn = max(6, Int(floor((inw + hp) / (6 * hp))))
        for (i, line) in wrap(c.heading, hn).enumerated() {
            rows.append(textRow(line, m, p: hp, bold: true, top: i == 0 ? 2 * f : 0, bot: 3 * f))
        }
        rows.append(rule(top: 1 * f, m))

        let n = c.targets.count
        let hU = 30 * f
        let hS = 84 * f
        let hb: CGFloat = n > 1 ? CGFloat(n - 1) * hU + hS : hS
        let lw = 5 * 6 * 2.4 * f
        let p1 = max(2.4 * f, min(4.6 * f, (inw - lw - 10 * f - 36 * f) / 33.25))

        var out = MPBMenu(rows: [], total: 0, f: f, hb: hb, p1: p1)
        for door in c.doors {
            switch door {
            case .skip:
                if !c.skipNeedsHold {
                    out.skipIdx = rows.count
                    rows.append(skipRow(top: 2 * f, m))
                }
            case .reschedule:
                if n > 0 {
                    out.boardIdx = rows.count
                    rows.append(boardRow(hb: hb, f: f, p1: p1))
                    out.noteIdx = rows.count
                    rows.append(noteRow(m))
                }
            case .home:
                if let mins = c.homeMinutes {
                    out.homeIdx = rows.count
                    rows.append(homeRow(minutes: mins, left: c.homeLeft, of: c.homeOf, top: 2 * f, m))
                }
            }
        }
        if c.skipNeedsHold {
            if !c.cost.isEmpty { rows.append(costRow(c.cost, top: 3 * f, m)) }
            out.holdIdx = rows.count
            rows.append(holdRow(m))
        }
        rows.append(tailRow(m))
        out.total = layOut(&rows)
        out.rows = rows
        return out
    }

    /// The menu at the biggest scale (1.2 down to 0.7) that fits `maxH`.
    static func fitMenu(_ c: MPBContent, inw: CGFloat, maxH: CGFloat) -> MPBMenu {
        var sc: CGFloat = 1.2
        var m = menu(c, inw: inw, f: sc)
        while m.total > maxH && sc > 0.7 {
            sc = ((sc - 0.03) * 100).rounded() / 100
            m = menu(c, inw: inw, f: sc)
        }
        return m
    }

    // MARK: Confirm slip

    static func confirmRows(_ kind: MPBConfirm, day: String, time: String, homeMinutes: Int, inw: CGFloat, f: CGFloat) -> (rows: [MPBRow], total: CGFloat) {
        let m = MPBMetrics(inw: inw, scale: f)
        var rows: [MPBRow] = []
        let label: String
        switch kind {
        case .alarm: label = "alarm set"
        case .skip: label = "skipped"
        case .home: label = "home workout"
        }
        let sp = min(4.6 * f, (inw - 30 * f) / (6 * CGFloat(label.count)))
        rows.append(stampRow(label, p: sp, m))
        switch kind {
        case .alarm:
            rows.append(flapRow(day, maxP: 5.4, m))
            rows.append(flapRow(time, maxP: 4.4, m))
        case .home:
            rows.append(flapRow("\(homeMinutes) min", maxP: 4.4, m))
        case .skip:
            break
        }
        rows.append(tailRow(m))
        var total: CGFloat = 0
        for r in rows { total += r.h }
        return (rows, total)
    }

    static func fitConfirm(_ kind: MPBConfirm, day: String, time: String, homeMinutes: Int, inw: CGFloat, maxH: CGFloat) -> (rows: [MPBRow], f: CGFloat) {
        var sc: CGFloat = 1.25
        var c = confirmRows(kind, day: day, time: time, homeMinutes: homeMinutes, inw: inw, f: sc)
        while c.total > maxH && sc > 0.7 {
            sc = ((sc - 0.03) * 100).rounded() / 100
            c = confirmRows(kind, day: day, time: time, homeMinutes: homeMinutes, inw: inw, f: sc)
        }
        return (c.rows, sc)
    }

    // MARK: Scene

    static func scene(g: MPBGeom, p1: CGFloat) -> MPBScene {
        let winAvail = max(160, g.avail - g.fixed)
        let paperWin = winAvail.rounded()
        let groupH = paperWin + g.fixed
        let groupTop = (g.regionTop + (g.avail - groupH) / 2).rounded()

        var keys: [MPBKey] = []
        let gap: CGFloat = 5
        let kw = (g.bx1 - g.bx0 - 11 * gap) / 12
        let ky = paperWin + g.bodyH + g.gapK
        for i in 0..<12 {
            keys.append(MPBKey(x: g.bx0 + CGFloat(i) * (kw + gap), y: ky, w: kw, h: g.keyH, isSpace: false))
        }
        if g.keyRows == 2 {
            let y2 = ky + g.keyH + 4
            for i in [0, 1] {
                keys.append(MPBKey(x: g.bx0 + CGFloat(i) * (kw + gap), y: y2, w: kw, h: g.keyH, isSpace: false))
            }
            keys.append(MPBKey(x: g.bx0 + 2 * (kw + gap), y: y2, w: 8 * kw + 7 * gap, h: g.keyH, isSpace: true))
            for i in [10, 11] {
                keys.append(MPBKey(x: g.bx0 + CGFloat(i) * (kw + gap), y: y2, w: kw, h: g.keyH, isSpace: false))
            }
        }
        var pool: [Int] = []
        var space = -1
        for (i, k) in keys.enumerated() {
            if k.isSpace { space = i } else { pool.append(i) }
        }
        let machine = machineParts(g: g, sy: paperWin)
        var scene = MPBScene(
            g: g,
            paperWin: paperWin,
            groupH: groupH,
            groupTop: groupTop,
            keys: keys,
            pool: pool,
            space: space,
            body: machine.body,
            coverRects: machine.coverRects,
            coverDots: machine.coverDots
        )
        scene.p1 = p1
        scene.pitch = 6.3 * p1
        return scene
    }

    /// The printer's static dots: ghost paper guides, body outline, rail, platen, panel.
    static func machineParts(g: MPBGeom, sy: CGFloat) -> (body: [MPBLayer], coverRects: [CGRect], coverDots: Path) {
        var layers: [MPBLayer] = []

        var ghost = Path()
        var gy = sy - 8
        while gy > 24 {
            mpbDot(&ghost, g.px - 0.5, gy, 0.7)
            mpbDot(&ghost, g.px + g.pw + 0.5, gy, 0.7)
            gy -= 6
        }
        layers.append(MPBLayer(path: ghost, alpha: 0.12))

        var outline = Path()
        for pt in mpbRRPoints(x: g.bx0, y: sy, w: g.bx1 - g.bx0, h: g.bodyH, r: 15, step: 4.2) {
            if pt.y < sy + 1 && pt.x > g.px - 16 && pt.x < g.px + g.pw + 16 { continue }
            mpbDot(&outline, pt.x, pt.y, 1.15)
        }
        layers.append(MPBLayer(path: outline, alpha: 0.3))

        var rail = Path()
        var rx = g.bx0 + 18
        while rx <= g.bx1 - 18 {
            mpbDot(&rail, rx, sy + 10, 0.8)
            rx += 3.6
        }
        layers.append(MPBLayer(path: rail, alpha: 0.2))

        var platen = Path()
        var qx = g.px - 12
        while qx <= g.px + g.pw + 12 {
            mpbDot(&platen, qx, sy - 0.8, 1.15)
            mpbDot(&platen, qx, sy + 2.2, 1.15)
            qx += 2.6
        }
        layers.append(MPBLayer(path: platen, alpha: 0.85))

        let mid = (g.bx0 + g.bx1) / 2
        let py0 = sy + (g.short ? 21 : 24)
        let caption = "GYMLOCK"
        let cp: CGFloat = 1.05
        var cap = Path()
        mpbAddText(&cap, caption, x0: mid - (CGFloat(caption.count) * 6 * cp - cp) / 2, y0: py0, px: cp, py: cp, r: cp * 0.4, bold: false)
        layers.append(MPBLayer(path: cap, alpha: 0.34))

        let py1 = sy + g.bodyH - (g.short ? 13 : 17)
        var pills = Path()
        for mIdx in [-1, 0, 1] {
            let cx = mid + CGFloat(mIdx) * 34 - 6
            let w: CGFloat = 24
            let hh: CGFloat = 8
            for pt in mpbRRPoints(x: cx - w / 2, y: py1 - hh / 2, w: w, h: hh, r: 3.5, step: 3) {
                mpbDot(&pills, pt.x, pt.y, 0.8)
            }
        }
        layers.append(MPBLayer(path: pills, alpha: 0.26))

        var led = Path()
        mpbDot(&led, mid + 54, py1, 2.1)
        layers.append(MPBLayer(path: led, alpha: 0.8))

        var rects: [CGRect] = []
        var dots = Path()
        let sp = MPBGeom.sp
        let covers: [(CGFloat, CGFloat)] = [(g.px - 2, sp - 1), (g.px + g.pw - sp + 3, sp - 1)]
        for (x, w) in covers {
            rects.append(CGRect(x: x + 1, y: sy - 15, width: w - 2, height: 15))
            for pt in mpbRRPoints(x: x, y: sy - 15, w: w, h: 15, r: 3, step: 3.4) {
                if pt.y > sy - 1 { continue }
                mpbDot(&dots, pt.x, pt.y, 0.8)
            }
        }
        return (layers, rects, dots)
    }
}

// MARK: - One frame

/// Everything needed to draw one sheet of paper at one moment.
private nonisolated struct MPBSheet {
    var job: MPBJob
    var t: Double
    var now: Double
    var feed: CGFloat
    var bob: CGFloat
    var rag: MPBRag?
    var sel: Int
    var selA: [Double]
    var reelOn: Bool
    var reelText: [String]
    var tiles: [[String]]
    /// The half-flip a nudge gives each board row's hour tile, 0...0.5.
    var flapA: [Double]
    /// Reduce Motion: brightness pulse per board row (1 = none).
    var pulse: [Double]
    var note: String
    var noteT: Double
    var holdP: Double
    var holdPulse: Double
    var homeNudge: Double
    var homePulse: Double
    var pressed: MPBTag?
    /// Short place names of the board rows ("today", "thu").
    var labels: [String] = []
}

private nonisolated struct MPBTearFrame {
    var tau: Double
    var perfY: CGFloat
    var yTop: CGFloat
    var rag: MPBRag
    var frozen: MPBSheet
}

private nonisolated struct MPBFrame {
    var scene: MPBScene
    var sheet: MPBSheet
    var keyDepth: [Double]
    var carriage: CGFloat
    var knobBase: CGFloat
    var tear: MPBTearFrame?
    var hits: [MPBHit]
    var drums: [MPBDrumRect]
    var peek: [Double]
    var reelValue: [String]
    var reelPulse: Double
    var goVisible: Bool
    var goEnabled: Bool
    var accessibleHeading: Bool
}

// MARK: - Drawing

private nonisolated enum MPBDraw {
    static let flK = 3
    static let flSD = 0.07
    static let tearT = 0.40

    // MARK: Paper window

    static func paper(_ c: inout GraphicsContext, scene: MPBScene, s: MPBSheet, reduce: Bool, colors: MPBColors) {
        sheet(&c, scene: scene, s: s, reduce: reduce, colors: colors)
    }

    static func perfPath(px: CGFloat, pw: CGFloat, y: CGFloat) -> Path {
        var p = Path()
        var x = px + 3
        while x < px + pw - 3 {
            p.addRect(CGRect(x: x, y: y, width: 4, height: 1))
            x += 7
        }
        return p
    }

    static func sheet(_ c: inout GraphicsContext, scene: MPBScene, s: MPBSheet, reduce: Bool, colors: MPBColors) {
        let g = scene.g
        let win = scene.paperWin
        let px = g.px
        let pw = g.pw
        let sp = MPBGeom.sp
        let inw = g.inw
        let job = s.job
        let t = s.t
        let feed = s.feed
        let base = win - feed + s.bob
        let yt = base - job.stub

        // the paper: a ragged top edge after a tear, a straight one otherwise
        var fillCtx = c
        fillCtx.addFilter(.shadow(color: colors.ink.opacity(0.075), radius: 7, x: 0, y: -2))
        if let rg = s.rag {
            var poly = Path()
            poly.move(to: CGPoint(x: px, y: yt + rg.rel[0]))
            for i in 1..<rg.n {
                poly.addLine(to: CGPoint(x: px + CGFloat(i) * rg.step, y: yt + rg.rel[i]))
            }
            poly.addLine(to: CGPoint(x: px + pw, y: win + 2))
            poly.addLine(to: CGPoint(x: px, y: win + 2))
            poly.closeSubpath()
            fillCtx.fill(poly, with: .color(colors.paper))
        } else {
            fillCtx.fill(Path(CGRect(x: px, y: yt, width: pw, height: win - yt + 2)), with: .color(colors.paper))
        }
        let ye = s.rag != nil ? yt + 3 : yt
        c.fill(Path(CGRect(x: px, y: ye, width: 1, height: max(0, win - ye))), with: .color(colors.border))
        c.fill(Path(CGRect(x: px + pw - 1, y: ye, width: 1, height: max(0, win - ye))), with: .color(colors.border))

        // tractor margins
        var micro = Path()
        var my = win - 2
        let microMin = max(ye + 3, -6)
        while my > microMin {
            micro.addRect(CGRect(x: px + sp - 1, y: my, width: 1, height: 2))
            micro.addRect(CGRect(x: px + pw - sp, y: my, width: 1, height: 2))
            my -= 5
        }
        c.fill(micro, with: .color(colors.ink.opacity(0.08)))

        let ph: CGFloat = 12
        var off = (win - feed).truncatingRemainder(dividingBy: ph)
        if off < 0 { off += ph }
        var holes = Path()
        var hy = off - ph
        while hy < win - 3 {
            if hy >= ye + 6 {
                mpbDot(&holes, px + 11, hy, 2.7)
                mpbDot(&holes, px + pw - 11, hy, 2.7)
            }
            hy += ph
        }
        c.fill(holes, with: .color(colors.ink.opacity(0.06)))

        // the torn edge: hairline and fibres, only where the tear has passed
        if let rg = s.rag {
            let shown: (CGFloat) -> Bool = { x in
                rg.dir > 0 ? x <= px + rg.front : x >= px + pw - rg.front
            }
            var edge = Path()
            var pen = false
            for i in 0..<rg.n {
                let x = px + CGFloat(i) * rg.step
                if !shown(x) { pen = false; continue }
                let pt = CGPoint(x: x, y: yt + rg.rel[i])
                if pen { edge.addLine(to: pt) } else { edge.move(to: pt) }
                pen = true
            }
            c.stroke(edge, with: .color(colors.ink.opacity(0.28)), lineWidth: 0.8)
            fibres(&c, rg: rg, px: px, y0: yt, dirY: -1, shown: shown, offsets: nil, colors: colors)
        } else {
            c.fill(perfPath(px: px, pw: pw, y: yt + 4), with: .color(colors.ink.opacity(0.17)))
        }
        if job.perfIdx >= 0 && job.perfIdx < job.rows.count {
            let r = job.rows[job.perfIdx]
            if t >= r.fs {
                c.fill(perfPath(px: px, pw: pw, y: base + r.py + r.h + 0.5), with: .color(colors.ink.opacity(0.17)))
            }
        }

        // rows
        for r in job.rows {
            if r.tag == .tail { continue }
            if r.layers.isEmpty && !r.isLive && r.tag != .hold { continue }
            if t < r.s { continue }
            let y = base + r.py
            if y + r.h < 0 || y > win { continue }
            let rev: CGFloat
            if r.isText {
                if r.len == 0 || r.dur <= 0 { continue }
                let n: Int = reduce ? r.len : Int(mpbClamp(floor((t - r.s) * Double(r.len) / r.dur + 1e-6), 0, Double(r.len)))
                rev = n >= r.len ? inw + 1 : r.x0 + CGFloat(n) * r.cw
            } else {
                let u: Double = reduce || r.dur <= 0 ? 1 : mpbClamp((t - r.s) / r.dur, 0, 1)
                rev = u >= 1 ? inw + 1 : inw * CGFloat(u)
            }
            if rev <= 0.5 { continue }
            let fade: Double = reduce ? mpbClamp((t - r.s) / 0.2, 0, 1) : 1
            var rc = c
            rc.translateBy(x: px + sp, y: y)
            rc.opacity = fade

            switch r.tag {
            case .board:
                let e = s.now - (job.t0 + r.s)
                board(&rc, row: r, s: s, e: e, inw: inw, reduce: reduce, colors: colors)
            case .note:
                note(&rc, row: r, s: s, inw: inw, reduce: reduce, colors: colors)
            case .flap:
                let e = s.now - (job.t0 + r.s)
                flapRow(&rc, row: r, e: e, inw: inw, reduce: reduce, colors: colors)
            default:
                var lc = rc
                if r.tag == .home {
                    let lift: CGFloat = reduce ? 0 : CGFloat(4 * s.homeNudge)
                    let sc: CGFloat = reduce ? 1 : CGFloat(1 + 0.04 * s.homeNudge)
                    lc.translateBy(x: 0, y: -lift)
                    lc.translateBy(x: inw / 2, y: r.h / 2)
                    lc.scaleBy(x: sc, y: sc)
                    lc.translateBy(x: -inw / 2, y: -r.h / 2)
                    lc.opacity = fade * (reduce ? s.homePulse : 1)
                }
                if rev < inw + 1 {
                    lc.clip(to: Path(CGRect(x: -6, y: -4, width: rev + 6, height: r.h + 8)))
                }
                for layer in r.layers {
                    let tint = layer.coral ? colors.accent : colors.ink
                    let color = tint.opacity(layer.alpha)
                    if let lw = layer.stroke {
                        lc.stroke(layer.path, with: .color(color), lineWidth: lw)
                    } else {
                        lc.fill(layer.path, with: .color(color), style: FillStyle(eoFill: layer.evenOdd))
                    }
                }
                if (r.tag == .home || r.tag == .skip) && s.pressed == r.tag && rev >= inw - 1 {
                    let rr = Path(roundedRect: r.hl, cornerRadius: r.hlR)
                    lc.fill(rr, with: .color(colors.ink.opacity(0.07)))
                }
                if r.tag == .hold && rev >= inw - 1 {
                    holdLine(&rc, row: r, s: s, inw: inw, reduce: reduce, colors: colors)
                }
            }
        }
    }

    // MARK: Board

    static func flapTile(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, old: String, new: String, a: Double, P: CGFloat, bold: Bool, f: CGFloat, colors: MPBColors) {
        let cy = y + h / 2
        c.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 4 * f), with: .color(colors.ink))
        func txt(_ s: String) -> Path {
            var path = Path()
            mpbAddText(&path, s, x0: x + w / 2 - mpbStrW(s, P) / 2, y0: cy - 3.5 * P, px: P, py: P, r: P * (bold ? 0.4 : 0.38), bold: bold)
            return path
        }
        var top = c
        top.clip(to: Path(CGRect(x: x, y: y, width: w, height: h / 2)))
        top.fill(txt(new), with: .color(colors.canvas))
        var bottom = c
        bottom.clip(to: Path(CGRect(x: x, y: cy, width: w, height: h / 2)))
        bottom.fill(txt(a < 0.5 ? old : new), with: .color(colors.canvas))
        if a > 0 && a < 0.5 {
            var fl = c
            fl.clip(to: Path(CGRect(x: x, y: y, width: w, height: h / 2)))
            fl.translateBy(x: 0, y: cy)
            fl.scaleBy(x: 1, y: CGFloat(1 - 2 * a))
            fl.translateBy(x: 0, y: -cy)
            fl.fill(Path(CGRect(x: x, y: y, width: w, height: h / 2)), with: .color(colors.ink))
            fl.fill(txt(old), with: .color(colors.canvas))
        } else if a >= 0.5 && a < 1 {
            var fl = c
            fl.clip(to: Path(CGRect(x: x, y: cy, width: w, height: h / 2)))
            fl.translateBy(x: 0, y: cy)
            fl.scaleBy(x: 1, y: CGFloat(2 * a - 1))
            fl.translateBy(x: 0, y: -cy)
            fl.fill(Path(CGRect(x: x, y: cy, width: w, height: h / 2)), with: .color(colors.ink))
            fl.fill(txt(new), with: .color(colors.canvas))
        }
        c.fill(Path(CGRect(x: x + 1, y: cy - 0.5, width: w - 2, height: 1)), with: .color(colors.canvas.opacity(0.3)))
    }

    static func rndTile(_ k: Int, _ seed: Int, _ st: Int) -> String {
        let r = mpbHash(seed, st * 7 + k * 3 + 1)
        switch k {
        case 0: return "\(1 + Int(r * 12))"
        case 1: return MPBFormat.pad2(Int(r * 12) * 5)
        default: return r > 0.5 ? "pm" : "am"
        }
    }

    /// A tile as it is printed: it flips through random values, then lands.
    static func entryTile(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, k: Int, seed: Int, fin: String, P: CGFloat, e: Double, delay: Double, bold: Bool, f: CGFloat, reduce: Bool, colors: MPBColors) {
        let tau = e - delay
        let total = Double(flK + 1) * flSD
        if reduce || tau >= total {
            flapTile(&c, x: x, y: y, w: w, h: h, old: fin, new: fin, a: 1, P: P, bold: bold, f: f, colors: colors)
            return
        }
        if tau < 0 { return }
        let st = Int(floor(tau / flSD))
        let a = tau / flSD - Double(st)
        let old = st == 0 ? " " : rndTile(k, seed, st - 1)
        let new = st >= flK ? fin : rndTile(k, seed, st)
        flapTile(&c, x: x, y: y, w: w, h: h, old: old, new: new, a: a, P: P, bold: bold, f: f, colors: colors)
    }

    static func board(_ c: inout GraphicsContext, row: MPBRow, s: MPBSheet, e: Double, inw: CGFloat, reduce: Bool, colors: MPBColors) {
        let f = row.f
        let n = s.tiles.count
        let geo = mpbBoardGeo(n: n, f: f, hb: row.h, p1: row.p1, inw: inw, selA: s.selA)
        for g in geo {
            let isSel = s.sel == g.i
            let other = s.sel >= 0 && !isSel
            let ry = g.y
            if g.i > 0 {
                var xx: CGFloat = 0
                var dash = Path()
                while xx < inw {
                    dash.addRect(CGRect(x: xx, y: ry, width: 1.5 * f, height: 1))
                    xx += 4.4 * f
                }
                c.fill(dash, with: .color(colors.ink.opacity(0.2)))
            }
            // the place
            var lab = Path()
            mpbAddText(&lab, labelFor(s, g.i), x0: 0, y0: ry + (g.h - 9 * g.lp) / 2, px: g.lp, py: g.lp, r: g.lp * (other ? 0.37 : 0.4), bold: !other)
            c.fill(lab, with: .color(colors.ink.opacity(other ? 0.5 : 1)))

            let live = isSel && s.reelOn
            let strs = live ? s.reelText : s.tiles[g.i]
            let pu = reduce ? (g.i < s.pulse.count ? s.pulse[g.i] : 1) : 1
            var tc = c
            tc.opacity = c.opacity * (other ? 0.5 : 1) * pu
            for k in 0..<3 {
                let P = g.P * (k == 2 ? 0.75 : 1)
                if live && g.a > 0.9 {
                    tc.fill(Path(roundedRect: CGRect(x: g.tx[k], y: g.ty, width: g.tw[k], height: g.th), cornerRadius: 4 * f), with: .color(colors.ink))
                } else {
                    let nu: Double = (!reduce && s.sel < 0 && k == 0 && e > 1 && g.i < s.flapA.count) ? s.flapA[g.i] : 0
                    if nu > 0 {
                        flapTile(&tc, x: g.tx[k], y: g.ty, w: g.tw[k], h: g.th, old: strs[k], new: strs[k], a: nu, P: P, bold: g.a > 0.5, f: f, colors: colors)
                    } else {
                        entryTile(&tc, x: g.tx[k], y: g.ty, w: g.tw[k], h: g.th, k: k, seed: g.i * 5 + k, fin: strs[k], P: P, e: e, delay: Double(g.i * 3 + k) * 0.025, bold: g.a > 0.5, f: f, reduce: reduce, colors: colors)
                    }
                }
            }
            if live && g.a > 0.9 {
                // the centre line over the reels
                for k in 0..<3 {
                    let cy = g.ty + g.th / 2
                    tc.fill(Path(CGRect(x: g.tx[k] + 1, y: cy - 0.5, width: g.tw[k] - 2, height: 1)), with: .color(colors.canvas.opacity(0.3)))
                }
            }
            var colon = Path()
            for sgn in [-1, 1] {
                mpbDot(&colon, g.colX, g.ty + g.th / 2 + CGFloat(sgn) * g.P * 1.2, g.P * 0.5)
            }
            tc.fill(colon, with: .color(colors.ink))
        }
    }

    private static func labelFor(_ s: MPBSheet, _ i: Int) -> String {
        return i < s.labels.count ? s.labels[i] : ""
    }

    static func note(_ c: inout GraphicsContext, row: MPBRow, s: MPBSheet, inw: CGFloat, reduce: Bool, colors: MPBColors) {
        let str = s.note
        if str.isEmpty { return }
        let n = reduce ? str.count : Int(mpbClamp(floor((s.now - s.noteT) * 70), 0, Double(str.count)))
        if n <= 0 { return }
        let np = row.p
        let shown = String(str.prefix(n))
        var path = Path()
        mpbAddText(&path, shown, x0: (inw - mpbStrW(str, np)) / 2, y0: 2 * row.f, px: np, py: np, r: np * 0.37, bold: false)
        c.fill(path, with: .color(colors.ink.opacity(0.75)))
    }

    static func flapRow(_ c: inout GraphicsContext, row: MPBRow, e: Double, inw: CGFloat, reduce: Bool, colors: MPBColors) {
        let f = row.f
        let P = row.flapP
        let str = row.flapText
        let tw = 5 * P + 10 * f
        let th = 7 * P + 12 * f
        let adv = tw + 3 * f
        let w = CGFloat(str.count) * adv - 3 * f
        let total = Double(flK + 1) * flSD
        var q = 0
        for ch in str {
            let x = (inw - w) / 2 + CGFloat(q) * adv
            q += 1
            if ch == " " { continue }
            let tau = e - Double(q) * 0.04
            let fin = String(ch)
            if reduce || tau >= total {
                flapTile(&c, x: x, y: 4 * f, w: tw, h: th, old: fin, new: fin, a: 1, P: P, bold: true, f: f, colors: colors)
            } else if tau >= 0 {
                let st = Int(floor(tau / flSD))
                let a = tau / flSD - Double(st)
                func rc(_ s2: Int) -> String {
                    let code = 97 + Int(floor(mpbHash(q, s2 * 5 + 2) * 26))
                    return String(Character(UnicodeScalar(UInt8(min(122, max(97, code))))))
                }
                flapTile(&c, x: x, y: 4 * f, w: tw, h: th, old: st == 0 ? " " : rc(st - 1), new: st >= flK ? fin : rc(st), a: a, P: P, bold: true, f: f, colors: colors)
            }
        }
    }

    // MARK: Hold row

    static func holdLine(_ c: inout GraphicsContext, row: MPBRow, s: MPBSheet, inw: CGFloat, reduce: Bool, colors: MPBColors) {
        let sp = MPBGeom.sp
        let yy = row.h + 0.5
        var dash = Path()
        var xx = -sp + 4
        while xx < inw + sp - 4 {
            dash.addRect(CGRect(x: xx, y: yy - 0.5, width: 3.5, height: 1))
            xx += 7
        }
        let dashAlpha: Double = reduce ? 0.4 + 0.2 * (1 - s.holdPulse) / 0.35 : 0.4
        c.fill(dash, with: .color(colors.ink.opacity(dashAlpha)))
        let p = s.holdP
        if p <= 0.002 { return }
        let xf = -sp + CGFloat(p) * (inw + 2 * sp)
        var top = Path()
        var bot: [CGPoint] = []
        top.move(to: CGPoint(x: -sp, y: yy))
        var x = -sp
        while x <= xf {
            let j = CGFloat((mpbHash(Int(floor((Double(x) + 50) / 2.4)), 5) - 0.5) * 2.4 + sin(Double(x) * 0.13) * 0.8)
            let w = min(3, 0.3 + (xf - x) * 0.03)
            top.addLine(to: CGPoint(x: x, y: yy + j))
            bot.append(CGPoint(x: x, y: yy + j + w))
            x += 2.4
        }
        for pt in bot.reversed() { top.addLine(to: pt) }
        top.closeSubpath()
        c.fill(top, with: .color(colors.muted))
        c.stroke(top, with: .color(colors.ink.opacity(0.55)), lineWidth: 0.8)
        var fx = -sp + 3
        var fib = Path()
        while fx <= xf {
            let k = Int(floor((Double(fx) + 50) / 6.5))
            fib.move(to: CGPoint(x: fx, y: yy + 1))
            fib.addLine(to: CGPoint(x: fx + CGFloat((mpbHash(k, 3) - 0.5) * 3), y: yy + 3.5 + CGFloat(mpbHash(k, 4) * 2.5)))
            fx += 6.5
        }
        c.stroke(fib, with: .color(colors.ink.opacity(0.35)), lineWidth: 0.7)
    }

    // MARK: Fibres

    static func fibres(_ c: inout GraphicsContext, rg: MPBRag, px: CGFloat, y0: CGFloat, dirY: CGFloat, shown: (CGFloat) -> Bool, offsets: ((CGFloat) -> CGPoint)?, colors: MPBColors) {
        var light = Path()
        var dark = Path()
        for fb in rg.fib {
            let x = px + CGFloat(fb.i) * rg.step
            if !shown(x) { continue }
            let t = offsets?(x) ?? .zero
            let y = y0 + rg.rel[fb.i] + t.y
            let a = CGPoint(x: x + t.x, y: y)
            let b = CGPoint(x: x + t.x + sin(fb.ang) * fb.len, y: y + dirY * cos(fb.ang) * fb.len)
            if fb.white {
                light.move(to: a)
                light.addLine(to: b)
            } else {
                dark.move(to: a)
                dark.addLine(to: b)
            }
        }
        c.stroke(light, with: .color(colors.paper), lineWidth: 1.1)
        c.stroke(dark, with: .color(colors.ink.opacity(0.4)), lineWidth: 0.7)
    }

    // MARK: Tear

    /// The torn-off piece lifting away: strip by strip, each lifting and shearing a little differently.
    static func tear(_ c: inout GraphicsContext, scene: MPBScene, tf: MPBTearFrame, sym: GraphicsContext.ResolvedSymbol?, reduce: Bool, colors: MPBColors) {
        guard let sym else { return }
        let g = scene.g
        let rg = tf.rag
        if reduce {
            let a = 1 - mpbClamp(tf.tau / 0.22, 0, 1)
            if a <= 0 { return }
            var cc = c
            cc.opacity = a
            cc.translateBy(x: 0, y: scene.groupTop)
            cc.clip(to: Path(CGRect(x: -400, y: -4000, width: g.w + 800, height: tf.perfY + 4000)))
            cc.draw(sym, at: .zero, anchor: .topLeading)
            return
        }
        let after = max(0, tf.tau - tearT)
        if after > 0.8 { return }
        let px = g.px
        let pw = g.pw
        let dir = rg.dir
        let e2 = mpbSmooth(after / 0.75)
        let alpha = 1 - mpbSmooth((after - 0.42) / 0.34)
        let pvx = dir > 0 ? px : px + pw
        let perfY = tf.perfY
        let yTop = tf.yTop
        let n = rg.n - 1
        if n < 1 { return }

        var cc = c
        cc.opacity = alpha
        cc.translateBy(x: 0, y: scene.groupTop)
        if after > 0 {
            cc.translateBy(x: pvx, y: perfY)
            cc.translateBy(x: -dir * 30 * CGFloat(e2), y: -215 * CGFloat(e2) - 20 * CGFloat(after))
            cc.rotate(by: .radians(Double(-dir) * 0.34 * e2))
            cc.translateBy(x: -pvx, y: -perfY)
        }

        var lift = [CGFloat](repeating: 0, count: n)
        var shx = [CGFloat](repeating: 0, count: n)
        let prog = min(1, tf.tau / tearT)
        for k in 0..<n {
            let xm = px + (CGFloat(k) + 0.5) * rg.step
            let ds = dir > 0 ? xm - px : px + pw - xm
            let tl = rg.front - ds
            let L: CGFloat = tl > 0 ? min(60, (0.085 * tl + 0.0004 * tl * tl) * CGFloat(0.35 + 0.65 * prog)) : 0
            lift[k] = L
            shx[k] = -dir * L * 0.1
        }

        // soft shadow of the lifting piece
        var sh = cc
        sh.addFilter(.shadow(color: colors.ink.opacity(0.2), radius: CGFloat(6 + e2 * 5), x: 0, y: CGFloat(5 + e2 * 16)))
        var sil = Path()
        sil.move(to: CGPoint(x: px + shx[0], y: perfY + rg.rel[0] - lift[0]))
        for k in 0..<n {
            sil.addLine(to: CGPoint(x: px + CGFloat(k + 1) * rg.step + shx[k], y: perfY + rg.rel[k + 1] - lift[k]))
        }
        for k in stride(from: n - 1, through: 0, by: -1) {
            sil.addLine(to: CGPoint(x: px + CGFloat(k) * rg.step + shx[k], y: yTop - lift[k]))
        }
        sil.closeSubpath()
        sh.fill(sil, with: .color(colors.paper))

        // shadow on the stub where the piece is lifted
        for k in 0..<n where lift[k] > 1 {
            let x = px + CGFloat(k) * rg.step
            var q = Path()
            q.move(to: CGPoint(x: x, y: perfY + rg.rel[k]))
            q.addLine(to: CGPoint(x: x + rg.step + 0.4, y: perfY + rg.rel[k + 1]))
            q.addLine(to: CGPoint(x: x + rg.step + 0.4, y: perfY + rg.rel[k + 1] + 5))
            q.addLine(to: CGPoint(x: x, y: perfY + rg.rel[k] + 5))
            q.closeSubpath()
            cc.fill(q, with: .color(colors.ink.opacity(0.07 * Double(min(1, lift[k] / 10)))))
        }

        // the piece, in strips of three so each can lift and shear on its own
        var k0 = 0
        while k0 < n {
            let k1 = min(n, k0 + 3)
            let km = min(n - 1, (k0 + k1) / 2)
            let x = px + CGFloat(k0) * rg.step
            let w = CGFloat(k1 - k0) * rg.step + 0.6
            var sc = cc
            sc.translateBy(x: shx[km], y: -lift[km])
            var clip = Path()
            clip.move(to: CGPoint(x: x, y: -80))
            clip.addLine(to: CGPoint(x: x + w, y: -80))
            clip.addLine(to: CGPoint(x: x + w, y: perfY + rg.rel[k1] + 0.3))
            clip.addLine(to: CGPoint(x: x, y: perfY + rg.rel[k0] + 0.3))
            clip.closeSubpath()
            sc.clip(to: clip)
            sc.draw(sym, at: .zero, anchor: .topLeading)
            k0 = k1
        }

        // torn edge: lighter fringe, darker hairline, fibres
        let shown: (CGFloat) -> Bool = { x in
            let ds = dir > 0 ? x - px : px + pw - x
            return rg.front - ds > 0
        }
        let offs: (CGFloat) -> CGPoint = { x in
            let k = Int(mpbClamp(floor(Double((x - px) / rg.step)), 0, Double(n - 1)))
            return CGPoint(x: shx[k], y: -lift[k])
        }
        var edge = Path()
        var pen = false
        for i in 0..<rg.n {
            let x = px + CGFloat(i) * rg.step
            if !shown(x) { pen = false; continue }
            let t = offs(x)
            let pt = CGPoint(x: x + t.x, y: perfY + rg.rel[i] + t.y)
            if pen { edge.addLine(to: pt) } else { edge.move(to: pt) }
            pen = true
        }
        cc.stroke(edge, with: .color(colors.paper.opacity(0.95)), lineWidth: 3)
        cc.stroke(edge, with: .color(colors.ink.opacity(0.5)), lineWidth: 0.9)
        fibres(&cc, rg: rg, px: px, y0: perfY, dirY: 1, shown: shown, offsets: offs, colors: colors)
    }

    // MARK: Machine

    static func machine(_ c: inout GraphicsContext, scene: MPBScene, fr: MPBFrame, reduce: Bool, colors: MPBColors) {
        let g = scene.g
        let sy = scene.paperWin

        for layer in scene.body {
            c.fill(layer.path, with: .color(colors.ink.opacity(layer.alpha)))
        }
        for rect in scene.coverRects {
            c.fill(Path(rect), with: .color(colors.canvas))
        }
        c.fill(scene.coverDots, with: .color(colors.ink.opacity(0.3)))

        // knobs turn with the paper feed
        let ang: CGFloat = reduce ? 0 : (fr.knobBase + fr.sheet.feed) * 0.065
        let ky = sy + 10 + (g.bodyH - 10) / 2
        let knobR = min(12, g.bodyH * 0.2)
        knob(&c, cx: g.bx0 + 28, cy: ky, ang: ang, radius: knobR, colors: colors)
        knob(&c, cx: g.bx1 - 28, cy: ky, ang: ang, radius: knobR, colors: colors)

        // carriage on the print head
        let cx = g.px + MPBGeom.sp + fr.carriage
        let cw: CGFloat = 18
        let ch: CGFloat = 13
        let cy = sy - 6
        c.fill(Path(roundedRect: CGRect(x: cx - 3, y: cy, width: cw, height: ch), cornerRadius: 3), with: .color(colors.canvas))
        c.stroke(
            Path(roundedRect: CGRect(x: cx - 3 + 0.5, y: cy + 0.5, width: cw - 1, height: ch - 1), cornerRadius: 3),
            with: .color(colors.ink.opacity(0.34)),
            lineWidth: 1
        )
        var head = Path()
        for j in 0..<3 {
            for i in 0..<5 {
                mpbDot(&head, cx - 3 + 2.7 + CGFloat(i) * 2.8 + 1.0, cy + 2.8 + CGFloat(j) * 3.1, 0.95)
            }
        }
        c.fill(head, with: .color(colors.ink.opacity(0.88)))
        c.fill(Path(CGRect(x: cx - 3 + 1.5, y: cy + ch - 3, width: 3, height: 3)), with: .color(colors.ink))

        // keys
        for (i, k) in scene.keys.enumerated() {
            let dep = (!reduce && i < fr.keyDepth.count) ? fr.keyDepth[i] : 0
            let d = CGFloat(dep) * 2
            let cap = CGRect(x: k.x, y: k.y + d, width: k.w, height: k.h - 2)
            let down = d > 0.2
            c.fill(
                Path(roundedRect: cap, cornerRadius: 4),
                with: .color(down ? colors.ink.opacity(0.04 + 0.06 * dep) : colors.canvas)
            )
            c.stroke(
                Path(roundedRect: CGRect(x: k.x + 0.5, y: k.y + d + 0.5, width: k.w - 1, height: k.h - 3), cornerRadius: 4),
                with: .color(down ? colors.ink.opacity(0.16 + 0.12 * dep) : colors.ink.opacity(0.15)),
                lineWidth: 1
            )
            if d < 1.2 {
                c.fill(Path(CGRect(x: k.x + 3, y: k.y + k.h - 2 + d, width: k.w - 6, height: 1)), with: .color(colors.ink.opacity(0.09)))
            }
            var dot = Path()
            mpbDot(&dot, k.x + k.w / 2, k.y + d + (k.h - 2) / 2, 1.1)
            c.fill(dot, with: .color(colors.ink.opacity(0.12 + 0.12 * dep)))
        }
    }

    /// A ring of 16 dots with a bright arc; it turns with the paper feed.
    static func knob(_ c: inout GraphicsContext, cx: CGFloat, cy: CGFloat, ang: CGFloat, radius: CGFloat, colors: MPBColors) {
        let n = 16
        var dim = Path()
        var bright = Path()
        let pos = Double(ang) / (2 * Double.pi / Double(n))
        for k in 0..<n {
            let a = Double(k) / Double(n) * 2 * Double.pi - Double.pi / 2
            let x = cx + CGFloat(cos(a)) * radius
            let y = cy + CGFloat(sin(a)) * radius
            var d = (Double(k) - pos).truncatingRemainder(dividingBy: Double(n))
            if d < 0 { d += Double(n) }
            d = floor(d)
            if d < 4 {
                mpbDot(&bright, x, y, 1.35 - CGFloat(d) * 0.12)
            } else {
                mpbDot(&dim, x, y, 1.05)
            }
        }
        mpbDot(&dim, cx, cy, 1.5)
        let spokeAngle = floor(pos) / Double(n) * 2 * Double.pi - Double.pi / 2
        for q in 1...2 {
            let rr = CGFloat(q) * radius * 0.33
            mpbDot(&dim, cx + CGFloat(cos(spokeAngle)) * rr, cy + CGFloat(sin(spokeAngle)) * rr, 0.9)
        }
        c.fill(dim, with: .color(colors.ink.opacity(0.26)))
        c.fill(bright, with: .color(colors.ink.opacity(0.75)))
    }
}

// MARK: - The engine

private nonisolated struct MPBTearState {
    var t0: Double
    var perfY: CGFloat
    var yTop: CGFloat
    var rag: MPBRag
    var frozen: MPBSheet
}

@MainActor
private final class MPBEngine {
    enum Mode { case menu, done, closing }

    // set up once
    private var prepared = false
    private var size: CGSize = .zero
    private var base: Double = 0
    private var lastNow: Double = 0
    private var data: CantTodayData?
    private var haptics: PauseHaptics?
    private var nudger: CantTodayNudger?
    private var reduce = false
    private var content = MPBContent.empty
    private var scene: MPBScene?
    private var layoutInfo: MPBMenu?

    // the paper
    private var job = MPBJob.empty
    private var jobSerial = 0
    private var rag: MPBRag?
    private var tear: MPBTearState?
    private var knobBase: CGFloat = 0
    private var lastFeed: CGFloat = 0
    private var lastBob: CGFloat = 0
    private var hapN = 0

    // interaction
    private(set) var now: Double = 0
    private var mode: Mode = .menu
    private var sel = -1
    private var selA: [Double] = []
    var reel: [Int] = [0, 0, 0]
    var drumTouch: [Bool] = [false, false, false]
    private var note = ""
    private var noteT: Double = 0
    private var printed = 0
    private var bumpT: Double = -9
    private var pressedTag: MPBTag?
    private var holdMark = 0
    private var holdActive = false
    private var presses: [(key: Int, t: Double)] = []
    private var confirmDay = ""
    private var confirmTime = ""

    // nudges
    private var nudgeIDs: [String] = []
    private var menuSettled = false
    private var reelSettled = false

    private let tearT = MPBDraw.tearT

    // MARK: Setup

    private func prepare(_ input: CantTodayInput, date: Date) {
        let sz = input.layout.size
        if prepared && sz == size { return }
        let first = !prepared
        prepared = true
        size = sz
        if first { base = date.timeIntervalSinceReferenceDate }
        let n = date.timeIntervalSinceReferenceDate - base
        now = n
        data = input.data
        haptics = input.haptics
        reduce = input.reduceMotion
        if nudger == nil {
            nudger = CantTodayNudger(haptics: input.haptics, reduceMotion: input.reduceMotion)
        }

        let d = input.data
        var doors: [MPBDoor] = []
        for door in d.order {
            switch door {
            case .reschedule: doors.append(.reschedule)
            case .home: doors.append(.home)
            case .skip: doors.append(.skip)
            }
        }
        var targets: [MPBContent.Target] = []
        for t in d.targets {
            let ix = MPBFormat.indices(t.defaultMinutes)
            targets.append(MPBContent.Target(
                short: t.short,
                name: t.name,
                defaultMin: t.defaultMinutes,
                tiles: [MPBFormat.reel(0, ix.h), MPBFormat.reel(1, ix.m), MPBFormat.reel(2, ix.a)]
            ))
        }
        var cost: [MPBContent.Cost] = []
        for q in d.cost {
            let kind: MPBCostKind
            switch q.kind {
            case .week: kind = .week
            case .row: kind = .row
            case .streak: kind = .streak
            }
            cost.append(MPBContent.Cost(kind: kind, big: q.big, hot: q.hot))
        }
        content = MPBContent(
            heading: d.heading,
            doors: doors,
            targets: targets,
            cost: cost,
            homeMinutes: d.homeMinutes,
            homeLeft: d.homeLeft,
            homeOf: d.homeOf,
            skipNeedsHold: d.skipNeedsHold
        )

        let layout = input.layout
        let g = MPBGeom(
            width: sz.width,
            height: sz.height,
            contentTop: layout.contentTop,
            contentBottom: layout.contentBottom - (56 + 14)
        )
        let provisional = MPBBuild.scene(g: g, p1: 3)
        let menu = MPBBuild.fitMenu(content, inw: g.inw, maxH: provisional.paperWin - 30)
        scene = MPBBuild.scene(g: g, p1: menu.p1)
        layoutInfo = menu

        var rows = menu.rows
        MPBBuild.schedule(&rows, from: 0, s0: 0.35)
        job = MPBJob(rows: rows, total: menu.total, stub: 22 * menu.f, adv: MPBBuild.adv, perfIdx: menu.holdIdx, t0: n, bobAfter: nil)
        rag = nil
        tear = nil
        jobSerial += 1
        hapN = 0
        mode = .menu
        sel = -1
        selA = [Double](repeating: 0, count: content.targets.count)
        menuSettled = false
        reelSettled = false
        nudgeIDs = []
        note = ""

        if input.startsOnReschedule && !content.targets.isEmpty {
            // straight onto the reel, no intro: everything is already printed
            job.t0 = n - 1000
            let want = d.targets.firstIndex(where: { $0.isToday }) ?? 0
            selectRow(want, instant: true)
        }
    }

    // MARK: Allowed

    private func allowedMinutes(_ target: Int, _ minutes: Int) -> Bool {
        guard let data, target >= 0, target < data.targets.count else { return false }
        return data.allowed(data.targets[target], minutes: minutes).isOK
    }

    private func blockedWhy(_ target: Int, _ minutes: Int) -> String {
        guard let data, target >= 0, target < data.targets.count else { return "" }
        switch data.allowed(data.targets[target], minutes: minutes) {
        case .ok: return ""
        case .blocked(let why): return why
        }
    }

    private func nearestOK(_ target: Int, _ minutes: Int) -> Int {
        var d = 0
        while d <= 720 {
            for sgn in [1, -1] {
                let m = (((minutes + sgn * d) % 1440) + 1440) % 1440
                if allowedMinutes(target, m) { return m }
            }
            d += 5
        }
        return minutes
    }

    private var readMinutes: Int {
        MPBFormat.minutes(h: reel[0], m: reel[1], a: reel[2])
    }

    func cellAllowed(_ k: Int, _ idx: Int) -> Bool {
        if sel < 0 { return true }
        var r = reel
        r[k] = idx
        return allowedMinutes(sel, MPBFormat.minutes(h: r[0], m: r[1], a: r[2]))
    }

    func cellBlocked(_ k: Int, _ idx: Int) {
        if sel < 0 { return }
        var r = reel
        r[k] = idx
        note = blockedWhy(sel, MPBFormat.minutes(h: r[0], m: r[1], a: r[2]))
        noteT = now
    }

    /// VoiceOver: move a reel one value, skipping values that are not allowed.
    func step(_ k: Int, _ delta: Int) {
        let count = k == 2 ? 2 : 12
        var idx = reel[k]
        for _ in 0..<count {
            idx += delta
            if k < 2 {
                idx = ((idx % count) + count) % count
            } else if idx < 0 || idx >= count {
                return
            }
            if cellAllowed(k, idx) {
                reel[k] = idx
                printed = readMinutes
                return
            }
        }
    }

    // MARK: Touch

    func userSelectRow(_ i: Int) {
        guard mode == .menu else { return }
        nudger?.touched(kind: "tile")
        nudger?.cancel()
        selectRow(i, instant: false)
        nudger?.rest(at: now)
    }

    private func selectRow(_ i: Int, instant: Bool) {
        guard i >= 0, i < content.targets.count, i != sel else { return }
        if !instant { haptics?.play(.rigid) }
        pressRand(5)
        bumpT = now
        sel = i
        note = ""
        var m = content.targets[i].defaultMin
        if !allowedMinutes(i, m) { m = nearestOK(i, m) }
        let ix = MPBFormat.indices(m)
        reel = [ix.h, ix.m, ix.a]
        printed = m
        if instant {
            for j in selA.indices { selA[j] = j == i ? 1 : 0 }
        }
        nudger?.cancel()
        nudger?.setItems(["reel0", "reel1", "reel2"], kinds: ["reel0": "reel", "reel1": "reel", "reel2": "reel"])
        nudgeIDs = ["reel0", "reel1", "reel2"]
        reelSettled = false
    }

    func setDrumTouch(_ k: Int, _ on: Bool) {
        guard k >= 0 && k < 3 else { return }
        let was = drumTouch.contains(true)
        drumTouch[k] = on
        let isNow = drumTouch.contains(true)
        if isNow && !was {
            note = ""
            nudger?.touched(kind: "reel")
            nudger?.cancel()
        } else if !isNow && was {
            let m = readMinutes
            if sel >= 0 && allowedMinutes(sel, m) && m != printed {
                printed = m
                bumpT = now
                pressRand(3)
            }
            nudger?.rest(at: now)
        }
    }

    func pressBegan(_ door: MPBDoor) {
        pressedTag = (door == .home) ? MPBTag.home : MPBTag.skip
        nudger?.touched(kind: "chip")
        nudger?.cancel()
    }

    func pressEnded() {
        pressedTag = nil
        nudger?.rest(at: now)
    }

    func holdBegan() {
        holdActive = true
        nudger?.touched(kind: "hold")
        nudger?.cancel()
    }

    func holdEnded() {
        holdActive = false
        nudger?.rest(at: now)
    }

    func closing() {
        mode = .closing
        nudger?.cancel()
    }

    private func pressRand(_ n: Int) {
        guard !reduce, let sc = scene, !sc.pool.isEmpty else { return }
        for i in 0..<n {
            let key = sc.pool[Int(mpbHash(i + Int(now * 50), 17) * Double(sc.pool.count)) % sc.pool.count]
            presses.append((key, now + Double(i) * 0.03))
        }
    }

    // MARK: Commit

    func canTake(_ kind: MPBConfirm) -> Bool {
        guard mode == .menu else { return false }
        switch kind {
        case .home: return content.homeMinutes != nil
        case .skip: return !content.skipNeedsHold
        case .alarm: return alarmChoice() != nil
        }
    }

    /// The day and time of the open row, only when the real rule says the time is ok.
    func alarmChoice() -> (day: Date, time: TimeOfDay)? {
        guard mode == .menu, sel >= 0, let data, sel < data.targets.count else { return nil }
        if drumTouch.contains(true) { return nil }
        let m = readMinutes
        if !allowedMinutes(sel, m) { return nil }
        return (data.targets[sel].day, CantTodayClock.timeOfDay(m))
    }

    /// Prints the confirm slip onto the same paper: the old slip feeds out, the new one prints.
    func commit(_ kind: MPBConfirm) {
        guard let sc = scene, mode == .menu else { return }
        if kind == .alarm, sel >= 0 {
            confirmDay = content.targets[sel].short
            confirmTime = CantTodayClock.text(readMinutes)
        }
        mode = .done
        nudger?.cancel()
        nudgeIDs = []
        pressedTag = nil
        pressRand(kind == .alarm ? 5 : 4)
        bumpT = now
        let inw = sc.g.inw
        let fit = MPBBuild.fitConfirm(kind, day: confirmDay, time: confirmTime, homeMinutes: content.homeMinutes ?? 0, inw: inw, maxH: sc.paperWin - 30)
        var rows: [MPBRow] = [MPBBuild.feedOutRow(paperWin: sc.paperWin)]
        rows.append(contentsOf: fit.rows)
        let from = job.rows.count
        job.rows.append(contentsOf: rows)
        let total = MPBBuild.layOut(&job.rows, from: from, startY: job.total)
        job.total = total
        MPBBuild.schedule(&job.rows, from: from, s0: max(0, now - job.t0))
        job.perfIdx = -1
    }

    /// The hold finished: tear the slip along the perforation and feed the "skipped" slip.
    func finishHold(holdProgress: Double) {
        guard let sc = scene, mode == .menu else { return }
        mode = .done
        nudger?.cancel()
        nudgeIDs = []
        holdActive = false
        let g = sc.g
        let win = sc.paperWin
        // where the perforation is, on the paper as last drawn
        var perfY = win
        if job.perfIdx >= 0 && job.perfIdx < job.rows.count {
            let r = job.rows[job.perfIdx]
            perfY = win - lastFeed + lastBob + r.py + r.h + 0.5
        }
        let yt = win - lastFeed - job.stub + lastBob
        var frozen = sheetState(t: now - job.t0, hold: max(0.98, holdProgress), nudge: [:])
        frozen.holdP = max(0.98, holdProgress)
        let stubH = max(10, win - perfY)

        let newRag = MPBRag.make(seed: 5, pw: g.pw, dir: 1)
        var rg = newRag
        rg.front = g.pw + 1
        tear = MPBTearState(t0: now - tearT, perfY: perfY, yTop: max(-30, yt), rag: rg, frozen: frozen)
        rag = rg

        let fit = MPBBuild.fitConfirm(.skip, day: "", time: "", homeMinutes: 0, inw: g.inw, maxH: win - 30)
        var rows = fit.rows
        MPBBuild.layOut(&rows)
        var total: CGFloat = 0
        for r in rows { total += r.h }
        MPBBuild.schedule(&rows, from: 0, s0: tearT + 0.06)
        knobBase += lastFeed
        job = MPBJob(rows: rows, total: total, stub: stubH, adv: MPBBuild.adv, perfIdx: -1, t0: tear?.t0 ?? now, bobAfter: tearT)
        jobSerial += 1
        hapN = 0
    }

    // MARK: Frame

    func frame(input: CantTodayInput, date: Date, holdProgress: Double) -> MPBFrame {
        prepare(input, date: date)
        let sc = scene!
        now = date.timeIntervalSinceReferenceDate - base
        let dt = min(0.05, max(0.001, now - lastNow))
        lastNow = now
        let win = sc.paperWin

        // rows open and close
        for i in selA.indices {
            let to: Double = sel == i ? 1 : 0
            var v = selA[i]
            if reduce { v = to } else { v += (to - v) * (1 - exp(-dt * 13)) }
            if abs(to - v) < 0.002 { v = to }
            selA[i] = v
        }

        // the tear runs, then the piece flies off
        var tearFrame: MPBTearFrame?
        if var tr = tear {
            let tau = now - tr.t0
            var done = false
            if reduce {
                if tau >= 0.22 { done = true }
            } else {
                let after = max(0, tau - tearT)
                let pw = sc.g.pw
                tr.rag.front = tau < tearT ? CGFloat(pow(tau / tearT, 1.5)) * pw : pw + CGFloat(after) * pw * 2.2
                if tau < tearT { haptics?.play(.light) }
                if after > 0.8 { done = true }
            }
            if done {
                tear = nil
                rag?.front = sc.g.pw + 9999
            } else {
                rag?.front = reduce ? sc.g.pw + 999 : tr.rag.front
                tear = tr
                tearFrame = MPBTearFrame(tau: tau, perfY: tr.perfY, yTop: tr.yTop, rag: tr.rag, frozen: tr.frozen)
            }
        }

        // hold: ticks as it fills
        if mode == .menu && holdProgress > 0.002 {
            let mark = Int(holdProgress * 4)
            if mark > holdMark && holdProgress < 1 {
                holdMark = mark
                haptics?.play(.light)
            }
        } else if holdProgress <= 0.002 {
            holdMark = 0
        }

        let t = now - job.t0
        let feed = job.feed(at: t, reduce: reduce)
        var bob: CGFloat = 0
        if !reduce, let ba = job.bobAfter {
            let a = t - ba
            if a >= 0 { bob += CGFloat(3.4 * exp(-11 * a) * sin(a * 2 * Double.pi * 3.2)) }
        }
        let bumpAge = now - bumpT
        if !reduce && bumpAge >= 0 && bumpAge < 0.4 {
            bob += CGFloat(2.2 * exp(-13 * bumpAge) * sin(bumpAge * 2 * Double.pi * 3.4))
        }
        lastFeed = feed
        lastBob = bob

        printingHaptics(t: t)

        // nudges
        let nudgeAmounts = updateNudges(t: t)

        // the sheet
        var sheet = sheetState(t: t, hold: holdProgress, nudge: nudgeAmounts)
        sheet.feed = feed
        sheet.bob = bob

        // carriage and keys
        let carriage = job.carriageX(at: t, reduce: reduce, inw: sc.g.inw)
        var depths = [Double](repeating: 0, count: sc.keys.count)
        if !reduce {
            depths = job.keyDepths(at: t, keyCount: sc.keys.count, pool: sc.pool, space: sc.space)
            presses.removeAll(where: { now - $0.t > 0.2 })
            for p in presses where p.key < depths.count {
                depths[p.key] = max(depths[p.key], MPBJob.keyShape(now - p.t))
            }
        }

        // hit areas
        var hits: [MPBHit] = []
        var drums: [MPBDrumRect] = []
        if mode == .menu, let menu = layoutInfo {
            let px = sc.g.px
            let pw = sc.g.pw
            let sp = MPBGeom.sp
            let gt = sc.groupTop
            func top(_ r: MPBRow) -> CGFloat { win - feed + bob + r.py + gt }
            func ready(_ r: MPBRow) -> Bool { r.s.isFinite && t >= r.e }

            if menu.boardIdx >= 0, menu.boardIdx < job.rows.count, ready(job.rows[menu.boardIdx]) {
                let br = job.rows[menu.boardIdx]
                let bt = top(br)
                let geo = mpbBoardGeo(n: content.targets.count, f: menu.f, hb: br.h, p1: menu.p1, inw: sc.g.inw, selA: selA)
                for gg in geo {
                    if gg.i != sel {
                        hits.append(MPBHit(
                            id: "row\(gg.i)", kind: .row, index: gg.i,
                            rect: CGRect(x: px, y: bt + gg.y, width: pw, height: gg.h),
                            label: "reschedule, \(content.targets[gg.i].name), \(content.targets[gg.i].tiles[0]):\(content.targets[gg.i].tiles[1]) \(content.targets[gg.i].tiles[2])"
                        ))
                    }
                }
                if sel >= 0, sel < geo.count, geo[sel].a > 0.9 {
                    let gg = geo[sel]
                    for k in 0..<3 {
                        drums.append(MPBDrumRect(
                            k: k,
                            rect: CGRect(x: px + sp + gg.tx[k] + 1, y: bt + gg.ty + 1, width: gg.tw[k] - 2, height: gg.th - 2)
                        ))
                    }
                }
            }
            for (idx, tag) in [(menu.homeIdx, MPBTag.home), (menu.skipIdx, MPBTag.skip)] {
                if idx >= 0, idx < job.rows.count, ready(job.rows[idx]) {
                    let r = job.rows[idx]
                    let pad = max(0, (44 - r.hl.height) / 2)
                    let rt = top(r)
                    let label = tag == .home ? "home workout, \(content.homeMinutes ?? 0) minutes" : "skip today"
                    hits.append(MPBHit(
                        id: tag == .home ? "home" : "skip",
                        kind: tag == .home ? .home : .skip,
                        index: 0,
                        rect: CGRect(x: px + 6, y: rt + r.hl.minY - pad, width: pw - 12, height: r.hl.height + 2 * pad),
                        label: label
                    ))
                }
            }
            if menu.holdIdx >= 0, menu.holdIdx < job.rows.count, ready(job.rows[menu.holdIdx]) {
                let r = job.rows[menu.holdIdx]
                let rt = top(r)
                hits.append(MPBHit(
                    id: "hold", kind: .hold, index: 0,
                    rect: CGRect(x: px, y: rt - 10 * menu.f, width: pw, height: r.h + 26 * menu.f),
                    label: "hold to skip"
                ))
            }
        }

        // reels
        var peek = [Double](repeating: 0, count: 3)
        var reelPulse = 1.0
        for k in 0..<3 {
            let a = nudgeAmounts["reel\(k)"] ?? 0
            if reduce {
                reelPulse = min(reelPulse, 1 - 0.35 * min(1, a))
            } else {
                peek[k] = 0.6 * a
            }
        }
        let reelValue = [MPBFormat.reel(0, reel[0]), MPBFormat.reel(1, reel[1]), MPBFormat.reel(2, reel[2])]

        // "set alarm"
        let goVisible = mode == .menu && sel >= 0
        let goEnabled = goVisible && !drumTouch.contains(true) && allowedMinutes(sel, readMinutes)

        return MPBFrame(
            scene: sc,
            sheet: sheet,
            keyDepth: depths,
            carriage: carriage,
            knobBase: knobBase,
            tear: tearFrame,
            hits: hits,
            drums: drums,
            peek: peek,
            reelValue: reelValue,
            reelPulse: reelPulse,
            goVisible: goVisible,
            goEnabled: goEnabled,
            accessibleHeading: mode == .menu
        )
    }

    private func sheetState(t: Double, hold: Double, nudge: [String: Double]) -> MPBSheet {
        var flapA = [Double](repeating: 0, count: content.targets.count)
        var pulse = [Double](repeating: 1, count: content.targets.count)
        for i in content.targets.indices {
            let a = nudge["row\(i)"] ?? 0
            if reduce {
                pulse[i] = 1 - 0.35 * min(1, a)
            } else {
                flapA[i] = min(1, a) * 0.5
            }
        }
        let homeA = nudge["home"] ?? 0
        let holdA = nudge["hold"] ?? 0
        var s = MPBSheet(
            job: job,
            t: t,
            now: now,
            feed: lastFeed,
            bob: lastBob,
            rag: rag,
            sel: sel,
            selA: selA,
            reelOn: sel >= 0,
            reelText: [MPBFormat.reel(0, reel[0]), MPBFormat.reel(1, reel[1]), MPBFormat.reel(2, reel[2])],
            tiles: content.targets.map { $0.tiles },
            flapA: flapA,
            pulse: pulse,
            note: note,
            noteT: noteT,
            holdP: 0,
            holdPulse: reduce ? 1 - 0.35 * min(1, holdA) : 1,
            homeNudge: homeA,
            homePulse: reduce ? 1 - 0.35 * min(1, homeA) : 1,
            pressed: pressedTag
        )
        s.labels = content.targets.map { $0.short }
        if mode == .menu {
            s.holdP = min(1, hold + (reduce ? 0 : 0.25 * holdA))
        } else {
            s.holdP = hold
        }
        return s
    }

    // MARK: Haptics while printing

    private func printingHaptics(t: Double) {
        guard let haptics else { return }
        var total = 0
        for (i, r) in job.rows.enumerated() {
            if !r.s.isFinite || t < r.s { continue }
            if r.isText {
                let n = reduce ? r.len : Int(mpbClamp(floor((t - r.s) * Double(r.len) / max(0.001, r.dur) + 1e-6), 0, Double(r.len)))
                total += n
            } else if r.tag == .flap || r.tag == .board {
                let e = now - (job.t0 + r.s)
                let span = r.tag == .flap ? 0.3 + Double(r.flapText.count) * 0.04 : 0.28 + Double(content.targets.count * 3) * 0.025
                if e >= 0 && e < span && !reduce { haptics.play(.light) }
            } else if r.tag != .tail && r.tag != .note && !r.layers.isEmpty {
                if t >= r.e && t - r.e < 0.3 { haptics.cue("mpb-\(jobSerial)-\(i)", .soft) }
            }
        }
        if total - hapN >= 3 {
            if total - hapN <= 8 { haptics.play(.light) }
            hapN = total
        }
    }

    // MARK: Nudges

    /// Runs the shared "touch me" wave and returns each item's envelope.
    private func updateNudges(t: Double) -> [String: Double] {
        guard let nudger else { return [:] }
        if mode != .menu {
            return [:]
        }
        // the menu has settled: set the wave's items, top to bottom, then start it
        if sel < 0 && !menuSettled, let menu = layoutInfo {
            let rows = job.rows
            func ready(_ i: Int) -> Bool { i >= 0 && i < rows.count && rows[i].s.isFinite && t >= rows[i].e }
            let boardOK = menu.boardIdx < 0 || (ready(menu.boardIdx) && t >= rows[menu.boardIdx].s + 1.0)
            let homeOK = menu.homeIdx < 0 || ready(menu.homeIdx)
            let holdOK = menu.holdIdx < 0 || ready(menu.holdIdx)
            let anyDoor = menu.boardIdx >= 0 || menu.homeIdx >= 0 || menu.holdIdx >= 0
            if boardOK && homeOK && holdOK && anyDoor {
                menuSettled = true
                var ids: [String] = []
                var kinds: [String: String] = [:]
                for door in content.doors {
                    switch door {
                    case .reschedule:
                        for i in content.targets.indices {
                            ids.append("row\(i)")
                            kinds["row\(i)"] = "tile"
                        }
                    case .home:
                        if menu.homeIdx >= 0 {
                            ids.append("home")
                            kinds["home"] = "chip"
                        }
                    case .skip:
                        break
                    }
                }
                if menu.holdIdx >= 0 {
                    ids.append("hold")
                    kinds["hold"] = "hold"
                }
                nudger.setItems(ids, kinds: kinds)
                nudgeIDs = ids
                nudger.settle(at: now)
            }
        }
        // an opened row: the reels have settled
        if sel >= 0 && !reelSettled && sel < selA.count && selA[sel] >= 0.98 {
            reelSettled = true
            nudger.settle(at: now)
        }
        var out: [String: Double] = [:]
        for id in nudgeIDs {
            out[id] = nudger.amount(id, at: now)
        }
        return out
    }
}
