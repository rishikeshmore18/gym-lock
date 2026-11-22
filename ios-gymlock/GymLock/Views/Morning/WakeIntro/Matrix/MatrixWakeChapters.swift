//
//  MatrixWakeChapters.swift
//  GymLock · Wake intro, Matrix concepts (native port)
//
//  Port of web/morning2/mx2.ts (what the full-screen board shows on each frame) plus the pieces of
//  web/morning2/board.ts (geometry, cardCell, targets, ledFlip), plan.ts (timeline in frames, beatAt,
//  idleT) and matrix.tsx (mxCam) that the chapters depend on.
//
//  Statement order, call counts and arguments follow the TypeScript one for one: dot identity depends
//  on it (PORTING-GUIDE.md section 5). Everything here is a pure function of (frame, facts, timeline).
//
//  Units: board cells. The full-screen board is 52 x 113 cells at 7.5 pt on the web's 390 x 844 page;
//  the home card's board is 38 x 35 cells at 12.5 card units, mapped into the same space by `cardCell`.
//  Time: web frames at 30 fps (`f`); chapter-local time `lt` in seconds.
//

import Foundation

// MARK: - Geometry (board.ts, plan.ts)

public enum MatrixWakeGeo {
    public static let FPS: Double = 30
    /// The web page the prototype was designed on.
    public static let W: Double = 390
    public static let H: Double = 844
    public static let PITCH: Double = 7.5
    public static let COLS = 52 // ceil(390 / 7.5)
    public static let ROWS = 113 // ceil(844 / 7.5)
    /// The home card's board.
    public static let CCOLS = 38, CROWS = 35
    public static let CPITCH: Double = 12.5, COX: Double = 492, COY: Double = 26
    /// The home hero card's slot on the web page (1000 : 488).
    public static let CARD_X: Double = 18, CARD_Y: Double = 108, CARD_W: Double = 354
    public static let CARD_H: Double = (354 * 488) / 1000
    public static let CARD_S: Double = 354.0 / 1000
    /// The settled page loops a 12 s idle; every idle motion divides it (plan.ts IDLE).
    public static let IDLE_FRAMES: Double = 360
    /// Engine pool size (board.ts N_DOTS) and target caps.
    public static let N_DOTS = 1500
    public static let FULL_CAP = 1400
    public static let CARD_CAP = 720

    /// board.ts `cardCell(i, j)`: a card board cell in full-screen board units.
    @inline(__always)
    public static func cardCell(_ i: Double, _ j: Double) -> (x: Double, y: Double) {
        ((CARD_X + (COX + (i + 0.5) * CPITCH) * CARD_S) / PITCH, (CARD_Y + (COY + (j + 0.5) * CPITCH) * CARD_S) / PITCH)
    }
}

// MARK: - Inputs

/// The facts the dots need (model.ts `facts()` subset), clamped like the web.
public struct MatrixWakeFacts: Equatable, Sendable {
    public enum Mission: Equatable, Sendable { case steps, bag, water, shoe }
    /// LED gym time, "h:mm".
    public var time: String
    /// LED leave-by time, or nil (the web's empty string).
    public var leave: String?
    public var mission: Mission
    /// Step count when `mission == .steps` (1...40), else 0.
    public var steps: Int
    public var goal: Int
    public var done: Int
    public var day: Int
    public var streak: Int

    public init(time: String, leave: String?, mission: Mission, steps: Int, goal: Int, done: Int, day: Int, streak: Int, isFirst: Bool = false) {
        self.time = MatrixWakeFacts.ledClock(time) ?? time
        if let l = leave, let c = MatrixWakeFacts.ledClock(l) { self.leave = c } else { self.leave = nil }
        self.mission = mission
        self.steps = mission == .steps ? min(40, max(1, steps)) : 0
        let g = min(7, max(1, goal))
        self.goal = g
        self.done = isFirst ? 0 : min(g, max(0, done))
        self.day = isFirst ? 1 : min(999, max(1, day))
        self.streak = isFirst ? 0 : min(999, max(0, streak))
    }

    /// model.ts `clock()`: "07:05" -> "7:05"; nil unless the string is h:mm or hh:mm.
    public static func ledClock(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let h = parts[0], m = parts[1]
        guard (1...2).contains(h.count), m.count == 2,
              h.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
              m.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
              let hv = Int(h) else { return nil }
        return "\(hv):\(m)"
    }

    /// "h:mm" from a Date in the device calendar (12-hour, as the app shows times on the board).
    public static func ledClock(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        let h24 = c.hour ?? 0, mm = c.minute ?? 0
        let h = h24 % 12 == 0 ? 12 : h24 % 12
        return "\(h):\(mm < 10 ? "0" : "")\(mm)"
    }
}

public enum MatrixWakeBeat: Equatable, Sendable { case greet, commit, leave, mission, day, week }

/// plan.ts `Plan` in web frames (30 fps). Built from the shared WakePlan (seconds) by the stage.
public struct MatrixWakeTimeline: Equatable, Sendable {
    public struct Beat: Equatable, Sendable {
        public var id: MatrixWakeBeat
        public var at: Double
        public var end: Double
        public var i: Int
        public init(id: MatrixWakeBeat, at: Double, end: Double, i: Int) { self.id = id; self.at = at; self.end = end; self.i = i }
    }
    public var beats: [Beat]
    public var condense: Double
    public var land: Double
    public var wipe0: Double
    public var wipe1: Double
    public var intro: Double
    public var rm: Bool

    public init(beats: [Beat], condense: Double, land: Double, wipe0: Double, wipe1: Double, intro: Double, rm: Bool) {
        self.beats = beats; self.condense = condense; self.land = land; self.wipe0 = wipe0; self.wipe1 = wipe1; self.intro = intro; self.rm = rm
    }

    /// seconds -> frames, snapped to the frame grid when within 1e-6 (so 0.2 s is exactly frame 6).
    public static func frames(_ s: Double) -> Double {
        let f = s * MatrixWakeGeo.FPS
        let r = f.rounded()
        return abs(f - r) < 1e-6 ? r : f
    }

    /// plan.ts `beatAt`: the chapter on screen at frame f (nil once condensing).
    public func beatAt(_ f: Double) -> Beat? {
        if f >= condense { return nil }
        guard var b = beats.first else { return nil }
        for x in beats where f >= x.at { b = x }
        return b
    }

    /// plan.ts `idleT`: seconds into the idle loop, continuous across the seam.
    public func idleT(_ f: Double) -> Double {
        let I = MatrixWakeGeo.IDLE_FRAMES
        return MatrixWakeJS.rem(MatrixWakeJS.rem(f - intro, I) + I, I) / MatrixWakeGeo.FPS
    }
}

public enum MatrixWakeVariant: Equatable, Sendable {
    /// Matrix A (plan): greet, commit, leave, mission.
    case a
    /// Matrix B (progress): greet, commit, day, week.
    case b
}

/// One frame's board output (board.ts `Frame` minus the boards, which the caller owns).
public struct MatrixWakeFrameOut: Equatable, Sendable {
    public var key: String
    public var opts: MatrixWakeDealOptions?
    public var flash: Double
    public var hasCard: Bool
}

// MARK: - The scene

public struct MatrixWakeScene: Equatable, Sendable {
    public var facts: MatrixWakeFacts
    public var timeline: MatrixWakeTimeline
    public var variant: MatrixWakeVariant

    public init(facts: MatrixWakeFacts, timeline: MatrixWakeTimeline, variant: MatrixWakeVariant) {
        self.facts = facts; self.timeline = timeline; self.variant = variant
    }

    /// Fresh boards with the web's sizes and caps.
    public static func makeBoards() -> (full: MatrixWakeBoard, card: MatrixWakeBoard) {
        (MatrixWakeBoard(width: MatrixWakeGeo.COLS, height: MatrixWakeGeo.ROWS, cap: MatrixWakeGeo.FULL_CAP),
         MatrixWakeBoard(width: MatrixWakeGeo.CCOLS, height: MatrixWakeGeo.CROWS, cap: MatrixWakeGeo.CARD_CAP))
    }

    /// mx2.ts `mxFrame(f, c)`. Resets and fills both boards.
    public func frame(_ f: Double, full: inout MatrixWakeBoard, card: inout MatrixWakeBoard) -> MatrixWakeFrameOut {
        full.reset()
        card.reset()
        let F = facts, P = timeline
        typealias C = MatrixWakeChapters
        guard let b = P.beatAt(f) else {
            // condense: every dot flies into the home card's board
            let t = f >= P.intro ? P.idleT(f) : (f - P.intro) / 30
            C.cardArt(&card, variant, F, t, MXW.cl((f - P.land + 4) / 8))
            return MatrixWakeFrameOut(key: "card", opts: MatrixWakeDealOptions(stagger: 0.1), flash: 0, hasCard: true)
        }
        // Reduce Motion: each chapter is shown finished, no build-up
        let lt = P.rm ? 6 : (f - b.at) / 30
        let idle = lt
        switch b.id {
        case .greet:
            C.greet(&full, lt)
            return MatrixWakeFrameOut(key: "greet", opts: MatrixWakeDealOptions(stagger: 0), flash: 0, hasCard: false)
        case .commit:
            let flip = MXW.ez((lt - 0.12) / 0.42)
            C.commitBoard(&full, F, nil, F.time, flip, MXW.ez((lt - 0.05) / 0.3))
            return MatrixWakeFrameOut(key: "commit", opts: MatrixWakeDealOptions(stagger: 0.3, burst: 16), flash: 0.12 * C.hit(lt - 0.5, 0.12), hasCard: false)
        case .leave:
            // the board turns over from the gym time to the leave time, in place; the track builds under it
            let flip = F.leave != nil ? MXW.ez((lt - 0.08) / 0.4) : 1
            C.commitBoard(&full, F, F.time, F.leave ?? F.time, flip, 1 - MXW.ez(lt / 0.3))
            C.track(&full, lt, F, idle)
            return MatrixWakeFrameOut(key: "commit", opts: nil, flash: 0, hasCard: false)
        case .mission:
            if F.mission == .steps { C.footprints(&full, lt, F) } else { C.missionIcon(&full, lt, F) }
            return MatrixWakeFrameOut(key: "mission", opts: MatrixWakeDealOptions(stagger: 0.3), flash: 0, hasCard: false)
        case .day:
            let n = C.runGrid(&full, lt, F)
            // the count rolls with the fill
            let shown = max(1, min(F.day, n))
            C.ledFlip(&full, nil, String(F.day > 66 && lt > 1.75 ? F.day : shown), C.CX, 76, 2, MXW.ez((lt - 0.3) / 0.3), 1, 0.08)
            let todayK = min(66, F.day) - 1
            C.ripple(&full, C.GRID_X0 + Double(todayK % 11) * C.GRID_STEP + 1.5, C.GRID_Y0 + Double(todayK / 11) * C.GRID_STEP + 1.5, 2, 10, lt - 1.75, 0.6, 16)
            return MatrixWakeFrameOut(key: "day", opts: MatrixWakeDealOptions(stagger: 0.32, burst: 12), flash: 0.1 * C.hit(lt - 1.75, 0.12), hasCard: false)
        case .week:
            C.weekDiscs(&full, lt, F, idle)
            return MatrixWakeFrameOut(key: "week", opts: MatrixWakeDealOptions(stagger: 0.3), flash: 0, hasCard: false)
        }
    }

    /// The frame's flash at a continuous frame time (same formulas as `frame`, no board work).
    public func flash(_ f: Double) -> Double {
        let P = timeline
        guard !P.rm, let b = P.beatAt(f) else { return 0 }
        let lt = (f - b.at) / 30
        switch b.id {
        case .commit: return 0.12 * MatrixWakeChapters.hit(lt - 0.5, 0.12)
        case .day: return 0.1 * MatrixWakeChapters.hit(lt - 1.75, 0.12)
        default: return 0
        }
    }

    /// matrix.tsx `mxCam`: the board's camera (a punch-in when a chapter lands, a slow settle on the greeting).
    public func cam(_ f: Double) -> Double {
        let P = timeline
        if P.rm { return 1 }
        guard let b = P.beatAt(f) else { return 1 }
        let lt = (f - b.at) / 30
        func punch(_ at: Double, _ k: Double) -> Double {
            let a = lt - at
            return a > 0 ? k * (a / 0.08) * exp(1 - a / 0.08) : 0
        }
        switch b.id {
        case .greet: return 1.05 - 0.05 * MXW.eio(lt / 2.2)
        case .commit: return 1 + punch(0.48, 0.055)
        case .day: return 1 + punch(1.75, 0.03)
        case .week: return 1 + punch(0.3, 0.02)
        default: return 1
        }
    }

    /// board.ts `targets(fr)`: full-screen targets as they are, card cells remapped (ids + 5,000,000).
    public static func targets(full: MatrixWakeBoard, card: MatrixWakeBoard, hasCard: Bool, into out: inout ContiguousArray<MatrixWakeTarget>) {
        out.removeAll(keepingCapacity: true)
        full.appendOut(to: &out, limit: full.cap) { $0 }
        if hasCard {
            card.appendOut(to: &out, limit: card.cap) { q in
                let p = MatrixWakeGeo.cardCell(q.x - 0.5, q.y - 0.5)
                return MatrixWakeTarget(x: p.x, y: p.y, b: q.b, c: q.c, id: 5_000_000 + q.id)
            }
        }
    }
}

// MARK: - Chapters (mx2.ts)

public enum MatrixWakeChapters {
    static let TAU = MXW.TAU
    static let CX: Double = 26
    static let COLS = MatrixWakeGeo.COLS
    static let ROWS = MatrixWakeGeo.ROWS

    // ---------- shared pieces ----------
    /// the greeting's horizon row
    public static let HZ: Double = 78
    /// the morning track row
    public static let TRACK: Double = 93
    public static let NODES: [Double] = [6, 19, 33, 46]
    /// top row of the big LED time
    public static let TIME_Y: Double = 65
    public static let GRID_X0: Double = 4, GRID_Y0: Double = 44, GRID_STEP: Double = 4, GRID_BLK: Double = 3
    public static let WEEK_ROW: Double = 66
    /// the LED count beside the footprints
    public static let STEP_COUNTER = (cx: 38.0, y: 64.0)

    @inline(__always) static func ez5(_ x: Double) -> Double { 1 - pow(1 - MXW.cl(x), 5) }
    @inline(__always) static func hit(_ a: Double, _ d: Double = 0.25) -> Double { a >= 0 ? exp(-a / d) : 0 }

    public struct WeekGeom: Sendable {
        public let n: Int
        public let r: Double
        public let s: Double
        public func x(_ k: Int) -> Double { MatrixWakeChapters.CX - (s * Double(n - 1)) / 2 + s * Double(k) }
    }
    public static func weekGeom(_ n: Int) -> WeekGeom {
        let r = n <= 4 ? 4.5 : n <= 5 ? 3.9 : 3.1
        let s = min(12, 44 / Double(max(1, n - 1)))
        return WeekGeom(n: n, r: r, s: s)
    }

    static let SUN_PTS: [(Double, Double)] = {
        var o: [(Double, Double)] = []
        for y in -12...12 {
            for x in -12...12 where Double(x * x + y * y) <= 12.2 * 12.2 { o.append((Double(x), Double(y))) }
        }
        return o
    }()

    /// a ring of cells; dashed draws every other step (the app's planned-day marker is dashed)
    static func ringCells(_ g: inout MatrixWakeBoard, _ cx: Double, _ cy: Double, _ r: Double, _ b: Double, _ dash: Bool = false, _ c: Int = 0) {
        let n = max(10, Int(MatrixWakeJS.round(TAU * r * 1.3)))
        for i in 0..<n {
            if dash && (i / 2) % 2 != 0 { continue }
            let a = (Double(i) / Double(n)) * TAU
            g.on(cx + sin(a) * r, cy - cos(a) * r, b, c)
        }
    }

    static let FLAME = MatrixWakePixels(["...#.....", "...##....", "..###....", "..####.#.", ".#####.##", ".########", "#########", "####.####", "###...###", "###...###", ".###.###.", "..#####.."])
    static let FLAME_S = MatrixWakePixels(["..#..", ".##..", ".###.", "####.", "#####", "##.##", "#...#", ".###."])

    /// a lit pixel flame: a session that counted
    static func flameGlyph(_ g: inout MatrixWakeBoard, _ cx: Double, _ cy: Double, _ big: Bool, _ b: Double) {
        let F = big ? FLAME : FLAME_S
        g.glyph(F, MatrixWakeJS.round(cx - Double(F.firstWidth) / 2), MatrixWakeJS.round(cy - Double(F.height) / 2 - 0.5), 1, b)
    }

    /// a ring of free dots thrown out from (x, y) when a = 0; always pushed, dark when idle
    static func ripple(_ g: inout MatrixWakeBoard, _ x: Double, _ y: Double, _ r0: Double, _ r1: Double, _ a: Double, _ d: Double, _ n: Int, _ b: Double = 0.6) {
        let live = a >= 0 && a < d
        let p = live ? MXW.ez(a / d) : 0
        for i in 0..<max(0, n) {
            let an = (Double(i) / Double(n)) * TAU
            let r = MXW.lerp(r0, r1, p)
            g.fr(x + sin(an) * r, y - cos(an) * r, live ? b * (1 - a / d) : 0)
        }
    }

    /// a diagonal band of light crossing the art once every `per` seconds (calm idle)
    static func sheen(_ x: Double, _ y: Double, _ t: Double, _ per: Double, _ span: Double = 60, _ w: Double = 5) -> Double {
        let u = (MatrixWakeJS.rem(MatrixWakeJS.rem(t, per) + per, per) / per) * (2 * span + 6 * w) - span - 3 * w
        let d = x + y * 0.5 - u
        return exp(-(d * d) / (w * w))
    }

    // ---------- board.ts ledFlip ----------

    /// LED digits, each row of the glyph box switching from `from` to `to` as `flip` passes it (a
    /// departure board turning over); unlit font cells dim.
    public static func ledFlip(_ g: inout MatrixWakeBoard, _ from: String?, _ to: String, _ cx: Double, _ y: Double, _ scale: Double, _ flip: Double, _ b: Double, _ dim: Double, _ coralIdx: Int = -1) {
        let midY = y + 3.5 * scale
        let cut = y + flip * (7 * scale + 2)
        if let from {
            put(&g, lay(from, cx, y, scale, dim, coralIdx), lit: true, keepBelow: cut - 1, keepAbove: nil, edgeAt: -99, b: b, dim: dim, midY: midY)
        } else {
            put(&g, lay(to, cx, y, scale, dim, coralIdx), lit: false, keepBelow: cut - 1, keepAbove: nil, edgeAt: -99, b: b, dim: dim, midY: midY)
        }
        put(&g, lay(to, cx, y, scale, dim, coralIdx), lit: true, keepBelow: nil, keepAbove: cut, edgeAt: cut, b: b, dim: dim, midY: midY)
    }

    private static func lay(_ s: String, _ cx: Double, _ y: Double, _ scale: Double, _ dim: Double, _ coralIdx: Int) -> [MatrixWakeLED.Pixel] {
        MatrixWakeLED.text(s, MatrixWakeJS.round(cx - MatrixWakeLED.textWidth(s, scale: scale) / 2), y, dim: dim, scale: scale, coral: coralIdx >= 0 ? coralIdx : -1)
    }

    /// `keepBelow`: keep yy >= value; `keepAbove`: keep yy < value.
    private static func put(_ g: inout MatrixWakeBoard, _ pts: [MatrixWakeLED.Pixel], lit: Bool, keepBelow: Double?, keepAbove: Double?, edgeAt: Double, b: Double, dim: Double, midY: Double) {
        for q in pts {
            if let kb = keepBelow, !(q.y >= kb) { continue }
            if let ka = keepAbove, !(q.y < ka) { continue }
            let on = q.b == 1 && lit
            let edge = abs(q.y - edgeAt) < 1.6 ? 1.2 : 1
            // coral is one mark: the lower dot of the colon
            g.on(q.x - 0.5, q.y - 0.5, on ? min(1, b * edge) : dim, on && q.c != 0 && q.y > midY ? 1 : 0)
        }
    }

    // ---------- chapters ----------

    static func greet(_ g: inout MatrixWakeBoard, _ lt: Double) {
        // the board powers on: one scan line runs down the screen
        if lt < 0.55 {
            let r = (MXW.ez(lt / 0.55) * Double(ROWS + 4)).rounded(.down)
            for x in 0..<COLS {
                g.on(Double(x), r, 0.45)
                g.on(Double(x), r - 1, 0.2)
            }
        }
        // the horizon draws out from the centre
        let hw = 23 * MXW.ez((lt - 0.15) / 0.5)
        var x = MatrixWakeJS.round(CX - hw)
        while x < CX + hw {
            g.on(x, HZ, 0.5)
            x += 1
        }
        // the sun rises out of it (free dots: it glides)
        let rise = MXW.ez((lt - 0.25) / 1.35)
        let cy = HZ + 14 - 17 * rise
        for (dx, dy) in SUN_PTS {
            let y = cy + dy
            g.fr(CX + dx, y, y < HZ - 0.4 ? 1 : 0)
        }
        // rays: sixteen spokes that grow and turn very slowly
        let grow = MXW.ez((lt - 0.7) / 0.9)
        for i in 0..<16 {
            let a = (Double(i) / 16) * TAU + lt * 0.07
            for k in 0..<4 {
                let rr = 16 + Double(k) * 3.2
                let x = CX + sin(a) * rr, y = cy - cos(a) * rr
                let on = grow * 4 > Double(k) + 0.2
                g.fr(x, y, on && y < HZ - 0.6 ? (i % 2 != 0 ? 0.5 : 0.95) * (1 - Double(k) * 0.12) : 0)
            }
        }
        // light on the water under it
        let refl: [Double] = [22, 16, 10, 5]
        for (k, w) in refl.enumerated() {
            let yy = HZ + 3 + Double(k) * 3
            let b = (0.45 - Double(k) * 0.08) * rise
            var xx = MatrixWakeJS.round(CX - w)
            while xx < CX + w {
                g.on(xx, yy, b)
                xx += k % 2 != 0 ? 2 : 1
            }
        }
    }

    static func commitBoard(_ g: inout MatrixWakeBoard, _ F: MatrixWakeFacts, _ fromTime: String?, _ toTime: String, _ flip: Double, _ dumb: Double) {
        // the gym mark above the time
        if dumb > 0.02 { g.glyph(MXW.dumbbell, CX - 11, TIME_Y - 14, 2, dumb) }
        // the colon's lower dot is coral while the time is the commitment; on the plan it moves to you
        let colon = fromTime == nil ? (toTime.unicodeScalars.firstIndex(of: ":").map { toTime.unicodeScalars.distance(from: toTime.unicodeScalars.startIndex, to: $0) } ?? -1) : -1
        ledFlip(&g, fromTime, toTime, CX, TIME_Y, 2, flip, 1, 0.1, colon)
    }

    private static let YOU: [(Double, Double)] = [(0, 0), (1, 0), (0, 1), (1, 1)]

    static func track(_ g: inout MatrixWakeBoard, _ lt: Double, _ F: MatrixWakeFacts, _ idle: Double) {
        let p = MXW.ez((lt - 0.3) / 0.8)
        let x1 = MXW.lerp(NODES[0], NODES[3], p)
        var x = NODES[0]
        while x <= x1 {
            g.on(x, TRACK, 0.38)
            x += 1
        }
        for (k, nx) in NODES.enumerated() {
            let on = x1 >= nx - 0.5
            if !on { continue }
            let pop = MXW.ez((lt - 0.3 - Double(k) * 0.2) / 0.25)
            if k == 0 { g.disc(nx + 0.5, TRACK + 0.5, 2.7, pop) } else { ringCells(&g, nx + 0.5, TRACK + 0.5, 2.6, (k == 2 ? 1 : 0.7) * pop) }
        }
        // the leave stop hangs from the time: a dotted stem
        if F.leave != nil {
            let st = MXW.ez((lt - 0.9) / 0.4)
            var y = TIME_Y + 16
            while y < TIME_Y + 16 + (TRACK - 3 - TIME_Y - 16) * st {
                g.on(NODES[2], y, 0.45)
                y += 2
            }
        }
        // you: a coral dot on the track, just out of "up", heading for the next stop
        let go = MXW.ez((lt - 1.0) / 1.0)
        let yx = NODES[0] + 4 + (NODES[1] - NODES[0] - 7) * go + sin(idle * TAU * 0.25) * 0.35 * go
        let vis: Double = lt > 0.9 ? 1 : 0
        for (dx, dy) in YOU { g.fr(yx + dx - 0.5, TRACK - 0.5 + dy, vis, 1) }
    }

    // footprints from above, toes first (rows reversed like the TS `.reverse()`)
    static let FOOT_L = MatrixWakePixels([".#.", "...", "###", "###", "##."])
    static let FOOT_R = MatrixWakePixels([".#.", "...", "###", "###", ".##"])

    static func footprints(_ g: inout MatrixWakeBoard, _ lt: Double, _ F: MatrixWakeFacts) {
        let N = min(24, max(4, F.steps))
        let Nd = Double(N)
        // a straight, even march down the left half: one print every 3 rows, left and right alternating
        let step = min(3, 60 / Nd), top: Double = 40, cx: Double = 15
        let lit = min(N, Int((Nd * MXW.cl((lt - 0.4) / 1.35)).rounded(.down)) + (lt > 0.4 ? 1 : 0))
        for k in 0..<N {
            let left = k % 2 == 0
            let R = left ? FOOT_L : FOOT_R
            let x0 = left ? cx - 4 : cx + 1, y0 = MatrixWakeJS.round(top + Double(k) * step)
            let on = k < lit, cur = k == lit - 1
            for (j, row) in R.rows.enumerated() {
                for (i, ch) in row.enumerated() where ch == MatrixWakePixels.hash {
                    // the newest print's toes are coral: you, now
                    let toe = j == 4 && cur && (left ? i < 2 : i > 0)
                    g.on(x0 + Double(i), y0 + Double(j), on ? 1 : 0.16, toe ? 1 : 0)
                }
            }
        }
        // the count, on the board's own LED digits, rolling with each print. The board draws at most
        // 24 prints, but the count is the mission's real target, so it lands on F.steps.
        let count = N == F.steps ? lit : Int((Double(lit) * Double(F.steps) / Nd).rounded())
        ledFlip(&g, nil, String(count), STEP_COUNTER.cx, STEP_COUNTER.y, 2, MXW.ez((lt - 0.2) / 0.3), 1, 0.08)
    }

    // a sneaker, side on, toe to the right; the coral is the pull tab at the heel
    static let SNEAKER = MatrixWakePixels([
        "....o######.........",
        "....#######.........",
        "....##+#+##.........",
        "....#########.......",
        "...############.....",
        "..###############...",
        ".#################..",
        "###################.",
        "####################",
        "++++++++++++++++++++",
    ])

    static func missionIcon(_ g: inout MatrixWakeBoard, _ lt: Double, _ F: MatrixWakeFacts) {
        let isShoe = F.mission != .bag
        let R = isShoe ? SNEAKER : MXW.bag
        let s: Double = isShoe ? 2 : 4
        let w = Double(R.firstWidth) * s, h = Double(R.height) * s
        let x0 = MatrixWakeJS.round(CX - w / 2), y0 = MatrixWakeJS.round(70 - h / 2)
        let sweep = MXW.ez((lt - 0.35) / 1.0) * (w + 4)
        for (j, row) in R.rows.enumerated() {
            for (i, ch) in row.enumerated() {
                if ch != MatrixWakePixels.hash && ch != MatrixWakePixels.coral { continue }
                var v = 0.0
                while v < s {
                    var u = 0.0
                    while u < s {
                        let x = x0 + Double(i) * s + u
                        let on = x - x0 < sweep
                        g.on(x, y0 + Double(j) * s + v, on ? 1 : 0.16, ch == MatrixWakePixels.coral && on && u > 0 && u < 3 && v > 0 && v < 3 ? 1 : 0)
                        u += 1
                    }
                    v += 1
                }
            }
        }
    }

    /// Returns `n` of the TS `{n, todayK}`.
    static func runGrid(_ g: inout MatrixWakeBoard, _ lt: Double, _ F: MatrixWakeFacts, _ settledTo: Int = -1) -> Int {
        let lived = min(66, F.day - 1)
        let todayK = min(66, F.day) - 1
        let n = settledTo >= 0 ? lived : Int((Double(lived) * ez5((lt - 0.35) / 1.3)).rounded(.down))
        let todayOn = settledTo >= 0 || lt > 1.75
        for k in 0..<66 {
            let bx = GRID_X0 + Double(k % 11) * GRID_STEP, by = GRID_Y0 + Double(k / 11) * GRID_STEP
            let isToday = k == todayK && F.day <= 66
            let on = k < n || (F.day > 66 && k < n + 1)
            let b = isToday ? (todayOn ? 1 : 0.16) : on ? 1 : 0.16
            g.rect(bx, by, GRID_BLK, GRID_BLK, b, true, isToday && todayOn ? 1 : 0)
        }
        return n + (todayOn ? 1 : 0)
    }

    static func weekDiscs(_ g: inout MatrixWakeBoard, _ lt: Double, _ F: MatrixWakeFacts, _ idle: Double) {
        let n = F.goal, W = weekGeom(n)
        for k in 0..<max(0, n) {
            let x = W.x(k), y = WEEK_ROW
            // every target exists from the first frame so the dots fly straight into it; it brightens as it pops
            let pop = 0.35 + 0.65 * MXW.ez((lt - 0.25 - Double(k) * 0.12) / 0.3)
            if k < F.done {
                flameGlyph(&g, x, y, n <= 5, pop)
            } else if k == F.done {
                ringCells(&g, x, y, W.r, pop)
                let br = 0.8 + 0.2 * cos(idle * TAU * 0.25)
                g.rect(MatrixWakeJS.round(x - 1), MatrixWakeJS.round(y - 1), 2, 2, pop * br, true, 1)
            } else {
                ringCells(&g, x, y, W.r, 0.42 * pop, true)
            }
        }
    }

    // ---------- the home card's board (38 x 35; art in columns 8 to 37) ----------

    private static let CARD_NODES: [Double] = [10, 18, 27, 35]

    static func cardArt(_ g: inout MatrixWakeBoard, _ variant: MatrixWakeVariant, _ F: MatrixWakeFacts, _ t: Double, _ arrive: Double) {
        func sh(_ x: Double, _ y: Double) -> Double { 0.82 + 0.18 * sheen(x, y, t, 6) }
        switch variant {
        case .a:
            // the gym, and the morning track under it with you on it
            let R = MXW.dumbbell
            for (j, row) in R.rows.enumerated() {
                for (i, ch) in row.enumerated() where ch == MatrixWakePixels.hash {
                    let bx = 12 + Double(i) * 2, by = 6 + Double(j) * 2
                    for v in 0..<2 {
                        for u in 0..<2 { g.on(bx + Double(u), by + Double(v), sh(bx, by)) }
                    }
                }
            }
            for x in 10...35 { g.on(Double(x), 24, 0.35) }
            for (k, x) in CARD_NODES.enumerated() {
                if k == 0 { g.disc(x + 0.5, 24.5, 1.8, sh(x, 24)) } else { ringCells(&g, x + 0.5, 24.5, 1.9, (k == 2 ? 1 : 0.65) * sh(x, 24)) }
            }
            if F.leave != nil {
                var y: Double = 18
                while y < 22 {
                    g.on(27, y, 0.4)
                    y += 2
                }
            }
            let br = 0.75 + 0.25 * cos(t * TAU * 0.25)
            g.on(13, 24, br * arrive, 1)
        case .b:
            // the run (11 x 6), today coral; the week under it
            let lived = min(66, F.day - 1), todayK = min(66, F.day) - 1
            for k in 0..<66 {
                let x = 13 + Double(k % 11) * 2, y = 3 + Double(k / 11) * 2
                let isToday = k == todayK && F.day <= 66
                if isToday { g.on(x, y, (0.75 + 0.25 * cos(t * TAU * 0.25)) * arrive, 1) } else { g.on(x, y, k < lived || F.day > 66 ? sh(x, y) : 0.16) }
            }
            let n = F.goal, s = min(6, 24 / Double(max(1, n - 1)))
            for k in 0..<max(0, n) {
                let x = 23 - (s * Double(n - 1)) / 2 + s * Double(k)
                if k < F.done { g.disc(x + 0.5, 24.5, 2.1, sh(x, 24)) } else if k == F.done { ringCells(&g, x + 0.5, 24.5, 2.2, 0.95) } else { ringCells(&g, x + 0.5, 24.5, 2.2, 0.38, true) }
            }
        }
    }
}
