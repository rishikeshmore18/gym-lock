import SwiftUI

/// The Progress Photos card.
///
/// Answers a question the charts above it cannot: not "did I show up" but "did
/// it change anything". That is why the photographs are stacked rather than
/// laid out in a row — a row of four thumbnails is a gallery, and a gallery
/// invites browsing. A stack invites comparison, which is the only reason
/// anyone takes a progress photo in the first place.
struct ProgressPhotosCard: View {
    let store: ProgressPhotoStore
    /// Stagger so the card lands after the chart above it.
    var appearanceDelay: Double = 0.24
    /// Raises the Story editor. Owned by the tab so the cover is presented
    /// from a view that stays on screen while this card scrolls away.
    var onShare: ((ShareOrigin) -> Void)?
    /// The zoom transition's source namespace, shared with the presenter.
    var transitionNamespace: Namespace.ID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The photo currently in front, by identity rather than index, so it
    /// survives a new import shifting every position along.
    @State private var focusedPhotoID: UUID?
    /// Front card while the demonstration stack is showing. Nil until one is
    /// chosen, so the default can follow the progress reveal.
    @State private var demoFocus: Int?
    /// Raised by the Add Photo menu, consumed by the importer.
    @State private var pendingSource: ProgressPhotoSourceChoice?
    @State private var contentWidth: CGFloat = 0
    @State private var hasAppeared = false
    /// A photo the user has asked to delete, awaiting confirmation.
    @State private var photoPendingDeletion: ProgressPhoto?

    // MARK: Progress reveal (presentation only, never persisted)

    /// Set once the oldest-to-newest reveal has played, been taken over by
    /// the user, or been ruled out by a change to the photos.
    @State private var hasRunReveal = false
    /// Whether the whole card is inside the scroll view's viewport.
    @State private var isCardFullyVisible = false
    /// Whether the card's own entrance has finished, so the deck never moves
    /// while the card itself is still arriving.
    @State private var isEntranceSettled = false
    /// Handed to the stack; it glides once this turns true.
    @State private var isRevealRequested = false

    private var photos: [ProgressPhoto] { store.photos }
    private var isDemo: Bool { photos.isEmpty }

    /// The reveal plays only over the four demonstration photos or exactly
    /// four real ones: the states where the deck is a clean start-to-now line.
    private var isRevealShape: Bool { photos.isEmpty || photos.count == 4 }
    /// Until the reveal has played, the oldest photo rests in front.
    private var isAwaitingReveal: Bool { isRevealShape && !hasRunReveal }

    private var currentDemoFocus: Int {
        demoFocus ?? (isAwaitingReveal ? 0 : ProgressPhotoDemoArtwork.frameCount - 1)
    }

    /// Position of the focused photo in the user's full history.
    private var focusedIndex: Int {
        guard !photos.isEmpty else { return 0 }
        if let focusedPhotoID, let found = photos.firstIndex(where: { $0.id == focusedPhotoID }) {
            return found
        }
        // No explicit choice yet: the newest photo leads, because that is the
        // one the user just added and the one they want to see. Before the
        // progress reveal, the oldest rests in front so the deck can travel.
        return isAwaitingReveal ? 0 : photos.count - 1
    }

    private var slides: [ProgressPhotoSlide] {
        isDemo ? ProgressPhotoSlide.demoSlides : ProgressPhotoSlide.slides(
            for: photos,
            focus: focusedIndex,
            installDate: store.installDate
        )
    }

    private var focusedID: String {
        isDemo ? "demo-\(currentDemoFocus)" : photos[focusedIndex].id.uuidString
    }

    /// Large accessibility text needs the full width, so the copy moves below
    /// the photographs rather than being squeezed beside them.
    private var isStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isStackedLayout {
                VStack(alignment: .leading, spacing: 16) {
                    stackRegion(width: contentWidth)
                    sideColumn
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    stackRegion(width: photoRegionWidth)
                    sideColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(ProgressCardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: ProgressCardMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ProgressCardMetrics.cornerRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 10, y: 4)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width - ProgressCardMetrics.padding * 2
        } action: { width in
            contentWidth = width
        }
        // Measured before the entrance offset, so the card counts as visible
        // by where it actually sits in the page.
        .onScrollVisibilityChange(threshold: 0.97) { isVisible in
            isCardFullyVisible = isVisible
            requestRevealIfReady()
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16)
        .task {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(Theme.settle.delay(appearanceDelay)) { hasAppeared = true }
                // The entrance is a delay plus Theme.settle's 0.55 s.
                try? await Task.sleep(for: .seconds(appearanceDelay + 0.55))
                guard !Task.isCancelled else { return }
            }
            isEntranceSettled = true
            requestRevealIfReady()
        }
        // Keyed on the photos themselves, not just the count: a replacement
        // swaps one photo for another and leaves the count unchanged, and the
        // card still has to bring the new photograph to the front.
        .onChange(of: photos) { _, _ in
            // A change to the photos is never a reason to replay the reveal.
            hasRunReveal = true
            isRevealRequested = false
            // A newly added photo takes the front. Clearing the explicit
            // choice is enough — focus falls back to the newest.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                focusedPhotoID = nil
            }
        }
        .progressPhotoImporter(store: store, pendingSource: $pendingSource) { saved in
            // Sharing from the review screen: the photo is already written,
            // and the toast on the editor says so.
            onShare?(.progressPhoto(saved, justSaved: true))
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: Binding(
                get: { photoPendingDeletion != nil },
                set: { if !$0 { photoPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive) {
                guard let photo = photoPendingDeletion else { return }
                photoPendingDeletion = nil
                Task { await store.remove(photo) }
            }
            Button("Cancel", role: .cancel) { photoPendingDeletion = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Progress Photos")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Theme.ink)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Photographs

    /// Width given to the stack, leaving the copy beside it enough room to
    /// stay on two lines on a narrow iPhone.
    private var photoRegionWidth: CGFloat {
        guard contentWidth > 0 else { return 0 }
        let minimumSideColumn: CGFloat = 116
        let spacing: CGFloat = 14
        let preferred = contentWidth * 0.56
        return max(min(preferred, contentWidth - minimumSideColumn - spacing), 96)
    }

    @ViewBuilder
    private func stackRegion(width: CGFloat) -> some View {
        if width > 0 {
            ProgressPhotoStack(
                slides: slides,
                focusedID: focusedID,
                regionWidth: width,
                reduceMotion: reduceMotion,
                onFocus: focus,
                // Only real photographs can be deleted or shared; the
                // demonstration stack has nothing behind it.
                onDelete: isDemo ? nil : { photoPendingDeletion = $0 },
                onShare: isDemo || onShare == nil ? nil : { onShare?(.progressPhoto($0)) },
                transitionNamespace: transitionNamespace,
                isRevealRequested: isRevealRequested
            )
        } else {
            // First layout pass, before the width is known. Reserves nothing
            // so the card does not flash at the wrong size.
            Color.clear.frame(height: 0)
        }
    }

    // MARK: Copy and action

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("See the\nreal change.")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Same you.\nStronger tomorrow.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .lineSpacing(1)

            addButton
        }
    }

    private var addButton: some View {
        ProgressPhotoAddButton(
            pendingSource: $pendingSource,
            isBusy: store.isImporting,
            hasCamera: ProgressPhotoCameraAvailability.hasCamera
        )
    }

    // MARK: Focus

    /// The single way a photograph comes to the front, whether it was tapped
    /// or a drag landed on it. The animation belongs to the caller, which is
    /// what lets a throw glide for longer than a tap.
    ///
    /// No haptic here: the stack already ticks as each photograph passes the
    /// front, both under the finger and on a tap, and ticking again when the
    /// same change is committed would double up on every gesture.
    private func focus(_ slide: ProgressPhotoSlide) {
        // Any focus change, from the reveal landing or from the user, ends
        // the reveal for this visit. The oldest-first default is pinned
        // first so nothing jumps as it goes away.
        if isAwaitingReveal {
            if isDemo {
                demoFocus = currentDemoFocus
            } else if focusedPhotoID == nil {
                focusedPhotoID = photos.first?.id
            }
            hasRunReveal = true
        }

        switch slide.content {
        case let .demo(index):
            guard index != currentDemoFocus else { return }
            demoFocus = index
        case let .photo(photo):
            guard photo.id != photos[focusedIndex].id else { return }
            focusedPhotoID = photo.id
        }
    }

    /// Asks the deck to travel once, when an eligible card has finished
    /// arriving and sits wholly on screen. Never re-armed, so scrolling the
    /// card away and back does not replay it.
    private func requestRevealIfReady() {
        guard isAwaitingReveal, !isRevealRequested,
              isCardFullyVisible, isEntranceSettled
        else { return }
        isRevealRequested = true
    }
}
