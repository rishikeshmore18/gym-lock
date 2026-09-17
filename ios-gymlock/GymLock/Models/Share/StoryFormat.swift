import CoreGraphics
import Foundation

/// Where the text may safely sit, as fractions of the canvas.
///
/// Instagram lays its own chrome over the top and bottom of a Story — the
/// account row above, the reply bar below — and anything drawn there is
/// covered on every phone that views it.
nonisolated struct StorySafeInsets: Hashable {
    let top: Double
    let bottom: Double
    let sides: Double
}

/// The two export shapes.
///
/// Everything is authored on a 1080-wide canvas and exported at exactly these
/// pixel sizes. There is no device-dependent layout anywhere between the two:
/// an iPhone SE and a Pro Max produce identical files.
nonisolated enum StoryFormat: String, CaseIterable, Hashable, Codable, Identifiable {
    case story
    case post

    var id: String { rawValue }

    /// The one width every layout is authored against.
    static let canvasWidth: CGFloat = 1080

    var size: CGSize {
        switch self {
        case .story: CGSize(width: 1080, height: 1920)
        case .post: CGSize(width: 1080, height: 1350)
        }
    }

    var ratio: CGFloat { size.width / size.height }

    var safeInsets: StorySafeInsets {
        switch self {
        case .story: StorySafeInsets(top: 0.130, bottom: 0.177, sides: 0.067)
        case .post: StorySafeInsets(top: 0.089, bottom: 0.089, sides: 0.067)
        }
    }

    var title: String {
        switch self {
        case .story: "Story"
        case .post: "Post"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .story: "Story format"
        case .post: "Post format"
        }
    }

    /// Name of the temporary file handed to the share sheet, so the receiving
    /// app shows something sensible rather than a UUID.
    var fileName: String {
        switch self {
        case .story: "GymLock-Story.jpg"
        case .post: "GymLock-Post.jpg"
        }
    }
}
