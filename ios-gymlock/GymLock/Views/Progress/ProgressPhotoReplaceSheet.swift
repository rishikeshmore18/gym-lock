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

    /// What a pane has to draw.
    ///
    /// Three states, not an optional. An optional collapses "still reading the
    /// file" and "this file cannot be opened" into the same `nil`, and the pane
    /// drew a spinner for it — so a photo whose bytes had gone missing left the
    /// user watching an indicator that could never finish, with no way to tell
    /// that waiting was pointless.
    private enum PaneState {
        case loading
        case ready(UIImage)
        case unavailable
    }

    /// The stored photo, loaded from disk.
    @State private var existing: PaneState = .loading
    /// The incoming photo, decoded once.
    ///
    /// Held in state rather than computed in `body`: SwiftUI re-evaluates a
    /// body on every state change, and decoding a screen-sized JPEG each time
    /// was work done over and over for a result that never changes.
    @State private var incoming: PaneState = .loading
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            header
            comparison
            actions
        }
        .background(Theme.canvas)
        // Two independent tasks rather than one: whichever photo resolves
        // first draws immediately instead of waiting on the other.
        .task { await loadExisting() }
        .task { await loadIncoming() }
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
                state: existing,
                isNew: false
            )

            pane(
                title: "New",
                subtitle: "Just added",
                state: incoming,
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
        state: PaneState,
        isNew: Bool
    ) -> some View {
        VStack(spacing: 10) {
            // Colour as the size anchor with the photo in an overlay: a `.fill`
            // image takes its layout width from the source aspect ratio, which
            // would break the two panes out of their equal split.
            Color(white: 0.93)
                .aspectRatio(ProgressPhotoMetrics.aspectRatio, contentMode: .fit)
                .overlay {
                    switch state {
                    case .loading:
                        ProgressView().tint(Theme.inkTertiary)
                    case let .ready(image):
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    case .unavailable:
                        unavailableArtwork
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
        .accessibilityLabel(accessibilityLabel(state: state, subtitle: subtitle, isNew: isNew))
    }

    /// Shown when a stored photo's file cannot be read.
    ///
    /// Says so plainly instead of spinning. A photo that will not open is also
    /// the strongest possible argument for replacing it, so the decision this
    /// sheet is asking for still makes sense — it just makes itself.
    private var unavailableArtwork: some View {
        VStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
            Text("Can't open\nthis photo")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .allowsHitTesting(false)
    }

    private func accessibilityLabel(
        state: PaneState,
        subtitle: String,
        isNew: Bool
    ) -> String {
        if case .unavailable = state {
            return isNew
                ? "New photo, could not be opened"
                : "Current photo from \(subtitle), could not be opened"
        }
        return isNew
            ? "New photo, just added"
            : "Current photo from \(subtitle), the one that would be replaced"
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

    /// Loads the stored photo, best copy first, and never gives up silently.
    ///
    /// The full-size copy is preferred because this is a comparison the user is
    /// being asked to judge, and a 600px thumbnail stretched across half an
    /// iPhone would be judged on its softness. But the thumbnail is shown
    /// first when it is already warm in the cache, so the pane draws something
    /// real on the first frame instead of an indicator, and it is also the
    /// fallback if the full copy has gone missing — a slightly soft photograph
    /// is worth far more here than a perfect one that never appears.
    private func loadExisting() async {
        let loader = ProgressPhotoImageLoader.shared
        let photo = pending.existing

        if let warm = loader.cached(photo.thumbnailName) {
            existing = .ready(warm)
        }

        if let full = await loader.image(named: photo.fileName) {
            existing = .ready(full)
            return
        }

        if let thumbnail = await loader.image(named: photo.thumbnailName) {
            existing = .ready(thumbnail)
            return
        }

        // Nothing on disk could be opened. Keep a warm thumbnail if one is
        // already on screen rather than replacing a visible photo with an
        // error.
        if case .ready = existing { return }
        existing = .unavailable
    }

    private func loadIncoming() async {
        let data = pending.previewData
        let decoded = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value
        incoming = decoded.map(PaneState.ready) ?? .unavailable
    }
}

// MARK: - Presentation

extension View {
    /// Presents the comparison whenever the store is holding a photo back.
    ///
    /// A sheet at a large detent rather than a full-screen cover: the card
    /// underneath stays faintly visible, which keeps the decision anchored to
    /// the place it came from instead of feeling like a separate screen.
    ///
    /// `onReplaced` reports the photo that was actually written, so a caller
    /// that was on its way to the Story editor can carry on with the right
    /// one. Cancelling reports nothing: there is nothing new to share.
    func progressPhotoReplaceSheet(
        store: ProgressPhotoStore,
        onReplaced: ((ProgressPhoto) -> Void)? = nil
    ) -> some View {
        sheet(
            item: Binding(
                get: { store.pendingReplacement },
                // Swiping the sheet away is a decision too, and the safe
                // reading of walking away is "keep what I already had".
                set: { if $0 == nil { store.cancelReplacement() } }
            )
        ) { pending in
            ProgressPhotoReplaceSheet(pending: pending) {
                Task {
                    guard let replaced = await store.confirmReplacement() else { return }
                    onReplaced?(replaced)
                }
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
