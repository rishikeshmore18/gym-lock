//
//  MissionMatrixArt.swift
//  GymLock
//
//  The approved Matrix pixel art (ported cell-for-cell from the web reference), parsed once into
//  lazily cached cell lists, plus the per-figure idle animations and edge cells for outline mode.
//
//  Art legend (character per cell): '#' solid (alpha 1), ':' light (alpha .35), '.' empty.
//  Other letters are idle groups: shoes a/b/c lace bars | shoesOn o bow | steps A..D prints |
//  water r ripple row, w water | bag h handle | door L leaf, W light wedge | mirror g glint |
//  check a accent | camera l lens glass.
//

import Foundation

/// One parsed figure: cells inside the trimmed bounding box, sorted by x then y.
nonisolated struct MissionMatrixCells: Sendable {
    let n: Int
    let w: Int
    let h: Int
    let x: [UInt16]
    let y: [UInt16]
    /// ASCII code of the art character (the idle group).
    let g: [UInt8]
    /// Base alpha per cell (1.0, or 0.35 for ':' and 'W').
    let a: [Float]
    /// 1 when the cell has an empty 4-neighbour (or touches the bounding box).
    let edge: [UInt8]
    /// Indices (into the arrays above) of the edge cells, in order. Used by outline mode.
    let edgeIndex: [Int]
    var ne: Int { edgeIndex.count }
    /// True for the check figure's accent cell ('a').
    func isAccent(_ i: Int, figure: MissionFigure) -> Bool { figure == .check && g[i] == 97 }
}

nonisolated enum MissionMatrixArt {
    // MARK: - Parsing

    static func baseAlpha(_ ch: UInt8) -> Float {
        if ch == 58 { return 0.35 }   // ':'
        if ch == 87 { return 0.35 }   // 'W' light wedge
        return 1
    }

    /// Trim to the bounding box, optionally scale by an integer, sort by x then y, flag edge cells.
    static func parse(_ rows: [String], scale: Int) -> MissionMatrixCells {
        let grid: [[UInt8]] = rows.map { Array($0.utf8) }
        var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
        for (y, row) in grid.enumerated() {
            for (x, ch) in row.enumerated() where ch != 46 {
                if x < x0 { x0 = x }
                if x > x1 { x1 = x }
                if y < y0 { y0 = y }
                if y > y1 { y1 = y }
            }
        }
        if x1 < 0 {
            return MissionMatrixCells(n: 0, w: 0, h: 0, x: [], y: [], g: [], a: [], edge: [], edgeIndex: [])
        }
        let w0 = x1 - x0 + 1, h0 = y1 - y0 + 1
        let w = w0 * scale, h = h0 * scale
        var occ = [Bool](repeating: false, count: w * h)
        var chr = [UInt8](repeating: 46, count: w * h)
        for y in 0..<h0 {
            for x in 0..<w0 {
                let row = grid[y + y0]
                let ch: UInt8 = (x + x0) < row.count ? row[x + x0] : 46
                if ch == 46 { continue }
                for j in 0..<scale {
                    for i in 0..<scale {
                        let idx = (y * scale + j) * w + x * scale + i
                        occ[idx] = true
                        chr[idx] = ch
                    }
                }
            }
        }
        var xs: [UInt16] = [], ys: [UInt16] = [], gs: [UInt8] = [], alphas: [Float] = []
        var edges: [UInt8] = [], edgeIdx: [Int] = []
        for x in 0..<w {
            for y in 0..<h {
                if !occ[y * w + x] { continue }
                var e = x == 0 || y == 0 || x == w - 1 || y == h - 1
                if !e {
                    let here = y * w + x
                    e = !occ[here - 1] || !occ[here + 1] || !occ[here - w] || !occ[here + w]
                }
                if e { edgeIdx.append(xs.count) }
                xs.append(UInt16(x)); ys.append(UInt16(y))
                gs.append(chr[y * w + x]); alphas.append(baseAlpha(chr[y * w + x]))
                edges.append(e ? 1 : 0)
            }
        }
        return MissionMatrixCells(n: xs.count, w: w, h: h, x: xs, y: ys, g: gs, a: alphas,
                                  edge: edges, edgeIndex: edgeIdx)
    }

    // MARK: - Cached cell lists

    /// Index of a figure in `MissionFigure.allCases` order (exhaustive, no lookup).
    static func index(of figure: MissionFigure) -> Int {
        switch figure {
        case .shoes: return 0
        case .shoesOn: return 1
        case .steps: return 2
        case .water: return 3
        case .bag: return 4
        case .door: return 5
        case .mirror: return 6
        case .check: return 7
        case .camera: return 8
        }
    }

    private static let bigCells: [MissionMatrixCells] = MissionFigure.allCases.map { parse(bigRows($0), scale: 1) }
    private static let smallCells: [MissionMatrixCells] = MissionFigure.allCases.map { parse(smallRows($0), scale: 1) }

    static func big(_ figure: MissionFigure) -> MissionMatrixCells { bigCells[index(of: figure)] }
    static func small(_ figure: MissionFigure) -> MissionMatrixCells { smallCells[index(of: figure)] }

    /// Big art when it fits the board, else the 13x9 art scaled by an integer.
    static func cells(for figure: MissionFigure, cols: Int, rows: Int) -> MissionMatrixCells {
        let b = big(figure)
        if b.w <= cols && b.h <= rows { return b }
        let k = max(1, min(cols / 13, rows / 9))
        return k == 1 ? small(figure) : parse(smallRows(figure), scale: k)
    }

    // MARK: - Raw art

    static func bigRows(_ figure: MissionFigure) -> [String] {
        switch figure {
        case .shoes: return bigShoes
        case .shoesOn: return bigShoesOn
        case .steps: return bigSteps
        case .water: return bigWater
        case .bag: return bigBag
        case .door: return bigDoor
        case .mirror: return bigMirror
        case .check: return bigCheck
        case .camera: return bigCamera
        }
    }

    static func smallRows(_ figure: MissionFigure) -> [String] {
        switch figure {
        case .shoes: return smallShoes
        case .shoesOn: return smallShoesOn
        case .steps: return smallSteps
        case .water: return smallWater
        case .bag: return smallBag
        case .door: return smallDoor
        case .mirror: return smallMirror
        case .check: return smallCheck
        case .camera: return smallCamera
        }
    }

    // MARK: - Big art

    static let bigShoes: [String] = [
        "..##..........................",
        "..####........................",
        ".#####....##..................",
        ".#############................",
        ".################.............",
        ".###################..........",
        ".###############.######.......",
        ".###########.##.###.######....",
        ".########...######.###.#####..",
        ".#####...############.#######.",
        ".##...#######################.",
        ".#############################",
        ".#######################......",
        "........................######",
        "##############################",
        "########################......",
    ]

    static let bigShoesOn: [String] = [
        "......###.....................",
        ".....#####....................",
        ".....#####....................",
        ".....#...#....................",
        ".....#####....................",
        ".....#...#....................",
        "..##.#####....................",
        "..########....................",
        ".###########..................",
        ".#############................",
        ".################.............",
        ".###################..........",
        ".###############.######.......",
        ".###########.##.###.######....",
        ".########...######.###.#####..",
        ".#####...############.#######.",
        ".##...#######################.",
        ".#############################",
        ".#######################......",
        "........................######",
        "##############################",
        "########################......",
    ]

    static let bigSteps: [String] = [
        "............................DDD.",
        "...........................DDDDD",
        "...........................DDDDD",
        "....................CCC...DDDDD.",
        "...................CCCCC..DDDDD.",
        "...................CCCCC...DDDD.",
        "..................CCCCC.....DDD.",
        "............BBB...CCCCC....DDD..",
        "...........BBBBB..CCCC..........",
        "...........BBBBB..CCC.....DDDD..",
        "....AAA...BBBBB..CCC.....DDDD...",
        "...AAAAA..BBBBB...........DD....",
        "...AAAAA...BBBB..CCCC...........",
        "..AAAAA.....BBB.CCCC............",
        "..AAAAA....BBB...CC.............",
        "..AAAA..........................",
        "..AAA.....BBBB..................",
        ".AAA.....BBBB...................",
        "..........BB....................",
        ".AAAA...........................",
        "AAAA............................",
        ".AA.............................",
    ]

    static let bigWater: [String] = [
        ".....##....",
        "....####...",
        "..#######..",
        "..#######..",
        "..#######..",
        "...#####...",
        "...#:::#...",
        "..#:::::#..",
        ".#:::::::#.",
        "#:::::::::#",
        "#.........#",
        "#.........#",
        "#:::::::::#",
        "#:::::::::#",
        "#rrrrrrrrr#",
        "#wwwwwwwww#",
        "#wwwwwwwww#",
        "#wwwwwwwww#",
        "#wwwwwwwww#",
        "#wwwwwwwww#",
        "#wwwwwwwww#",
        ".#########.",
    ]

    static let bigBag: [String] = [
        ".........hhhhhhhh.........",
        "........h........h........",
        "........h........h........",
        ".....################.....",
        "...####################...",
        "..######################..",
        ".##........##..........##.",
        "###.######.##.########.###",
        "###.######.##.########.###",
        "###.######....########.###",
        ".##.##################.##.",
        "..######################..",
        "...####################...",
        ".....################.....",
    ]

    static let bigDoor: [String] = [
        "..########LL########..........",
        "..#####LLLLL########..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLL.L......##..........",
        "..##.LLLLL.L......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        "..##.LLLLLLL......##..........",
        ".......LLLLL..................",
        "..........LL..................",
        "...........WWWWWW.............",
        "............WWWWWWWWWW........",
        ".............WWWWWWWWWWWWWW...",
        "..............................",
    ]

    static let bigMirror: [String] = [
        "....#####...............",
        "..#########.............",
        "..##.....##.............",
        ".##.......##.....##.##..",
        "###.......###....##.##..",
        "##...g.....##....#..#...",
        "##..g......##...........",
        "##.g.......##...........",
        "##.........##...........",
        "##...g.....##...........",
        "##..g......##...........",
        "##.g.......##...........",
        "###.......###...........",
        ".##.......##............",
        "..##.....##.............",
        "..#########.............",
        "....#####...............",
        ".....##.................",
        ".....##.................",
        ".##########.............",
        ".##########.............",
    ]

    static let bigCheck: [String] = [
        ".....................#a.",
        "....................##..",
        "...................##...",
        "..................##....",
        ".................##.....",
        "................##......",
        "...............##.......",
        "##............##........",
        ".##..........##.........",
        "..##........##..........",
        "...##......##...........",
        "....##....##............",
        ".....##..##.............",
        "......####..............",
        ".......##...............",
        "........................",
    ]

    static let bigCamera: [String] = [
        "............................",
        "..........########..........",
        ".........#........#..####...",
        ".........#........#..####...",
        "..########################..",
        ".#........................#.",
        "#...........####...........#",
        "#..##.....###..###.........#",
        "#.........#......#.........#",
        "#........##..ll..##........#",
        "#........#..llll..#........#",
        "#........#..llll..#........#",
        "#........##..ll..##........#",
        "#.........#......#.........#",
        "#.........###..###.........#",
        "#...........####...........#",
        ".#........................#.",
        "..########################..",
    ]

    // MARK: - Small art

    static let smallShoes: [String] = [
        ".............",
        ".###.........",
        ".#######.....",
        ".#########...",
        ".###########.",
        ".###########.",
        "............#",
        "############.",
        ".............",
    ]

    static let smallShoesOn: [String] = [
        "....##.......",
        "....##.......",
        ".#####.......",
        ".#######.....",
        ".#########...",
        ".###########.",
        ".###########.",
        "............#",
        "############.",
    ]

    static let smallSteps: [String] = [
        ".............",
        "........##...",
        "........##...",
        "........##...",
        "...##........",
        "...##...##...",
        "...##........",
        ".............",
        "...##........",
    ]

    static let smallWater: [String] = [
        "..##.",
        ".####",
        "#####",
        ".###.",
        "#:::#",
        "#:::#",
        "#www#",
        "#www#",
        ".###.",
    ]

    static let smallBag: [String] = [
        "....#####....",
        "...#.....#...",
        "..#########..",
        "#############",
        "#...........#",
        "#############",
        "#############",
        ".###########.",
        "..#########..",
    ]

    static let smallDoor: [String] = [
        "..###LL####..",
        "..#LLLL...#..",
        "..#LLLL...#..",
        "..#LLLL...#..",
        "..#LL.L...#..",
        "..#LLLL...#..",
        "..#LLLL...#..",
        "..#LLLL...#..",
        ".....LL......",
    ]

    static let smallMirror: [String] = [
        ".#####.",
        "#.....#",
        "#.....#",
        "#.....#",
        "#.....#",
        "#.....#",
        ".#####.",
        "...#...",
        "#######",
    ]

    static let smallCheck: [String] = [
        ".........##",
        "........##.",
        "#......##..",
        "##....##...",
        ".##..##....",
        "..####.....",
        "...##......",
    ]

    static let smallCamera: [String] = [
        "...###..##..",
        ".##########.",
        "#..........#",
        "#...####...#",
        "#..##..##..#",
        "#..#.##.#..#",
        "#..##..##..#",
        "#...####...#",
        ".##########.",
    ]

}

// MARK: - Idle animations

/// Per-cell offset (in cells) and alpha multiplier from a figure's clock `t` (seconds).
nonisolated struct MissionMatrixIdleOffset: Sendable {
    var dx: Float
    var dy: Float
    var alpha: Float
    static let none = MissionMatrixIdleOffset(dx: 0, dy: 0, alpha: 1)
}

nonisolated enum MissionMatrixIdle {
    private static let tau = Double.pi * 2

    private static func smooth(_ a: Double, _ b: Double, _ v: Double) -> Double {
        let t = min(1, max(0, (v - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// `g` is the cell's art character (ASCII), `x`/`y` its position inside the figure's bounding box.
    static func cell(_ figure: MissionFigure, g: UInt8, x: Float, y: Float, t: Double) -> MissionMatrixIdleOffset {
        var dx = 0.0, dy = 0.0, a = 1.0
        switch figure {
        case .steps:
            // Prints appear fully inked in walking order; the oldest fades out (loop 2.4 s,
            // always at least one print inked).
            let i = Int(g) - 65
            if i < 0 || i > 3 { break }
            let tt = t.truncatingRemainder(dividingBy: 2.4)
            let fi = Double(i)
            if i < 3 {
                a = smooth(0.4 * fi, 0.4 * fi + 0.18, tt) * (1 - smooth(1.9 + 0.1 * fi, 2.1 + 0.1 * fi, tt))
            } else {
                a = tt < 1.2 ? 1 - smooth(0.35, 0.55, tt) : smooth(1.2, 1.38, tt)
            }
        case .bag:
            // Handle lifts a touch and settles.
            if g == 104 { dy = -0.5 * (0.5 - 0.5 * cos(tau * t / 3)) }
        case .door:
            // Leaf eases open, light breathes.
            let e = 0.5 - 0.5 * cos(tau * t / 3.5)
            if g == 76 {
                dx = (Double(x) - 3) / 6 * e
            } else if g == 87 {
                dx = (Double(x) - 9) * 0.12 * e
                a = 0.7 + 0.6 * e
            }
        case .mirror:
            // Glint sweeps across the glass.
            if g == 103 {
                let u = t.truncatingRemainder(dividingBy: 2.5) / 2.5
                dx = -2 + 4 * u
                let s = sin(Double.pi * u)
                a = 0.2 + 0.8 * s * s
            }
        case .check:
            a = 0.95 + 0.05 * sin(tau * t / 3)
        case .camera:
            if g == 108 { a = 0.65 + 0.35 * (0.5 + 0.5 * sin(tau * t / 2.4)) }
        case .shoes, .shoesOn, .water:
            break
        }
        return MissionMatrixIdleOffset(dx: Float(dx), dy: Float(dy), alpha: Float(a))
    }
}
