//
//  MatrixPrinterPauseStage.swift
//  GymLock · the "plans changed" pause · Matrix printer look
//
//  Port of the approved prototype (docs/prototypes: v-mprinter.html). A dot-matrix receipt printer
//  prints the stakes for 30 seconds (the receipt: title, week strip, the 66 visits, the user's own
//  words, if you go / if you skip, one fact, a barcode), then the receipt tears off at the
//  perforation and each door prints as its own ticket.
//
//  Everything is a pure function of `input.t` and `input.phase`: row times are solved once per
//  layout (the prototype's pacing solver), and each frame only looks up where the paper, the
//  carriage, the knobs and the keys are at that moment. The only state is a small cache of the
//  built timelines, keyed by screen size and script.
//
//  Drawing: two Canvases in group space (paper window, then machine). The paper is masked at the
//  top so it fades out under the header. The group (paper window + printer + keys) is centred
//  between `contentTop` and `contentBottom`; the receipt text scales down (to 0.76) when the
//  screen is short.
//

import SwiftUI

// MARK: - View

struct MatrixPrinterPauseStage: View {
    let input: PauseStageInput

    /// Built timelines; never drives a redraw.
    @State private var cache = MPPCache()

    var body: some View {
        content()
    }

    private func content() -> some View {
        let scene = cache.scene(for: input)
        let frame = cache.frame(scene: scene, input: input)
        cache.fireHaptics(frame, input.haptics)
        let reduce = input.reduceMotion
        let colors = MPPColors(
            ink: Theme.ink,
            paper: Theme.surface,
            canvas: Theme.canvas,
            border: Theme.border,
            accent: Theme.accent
        )
        let width = input.layout.size.width
        let height = input.layout.size.height
        let paperWin = scene.paperWin
        let groupH = scene.groupH
        let groupTop = scene.groupTop

        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                MPPDraw.paper(&context, scene: scene, frame: frame, reduce: reduce, colors: colors)
            }
            .frame(width: width, height: paperWin)
            .clipped()
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(30, paperWin))
                    Rectangle().fill(Color.black)
                }
            }
            .offset(y: groupTop)
            .accessibilityHidden(true)

            Canvas { context, _ in
                MPPDraw.machine(&context, scene: scene, frame: frame, reduce: reduce, colors: colors)
            }
            .frame(width: width, height: groupH)
            .offset(y: groupTop)
            .accessibilityHidden(true)

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(spokenText()))
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// The words of the current line, or the current door, for VoiceOver.
    private func spokenText() -> String {
        switch input.phase {
        case .waiting:
            guard let line = input.currentLine else { return "" }
            if let source = line.source { return line.text + ", " + source }
            return line.text
        case .choosing, .committed:
            guard let door = input.choice?.choice else { return "" }
            return ([door.title, door.lead] + door.perks).joined(separator: ". ")
        }
    }
}

// MARK: - Plain values

private nonisolated struct MPPColors {
    let ink: Color
    let paper: Color
    let canvas: Color
    let border: Color
    let accent: Color
}

private nonisolated enum MPPStyle {
    case n, g, d, b

    var alpha: Double {
        switch self {
        case .n: return 1
        case .g: return 0.66
        case .d: return 0.4
        case .b: return 1
        }
    }
}

private typealias MPPSeg = (String, MPPStyle)

private nonisolated enum MPPDayState {
    case done, today, planned, missed, rest
}

private nonisolated enum MPPDoorKind {
    case gym, home, cant
}

/// Everything the printer prints, copied out of the contract once (the contract types are
/// main-actor; the drawing is not).
private nonisolated struct MPPData {
    struct Day {
        let letter: String
        let state: MPPDayState
    }
    struct Row {
        let label: String
        let value: String
    }
    struct Door {
        let kind: MPPDoorKind
        let title: String
        let lead: String
        let perks: [String]
    }

    let dateLine: String
    let rows: [Row]
    let week: [Day]
    let visits: Int
    let quote: String?
    let quotePause: Double
    let ifGo: String
    let ifSkip: String
    let factText: String?
    let factSource: String?
    let factPause: Double
    let doors: [Door]
}

private nonisolated func mppClamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T {
    return min(max(x, lo), hi)
}

private nonisolated func mppEase(_ x: Double) -> Double {
    return 1 - pow(1 - x, 3)
}

/// Line feed with a small overshoot (0.5 pt on any row height).
private nonisolated func mppEase1(_ p: Double, _ h: Double) -> Double {
    if p >= 1 { return 1 }
    if p <= 0 { return 0 }
    let c1 = mppClamp(0.5 / h / 0.059, 0.15, 1.2)
    let c3 = c1 + 1
    let q = p - 1
    return 1 + c3 * q * q * q + c1 * q * q
}

private nonisolated func mppHash(_ i: Int, _ k: Int) -> Double {
    let a = UInt32(truncatingIfNeeded: i) &* 374761393
    let b = UInt32(truncatingIfNeeded: k) &* 668265263
    var h = a &+ b
    h = (h ^ (h >> 13)) &* 1274126177
    return Double(h ^ (h >> 16)) / 4294967296.0
}

private nonisolated func mppDot(_ path: inout Path, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

/// Points along a rounded rectangle's outline, `step` apart.
private nonisolated func mppRRPoints(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, step: CGFloat) -> [CGPoint] {
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

// MARK: - Rows and jobs

/// One drawable layer of a row: a path of dots, its fade, and how it is painted.
private nonisolated struct MPPLayer {
    var path: Path
    var alpha: Double
    var coral = false
    var stroke: CGFloat? = nil
    var evenOdd = false
    /// The blinking centre of today's box.
    var blink = false
    /// Not drawn until the sweep has passed this x.
    var minReveal: CGFloat = 0
}

private nonisolated struct MPPRow {
    var isText: Bool
    var isTail = false
    var h: CGFloat
    var py: CGFloat = 0
    var layers: [MPPLayer] = []
    // text
    var chars: [Character] = []
    var len = 0
    var cw: CGFloat = 0
    var p: CGFloat = 0
    var x0: CGFloat = 0
    var endX: CGFloat = 0
    // graphic
    var gdur: Double = 0
    // timeline (seconds on the job's clock)
    var pauseAfter: Double = 0
    var s: Double = .infinity
    var dur: Double = 0
    var e: Double = 0
    var fs: Double = .infinity
    var cs: Double = .infinity
}

private nonisolated struct MPPJob {
    var rows: [MPPRow]
    var total: CGFloat
    var stub: CGFloat
    var adv: Double
    /// The row whose bottom edge is the perforation (the receipt), or -1.
    var perfIdx: Int
    var end: Double

    /// How far the paper has been fed by time `t`.
    func feed(at t: Double, reduce: Bool) -> CGFloat {
        var feed: CGFloat = 0
        for r in rows {
            if t < r.fs { break }
            if reduce {
                feed += r.h
            } else {
                feed += r.h * CGFloat(mppEase1((t - r.fs) / adv, Double(r.h)))
            }
        }
        return feed
    }

    /// Where the print head is along the row, relative to the paper's inner left edge.
    func carriageX(at t: Double, reduce: Bool, inw: CGFloat) -> CGFloat {
        if reduce { return 0 }
        var cur: MPPRow? = nil
        var prev: MPPRow? = nil
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
        let x0: CGFloat = a.isText ? a.x0 : 0
        if t < a.s {
            let u = mppClamp((t - a.cs) / max(0.001, a.s - a.cs), 0, 1)
            var px: CGFloat = 0
            if let prev, t - prev.e < 0.12 { px = prev.endX }
            if u < 0.55 { return px * CGFloat(1 - mppEase(u / 0.55)) }
            return x0 * CGFloat(mppEase((u - 0.55) / 0.45))
        }
        if t <= a.e {
            if a.isText {
                let travelled = CGFloat((t - a.s) * (Double(a.len) / max(0.001, a.dur))) * a.cw
                return min(a.endX + a.p, a.x0 + travelled)
            }
            return inw * CGFloat((t - a.s) / max(0.001, a.dur))
        }
        let ret = mppClamp((t - a.e) / 0.14, 0, 1)
        return a.endX * CGFloat(1 - mppEase(ret))
    }

    /// How far down each key is (0 to 1): one press per printed character, 90 ms each.
    func keyDepths(at t: Double, keyCount: Int, pool: [Int], space: Int) -> [Double] {
        var dep = [Double](repeating: 0, count: keyCount)
        if pool.isEmpty { return dep }
        let win = 0.09
        func shape(_ age: Double) -> Double {
            let a = age / win
            if a < 0 || a >= 1 { return 0 }
            return a < 0.4 ? a / 0.4 : 1 - (a - 0.4) / 0.6
        }
        for (ri, r) in rows.enumerated() {
            if r.isTail || !r.s.isFinite || t < r.s || t > r.e + win + 0.01 { continue }
            if r.isText {
                if r.len == 0 || r.dur <= 0 { continue }
                let d = r.dur / Double(r.len)
                let hi = min(r.len - 1, Int(floor((t - r.s) / d)) - 1)
                let lo = max(0, Int(ceil((t - win - r.s) / d)) - 1)
                if lo > hi { continue }
                for q in lo...hi {
                    let tp = r.s + Double(q + 1) * d
                    var k = pool[Int(mppHash(ri * 977 + q, 3) * Double(pool.count)) % pool.count]
                    if r.chars[q] == " " && space >= 0 { k = space }
                    dep[k] = max(dep[k], shape(t - tp))
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
                    let k = pool[Int(mppHash(ri * 31 + kc, 5) * Double(pool.count)) % pool.count]
                    dep[k] = max(dep[k], shape(t - tp))
                }
            }
        }
        return dep
    }
}

// MARK: - Metrics and geometry

/// Text size for a sheet: `scale` shrinks the dot pitch on short screens.
private nonisolated struct MPPMetrics {
    let f: CGFloat
    let u: CGFloat
    let n: Int
    let stub0: CGFloat
    let tail: CGFloat
    let inw: CGFloat

    init(inw: CGFloat, scale: CGFloat) {
        f = scale
        u = 1.6 * scale
        n = max(8, Int(floor((inw + 1.6 * scale) / (6 * 1.6 * scale))))
        stub0 = 22 * scale
        tail = 16 * scale
        self.inw = inw
    }
}

private nonisolated struct MPPGeom {
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
        inw = pw - 2 * MPPGeom.sp
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

private nonisolated struct MPPKey {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
    let isSpace: Bool
}

private nonisolated struct MPPScene {
    let g: MPPGeom
    let data: MPPData
    let receipt: MPPJob
    let receiptFeed: CGFloat
    let tailH: CGFloat
    let paperWin: CGFloat
    let groupH: CGFloat
    let groupTop: CGFloat
    let keys: [MPPKey]
    let pool: [Int]
    let space: Int
    /// Printer body, rail, platen, panel (dots, drawn under the carriage).
    let body: [MPPLayer]
    /// The tractor covers over the paper margins.
    let coverRects: [CGRect]
    let coverDots: Path
}

// MARK: - Building the print timeline

private nonisolated enum MPPBuild {
    // MARK: Text

    static func addText(_ path: inout Path, _ str: String, x0: CGFloat, y0: CGFloat, p: CGFloat, r: CGFloat, bold: Bool) {
        var cx = x0
        for ch in str {
            if let gl = PrinterDotFont.glyph(ch) {
                let off = (5 - gl.width) / 2
                for (j, row) in gl.rows.enumerated() {
                    for (i, lit) in row.enumerated() where lit {
                        let x = cx + (CGFloat(off + i) + 0.5) * p
                        let y = y0 + (CGFloat(j) + 0.5) * p
                        mppDot(&path, x, y, r)
                        if bold { mppDot(&path, x + p * 0.42, y, r) }
                    }
                }
            }
            cx += 6 * p
        }
    }

    static func textRow(_ segs: [MPPSeg], _ m: MPPMetrics, p: CGFloat? = nil, center: Bool = false, top: CGFloat = 0, bot: CGFloat? = nil) -> MPPRow {
        let pp = p ?? m.u
        var full = ""
        for s in segs { full += s.0 }
        let chars = Array(full)
        let cw = 6 * pp
        let len = chars.count
        let w = CGFloat(len) * cw - pp
        let x0: CGFloat = center ? ((m.inw - w) / 2 / pp).rounded() * pp : 0
        let h = top + 9 * pp + (bot ?? 3.4 * m.f)
        var row = MPPRow(isText: true, h: h)
        row.chars = chars
        row.len = len
        row.cw = cw
        row.p = pp
        row.x0 = x0
        row.endX = x0 + CGFloat(len) * cw - pp
        var cx = x0
        for seg in segs {
            var path = Path()
            let bold = seg.1 == .b
            addText(&path, seg.0, x0: cx, y0: top, p: pp, r: pp * (bold ? 0.4 : 0.37), bold: bold)
            if !path.isEmpty { row.layers.append(MPPLayer(path: path, alpha: seg.1.alpha)) }
            cx += CGFloat(seg.0.count) * 6 * pp
        }
        return row
    }

    static func graphicRow(h: CGFloat, gdur: Double, layers: [MPPLayer], _ m: MPPMetrics) -> MPPRow {
        var row = MPPRow(isText: false, h: h)
        row.layers = layers
        row.gdur = gdur
        row.endX = m.inw
        return row
    }

    static func wrap(_ s: String, _ n: Int) -> [String] {
        var out: [String] = []
        var line = ""
        for word in s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
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

    /// "label ..... value" with dot leaders.
    static func kv(_ label: String, _ value: String, top: CGFloat, _ m: MPPMetrics) -> MPPRow {
        let d = max(2, m.n - label.count - value.count - 2)
        let leaders = " " + String(repeating: ".", count: d) + " "
        let segs: [MPPSeg] = [(label, MPPStyle.g), (leaders, MPPStyle.d), (value, MPPStyle.b)]
        return textRow(segs, m, top: top)
    }

    static func rule(top: CGFloat, _ m: MPPMetrics) -> MPPRow {
        var path = Path()
        let y = top + 3 * m.f
        var x: CGFloat = 1
        while x < m.inw {
            mppDot(&path, x, y, 0.9)
            x += 4.4 * m.f + 1.2
        }
        return graphicRow(h: top + 7 * m.f, gdur: 0.28, layers: [MPPLayer(path: path, alpha: 0.3)], m)
    }

    // MARK: Week strip

    static func strip(p3 requested: CGFloat, days: [MPPData.Day], top: CGFloat, _ m: MPPMetrics) -> MPPRow {
        let count = CGFloat(days.count)
        let p3 = min(requested, (m.inw - 2 * max(0, count - 1)) / (11 * count))
        let bw = 11 * p3
        let gap: CGFloat = days.count > 1 ? (m.inw - count * bw) / (count - 1) : 0
        let lp = max(1, 0.375 * p3)
        let h = top + bw + 5 * m.f + 9 * lp + 3 * m.f
        let check = PrinterDotIcons.check.map { Array($0) }
        var layers: [MPPLayer] = []
        for (di, day) in days.enumerated() {
            let cx = CGFloat(di) * (bw + gap) + bw / 2
            let cy = top + bw / 2
            let r = p3 * 0.36
            var box = Path()
            for j in 0..<11 {
                for i in 0..<11 {
                    if (i == 0 || i == 10) && (j == 0 || j == 10) { continue }
                    var lit = false
                    switch day.state {
                    case .done:
                        lit = true
                        if j >= 2 && j <= 8 {
                            let row = check[j - 2]
                            if i < row.count && row[i] == "#" { lit = false }
                        }
                    case .today, .planned:
                        lit = (i == 0 || i == 10 || j == 0 || j == 10)
                    case .missed:
                        // outlined box with a diagonal slash of dots
                        lit = (i == 0 || i == 10 || j == 0 || j == 10) || (i == j && i >= 2 && i <= 8)
                    case .rest:
                        lit = false
                    }
                    if !lit { continue }
                    mppDot(&box, cx + CGFloat(i - 5) * p3, cy + CGFloat(j - 5) * p3, r)
                }
            }
            if day.state == .rest {
                for i in 4...6 { mppDot(&box, cx + CGFloat(i - 5) * p3, cy, r) }
            }
            var alpha = 1.0
            switch day.state {
            case .planned, .missed: alpha = 0.55
            case .rest: alpha = 0.38
            default: alpha = 1
            }
            layers.append(MPPLayer(path: box, alpha: alpha))

            // the day's letter under the box
            let style: MPPStyle = day.state == .today ? .b : (day.state == .rest ? .d : .g)
            var label = Path()
            addText(&label, day.letter, x0: cx - 2.5 * lp, y0: top + bw + 5 * m.f, p: lp, r: lp * (style == .b ? 0.4 : 0.37), bold: style == .b)
            layers.append(MPPLayer(path: label, alpha: style.alpha))

            // today blinks: a small filled centre
            if day.state == .today {
                var dyn = Path()
                for j in 3...7 {
                    for i in 4...6 {
                        mppDot(&dyn, cx + CGFloat(i - 5) * p3, cy + CGFloat(j - 5) * p3, p3 * 0.38)
                    }
                }
                var layer = MPPLayer(path: dyn, alpha: 1)
                layer.blink = true
                layer.minReveal = cx + bw / 2 + 2
                layers.append(layer)
            }
        }
        return graphicRow(h: h, gdur: 0.6, layers: layers, m)
    }

    // MARK: The 66 visits

    static func gridRows(visits: Int, _ m: MPPMetrics) -> [MPPRow] {
        let cols = 22
        let gx = m.inw * 0.95 / CGFloat(cols)
        let ox = m.inw * 0.025
        let rr = min(3.0, gx * 0.23)
        var rows: [MPPRow] = []
        for r in 0..<3 {
            let top: CGFloat = r == 0 ? 6 * m.f : 0
            let h = gx + (r == 0 ? 6 * m.f : 0) - 1 * m.f
            let cy = top + gx / 2 - 0.5 * m.f
            var filled = Path()
            var hollow = Path()
            var faint = Path()
            for q in 0..<cols {
                let idx = r * cols + q
                let cx = ox + CGFloat(q) * gx + gx / 2
                if idx < visits {
                    mppDot(&filled, cx, cy, rr)
                } else if idx == visits {
                    mppDot(&hollow, cx, cy, rr)
                } else {
                    mppDot(&faint, cx, cy, rr * 0.5)
                }
            }
            var hollowLayer = MPPLayer(path: hollow, alpha: 1)
            hollowLayer.coral = true
            hollowLayer.stroke = 1.5
            rows.append(graphicRow(h: h, gdur: 0.6, layers: [
                MPPLayer(path: filled, alpha: 1),
                hollowLayer,
                MPPLayer(path: faint, alpha: 0.17)
            ], m))
        }
        return rows
    }

    static func barcode(top: CGFloat, _ m: MPPMetrics) -> MPPRow {
        let p = 2.2 * m.f
        let r = p * 0.38
        var path = Path()
        var x: CGFloat = 0
        var k = 0
        let total = m.inw - 2 * p
        while x < total {
            let wbar = 1 + Int(floor(mppHash(k, 7) * 2.4))
            let gap = 1 + Int(floor(mppHash(k, 11) * 3))
            var b = 0
            while b < wbar && x < total {
                for j in 0..<6 {
                    mppDot(&path, p / 2 + x, top + (CGFloat(j) + 0.5) * p, r)
                }
                b += 1
                x += p
            }
            x += CGFloat(gap) * p
            k += 1
        }
        return graphicRow(h: top + 6 * p + 4 * m.f, gdur: 0.5, layers: [MPPLayer(path: path, alpha: 0.85)], m)
    }

    // MARK: Ticket icon

    static func iconBands(_ kind: MPPDoorKind, top: CGFloat, _ m: MPPMetrics) -> [MPPRow] {
        let src: [String]
        switch kind {
        case .gym: src = PrinterDotIcons.dumbbell
        case .home: src = PrinterDotIcons.house
        case .cant: src = PrinterDotIcons.calendar
        }
        let grid = src.map { Array($0) }
        let cp = 6 * m.f
        let w = CGFloat(grid.map { $0.count }.max() ?? 0)
        let band = 3
        var out: [MPPRow] = []
        var r0 = 0
        while r0 < grid.count {
            let r1 = min(grid.count, r0 + band)
            let h = CGFloat(r1 - r0) * cp + (r0 == 0 ? top : 0) + (r1 == grid.count ? 6 * m.f : 0)
            let ox = (m.inw - w * cp) / 2
            let oy: CGFloat = r0 == 0 ? top : 0
            let r = cp * 0.4
            var path = Path()
            for j in r0..<r1 {
                for (i, ch) in grid[j].enumerated() {
                    if ch == "." { continue }
                    let x = ox + (CGFloat(i) + 0.5) * cp
                    let y = oy + (CGFloat(j - r0) + 0.5) * cp
                    if ch == "o" {
                        mppDot(&path, x, y, r * 1.45)
                        mppDot(&path, x, y, r * 0.55)
                    } else {
                        mppDot(&path, x, y, r)
                    }
                }
            }
            var layer = MPPLayer(path: path, alpha: 1)
            layer.evenOdd = true
            out.append(graphicRow(h: h, gdur: 0.1, layers: [layer], m))
            r0 = r1
        }
        return out
    }

    // MARK: Scheduling

    /// Times every row. `target` > 0 solves the pause scale so the last row ends at `target`.
    static func schedule(_ rows: inout [MPPRow], rate: Double, adv: Double, s0: Double, target: Double) {
        func run(_ rows: inout [MPPRow], _ k: Double) -> Double {
            var t = s0
            var last = 0.0
            for i in rows.indices {
                rows[i].s = t
                rows[i].dur = rows[i].isText ? Double(rows[i].len) / rate : rows[i].gdur
                rows[i].e = rows[i].s + rows[i].dur
                rows[i].fs = rows[i].s - adv
                rows[i].cs = rows[i].fs
                last = rows[i].e
                t = rows[i].e + adv + rows[i].pauseAfter * k
            }
            return last
        }
        var k = 1.0
        if target > 0 {
            var lo = 0.0
            var hi = 60.0
            for _ in 0..<40 {
                k = (lo + hi) / 2
                if run(&rows, k) < target { lo = k } else { hi = k }
            }
        }
        _ = run(&rows, k)
    }

    static func layOut(_ rows: inout [MPPRow]) -> CGFloat {
        var y: CGFloat = 0
        for i in rows.indices {
            rows[i].py = y
            y += rows[i].h
        }
        return y
    }

    // MARK: The receipt

    static func receipt(_ d: MPPData, _ m: MPPMetrics) -> MPPJob {
        var rows: [MPPRow] = []
        func add(_ rs: [MPPRow], _ pause: Double) {
            if rs.isEmpty { return }
            var rs = rs
            rs[rs.count - 1].pauseAfter = pause
            rows.append(contentsOf: rs)
        }
        let f = m.f
        let adv = 0.11

        add([textRow([("GYMLOCK", MPPStyle.n)], m, p: 3.3 * f, center: true, top: 2 * f, bot: 4 * f)], 0.35)
        add([textRow([(d.dateLine, MPPStyle.g)], m, center: true)], 0.5)
        add([rule(top: 2 * f, m)], 0.15)

        for r in d.rows {
            switch r.label {
            case "gym by":
                add([kv(r.label, r.value, top: 4 * f, m)], 0.45)
            case "streak":
                add([kv(r.label, r.value, top: 0, m)], 0.5)
            case "last time":
                add([kv(r.label, r.value, top: 0, m)], 0.4)
            case "this week":
                add([kv(r.label, r.value, top: 4 * f, m)], 0.3)
                if !d.week.isEmpty { add([strip(p3: 3 * f, days: d.week, top: 3 * f, m)], 0.6) }
            case "this visit":
                add([kv(r.label, r.value, top: 4 * f, m)], 0.35)
                add(gridRows(visits: d.visits, m), 0.8)
            default:
                add([kv(r.label, r.value, top: 0, m)], 0.4)
            }
        }
        add([rule(top: 3 * f, m)], 0.15)

        if let quote = d.quote {
            add([textRow([("you said:", MPPStyle.g)], m, top: 2 * f)], 0.35)
            add(wrap(quote, m.n).map { textRow([($0, MPPStyle.b)], m) }, d.quotePause + 0.6)
            add([rule(top: 2 * f, m)], 0.15)
        }

        add([kv("if you go", d.ifGo, top: 2 * f, m)], 0.4)
        add([kv("if you skip", d.ifSkip, top: 0, m)], 0.7)
        add([rule(top: 2 * f, m)], 0.15)

        if let fact = d.factText {
            let lines = wrap(fact, m.n).map { textRow([($0, MPPStyle.n)], m) }
            if let source = d.factSource {
                add(lines, 0.4)
                add([textRow([(source, MPPStyle.g)], m, p: m.u * 0.8, bot: 3 * f)], d.factPause + 0.5)
            } else {
                add(lines, d.factPause + 0.5)
            }
        }

        add([barcode(top: 2 * f, m)], 0.4)
        add([textRow([("--- tear here ---", MPPStyle.d)], m, center: true, top: 1 * f)], 0)

        var tail = graphicRow(h: m.tail, gdur: 0, layers: [], m)
        tail.isTail = true
        rows.append(tail)

        let total = layOut(&rows)
        schedule(&rows, rate: 28, adv: adv, s0: 0.35, target: 28.62)
        // The tail is fed just after the last printed row and never prints.
        let tearIdx = rows.count - 2
        let tearEnd = rows[tearIdx].e
        rows[rows.count - 1].fs = tearEnd + 0.15
        rows[rows.count - 1].s = .infinity
        rows[rows.count - 1].cs = .infinity
        return MPPJob(rows: rows, total: total, stub: m.stub0, adv: adv, perfIdx: tearIdx, end: tearEnd)
    }

    // MARK: A door's ticket

    static func ticket(_ door: MPPData.Door, week: [MPPData.Day], _ m: MPPMetrics, stub: CGFloat) -> MPPJob {
        var rows: [MPPRow] = []
        let f = m.f
        let adv = 0.05

        let tp = 2.9 * f
        let tn = max(6, Int(floor((m.inw + tp) / (6 * tp))))
        for (i, line) in wrap(door.title.uppercased(), tn).enumerated() {
            rows.append(textRow([(line, MPPStyle.n)], m, p: tp, center: true, top: i == 0 ? 2 * f : 1 * f, bot: 3 * f))
        }
        rows.append(contentsOf: iconBands(door.kind, top: 4 * f, m))
        for (i, line) in wrap(door.lead, m.n).enumerated() {
            rows.append(textRow([(line, MPPStyle.n)], m, top: i == 0 ? 2 * f : 0))
        }
        for (pi, perk) in door.perks.enumerated() {
            for (i, line) in wrap(perk, max(4, m.n - 2)).enumerated() {
                if i == 0 {
                    let segs: [MPPSeg] = [("+ ", MPPStyle.b), (line, MPPStyle.n)]
                    rows.append(textRow(segs, m, top: pi == 0 ? 2 * f : 0))
                } else {
                    rows.append(textRow([("  " + line, MPPStyle.n)], m))
                }
            }
        }
        if door.kind != .cant && !week.isEmpty {
            // today is filled on a ticket: this is the day you are doing
            let filled = week.map { $0.state == .today ? MPPData.Day(letter: $0.letter, state: .done) : $0 }
            rows.append(strip(p3: 2.1 * f, days: filled, top: 5 * f, m))
        }

        let total = layOut(&rows)
        var chars = 0
        var gsum = 0.0
        for r in rows {
            if r.isText { chars += r.len } else { gsum += r.gdur }
        }
        let s0 = 0.3
        let spare = max(0.4, 2.4 - s0 - gsum - Double(rows.count - 1) * adv)
        let rate = max(60, Double(chars) / spare)
        schedule(&rows, rate: rate, adv: adv, s0: s0, target: 0)
        let end = rows.last?.e ?? 0
        return MPPJob(rows: rows, total: total, stub: stub, adv: adv, perfIdx: -1, end: end)
    }

    // MARK: Scene

    static func scene(_ data: MPPData, g: MPPGeom) -> MPPScene {
        var m = MPPMetrics(inw: g.inw, scale: 1)
        var job = receipt(data, m)
        var need = job.total + job.stub
        let winAvail = max(120, g.avail - g.fixed)
        if need > winAvail {
            let sc = mppClamp(winAvail / need, 0.76, 1)
            m = MPPMetrics(inw: g.inw, scale: sc)
            job = receipt(data, m)
            need = job.total + job.stub
        }
        let paperWin = min(winAvail, need + 10).rounded()
        let groupH = paperWin + g.fixed
        let groupTop = (g.regionTop + (g.avail - groupH) / 2).rounded()

        // keys
        var keys: [MPPKey] = []
        let gap: CGFloat = 5
        let kw = (g.bx1 - g.bx0 - 11 * gap) / 12
        let ky = paperWin + g.bodyH + g.gapK
        for i in 0..<12 {
            keys.append(MPPKey(x: g.bx0 + CGFloat(i) * (kw + gap), y: ky, w: kw, h: g.keyH, isSpace: false))
        }
        if g.keyRows == 2 {
            let y2 = ky + g.keyH + 4
            for i in [0, 1] {
                keys.append(MPPKey(x: g.bx0 + CGFloat(i) * (kw + gap), y: y2, w: kw, h: g.keyH, isSpace: false))
            }
            keys.append(MPPKey(x: g.bx0 + 2 * (kw + gap), y: y2, w: 8 * kw + 7 * gap, h: g.keyH, isSpace: true))
            for i in [10, 11] {
                keys.append(MPPKey(x: g.bx0 + CGFloat(i) * (kw + gap), y: y2, w: kw, h: g.keyH, isSpace: false))
            }
        }
        var pool: [Int] = []
        var space = -1
        for (i, k) in keys.enumerated() {
            if k.isSpace { space = i } else { pool.append(i) }
        }

        let machine = machineParts(g: g, sy: paperWin)
        return MPPScene(
            g: g,
            data: data,
            receipt: job,
            receiptFeed: job.feed(at: 1_000_000_000, reduce: false),
            tailH: m.tail,
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
    }

    /// The printer's static dots: ghost paper guides, body outline, rail, platen, panel.
    static func machineParts(g: MPPGeom, sy: CGFloat) -> (body: [MPPLayer], coverRects: [CGRect], coverDots: Path) {
        var layers: [MPPLayer] = []

        // ghost paper guides above the printer
        var ghost = Path()
        var gy = sy - 8
        while gy > 24 {
            mppDot(&ghost, g.px - 0.5, gy, 0.7)
            mppDot(&ghost, g.px + g.pw + 0.5, gy, 0.7)
            gy -= 6
        }
        layers.append(MPPLayer(path: ghost, alpha: 0.12))

        // body outline (open where the paper comes out)
        var outline = Path()
        for pt in mppRRPoints(x: g.bx0, y: sy, w: g.bx1 - g.bx0, h: g.bodyH, r: 15, step: 4.2) {
            if pt.y < sy + 1 && pt.x > g.px - 16 && pt.x < g.px + g.pw + 16 { continue }
            mppDot(&outline, pt.x, pt.y, 1.15)
        }
        layers.append(MPPLayer(path: outline, alpha: 0.3))

        // carriage rail
        var rail = Path()
        var rx = g.bx0 + 18
        while rx <= g.bx1 - 18 {
            mppDot(&rail, rx, sy + 10, 0.8)
            rx += 3.6
        }
        layers.append(MPPLayer(path: rail, alpha: 0.2))

        // platen / slot
        var platen = Path()
        var qx = g.px - 12
        while qx <= g.px + g.pw + 12 {
            mppDot(&platen, qx, sy - 0.8, 1.15)
            mppDot(&platen, qx, sy + 2.2, 1.15)
            qx += 2.6
        }
        layers.append(MPPLayer(path: platen, alpha: 0.85))

        // panel: caption, pills, led
        let mid = (g.bx0 + g.bx1) / 2
        let py0 = sy + (g.short ? 21 : 24)
        let caption = "GYMLOCK"
        let cp: CGFloat = 1.05
        var cap = Path()
        MPPBuild.addText(&cap, caption, x0: mid - (CGFloat(caption.count) * 6 * cp - cp) / 2, y0: py0, p: cp, r: cp * 0.4, bold: false)
        layers.append(MPPLayer(path: cap, alpha: 0.34))

        let py1 = sy + g.bodyH - (g.short ? 13 : 17)
        var pills = Path()
        for mIdx in [-1, 0, 1] {
            let cx = mid + CGFloat(mIdx) * 34 - 6
            let w: CGFloat = 24
            let hh: CGFloat = 8
            for pt in mppRRPoints(x: cx - w / 2, y: py1 - hh / 2, w: w, h: hh, r: 3.5, step: 3) {
                mppDot(&pills, pt.x, pt.y, 0.8)
            }
        }
        layers.append(MPPLayer(path: pills, alpha: 0.26))

        var led = Path()
        mppDot(&led, mid + 54, py1, 2.1)
        layers.append(MPPLayer(path: led, alpha: 0.8))

        // tractor covers over the paper margins
        var rects: [CGRect] = []
        var dots = Path()
        let sp = MPPGeom.sp
        let covers: [(CGFloat, CGFloat)] = [(g.px - 2, sp - 1), (g.px + g.pw - sp + 3, sp - 1)]
        for (x, w) in covers {
            rects.append(CGRect(x: x + 1, y: sy - 15, width: w - 2, height: 15))
            for pt in mppRRPoints(x: x, y: sy - 15, w: w, h: 15, r: 3, step: 3.4) {
                if pt.y > sy - 1 { continue }
                mppDot(&dots, pt.x, pt.y, 0.8)
            }
        }
        return (layers, rects, dots)
    }
}

// MARK: - Drawing

private nonisolated enum MPPDraw {
    // MARK: Paper window

    static func paper(_ c: inout GraphicsContext, scene: MPPScene, frame: MPPFrame, reduce: Bool, colors: MPPColors) {
        paperSheet(&c, scene: scene, job: frame.main, t: frame.mainT, reduce: reduce, blink: frame.blink, colors: colors)
        if let fly = frame.fly {
            flyingSheet(&c, scene: scene, fly: fly, reduce: reduce, blink: frame.blink, colors: colors)
        }
    }

    /// The sheet that was just torn off (or replaced), lifting away and fading.
    static func flyingSheet(_ c: inout GraphicsContext, scene: MPPScene, fly: MPPFly, reduce: Bool, blink: Bool, colors: MPPColors) {
        let dur = reduce ? 0.2 : 0.38
        let u = mppClamp(fly.age / dur, 0, 1)
        if u >= 1 { return }
        let g = scene.g
        let win = scene.paperWin
        let finalT = 1_000_000_000.0
        let feed = fly.job.feed(at: finalT, reduce: false)
        var perfY = win
        if fly.atPerforation, fly.job.perfIdx >= 0 {
            let r = fly.job.rows[fly.job.perfIdx]
            perfY = win - feed + r.py + r.h
        }
        var fc = c
        fc.opacity = 1 - u
        if !reduce {
            let e = CGFloat(u * u)
            fc.translateBy(x: 0, y: -fly.lift * e)
            let ox = g.px + g.pw / 2
            fc.translateBy(x: ox, y: perfY)
            fc.rotate(by: .degrees(Double(2 * e)))
            fc.translateBy(x: -ox, y: -perfY)
        }
        if fly.atPerforation {
            fc.clip(to: Path(CGRect(x: -400, y: -4000, width: g.w + 800, height: perfY + 4000)))
        }
        paperSheet(&fc, scene: scene, job: fly.job, t: finalT, reduce: reduce, blink: blink, colors: colors)
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

    static func paperSheet(_ c: inout GraphicsContext, scene: MPPScene, job: MPPJob, t: Double, reduce: Bool, blink: Bool, colors: MPPColors) {
        let g = scene.g
        let win = scene.paperWin
        let px = g.px
        let pw = g.pw
        let sp = MPPGeom.sp
        let inw = g.inw
        let feed = job.feed(at: t, reduce: reduce)
        let yt = win - feed - job.stub

        // paper with hairline sides
        c.fill(Path(CGRect(x: px, y: yt, width: pw, height: win - yt + 2)), with: .color(colors.paper))
        c.fill(Path(CGRect(x: px, y: yt, width: 1, height: win - yt)), with: .color(colors.border))
        c.fill(Path(CGRect(x: px + pw - 1, y: yt, width: 1, height: win - yt)), with: .color(colors.border))

        // tractor margins: micro-perforation lines and sprocket holes
        var micro = Path()
        var my = win - 2
        let microMin = max(yt + 3, -6)
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
            if hy >= yt + 6 {
                mppDot(&holes, px + 11, hy, 2.7)
                mppDot(&holes, px + pw - 11, hy, 2.7)
            }
            hy += ph
        }
        c.fill(holes, with: .color(colors.ink.opacity(0.06)))

        // perforation at the top of the stub, and at the tear line
        let perfColor = colors.ink.opacity(0.17)
        c.fill(perfPath(px: px, pw: pw, y: yt + 4), with: .color(perfColor))
        if job.perfIdx >= 0 {
            let r = job.rows[job.perfIdx]
            if t >= r.fs {
                c.fill(perfPath(px: px, pw: pw, y: win - feed + r.py + r.h + 0.5), with: .color(perfColor))
            }
        }

        // rows
        for r in job.rows {
            if r.isTail || r.layers.isEmpty { continue }
            if t < r.s { continue }
            let y = win - feed + r.py
            if y + r.h < 0 || y > win { continue }
            let rev: CGFloat
            if r.isText {
                if r.len == 0 || r.dur <= 0 { continue }
                let n: Int = reduce ? r.len : Int(mppClamp(floor((t - r.s) * Double(r.len) / r.dur + 1e-6), 0, Double(r.len)))
                rev = n >= r.len ? inw + 1 : r.x0 + CGFloat(n) * r.cw
            } else {
                let u: Double = reduce || r.dur <= 0 ? 1 : mppClamp((t - r.s) / r.dur, 0, 1)
                rev = u >= 1 ? inw + 1 : inw * CGFloat(u)
            }
            if rev <= 0.5 { continue }
            let fade: Double = reduce ? mppClamp((t - r.s) / 0.2, 0, 1) : 1
            var rc = c
            rc.translateBy(x: px + sp, y: y)
            if rev < inw + 1 {
                rc.clip(to: Path(CGRect(x: -6, y: -4, width: rev + 6, height: r.h + 8)))
            }
            for layer in r.layers {
                if layer.blink && !blink { continue }
                if rev < layer.minReveal { continue }
                let base = layer.coral ? colors.accent : colors.ink
                let color = base.opacity(layer.alpha * fade)
                if let lw = layer.stroke {
                    rc.stroke(layer.path, with: .color(color), lineWidth: lw)
                } else {
                    rc.fill(layer.path, with: .color(color), style: FillStyle(eoFill: layer.evenOdd))
                }
            }
        }
    }

    // MARK: Machine

    static func machine(_ c: inout GraphicsContext, scene: MPPScene, frame: MPPFrame, reduce: Bool, colors: MPPColors) {
        let g = scene.g
        let sy = scene.paperWin
        let job = frame.main
        let t = frame.mainT

        for layer in scene.body {
            c.fill(layer.path, with: .color(colors.ink.opacity(layer.alpha)))
        }

        // tractor covers
        for rect in scene.coverRects {
            c.fill(Path(rect), with: .color(colors.canvas))
        }
        c.fill(scene.coverDots, with: .color(colors.ink.opacity(0.3)))

        // knobs: a few dots per line feed
        let feed = job.feed(at: t, reduce: reduce)
        let ang: CGFloat = reduce ? 0 : (frame.knobBase + feed) * 0.065
        let ky = sy + 10 + (g.bodyH - 10) / 2
        let knobR = min(12, g.bodyH * 0.2)
        knob(&c, cx: g.bx0 + 28, cy: ky, ang: ang, radius: knobR, colors: colors)
        knob(&c, cx: g.bx1 - 28, cy: ky, ang: ang, radius: knobR, colors: colors)

        // carriage on the print head
        let cx = g.px + MPPGeom.sp + job.carriageX(at: t, reduce: reduce, inw: g.inw)
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
                mppDot(&head, cx - 3 + 2.7 + CGFloat(i) * 2.8 + 1.0, cy + 2.8 + CGFloat(j) * 3.1, 0.95)
            }
        }
        c.fill(head, with: .color(colors.ink.opacity(0.88)))
        c.fill(Path(CGRect(x: cx - 3 + 1.5, y: cy + ch - 3, width: 3, height: 3)), with: .color(colors.ink))

        // keys
        var depths = [Double](repeating: 0, count: scene.keys.count)
        if !reduce {
            depths = job.keyDepths(at: t, keyCount: scene.keys.count, pool: scene.pool, space: scene.space)
        }
        for (i, k) in scene.keys.enumerated() {
            let dep = depths[i]
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
            mppDot(&dot, k.x + k.w / 2, k.y + d + (k.h - 2) / 2, 1.1)
            c.fill(dot, with: .color(colors.ink.opacity(0.12 + 0.12 * dep)))
        }
    }

    /// A ring of 16 dots with a bright arc; it turns with the paper feed.
    static func knob(_ c: inout GraphicsContext, cx: CGFloat, cy: CGFloat, ang: CGFloat, radius: CGFloat, colors: MPPColors) {
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
                mppDot(&bright, x, y, 1.35 - CGFloat(d) * 0.12)
            } else {
                mppDot(&dim, x, y, 1.05)
            }
        }
        mppDot(&dim, cx, cy, 1.5)
        let spokeAngle = floor(pos) / Double(n) * 2 * Double.pi - Double.pi / 2
        for q in 1...2 {
            let rr = CGFloat(q) * radius * 0.33
            mppDot(&dim, cx + CGFloat(cos(spokeAngle)) * rr, cy + CGFloat(sin(spokeAngle)) * rr, 0.9)
        }
        c.fill(dim, with: .color(colors.ink.opacity(0.26)))
        c.fill(bright, with: .color(colors.ink.opacity(0.75)))
    }
}

// MARK: - One frame

/// The sheet that is leaving: the receipt at its perforation, or the previous door's ticket.
private nonisolated struct MPPFly {
    let job: MPPJob
    let age: Double
    let lift: CGFloat
    let atPerforation: Bool
}

private nonisolated struct MPPFrame {
    let main: MPPJob
    /// Seconds on `main`'s own clock (negative before it starts printing).
    let mainT: Double
    /// Paper already fed before this sheet, so the knobs do not jump.
    let knobBase: CGFloat
    let fly: MPPFly?
    let blink: Bool
    /// Haptic ids are unique per printed sheet.
    let serial: Int
    let live: Bool
}

// MARK: - Cache

/// Builds the timelines once per layout and works out, each frame, which sheet is on the printer.
/// Its fields only remember what the host's phase cannot tell us (how old a ticket was when a
/// door was taken); they never drive a redraw.
private final class MPPCache {
    private var key: MPPCacheKey?
    private var built: MPPScene?
    private var tickets: [Int: MPPJob] = [:]

    private var lastIndex = -1
    private var lastAge = 0.0
    private var lastT = 0.0
    private var lastFirst = false
    private var lastBase: CGFloat = 0

    func scene(for input: PauseStageInput) -> MPPScene {
        let layout = input.layout
        let newKey = MPPCacheKey(
            w: layout.size.width,
            h: layout.size.height,
            top: layout.contentTop,
            bottom: layout.contentBottom,
            visits: input.facts.visitsBefore,
            rows: input.script.receiptRows.count,
            ifGo: input.script.ifGo,
            ifSkip: input.script.ifSkip,
            date: input.facts.dateLabel,
            now: input.facts.nowLabel
        )
        if let built, key == newKey { return built }
        let geom = MPPGeom(
            width: layout.size.width,
            height: layout.size.height,
            contentTop: layout.contentTop,
            contentBottom: layout.contentBottom
        )
        let scene = MPPBuild.scene(extract(input), g: geom)
        key = newKey
        built = scene
        tickets = [:]
        lastIndex = -1
        return scene
    }

    /// The contract's values, as plain data.
    private func extract(_ input: PauseStageInput) -> MPPData {
        let facts = input.facts
        let script = input.script
        let week: [MPPData.Day] = facts.week.map { day in
            let state: MPPDayState
            switch day.state {
            case .done: state = .done
            case .today: state = .today
            case .planned: state = .planned
            case .missed: state = .missed
            case .rest: state = .rest
            }
            return MPPData.Day(letter: day.letter, state: state)
        }
        let rows = script.receiptRows.map { MPPData.Row(label: $0.label, value: $0.value) }
        let doors: [MPPData.Door] = script.choices.map { choice in
            let kind: MPPDoorKind
            switch choice.key {
            case .gym: kind = .gym
            case .home: kind = .home
            case .cant: kind = .cant
            }
            return MPPData.Door(kind: kind, title: choice.title, lead: choice.lead, perks: choice.perks)
        }
        func pause(_ text: String) -> Double {
            return mppClamp(PauseScript.lineDuration(text) * 0.22, 0.5, 1.5)
        }
        return MPPData(
            dateLine: facts.dateLabel + "  " + facts.nowLabel,
            rows: rows,
            week: week,
            visits: facts.visitsBefore,
            quote: script.quote,
            quotePause: script.quote.map { pause($0) } ?? 0,
            ifGo: script.ifGo,
            ifSkip: script.ifSkip,
            factText: script.fact?.text,
            factSource: script.fact?.source,
            factPause: script.fact.map { pause($0.text) } ?? 0,
            doors: doors
        )
    }

    private func ticket(_ index: Int, first: Bool, scene: MPPScene) -> MPPJob {
        let slot = index * 2 + (first ? 1 : 0)
        if let job = tickets[slot] { return job }
        let door = scene.data.doors[index]
        let inw = scene.g.inw
        // the first ticket continues the receipt's own stub
        let stub: CGFloat = first ? scene.tailH : 16
        var job = MPPBuild.ticket(door, week: scene.data.week, MPPMetrics(inw: inw, scale: 1), stub: stub)
        let sc = mppClamp(0.64 * scene.paperWin / (job.total + stub), 1, 1.2)
        if sc > 1.02 {
            job = MPPBuild.ticket(door, week: scene.data.week, MPPMetrics(inw: inw, scale: sc), stub: stub)
        }
        tickets[slot] = job
        return job
    }

    func frame(scene: MPPScene, input: PauseStageInput) -> MPPFrame {
        let t = input.t
        let reduce = input.reduceMotion
        let blink = reduce || Int(floor(t / 0.6)) % 2 == 0
        let count = scene.data.doors.count
        func valid(_ i: Int) -> Int { return min(max(i, 0), count - 1) }

        switch input.phase {
        case .waiting:
            return MPPFrame(main: scene.receipt, mainT: t, knobBase: 0, fly: nil, blink: blink, serial: 0, live: true)

        case .choosing(let index, let since, let from):
            let idx = valid(index)
            let age = max(0, t - since)
            let first = from == nil
            let job = ticket(idx, first: first, scene: scene)
            let base: CGFloat
            let fly: MPPFly
            if let from {
                let old = ticket(valid(from), first: false, scene: scene)
                base = old.feed(at: 1_000_000_000, reduce: false)
                fly = MPPFly(job: old, age: age, lift: 40, atPerforation: false)
            } else {
                base = scene.receiptFeed
                fly = MPPFly(job: scene.receipt, age: age, lift: 20, atPerforation: true)
            }
            lastIndex = idx
            lastAge = age
            lastT = t
            lastFirst = first
            lastBase = base
            let delay = first ? (reduce ? 0.2 : 0.42) : 0
            return MPPFrame(
                main: job,
                mainT: age - delay,
                knobBase: base,
                fly: fly,
                blink: blink,
                serial: Int((since * 1000).rounded()) + 1,
                live: true
            )

        case .committed:
            // Hold the ticket as it was; the screen leaves in a moment.
            let idx = valid(input.choice?.index ?? max(0, lastIndex))
            let same = idx == lastIndex
            let first = same ? lastFirst : false
            let age = same ? lastAge + (t - lastT) : 10
            let job = ticket(idx, first: first, scene: scene)
            let delay = first ? (reduce ? 0.2 : 0.42) : 0
            return MPPFrame(
                main: job,
                mainT: age - delay,
                knobBase: same ? lastBase : 0,
                fly: nil,
                blink: blink,
                serial: 0,
                live: false
            )
        }
    }

    /// Printer ticks while characters print, a soft tap when a graphic row completes. The host
    /// plays each id once, so a skipped frame or a replay never doubles a tap.
    func fireHaptics(_ frame: MPPFrame, _ haptics: PauseHaptics) {
        if !frame.live { return }
        let t = frame.mainT
        let prefix = frame.serial == 0 ? "mp" : "mp\(frame.serial)"
        for (ri, r) in frame.main.rows.enumerated() {
            if r.isTail || !r.s.isFinite || t < r.s { continue }
            if r.isText {
                if r.len == 0 || r.dur <= 0 || t > r.e + 0.35 { continue }
                let n = min(r.len, Int(floor((t - r.s) * Double(r.len) / r.dur)))
                if n >= 1 {
                    haptics.cue("\(prefix).c.\(ri).\(n / 3)", .light)
                }
            } else if t >= r.e && t - r.e < 0.3 {
                haptics.cue("\(prefix).g.\(ri)", .soft)
            }
        }
    }
}

private struct MPPCacheKey: Equatable {
    let w: CGFloat
    let h: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    let visits: Int
    let rows: Int
    let ifGo: String
    let ifSkip: String
    let date: String
    let now: String
}
