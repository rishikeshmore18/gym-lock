import SwiftUI

/// The side-by-side comparison shown before a photo is replaced.
///
/// A confirmation dialog would be cheaper, but it would ask the user to make a
/// decision about two photographs without letting them see either one. The only
/// honest way to ask "replace this?" is to show what is being replaced and what
/// it is being replaced with, at a size where the difference is legible.
///
/// Nothing is written or deleted until Replace Photo is tapped. Every other
/// exit — Keep Existing, the close control, a swipe down — leaves the stored
/// photo exactly as it was.
struct ProgressPhotoReplaceSheet: View {
    let pending: PendingProgressPhoto
    let onReplace: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The stored photo, loaded from disk.
    @State private var existingImage: UIImage?
    @State private var hasAppeared = false

    /// The incoming photo, decoded from the preview prepared by the store.
    private var newImage: UIImage? { UIImage(data: pending.previewData) }

    var body: some View {
        VStack(spacing: 0) {
            header
            comparison
            actions
        }
        .background(Theme.canvas)
        .task { await loadExisting() }
        .task {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Replace \(pending.dayDescription)'s photo?")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text("GymLock keeps one photo per day.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Keep existing photo")
            .padding(.trailing, 6)
            .padding(.top, 8)
        }
    }

    // MARK: Comparison

    /// Both photographs at equal size, side by side.
    ///
    /// Equal width is the point: any difference in size would read as a
    /// recommendation, and this screen has no opinion about which photo the
    /// user should keep. The new one carries the accent so it is identifiable
    /// at a glance without the labels having to be read.
    private var comparison: some View {
        HStack(spacing: 12) {
            pane(
                title: "Current",
                subtitle: pending.existing.createdAt
                    .formatted(.dateTime.month(.abbreviated).day()),
                image: existingImage,
                isNew: false
            )

            pane(
                title: "New",
                subtitle: "Just added",
                image: newImage,
                isNew: true
            )
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
        .scaleEffect(hasAppeared ? 1 : 0.96)
        .opacity(hasAppeared ? 1 : 0)
    }

    private func pane(
        title: String,
        subtitle: String,
        image: UIImage?,
        isNew: Bool
    ) -> some View {
        VStack(spacing: 10) {
            // Colour as the size anchor with the photo in an overlay: a `.fill`
            // image takes its layout width from the source aspect ratio, which
            // would break the two panes out of their equal split.
            Color(white: 0.93)
                .aspectRatio(ProgressPhotoMetrics.aspectRatio, contentMode: .fit)
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
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            isNew ? Theme.accent : Theme.border,
                            lineWidth: isNew ? 2.5 : 1
                        )
                }
                .shadow(color: .black.opacity(isNew ? 0.14 : 0.07), radius: 12, y: 6)

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isNew ? Theme.accent : Theme.ink)
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isNew
                ? "New photo, just added"
                : "Current photo from \(subtitle), the one that would be replaced"
        )
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.commit()
                onReplace()
            } label: {
                Text("Replace Photo")
            }
            .buttonStyle(PrimaryCTAStyle(isEnabled: true))

            Button {
                Haptics.tap()
                onCancel()
            } label: {
                Text("Keep Existing Photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(.rect)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func loadExisting() async {
        // The full-size copy rather than the card thumbnail: this is a
        // comparison the user is being asked to judge, and a 600px thumbnail
        // stretched across half an iPhone would be judged on its softness.
        existingImage = await ProgressPhotoImageLoader.shared
            .image(named: pending.existing.fileName)
    }
}

// MARK: - Presentation

extension View {
    /// Presents the comparison whenever the store is holding a photo back.
    ///
    /// A sheet at a large detent rather than a full-screen cover: the card
    /// underneath stays faintly visible, which keeps the decision anchored to
    /// the place it came from instead of feeling like a separate screen.
    func progressPhotoReplaceSheet(store: ProgressPhotoStore) -> some View {
        sheet(
            item: Binding(
                get: { store.pendingReplacement },
                // Swiping the sheet away is a decision too, and the safe
                // reading of walking away is "keep what I already had".
                set: { if $0 == nil { store.cancelReplacement() } }
            )
        ) { pending in
            ProgressPhotoReplaceSheet(pending: pending) {
                Task { await store.confirmReplacement() }
            } onCancel: {
                store.cancelReplacement()
            }
            .presentationDetents([.fraction(0.88)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }
}

#if DEBUG
#Preview("Replace comparison") {
    let existing = ProgressPhoto(
        id: UUID(),
        createdAt: Date(),
        fileName: "missing.jpg",
        thumbnailName: "missing-thumb.jpg",
        source: .camera
    )
    let preview = ProgressPhotoDemoArtwork.frame(3)?
        .jpegData(compressionQuality: 0.9) ?? Data()

    return Color(Theme.canvas)
        .sheet(isPresented: .constant(true)) {
            ProgressPhotoReplaceSheet(
                pending: PendingProgressPhoto(
                    imageData: preview,
                    previewData: preview,
                    source: .camera,
                    createdAt: Date(),
                    existing: existing
                ),
                onReplace: {},
                onCancel: {}
            )
            .presentationDetents([.fraction(0.88)])
        }
}
#endif
