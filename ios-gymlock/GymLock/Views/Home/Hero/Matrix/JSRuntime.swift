//
//  JSRuntime.swift
//  GymLock · Matrix hero
//
//  The small slice of JavaScript semantics the generated scene files (Matrix/Scenes/MX*.swift)
//  rely on. The scenes are machine-translated from web-reference/hero13/mx/*.ts by
//  docs/hero-pack/swift/tools/ts2swift.ts; every helper here reproduces the JS behaviour exactly
//  (Math.round rounds half up, `%` truncates, sorts are stable, numbers print like JS), so the
//  Swift boards match the web goldens dot for dot.
//

import Foundation

// MARK: - JS

public enum JS {
    // ---- Math
    @inline(__always) public static func floor(_ x: Double) -> Double { x.rounded(.down) }
    @inline(__always) public static func ceil(_ x: Double) -> Double { x.rounded(.up) }
    @inline(__always) public static func round(_ x: Double) -> Double { JSMath.round(x) }
    @inline(__always) public static func trunc(_ x: Double) -> Double { x.rounded(.towardZero) }
    @inline(__always) public static func abs(_ x: Double) -> Double { Swift.abs(x) }
    @inline(__always) public static func sign(_ x: Double) -> Double { x > 0 ? 1 : x < 0 ? -1 : x }
    @inline(__always) public static func sqrt(_ x: Double) -> Double { Foundation.sqrt(x) }
    @inline(__always) public static func cbrt(_ x: Double) -> Double { Foundation.cbrt(x) }
    @inline(__always) public static func exp(_ x: Double) -> Double { Foundation.exp(x) }
    @inline(__always) public static func log(_ x: Double) -> Double { Foundation.log(x) }
    @inline(__always) public static func log2(_ x: Double) -> Double { Foundation.log2(x) }
    @inline(__always) public static func log10(_ x: Double) -> Double { Foundation.log10(x) }
    @inline(__always) public static func pow(_ a: Double, _ b: Double) -> Double { Foundation.pow(a, b) }
    @inline(__always) public static func sin(_ x: Double) -> Double { Foundation.sin(x) }
    @inline(__always) public static func cos(_ x: Double) -> Double { Foundation.cos(x) }
    @inline(__always) public static func tan(_ x: Double) -> Double { Foundation.tan(x) }
    @inline(__always) public static func asin(_ x: Double) -> Double { Foundation.asin(x) }
    @inline(__always) public static func acos(_ x: Double) -> Double { Foundation.acos(x) }
    @inline(__always) public static func atan(_ x: Double) -> Double { Foundation.atan(x) }
    @inline(__always) public static func atan2(_ y: Double, _ x: Double) -> Double { Foundation.atan2(y, x) }
    @inline(__always) public static func sq(_ x: Double) -> Double { x * x }

    /// Math.hypot: sqrt of the sum of squares (V8 scales to avoid overflow; values here are small).
    public static func hypot(_ xs: Double...) -> Double {
        if xs.count == 2 { return Foundation.hypot(xs[0], xs[1]) }
        var s = 0.0
        for x in xs { s += x * x }
        return Foundation.sqrt(s)
    }

    /// Math.max: NaN wins, no arguments is -Infinity.
    public static func max(_ xs: Double...) -> Double { max(xs) }
    public static func max(_ xs: [Double]) -> Double {
        var m = -Double.infinity
        for x in xs {
            if x.isNaN { return .nan }
            if x > m || (x == 0 && m == 0 && x.sign == .plus) { m = x }
        }
        return m
    }
    /// Math.min: NaN wins, no arguments is Infinity.
    public static func min(_ xs: Double...) -> Double { min(xs) }
    public static func min(_ xs: [Double]) -> Double {
        var m = Double.infinity
        for x in xs {
            if x.isNaN { return .nan }
            if x < m || (x == 0 && m == 0 && x.sign == .minus) { m = x }
        }
        return m
    }

    // ---- truthiness and logic
    @inline(__always) public static func truthy(_ x: Bool) -> Bool { x }
    @inline(__always) public static func truthy(_ x: Double) -> Bool { x != 0 && !x.isNaN }
    @inline(__always) public static func truthy(_ x: String) -> Bool { !x.isEmpty }
    @inline(__always) public static func truthy<T>(_ x: T?) -> Bool { x != nil }

    /// `a || b` on numbers.
    @inline(__always) public static func or(_ a: Double, _ b: @autoclosure () -> Double) -> Double { truthy(a) ? a : b() }
    @inline(__always) public static func or(_ a: String, _ b: @autoclosure () -> String) -> String { a.isEmpty ? b() : a }
    @inline(__always) public static func or<T>(_ a: T?, _ b: @autoclosure () -> T) -> T { a ?? b() }
    /// `a && b` on numbers.
    @inline(__always) public static func and(_ a: Double, _ b: @autoclosure () -> Double) -> Double { truthy(a) ? b() : a }

    /// A board colour flag from a JS number (0 ink, anything else coral).
    @inline(__always) public static func flag(_ c: Double) -> Int { c != 0 && !c.isNaN ? 1 : 0 }
    @inline(__always) public static func flag(_ c: Bool) -> Int { c ? 1 : 0 }
    @inline(__always) public static func flag(_ c: Int) -> Int { c }

    // ---- ++ / -- in expressions
    @discardableResult @inline(__always) public static func postInc(_ x: inout Double) -> Double { let v = x; x += 1; return v }
    @discardableResult @inline(__always) public static func postDec(_ x: inout Double) -> Double { let v = x; x -= 1; return v }
    @discardableResult @inline(__always) public static func preInc(_ x: inout Double) -> Double { x += 1; return x }
    @discardableResult @inline(__always) public static func preDec(_ x: inout Double) -> Double { x -= 1; return x }

    // ---- numbers to strings
    /// `String(n)` / template literal of a number, printed the way JS prints it.
    public static func str(_ x: Double) -> String {
        if x.isNaN { return "NaN" }
        if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
        if x == 0 { return "0" }
        if x == x.rounded(), Swift.abs(x) < 1e21 { return String(format: "%.0f", x) }
        // Swift's description is the shortest round-trip form, which is also what JS prints
        // for the 1e-7 ..< 1e21 range used here.
        return "\(x)"
    }
    public static func str(_ x: String) -> String { x }
    public static func str(_ x: Bool) -> String { x ? "true" : "false" }
    public static func str(_ x: Int) -> String { String(x) }

    /// Number.prototype.toFixed
    public static func toFixed(_ x: Double, _ digits: Double) -> String {
        String(format: "%.\(Int(digits))f", x)
    }

    // ---- strings
    /// `[...s]`
    public static func chars(_ s: String) -> [String] { s.unicodeScalars.map { String($0) } }
    /// `s[i]` (empty string stands in for `undefined`)
    public static func at(_ s: String, _ i: Double) -> String {
        guard i >= 0, i == i.rounded() else { return "" }
        let u = Array(s.unicodeScalars)
        let k = Int(i)
        return k < u.count ? String(u[k]) : ""
    }
    public static func at<T>(_ a: [T], _ i: Double) -> T { a[Int(i)] }
    /// `String.prototype.indexOf`
    public static func indexOf(_ s: String, _ sub: String) -> Double {
        if sub.isEmpty { return 0 }
        let a = Array(s.unicodeScalars), b = Array(sub.unicodeScalars)
        if b.count > a.count { return -1 }
        var i = 0
        while i + b.count <= a.count {
            if Array(a[i..<(i + b.count)]) == b { return Double(i) }
            i += 1
        }
        return -1
    }
    /// `Array.prototype.indexOf`
    public static func indexOf<T: Equatable>(_ a: [T], _ x: T) -> Double {
        if let i = a.firstIndex(of: x) { return Double(i) }
        return -1
    }
    public static func includes<T: Equatable>(_ a: [T], _ x: T) -> Bool { a.contains(x) }
    public static func includes(_ s: String, _ sub: String) -> Bool { indexOf(s, sub) >= 0 }
    public static func padStart(_ s: String, _ n: Double, _ fill: String = " ") -> String {
        let len = s.unicodeScalars.count, want = Int(n)
        if len >= want || fill.isEmpty { return s }
        var pad = ""
        let f = Array(fill.unicodeScalars)
        var k = 0
        while pad.unicodeScalars.count < want - len {
            pad.unicodeScalars.append(f[k % f.count])
            k += 1
        }
        return pad + s
    }
    public static func padEnd(_ s: String, _ n: Double, _ fill: String = " ") -> String {
        let len = s.unicodeScalars.count, want = Int(n)
        if len >= want || fill.isEmpty { return s }
        var pad = ""
        let f = Array(fill.unicodeScalars)
        var k = 0
        while pad.unicodeScalars.count < want - len {
            pad.unicodeScalars.append(f[k % f.count])
            k += 1
        }
        return s + pad
    }
    public static func split(_ s: String, _ sep: String) -> [String] {
        if sep.isEmpty { return chars(s) }
        return s.components(separatedBy: sep)
    }
    public static func repeatStr(_ s: String, _ n: Double) -> String { String(repeating: s, count: Swift.max(0, Int(n))) }

    // ---- slices (negative indices count from the end, like JS)
    private static func sliceBounds(_ count: Int, _ a: Double?, _ b: Double?) -> Range<Int> {
        func norm(_ v: Double) -> Int {
            let i = Int(v.rounded(.towardZero))
            return i < 0 ? Swift.max(0, count + i) : Swift.min(i, count)
        }
        let lo = a.map(norm) ?? 0
        let hi = b.map(norm) ?? count
        return lo < hi ? lo..<hi : lo..<lo
    }
    public static func slice<T>(_ a: [T], _ from: Double = 0, _ to: Double? = nil) -> [T] {
        Array(a[sliceBounds(a.count, from, to)])
    }
    public static func slice(_ s: String, _ from: Double = 0, _ to: Double? = nil) -> String {
        let u = Array(s.unicodeScalars)
        var o = String.UnicodeScalarView()
        o.append(contentsOf: u[sliceBounds(u.count, from, to)])
        return String(o)
    }

    // ---- tuples used as JS arrays
    public static func arr<T>(_ t: (T, T)) -> [T] { [t.0, t.1] }
    public static func arr<T>(_ t: (T, T, T)) -> [T] { [t.0, t.1, t.2] }
    public static func arr<T>(_ t: (T, T, T, T)) -> [T] { [t.0, t.1, t.2, t.3] }
    public static func tuple2<T>(_ a: [T]) -> (T, T) { (a[0], a[1]) }
    public static func tuple3<T>(_ a: [T]) -> (T, T, T) { (a[0], a[1], a[2]) }
    public static func tuple4<T>(_ a: [T]) -> (T, T, T, T) { (a[0], a[1], a[2], a[3]) }

    // ---- arrays
    /// `Array.from({length: n}, (_, i) => i)`
    public static func range(_ n: Double) -> [Double] {
        let k = Swift.max(0, Int(n))
        var o = [Double]()
        o.reserveCapacity(k)
        for i in 0..<k { o.append(Double(i)) }
        return o
    }
    /// `new Array(n)` filled with the element default (holes read as the default).
    public static func newArray<T>(_ n: Double, _ fill: T) -> [T] { Array(repeating: fill, count: Swift.max(0, Int(n))) }
    /// `a.length = n` (truncating; the scenes never grow an array this way)
    public static func setLength<T>(_ a: inout [T], _ n: Double) {
        let k = Swift.max(0, Int(n))
        if a.count > k { a.removeLast(a.count - k) }
    }
    /// Array.prototype.sort with a comparator (stable, like V8's TimSort).
    public static func sort<T>(_ a: inout [T], _ cmp: (T, T) -> Double) {
        a = sorted(a, cmp)
    }
    public static func sorted<T>(_ a: [T], _ cmp: (T, T) -> Double) -> [T] {
        let idx = a.indices.sorted { i, j in
            let r = cmp(a[i], a[j])
            if r < 0 { return true }
            if r > 0 { return false }
            return i < j
        }
        return idx.map { a[$0] }
    }
    /// Array.prototype.sort without a comparator on numbers (JS compares the printed strings).
    public static func sortDefault(_ a: inout [Double]) {
        a = a.enumerated().sorted { l, r in
            let ls = str(l.element), rs = str(r.element)
            return ls == rs ? l.offset < r.offset : ls < rs
        }.map(\.element)
    }
    public static func findIndex<T>(_ a: [T], _ f: (T) -> Bool) -> Double {
        if let i = a.firstIndex(where: f) { return Double(i) }
        return -1
    }
    public static func reversed<T>(_ a: [T]) -> [T] { Array(a.reversed()) }
    public static func fill<T>(_ a: inout [T], _ v: T) {
        for i in a.indices { a[i] = v }
    }

    // ---- bit ops (ToInt32 semantics)
    @inline(__always) public static func bor(_ a: Double, _ b: Double) -> Double { Double(JSMath.toInt32(a) | JSMath.toInt32(b)) }
    @inline(__always) public static func band(_ a: Double, _ b: Double) -> Double { Double(JSMath.toInt32(a) & JSMath.toInt32(b)) }
    @inline(__always) public static func bxor(_ a: Double, _ b: Double) -> Double { Double(JSMath.toInt32(a) ^ JSMath.toInt32(b)) }
    @inline(__always) public static func shl(_ a: Double, _ b: Double) -> Double { Double(JSMath.toInt32(a) << (JSMath.toUint32(b) & 31)) }
    @inline(__always) public static func shr(_ a: Double, _ b: Double) -> Double { Double(JSMath.toInt32(a) >> (JSMath.toUint32(b) & 31)) }
    @inline(__always) public static func ushr(_ a: Double, _ b: Double) -> Double { Double(JSMath.toUint32(a) >> (JSMath.toUint32(b) & 31)) }
}

// MARK: - Map / Set (insertion-ordered, reference semantics like JS)

public final class JSMap<K: Hashable, V> {
    private var order: [K] = []
    private var store: [K: V] = [:]
    public init() {}
    public var count: Int { store.count }
    public var size: Double { Double(store.count) }
    public func get(_ k: K) -> V? { store[k] }
    public func has(_ k: K) -> Bool { store[k] != nil }
    @discardableResult public func set(_ k: K, _ v: V) -> JSMap<K, V> {
        if store.updateValue(v, forKey: k) == nil { order.append(k) }
        return self
    }
    @discardableResult public func delete(_ k: K) -> Bool {
        guard store.removeValue(forKey: k) != nil else { return false }
        if let i = order.firstIndex(of: k) { order.remove(at: i) }
        return true
    }
    public func clear() {
        order.removeAll()
        store.removeAll()
    }
    public var keys: [K] { order }
    public var values: [V] { order.map { store[$0]! } }
    public var entries: [(K, V)] { order.map { ($0, store[$0]!) } }
}

public final class JSSet<T: Hashable> {
    private var order: [T] = []
    private var store: Set<T> = []
    public init() {}
    public init(_ xs: [T]) { for x in xs { add(x) } }
    public var count: Int { store.count }
    public var size: Double { Double(store.count) }
    public func has(_ x: T) -> Bool { store.contains(x) }
    @discardableResult public func add(_ x: T) -> JSSet<T> {
        if store.insert(x).inserted { order.append(x) }
        return self
    }
    @discardableResult public func delete(_ x: T) -> Bool {
        guard store.remove(x) != nil else { return false }
        if let i = order.firstIndex(of: x) { order.remove(at: i) }
        return true
    }
    public func clear() {
        order.removeAll()
        store.removeAll()
    }
    public var values: [T] { order }
}

// MARK: - mxlib / hero4 dots, string-keyed (the shape the generated scenes use)

/// hero4/dots.ts `Tgt`
public final class MXTgt {
    public var x: Double
    public var y: Double
    public var b: Double
    public var c: Double?
    public init(x: Double, y: Double, b: Double, c: Double? = nil) {
        self.x = x
        self.y = y
        self.b = b
        self.c = c
    }
}

public enum MXJS {
    /// mxlib.ts `ICON`, verbatim.
    public static let ICON: [String: [String]] = [
        "bell": ["....#....", "..#####..", ".##...##.", ".#.....#.", ".#.....#.", ".#.....#.", "##.....##", "#########", ".........", "...###..."],
        "sun": ["....#....", ".#..#..#.", "..#...#..", "....#....", "#..###..#", "...###...", "....#....", "..#...#..", ".#..#..#.", "....#...."],
        "moon": ["..####...", ".###.....", "###......", "###......", "###......", "###......", ".###.....", "..####..."],
        "lock": ["..#####..", ".##...##.", ".#.....#.", ".#.....#.", "#########", "#########", "####o####", "####o####", "#########", "#########"],
        "dumbbell": ["##.......##", "##.......##", "###########", "##.......##", "##.......##"],
        "check": [".........##", "........##.", ".......##..", "##....##...", ".##..##....", "..####.....", "...##......"],
        "pause": ["###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "###..###", "###..###"],
        "plane": [".....#......", ".....##.....", "#....###....", "############", "#....###....", ".....##.....", ".....#......"],
        "flag": ["#######", "#######o", "#######", "#......", "#......", "#......", "#......", "#......"],
        "pin": ["..###..", ".#####.", "##...##", "##.o.##", ".#####.", "..###..", "...#..."],
        "house": ["....#....", "...###...", "..#####..", ".#######.", "#########", ".##...##.", ".##...##.", ".##.o.##.", ".##...##."],
        "bag": ["...###...", "..#...#..", "#########", "#########", "#########", "####o####", "#########", "#########"],
        "shoe": ["#####.....", "#####.....", "######....", "#########.", "##########", "##########"],
        "plus": ["..#..", "..#..", "#####", "..#..", "..#.."],
        "power": ["....#....", ".#..#..#.", "#...#...#", "#...#...#", "#.......#", "#.......#", ".#.....#.", "..#####.."],
        "flake": ["....#....", ".#..#..#.", "..#.#.#..", "...###...", "#########", "...###...", "..#.#.#..", ".#..#..#.", "....#...."],
        "arrowR": ["....#...", "....##..", "#######.", "########", "#######.", "....##..", "....#..."],
        "arrowU": ["...#...", "..###..", ".#####.", "#######", "..###..", "..###..", "..###..", "..###.."],
        "z": ["####", "..#.", ".#..", "####"],
        "bolt": ["...###", "..###.", ".###..", "######", "..###.", ".###..", "###...", "#....."],
    ]

    public static func iconW(_ k: String) -> Double {
        JS.max((ICON[k] ?? []).map { Double($0.unicodeScalars.count) })
    }
    public static func iconH(_ k: String) -> Double { Double((ICON[k] ?? []).count) }

    /// hero4/dots.ts `text`
    public static func text(_ s: String, _ x0: Double, _ y0: Double, dim: Double? = nil, scale: Double = 1, gap: Double = 1, coral: [Double]? = nil) -> [MXTgt] {
        MatrixLED.text(s, x0, y0, dim: dim, scale: scale, gap: gap, coral: coral?.map { Int($0) })
            .map { MXTgt(x: $0.x, y: $0.y, b: $0.b, c: Double($0.c)) }
    }
    /// hero4/dots.ts `textWidth`
    public static func textWidth(_ s: String, _ scale: Double = 1, _ gap: Double = 1) -> Double {
        MatrixLED.textWidth(s, scale: scale, gap: gap)
    }
}

// MARK: - board overloads for string-keyed glyphs

extension MatrixBoard {
    /// `g.glyph(ICON[k], ...)` with the raw string rows.
    public mutating func glyph(_ rows: [String], _ x: Double, _ y: Double, _ s: Double = 1, _ b: Double = 1, _ free: Bool = false) {
        glyph(PixelRows(rows), x, y, s, b, free)
    }
}
