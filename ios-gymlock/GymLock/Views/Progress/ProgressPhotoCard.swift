import SwiftUI

/// Shared geometry for the photo stack, so the card and the stack cannot drift
/// apart when either is tuned.
enum ProgressPhotoMetrics {
    /// Portrait, matching how people actually photograph themselves.
    static let aspectRatio: CGFloat = 3.0 / 4.0
    static let cornerRadius: CGFloat = 13
    /// Width a card wants when there is room for it. Everything else is
    /// derived from the width actually available, so the stack fits a narrow
    /// iPhone without any hardcoded screen measurements.
    static let preferredCardWidth: CGFloat = 118
    /// How much the focused card grows.
    static let focusScale: CGFloat = 1.06

    static func height(for width: CGFloat) -> CGFloat { width / aspectRatio }

    /// Height of the whole stack region, including room for the focused card
    /// to scale up without being clipped.
    static func regionHeight(for width: CGFloat) -> CGFloat {
        height(for: width) * focusScale + 6
    }
}

/// One photograph in the stack.
///
/// Draws like a physical print: a white border around the image, a soft drop
/// shadow, and a rounded corner. The border is what makes overlapping cards
/// legible — without it, two greyscale photos on top of each other merge into
/// a single grey mass and the stack stops reading as separate objects.
struct ProgressPhotoCard: View {
    let slide: ProgressPhotoSlide
    /// Full opacity for the focused card, less for the ones behind it.
    let dimming: Double
    /// Whether the marker chip ("Day 0" / "Latest") is shown.
    let showsMarker: Bool
    let width: CGFloat

    @State private var image: UIImage?

    private var height: CGFloat { width / ProgressPhotoMetrics.aspectRatio }

    var body: some View {
        // Colour first as the size anchor with the photo in an overlay: a
        // `.fill` image sets its own layout width from the source aspect
        // ratio, which would push neighbouring cards out of the stack.
        Color(white: 0.93)
            .frame(width: width, height: height)
            .overlay { artwork }
            .clipShape(.rect(cornerRadius: ProgressPhotoMetrics.cornerRadius))
            .overlay(alignment: .bottomLeading) {
                if showsMarker, let text = slide.markerText {
                    MarkerChip(text: text)
                        .padding(8)
                }
            }
            // The print's white edge. Inside the clip so the photo is inset by
            // it rather than covered.
            .padding(3)
            .background(
                Theme.surface,
                in: .rect(cornerRadius: ProgressPhotoMetrics.cornerRadius + 3)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ProgressPhotoMetrics.cornerRadius + 3)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, x: -2, y: 4)
            .opacity(dimming)
            .task(id: slide.id) { await load() }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                // Demo frames sit slightly back so they never read as the
                // user's own history.
                .opacity(slide.isDemo ? 0.82 : 1)
                .allowsHitTesting(false)
        } else {
            // A missing file lands here too, which is why this is a calm
            // placeholder rather than an error: a photo whose file went away
            // should leave a quiet gap, not break the card.
            ZStack {
                Theme.surfaceMuted
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary.opacity(0.5))
            }
            .allowsHitTesting(false)
        }
    }

    private func load() async {
        switch slide.content {
        case let .demo(index):
            image = ProgressPhotoDemoArtwork.frame(index)
        case let .photo(photo):
            // Straight from the cache when it is warm, so a card that has been
            // seen before draws on its first frame instead of flashing.
            if let hit = ProgressPhotoImageLoader.shared.cached(photo.thumbnailName) {
                image = hit
                return
            }
            let loaded = await ProgressPhotoImageLoader.shared.image(named: photo.thumbnailName)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) { image = loaded }
        }
    }
}

// MARK: - Marker

/// The "Day 0" / "Latest" chip.
private struct MarkerChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.ink.opacity(0.82), in: .capsule)
    }
}

#Preview("Photo card") {
    HStack(spacing: 14) {
        ProgressPhotoCard(
            slide: ProgressPhotoSlide.demoSlides[0],
            dimming: 1,
            showsMarker: true,
            width: ProgressPhotoMetrics.preferredCardWidth
        )
        ProgressPhotoCard(
            slide: ProgressPhotoSlide.demoSlides[3],
            dimming: 0.9,
            showsMarker: true,
            width: ProgressPhotoMetrics.preferredCardWidth
        )
    }
    .padding(30)
    .background(Theme.canvas)
}
