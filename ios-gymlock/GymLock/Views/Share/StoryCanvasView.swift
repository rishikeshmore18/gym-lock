import SwiftUI

/// The frame, drawn. One view for the preview and for the export.
///
/// Everything is positioned from normalized layouts scaled to `canvasSize`,
/// so the editor draws this at phone size and the renderer draws it at
/// 1080 × 1920, and they are the same picture. There is deliberately no
/// second, export-only layout to drift from what the user saw.
///
/// `layers` lets the editor and the sticker draw parts of it: the editor keeps
/// the photo still and slides only the elements while paging, and the sticker
/// is the elements alone on transparency. Nothing inside here may use glass or
/// a material — `ImageRenderer` has no backdrop to sample, and would render
/// them flat.
struct StoryCanvasView: View {
    struct Layers: OptionSet {
        let rawValue: Int
        static let photo = Layers(rawValue: 1 << 0)
        static let band = Layers(rawValue: 1 << 1)
        static let elements = Layers(rawValue: 1 << 2)
        static let all: Layers = [.photo, .band, .elements]
    }

    let context: ShareContext
    let frame: ShareFrame
    let format: StoryFormat
    let assets: StoryAssets
    let transform: PhotoTransform
    let layouts: StoryElementLayouts
    let canvasSize: CGSize
    /// False for export, so every frame renders its settled end state.
    let isAnimated: Bool
    var layers: Layers = .all
    /// Reports each element's drawn size, normalized, so the editor can hit
    /// test and draw selection chrome. Unused by the renderer.
    var onElementSize: ((StoryElementKind, CGSize) -> Void)? = nil
    /// A locked frame has no real data to draw, so its miniature shows only
    /// the frame's statement word in the frame's own style, plus the mark —
    /// the shape of the result and nothing invented. Never used for export:
    /// a locked frame cannot be rendered.
    var isLockedPreview: Bool = false

    private var layout: StoryLayout { StoryLayout(format: format, canvasSize: canvasSize) }

    /// The elements this frame actually has something to draw for.
    static func activeElements(frame: ShareFrame, context: ShareContext) -> [StoryElementKind] {
        frame.elements.filter { kind in
            kind != .inset || context.journey?.dayZeroPhoto != nil
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if layers.contains(.photo) {
                StoryPhotoLayer(image: assets.photo, transform: transform, canvasSize: canvasSize)
            }

            // Only over a photograph, and only where there is text to protect.
            // The flat card needs no help, and Clean has nothing to read.
            if layers.contains(.band), assets.photo != nil, frame.usesLegibilityBand {
                StoryLegibilityBand(layout: layout)
            }

            if layers.contains(.elements), isLockedPreview {
                lockedPreviewElements
            } else if layers.contains(.elements) {
                ForEach(Self.activeElements(frame: frame, context: context)) { kind in
                    if let element = layouts[kind], !element.isHidden {
                        elementView(kind, scale: element.scale)
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                                onElementSize?(kind, layout.normalized(size))
                            }
                            // Proposes the text width; the content inside hugs
                            // its own size, which is what gets measured above.
                            .frame(
                                maxWidth: layout.textWidth(elementScale: element.scale),
                                alignment: .topLeading
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(x: layout.x(element.origin.x), y: layout.y(element.origin.y))
                    }
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    /// The statement word and the mark at their default positions.
    @ViewBuilder
    private var lockedPreviewElements: some View {
        let defaults = StoryElementLayouts.defaults(for: frame, format: format)
        if let statement = defaults[.statement], !frame.lockedPreviewWord.isEmpty {
            StoryStatementText(text: Text(frame.lockedPreviewWord), layout: layout, scale: statement.scale)
                .frame(maxWidth: layout.textWidth(elementScale: statement.scale), alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: layout.x(statement.origin.x), y: layout.y(statement.origin.y))
        }
        if let mark = defaults[.mark] {
            StoryMarkView(layout: layout, scale: mark.scale)
                .offset(x: layout.x(mark.origin.x), y: layout.y(mark.origin.y))
        }
    }

    @ViewBuilder
    private func elementView(_ kind: StoryElementKind, scale: Double) -> some View {
        switch frame {
        case .clean:
            CleanFrame(kind: kind, layout: layout, scale: scale)
        case .showedUp:
            ShowedUpFrame(kind: kind, context: context, layout: layout, scale: scale, isAnimated: isAnimated)
        case .momentum:
            MomentumFrame(kind: kind, context: context, layout: layout, scale: scale, isAnimated: isAnimated)
        case .receipt:
            ReceiptFrame(kind: kind, context: context, layout: layout, scale: scale, isAnimated: isAnimated)
        case .journey:
            JourneyFrame(kind: kind, context: context, layout: layout, scale: scale, dayZeroImage: assets.dayZero)
        case .comeback:
            ComebackFrame(kind: kind, context: context, layout: layout, scale: scale)
        case .quickSave:
            QuickSaveFrame(kind: kind, context: context, layout: layout, scale: scale)
        case .milestone:
            MilestoneFrame(kind: kind, context: context, layout: layout, scale: scale, isAnimated: isAnimated)
        }
    }
}
