//
//  RidgeCanvas.swift
//  GymLock · Ridge hero
//
//  A small CanvasRenderingContext2D over a CoreGraphics bitmap, with exactly the subset the generated
//  Ridge painters use (see docs/hero-pack/swift/RIDGE-PORT.md). One design unit = one bitmap pixel.
//  Coordinates are canvas coordinates (y down); the bitmap's own CTM is flipped once at creation.
//  The canvas transform (`ctm`) is applied to path points as they are added, like a browser does,
//  so a later transform change never moves a path that is already built.
//

import CoreGraphics
import Foundation

@inline(__always) private func cgF(_ d: Double) -> CGFloat { CGFloat(d) }

// MARK: - Colour

/// A parsed CSS colour, channels 0...1, non-premultiplied.
struct C2DColor: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let clear = C2DColor(r: 0, g: 0, b: 0, a: 0)
    static let black = C2DColor(r: 0, g: 0, b: 0, a: 1)

    var cg: CGColor { CGColor(srgbRed: cgF(r), green: cgF(self.g), blue: cgF(b), alpha: cgF(a)) }

    private static var cache: [String: C2DColor] = [:]

    /// Parses `rgba()`, `rgb()`, `#rgb`, `#rrggbb`, `#rrggbbaa` and a few names. Unknown strings are black,
    /// like a canvas keeps its previous (default black) style.
    static func parse(_ s: String) -> C2DColor {
        if let hit = cache[s] { return hit }
        let c = parseUncached(s)
        if cache.count > 4096 { cache.removeAll(keepingCapacity: true) }
        cache[s] = c
        return c
    }

    private static func parseUncached(_ raw: String) -> C2DColor {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("rgb") {
            guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { return .black }
            let parts = s[s.index(after: open)..<close].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).compactMap { Double($0) }
            guard parts.count >= 3 else { return .black }
            let a = parts.count >= 4 ? max(0, min(1, parts[3])) : 1
            return C2DColor(r: max(0, min(255, parts[0])) / 255, g: max(0, min(255, parts[1])) / 255, b: max(0, min(255, parts[2])) / 255, a: a)
        }
        if s.hasPrefix("#") {
            let hex = Array(s.dropFirst())
            func nib(_ c: Character) -> Double { Double(c.hexDigitValue ?? 0) }
            switch hex.count {
            case 3, 4:
                let a = hex.count == 4 ? nib(hex[3]) * 17 / 255 : 1
                return C2DColor(r: nib(hex[0]) * 17 / 255, g: nib(hex[1]) * 17 / 255, b: nib(hex[2]) * 17 / 255, a: a)
            case 6, 8:
                func byte(_ i: Int) -> Double { (nib(hex[i]) * 16 + nib(hex[i + 1])) / 255 }
                return C2DColor(r: byte(0), g: byte(2), b: byte(4), a: hex.count == 8 ? byte(6) : 1)
            default:
                return .black
            }
        }
        switch s {
        case "transparent": return .clear
        case "white": return C2DColor(r: 1, g: 1, b: 1, a: 1)
        case "black": return .black
        default: return .black
        }
    }
}

// MARK: - Gradient

final class C2DGradient {
    enum Kind {
        case linear(Double, Double, Double, Double)
        case radial(Double, Double, Double, Double, Double, Double)
    }

    let kind: Kind
    private var stops: [(offset: Double, color: C2DColor, order: Int)] = []
    private var built: CGGradient?

    init(_ kind: Kind) { self.kind = kind }

    func addColorStop(_ offset: Double, _ color: String) {
        guard offset.isFinite else { return }
        stops.append((max(0, min(1, offset)), C2DColor.parse(color), stops.count))
        built = nil
    }

    /// Stops sorted by offset, insertion order breaking ties (as the canvas spec requires).
    var cgGradient: CGGradient? {
        if let built { return built }
        guard !stops.isEmpty else { return nil }
        var s = stops.sorted { $0.offset != $1.offset ? $0.offset < $1.offset : $0.order < $1.order }
        if s.count == 1 { s.append((1, s[0].color, 1)) }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = s.map { $0.color.cg } as CFArray
        var locs = s.map { CGFloat($0.offset) }
        built = CGGradient(colorsSpace: space, colors: colors, locations: &locs)
        return built
    }
}

// MARK: - Surface

/// A bitmap (an offscreen canvas or a snapshot of one).
final class C2DSurface {
    let width: Int
    let height: Int
    /// Present for surfaces that can be painted into (layer caches).
    let context: CGContext?
    private var image: CGImage?

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.context = C2D.makeBitmap(self.width, self.height)
        self.image = nil
    }

    init(snapshot: CGImage?, width: Int, height: Int) {
        self.width = width
        self.height = height
        self.context = nil
        self.image = snapshot
    }

    /// Call after painting into `context` so draws reuse one immutable image.
    func seal() { image = context?.makeImage() }

    var cgImage: CGImage? {
        if let image { return image }
        image = context?.makeImage()
        return image
    }
}

// MARK: - Style

enum C2DStyle: ExpressibleByStringLiteral {
    case color(C2DColor)
    case gradient(C2DGradient)
    case pattern(CGImage?, Int, Int)

    init(stringLiteral value: String) { self = .color(C2DColor.parse(value)) }
    init(_ s: String) { self = .color(C2DColor.parse(s)) }
    init(_ s: C2DStyle) { self = s }
    init(_ g: C2DGradient) { self = .gradient(g) }
}

// MARK: - Path2D

final class C2DPath {
    let path = CGMutablePath()

    init() {}

    func moveTo(_ x: Double, _ y: Double) {
        guard x.isFinite, y.isFinite else { return }
        path.move(to: CGPoint(x: x, y: y))
    }

    func lineTo(_ x: Double, _ y: Double) {
        guard x.isFinite, y.isFinite else { return }
        if path.isEmpty { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }

    func quadraticCurveTo(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
        guard (cx + cy + x + y).isFinite else { return }
        if path.isEmpty { path.move(to: CGPoint(x: cx, y: cy)) }
        path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
    }

    func bezierCurveTo(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
        guard (c1x + c1y + c2x + c2y + x + y).isFinite else { return }
        if path.isEmpty { path.move(to: CGPoint(x: c1x, y: c1y)) }
        path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
    }

    func closePath() {
        if !path.isEmpty { path.closeSubpath() }
    }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        path.addRect(CGRect(x: x, y: y, width: w, height: h))
    }
}

// MARK: - Context

final class C2D {
    struct State {
        var ctm: CGAffineTransform = .identity
        var alpha: Double = 1
        var composite: String = "source-over"
        var blend: CGBlendMode = .normal
        var fill: C2DStyle = .color(.black)
        var stroke: C2DStyle = .color(.black)
        var lineWidth: Double = 1
        var cap: CGLineCap = .butt
        var join: CGLineJoin = .miter
        var dash: [Double] = []
    }

    let cg: CGContext
    let widthPx: Int
    let heightPx: Int
    private var st = State()
    private var stack: [State] = []
    private var path = CGMutablePath()

    static func makeBitmap(_ w: Int, _ h: Int) -> CGContext? {
        guard let ctx = CGContext(
            data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(max(1, h)))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .medium
        ctx.setShouldAntialias(true)
        return ctx
    }

    /// Wraps an existing (already flipped) bitmap context.
    init(_ cg: CGContext, width: Int, height: Int) {
        self.cg = cg
        self.widthPx = width
        self.heightPx = height
    }

    /// Paints into a layer surface.
    convenience init?(surface: C2DSurface) {
        guard let c = surface.context else { return nil }
        self.init(c, width: surface.width, height: surface.height)
    }

    /// A snapshot of everything painted so far (the browser's `ctx.canvas` used as an image source).
    var canvas: C2DSurface { C2DSurface(snapshot: cg.makeImage(), width: widthPx, height: heightPx) }

    // MARK: state

    var globalAlpha: Double {
        get { st.alpha }
        set { if newValue.isFinite, newValue >= 0, newValue <= 1 { st.alpha = newValue } }
    }

    var globalCompositeOperation: String {
        get { st.composite }
        set {
            let m: CGBlendMode?
            switch newValue {
            case "source-over": m = .normal
            case "multiply": m = .multiply
            case "screen": m = .screen
            case "overlay": m = .overlay
            case "darken": m = .darken
            case "lighten": m = .lighten
            case "soft-light": m = .softLight
            case "hard-light": m = .hardLight
            case "color-dodge": m = .colorDodge
            case "color-burn": m = .colorBurn
            case "difference": m = .difference
            case "source-atop": m = .sourceAtop
            case "source-in": m = .sourceIn
            case "source-out": m = .sourceOut
            case "destination-out": m = .destinationOut
            case "destination-in": m = .destinationIn
            case "destination-over": m = .destinationOver
            case "destination-atop": m = .destinationAtop
            case "lighter": m = .plusLighter
            case "copy": m = .copy
            case "xor": m = .xor
            default: m = nil
            }
            if let m { st.composite = newValue; st.blend = m }
        }
    }

    var fillStyle: C2DStyle {
        get { st.fill }
        set { st.fill = newValue }
    }

    var strokeStyle: C2DStyle {
        get { st.stroke }
        set { st.stroke = newValue }
    }

    var lineWidth: Double {
        get { st.lineWidth }
        set { if newValue.isFinite, newValue > 0 { st.lineWidth = newValue } }
    }

    var lineCap: String {
        get { st.cap == .round ? "round" : st.cap == .square ? "square" : "butt" }
        set { st.cap = newValue == "round" ? .round : newValue == "square" ? .square : .butt }
    }

    var lineJoin: String {
        get { st.join == .round ? "round" : st.join == .bevel ? "bevel" : "miter" }
        set { st.join = newValue == "round" ? .round : newValue == "bevel" ? .bevel : .miter }
    }

    func setLineDash(_ d: [Double]) {
        guard d.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return }
        st.dash = d.count % 2 == 1 ? d + d : d
    }

    func save() {
        stack.append(st)
        cg.saveGState()
    }

    func restore() {
        guard let s = stack.popLast() else { return }
        st = s
        cg.restoreGState()
    }

    // MARK: transform

    func translate(_ x: Double, _ y: Double) {
        st.ctm = CGAffineTransform(translationX: cgF(x), y: cgF(y)).concatenating(st.ctm)
    }

    func scale(_ x: Double, _ y: Double) {
        st.ctm = CGAffineTransform(scaleX: cgF(x), y: cgF(y)).concatenating(st.ctm)
    }

    func rotate(_ a: Double) {
        st.ctm = CGAffineTransform(rotationAngle: cgF(a)).concatenating(st.ctm)
    }

    func transform(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) {
        st.ctm = CGAffineTransform(a: cgF(a), b: cgF(b), c: cgF(c), d: cgF(d), tx: cgF(e), ty: cgF(f)).concatenating(st.ctm)
    }

    func setTransform(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) {
        st.ctm = CGAffineTransform(a: cgF(a), b: cgF(b), c: cgF(c), d: cgF(d), tx: cgF(e), ty: cgF(f))
    }

    func setTransform(_ m: (Double, Double, Double, Double, Double, Double)) {
        setTransform(m.0, m.1, m.2, m.3, m.4, m.5)
    }

    func resetTransform() { st.ctm = .identity }

    // MARK: path

    func beginPath() { path = CGMutablePath() }

    private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y).applying(st.ctm) }

    func moveTo(_ x: Double, _ y: Double) {
        guard x.isFinite, y.isFinite else { return }
        path.move(to: pt(x, y))
    }

    func lineTo(_ x: Double, _ y: Double) {
        guard x.isFinite, y.isFinite else { return }
        if path.isEmpty { path.move(to: pt(x, y)) } else { path.addLine(to: pt(x, y)) }
    }

    func quadraticCurveTo(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
        guard (cx + cy + x + y).isFinite else { return }
        if path.isEmpty { path.move(to: pt(cx, cy)) }
        path.addQuadCurve(to: pt(x, y), control: pt(cx, cy))
    }

    func bezierCurveTo(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
        guard (c1x + c1y + c2x + c2y + x + y).isFinite else { return }
        if path.isEmpty { path.move(to: pt(c1x, c1y)) }
        path.addCurve(to: pt(x, y), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
    }

    func closePath() {
        if !path.isEmpty { path.closeSubpath() }
    }

    /// Canvas angles: increasing angle is clockwise on screen, which is CoreGraphics' counter-clockwise
    /// in the same (unflipped) numbers, so `clockwise:` takes the canvas `anticlockwise` flag as is.
    private static func arcEnd(_ a0: Double, _ a1: Double, _ ccw: Bool) -> Double {
        let tau = Double.pi * 2
        if !ccw, a1 - a0 >= tau { return a0 + tau }
        if ccw, a0 - a1 >= tau { return a0 - tau }
        return a1
    }

    func arc(_ x: Double, _ y: Double, _ r: Double, _ a0: Double, _ a1: Double, _ ccw: Bool = false) {
        guard (x + y + r + a0 + a1).isFinite, r >= 0 else { return }
        let e = Self.arcEnd(a0, a1, ccw)
        path.addArc(center: CGPoint(x: x, y: y), radius: cgF(r), startAngle: cgF(a0), endAngle: cgF(e), clockwise: ccw, transform: st.ctm)
    }

    func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ rot: Double, _ a0: Double, _ a1: Double, _ ccw: Bool = false) {
        guard (x + y + rx + ry + rot + a0 + a1).isFinite, rx >= 0, ry >= 0 else { return }
        if rx == 0 || ry == 0 { return }
        let e = Self.arcEnd(a0, a1, ccw)
        let m = CGAffineTransform(scaleX: cgF(rx), y: cgF(ry))
            .concatenating(CGAffineTransform(rotationAngle: cgF(rot)))
            .concatenating(CGAffineTransform(translationX: cgF(x), y: cgF(y)))
            .concatenating(st.ctm)
        path.addArc(center: .zero, radius: 1, startAngle: cgF(a0), endAngle: cgF(e), clockwise: ccw, transform: m)
    }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        guard (x + y + w + h).isFinite else { return }
        path.addRect(CGRect(x: x, y: y, width: w, height: h), transform: st.ctm)
    }

    func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
        guard (x + y + w + h + r).isFinite else { return }
        let rc = CGRect(x: x, y: y, width: w, height: h).standardized
        let rr = max(0, min(r, min(rc.width, rc.height) / 2))
        if rr <= 0 {
            path.addRect(rc, transform: st.ctm)
        } else {
            path.addRoundedRect(in: rc, cornerWidth: cgF(rr), cornerHeight: cgF(rr), transform: st.ctm)
        }
    }

    // MARK: painting

    private func prep() {
        cg.setAlpha(cgF(st.alpha))
        cg.setBlendMode(st.blend)
    }

    /// Fills a path that is already in bitmap space.
    private func fillBase(_ p: CGPath, _ style: C2DStyle) {
        if p.isEmpty { return }
        switch style {
        case .color(let c):
            if c.a <= 0, st.blend == .normal { return }
            prep()
            cg.setFillColor(red: cgF(c.r), green: cgF(c.g), blue: cgF(c.b), alpha: cgF(c.a))
            cg.addPath(p)
            cg.fillPath()
        case .gradient(let gr):
            guard let cgg = gr.cgGradient else { return }
            cg.saveGState()
            prep()
            cg.addPath(p)
            cg.clip()
            cg.concatenate(st.ctm)
            drawGradient(gr, cgg)
            cg.restoreGState()
        case .pattern(let img, let w, let h):
            guard let img else { return }
            cg.saveGState()
            prep()
            cg.addPath(p)
            cg.clip()
            cg.concatenate(st.ctm)
            cg.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h), byTiling: true)
            cg.restoreGState()
        }
    }

    private func drawGradient(_ gr: C2DGradient, _ cgg: CGGradient) {
        let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch gr.kind {
        case let .linear(x0, y0, x1, y1):
            cg.drawLinearGradient(cgg, start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), options: opts)
        case let .radial(x0, y0, r0, x1, y1, r1):
            cg.drawRadialGradient(cgg, startCenter: CGPoint(x: x0, y: y0), startRadius: cgF(r0), endCenter: CGPoint(x: x1, y: y1), endRadius: cgF(r1), options: opts)
        }
    }

    func fill() { fillBase(path, st.fill) }

    func fill(_ p: C2DPath) {
        var m = st.ctm
        guard let tp = p.path.copy(using: &m) else { return }
        fillBase(tp, st.fill)
    }

    func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        guard (x + y + w + h).isFinite else { return }
        let p = CGMutablePath()
        p.addRect(CGRect(x: x, y: y, width: w, height: h), transform: st.ctm)
        fillBase(p, st.fill)
    }

    func stroke() {
        if path.isEmpty { return }
        let ctm = st.ctm
        let det = ctm.a * ctm.d - ctm.b * ctm.c
        guard abs(det) > 1e-12 else { return }
        var inv = ctm.inverted()
        guard let local = path.copy(using: &inv) else { return }
        strokeLocal(local)
    }

    /// Path2D stroke: the path is in user space, transformed by the current matrix.
    func stroke(_ p: C2DPath) {
        if p.path.isEmpty { return }
        strokeLocal(p.path)
    }

    private func strokeLocal(_ local: CGPath) {
        let ctm = st.ctm
        cg.saveGState()
        prep()
        cg.concatenate(ctm)
        cg.addPath(local)
        cg.setLineWidth(cgF(st.lineWidth))
        cg.setLineCap(st.cap)
        cg.setLineJoin(st.join)
        cg.setMiterLimit(10)
        cg.setLineDash(phase: 0, lengths: st.dash.map { CGFloat($0) })
        switch st.stroke {
        case .color(let c):
            cg.setStrokeColor(red: cgF(c.r), green: cgF(c.g), blue: cgF(c.b), alpha: cgF(c.a))
            cg.strokePath()
        case .gradient(let gr):
            if let cgg = gr.cgGradient {
                cg.replacePathWithStrokedPath()
                cg.clip()
                drawGradient(gr, cgg)
            }
        case .pattern(let img, let w, let h):
            if let img {
                cg.replacePathWithStrokedPath()
                cg.clip()
                cg.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h), byTiling: true)
            }
        }
        cg.restoreGState()
    }

    func clearRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        cg.saveGState()
        cg.concatenate(st.ctm)
        cg.clear(CGRect(x: x, y: y, width: w, height: h))
        cg.restoreGState()
    }

    func clip() {
        if path.isEmpty {
            cg.clip(to: CGRect.zero)
            return
        }
        cg.addPath(path)
        cg.clip()
    }

    func clip(_ p: C2DPath) {
        var m = st.ctm
        guard let tp = p.path.copy(using: &m), !tp.isEmpty else {
            cg.clip(to: CGRect.zero)
            return
        }
        cg.addPath(tp)
        cg.clip()
    }

    // MARK: images

    func createLinearGradient(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> C2DGradient {
        C2DGradient(.linear(x0, y0, x1, y1))
    }

    func createRadialGradient(_ x0: Double, _ y0: Double, _ r0: Double, _ x1: Double, _ y1: Double, _ r1: Double) -> C2DGradient {
        C2DGradient(.radial(x0, y0, max(0, r0), x1, y1, max(0, r1)))
    }

    func createPattern(_ s: C2DSurface, _ repetition: String) -> C2DStyle {
        .pattern(s.cgImage, s.width, s.height)
    }

    func drawImage(_ s: C2DSurface, _ dx: Double, _ dy: Double) {
        drawImage(s, dx, dy, Double(s.width), Double(s.height))
    }

    func drawImage(_ s: C2DSurface, _ dx: Double, _ dy: Double, _ dw: Double, _ dh: Double) {
        guard let img = s.cgImage, (dx + dy + dw + dh).isFinite, dw != 0, dh != 0 else { return }
        cg.saveGState()
        prep()
        cg.concatenate(st.ctm)
        cg.translateBy(x: cgF(dx), y: cgF(dy + dh))
        cg.scaleBy(x: 1, y: -1)
        cg.draw(img, in: CGRect(x: 0, y: 0, width: dw, height: dh))
        cg.restoreGState()
    }

    /// The 9-argument form: clips to the destination and draws the whole image scaled so that the source
    /// rect lands on it (exact for fractional source rects, which the water reflection uses).
    func drawImage(_ s: C2DSurface, _ sx: Double, _ sy: Double, _ sw: Double, _ sh: Double, _ dx: Double, _ dy: Double, _ dw: Double, _ dh: Double) {
        guard let img = s.cgImage, (sx + sy + sw + sh + dx + dy + dw + dh).isFinite, sw > 0, sh > 0, dw != 0, dh != 0 else { return }
        let kx = dw / sw, ky = dh / sh
        let fw = Double(s.width) * kx, fh = Double(s.height) * ky
        let ox = dx - sx * kx, oy = dy - sy * ky
        cg.saveGState()
        prep()
        cg.concatenate(st.ctm)
        cg.clip(to: CGRect(x: dx, y: dy, width: dw, height: dh))
        cg.translateBy(x: cgF(ox), y: cgF(oy + fh))
        cg.scaleBy(x: 1, y: -1)
        cg.draw(img, in: CGRect(x: 0, y: 0, width: fw, height: fh))
        cg.restoreGState()
    }
}
