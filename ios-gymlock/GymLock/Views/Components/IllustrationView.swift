import SwiftUI

/// Presents one of the supplied illustrations cropped to its drawing.
///
/// The source files carry a light grey studio margin around the artwork. Drawing
/// them raw would put a grey rectangle on the warm canvas, so the view scales the
/// image up behind a clipped window sized to the asset's measured `contentRect`.
/// The image is laid out inside a `GeometryReader`, so the oversized frame never
/// escapes into the surrounding layout.
struct IllustrationView: View {
    let illustration: Illustration
    /// Corner radius of the clipped window.
    var cornerRadius: CGFloat = 30
    /// Whether the settled artwork should breathe.
    var isBreathing: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let rect = illustration.contentRect
            let fullWidth = proxy.size.width / rect.width
            let fullHeight = fullWidth * (illustration.pixelSize.height / illustration.pixelSize.width)

            Image(illustration.assetName)
                .resizable()
                .interpolation(.high)
                .frame(width: fullWidth, height: fullHeight)
                .offset(x: -rect.minX * fullWidth, y: -rect.minY * fullHeight)
        }
        .aspectRatio(illustration.croppedAspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .breathing(isBreathing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
