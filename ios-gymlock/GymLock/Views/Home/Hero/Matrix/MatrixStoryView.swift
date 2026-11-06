//
//  MatrixStoryView.swift
//  GymLock · Matrix done flow (native port)
//
//  Native port of web/hero13/story13m.tsx (frame, copy, light) + web/hero13/mxstory.ts (the dots)
//  + the tap state machine in web/hero13/app13.tsx (onOverlayTap / onRockTap / collapse) + the screen
//  table CFG_M in web/hero12/screens12.ts.
//
//  The board:
//    - Design space: hero4/story4.tsx `fitComposition`. On every iPhone (aspect < 1080/1920) the
//      composition is 1080 wide and round(1080 / aspect / 2) * 2 tall; it is scaled by
//      s0 = viewWidth / 1080, so every phone shows the same picture, only taller or shorter.
//    - Grid: 52 x ceil(h / 21) cells at pitch 21 (ceil(1080 / 21) = 52), white at 0.07, radius 1.6.
//    - 1400 particles, dot radius 7.4, white and coral on #0A0A0B.
//    - The 1080 x 1920 text box is centred: ox = (w - 1080) / 2, oy = (h - 1920) / 2. The art centre
//      is cx = floor(w / 2 / 21) + 0.5, cy = floor((oy + 900) / 21) + 0.5 (cells).
//
//  The flow (app13.tsx):
//    - Screens: verified, today, week, [month], far, climax (month only in a month's first/last week).
//    - Nothing moves on by itself. A tap before the screen's `settle` finishes its animation; the next
//      tap goes to the next screen; a tap on the left 22% goes back.
//    - The last screen (climax) is built with N taps (5, or 7 for the week's last session and every
//      Sunday). The Nth tap seals it (sealT): heavy, heavy +70 ms, success +160 ms.
//    - At sealT + 1.6 s the finished object becomes the session count (`counted`, engine key "count").
//    - At sealT + 3.6 s (4.2 s on the month's last session) the overlay collapses into the home card
//      over 0.55 s; at 70% the card switches to `verified` (onLanded), at 100% it is gone (onFinished).
//
//  Ported fully: the frame, the copy layers for the header, the climax and the button, the tap and
//  seal timings, haptics per screen, the collapse, all mxstory helpers, Wednesday's finish (BATTERY)
//  and the count (all seven days). Everything else is a clearly marked TODO mapped to mxstory.ts.
//
//  Depends on: MatrixEngine.swift, MatrixBoard.swift, MatrixScene.swift, HeroHaptics.swift,
//              MatrixCardView.swift (MatrixGridRenderer, MatrixRGB, MatrixRich).
//

import SwiftUI
import Observation

// MARK: - Screens and timing (screens12.ts)

public enum MatrixStoryScreen: String, Sendable, CaseIterable {
    case verified, today, week, month, far, climax
}

public enum MatrixMonthPos: String, Sendable {
    case first, middle, last
}

public enum MatrixStoryConfig {
    /// `screens12(mp)`: five screens, six in a month's first and last weeks.
    public static func screens(_ mp: MatrixMonthPos) -> [MatrixStoryScreen] {
        mp == .middle ? [.verified, .today, .week, .far, .climax] : [.verified, .today, .week, .month, .far, .climax]
    }

    public struct Screen: Sendable {
        public let settle: Double
        public let haptics: [HapticCue]
    }

    /// CFG_M: seconds until the screen's animation has settled, and its haptics (screen seconds).
    public static func cfg(_ id: MatrixStoryScreen) -> Screen {
        func h(_ t: Double, _ k: HapticKind) -> HapticCue { HapticCue(t: t, kind: k) }
        switch id {
        case .verified:
            return Screen(settle: 1.5, haptics: [h(0.05, .medium), h(0.75, .heavy), h(0.8, .success)])
        case .today:
            return Screen(settle: 2.3, haptics: [h(0.05, .medium)] + (0..<13).map { h(0.3 + Double($0) * 0.14, .light) } + [h(2.12, .heavy)])
        case .week:
            return Screen(settle: 2.4, haptics: [h(0.05, .medium)] + (0..<8).map { h(0.2 + Double($0) * 0.18, .light) } + [h(1.9, .medium), h(2.15, .medium)])
        case .month:
            return Screen(settle: 1.8, haptics: [h(0.05, .medium)] + (0..<8).map { h(0.25 + Double($0) * 0.1, .light) } + [h(1.3, .heavy)])
        case .far:
            return Screen(settle: 1.9, haptics: [h(0.05, .medium), h(0.7, .heavy), h(0.75, .success), h(1.5, .light)])
        case .climax:
            return Screen(settle: 1.0, haptics: [h(0.05, .medium)])
        }
    }

    /// Seconds after the seal that the count takes over (story13m.tsx `counted`).
    public static let countAfter: Double = 1.6
    /// Seconds after the seal that the overlay collapses (app13.tsx, Matrix).
    public static func collapseAfter(mp: MatrixMonthPos, pos: MatrixWeekPos) -> Double { mp == .last && pos == .last ? 4.2 : 3.6 }
    public static let collapseDuration: Double = 0.55
}

// MARK: - Climax copy (mxstory.ts MX_CLIMAX, days12.ts POS_TAIL / endFor)

public struct MatrixClimaxCopy: Sendable {
    public let eyebrow: String
    public let lastEyebrow: String
    public let title: String
    public let sub: @Sendable (Int) -> String
    public let idle: String
    public let mid: String
    public let end: String

    public static let byDay: [MatrixClimaxCopy] = [
        MatrixClimaxCopy(eyebrow: "TODAY’S SUNRISE", lastEyebrow: "THE WEEK’S LAST SUNRISE", title: "Raise it.", sub: { "Tap **\($0) times** to lift the sun over the horizon." }, idle: "Tap to raise the sun", mid: "Higher", end: "The sun is up, and so is the count."),
        MatrixClimaxCopy(eyebrow: "TODAY’S BLOCK", lastEyebrow: "THE WEEK’S LAST BLOCK", title: "Build it.", sub: { "Tap **\($0) times.** Every session is a block in the wall." }, idle: "Tap to place a block", mid: "Next block", end: "Set in place. The wall gets taller every session."),
        MatrixClimaxCopy(eyebrow: "TODAY’S CHARGE", lastEyebrow: "THE WEEK’S LAST CHARGE", title: "Charge it.", sub: { "Tap **\($0) times** to fill today’s charge." }, idle: "Tap to charge", mid: "Charging", end: "Fully charged. Training gives back more than it takes."),
        MatrixClimaxCopy(eyebrow: "TODAY’S BAR", lastEyebrow: "THE WEEK’S LAST LIFT", title: "Load it.", sub: { "Tap **\($0) times.** Every tap adds a plate." }, idle: "Tap to add a plate", mid: "Add another", end: "Loaded and lifted. One more rep for the habit."),
        MatrixClimaxCopy(eyebrow: "TODAY’S PUSH", lastEyebrow: "THE WEEK’S LAST PUSH", title: "Push it.", sub: { "Tap **\($0) times** to push today to the top." }, idle: "Tap to push", mid: "Higher", end: "Top reached. One more on the count."),
        MatrixClimaxCopy(eyebrow: "TODAY’S RING", lastEyebrow: "THE WEEK’S LAST RING", title: "Close it.", sub: { "Tap **\($0) times** to close today’s ring." }, idle: "Tap to close the ring", mid: "Keep closing", end: "Ring closed. Habits are loops you keep closing."),
        MatrixClimaxCopy(eyebrow: "THE WEEK’S SAND", lastEyebrow: "THE WEEK’S LAST GRAINS", title: "Turn it.", sub: { "Tap **\($0) times.** One day of sand for each." }, idle: "Tap to let a day fall", mid: "Next day", end: "Every day through. Turn it over and a new week starts."),
    ]

    public static let tally = ["SUNRISES", "BLOCKS LAID", "CHARGES", "BARS LIFTED", "PUSHES", "RINGS CLOSED", "WEEKS TURNED"]

    public static func posTail(_ pos: MatrixWeekPos) -> String {
        switch pos {
        case .first: return "The first of the week is the hardest to start."
        case .middle: return "The middle is where most people stop. **You didn’t.**"
        case .last: return "A full week, finished on a high. **That’s how it will be remembered.**"
        }
    }

    /// `endFor(pos, day)`: the closing line and the button. The next session is the next weekday.
    /// NOTE: the week numbers in the `last` line are the prototype's sample data; feed real values.
    public static func end(pos: MatrixWeekPos, day: Int) -> (sub: String, button: String) {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let next = day >= 4 ? "Monday" : names[max(0, min(6, day + 1))]
        if pos == .last { return ("Week **5 of 5.** Week streak **6.** Rest up.", "Week done. See you Monday") }
        return (pos == .first ? "Next: **\(next), 07:00.** Keep it rolling." : "Next: **\(next), 07:00.** Only 2 left.", "See you \(next)")
    }
}

/// Copy for the screens before the climax. Comes from the app's copy tables (DONE12, POS_WEEK,
/// monthScreen in the prototype). Captions accept **bold** markup.
public struct MatrixStoryCopy: Sendable {
    public struct Header: Sendable {
        public var eyebrow: String
        public var title: String
        public init(eyebrow: String, title: String) {
            self.eyebrow = eyebrow
            self.title = title
        }
    }
    public var headers: [MatrixStoryScreen: Header]
    /// The caption under the art (story13m.tsx: verified `V.sub`, week `PW.s2.sub`, month `MS.sub`, far line).
    public var captions: [MatrixStoryScreen: String]
    /// The quieter second line (week / month research notes).
    public var research: [MatrixStoryScreen: String]

    public init(headers: [MatrixStoryScreen: Header], captions: [MatrixStoryScreen: String] = [:], research: [MatrixStoryScreen: String] = [:]) {
        self.headers = headers
        self.captions = captions
        self.research = research
    }
}

// MARK: - Story scene context (mxstory.ts SC / Out)

public struct MatrixStoryContext: Sendable {
    public var t: Double
    /// seconds since the current screen started
    public var lt: Double
    public var cx: Double
    public var cy: Double
    public var cols: Int
    public var rows: Int
    public var N: Int
    public var taps: Int
    public var tapTimes: [Double]
    public var tapAt: Double?
    public var sealT: Double?
    /// seconds since the seal, or -1
    public var since: Double
    public var D: MatrixDayData
    public var day: Int
    public var pos: MatrixWeekPos
    /// POS_WEEK `{done, today}`
    public var weekDone: Int
    public var weekToday: Int
    public var pick: Bool
    public var picked: Bool
    public var pickAt: Double?
}

public struct MatrixGlow: Sendable, Equatable {
    public var x: Double, y: Double, r: Double, a: Double
}

public struct MatrixStoryOut: Sendable {
    public var phase: String?
    public var opts: MatrixDealOptions?
    public var flash: Double = 0
    public var glow: [MatrixGlow] = []
}

// MARK: - mxstory.ts helpers and screens

public enum MatrixStoryScenes {
    typealias P = (Double, Double)

    static func cl(_ x: Double) -> Double { MX.cl(x) }
    static func ez(_ x: Double) -> Double { MX.ez(x) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { MX.lerp(a, b, t) }
    static let TAU = MX.TAU

    static func seg(_ x: Double, _ a: Double, _ d: Double) -> Double { cl((x - a) / d) }
    /// a quick spring 0 -> 1 from a = 0: lands in about 0.14 s, a small overshoot, settled by 0.4 s
    static func sp(_ a: Double) -> Double { a <= 0 ? 0 : a > 0.6 ? 1 : MX.spr(a, 11, 9) }
    /// a pulse that decays after an event at a = 0
    static func hit(_ a: Double, _ d: Double = 0.25) -> Double { a >= 0 ? exp(-a / d) : 0 }
    static func C(_ v: Double) -> Double { v.rounded(.down) + 0.5 }
    static func eo5(_ x: Double) -> Double { 1 - pow(1 - cl(x), 5) }
    static func gb(_ x: Double) -> Double { exp(-x * x) }

    /// mxstory.ts `path(V)`: a polyline measured by arc length.
    struct Polyline {
        let V: [P]
        let L: [Double]
        let len: Double
        init(_ V: [P]) {
            self.V = V
            var L: [Double] = [0]
            for i in stride(from: 1, to: V.count, by: 1) { L.append(L[i - 1] + hypot(V[i].0 - V[i - 1].0, V[i].1 - V[i - 1].1)) }
            self.L = L
            len = L.last ?? 0
        }
        private func idx(_ s: Double) -> Int {
            var i = 1
            while i < V.count - 1 && L[i] < s { i += 1 }
            return i
        }
        func at(_ s: Double) -> P {
            guard V.count >= 2 else { return V.first ?? (0, 0) }
            let q = max(0, min(len, s)), i = idx(q)
            let d = L[i] - L[i - 1]
            let u = (q - L[i - 1]) / (d != 0 && !d.isNaN ? d : 1) // `|| 1`
            return (lerp(V[i - 1].0, V[i].0, u), lerp(V[i - 1].1, V[i].1, u))
        }
        func dir(_ s: Double) -> P {
            guard V.count >= 2 else { return (1, 0) }
            let i = idx(max(0, min(len, s)))
            let dx = V[i].0 - V[i - 1].0, dy = V[i].1 - V[i - 1].1
            let h = hypot(dx, dy), d = h != 0 ? h : 1
            return (dx / d, dy / d)
        }
    }

    /// a ring of free dots thrown out from (x, y) at a = 0; always pushed, dark when idle
    static func ripple(_ g: inout MatrixBoard, _ x: Double, _ y: Double, _ r0: Double, _ r1: Double, _ a: Double, _ d: Double, _ n: Int, _ b: Double = 0.6) {
        let live = a >= 0 && a < d, p = live ? ez(a / d) : 0
        for i in 0..<max(0, n) {
            let an = (Double(i) / Double(n)) * TAU, r = lerp(r0, r1, p)
            g.fr(x + sin(an) * r, y - cos(an) * r, live ? b * (1 - a / d) : 0)
        }
    }

    /// a diagonal band of light that crosses the art once every `per` seconds (calm idle)
    static func sheen(_ dx: Double, _ dy: Double, _ t: Double, _ per: Double = 3.4, _ span: Double = 34, _ w: Double = 3.5) -> Double {
        let u = (JSMath.rem(JSMath.rem(t, per) + per, per) / per) * (2 * span + 6 * w) - span - 3 * w
        let d = dx + dy * 0.55 - u
        return exp(-(d * d) / (w * w))
    }

    /// LED digits (5 x 7): digits and ':' only, like mxstory's F5.
    static let F5: [Unicode.Scalar: PixelRows] = MatrixLED.FONT.filter { entry in
        let zero: Unicode.Scalar = "0", nine: Unicode.Scalar = "9", colon: Unicode.Scalar = ":"
        return (entry.key >= zero && entry.key <= nine) || entry.key == colon
    }

    /// small 3 x 5 type for labels
    static let F3: [Unicode.Scalar: PixelRows] = [
        "M": PixelRows(["#...#", "##.##", "#.#.#", "#...#", "#...#"]), "T": PixelRows(["###", ".#.", ".#.", ".#.", ".#."]), "W": PixelRows(["#...#", "#...#", "#.#.#", "##.##", "#...#"]),
        "F": PixelRows(["###", "#..", "##.", "#..", "#.."]), "S": PixelRows([".##", "#..", ".#.", "..#", "##."]),
        "0": PixelRows(["###", "#.#", "#.#", "#.#", "###"]), "1": PixelRows([".#.", "##.", ".#.", ".#.", "###"]), "2": PixelRows(["##.", "..#", ".#.", "#..", "###"]),
        "3": PixelRows(["##.", "..#", ".#.", "..#", "##."]), "4": PixelRows(["#.#", "#.#", "###", "..#", "..#"]), "5": PixelRows(["###", "#..", "##.", "..#", "##."]),
        "6": PixelRows([".##", "#..", "###", "#.#", "###"]), "7": PixelRows(["###", "..#", ".#.", ".#.", ".#."]), "8": PixelRows(["###", "#.#", "###", "#.#", "###"]), "9": PixelRows(["###", "#.#", "###", "..#", "##."]),
    ]

    static func txt3(_ g: inout MatrixBoard, _ s: String, _ cx: Double, _ y: Double, _ b: Double) {
        var w = -1.0
        for ch in s.unicodeScalars { w += Double(F3[ch]?.rows.first?.count ?? 3) + 1 }
        var x = JSMath.round(cx - w / 2)
        for ch in s.unicodeScalars {
            if let R = F3[ch] {
                for (j, row) in R.rows.enumerated() {
                    for (i, c) in row.enumerated() where c == PixelRows.hash { g.on(x + Double(i), y + Double(j), b) }
                }
            }
            x += Double(F3[ch]?.rows.first?.count ?? 3) + 1
        }
    }

    /// LED digits on fixed slots laid out for `fmt`: unlit cells dim, so a changing number flips in place.
    static func led(_ g: inout MatrixBoard, _ s: String, _ fmt: String, _ cx: Double, _ y: Double, _ k: Double, _ b: Double, _ dim: Double, _ gap: Double, _ coral: Int = -1) {
        let fmtChars = Array(fmt.unicodeScalars)
        var W = -gap
        for ch in fmtChars { W += Double(F5[ch]?.rows.first?.count ?? 0) * k + gap }
        var x = JSMath.round(cx - W / 2)
        // s.padStart(fmt.length, ' ')
        var sv = Array(s.unicodeScalars)
        if sv.count < fmtChars.count { sv = [Unicode.Scalar](repeating: " ", count: fmtChars.count - sv.count) + sv }
        for (i, fch) in fmtChars.enumerated() {
            let R = i < sv.count ? F5[sv[i]] : nil
            let w = F5[fch]?.rows.first?.count ?? 0
            for r in 0..<7 {
                for c in 0..<w {
                    var on = false
                    if let R, r < R.rows.count, c < R.rows[r].count { on = R.rows[r][c] == PixelRows.one }
                    if !on && dim <= 0 { continue }
                    var v = 0.0
                    while v < k {
                        var u = 0.0
                        while u < k {
                            g.on(x + Double(c) * k + u, y + Double(r) * k + v, on ? b : dim, on && i == coral ? 1 : 0)
                            u += 1
                        }
                        v += 1
                    }
                }
            }
            x += Double(w) * k + gap
        }
    }

    /// the cells of a polyline with thickness (1 or 2), up to arc length upTo
    @discardableResult
    static func stroke(_ g: inout MatrixBoard, _ V: [P], _ upTo: Double, _ b: Double, _ thick: Int = 1, _ c: Int = 0) -> Polyline {
        let pt = Polyline(V)
        var s = 0.0
        while s <= min(upTo, pt.len) + 1e-6 {
            let (x, y) = pt.at(s)
            g.on(x, y, b, c)
            if thick > 1 {
                g.on(x + 1, y, b, c)
                g.on(x, y + 1, b, c)
            }
            s += 0.35
        }
        return pt
    }

    static func cellsOf(_ V: [P], _ thick: Int = 2) -> Set<Int> {
        let pt = Polyline(V)
        var S = Set<Int>()
        var s = 0.0
        while s <= pt.len {
            let (x, y) = pt.at(s)
            S.insert(Int(y.rounded(.down)) * 256 + Int(x.rounded(.down)))
            if thick > 1 {
                S.insert(Int(y.rounded(.down)) * 256 + Int((x + 1).rounded(.down)))
                S.insert(Int((y + 1).rounded(.down)) * 256 + Int(x.rounded(.down)))
            }
            s += 0.3
        }
        return S
    }

    // ============================== 6. THE FINISH ==============================

    static func lastAge(_ s: MatrixStoryContext) -> Double { s.tapAt.map { s.t - $0 } ?? -1 }

    // ---- Wed: BATTERY. Each tap charges a cell; full, the cells join and a bolt strikes through ----
    static let BOLT = PixelRows([".....####", "....####.", "...####..", "..####...", ".########", "########.", "...####..", "..####...", ".####....", ".##......", "#........"])

    static func finWed(_ g: inout MatrixBoard, _ s: MatrixStoryContext, _ age: (Int) -> Double) -> MatrixStoryOut {
        let cx = s.cx, cy = s.cy, N = s.N, t = s.t, since = s.since, taps = s.taps
        let cw = N >= 7 ? 4 : 5, inner = N * cw + N - 1, W = inner + 4, H = 17
        let Wd = Double(W)
        let x0 = JSMath.round(cx - (Wd + 2) / 2), y0 = cy.rounded(.down) - 9
        let sealed = s.sealT != nil
        for i in 0..<W {
            for j in 0..<H {
                let edge = i == 0 || j == 0 || i == W - 1 || j == H - 1
                let corner = (i == 0 || i == W - 1) && (j == 0 || j == H - 1)
                if edge && !corner { g.on(x0 + Double(i), y0 + Double(j), 0.85 + 0.15 * hit(since - 0.3, 0.3)) }
            }
        }
        for i in 0..<2 { for j in 0..<7 { g.on(x0 + Wd + Double(i), y0 + 5 + Double(j), 0.85) } }
        // the bolt, cut out of the full battery top to bottom
        let bx = JSMath.round(x0 + Wd / 2 - 4.5), by = y0 + 3
        let strike = sealed ? seg(since, 0.3, 0.12) * Double(BOLT.height) : -1
        var cut = Set<Int>()
        for (j, row) in BOLT.rows.enumerated() {
            for (i, ch) in row.enumerated() where ch == PixelRows.hash && Double(j) < strike {
                cut.insert(Int(by + Double(j)) * 256 + Int(bx) + i)
            }
        }
        func bolt(_ x: Double, _ y: Double) -> Bool { cut.contains(Int(y.rounded(.down)) * 256 + Int(x.rounded(.down))) }
        func shim(_ x: Double) -> Double {
            guard let sealT = s.sealT, since > 1 else { return 0 }
            return 0.12 * sheen(x - cx, 0, t - sealT - 1, 2.6, 24, 3)
        }
        for k in 0..<N {
            let sx = x0 + 2 + Double(k * (cw + 1)), a = age(k), f = a >= 0 ? ez(a / 0.14) : 0
            if k >= taps { g.rect(sx, y0 + 2, Double(cw), 13, 0.12) }
            for u in 0..<cw {
                for v in 0..<13 {
                    let vis = a >= 0 && Double(u) < f * Double(cw) + 0.05
                    let x = vis ? sx + Double(u) + 0.5 : sx + 0.5, y = y0 + 2.5 + Double(v)
                    let front = !sealed && k == taps - 1 && u == cw - 1 && v == 6 && f > 0.98
                    g.fr(x, y, vis && !bolt(x, y) ? 0.88 + 0.12 * hit(a, 0.2) + shim(x) : 0, front ? 1 : 0)
                }
            }
        }
        // the gaps between cells fill once it is full
        for k in stride(from: 0, to: N - 1, by: 1) {
            let gx = x0 + 2 + Double(k * (cw + 1) + cw) + 0.5
            for v in 0..<13 {
                let y = y0 + 2.5 + Double(v), vis = sealed && since > 0.16 + abs(Double(v) - 6) * 0.012
                g.fr(gx, vis ? y : y0 + 8.5, vis && !bolt(gx, y) ? 0.9 + shim(gx) : 0)
            }
        }
        g.on(bx + 4, by + 5, sealed && since > 0.42 ? 1 : 0, 1)
        return MatrixStoryOut(
            flash: 0.08 * hit(since - 0.3, 0.15),
            glow: [
                MatrixGlow(x: x0 + Wd / 2, y: y0 + 8.5, r: 22, a: 0.3 * hit(since - 0.3, 0.45)),
                MatrixGlow(x: x0 + 2 + (Double(taps) - 0.5) * Double(cw + 1), y: y0 + 8.5, r: 6, a: sealed ? 0 : 0.16 * hit(lastAge(s), 0.2)),
            ]
        )
    }

    // ============================== 7. THE COUNT ==============================
    // 1.6 s after the seal the finished object becomes the session count; the last digit ticks up.

    static func mini(_ g: inout MatrixBoard, _ day: Int, _ x: Double, _ y: Double) {
        let X = x.rounded(.down), Y = y.rounded(.down)
        switch day {
        case 0:
            g.line(X - 7, Y + 3, X + 7, Y + 3, 0.6)
            for dy in -4...2 { for dx in -4...4 where dx * dx + (dy + 1) * (dy + 1) <= 17 { g.on(X + Double(dx), Y + Double(dy), 0.9, dx == 0 && dy == -4 ? 1 : 0) } }
            for (dx, dy) in [(0.0, -7.0), (-5, -5), (5, -5), (-7, -1), (7, -1)] { g.on(X + dx, Y + dy, 0.8) }
        case 1:
            for (ox, oy, w) in [(-8.0, 1.0, 8), (1, 1, 8), (-8, -3, 3), (-4, -3, 8), (5, -3, 4)] {
                for v in 0..<3 { for u in 0..<w { g.on(X + ox + Double(u), Y + oy + Double(v), 0.85, ox == -4 && u >= 3 && u < 5 && v == 1 ? 1 : 0) } }
            }
        case 2:
            g.rect(X - 8, Y - 4, 16, 9, 0.85)
            g.rect(X + 8, Y - 2, 1, 5, 0.85, true)
            for v in 0..<7 { for u in 0..<14 { g.on(X - 7 + Double(u), Y - 3 + Double(v), 0.85) } }
            g.on(X, Y, 1, 1)
        case 3:
            g.line(X - 11, Y, X + 11, Y, 0.8)
            for sd in [-1.0, 1.0] {
                for (o, h) in [(5.0, 9.0), (6, 9), (7, 7), (8, 7)] { g.line(X + sd * o, Y - (h - 1) / 2, X + sd * o, Y + (h - 1) / 2, 0.9) }
            }
            g.on(X, Y, 1, 1)
        case 4:
            for i in -3...3 {
                g.on(X - 6 + Double(i), Y, 0.9)
                g.on(X - 6, Y + Double(i), 0.9)
            }
            g.on(X - 6, Y, 1, 1)
            for j in -3...3 { g.on(X + 4, Y + Double(j), 0.9) }
            g.on(X + 3, Y - 2, 0.9)
            g.on(X + 3, Y + 3, 0.9)
            g.on(X + 5, Y + 3, 0.9)
        case 5:
            for yy in -6...6 {
                for xx in -6...6 {
                    let r = hypot(Double(xx), Double(yy))
                    if r >= 3.6 && r <= 5.6 { g.on(X + Double(xx), Y + Double(yy), 0.92) }
                }
            }
            g.on(X, Y - 5, 1, 1)
        default:
            for i in -5...5 {
                g.on(X + Double(i), Y - 6, 0.85)
                g.on(X + Double(i), Y + 6, 0.85)
            }
            for j in 0...5 {
                let w = 1 + Double(j) * 0.8, jd = Double(j)
                g.on(X - w, Y - jd, 0.5)
                g.on(X + w, Y - jd, 0.5)
                g.on(X - w, Y + jd, 0.5)
                g.on(X + w, Y + jd, 0.5)
                if j >= 1 && j <= 4 {
                    var xx = (X - w + 1).rounded(.up)
                    while xx < X + w {
                        g.on(xx, Y - jd, 0.85, j == 1 && xx == X ? 1 : 0)
                        xx += 1
                    }
                }
            }
        }
    }

    static func count(_ g: inout MatrixBoard, _ s: MatrixStoryContext) -> MatrixStoryOut {
        let a = s.since - 1.6, tick = a > 0.55
        let n = tick ? s.D.sessions : s.D.sessions - 1
        let fmt = String(repeating: "8", count: String(s.D.sessions).count)
        led(&g, String(n), fmt, s.cx, s.cy.rounded(.down) - 18, 3, 0.95 + 0.05 * hit(a - 0.55, 0.3), 0, 3)
        mini(&g, s.day, s.cx, s.cy.rounded(.down) + 11)
        return MatrixStoryOut(opts: MatrixDealOptions(stagger: 0.12, burst: 24), glow: [MatrixGlow(x: s.cx, y: s.cy - 8, r: 22, a: 0.2 * hit(a - 0.55, 0.4))])
    }

    // ============================== entry (mxStory) ==============================

    /// `mxStory(id, counted, s)`: draws the screen into `g` (reset by the caller, sized cols x rows,
    /// cap 1400) and returns its phase, deal options, flash and glows.
    public static func render(_ g: inout MatrixBoard, _ id: MatrixStoryScreen, counted: Bool, _ s: MatrixStoryContext) -> MatrixStoryOut {
        let age = { (k: Int) -> Double in k < s.tapTimes.count ? s.t - s.tapTimes[k] : -1 }
        if counted { return count(&g, s) }
        switch id {
        case .verified:
            // TODO: port VERIFIED[s.day]: vMon (seal rosette), vTue (padlock opens), vWed (heartbeat
            // writes the check), vThu, vFri, vSat, vSun. mxstory.ts "1. VERIFIED", BEAT_V = 0.75.
            return MatrixStoryOut()
        case .today:
            // TODO: port `today` (SES, HR table with MatrixSinHash.hash(i, 5), the session strip).
            return MatrixStoryOut()
        case .week:
            // TODO: port `week` (EARLIER per pos, the week's bars).
            return MatrixStoryOut()
        case .month:
            // TODO: port `month` (calendar cells, target pick lighting from pickAt).
            return MatrixStoryOut()
        case .far:
            // TODO: port the far screen: s.day == 3 ? fThu(g, s) : [fMon, fTue, fWed, fMon, fFri, fSat, fSun][s.day](g, s, D.day).
            return MatrixStoryOut()
        case .climax:
            switch s.day {
            case 2: return finWed(&g, s, age)
            default:
                // TODO: port FINISH[s.day]: finMon (sunGeo), finTue (wallSlots), finThu (barbell),
                // finFri (chevCells / plusOne), finSat (RING), finSun (glassGeo).
                return MatrixStoryOut()
            }
        }
    }
}

// MARK: - Flow model (app13.tsx overlay state)

@MainActor
@Observable
public final class MatrixStoryModel {
    public let day: Int
    public let pos: MatrixWeekPos
    public let monthPos: MatrixMonthPos
    public let dayData: MatrixDayData
    public let weekDone: Int
    public let weekToday: Int
    /// The month's first week of a month's first session: the month screen asks for a target.
    public let monthPick: Bool
    public let ids: [MatrixStoryScreen]
    public let copy: MatrixStoryCopy
    /// Dynamic camera (lean-in on taps and seal). Off under Reduce Motion regardless.
    public let dynamic: Bool

    public private(set) var idx = 0
    public private(set) var start: Double = 0
    public private(set) var tapTimes: [Double] = []
    public private(set) var sealT: Double?
    public private(set) var collapseAt: Double?
    public private(set) var picked = false
    public private(set) var pickAt: Double?

    @ObservationIgnored public var onLanded: (() -> Void)?
    @ObservationIgnored public var onFinished: (() -> Void)?
    @ObservationIgnored let haptics = HeroHapticScheduler()
    @ObservationIgnored private let epoch: Date
    @ObservationIgnored private var landedFired = false
    @ObservationIgnored private var finishedFired = false

    public init(day: Int, pos: MatrixWeekPos, monthPos: MatrixMonthPos, dayData: MatrixDayData, weekDone: Int, weekToday: Int, monthPick: Bool, copy: MatrixStoryCopy, dynamic: Bool = true, now: Date = Date()) {
        self.day = day
        self.pos = pos
        self.monthPos = monthPos
        self.dayData = dayData
        self.weekDone = weekDone
        self.weekToday = weekToday
        self.monthPick = monthPick
        self.ids = MatrixStoryConfig.screens(monthPos)
        self.copy = copy
        self.dynamic = dynamic
        // headroom so engine timestamps are positive from the first frame
        self.epoch = now.addingTimeInterval(-2)
        let t = now.timeIntervalSince(epoch)
        start = t
        haptics.reset(cues: Self.cues(for: ids[0], start: t), at: t)
    }

    public var N: Int { MatrixContext.taps(day: day, pos: pos) }
    public var screen: MatrixStoryScreen { ids[idx] }
    public var isLast: Bool { idx == ids.count - 1 }

    public func time(_ date: Date) -> Double { date.timeIntervalSince(epoch) }
    public func lt(_ t: Double) -> Double { t - start }
    public func settled(_ t: Double) -> Bool { lt(t) >= MatrixStoryConfig.cfg(screen).settle }
    public func since(_ t: Double) -> Double { sealT.map { t - $0 } ?? -1 }
    public func counted(_ t: Double) -> Bool { sealT != nil && since(t) > MatrixStoryConfig.countAfter }
    /// 0...1 progress of the collapse into the card.
    public func collapse(_ t: Double) -> Double { collapseAt.map { MX.cl((t - $0) / MatrixStoryConfig.collapseDuration) } ?? 0 }

    private static func cues(for id: MatrixStoryScreen, start: Double) -> [HapticCue] {
        MatrixStoryConfig.cfg(id).haptics.map { HapticCue(t: start + $0.t, kind: $0.kind) }
    }

    private func goTo(_ i: Int, start s: Double, now t: Double) {
        idx = i
        start = s
        haptics.reset(cues: Self.cues(for: ids[i], start: s), at: t)
    }

    /// app13.tsx `onOverlayTap`. `xFraction` is the tap's x / screen width.
    public func tap(xFraction: Double, at t: Double) {
        guard collapseAt == nil else { return }
        let settle = MatrixStoryConfig.cfg(screen).settle
        if xFraction < 0.22 && idx > 0 {
            haptics.playNow(.light)
            goTo(idx - 1, start: t - MatrixStoryConfig.cfg(ids[idx - 1]).settle, now: t)
            return
        }
        if isLast {
            sealTap(at: t)
            return
        }
        if screen == .month && monthPick && !picked {
            // the target buttons call `pickTarget`; a tap elsewhere accepts the default
            picked = true
            pickAt = t
            haptics.playNow(.heavy)
            return
        }
        if !settled(t) {
            // the first tap finishes this screen's animation
            haptics.playNow(.light)
            goTo(idx, start: t - settle, now: t)
            return
        }
        haptics.playNow(.medium)
        goTo(idx + 1, start: t, now: t)
    }

    /// The month target buttons (month screen in a month's first week).
    public func pickTarget(at t: Double) {
        let first = !picked
        picked = true
        pickAt = t
        haptics.playNow(first ? .heavy : .medium)
        if first { haptics.add(HapticCue(t: t + 0.12, kind: .success)) }
    }

    /// app13.tsx `onRockTap`: build the finish; the Nth tap seals it.
    private func sealTap(at t: Double) {
        guard sealT == nil else { return }
        let n = tapTimes.count + 1
        tapTimes.append(t)
        if n >= N {
            sealT = t
            haptics.playNow(.heavy)
            haptics.add(HapticCue(t: t + 0.07, kind: .heavy))
            haptics.add(HapticCue(t: t + 0.16, kind: .success))
            collapseAt = t + MatrixStoryConfig.collapseAfter(mp: monthPos, pos: pos)
        } else {
            haptics.playNow(n >= N - 1 ? .heavy : Double(n) > Double(N) / 2 ? .medium : .light)
        }
    }

    /// Once per frame (from `.onChange(of: timeline.date)`): haptics on the frame, collapse callbacks.
    public func advance(to t: Double) {
        if let c = collapseAt, t >= c {
            // the web stops screen haptics once the overlay leaves; the seal cues are already past
            haptics.isActive = false
        }
        haptics.tick(t)
        let cp = collapse(t)
        if !landedFired && cp >= 0.7 {
            landedFired = true
            onLanded?()
        }
        if !finishedFired && cp >= 1 {
            finishedFired = true
            onFinished?()
        }
    }
}

// MARK: - Runtime (engine, grid cache; not observable)

@MainActor
final class MatrixStoryRuntime {
    static let PITCH: Double = 21
    static let BOX_W: Double = 1080
    static let BOX_H: Double = 1920
    static let GY: Double = 900
    static let FOCUS_Y: Double = 880

    private var engine: MatrixEngine?
    private var board = MatrixBoard(width: 52, height: 92, cap: 1400)
    private var dims = (cols: 0, rows: 0)
    private var grid: (key: String, image: Image)?

    /// hero4/story4.tsx `fitComposition(vw, vh)`.
    static func composition(_ size: CGSize) -> CGSize {
        let vw = Double(size.width), vh = Double(size.height)
        guard vw > 0, vh > 0 else { return CGSize(width: BOX_W, height: BOX_H) }
        let a = vw / vh
        if a < BOX_W / BOX_H { return CGSize(width: BOX_W, height: JSMath.round(BOX_W / a / 2) * 2) }
        return CGSize(width: JSMath.round((BOX_H * a) / 2) * 2, height: BOX_H)
    }

    func render(_ ctx: inout GraphicsContext, size: CGSize, date: Date, model: MatrixStoryModel, reduceMotion: Bool, displayScale: CGFloat) {
        let comp = Self.composition(size)
        let w = Double(comp.width), h = Double(comp.height)
        let s0 = Double(size.width) / w
        guard s0 > 0, s0.isFinite else { return }
        let cols = Int((w / Self.PITCH).rounded(.up)), rows = Int((h / Self.PITCH).rounded(.up))
        let oy = (h - Self.BOX_H) / 2
        let cx = (w / 2 / Self.PITCH).rounded(.down) + 0.5
        let cy = ((oy + Self.GY) / Self.PITCH).rounded(.down) + 0.5

        if dims.cols != cols || dims.rows != rows || engine == nil {
            dims = (cols, rows)
            engine = MatrixEngine(n: 1400, cols: cols, rows: rows)
            board = MatrixBoard(width: cols, height: rows, cap: 1400)
            grid = nil
        }
        guard let engine else { return }

        let t = model.time(date)
        let lt = model.lt(t)
        let since = model.since(t)
        let counted = model.counted(t)
        let id = model.screen
        let tapAt = model.tapTimes.last

        ctx.scaleBy(x: s0, y: s0)
        // the board leans in a touch on entry, on each tap and on the seal; no shake
        let dz = model.dynamic && !reduceMotion
        if dz {
            var camS = 1 + 0.05 * (1 - MX.ez(lt / 0.7))
            if id == .climax, let tapAt, model.sealT == nil { camS += 0.012 * exp(-(t - tapAt) * 9) }
            if id == .climax, let sealT = model.sealT { camS += 0.025 * exp(-(t - sealT) * 5) }
            let px = w * 0.5, py = h * 0.47
            ctx.translateBy(x: px, y: py)
            ctx.scaleBy(x: camS, y: camS)
            ctx.translateBy(x: -px, y: -py)
        }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(.sRGB, red: 10 / 255, green: 10 / 255, blue: 11 / 255)))
        let pxScale = s0 * Double(displayScale)
        let gkey = "\(cols)x\(rows):\(Int((pxScale * 1000).rounded()))"
        if grid?.key != gkey, let cg = MatrixGridRenderer.makeImage(cols: cols, rows: rows, pitch: Self.PITCH, radius: 1.6, color: MatrixRGB(0xFFFFFF), alpha: 0.07, pxScale: pxScale) {
            grid = (gkey, Image(decorative: cg, scale: 1))
        }
        if let img = grid?.image {
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: Double(cols) * Self.PITCH, height: Double(rows) * Self.PITCH))
        }

        let sc = MatrixStoryContext(
            t: t, lt: lt, cx: cx, cy: cy, cols: cols, rows: rows, N: model.N, taps: model.tapTimes.count,
            tapTimes: model.tapTimes, tapAt: tapAt, sealT: model.sealT, since: since, D: model.dayData,
            day: model.day, pos: model.pos, weekDone: model.weekDone, weekToday: model.weekToday,
            pick: model.monthPick, picked: model.picked, pickAt: model.pickAt
        )
        board.reset()
        let mx = MatrixStoryScenes.render(&board, id, counted: counted, sc)
        let key = counted ? "count" : "\(id.rawValue)\(model.day):\(mx.phase ?? "")"

        // local light: a soft bloom behind the dots where the beat lands
        for gl in mx.glow where gl.a >= 0.01 {
            let X = gl.x * Self.PITCH, Y = gl.y * Self.PITCH, R = gl.r * Self.PITCH
            let grad = Gradient(colors: [Color.white.opacity(min(0.22, gl.a * 0.55)), Color.white.opacity(0)])
            ctx.fill(Path(CGRect(x: X - R, y: Y - R, width: 2 * R, height: 2 * R)), with: .radialGradient(grad, center: CGPoint(x: X, y: Y), startRadius: 0, endRadius: R))
        }
        engine.update(key: key, targets: board.out(), t: t, options: mx.opts ?? MatrixDealOptions(stagger: 0.25))
        engine.draw(in: ctx, ox: 0, oy: 0, pitch: Self.PITCH, ink: .white, coral: MatrixRGB.coral.color, radius: 7.4)

        // a full-screen flash only on the real peaks (the seal, the count)
        var fl = mx.flash
        if id == .climax && counted && since < 1.9 { fl += 0.1 * (1 - (since - 1.6) / 0.3) }
        if fl > 0.01 && !reduceMotion {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.white.opacity(min(0.25, fl))))
        }
    }
}

// MARK: - The view

/// Full-screen done flow. Present it as an overlay above the home screen (ignoring safe areas), not
/// as a fullScreenCover, so the collapse can fly into the card. Pass the card's frame in this view's
/// coordinate space as `cardFrame` for the exact web collapse; without it the overlay fades and shrinks.
public struct MatrixStoryView: View {
    public let model: MatrixStoryModel
    public var cardFrame: CGRect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var runtime = MatrixStoryRuntime()

    public init(model: MatrixStoryModel, cardFrame: CGRect? = nil) {
        self.model = model
        self.cardFrame = cardFrame
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation(minimumInterval: nil, paused: scenePhase != .active)) { tl in
                let t = model.time(tl.date)
                let cp = model.collapse(t)
                ZStack(alignment: .topLeading) {
                    Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, sz in
                        runtime.render(&ctx, size: sz, date: tl.date, model: model, reduceMotion: reduceMotion, displayScale: displayScale)
                    }
                    .accessibilityHidden(true)
                    MatrixStoryCopyLayer(model: model, t: t, size: size, reduceMotion: reduceMotion)
                }
                .modifier(CollapseModifier(cp: cp, size: size, cardFrame: cardFrame))
                .onChange(of: tl.date) { _, d in model.advance(to: model.time(d)) }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                guard size.width > 0 else { return }
                model.tap(xFraction: Double(loc.x / size.width), at: model.time(Date()))
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(model.isLast ? "Tap to build today’s finish" : "Tap to continue")
    }
}

/// app13.tsx: the overlay flies into the card. p = eio(cp); scale toward the card's width; clip to the
/// card's height around FOCUS_Y; fade over the last 28%.
private struct CollapseModifier: ViewModifier {
    let cp: Double
    let size: CGSize
    let cardFrame: CGRect?

    func body(content: Content) -> some View {
        let opacity = 1 - MX.cl((cp - 0.72) / 0.28)
        if cp <= 0 {
            content
        } else if let r = cardFrame, size.width > 0 {
            let vw = Double(size.width), vh = Double(size.height)
            let comp = MatrixStoryRuntime.composition(size)
            let s0 = vw / Double(comp.width)
            let p = MX.eio(cp)
            let k = Double(r.width) / vw
            let focusY = ((Double(comp.height) - MatrixStoryRuntime.BOX_H) / 2 + MatrixStoryRuntime.FOCUS_Y) * s0
            let sc = 1 + (k - 1) * p
            let cx = vw / 2 + (Double(r.midX) - vw / 2) * p
            let cy = focusY + (Double(r.midY) - focusY) * p
            let hh = Double(r.height) / k / 2
            let top = p * max(0, focusY - hh), bottom = p * max(0, vh - focusY - hh)
            content
                .mask {
                    RoundedRectangle(cornerRadius: (p * 24) / k)
                        .padding(.top, top)
                        .padding(.bottom, bottom)
                }
                .scaleEffect(sc, anchor: .topLeading)
                .offset(x: cx - (vw / 2) * sc, y: cy - focusY * sc)
                .opacity(opacity)
        } else {
            content
                .scaleEffect(1 - 0.08 * MX.eio(cp))
                .opacity(opacity)
        }
    }
}

// MARK: - Copy layer (story13m.tsx HTML side)

private struct MatrixStoryCopyLayer: View {
    let model: MatrixStoryModel
    let t: Double
    let size: CGSize
    let reduceMotion: Bool

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }
    private static func springFast(_ frame: Double, _ fps: Double, stiffness k: Double = 100, damping c: Double = 10, mass m: Double = 1) -> Double {
        if frame <= 0 { return 0 }
        let tt = frame / fps, w0 = (k / m).squareRoot(), zeta = c / (2 * (k * m).squareRoot())
        if zeta < 1 {
            let wd = w0 * (1 - zeta * zeta).squareRoot()
            return 1 - exp(-zeta * w0 * tt) * (cos(wd * tt) + ((zeta * w0) / wd) * sin(wd * tt))
        }
        return 1 - exp(-w0 * tt) * (1 + w0 * tt)
    }

    var body: some View {
        let comp = MatrixStoryRuntime.composition(size)
        let cw = Double(comp.width), ch = Double(comp.height)
        let s0 = Double(size.width) / cw
        let ox = (cw - MatrixStoryRuntime.BOX_W) / 2, oy = (ch - MatrixStoryRuntime.BOX_H) / 2
        let lt = model.lt(t), since = model.since(t)
        let id = model.screen
        let leaving = model.collapseAt.map { t >= $0 } ?? false
        let a = { (at: Double, d: Double) -> Double in Self.eo((lt - at) / d) }
        let ca = { (at: Double, d: Double) -> Double in Self.eo((since - at) / d) }
        let white = Color.white
        let dz = model.dynamic && !reduceMotion
        let climax = MatrixClimaxCopy.byDay[max(0, min(6, model.day))]
        let end = MatrixClimaxCopy.end(pos: model.pos, day: model.day)
        let taps = model.tapTimes.count, N = model.N
        let tapAt = model.tapTimes.last

        // design units (comp) -> points
        let u = { (v: Double) -> Double in v * s0 }

        let header: (eyebrow: String, title: String) = {
            if id == .climax {
                if model.sealT != nil { return (model.pos == .last ? "WEEK COMPLETE" : "SESSIONS", "") }
                return (model.pos == .last ? climax.lastEyebrow : climax.eyebrow, climax.title)
            }
            let h = model.copy.headers[id]
            return (h?.eyebrow ?? "", h?.title ?? "")
        }()

        ZStack(alignment: .topLeading) {
            // progress, one segment per screen
            HStack(spacing: u(12)) {
                ForEach(Array(model.ids.enumerated()), id: \.offset) { i, sid in
                    let fill = i < model.idx ? 1 : i > model.idx ? 0 : MX.cl(lt / MatrixStoryConfig.cfg(sid).settle)
                    Capsule().fill(white.opacity(0.18))
                        .overlay(alignment: .leading) {
                            GeometryReader { g in Capsule().fill(white).frame(width: g.size.width * fill) }
                        }
                        .frame(height: u(7))
                }
            }
            .frame(width: u(cw - 120))
            .offset(x: u(60), y: u(max(oy, 0) + 90))
            .opacity(leaving ? 0 : 1)

            // the header
            VStack(spacing: 0) {
                if !header.eyebrow.isEmpty {
                    Text(header.eyebrow)
                        .font(.system(size: u(30), weight: .bold))
                        .tracking((0.16 + (1 - a(0.1, 0.3)) * 0.3) * u(30))
                        .foregroundStyle(white.opacity(0.55))
                }
                if !header.title.isEmpty {
                    let rise = 1 - Self.springFast(lt * 30 - 5, 30, stiffness: 220, damping: 11)
                    let pop = dz ? 1 + 0.25 * exp(-lt * 6) * cos(lt * 14) : 1
                    Text(header.title)
                        .font(.system(size: u(120), weight: .heavy, design: .rounded))
                        .tracking(-0.03 * u(120))
                        .foregroundStyle(white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, u(12))
                        .offset(y: u(rise * 50))
                        .scaleEffect(pop)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: u(960))
            .offset(x: u(ox + 60), y: u(oy + 250))
            .opacity(a(0.1, 0.3))

            // the screen's caption (verified / week / month / far); TODO: the today stats and month picker
            if id != .climax, id != .today, let cap = model.copy.captions[id] {
                let at: Double = id == .verified ? 0.9 : id == .week ? 0.8 : id == .month ? 0.7 : 1.4
                let top: Double = id == .verified ? 1350 : id == .week ? 1280 : id == .month ? 1230 : 1340
                VStack(spacing: u(30)) {
                    MatrixRich.text(cap, size: u(40), weight: .medium, color: white.opacity(0.62), boldColor: white, boldWeight: .bold)
                    if let r = model.copy.research[id] {
                        MatrixRich.text(r, size: u(30), weight: .medium, color: white.opacity(0.42), boldColor: white, boldWeight: .bold)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: u(860))
                .offset(x: u(ox + 110), y: u(oy + top) + (1 - a(at, 0.4)) * u(20))
                .opacity(a(at, 0.4))
            }

            // the climax, before the seal: the instruction and one dot per tap
            if id == .climax && model.sealT == nil {
                VStack(spacing: u(40)) {
                    MatrixRich.text(climax.sub(N), size: u(40), weight: .medium, color: white.opacity(0.62), boldColor: white, boldWeight: .bold)
                        .multilineTextAlignment(.center)
                    HStack(spacing: u(16)) {
                        ForEach(0..<N, id: \.self) { k in
                            let pop = k == taps - 1 && tapAt != nil ? 1 + 0.4 * max(0, 1 - (t - (tapAt ?? t)) * 4) : 1
                            Circle()
                                .fill(k < taps ? white : .clear)
                                .overlay { if k >= taps { Circle().strokeBorder(white.opacity(0.4), lineWidth: u(3)) } }
                                .frame(width: u(30), height: u(30))
                                .scaleEffect(pop)
                        }
                    }
                }
                .frame(width: u(860))
                .offset(x: u(ox + 110), y: u(oy + 1300))
                .opacity(a(0.4, 0.4))
            }

            // the climax, after the seal: the end line and the week's tail
            if id == .climax && model.sealT != nil {
                VStack(spacing: u(24)) {
                    MatrixRich.text(climax.end, size: u(46), weight: .bold, color: white, boldColor: white, boldWeight: .bold)
                    MatrixRich.text("\(MatrixClimaxCopy.posTail(model.pos)) \(end.sub)", size: u(36), weight: .medium, color: white.opacity(0.62), boldColor: white, boldWeight: .bold)
                }
                .multilineTextAlignment(.center)
                .frame(width: u(860))
                .offset(x: u(ox + 110), y: u(oy + 1300) + (1 - ca(1.7, 0.4)) * u(20))
                .opacity(ca(1.7, 0.4))
            }

            // the foot: a hint, or on the last screen the button that fills with each tap
            Group {
                if !model.isLast {
                    let show = model.settled(t)
                    HStack(spacing: u(14)) {
                        Text(id == .month && model.monthPick && !model.picked ? "Pick a target" : "Tap to continue")
                            .font(.system(size: u(30), weight: .semibold))
                            .tracking(0.04 * u(30))
                        Image(systemName: "chevron.right")
                            .font(.system(size: u(22), weight: .bold))
                            .opacity(show ? 1 : 0)
                    }
                    .foregroundStyle(white.opacity(show ? 0.45 + 0.25 * sin(lt * 4) : 0))
                } else {
                    let fill = model.sealT != nil ? 1 : min(1, Double(taps) / Double(N))
                    let label = model.sealT != nil ? end.button : taps > 0 ? (taps >= N - 1 ? "One more" : climax.mid) : climax.idle
                    Text(label)
                        .font(.system(size: u(38), weight: .bold))
                        .foregroundStyle(Color(.sRGB, red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255))
                        .padding(.vertical, u(30))
                        .padding(.horizontal, u(80))
                        .background {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    white
                                    MatrixRGB.coral.color.frame(width: g.size.width * fill)
                                }
                            }
                        }
                        .clipShape(Capsule())
                        .opacity(a(0.4, 0.3))
                }
            }
            .frame(width: size.width, height: u(300))
            .offset(y: Double(size.height) - u(300))
            .opacity(leaving ? 0 : 1)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

// MARK: - Parity self-test for the story board

#if DEBUG
extension MatrixParity {
    /// Golden values from mxstory.ts (finWed and count on a 52 x 112 board, cx 25.5, cy 52.5).
    public static func runStory() -> [String] {
        var fail: [String] = []
        func ctx(t: Double, taps: [Double], sealT: Double?) -> MatrixStoryContext {
            MatrixStoryContext(t: t, lt: 3, cx: 25.5, cy: 52.5, cols: 52, rows: 112, N: 5, taps: taps.count, tapTimes: taps, tapAt: taps.last, sealT: sealT, since: sealT.map { t - $0 } ?? -1, D: MatrixDayData(day: 23, week: 3, sessions: 14), day: 2, pos: .middle, weekDone: 3, weekToday: 1, pick: false, picked: false, pickAt: nil)
        }
        let cases: [(String, MatrixStoryContext, Bool, Int, Double)] = [
            ("finWed 3 taps", ctx(t: 50, taps: [48, 48.6, 49.4], sealT: nil), false, 548, 40930.2730297),
            ("finWed sealed", ctx(t: 50.9, taps: [48, 48.6, 49.4, 49.8, 50.2], sealT: 50.2), false, 484, 36546.0007385),
            ("count", ctx(t: 52.6, taps: [48, 48.6, 49.4, 49.8, 50.2], sealT: 50.2), true, 365, 29348.8163033),
        ]
        for (name, s, counted, n, sum) in cases {
            var g = MatrixBoard(width: 52, height: 112, cap: 1400)
            _ = MatrixStoryScenes.render(&g, .climax, counted: counted, s)
            let out = g.out()
            if out.count != n { fail.append("\(name): \(out.count) targets, want \(n)") }
            let got = checksum(out)
            if abs(got - sum) > 1e-9 * max(1, abs(sum)) { fail.append("\(name) checksum: got \(got), want \(sum)") }
        }
        return fail
    }
}
#endif
