import SwiftUI
import UIKit

/// Turns the canvas view into pixels.
///
/// The same `StoryCanvasView` the editor draws is handed to `ImageRenderer`
/// at exactly the format's pixel size with `isAnimated: false`, so every
/// frame renders its settled end state — counts finished, rows revealed,
/// checks drawn. No hand-mirrored export layout exists to drift from the
/// preview.
@MainActor
enum StoryRenderer {
    enum RenderError: Error, LocalizedError {
        case noImage
        case encodingFailed
        case emptySticker

        var errorDescription: String? {
            switch self {
            case .noImage, .encodingFailed: "couldn't create your story."
            case .emptySticker: "nothing to copy on this frame."
            }
        }
    }

    /// The full composition as a JPEG at exactly `format.size`.
    ///
    /// JPEG via `UIImage.jpegData`, which writes no EXIF and no GPS — the
    /// original photograph's metadata never reaches the export.
    static func renderImage(
        context: ShareContext,
        frame: ShareFrame,
        format: StoryFormat,
        assets: StoryAssets,
        transform: PhotoTransform,
        layouts: StoryElementLayouts
    ) throws -> Data {
        let image = try render(
            context: context,
            frame: frame,
            format: format,
            assets: assets,
            transform: transform,
            layouts: layouts,
            layers: .all,
            isOpaque: true
        )
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw RenderError.encodingFailed
        }
        return data
    }

    /// The overlay elements alone, on transparency, cropped to their bounds.
    ///
    /// This is the Strava pattern: the user pastes it over their own photo in
    /// Instagram. Cropping matters — a full 1080 × 1920 transparent page
    /// pastes as a sticker the size of the screen with the text in one
    /// corner.
    static func renderSticker(
        context: ShareContext,
        frame: ShareFrame,
        format: StoryFormat,
        assets: StoryAssets,
        layouts: StoryElementLayouts
    ) throws -> Data {
        let full = try render(
            context: context,
            frame: frame,
            format: format,
            assets: assets,
            transform: .default,
            layouts: layouts,
            layers: .elements,
            isOpaque: false
        )

        guard let cgImage = full.cgImage,
              let bounds = opaqueBounds(of: cgImage)
        else { throw RenderError.emptySticker }

        let padding: CGFloat = 24
        let padded = bounds.insetBy(dx: -padding, dy: -padding)
            .intersection(CGRect(origin: .zero, size: format.size))

        guard let cropped = cgImage.cropping(to: padded) else { throw RenderError.emptySticker }
        guard let data = UIImage(cgImage: cropped).pngData() else { throw RenderError.encodingFailed }
        return data
    }

    // MARK: Rendering

    private static func render(
        context: ShareContext,
        frame: ShareFrame,
        format: StoryFormat,
        assets: StoryAssets,
        transform: PhotoTransform,
        layouts: StoryElementLayouts,
        layers: StoryCanvasView.Layers,
        isOpaque: Bool
    ) throws -> UIImage {
        let canvas = StoryCanvasView(
            context: context,
            frame: frame,
            format: format,
            assets: assets,
            transform: transform,
            layouts: layouts,
            canvasSize: format.size,
            isAnimated: false,
            layers: layers
        )
        .frame(width: format.size.width, height: format.size.height)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(format.size)
        renderer.isOpaque = isOpaque

        guard let image = renderer.uiImage else { throw RenderError.noImage }
        return image
    }

    /// The smallest rectangle containing every non-transparent pixel.
    ///
    /// Reads the alpha channel directly rather than through Core Image; the
    /// bitmap is a couple of megapixels and this runs once per sticker.
    static func opaqueBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(
                  data: &pixels,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width where pixels[row + x * bytesPerPixel + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
