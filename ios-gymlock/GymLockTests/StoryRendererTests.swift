import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import GymLock

/// The export: exact pixels, no metadata, settled state, a real sticker.
@MainActor
struct StoryRendererTests {
    private let day = Date(timeIntervalSince1970: 1_789_600_000)

    private var context: ShareContext {
        let photo = ProgressPhoto(id: UUID(), createdAt: day, fileName: "f.jpg", thumbnailName: "t.jpg", source: .camera)
        let receipt = ReceiptTimeline(
            alarm: day, left: day.addingTimeInterval(1800), arrived: day.addingTimeInterval(2820), workout: nil
        )
        return ShareContext(
            referenceDay: day,
            photo: photo,
            streak: StreakSnapshot(
                weeks: 6, weeklyGoal: 3, thisWeekSessionDays: 3, isThisWeekKept: true,
                freezesAvailable: 1, lastCompletedWeekWasFrozen: false, isLiveWeekPreArmed: false, liveWeekStart: day
            ),
            outcome: SessionOutcome(date: day, kind: .showedUp),
            receipt: receipt,
            arrivedAt: receipt.arrived,
            verifiedVisitsTotal: 12,
            verifiedVisitsThisWeek: 2,
            quick20ThisWeek: 0,
            sessionDaysThisWeek: 3,
            journey: nil,
            comeback: nil,
            milestone: nil,
            installDate: day
        )
    }

    /// A photograph with EXIF and GPS baked in, to prove neither survives.
    private func taggedPhoto() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600))
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
        }
        guard let cg = image.cgImage else { return image }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return image
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Test Lens"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.33, kCGImagePropertyGPSLongitude: 122.0],
        ]
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return UIImage(data: data as Data) ?? image
    }

    private func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        return CGSize(width: width, height: height)
    }

    @Test("Story and Post export at exactly their pixel sizes")
    func exactSizes() throws {
        let assets = StoryAssets(photo: taggedPhoto(), dayZero: nil)
        for format in StoryFormat.allCases {
            let data = try StoryRenderer.renderImage(
                context: context, frame: .showedUp, format: format, assets: assets,
                transform: .default, layouts: .defaults(for: .showedUp, format: format)
            )
            #expect(pixelSize(of: data) == format.size)
        }
    }

    @Test("Exports carry no EXIF and no GPS")
    func noMetadata() throws {
        let assets = StoryAssets(photo: taggedPhoto(), dayZero: nil)
        let data = try StoryRenderer.renderImage(
            context: context, frame: .clean, format: .story, assets: assets,
            transform: .default, layouts: .defaults(for: .clean, format: .story)
        )
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifLensModel] == nil)
    }

    @Test("The sticker has alpha and is smaller than the canvas")
    func stickerAlpha() throws {
        let png = try StoryRenderer.renderSticker(
            context: context, frame: .receipt, format: .story, assets: .none,
            layouts: .defaults(for: .receipt, format: .story)
        )
        let image = try #require(UIImage(data: png))
        let cg = try #require(image.cgImage)
        #expect(cg.alphaInfo != .none && cg.alphaInfo != .noneSkipFirst && cg.alphaInfo != .noneSkipLast)
        #expect(CGFloat(cg.width) < StoryFormat.story.size.width)
        #expect(CGFloat(cg.height) < StoryFormat.story.size.height)
        #expect(cg.width > 100)
    }

    @Test("A settled render is deterministic")
    func deterministic() throws {
        let render = {
            try StoryRenderer.renderImage(
                context: self.context, frame: .momentum, format: .post, assets: .none,
                transform: .default, layouts: .defaults(for: .momentum, format: .post)
            )
        }
        let first = try render()
        let second = try render()
        #expect(first == second)
    }

    @Test("Card mode renders without a photograph")
    func cardMode() throws {
        let base = context
        let noPhoto = ShareContext(
            referenceDay: day, photo: nil, streak: base.streak, outcome: base.outcome,
            receipt: base.receipt, arrivedAt: base.arrivedAt, verifiedVisitsTotal: 12,
            verifiedVisitsThisWeek: 2, quick20ThisWeek: 0, sessionDaysThisWeek: 3,
            journey: nil, comeback: nil, milestone: nil, installDate: day
        )
        let data = try StoryRenderer.renderImage(
            context: noPhoto, frame: .receipt, format: .story, assets: .none,
            transform: .default, layouts: .defaults(for: .receipt, format: .story)
        )
        #expect(pixelSize(of: data) == StoryFormat.story.size)
    }
}
