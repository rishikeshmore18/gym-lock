import SwiftUI

/// The one piece of branding on a frame.
///
/// Always the transparent white mark from the asset catalog, never redrawn
/// and never the splash logo, whose baked-in black square would sit on a
/// photograph like a sticker. Sized as a fraction of the canvas so it is the
/// same object at every export size.
struct StoryMarkView: View {
    let layout: StoryLayout
    let scale: Double

    /// The smallest the mark may be drawn, relative to its default. Set by the
    /// legibility floor, not by taste: below this it stops reading as the mark.
    static let minimumScale = StoryLayout.markMinimumWidthFraction / StoryLayout.markWidthFraction

    var body: some View {
        Image("GymLockMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: layout.x(StoryLayout.markWidthFraction) * CGFloat(scale))
            .accessibilityHidden(true)
    }
}
