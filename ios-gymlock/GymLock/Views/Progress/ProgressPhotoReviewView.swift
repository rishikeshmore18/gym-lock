import SwiftUI

/// What the user wants done with a photo they have just approved.
///
/// One value rather than two callbacks, because the two outcomes share every
/// step but the last: both save through the same store path, and only Share
/// carries on into the editor afterwards.
enum ProgressPhotoIntent: Equatable {
    case save
    case saveAndShare
}

/// The review step every progress photo passes through before it is saved.
///
/// Extracted from the camera sheet so that Photos and Files imports get the
/// same moment of consideration a capture does. Until now they saved on the
/// spot, which meant a mis-tap in the picker became a permanent photo the user
/// then had to find and delete — while the camera, the source least likely to
/// need a second look, was the only one that offered it.
///
/// `.fit`, never `.fill`: the user is deciding whether this photograph is the
/// one, and a preview that quietly crops their head off would have them decide
/// on false information.
struct ProgressPhotoReviewView: View {
    let image: UIImage
    /// The label on the left button. "Retake" for the camera, which returns to
    /// the live viewfinder; "Choose another" for imports, which return to the
    /// picker.
    let retakeTitle: String
    let isBusy: Bool
    let onRetake: () -> Void
    let onChoose: (ProgressPhotoIntent) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("use this photo?")
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .viewfinderGlass(in: .capsule)
                .padding(.top, 14)

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 16)
                .transition(.opacity)
                .accessibilityLabel("The photo you are about to save")

            controls
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
        }
        .overlay(alignment: .topTrailing) {
            ViewfinderCloseButton(action: onCancel)
                .padding(.horizontal, 18)
                .padding(.top, 10)
        }
    }

    /// Retake on the left, Use Photo on the right thumb, Share in between.
    ///
    /// Share is a glass circle rather than a second pill so that Use Photo
    /// stays the obvious primary — most photos are simply kept, and two equal
    /// pills would make every save feel like a choice about publicity.
    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.tap()
                onRetake()
            } label: {
                Text(retakeTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(minWidth: 96, minHeight: 44, alignment: .leading)
            }
            .disabled(isBusy)

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                onChoose(.saveAndShare)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    // Nudged up so the arrow reads centred; the glyph's box
                    // includes the tray below it.
                    .offset(y: -1)
                    .frame(width: 48, height: 48)
                    .viewfinderGlass(in: .circle)
            }
            .disabled(isBusy)
            .accessibilityLabel("Save and share")

            Button {
                Haptics.tap()
                onChoose(.save)
            } label: {
                ZStack {
                    Text("Use Photo")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .opacity(isBusy ? 0 : 1)
                    if isBusy {
                        ProgressView().tint(.black)
                    }
                }
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(.white, in: .capsule)
            }
            .disabled(isBusy)
            .accessibilityLabel("Use Photo")
        }
    }
}

// MARK: - Viewfinder chrome

/// The close control shared by the viewfinder and the review.
struct ViewfinderCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .viewfinderGlass(in: .circle)
        }
        .accessibilityLabel("Close")
    }
}

/// Glass for chrome floating over a viewfinder or a photograph.
///
/// The `.clear` variant on iOS 26, because the regular glass tints itself
/// from the content behind it and turns a chip over a bright wall into a
/// grey lozenge. Under Reduce Transparency the material goes and a dark
/// opaque capsule takes over, which is what the user asked for.
private struct ViewfinderGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.black.opacity(0.72), in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.32), lineWidth: 1) }
        }
    }
}

extension View {
    /// Viewfinder chrome treatment: clear glass, material fallback, opaque
    /// under Reduce Transparency.
    func viewfinderGlass<S: InsettableShape>(in shape: S) -> some View {
        modifier(ViewfinderGlass(shape: shape))
    }
}

#if DEBUG
#Preview("Review") {
    ZStack {
        Color.black.ignoresSafeArea()
        ProgressPhotoReviewView(
            image: ProgressPhotoDemoArtwork.frame(2) ?? UIImage(),
            retakeTitle: "Retake",
            isBusy: false,
            onRetake: {},
            onChoose: { _ in },
            onCancel: {}
        )
    }
    .preferredColorScheme(.dark)
}
#endif
