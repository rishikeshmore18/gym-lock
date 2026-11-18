//
//  MatrixWakeBoard.swift
//  GymLock · Wake intro, Matrix concepts (native port)
//
//  Exact port of web/hero13/mxlib.ts (board API `G`, easing, pixel icons) and the 5 x 7 LED font
//  with text() / textWidth() from web/hero4/dots.ts. Reused from rork-pack/swift/MatrixBoard.swift
//  after review; changes from that file:
//    - The cell index is a flat Int32 table (id = iy * 256 + ix) instead of a Dictionary: no hashing
//      per `on`, and `reset` clears only the slots that were written.
//    - The alarm-rhythm helpers, `burst` and the sin hash (unused by the wake intro) were dropped.
//    - Every type is prefixed (MatrixWake*, MXW): the Home hero card's own Matrix files in the same
//      module already define MatrixEngine, MatrixBoard, MX, JSMath, MatrixHash, MatrixTarget, PixelRows...
//
//  Identity scheme (must match the web, or dots re-key and jump):
//    - `on(x, y)`  snapped cell, id = iy * 256 + ix. The brighter of two writes wins.
//    - `fr(x, y)`  free particle, id = 1_000_000 + push index within the frame.
//    - `out()`     cells first (first-write order), then free particles (push order), capped.
//

import Foundation

// MARK: - Pixel rows

/// A pixel bitmap written as strings, decoded to bytes once (no String work per frame).
/// '#' lit, 'o' coral, '+' dim, '1' lit (LED font), anything else off.
public struct MatrixWakePixels: Sendable, Equatable {
    public let rows: [[UInt8]]
    public init(_ strings: [String]) { rows = strings.map { Array($0.utf8) } }
    public var height: Int { rows.count }
    /// `Math.max(...rows.map(r => r.length))`
    public var width: Int { rows.map(\.count).max() ?? 0 }
    /// `rows[0].length`
    public var firstWidth: Int { rows.first?.count ?? 0 }

    public static let hash = UInt8(ascii: "#")
    public static let coral = UInt8(ascii: "o")
    public static let plus = UInt8(ascii: "+")
    public static let one = UInt8(ascii: "1")
}

// MARK: - The board (TS class G)

/// One frame of the board. A value type: build it, read `out()`, `reset()` and reuse next frame.
/// Width must be <= 256 (the id scheme packs x in 8 bits).
public struct MatrixWakeBoard: Sendable {
    public let width: Int
    public let height: Int
    public let cap: Int
    private var cells = ContiguousArray<MatrixWakeTarget>()
    private var slot: ContiguousArray<Int32>
    private var frees = ContiguousArray<MatrixWakeTarget>()

    /// `new G(W, H, cap)`
    public init(width: Int = MXW.COLS, height: Int = MXW.ROWS, cap: Int = 720) {
        self.width = min(256, max(1, width))
        self.height = max(1, height)
        self.cap = max(0, cap)
        slot = ContiguousArray(repeating: -1, count: self.height * 256)
        cells.reserveCapacity(self.cap)
        frees.reserveCapacity(self.cap)
    }

    /// Clear for the next frame, keeping the storage.
    public mutating func reset() {
        for q in cells { slot[q.id] = -1 }
        cells.removeAll(keepingCapacity: true)
        frees.removeAll(keepingCapacity: true)
    }

    /// Number of targets before the cap.
    public var rawCount: Int { cells.count + frees.count }

    /// A lit cell, snapped to the grid; the brighter of two writes wins.
    /// (A NaN coordinate is dropped; JS would insert a NaN-keyed cell. The chapters never produce one.)
    public mutating func on(_ x: Double, _ y: Double, _ b: Double = 1, _ c: Int = 0) {
        let fx = x.rounded(.down)
        let fy = y.rounded(.down)
        guard fx >= 0, fy >= 0, fx < Double(width), fy < Double(height) else { return }
        let k = Int(fy) * 256 + Int(fx)
        let bb = MXW.cl(b)
        let idx = Int(slot[k])
        if idx >= 0 {
            let ob = cells[idx].b
            if bb > ob || (c != 0 && bb >= ob * 0.7) {
                cells[idx].b = max(ob, bb)
                if c != 0 { cells[idx].c = 1 }
            }
        } else {
            slot[k] = Int32(cells.count)
            cells.append(MatrixWakeTarget(x: fx + 0.5, y: fy + 0.5, b: bb, c: c != 0 ? 1 : 0, id: k))
        }
    }

    /// A free particle (not snapped, not merged): for things in flight. Keep counts fixed per element:
    /// to hide one push it with b = 0, never skip it.
    public mutating func fr(_ x: Double, _ y: Double, _ b: Double = 1, _ c: Int = 0) {
        let W = Double(width), H = Double(height)
        let off = x < -0.5 || y < -0.5 || x > W + 0.5 || y > H + 0.5
        frees.append(MatrixWakeTarget(x: x, y: y, b: off ? 0 : MXW.cl(b), c: c != 0 ? 1 : 0, id: 1_000_000 + frees.count))
    }

    /// A free particle on a cell centre.
    public mutating func fs(_ x: Double, _ y: Double, _ b: Double = 1, _ c: Int = 0) {
        fr(x.rounded(.down) + 0.5, y.rounded(.down) + 0.5, b, c)
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
    public mutating func glyph(_ rows: MatrixWakePixels, _ x: Double, _ y: Double, _ s: Double = 1, _ b: Double = 1, _ free: Bool = false) {
        for (j, row) in rows.rows.enumerated() {
            for (i, ch) in row.enumerated() {
                if ch != MatrixWakePixels.hash && ch != MatrixWakePixels.coral && ch != MatrixWakePixels.plus { continue }
                let bb = ch == MatrixWakePixels.plus ? 0.22 * b : b
                let cc = ch == MatrixWakePixels.coral ? 1 : 0
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

    /// `[...cells, ...free].slice(0, cap)`
    public func out() -> ContiguousArray<MatrixWakeTarget> {
        var o = ContiguousArray<MatrixWakeTarget>()
        o.reserveCapacity(min(cap, cells.count + frees.count))
        appendOut(to: &o, limit: cap) { $0 }
        return o
    }

    /// Appends `out()` to `o`, each target passed through `map` (no intermediate array).
    public func appendOut(to o: inout ContiguousArray<MatrixWakeTarget>, limit: Int, _ map: (MatrixWakeTarget) -> MatrixWakeTarget) {
        var left = min(limit, cap)
        for q in cells {
            if left <= 0 { return }
            o.append(map(q))
            left -= 1
        }
        for q in frees {
            if left <= 0 { return }
            o.append(map(q))
            left -= 1
        }
    }
}

// MARK: - mxlib constants, easing, icons

/// Namespace for what mxlib.ts exports.
public enum MXW {
    public static let COLS = 38
    public static let ROWS = 35
    public static let TAU = Double.pi * 2

    @inline(__always) public static func cl(_ x: Double) -> Double { min(1, max(0, x)) }
    @inline(__always) public static func ez(_ x: Double) -> Double { 1 - pow(1 - cl(x), 3) }
    public static func eio(_ x: Double) -> Double {
        let k = cl(x)
        return k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
    }
    /// `rnd(i)` == mdots `hash(i, 1)`.
    @inline(__always) public static func rnd(_ i: Double) -> Double { MatrixWakeHash.hash(i, 1) }
    @inline(__always) public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    public enum Icon: Sendable { case dumbbell, bag, shoe }

    public static let dumbbell = MatrixWakePixels(["##.......##", "##.......##", "###########", "##.......##", "##.......##"])
    public static let bag = MatrixWakePixels(["...###...", "..#...#..", "#########", "#########", "#########", "####o####", "#########", "#########"])
    public static let shoe = MatrixWakePixels(["#####.....", "#####.....", "######....", "#########.", "##########", "##########"])

    public static func icon(_ k: Icon) -> MatrixWakePixels {
        switch k {
        case .dumbbell: return dumbbell
        case .bag: return bag
        case .shoe: return shoe
        }
    }
}

// MARK: - 5 x 7 LED font (hero4/dots.ts)

public enum MatrixWakeLED {
    public struct Pixel: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var b: Double
        public var c: UInt8
    }

    public static let FONT: [Unicode.Scalar: MatrixWakePixels] = [
        "0": MatrixWakePixels(["01110", "10001", "10011", "10101", "11001", "10001", "01110"]),
        "1": MatrixWakePixels(["00100", "01100", "00100", "00100", "00100", "00100", "01110"]),
        "2": MatrixWakePixels(["01110", "10001", "00001", "00010", "00100", "01000", "11111"]),
        "3": MatrixWakePixels(["11110", "00001", "00001", "01110", "00001", "00001", "11110"]),
        "4": MatrixWakePixels(["00010", "00110", "01010", "10010", "11111", "00010", "00010"]),
        "5": MatrixWakePixels(["11111", "10000", "11110", "00001", "00001", "10001", "01110"]),
        "6": MatrixWakePixels(["00110", "01000", "10000", "11110", "10001", "10001", "01110"]),
        "7": MatrixWakePixels(["11111", "00001", "00010", "00100", "01000", "01000", "01000"]),
        "8": MatrixWakePixels(["01110", "10001", "10001", "01110", "10001", "10001", "01110"]),
        "9": MatrixWakePixels(["01110", "10001", "10001", "01111", "00001", "00010", "01100"]),
        ":": MatrixWakePixels(["0", "0", "1", "0", "1", "0", "0"]),
        "D": MatrixWakePixels(["11110", "10001", "10001", "10001", "10001", "10001", "11110"]),
        "O": MatrixWakePixels(["01110", "10001", "10001", "10001", "10001", "10001", "01110"]),
        "N": MatrixWakePixels(["10001", "11001", "10101", "10011", "10001", "10001", "10001"]),
        "E": MatrixWakePixels(["11111", "10000", "10000", "11110", "10000", "10000", "11111"]),
        ".": MatrixWakePixels(["0", "0", "0", "0", "0", "0", "1"]),
        " ": MatrixWakePixels(["000", "000", "000", "000", "000", "000", "000"]),
    ]
    private static let space = MatrixWakePixels(["000", "000", "000", "000", "000", "000", "000"])

    @inline(__always)
    private static func glyph(_ ch: Unicode.Scalar) -> MatrixWakePixels { FONT[ch] ?? space }

    /// Every font pixel of a string becomes a target: lit pixels 1, unlit ones `dim` (only when `dim` is
    /// given). Iterates Unicode scalars, which is what JS `[...s]` does for this character set.
    public static func text(_ s: String, _ x0: Double, _ y0: Double, dim: Double? = nil, scale: Double = 1, gap: Double = 1, coral: Int = -1) -> [Pixel] {
        var out: [Pixel] = []
        out.reserveCapacity(s.unicodeScalars.count * 35 * Int(max(1, scale * scale)))
        var x = x0
        for (k, ch) in s.unicodeScalars.enumerated() {
            let g = glyph(ch)
            for r in 0..<min(7, g.height) {
                let row = g.rows[r]
                for cIdx in 0..<row.count {
                    let on = row[cIdx] == MatrixWakePixels.one
                    if !on && dim == nil { continue }
                    let isCoral: UInt8 = on && k == coral ? 1 : 0
                    var v = 0.0
                    while v < scale {
                        var u = 0.0
                        while u < scale {
                            out.append(Pixel(x: x + Double(cIdx) * scale + u + 0.5, y: y0 + Double(r) * scale + v + 0.5, b: on ? 1 : (dim ?? 0), c: isCoral))
                            u += 1
                        }
                        v += 1
                    }
                }
            }
            x += (Double(g.firstWidth) + gap) * scale
        }
        return out
    }

    public static func textWidth(_ s: String, scale: Double = 1, gap: Double = 1) -> Double {
        var w = 0.0
        for ch in s.unicodeScalars { w += (Double(glyph(ch).firstWidth) + gap) * scale }
        return w - gap * scale
    }
}
