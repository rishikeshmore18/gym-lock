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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The photo currently in front, by identity rather than index, so it
    /// survives a new import shifting every position along.
    @State private var focusedPhotoID: UUID?
    /// Front card while the demonstration stack is showing.
    @State private var demoFocus = ProgressPhotoDemoArtwork.frameCount - 1
    @State private var isShowingSourceDialog = false
    @State private var contentWidth: CGFloat = 0
    @State private var hasAppeared = false

    private var photos: [ProgressPhoto] { store.photos }
    private var isDemo: Bool { photos.isEmpty }

    /// Position of the focused photo in the user's full history.
    private var focusedIndex: Int {
        guard !photos.isEmpty else { return 0 }
        if let focusedPhotoID, let found = photos.firstIndex(where: { $0.id == focusedPhotoID }) {
            return found
        }
        // No explicit choice yet: the newest photo leads, because that is the
        // one the user just added and the one they want to see.
        return photos.count - 1
    }

    private var slides: [ProgressPhotoSlide] {
        isDemo ? ProgressPhotoSlide.demoSlides : ProgressPhotoSlide.slides(
            for: photos,
            focus: focusedIndex
        )
    }

    private var focusedID: String {
        isDemo ? "demo-\(demoFocus)" : photos[focusedIndex].id.uuidString
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
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16)
        .task {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(Theme.settle.delay(appearanceDelay)) { hasAppeared = true }
            }
        }
        .onChange(of: photos.count) { _, _ in
            // A newly added photo takes the front. Clearing the explicit
            // choice is enough — focus falls back to the newest.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                focusedPhotoID = nil
            }
        }
        .progressPhotoImporter(store: store, isShowingSourceDialog: $isShowingSourceDialog)
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
                onTap: focus,
                onStep: step
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
        Button {
            Haptics.soft()
            isShowingSourceDialog = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add Photo")
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 15)
            // Clears the 44pt minimum target without needing a hit-test hack.
            .frame(height: 44)
            .background(Theme.surfaceMuted, in: .capsule)
            .overlay {
                Capsule().strokeBorder(Theme.border, lineWidth: 1)
            }
            .opacity(store.isImporting ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(store.isImporting)
        .accessibilityLabel("Add progress photo")
        .accessibilityHint("Choose Camera, Photos, or Files.")
    }

    // MARK: Focus

    private func focus(_ slide: ProgressPhotoSlide) {
        switch slide.content {
        case let .demo(index):
            guard index != demoFocus else { return }
            demoFocus = index
        case let .photo(photo):
            guard photo.id != photos[focusedIndex].id else { return }
            focusedPhotoID = photo.id
        }
        Haptics.selection()
    }

    /// Moves one photo along the timeline. `+1` is towards today.
    private func step(_ delta: Int) {
        if isDemo {
            let target = min(max(demoFocus + delta, 0), ProgressPhotoDemoArtwork.frameCount - 1)
            guard target != demoFocus else { return }
            demoFocus = target
        } else {
            let target = min(max(focusedIndex + delta, 0), photos.count - 1)
            guard target != focusedIndex else { return }
            focusedPhotoID = photos[target].id
        }
        // One tick per settled change — never per drag frame.
        Haptics.selection()
    }
}
