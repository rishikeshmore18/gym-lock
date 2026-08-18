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

/// The pinned loop diagram. Only two frames are ever alive: the state being
/// shown and the one it is crossfading from, so the sequence stays cheap.
///
/// Nothing moves — the diagram transforms in place, which is what makes the
/// sequence read as one visual changing state rather than seven pictures.
struct LoopDiagramView: View {
    let state: LoopState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(neighbouring, id: \.id) { candidate in
                IllustrationView(
                    illustration: candidate.illustration,
                    cornerRadius: 26,
                    isBreathing: false
                )
                .opacity(candidate.id == state.id ? 1 : 0)
                .scaleEffect(candidate.id == state.id ? 1 : (reduceMotion ? 1 : 0.97))
            }
        }
        .animation(.easeInOut(duration: 0.34), value: state.id)
        .breathing(amplitude: 2)
        .accessibilityHidden(false)
        .accessibilityLabel(accessibilityDescription)
    }

    /// The current state plus its immediate neighbours, so a crossfade in either
    /// direction always has its partner frame already mounted.
    private var neighbouring: [LoopState] {
        LoopState.sequence.filter { abs($0.id - state.id) <= 1 }
    }

    private var accessibilityDescription: String {
        if let number = state.nodeNumber {
            return "Loop step \(number) of 6. \(state.caption)"
        }
        return "The missed-workout loop. \(state.caption)"
    }
}
