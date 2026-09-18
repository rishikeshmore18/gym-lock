import Foundation
import Testing
@testable import GymLock

/// The canvas arithmetic: normalized → actual, safe insets, element clamps,
/// and the crop.
@MainActor
struct StoryLayoutTests {
    @Test("Formats export at exactly their pixel sizes")
    func formatSizes() {
        #expect(StoryFormat.story.size == CGSize(width: 1080, height: 1920))
        #expect(StoryFormat.post.size == CGSize(width: 1080, height: 1350))
    }

    @Test("Normalized coordinates scale to the canvas")
    func normalizedToActual() {
        let export = StoryLayout.export(.story)
        #expect(export.x(0.5) == 540)
        #expect(export.y(0.5) == 960)
        #expect(export.scale == 1)

        let phone = StoryLayout(format: .story, canvasSize: CGSize(width: 360, height: 640))
        #expect(abs(phone.scale - 1.0 / 3.0) < 0.0001)
        #expect(abs(phone.fontSize(168) - 56) < 0.001)

        let post = StoryLayout.export(.post)
        #expect(post.y(1) == 1350)
    }

    @Test("Safe insets in pixels match the spec")
    func safeInsets() {
        let story = StoryLayout.export(.story).safeRect
        #expect(abs(story.minY - 250) < 1)
        #expect(abs(story.maxY - (1920 - 340)) < 1)
        #expect(abs(story.minX - 72) < 1)

        let post = StoryLayout.export(.post).safeRect
        #expect(abs(post.minY - 120) < 1)
        #expect(abs(post.maxY - (1350 - 120)) < 1)
    }

    @Test("Element defaults sit inside the safe area, mark bottom-left")
    func elementDefaults() {
        for format in StoryFormat.allCases {
            let mark = StoryLayout.defaultLayout(for: .mark, frame: .showedUp, format: format)
            #expect(abs(mark.origin.x - format.safeInsets.sides) < 0.0001)
            let markHeight = StoryLayout.markWidthFraction * Double(format.size.width) / Double(format.size.height)
            #expect(abs(mark.origin.y + markHeight - (1 - format.safeInsets.bottom)) < 0.001)

            let statement = StoryLayout.defaultLayout(for: .statement, frame: .showedUp, format: format)
            let facts = StoryLayout.defaultLayout(for: .facts, frame: .showedUp, format: format)
            #expect(statement.origin.y < facts.origin.y)
            #expect(facts.origin.y < mark.origin.y)
            #expect(statement.origin.y > format.safeInsets.top)
        }
    }

    @Test("The mark cannot shrink below six percent of the width")
    func markFloor() {
        let layout = StoryElementLayout(origin: .zero, scale: 1, isHidden: false)
        let shrunk = layout.scaled(to: 0.1, currentSize: CGSize(width: 0.07, height: 0.05), minimumScale: StoryMarkView.minimumScale)
        #expect(abs(shrunk.scale - StoryMarkView.minimumScale) < 0.0001)
        #expect(abs(StoryMarkView.minimumScale * StoryLayout.markWidthFraction - 0.06) < 0.0001)
    }

    @Test("Scaling keeps the centre in place")
    func scaleAboutCentre() {
        let layout = StoryElementLayout(origin: CGPoint(x: 0.2, y: 0.4), scale: 1, isHidden: false)
        let size = CGSize(width: 0.4, height: 0.2)
        let doubled = layout.scaled(to: 2, currentSize: size, minimumScale: 0.4)
        let centreBefore = CGPoint(x: 0.4, y: 0.5)
        let centreAfter = CGPoint(x: doubled.origin.x + size.width, y: doubled.origin.y + size.height)
        #expect(abs(centreBefore.x - centreAfter.x) < 0.0001)
        #expect(abs(centreBefore.y - centreAfter.y) < 0.0001)
    }

    @Test("Moving keeps the element's centre on the canvas")
    func moveClamp() {
        let layout = StoryElementLayout(origin: CGPoint(x: 0.5, y: 0.5), scale: 1, isHidden: false)
        let size = CGSize(width: 0.2, height: 0.1)
        let moved = layout.moved(by: CGSize(width: 5, height: -5), currentSize: size)
        #expect(abs(moved.origin.x - (1 - 0.1)) < 0.0001)
        #expect(abs(moved.origin.y - (-0.05)) < 0.0001)
    }

    @Test("Defaults are recognised as unmodified; a change is detected")
    func modifiedDetection() {
        var layouts = StoryElementLayouts.defaults(for: .showedUp, format: .story)
        #expect(!layouts.isModified(frame: .showedUp, format: .story))
        layouts[.facts]?.isHidden = true
        #expect(layouts.isModified(frame: .showedUp, format: .story))
    }

    @Test("Layouts round-trip through JSON")
    func codable() throws {
        let layouts = StoryElementLayouts.defaults(for: .journey, format: .post)
        let data = try JSONEncoder().encode(layouts)
        let decoded = try JSONDecoder().decode(StoryElementLayouts.self, from: data)
        #expect(decoded == layouts)
    }

    // MARK: Photo transform

    @Test("A clamped transform never exposes the canvas")
    func transformClamp() {
        let canvas = StoryFormat.story.size
        let portrait = CGSize(width: 3000, height: 4000)
        let landscape = CGSize(width: 4000, height: 3000)

        for image in [portrait, landscape] {
            for zoom in [1.0, 1.15, 2.5] {
                for focal in [(0.0, 0.0), (1.0, 1.0), (0.5, 0.42), (0.1, 0.9)] {
                    let raw = PhotoTransform(focalX: focal.0, focalY: focal.1, zoom: zoom)
                    let clamped = raw.clamped(imageSize: image, canvasSize: canvas)
                    #expect(!clamped.exposesCanvas(imageSize: image, canvasSize: canvas))
                }
            }
        }
    }

    @Test("Zoom is bounded to the allowed range")
    func zoomRange() {
        let canvas = StoryFormat.post.size
        let image = CGSize(width: 3000, height: 4000)
        let tooFar = PhotoTransform(focalX: 0.5, focalY: 0.5, zoom: 9).clamped(imageSize: image, canvasSize: canvas)
        #expect(tooFar.zoom == PhotoTransform.zoomRange.upperBound)
        let tooClose = PhotoTransform(focalX: 0.5, focalY: 0.5, zoom: 0.2).clamped(imageSize: image, canvasSize: canvas)
        #expect(tooClose.zoom == PhotoTransform.zoomRange.lowerBound)
    }

    @Test("Default transform fills the canvas at zoom 1")
    func defaultFills() {
        let canvas = StoryFormat.story.size
        let image = CGSize(width: 2400, height: 1800)
        #expect(!PhotoTransform.default.clamped(imageSize: image, canvasSize: canvas).exposesCanvas(imageSize: image, canvasSize: canvas))
    }
}
