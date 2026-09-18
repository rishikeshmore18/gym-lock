import SwiftUI

/// The photograph, aspect-filled and cropped by the transform — or, with no
/// photograph, the flat near-black card the session frames sit on.
///
/// Drawn from explicit geometry rather than `.scaledToFill`: the transform
/// says exactly how large the image is and where its centre lands, and the
/// same arithmetic runs at export size, so the crop the user framed is the
/// crop they get.
struct StoryPhotoLayer: View {
    let image: UIImage?
    let transform: PhotoTransform
    let canvasSize: CGSize

    var body: some View {
        ZStack {
            if let image {
                let drawn = transform.drawnSize(imageSize: image.size, canvasSize: canvasSize)
                let centre = transform.drawnCenter(imageSize: image.size, canvasSize: canvasSize)

                // Black behind the photo so a transient over-pan during a
                // gesture shows black rather than the editor bleeding through.
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: drawn.width, height: drawn.height)
                    .position(centre)
            } else {
                // Photo-less card mode. A flat dark canvas with the one
                // gradient the design allows — no glow, no texture.
                LinearGradient(
                    colors: [StoryTypography.cardTop, StoryTypography.cardBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// The soft darkening behind the text band.
///
/// A straight black gradient from transparent to about 60 %, confined to the
/// lower band where the statement sits. Not full-bleed, not coloured, not
/// blurred — the way Instagram itself protects captions over a bright photo.
/// Only drawn over a photograph: the flat card needs no help.
struct StoryLegibilityBand: View {
    let layout: StoryLayout

    var body: some View {
        let top = StoryLayout.legibilityBandTop(for: layout.format)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(StoryLayout.legibilityBandOpacity * 0.55), location: 0.55),
                    .init(color: .black.opacity(StoryLayout.legibilityBandOpacity), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: layout.y(1 - top))
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .allowsHitTesting(false)
    }
}
