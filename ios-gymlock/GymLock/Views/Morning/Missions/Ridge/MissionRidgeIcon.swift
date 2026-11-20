//
//  MissionRidgeIcon.swift
//  GymLock
//
//  The Ridge line icons: a port of drawRidgeIcon (ridge.ts). SF Symbols style on a 24-unit grid, stroke
//  size/12 (2 units), round caps and joins, centred in a size x size box.
//

import SwiftUI

/// Canvas-style path builder in the 24-unit grid. `at` sets a local translate/rotate/scale (like ctx.translate, rotate, scale).
nonisolated struct MissionRidgePen {
    private(set) var path = Path()
    private let grid: CGAffineTransform
    private var local = CGAffineTransform.identity

    init(grid: CGAffineTransform) {
        self.grid = grid
    }

    /// Local frame: point -> scale k, then rotate rot, then translate (dx, dy).
    mutating func at(dx: CGFloat, dy: CGFloat, k: CGFloat, rot: CGFloat) {
        local = CGAffineTransform(scaleX: k, y: k)
            .concatenating(CGAffineTransform(rotationAngle: rot))
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    private var total: CGAffineTransform {
        return local.concatenating(grid)
    }

    private func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: x, y: y).applying(total)
    }

    mutating func move(_ x: CGFloat, _ y: CGFloat) {
        path.move(to: map(x, y))
    }

    mutating func line(_ x: CGFloat, _ y: CGFloat) {
        path.addLine(to: map(x, y))
    }

    /// quadraticCurveTo(cx, cy, x, y)
    mutating func quad(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        path.addQuadCurve(to: map(x, y), control: map(cx, cy))
    }

    mutating func close() {
        path.closeSubpath()
    }

    mutating func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        let r = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
        path.addPath(Path(ellipseIn: r).applying(total))
    }

    mutating func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        ellipse(cx, cy, r, r)
    }

    /// Rounded rectangle (the `rr` helper): radius clamped to half the shorter side.
    mutating func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        let rad = min(r, w / 2, h / 2)
        let rect = CGRect(x: x, y: y, width: w, height: h)
        path.addPath(Path(roundedRect: rect, cornerRadius: rad, style: .circular).applying(total))
    }
}

/// The paths, one function per figure (coordinates copied from ridge.ts ICONS).
nonisolated enum MissionRidgeIconPaths {
    static func sneaker(_ p: inout MissionRidgePen, dy: CGFloat, k: CGFloat) {
        p.at(dx: 0, dy: dy, k: k, rot: 0)
        p.rrect(-10.6, 4.6, 21.6, 3.4, 1.7)
        p.move(-9.4, 4.6)
        p.line(-9.4, -5)
        p.quad(-9.4, -7, -7.4, -7)
        p.line(-5.9, -7)
        p.quad(-4.7, -7, -4.3, -5.8)
        p.quad(-3.8, -3.8, -1.6, -3.1)
        p.quad(1.6, -2.5, 3.8, -0.2)
        p.quad(5.6, 1.9, 8.6, 2.7)
        p.quad(10.4, 3.2, 10.4, 4.6)
        p.move(-2.2, -0.7)
        p.line(0.2, -2.3)
        p.move(0.6, 1.4)
        p.line(2.6, -0.3)
    }

    static func shoes(_ p: inout MissionRidgePen) {
        sneaker(&p, dy: -0.5, k: 1)
    }

    static func shoesOn(_ p: inout MissionRidgePen) {
        sneaker(&p, dy: 3.2, k: 0.86)
        p.at(dx: 0, dy: 0, k: 1, rot: 0)
        p.move(-6.6, -3.2)
        p.line(-6.6, -11)
        p.move(-1.8, -2.6)
        p.line(-1.8, -11)
    }

    static func foot(_ p: inout MissionRidgePen, cx: CGFloat, cy: CGFloat, rot: CGFloat) {
        p.at(dx: cx, dy: cy, k: 1, rot: rot)
        p.ellipse(0, -2.2, 3.1, 4.5)
        p.ellipse(0, 5.2, 2.2, 1.9)
    }

    static func steps(_ p: inout MissionRidgePen) {
        foot(&p, cx: -5, cy: 3, rot: -0.12)
        foot(&p, cx: 5.2, cy: -1.6, rot: 0.12)
    }

    static func water(_ p: inout MissionRidgePen) {
        p.at(dx: 0, dy: 0, k: 1, rot: 0)
        p.move(-4.4, 9.4)
        p.quad(-4.4, 11.2, -2.6, 11.2)
        p.line(2.6, 11.2)
        p.quad(4.4, 11.2, 4.4, 9.4)
        p.line(4.4, -1.6)
        p.quad(4.4, -4.2, 2.4, -5.8)
        p.line(2.4, -7.2)
        p.line(-2.4, -7.2)
        p.line(-2.4, -5.8)
        p.quad(-4.4, -4.2, -4.4, -1.6)
        p.close()
        p.rrect(-2.4, -10.6, 4.8, 3.4, 1.2)
        p.move(-4.4, 2.2)
        p.line(4.4, 2.2)
        p.move(-4.4, 6.4)
        p.line(4.4, 6.4)
    }

    static func bag(_ p: inout MissionRidgePen) {
        p.at(dx: 0, dy: 0, k: 1, rot: 0)
        p.move(-4.6, -3.2)
        p.quad(-4.6, -8.2, 0, -8.2)
        p.quad(4.6, -8.2, 4.6, -3.2)
        p.move(-10.4, 5.2)
        p.quad(-10.4, -3.2, -6.2, -3.2)
        p.line(6.2, -3.2)
        p.quad(10.4, -3.2, 10.4, 5.2)
        p.quad(10.4, 8.6, 7.2, 8.6)
        p.line(-7.2, 8.6)
        p.quad(-10.4, 8.6, -10.4, 5.2)
        p.close()
        p.move(-10.2, 1.2)
        p.line(10.2, 1.2)
        p.move(0, 1.2)
        p.line(0, 4.4)
    }

    static func door(_ p: inout MissionRidgePen) {
        p.at(dx: 0, dy: 0, k: 1, rot: 0)
        p.move(-6.8, -10.6)
        p.line(6.6, -10.6)
        p.line(6.6, 11)
        p.move(-10.4, 11)
        p.line(10.4, 11)
        p.move(-6.8, -10.6)
        p.line(1.6, -8.1)
        p.line(1.6, 8.6)
        p.line(-6.8, 11)
        p.close()
    }

    static func mirror(_ p: inout MissionRidgePen) {
        p.at(dx: 0, dy: 0, k: 1, rot: 0)
        p.ellipse(0, -2.6, 6.6, 8.6)
        p.move(0, 6)
        p.line(0, 11.4)
        p.move(-4.6, 11.4)
        p.line(4.6, 11.4)
        p.move(-3.1, -6.6)
        p.quad(-3.9, -4.4, -3.3, -2)
    }

    static func check(_ p: inout MissionRidgePen) {
        p.at(dx: 0, dy: 0, k: 1, rot: 0)
        p.move(-7.2, 0.6)
        p.line(-2.4, 5.6)
        p.line(7.6, -5.8)
    }

    static func camera(_ p: inout MissionRidgePen) {
        p.at(dx: 0, dy: 0, k: 1, rot: 0)
        p.move(-4.2, -6)
        p.line(-2.9, -8.6)
        p.quad(-2.6, -9, -2.1, -9)
        p.line(2.1, -9)
        p.quad(2.6, -9, 2.9, -8.6)
        p.line(4.2, -6)
        p.line(7, -6)
        p.quad(10.6, -6, 10.6, -2.4)
        p.line(10.6, 5)
        p.quad(10.6, 8.6, 7, 8.6)
        p.line(-7, 8.6)
        p.quad(-10.6, 8.6, -10.6, 5)
        p.line(-10.6, -2.4)
        p.quad(-10.6, -6, -7, -6)
        p.close()
        p.circle(0, 1.7, 4.3)
    }
}

/// The stroked outline of a figure, centred in the shape's rect (24 units = min side).
struct MissionRidgeIconShape: Shape {
    let figure: MissionFigure

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let s = side / 24
        let grid = CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        var p = MissionRidgePen(grid: grid)
        switch figure {
        case .shoes: MissionRidgeIconPaths.shoes(&p)
        case .shoesOn: MissionRidgeIconPaths.shoesOn(&p)
        case .steps: MissionRidgeIconPaths.steps(&p)
        case .water: MissionRidgeIconPaths.water(&p)
        case .bag: MissionRidgeIconPaths.bag(&p)
        case .door: MissionRidgeIconPaths.door(&p)
        case .mirror: MissionRidgeIconPaths.mirror(&p)
        case .check: MissionRidgeIconPaths.check(&p)
        case .camera: MissionRidgeIconPaths.camera(&p)
        }
        return p.path
    }
}

/// The door's knob: the only filled mark (arc at (-1.4, 0.8), r 1.3).
struct MissionRidgeIconKnob: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let c = CGPoint(x: rect.midX - 1.4 * s, y: rect.midY + 0.8 * s)
        let r = 1.3 * s
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

/// SF Symbols-style line icon for a mission figure.
struct MissionRidgeIcon: View {
    let figure: MissionFigure
    let size: CGFloat
    let color: Color

    init(figure: MissionFigure, size: CGFloat, color: Color) {
        self.figure = figure
        self.size = size
        self.color = color
    }

    var body: some View {
        ZStack {
            MissionRidgeIconShape(figure: figure)
                .stroke(color, style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
            if figure == .door {
                MissionRidgeIconKnob().fill(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
