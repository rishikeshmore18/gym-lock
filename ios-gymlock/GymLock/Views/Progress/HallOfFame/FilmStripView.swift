import SwiftUI
import UIKit

// MARK: - Style constants

/// Fixed film constants shared by the strip (and the reel, via the contract).
struct HallOfFameStyle {
    /// The film base. Film is film: the same in both card styles.
    static let filmBase = Color(red: 0.067, green: 0.067, blue: 0.067)
    /// Sprocket pitch in points, from src `pitch()`.
    static let sprocketPitch: (matrix: CGFloat, ridge: CGFloat) = (16, 22)
}

// MARK: - Strip

/// The live film strip: a vertical scroll of frames between two sprocket columns.
///
/// Geometry notes (see src.html `buildStrip`):
/// - The view is expected to fill the full screen height. `topInset` and
///   `bottomInset` are applied as scroll content margins, so the first frame
///   rests `topInset` below the top of this view.
/// - `pinchAnchor` is a unit point in this view's own (viewport) space. It is
///   converted to the frames container's space internally.
struct FilmStripView: View {
    let sections: [HallOfFameSection]
    let level: HallOfFameLevel
    let style: HeroCardStyle
    let stripWidth: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let pinchScale: CGFloat
    let pinchAnchor: UnitPoint
    @Binding var scrollPosition: String?
    let onTapFrame: (HallOfFameFrame) -> Void
    let onReachStart: () -> Void

    @State private var viewport = CGSize(width: 393, height: 852)
    @State private var offsetBox = ScrollOffsetBox()

    private let leaderHeight: CGFloat = 80
    private let sprocketWidth: CGFloat = 26

    private var isDemo: Bool {
        guard let first = sections.first?.frames.first else { return false }
        if case .demo = first.content { return true }
        return false
    }

    private var layout: StripLayout {
        StripLayout(
            sections: sections,
            level: level,
            stripWidth: stripWidth,
            sprocketWidth: sprocketWidth,
            viewportHeight: viewport.height,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    var body: some View {
        let lay = layout
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                strip(lay)
                    .frame(width: stripWidth)
                    .zIndex(1)
                endArt
            }
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.top, topInset, for: .scrollContent)
        .contentMargins(.bottom, bottomInset, for: .scrollContent)
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .scrollTargetBehavior(FilmSnapBehavior(isPaging: level == .photo))
        .onChange(of: scrollPosition) { _, new in
            if let new, let lead = lay.rowLead[new], lead != new { scrollPosition = lead }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            offsetBox.y = y
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        .overlay {
            if style == .matrix {
                FilmMatrixGlow(box: offsetBox, stripWidth: stripWidth, sprocketWidth: sprocketWidth)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Strip body

    private func strip(_ lay: StripLayout) -> some View {
        ZStack(alignment: .top) {
            filmLayer(lay)
            framesLayer(lay)
        }
        .background(HallOfFameStyle.filmBase)
        .overlay {
            Image(uiImage: FilmGrain.image)
                .resizable(resizingMode: .tile)
                .opacity(0.04)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            FilmChamfer()
                .frame(height: 13)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(Rectangle())
    }

    /// Film base columns and leader. Does not scale with the pinch.
    private func filmLayer(_ lay: StripLayout) -> some View {
        VStack(spacing: 0) {
            if lay.topPad > 0 {
                SprocketBlock(style: style, width: stripWidth, height: lay.topPad, offsetY: 0, columnWidth: sprocketWidth)
            }
            LazyVStack(spacing: 0) {
                ForEach(lay.items) { item in
                    SprocketBlock(style: style, width: stripWidth, height: item.height,
                                  offsetY: lay.topPad + item.y, columnWidth: sprocketWidth)
                }
            }
            SprocketBlock(style: style, width: stripWidth, height: leaderHeight,
                          offsetY: lay.topPad + lay.itemsHeight, columnWidth: sprocketWidth)
                .overlay {
                    if !isDemo {
                        PrintText(text: style == .matrix ? "START" : "WHERE IT STARTED", style: style)
                    }
                }
        }
    }

    /// Frames, print rows and headers. This is the layer the pinch scales.
    private func framesLayer(_ lay: StripLayout) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: lay.topPad)
            LazyVStack(spacing: 0) {
                ForEach(lay.items) { item in
                    itemView(item, lay)
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
            Color.clear.frame(height: leaderHeight)
        }
        .frame(width: stripWidth)
        .scaleEffect(pinchScale, anchor: scaleAnchor(total: lay.total))
    }

    private func scaleAnchor(total: CGFloat) -> UnitPoint {
        guard pinchScale != 1, total > 0, stripWidth > 0 else { return pinchAnchor }
        let cx = pinchAnchor.x * viewport.width - (viewport.width - stripWidth) / 2
        let cy = pinchAnchor.y * viewport.height + offsetBox.y
        return UnitPoint(x: cx / stripWidth, y: cy / total)
    }

    @ViewBuilder
    private func itemView(_ item: StripLayout.Item, _ lay: StripLayout) -> some View {
        switch item.kind {
        case .page(let frame):
            VStack(spacing: 0) {
                PrintRow(frame: frame, style: style)
                    .frame(height: 34)
                FilmFrameView(frame: frame, level: level, width: lay.frameWidth, height: lay.frameHeight,
                              showsCornerMarker: false, onTap: onTapFrame)
            }
            .padding(.horizontal, sprocketWidth)
            .frame(width: stripWidth, height: item.height, alignment: .top)
        case .row(let frames, let header):
            VStack(alignment: .leading, spacing: 0) {
                if let header {
                    SectionHeader(section: header, style: style)
                }
                HStack(alignment: .top, spacing: lay.gap) {
                    ForEach(frames) { frame in
                        FilmFrameView(frame: frame, level: level, width: lay.frameWidth, height: lay.frameHeight,
                                      showsCornerMarker: true, onTap: onTapFrame)
                    }
                }
            }
            .padding(.horizontal, sprocketWidth)
            .frame(width: stripWidth, height: item.height, alignment: .topLeading)
        }
    }

    // MARK: End of the strip

    @ViewBuilder
    private var endArt: some View {
        Group {
            if style == .ridge {
                RidgeEndArt()
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -34)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(height: 150)
            }
        }
        .onScrollVisibilityChange(threshold: 0.01) { visible in
            if visible { onReachStart() }
        }
    }
}

// MARK: - Layout model

/// Deterministic geometry for every item, so sprocket phase is continuous
/// across items and the lazy stacks never need to measure.
private struct StripLayout {
    enum Kind {
        case page(HallOfFameFrame)
        case row(frames: [HallOfFameFrame], header: HallOfFameSection?)
    }

    struct Item: Identifiable {
        let id: String
        let y: CGFloat
        let height: CGFloat
        let kind: Kind
    }

    let items: [Item]
    let topPad: CGFloat
    let itemsHeight: CGFloat
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let gap: CGFloat
    /// Frame id -> id of the scroll target that contains it (week and month rows).
    let rowLead: [String: String]

    var total: CGFloat { topPad + itemsHeight + 80 }

    init(sections: [HallOfFameSection], level: HallOfFameLevel, stripWidth: CGFloat, sprocketWidth: CGFloat,
         viewportHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) {
        let inner = stripWidth - 2 * sprocketWidth
        let cols = max(1, level.columns)
        let gap: CGFloat = level == .week ? 6 : (level == .month ? 5 : 0)
        var fw = ((inner - gap * CGFloat(cols - 1)) / CGFloat(cols)).rounded(.down)
        var fh = (fw * 4 / 3).rounded()
        var pageHeight: CGFloat = 0
        if level == .photo {
            let visible = max(260, viewportHeight - topInset - bottomInset)
            fw = inner
            fh = visible - 34 - 10
            pageHeight = viewportHeight - topInset + 4
        }

        var built: [Item] = []
        var lead: [String: String] = [:]
        var y: CGFloat = 0

        switch level {
        case .photo, .day:
            let height = level == .photo ? pageHeight : 34 + fh + 12
            for section in sections {
                for frame in section.frames {
                    built.append(Item(id: frame.id, y: y, height: height, kind: .page(frame)))
                    y += height
                }
            }
        case .week, .month:
            for section in sections {
                let frames = section.frames
                let rowCount = Int((Double(frames.count) / Double(cols)).rounded(.up))
                let hasHeader = section.title != nil
                for r in 0..<rowCount {
                    let slice = Array(frames[(r * cols)..<min(frames.count, (r + 1) * cols)])
                    let isFirst = r == 0
                    let isLast = r == rowCount - 1
                    let header: CGFloat = (isFirst && hasHeader) ? 46 : 0
                    let height = header + fh + (isLast ? 22 : gap)
                    let id = slice[0].id
                    for f in slice { lead[f.id] = id }
                    built.append(Item(id: id, y: y, height: height,
                                      kind: .row(frames: slice, header: (isFirst && hasHeader) ? section : nil)))
                    y += height
                }
            }
        }

        items = built
        itemsHeight = y
        topPad = level == .photo ? 0 : 60
        frameWidth = fw
        frameHeight = fh
        self.gap = gap
        rowLead = lead
    }
}

// MARK: - Snap

/// Photo level snaps one page at a time; the other levels scroll freely.
private struct FilmSnapBehavior: ScrollTargetBehavior {
    let isPaging: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard isPaging else { return }
        let aligned = ViewAlignedScrollTargetBehavior(limitBehavior: .always)
        aligned.updateTarget(&target, context: context)
    }
}

// MARK: - Scroll offset (observed only by the glow)

@MainActor @Observable
private final class ScrollOffsetBox {
    var y: CGFloat = 0
}

// MARK: - Sprockets

private struct SprocketBlock: View {
    let style: HeroCardStyle
    let width: CGFloat
    let height: CGFloat
    /// Distance of this block's top from the top of the strip, for continuous phase.
    let offsetY: CGFloat
    let columnWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let pitch = style == .matrix ? HallOfFameStyle.sprocketPitch.matrix : HallOfFameStyle.sprocketPitch.ridge
            let phase = offsetY.truncatingRemainder(dividingBy: pitch)
            let xs: [CGFloat] = [0, size.width - columnWidth]
            if style == .matrix {
                var path = Path()
                var y = -phase
                while y < size.height {
                    for x in xs {
                        path.addRoundedRect(in: CGRect(x: x + 9, y: y + 4, width: 8, height: 8),
                                            cornerSize: CGSize(width: 1, height: 1))
                    }
                    y += pitch
                }
                ctx.fill(path, with: .color(Color(red: 0.188, green: 0.188, blue: 0.188)))
            } else {
                var outer = Path(), mid = Path(), core = Path()
                var y = -phase
                while y < size.height {
                    for x in xs {
                        outer.addRoundedRect(in: CGRect(x: x + 6.2, y: y + 2.4, width: 13.6, height: 17.2),
                                             cornerSize: CGSize(width: 6, height: 6))
                        mid.addRoundedRect(in: CGRect(x: x + 7.4, y: y + 3.7, width: 11.2, height: 14.6),
                                           cornerSize: CGSize(width: 4.8, height: 4.8))
                        core.addRoundedRect(in: CGRect(x: x + 8.6, y: y + 5, width: 8.8, height: 12),
                                            cornerSize: CGSize(width: 3.4, height: 3.4))
                    }
                    y += pitch
                }
                ctx.fill(outer, with: .color(Color(white: 0.847).opacity(0.2)))
                ctx.fill(mid, with: .color(Color(white: 0.839).opacity(0.35)))
                ctx.fill(core, with: .color(Color(white: 0.824).opacity(0.88)))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// Lit cells near the vertical centre of the viewport. One canvas, positioned
/// from the scroll offset: no per-hole state.
private struct FilmMatrixGlow: View {
    let box: ScrollOffsetBox
    let stripWidth: CGFloat
    let sprocketWidth: CGFloat

    private static let stops: [(CGFloat, CGFloat)] = [(0.24, 0), (0.38, 0.5), (0.50, 1), (0.62, 0.5), (0.76, 0)]

    private static func alpha(at u: CGFloat) -> CGFloat {
        guard u > stops[0].0, u < stops[stops.count - 1].0 else { return 0 }
        for i in 1..<stops.count where u <= stops[i].0 {
            let a = stops[i - 1], b = stops[i]
            return a.1 + (b.1 - a.1) * (u - a.0) / (b.0 - a.0)
        }
        return 0
    }

    var body: some View {
        let off = box.y
        Canvas { ctx, size in
            guard size.height > 0 else { return }
            let pitch = HallOfFameStyle.sprocketPitch.matrix
            let x0 = (size.width - stripWidth) / 2
            let xs = [x0, x0 + stripWidth - sprocketWidth]
            let kMin = max(0, Int(((size.height * 0.24 + off) / pitch).rounded(.down)) - 1)
            let kMax = Int(((size.height * 0.76 + off) / pitch).rounded(.up)) + 1
            guard kMax >= kMin else { return }
            for k in kMin...kMax {
                let y = CGFloat(k) * pitch + 4 - off
                let a = Self.alpha(at: (y + 4) / size.height)
                if a <= 0.01 { continue }
                var path = Path()
                for x in xs {
                    path.addRoundedRect(in: CGRect(x: x + 9, y: y, width: 8, height: 8),
                                        cornerSize: CGSize(width: 1, height: 1))
                }
                ctx.fill(path, with: .color(Color(white: 0.949).opacity(a)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Chamfer, grain

/// The cut film end: two canvas-coloured corner triangles at the top.
private struct FilmChamfer: View {
    var body: some View {
        Canvas { ctx, size in
            let c: CGFloat = 13
            var left = Path()
            left.move(to: .zero)
            left.addLine(to: CGPoint(x: c, y: 0))
            left.addLine(to: CGPoint(x: 0, y: c))
            left.closeSubpath()
            var right = Path()
            right.move(to: CGPoint(x: size.width, y: 0))
            right.addLine(to: CGPoint(x: size.width - c, y: 0))
            right.addLine(to: CGPoint(x: size.width, y: c))
            right.closeSubpath()
            ctx.fill(left, with: .color(Theme.canvas))
            ctx.fill(right, with: .color(Theme.canvas))
        }
    }
}

/// Static white noise, drawn once with a seeded generator, tiled at 4% opacity.
private enum FilmGrain {
    static let image: UIImage = make()

    private static func make() -> UIImage {
        let side = 140
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(side * side) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let a = UInt8(truncatingIfNeeded: (seed >> 33) & 0xFF)
            // Premultiplied white: every channel equals alpha.
            pixels[i * 4] = a
            pixels[i * 4 + 1] = a
            pixels[i * 4 + 2] = a
            pixels[i * 4 + 3] = a
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        guard let provider,
              let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: side * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: info),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}

// MARK: - Ridge end art

/// Grey wash ridge silhouettes under the oldest frame (Ridge style only).
private struct RidgeEndArt: View {
    private static let far: [CGPoint] = pts([(-10, 112), (38, 78), (74, 100), (122, 48), (164, 92), (206, 60), (252, 98), (302, 52), (350, 90), (403, 70)])
    private static let mid: [CGPoint] = pts([(-10, 134), (52, 104), (98, 122), (150, 86), (206, 124), (262, 98), (322, 128), (403, 104)])
    private static let near: [CGPoint] = pts([(-10, 158), (66, 132), (128, 150), (192, 126), (254, 152), (332, 134), (403, 150)])

    private static func pts(_ a: [(CGFloat, CGFloat)]) -> [CGPoint] { a.map { CGPoint(x: $0.0, y: $0.1) } }

    /// Closed silhouette with softened peaks (quadratic midpoints).
    private static func ridge(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard let first = p.first, let last = p.last else { return path }
        path.move(to: CGPoint(x: first.x, y: 200))
        path.addLine(to: first)
        for i in 1..<(p.count - 1) {
            let mx = (p[i].x + p[i + 1].x) / 2, my = (p[i].y + p[i + 1].y) / 2
            path.addQuadCurve(to: CGPoint(x: mx, y: my), control: p[i])
        }
        path.addLine(to: last)
        path.addLine(to: CGPoint(x: last.x, y: 200))
        path.closeSubpath()
        return path
    }

    var body: some View {
        Canvas { ctx, size in
            let s = max(size.width / 393, size.height / 190)
            let tx = (size.width - 393 * s) / 2
            let ty = size.height - 190 * s
            let t = CGAffineTransform(translationX: tx, y: ty).scaledBy(x: s, y: s)
            ctx.fill(Self.ridge(Self.far).applying(t), with: .color(Color(white: 0.824).opacity(0.85)))
            ctx.fill(Self.ridge(Self.mid).applying(t), with: .color(Color(white: 0.675).opacity(0.9)))
            let mist = Path(CGRect(x: -10, y: 96, width: 413, height: 50)).applying(t)
            ctx.fill(mist, with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.3)]),
                startPoint: CGPoint(x: 0, y: 96 * s + ty),
                endPoint: CGPoint(x: 0, y: 146 * s + ty)))
            ctx.fill(Self.ridge(Self.near).applying(t), with: .color(Color(white: 0.435)))
        }
        .blur(radius: 1.2)
    }
}

// MARK: - Print text, pills, headers

/// Dot-grid mask for the Matrix print style (1.9 pt cells).
private struct DotMask: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 1.9
            var path = Path()
            var y = cell / 2
            while y < size.height + cell {
                var x = cell / 2
                while x < size.width + cell {
                    path.addEllipse(in: CGRect(x: x - 0.93, y: y - 0.93, width: 1.86, height: 1.86))
                    x += cell
                }
                y += cell
            }
            ctx.fill(path, with: .color(.black))
        }
    }
}

private struct PrintText: View {
    let text: String
    let style: HeroCardStyle

    var body: some View {
        switch style {
        case .matrix:
            Text(text)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .tracking(11.5 * 0.14)
                .foregroundStyle(Color(white: 0.949))
                .lineLimit(1)
                .fixedSize()
                .mask { DotMask() }
                .accessibilityHidden(true)
        case .ridge:
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(9.5 * 0.24)
                .foregroundStyle(Color(white: 0.941).opacity(0.72))
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }
}

private struct FilmPill: View {
    let text: String
    let isLatest: Bool
    let compact: Bool

    var body: some View {
        let size: CGFloat = compact ? 9 : 10.5
        HStack(spacing: compact ? 4 : 5) {
            if isLatest {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .tracking(size * 0.02)
                .foregroundStyle(Color(white: 0.949))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: compact ? 16 : 19)
        .background(
            compact ? Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255).opacity(0.62) : Color.white.opacity(0.14),
            in: Capsule()
        )
        .accessibilityHidden(true)
    }
}

/// Edge print above each frame at Photo and Day level: date, marker, day number.
private struct PrintRow: View {
    let frame: HallOfFameFrame
    let style: HeroCardStyle

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let t = frame.dateText { PrintText(text: t, style: style) } else { Color.clear }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let m = frame.markerText {
                FilmPill(text: m, isLatest: frame.marker == .latest, compact: false)
            }
            Group {
                if let t = frame.dayText { PrintText(text: t, style: style) } else { Color.clear }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }
}

/// Week and month header: title left, count right, hairline under.
private struct SectionHeader: View {
    let section: HallOfFameSection
    let style: HeroCardStyle

    var body: some View {
        HStack(spacing: 0) {
            if let t = section.title { PrintText(text: t, style: style) }
            Spacer(minLength: 8)
            if let c = section.countText { PrintText(text: c, style: style) }
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.22)).frame(height: 0.5)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([section.title, section.countText].compactMap { $0?.capitalized }.joined(separator: ", ")))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Frame

private struct FilmFrameView: View {
    let frame: HallOfFameFrame
    let level: HallOfFameLevel
    let width: CGFloat
    let height: CGFloat
    let showsCornerMarker: Bool
    let onTap: (HallOfFameFrame) -> Void

    @State private var lifted = false

    private var isTappable: Bool { level != .photo }

    private var label: String {
        guard let date = frame.date else { return "Example photo" }
        var s = "Progress photo, " + date.formatted(.dateTime.month(.wide).day())
        if let d = frame.dayNumber { s += ", day \(d)" }
        return s
    }

    var body: some View {
        Group {
            if isTappable {
                Button {
                    withAnimation(.timingCurve(0.22, 0.9, 0.24, 1, duration: 0.25)) { lifted = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(140))
                        onTap(frame)
                        withAnimation(Theme.settle) { lifted = false }
                    }
                } label: {
                    framed
                }
                .buttonStyle(FrameLiftStyle(forced: lifted))
            } else {
                framed
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(frame.markerText ?? "")
        .accessibilityAddTraits(isTappable ? [.isImage, .isButton] : .isImage)
    }

    private var framed: some View {
        FrameImage(frame: frame, useFull: level == .photo, width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            }
            .overlay(alignment: .topLeading) {
                if showsCornerMarker, let m = frame.markerText {
                    FilmPill(text: m, isLatest: frame.marker == .latest, compact: true)
                        .padding(4)
                }
            }
    }
}

/// 1.02 lift with a deeper shadow while pressed (or while the tap flourish runs).
private struct FrameLiftStyle: ButtonStyle {
    let forced: Bool

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isPressed || forced
        configuration.label
            .scaleEffect(on ? 1.02 : 1)
            .shadow(color: .black.opacity(on ? 0.6 : 0), radius: 11, x: 0, y: on ? 8 : 0)
            .zIndex(on ? 3 : 0)
            .animation(.timingCurve(0.22, 0.9, 0.24, 1, duration: on ? 0.25 : 0.5), value: on)
    }
}

/// The picture: scaledToFill with a 50% x / 28% y focus point, clipped to the frame.
private struct FrameImage: View {
    let frame: HallOfFameFrame
    let useFull: Bool
    let width: CGFloat
    let height: CGFloat

    @State private var image: UIImage?

    init(frame: HallOfFameFrame, useFull: Bool, width: CGFloat, height: CGFloat) {
        self.frame = frame
        self.useFull = useFull
        self.width = width
        self.height = height
        _image = State(initialValue: Self.immediate(frame, useFull: useFull))
    }

    private static func immediate(_ frame: HallOfFameFrame, useFull: Bool) -> UIImage? {
        switch frame.content {
        case .demo(let index):
            return ProgressPhotoDemoArtwork.frame(index)
        case .photo(let photo):
            let loader = ProgressPhotoImageLoader.shared
            if useFull {
                return loader.cached(photo.fileName) ?? loader.cached(photo.thumbnailName)
            }
            return loader.cached(photo.thumbnailName)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HallOfFameStyle.filmBase
            if let image, image.size.width > 0, image.size.height > 0 {
                let s = max(width / image.size.width, height / image.size.height)
                let dw = image.size.width * s
                let dh = image.size.height * s
                Image(uiImage: image)
                    .resizable()
                    .frame(width: dw, height: dh)
                    .offset(x: -(dw - width) * 0.5, y: -(dh - height) * 0.28)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .task(id: "\(frame.id)|\(useFull)") {
            guard case .photo(let photo) = frame.content else { return }
            let name = useFull ? photo.fileName : photo.thumbnailName
            if let hit = ProgressPhotoImageLoader.shared.cached(name) {
                image = hit
                return
            }
            let loaded = await ProgressPhotoImageLoader.shared.image(named: name)
            if !Task.isCancelled, let loaded { image = loaded }
        }
    }
}
