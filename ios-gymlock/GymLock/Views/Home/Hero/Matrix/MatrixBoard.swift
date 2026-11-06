//
//  MatrixBoard.swift
//  GymLock · Matrix hero (native port)
//
//  Exact port of web/hero13/mxlib.ts (board API `G`, easing, alarm rhythm, pixel icons) and the 5 x 7
//  LED font with text() / textWidth() from web/hero4/dots.ts.
//
//  Everything is in grid cells. The hero card board is 38 x 35 cells, centre (CX, CY) = (22, 17);
//  the done-flow board is 52 x ceil(h / 21).
//
//  Identity scheme (must match the web exactly, or dots re-key and jump):
//    - `on(x, y)`  snapped cell, id = iy * 256 + ix. The brighter of two writes wins.
//    - `fr(x, y)`  free particle, id = 1_000_000 + push index within the frame.
//    - `fs(x, y)`  free particle on a cell centre (same id scheme as fr).
//    - `out()`     cells first (in first-write order), then free particles (in push order), capped.
//
//  Scene authors port helpers by calling them unqualified inside `extension MX { ... }`, which is how
//  MatrixScene.swift is written: `cl(x)`, `ez(x)`, `g.on(...)` read exactly like the TypeScript.
//
//  Depends on: MatrixEngine.swift (MatrixTarget, JSMath, MatrixHash).
//

import Foundation

// MARK: - Pixel rows

/// A pixel bitmap written as strings, pre-decoded to bytes once (no String work per frame).
/// Characters keep their TS meaning: '#' lit, 'o' coral, '+' dim, '1' lit (LED font), anything else off.
public struct PixelRows: Sendable, Equatable {
    public let rows: [[UInt8]]
    public init(_ strings: [String]) { rows = strings.map { Array($0.utf8) } }
    public var height: Int { rows.count }
    /// `Math.max(...rows.map(r => r.length))`
    public var width: Int { rows.map(\.count).max() ?? 0 }

    public static let hash = UInt8(ascii: "#")
    public static let coral = UInt8(ascii: "o")
    public static let plus = UInt8(ascii: "+")
    public static let one = UInt8(ascii: "1")
}

// MARK: - The board (TS class G)

/// One frame of the board. A value type: build it, read `out()`, throw it away (or `reset()` and
/// reuse the storage next frame).
public struct MatrixBoard {
    public let width: Int
    public let height: Int
    public let cap: Int
    private var cells = ContiguousArray<MatrixTarget>()
    private var cellIndex: [Int: Int] = [:]
    private var frees = ContiguousArray<MatrixTarget>()

    /// `new G(W = COLS, H = ROWS, cap = 720)`
    public init(width: Int = MX.COLS, height: Int = MX.ROWS, cap: Int = 720) {
        self.width = width
        self.height = height
        self.cap = cap
        cells.reserveCapacity(cap)
        frees.reserveCapacity(cap)
        cellIndex.reserveCapacity(cap)
    }

    /// Clear for the next frame, keeping the allocated storage.
    public mutating func reset() {
        cells.removeAll(keepingCapacity: true)
        frees.removeAll(keepingCapacity: true)
        cellIndex.removeAll(keepingCapacity: true)
    }

    /// Number of targets that `out()` would return (before the cap).
    public var rawCount: Int { cells.count + frees.count }

    /// A lit cell, snapped to the grid; the brighter of two writes wins.
    /// Web difference: a NaN coordinate is dropped here (JS would insert a NaN-keyed cell).
    public mutating func on(_ x: Double, _ y: Double, _ b: Double = 1, _ c: Int = 0) {
        let fx = x.rounded(.down)
        let fy = y.rounded(.down)
        guard fx >= 0, fy >= 0, fx < Double(width), fy < Double(height) else { return }
        let ix = Int(fx)
        let iy = Int(fy)
        let k = iy * 256 + ix
        let bb = MX.cl(b)
        if let idx = cellIndex[k] {
            let ob = cells[idx].b
            if bb > ob || (c != 0 && bb >= ob * 0.7) {
                cells[idx].b = max(ob, bb)
                if c != 0 { cells[idx].c = 1 }
            }
        } else {
            cellIndex[k] = cells.count
            cells.append(MatrixTarget(x: fx + 0.5, y: fy + 0.5, b: bb, c: c != 0 ? 1 : 0, id: k))
        }
    }

    /// A free particle (not snapped, not merged): for things in flight. Keep counts fixed per element:
    /// to hide one, push it with b = 0, never skip it.
    public mutating func fr(_ x: Double, _ y: Double, _ b: Double = 1, _ c: Int = 0) {
        let W = Double(width), H = Double(height)
        let off = x < -0.5 || y < -0.5 || x > W + 0.5 || y > H + 0.5
        frees.append(MatrixTarget(x: x, y: y, b: off ? 0 : MX.cl(b), c: c != 0 ? 1 : 0, id: 1_000_000 + frees.count))
    }

    /// A free particle that sits on a cell centre (crisp, but keeps its own slot).
    public mutating func fs(_ x: Double, _ y: Double, _ b: Double = 1, _ c: Int = 0) {
        fr(x.rounded(.down) + 0.5, y.rounded(.down) + 0.5, b, c)
    }

    public mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ b: Double = 1, _ c: Int = 0, _ dash: Double = 0) {
        let n = max(1, JSMath.round(max(abs(x1 - x0), abs(y1 - y0))))
        var i = 0.0
        while i <= n {
            defer { i += 1 }
            if dash != 0 && (i / dash).rounded(.down).truncatingRemainder(dividingBy: 2) != 0 { continue }
            // keep the TS operation order: ((x1 - x0) * i) / n
            on(x0 + ((x1 - x0) * i) / n + 0.5, y0 + ((y1 - y0) * i) / n + 0.5, b, c)
        }
    }

    /// An arc from a0 to a1 (radians, 0 = up, clockwise). `ry` defaults to `r`.
    public mutating func ring(_ cx: Double, _ cy: Double, _ r: Double, _ b: Double = 1, _ c: Int = 0, _ a0: Double = 0, _ a1: Double = MX.TAU, _ ry: Double? = nil, _ step: Double = 1) {
        let ry = ry ?? r
        let L = abs(a1 - a0) * max(r, ry)
        let n = max(6, JSMath.round(L / step))
        var i = 0.0
        while i <= n {
            let a = a0 + ((a1 - a0) * i) / n
            on(cx + sin(a) * r, cy - cos(a) * ry, b, c)
            i += 1
        }
    }

    public mutating func disc(_ cx: Double, _ cy: Double, _ r: Double, _ b: Double = 1, _ c: Int = 0) {
        var y = (cy - r).rounded(.down)
        while y <= cy + r {
            var x = (cx - r).rounded(.down)
            while x <= cx + r {
                let dx = x + 0.5 - cx, dy = y + 0.5 - cy
                if dx * dx + dy * dy <= r * r { on(x, y, b, c) }
                x += 1
            }
            y += 1
        }
    }

    public mutating func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ b: Double = 1, _ fill: Bool = false, _ c: Int = 0) {
        var j = 0.0
        while j < h {
            var i = 0.0
            while i < w {
                if fill || i == 0 || j == 0 || i == w - 1 || j == h - 1 { on(x + i, y + j, b, c) }
                i += 1
            }
            j += 1
        }
    }

    /// A pixel icon: '#' lit, 'o' coral, '+' dim (0.22 * b), anything else off.
    public mutating func glyph(_ rows: PixelRows, _ x: Double, _ y: Double, _ s: Double = 1, _ b: Double = 1, _ free: Bool = false) {
        for (j, row) in rows.rows.enumerated() {
            for (i, ch) in row.enumerated() {
                if ch != PixelRows.hash && ch != PixelRows.coral && ch != PixelRows.plus { continue }
                let bb = ch == PixelRows.plus ? 0.22 * b : b
                let cc = ch == PixelRows.coral ? 1 : 0
                var v = 0.0
                while v < s {
                    var u = 0.0
                    while u < s {
                        let px = x + Double(i) * s + u, py = y + Double(j) * s + v
                        if free { fs(px, py, bb, cc) } else { on(px, py, bb, cc) }
                        u += 1
                    }
                    v += 1
                }
            }
        }
    }

    /// LED digits, centred on cx; `dim` draws the unlit font cells too (a board that flips in place).
    /// `coral` lists character indices drawn coral.
    public mutating func num(_ s: String, _ cx: Double, _ y: Double, _ scale: Double = 1, _ b: Double = 1, dim: Double? = nil, coral: [Int]? = nil) {
        let x0 = JSMath.round(cx - MatrixLED.textWidth(s, scale: scale) / 2)
        for q in MatrixLED.text(s, x0, y, dim: dim, scale: scale, coral: coral) {
            on(q.x, q.y, q.b == 1 ? b : q.b, Int(q.c))
        }
    }

    /// `[...cells, ...free].slice(0, cap)`
    public func out() -> ContiguousArray<MatrixTarget> {
        var o = ContiguousArray<MatrixTarget>()
        o.reserveCapacity(min(cap, cells.count + frees.count))
        for q in cells {
            if o.count >= cap { return o }
            o.append(q)
        }
        for q in frees {
            if o.count >= cap { return o }
            o.append(q)
        }
        return o
    }
}

// MARK: - mxlib constants, easing, rhythm, icons

/// Namespace for everything mxlib.ts exports. Scenes live in `extension MX` so they can call these
/// unqualified, exactly like the TypeScript.
public enum MX {
    public static let COLS = 38
    public static let ROWS = 35
    public static let CX: Double = 22
    public static let CY: Double = 17
    public static let TAU = Double.pi * 2
    /// hero4/card4.tsx PROOF: twenty minutes on the gym floor.
    public static let PROOF: Double = 20 * 60

    // ---------- easing ----------
    @inline(__always) public static func cl(_ x: Double) -> Double { min(1, max(0, x)) }
    @inline(__always) public static func ez(_ x: Double) -> Double { 1 - pow(1 - cl(x), 3) }
    public static func eio(_ x: Double) -> Double {
        let k = cl(x)
        return k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
    }
    public static func back(_ x: Double, _ k: Double = 1.7) -> Double {
        let u = cl(x) - 1
        return 1 + (k + 1) * u * u * u + k * u * u
    }
    /// springy settle from 0 to 1
    public static func spr(_ x: Double, _ w: Double = 13, _ z: Double = 5) -> Double {
        x <= 0 ? 0 : 1 - exp(-x * z) * cos(x * w)
    }
    /// a sharp hit every P seconds that decays over w
    public static func pulse(_ t: Double, _ P: Double, _ w: Double = 0.14, _ off: Double = 0) -> Double {
        exp(-(JSMath.rem(JSMath.rem(t - off, P) + P, P)) / w)
    }
    /// `rnd(i)` == `hash(i, 1)` of mdots: deterministic 0..<1.
    @inline(__always) public static func rnd(_ i: Double) -> Double { MatrixHash.hash(i, 1) }
    @inline(__always) public static func rnd(_ i: Int) -> Double { MatrixHash.hash(Double(i), 1) }
    @inline(__always) public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    @inline(__always) public static func since(_ T: Double, _ at: Double) -> Double { T - at }

    // ---------- the alarm's rhythm: five fast rings (0.35 to 2.35 s), the sixth at 2.85 s, then every 2.5 s ----------
    public static let RINGS: [Double] = [0.35, 0.85, 1.35, 1.85, 2.35]

    public static func ringBeat(_ T: Double) -> Double {
        var v = 0.0
        for b in RINGS where T >= b { v = max(v, exp(-(T - b) / 0.13)) }
        if T > 2.6 { v = max(v, pulse(T, 2.5, 0.13, 0.35)) }
        return v
    }

    /// Time of the latest ring at or before T, or -1.
    ///
    /// FIXED relative to mxlib.ts: the TS version returns 0.35 for T in (2.6, 2.85) because
    /// `floor((T - 0.35) / 2.5) * 2.5 + 0.35` is 0.35 there, so anything keyed on it jumped back two
    /// seconds for a quarter second. This version is monotonic and agrees with ringBeat and ringIndex:
    /// 0.35, 0.85, 1.35, 1.85, 2.35, 2.85, 5.35, 7.85, ...
    /// Use `lastRingWeb` only to reproduce an old web frame bit for bit.
    public static func lastRing(_ T: Double) -> Double {
        if T >= 2.85 { return 2.85 + ((T - 2.85) / 2.5).rounded(.down) * 2.5 }
        var last = -1.0
        for b in RINGS where T >= b { last = b }
        return last
    }

    /// The original mxlib.ts lastRing, jump included. Parity tests only.
    public static func lastRingWeb(_ T: Double) -> Double {
        var last = -1.0
        for b in RINGS where T >= b { last = b }
        if T > 2.6 { last = ((T - 0.35) / 2.5).rounded(.down) * 2.5 + 0.35 }
        return last
    }

    /// Index of the latest ring (0-based), -1 before the first. 5 is the ring at 2.85 s.
    public static func ringIndex(_ T: Double) -> Int {
        var k = -1
        for b in RINGS where T >= b { k += 1 }
        if T > 2.6 { k = 4 + Int(((T - 0.35 - 2.5) / 2.5).rounded(.down)) + 1 }
        return k
    }

    /// Particles thrown from a point: positions at a given age, flattened [dx0, dy0, dx1, dy1, ...].
    public static func burst(_ n: Int, _ age: Double, _ speed: Double, _ grav: Double, _ seed: Double, _ up: Bool = false) -> [Double] {
        var o: [Double] = []
        o.reserveCapacity(n * 2)
        for i in 0..<max(0, n) {
            let fi = Double(i)
            let a = up ? -Double.pi / 2 + (rnd(seed + fi * 3) - 0.5) * 2.4 : rnd(seed + fi * 3) * TAU
            let s = speed * (0.45 + rnd(seed + fi * 3 + 1) * 0.75)
            o.append(cos(a) * s * age)
            o.append(sin(a) * s * age + 0.5 * grav * age * age)
        }
        return o
    }

    // ---------- pixel icons ----------
    public enum Icon: String, CaseIterable, Sendable {
        case bell, sun, moon, lock, dumbbell, check, pause, plane, flag, pin, house, bag, shoe, plus, power, flake, arrowR, arrowU, z, bolt
    }

    public static let ICON: [Icon: PixelRows] = [
        .bell: PixelRows(["....#....", "..#####..", ".##...##.", ".#.....#.", ".#.....#.", ".#.....#.", "##.....##", "#########", ".........", "...###..."]),
        .sun: PixelRows(["....#....", ".#..#..#.", "..#...#..", "....#....", "#..###..#", "...###...", "....#....", "..#...#..", ".#..#..#.", "....#...."]),
        .moon: PixelRows(["..####...", ".###.....", "###......", "###......", "###......", "###......", ".###.....", "..####..."]),
        .lock: PixelRows(["..#####..", ".##...##.", ".#.....#.", ".#.....#.", "#########", "#########", "####o####", "####o####", "#########", "#########"]),
        .dumbbell: PixelRows(["##.......##", "##.......##", "###########", "##.......##", "##.......##"]),
        .check: PixelRows([".........##", "........##.", ".......##..", "##....##...", ".##..##....", "..####.....", "...##......"]),
        .pause: PixelRows(["###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "###..###"]),
        .plane: PixelRows([".....#......", ".....##.....", "#....###....", "############", "#....###....", ".....##.....", ".....#......"]),
        .flag: PixelRows(["#######", "#######o", "#######", "#......", "#......", "#......", "#......", "#......"]),
        .pin: PixelRows(["..###..", ".#####.", "##...##", "##.o.##", ".#####.", "..###..", "...#..."]),
        .house: PixelRows(["....#....", "...###...", "..#####..", ".#######.", "#########", ".##...##.", ".##...##.", ".##.o.##.", ".##...##."]),
        .bag: PixelRows(["...###...", "..#...#..", "#########", "#########", "#########", "####o####", "#########", "#########"]),
        .shoe: PixelRows(["#####.....", "#####.....", "######....", "#########.", "##########", "##########"]),
        .plus: PixelRows(["..#..", "..#..", "#####", "..#..", "..#.."]),
        .power: PixelRows(["....#....", ".#..#..#.", "#...#...#", "#...#...#", "#.......#", "#.......#", ".#.....#.", "..#####.."]),
        .flake: PixelRows(["....#....", ".#..#..#.", "..#.#.#..", "...###...", "#########", "...###...", "..#.#.#..", ".#..#..#.", "....#...."]),
        .arrowR: PixelRows(["....#...", "....##..", "#######.", "########", "#######.", "....##..", "....#..."]),
        .arrowU: PixelRows(["...#...", "..###..", ".#####.", "#######", "..###..", "..###..", "..###..", "..###.."]),
        .z: PixelRows(["####", "..#.", ".#..", "####"]),
        .bolt: PixelRows(["...###", "..###.", ".###..", "######", "..###.", ".###..", "###...", "#....."]),
    ]

    private static func rows(_ k: Icon) -> PixelRows { ICON[k] ?? PixelRows([]) }
    public static func iconW(_ k: Icon) -> Int { rows(k).width }
    public static func iconH(_ k: Icon) -> Int { rows(k).height }

    /// Draw an icon centred on (cx, cy).
    public static func icon(_ g: inout MatrixBoard, _ k: Icon, _ cx: Double, _ cy: Double, _ s: Double = 1, _ b: Double = 1, _ free: Bool = false) {
        let x = JSMath.round(cx - (Double(iconW(k)) * s) / 2)
        let y = JSMath.round(cy - (Double(iconH(k)) * s) / 2)
        g.glyph(rows(k), x, y, s, b, free)
    }

    /// An icon as points (for morphs and free motion): (dx, dy, coral) around the icon's centre.
    public static func iconPts(_ k: Icon, _ s: Double = 1) -> [(x: Double, y: Double, c: Int)] {
        var o: [(x: Double, y: Double, c: Int)] = []
        let R = rows(k), w = Double(R.width), h = Double(R.height)
        for (j, row) in R.rows.enumerated() {
            for (i, ch) in row.enumerated() where ch == PixelRows.hash || ch == PixelRows.coral {
                var v = 0.0
                while v < s {
                    var u = 0.0
                    while u < s {
                        o.append((x: Double(i) * s + u - (w * s) / 2, y: Double(j) * s + v - (h * s) / 2, c: ch == PixelRows.coral ? 1 : 0))
                        u += 1
                    }
                    v += 1
                }
            }
        }
        return o
    }
}

// MARK: - 5 x 7 LED font (hero4/dots.ts)

public enum MatrixLED {
    public struct Pixel: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var b: Double
        public var c: UInt8
    }

    public static let FONT: [Unicode.Scalar: PixelRows] = [
        "0": PixelRows(["01110", "10001", "10011", "10101", "11001", "10001", "01110"]),
        "1": PixelRows(["00100", "01100", "00100", "00100", "00100", "00100", "01110"]),
        "2": PixelRows(["01110", "10001", "00001", "00010", "00100", "01000", "11111"]),
        "3": PixelRows(["11110", "00001", "00001", "01110", "00001", "00001", "11110"]),
        "4": PixelRows(["00010", "00110", "01010", "10010", "11111", "00010", "00010"]),
        "5": PixelRows(["11111", "10000", "11110", "00001", "00001", "10001", "01110"]),
        "6": PixelRows(["00110", "01000", "10000", "11110", "10001", "10001", "01110"]),
        "7": PixelRows(["11111", "00001", "00010", "00100", "01000", "01000", "01000"]),
        "8": PixelRows(["01110", "10001", "10001", "01110", "10001", "10001", "01110"]),
        "9": PixelRows(["01110", "10001", "10001", "01111", "00001", "00010", "01100"]),
        ":": PixelRows(["0", "0", "1", "0", "1", "0", "0"]),
        "D": PixelRows(["11110", "10001", "10001", "10001", "10001", "10001", "11110"]),
        "O": PixelRows(["01110", "10001", "10001", "10001", "10001", "10001", "01110"]),
        "N": PixelRows(["10001", "11001", "10101", "10011", "10001", "10001", "10001"]),
        "E": PixelRows(["11111", "10000", "10000", "11110", "10000", "10000", "11111"]),
        ".": PixelRows(["0", "0", "0", "0", "0", "0", "1"]),
        " ": PixelRows(["000", "000", "000", "000", "000", "000", "000"]),
    ]

    private static func glyph(_ ch: Unicode.Scalar) -> PixelRows {
        FONT[ch] ?? FONT[" "] ?? PixelRows(["000", "000", "000", "000", "000", "000", "000"])
    }

    /// Every font pixel of a string becomes a target: lit pixels bright, unlit ones `dim` (only when
    /// dim is given), so a changing number flips dots in place like an LED board.
    /// Iterates Unicode scalars, which is what JS `[...s]` does for this character set.
    public static func text(_ s: String, _ x0: Double, _ y0: Double, dim: Double? = nil, scale: Double = 1, gap: Double = 1, coral: [Int]? = nil) -> [Pixel] {
        var out: [Pixel] = []
        var x = x0
        for (k, ch) in s.unicodeScalars.enumerated() {
            let g = glyph(ch)
            for r in 0..<min(7, g.height) {
                let row = g.rows[r]
                for cIdx in 0..<row.count {
                    let on = row[cIdx] == PixelRows.one
                    if !on && dim == nil { continue }
                    var v = 0.0
                    while v < scale {
                        var u = 0.0
                        while u < scale {
                            let isCoral = on && (coral?.contains(k) ?? false)
                            out.append(Pixel(x: x + Double(cIdx) * scale + u + 0.5, y: y0 + Double(r) * scale + v + 0.5, b: on ? 1 : (dim ?? 0), c: isCoral ? 1 : 0))
                            u += 1
                        }
                        v += 1
                    }
                }
            }
            x += (Double(g.rows.first?.count ?? 0) + gap) * scale
        }
        return out
    }

    public static func textWidth(_ s: String, scale: Double = 1, gap: Double = 1) -> Double {
        var w = 0.0
        for ch in s.unicodeScalars { w += (Double(glyph(ch).rows.first?.count ?? 0) + gap) * scale }
        return w - gap * scale
    }
}

// MARK: - hero4/dots.ts sin hash

public enum MatrixSinHash {
    /// hero4/dots.ts `hash(i, s)` (sin based). mxstory.ts imports this one (the `today` heart-rate
    /// wobble). Platform `sin` may differ from V8 in the last ulp; the result differs by ~1e-11.
    public static func hash(_ i: Double, _ s: Double) -> Double {
        let x = sin(i * 127.1 + s * 311.7) * 43758.5453
        return x - x.rounded(.down)
    }
}
