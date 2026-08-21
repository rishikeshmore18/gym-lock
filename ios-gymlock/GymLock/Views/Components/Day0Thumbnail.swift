import AVFoundation
import SwiftUI

/// Shows a captured Day 0 photo or the first frame of a Day 0 clip.
///
/// The frame is pulled off the main thread and cached in view state, so the
/// thumbnail can appear on any screen that wants to remind the user what they
/// started from without re-decoding the file each time.
struct Day0Thumbnail: View {
    let media: Day0Media
    var height: CGFloat = 200
    var cornerRadius: CGFloat = Theme.cardRadius
    var showsBadge: Bool = true

    @State private var image: UIImage?

    var body: some View {
        // Colour first as the size anchor, artwork in an overlay: a `.fill`
        // image would otherwise widen the layout frame beyond its container.
        Color(.secondarySystemBackground)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    ProgressView().tint(Theme.inkTertiary)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(alignment: .bottomLeading) {
                if showsBadge { badge }
            }
            .task(id: media.fileName) { await load() }
            .accessibilityLabel(media.kind == .photo ? "Your Day 0 photo" : "Your Day 0 video")
    }

    private var badge: some View {
        HStack(spacing: 6) {
            Image(systemName: media.kind == .photo ? "camera.fill" : "video.fill")
                .font(.system(size: 10, weight: .bold))
            Text("day 0")
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Theme.ink.opacity(0.72), in: .capsule)
        .padding(12)
    }

    private func load() async {
        guard let url = media.fileURL else { return }

        let kind = media.kind
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            switch kind {
            case .photo:
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            case .video:
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                guard let cgImage = try? await generator.image(at: time).image else { return nil }
                return UIImage(cgImage: cgImage)
            }
        }.value

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.28)) { image = loaded }
    }
}
