import CoreGraphics
import Foundation

/// How the photograph is cropped into the canvas.
///
/// Normalized, like everything else on the canvas: the focal point is a
/// fraction of the image, the zoom a multiplier on aspect-fill. The same
/// struct produces the same crop in the editor and in the export, so what the
/// user framed is what they get.
nonisolated struct PhotoTransform: Codable, Hashable {
    /// Point of the image drawn at the canvas centre, as fractions of the
    /// image's own size.
    var focalX: Double
    var focalY: Double
    /// 1 is aspect-fill; larger crops in.
    var zoom: Double

    static let zoomRange: ClosedRange<Double> = 1.0...2.5

    /// Slightly above centre, because faces sit high in a portrait.
    static let `default` = PhotoTransform(focalX: 0.5, focalY: 0.42, zoom: 1)

    /// Past this, one finger pans the photo rather than paging frames — a
    /// user who has zoomed in is composing, not browsing.
    static let panTakeoverZoom: Double = 1.15

    /// The scale applied to the image so it fills the canvas at this zoom.
    func fillScale(imageSize: CGSize, canvasSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let fill = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        return fill * CGFloat(zoom)
    }

    /// The image's drawn size on the canvas.
    func drawnSize(imageSize: CGSize, canvasSize: CGSize) -> CGSize {
        let scale = fillScale(imageSize: imageSize, canvasSize: canvasSize)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Where the image's centre lands on the canvas for this focal point.
    func drawnCenter(imageSize: CGSize, canvasSize: CGSize) -> CGPoint {
        let drawn = drawnSize(imageSize: imageSize, canvasSize: canvasSize)
        return CGPoint(
            x: canvasSize.width / 2 - (CGFloat(focalX) - 0.5) * drawn.width,
            y: canvasSize.height / 2 - (CGFloat(focalY) - 0.5) * drawn.height
        )
    }

    /// The same transform with the focal point pulled back inside the range
    /// where the photo still covers the whole canvas.
    ///
    /// Half the canvas, in image-normalized units, is how far the focal point
    /// may stray from the image's own edges. At aspect-fill on the fitting
    /// axis that is exactly half the image, so the focal point is pinned to
    /// the middle on that axis — there is nowhere to pan to.
    func clamped(imageSize: CGSize, canvasSize: CGSize) -> PhotoTransform {
        var copy = self
        copy.zoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)

        let drawn = copy.drawnSize(imageSize: imageSize, canvasSize: canvasSize)
        guard drawn.width > 0, drawn.height > 0 else { return copy }

        let halfX = Double(canvasSize.width / drawn.width) / 2
        let halfY = Double(canvasSize.height / drawn.height) / 2
        copy.focalX = min(max(copy.focalX, halfX), 1 - halfX)
        copy.focalY = min(max(copy.focalY, halfY), 1 - halfY)

        // Floating-point can leave the range inverted by a hair when the
        // image exactly fits; settle on the centre rather than NaN.
        if !copy.focalX.isFinite || halfX > 0.5 { copy.focalX = 0.5 }
        if !copy.focalY.isFinite || halfY > 0.5 { copy.focalY = 0.5 }
        return copy
    }

    /// Whether the photo would show canvas behind it anywhere.
    func exposesCanvas(imageSize: CGSize, canvasSize: CGSize) -> Bool {
        let drawn = drawnSize(imageSize: imageSize, canvasSize: canvasSize)
        let centre = drawnCenter(imageSize: imageSize, canvasSize: canvasSize)
        let minX = centre.x - drawn.width / 2
        let maxX = centre.x + drawn.width / 2
        let minY = centre.y - drawn.height / 2
        let maxY = centre.y + drawn.height / 2
        let tolerance: CGFloat = 0.5
        return minX > tolerance || minY > tolerance
            || maxX < canvasSize.width - tolerance || maxY < canvasSize.height - tolerance
    }

    /// Pans by a canvas-point translation.
    func panned(by translation: CGSize, imageSize: CGSize, canvasSize: CGSize) -> PhotoTransform {
        let drawn = drawnSize(imageSize: imageSize, canvasSize: canvasSize)
        guard drawn.width > 0, drawn.height > 0 else { return self }
        var copy = self
        copy.focalX -= Double(translation.width / drawn.width)
        copy.focalY -= Double(translation.height / drawn.height)
        return copy
    }

    /// Zooms so that the canvas point under the fingers stays under them.
    func zoomed(
        to newZoom: Double,
        about anchor: CGPoint,
        imageSize: CGSize,
        canvasSize: CGSize
    ) -> PhotoTransform {
        let drawnBefore = drawnSize(imageSize: imageSize, canvasSize: canvasSize)
        guard drawnBefore.width > 0, drawnBefore.height > 0 else { return self }
        let centreBefore = drawnCenter(imageSize: imageSize, canvasSize: canvasSize)

        // The image point under the anchor, normalized.
        let imageX = Double((anchor.x - centreBefore.x) / drawnBefore.width) + 0.5
        let imageY = Double((anchor.y - centreBefore.y) / drawnBefore.height) + 0.5

        var copy = self
        copy.zoom = min(max(newZoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let drawnAfter = copy.drawnSize(imageSize: imageSize, canvasSize: canvasSize)

        // Solve for the focal point that puts that same image point back
        // under the anchor at the new size.
        copy.focalX = imageX - Double((anchor.x - canvasSize.width / 2) / drawnAfter.width)
        copy.focalY = imageY - Double((anchor.y - canvasSize.height / 2) / drawnAfter.height)
        return copy
    }
}
