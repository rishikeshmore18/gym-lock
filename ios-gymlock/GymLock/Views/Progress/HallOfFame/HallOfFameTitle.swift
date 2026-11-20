import SwiftUI
import UIKit

/// "Hall of Fame": 40 pt heavy big, then a glide to the small top-middle title.
/// Matrix: LED dots fly into the word and resolve. Ridge: soft wavy ink wipe
/// left to right, each letter rising on a spring and de-blurring.
struct HallOfFameTitle: View {
    let progress: Double
    let glide: Double
    let style: HeroCardStyle
    let counter: String?

    private static let bigScale: CGFloat = 40.0 / 22.0
    /// Reveal span in src milliseconds (src T0 1000 to 1850).
    private static let spanMS: Double = 850

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let size = geo.size
            let finalCy = safeTop + 19
            let bigCy = max(120, size.height * 0.30)
            let g = min(max(glide, 0), 1) // already eased by ReelScene (settle)
            let cy = bigCy + (finalCy - bigCy) * g
            let sc = Self.bigScale + (1 - Self.bigScale) * g
            let ms = min(max(progress, 0), 1) * Self.spanMS

            ZStack {
                if style == .matrix {
                    TitleDotsCanvas(ms: ms, size: size)
                }
                word(ms: ms)
            }
            .scaleEffect(sc)
            .position(x: size.width / 2, y: cy)

            Text(counter ?? " ")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.inkTertiary)
                .opacity(counter == nil ? 0 : 1)
                .position(x: size.width / 2, y: finalCy + 24)
                .animation(.easeOut(duration: 0.18), value: counter)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hall of Fame")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Word

    @ViewBuilder
    private func word(ms: Double) -> some View {
        let chars = TitleGeometry.chars
        if style == .matrix {
            let o = Self.clamp((ms - 600) / 220)
            HStack(spacing: 0) {
                ForEach(chars.indices, id: \.self) { i in
                    letter(chars[i]).opacity(o)
                }
            }
        } else {
            let wp = Self.turn(Self.clamp(ms / 720))
            HStack(spacing: 0) {
                ForEach(chars.indices, id: \.self) { i in
                    let u = Self.clamp((ms - 35 * Double(i)) / 380)
                    let sp = u >= 1 ? 1 : 1 - exp(-5.5 * u) * cos(9 * u)
                    letter(chars[i])
                        .opacity(Self.clamp(u * 2.5))
                        .offset(y: 16 * (1 - sp))
                        .blur(radius: u >= 1 ? 0 : 6 * (1 - u))
                }
            }
            .mask {
                if wp < 1 {
                    WipeMask(edge: (TitleGeometry.width + 40) * wp - 6)
                        .frame(width: TitleGeometry.width + 40, height: 60)
                } else {
                    Rectangle().frame(width: TitleGeometry.width + 40, height: 60)
                }
            }
        }
    }

    private func letter(_ ch: Character) -> some View {
        Text(String(ch))
            .font(.system(size: 22, weight: .heavy))
            .tracking(TitleGeometry.tracking)
            .foregroundStyle(Theme.ink)
            .fixedSize()
    }

    // MARK: Easing

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func settle(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private static func turn(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
}

// MARK: - Geometry shared by the letters and the dots

private enum TitleGeometry {
    static let text = "Hall of Fame"
    static let chars = Array(text)
    static let tracking: CGFloat = -0.44
    static let font = UIFont.systemFont(ofSize: 22, weight: .heavy)

    static let widths: [CGFloat] = chars.map {
        (String($0) as NSString).size(withAttributes: [.font: font]).width + tracking
    }
    static let width: CGFloat = widths.reduce(0, +)
}

// MARK: - Ridge wipe mask: a soft, wavy right edge

private struct WipeMask: View {
    let edge: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let e = max(edge, 0)
            var p = Path()
            p.move(to: CGPoint(x: -40, y: 0))
            p.addLine(to: CGPoint(x: e - 10, y: 0))
            let period: CGFloat = 14
            var y: CGFloat = 0
            while y < size.height {
                p.addQuadCurve(to: CGPoint(x: e - 10, y: min(y + period, size.height)),
                               control: CGPoint(x: e + 10, y: y + period / 2))
                y += period
            }
            p.addLine(to: CGPoint(x: -40, y: size.height))
            p.closeSubpath()
            ctx.fill(p, with: .color(.black))
        }
        .blur(radius: 2.5)
    }
}

// MARK: - Matrix dots

private struct TitleDot: Sendable {
    let x: CGFloat      // target, 22 pt space, relative to the word centre
    let y: CGFloat
    let letter: Int
    let rx: CGFloat     // scatter, -0.5...0.5
    let ry: CGFloat
}

private enum TitleDots {
    static let list: [TitleDot] = build()

    private static func build() -> [TitleDot] {
        let big = 40.0 / 22.0
        let ow = 80, oh = 80
        let cell: CGFloat = 3.4
        let font = UIFont.systemFont(ofSize: 40, weight: .heavy)
        var rs: Double = 7
        func rnd() -> CGFloat { rs = (rs * 16807).truncatingRemainder(dividingBy: 2147483647); return CGFloat(rs / 2147483647) }
        var out: [TitleDot] = []
        var left: CGFloat = -TitleGeometry.width / 2
        for (l, ch) in TitleGeometry.chars.enumerated() {
            let wl = TitleGeometry.widths[l]
            defer { left += wl }
            if ch == " " { continue }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: ow * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let raw = ctx.data else { continue }
            ctx.translateBy(x: 0, y: CGFloat(oh))
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            (String(ch) as NSString).draw(at: CGPoint(x: 2, y: CGFloat(oh) / 2 + 2 - font.lineHeight / 2),
                                          withAttributes: [.font: font, .foregroundColor: UIColor.black])
            UIGraphicsPopContext()
            let px = raw.bindMemory(to: UInt8.self, capacity: ow * oh * 4)
            let wb = wl * big
            let xb = left * big
            var y: CGFloat = 0
            while y < CGFloat(oh) {
                var x: CGFloat = 0
                while x < min(CGFloat(ow), wb + 6) {
                    let col = Int(x + cell / 2), row = Int(y + cell / 2)
                    if col < ow, row < oh, px[(row * ow + col) * 4 + 3] > 110 {
                        let tx = (xb + x - 2 + cell / 2) / big
                        let ty = (y - CGFloat(oh) / 2 + cell / 2) / big
                        out.append(TitleDot(x: tx, y: ty, letter: l, rx: rnd() - 0.5, ry: rnd() - 0.5))
                    }
                    x += cell
                }
                y += cell
            }
        }
        return out
    }
}

private struct TitleDotsCanvas: View {
    let ms: Double
    let size: CGSize

    var body: some View {
        let big = 40.0 / 22.0
        Canvas { ctx, sz in
            guard ms < 850, ms > 0 else { return }
            let fade = 1 - min(max((ms - 600) / 220, 0), 1)
            var path = Path()
            let cx = sz.width / 2, cy = sz.height / 2
            for d in TitleDots.list {
                let u = min(max((ms - 35 * Double(d.letter)) / 520, 0), 1)
                if u <= 0 { continue }
                let e = 1 - pow(1 - u, 3)
                let sx = d.rx * size.width * 1.1 / big
                let sy = d.ry * 330 / big
                let x = cx + sx + (d.x - sx) * e
                let y = cy + sy + (d.y - sy) * e
                let r = 1.55 / big * min(1, u * 5)
                path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            ctx.opacity = fade
            ctx.fill(path, with: .color(Theme.ink))
        }
        .frame(width: size.width, height: 400)
    }
}
