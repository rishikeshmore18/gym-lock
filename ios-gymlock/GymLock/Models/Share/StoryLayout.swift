import CoreGraphics
import Foundation
import SwiftUI

/// The movable pieces of a frame.
///
/// Every frame is built from at most four of these. They are the units the
/// user can select, drag, resize and (for two of them) remove, and the units
/// whose positions are remembered.
nonisolated enum StoryElementKind: String, CaseIterable, Hashable, Codable, CodingKeyRepresentable, Identifiable {
    /// The one thing the frame says. On the Receipt this is the ticket.
    case statement
    /// The supporting line or two under the statement.
    case facts
    /// The Day 0 inset on the Journey frame. Behaves like a fact: removable.
    case inset
    /// The GymLock mark. Movable and resizable, never removable.
    case mark

    var id: String { rawValue }

    /// Whether the delete control is offered. The mark is the one piece of
    /// branding on the frame, and it stays.
    var isRemovable: Bool { self != .mark }

    var accessibilityName: String {
        switch self {
        case .statement: "Statement"
        case .facts: "Facts"
        case .inset: "Day 0 photo"
        case .mark: "GymLock mark"
        }
    }
}

/// Converts between the canvas the frames are authored on and the canvas
/// they are drawn on.
///
/// Everything a frame specifies — a font size, a margin, a position — is a
/// fraction of the canvas: x and widths as fractions of canvas width, y and
/// heights as fractions of canvas height, type as a fraction of width so Story
/// and Post share one horizontal scale. The view multiplies by the size it is
/// actually given, which is a phone-sized preview in the editor and exactly
/// 1080 × 1920 in the export. There is no second layout to drift.
struct StoryLayout: Hashable {
    let format: StoryFormat
    /// The size the canvas is being drawn at, in points.
    let canvasSize: CGSize

    init(format: StoryFormat, canvasSize: CGSize) {
        self.format = format
        self.canvasSize = canvasSize
    }

    /// A layout at export size.
    static func export(_ format: StoryFormat) -> StoryLayout {
        StoryLayout(format: format, canvasSize: format.size)
    }

    /// Points per canvas-point: 1 at export, ~0.36 on a phone.
    var scale: CGFloat { canvasSize.width / StoryFormat.canvasWidth }

    // MARK: Conversion

    func x(_ fraction: Double) -> CGFloat { CGFloat(fraction) * canvasSize.width }
    func y(_ fraction: Double) -> CGFloat { CGFloat(fraction) * canvasSize.height }

    func point(_ normalized: CGPoint) -> CGPoint {
        CGPoint(x: x(normalized.x), y: y(normalized.y))
    }

    func normalized(_ point: CGPoint) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
        return CGPoint(x: point.x / canvasSize.width, y: point.y / canvasSize.height)
    }

    func normalized(_ size: CGSize) -> CGSize {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
        return CGSize(width: size.width / canvasSize.width, height: size.height / canvasSize.height)
    }

    /// A type size authored in canvas points, at the drawn scale, times the
    /// element's own scale.
    func fontSize(_ canvasPoints: CGFloat, elementScale: Double = 1) -> CGFloat {
        canvasPoints * scale * CGFloat(elementScale)
    }

    /// The safe area, in points.
    var safeRect: CGRect {
        let insets = format.safeInsets
        return CGRect(
            x: x(insets.sides),
            y: y(insets.top),
            width: x(1 - insets.sides * 2),
            height: y(1 - insets.top - insets.bottom)
        )
    }

    /// Width text may run to before it wraps or shrinks, in points.
    func textWidth(elementScale: Double = 1) -> CGFloat {
        x(Self.textWidthFraction) * CGFloat(elementScale)
    }

    // MARK: Type roles (canvas points, 1080-wide)

    enum TypeScale {
        static let statement: CGFloat = 168
        static let statementTracking: CGFloat = -0.02
        static let heroNumber: CGFloat = 320
        static let heroLabel: CGFloat = 112
        static let eyebrow: CGFloat = 34
        static let eyebrowTracking: CGFloat = 0.10
        static let fact: CGFloat = 44
        static let receiptRow: CGFloat = 52
        static let annotation: CGFloat = 32
        static let journeyNumber: CGFloat = 240
        static let journeyLabel: CGFloat = 96
        static let milestoneNumber: CGFloat = 260
    }

    /// The mark's default width, as a fraction of canvas width.
    static let markWidthFraction: Double = 0.07
    /// The mark never shrinks below this width. Legible at arm's length on
    /// a phone; the resize handle stops here rather than snapping back.
    static let markMinimumWidthFraction: Double = 0.06
    /// The Day 0 inset's default width.
    static let insetWidthFraction: Double = 0.24
    /// Statements and facts run the safe width.
    static let textWidthFraction: Double = 1 - 0.067 * 2

    /// Where the soft darkening behind the text band starts, as a fraction of
    /// canvas height. The band runs from here to the bottom edge.
    static func legibilityBandTop(for format: StoryFormat) -> Double {
        switch format {
        case .story: 0.50
        case .post: 0.40
        }
    }

    /// How dark the band gets at the very bottom.
    static let legibilityBandOpacity: Double = 0.60

    // MARK: Element defaults

    /// Where an element sits before the user touches it.
    ///
    /// Origins are the element's top-leading corner. Everything stacks up
    /// from the mark: the mark sits on the bottom safe inset, the facts above
    /// it, and the statement above the facts by roughly its own height, so a
    /// single-line statement and a two-line one both land with the same gap.
    static func defaultLayout(
        for kind: StoryElementKind,
        frame: ShareFrame,
        format: StoryFormat
    ) -> StoryElementLayout {
        let insets = format.safeInsets
        let sides = insets.sides
        let bottom = 1 - insets.bottom
        // Vertical fractions from canvas points on this format's height.
        let unit = 1 / Double(format.size.height)

        let markHeight = markWidthFraction * Double(format.size.width) * unit
        let markTop = bottom - markHeight
        let gapToMark = 40 * unit
        let factsHeight = factsHeightCanvasPoints(for: frame) * unit
        let factsTop = markTop - gapToMark - factsHeight
        let gapToFacts = 22 * unit
        let statementHeight = statementHeightCanvasPoints(for: frame) * unit
        let statementTop = factsTop - gapToFacts - statementHeight

        switch kind {
        case .mark:
            return StoryElementLayout(origin: CGPoint(x: sides, y: markTop), scale: 1, isHidden: false)
        case .facts:
            return StoryElementLayout(origin: CGPoint(x: sides, y: factsTop), scale: 1, isHidden: false)
        case .statement:
            return StoryElementLayout(origin: CGPoint(x: sides, y: statementTop), scale: 1, isHidden: false)
        case .inset:
            // Bottom-trailing, sitting on the same baseline as the mark, so it
            // reads as a caption to the frame rather than competing with the
            // statement on the left.
            let insetWidth = insetWidthFraction
            let insetHeight = insetWidth * Double(format.size.width) / Double(ProgressPhotoMetrics.aspectRatio) * unit
                + 44 * unit // caption
            return StoryElementLayout(
                origin: CGPoint(x: 1 - sides - insetWidth, y: bottom - insetHeight),
                scale: 1,
                isHidden: false
            )
        }
    }

    /// Rough authored height of each frame's statement block, in canvas
    /// points. Only used to place the default; the drawn block is measured.
    private static func statementHeightCanvasPoints(for frame: ShareFrame) -> Double {
        switch frame {
        case .clean: 0
        case .showedUp, .comeback: Double(TypeScale.statement) * 1.05
        case .quickSave: Double(TypeScale.statement) * 2.05
        case .momentum: Double(TypeScale.eyebrow) * 1.4 + Double(TypeScale.heroNumber) * 1.02
        case .receipt: 5 * Double(TypeScale.receiptRow) * 1.45 + 70
        case .journey: Double(TypeScale.journeyNumber) * 1.05
        case .milestone: Double(TypeScale.milestoneNumber) * 1.02 + Double(TypeScale.eyebrow) * 1.4 + 36
        }
    }

    private static func factsHeightCanvasPoints(for frame: ShareFrame) -> Double {
        switch frame {
        case .clean: 0
        case .comeback, .showedUp, .journey: Double(TypeScale.fact) * 2.6
        default: Double(TypeScale.fact) * 1.3
        }
    }
}

/// One element's position and size, as fractions of the canvas.
///
/// Never pixels. The same struct places the element on a 320-point preview
/// and on the 1080-pixel export, which is what makes the two agree.
struct StoryElementLayout: Hashable, Codable {
    /// Top-leading corner, normalized.
    var origin: CGPoint
    /// Multiplier on the element's authored size. 1 is the default size.
    var scale: Double
    /// Removed by the user. Only `isRemovable` kinds can be.
    var isHidden: Bool

    static let scaleRange: ClosedRange<Double> = 0.4...3.0

    /// Scales about the element's current centre, given its current drawn
    /// size in normalized units, keeping the centre where it was.
    ///
    /// Instagram's text tool scales about the centre, and it is what a pinch
    /// feels like it should do; scaling about a corner sends the element
    /// sliding away from the fingers.
    func scaled(to newScale: Double, currentSize: CGSize, minimumScale: Double) -> StoryElementLayout {
        let clamped = min(max(newScale, max(Self.scaleRange.lowerBound, minimumScale)), Self.scaleRange.upperBound)
        guard scale > 0, currentSize.width > 0 else {
            var copy = self
            copy.scale = clamped
            return copy
        }
        let ratio = clamped / scale
        let newSize = CGSize(width: currentSize.width * ratio, height: currentSize.height * ratio)
        let centre = CGPoint(x: origin.x + currentSize.width / 2, y: origin.y + currentSize.height / 2)
        return StoryElementLayout(
            origin: CGPoint(x: centre.x - newSize.width / 2, y: centre.y - newSize.height / 2),
            scale: clamped,
            isHidden: isHidden
        )
    }

    /// Moves by a normalized translation, keeping the centre inside the
    /// canvas so an element can be pushed to an edge but never lost.
    func moved(by translation: CGSize, currentSize: CGSize) -> StoryElementLayout {
        var copy = self
        let proposed = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)
        let halfW = currentSize.width / 2
        let halfH = currentSize.height / 2
        copy.origin = CGPoint(
            x: min(max(proposed.x, -halfW), 1 - halfW),
            y: min(max(proposed.y, -halfH), 1 - halfH)
        )
        return copy
    }
}

/// Every element's layout for one frame in one format.
struct StoryElementLayouts: Hashable, Codable {
    var layouts: [StoryElementKind: StoryElementLayout]

    /// All defaults for a frame and format.
    static func defaults(for frame: ShareFrame, format: StoryFormat) -> StoryElementLayouts {
        var result: [StoryElementKind: StoryElementLayout] = [:]
        for kind in frame.elements {
            result[kind] = StoryLayout.defaultLayout(for: kind, frame: frame, format: format)
        }
        return StoryElementLayouts(layouts: result)
    }

    subscript(kind: StoryElementKind) -> StoryElementLayout? {
        get { layouts[kind] }
        set { layouts[kind] = newValue }
    }

    /// Whether anything differs from the defaults, which is what makes the
    /// "Reset layout" link appear.
    func isModified(frame: ShareFrame, format: StoryFormat) -> Bool {
        self != .defaults(for: frame, format: format)
    }
}
