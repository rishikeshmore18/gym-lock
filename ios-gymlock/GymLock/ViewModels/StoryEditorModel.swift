import Observation
import SwiftUI

/// Everything the Story editor knows, in one place.
///
/// The context is built once when the editor opens and never recomputed on a
/// swipe. The working image is decoded once and held here for the life of the
/// editor. Every arrangement the user makes — crop, element positions, sizes,
/// removals — is written through to `StoryLayoutStore` as normalized
/// fractions, so reopening the same share restores it on any iPhone.
@Observable
@MainActor
final class StoryEditorModel {
    let origin: ShareOrigin
    let context: ShareContext
    /// The frames this context can honestly support, in display order. The
    /// only frames that can be selected, swiped to, rendered or shared.
    let frames: [ShareFrame]
    /// Every frame with where it stands, in `allCases` order.
    let availability: [(frame: ShareFrame, state: FrameAvailability)]
    /// The locked frames the rail shows after the available ones: nearest to
    /// unlocking first, capped so a new user sees promise rather than a wall.
    let lockedForRail: [(frame: ShareFrame, lock: FrameLock)]

    /// The locked frame whose explanation is showing above its rail cell.
    var explainedLock: ShareFrame?
    var isShowingAllFrames = false
    private var lockExplanationFade: Task<Void, Never>?

    private(set) var format: StoryFormat = .story
    /// Which frame is current. Paging animates through fractional positions
    /// in the canvas; this is the settled value.
    var index = 0
    private(set) var assets: StoryAssets = .none
    private(set) var isLoadingAssets = true

    /// The crop for the current format.
    var transform: PhotoTransform
    /// Element arrangements for the current format, keyed by frame.
    private(set) var layouts: [ShareFrame: StoryElementLayouts] = [:]
    /// The element the user has tapped, if any.
    var selectedElement: StoryElementKind?
    /// Measured drawn size of every element, normalized, keyed by frame.
    ///
    /// Kept per frame rather than for the current frame only: the incoming
    /// overlay during a page is measured while it is still incoming, and
    /// that measurement has to survive the commit or the new frame's elements
    /// cannot be hit-tested until something else moves them.
    private(set) var elementSizes: [ShareFrame: [StoryElementKind: CGSize]] = [:]

    // Export
    private(set) var isRendering = false
    var renderError: String?
    var shareItem: RenderedStory?
    var toast: String?

    private let layoutStore: StoryLayoutStore
    private var toastFade: Task<Void, Never>?

    /// Whether there is anything to share for this origin at all. A session
    /// origin with no outcome recorded has nothing honest to say.
    var hasFrames: Bool { !frames.isEmpty }

    var frame: ShareFrame {
        guard !frames.isEmpty else { return .clean }
        return frames[min(max(index, 0), frames.count - 1)]
    }
    var currentLayouts: StoryElementLayouts {
        layouts[frame] ?? .defaults(for: frame, format: format)
    }
    var isLayoutModified: Bool {
        currentLayouts.isModified(frame: frame, format: format)
    }

    init(origin: ShareOrigin, store: AppStore, photos: ProgressPhotoStore?, layoutStore: StoryLayoutStore) {
        self.origin = origin
        self.layoutStore = layoutStore
        context = ShareContextBuilder.build(origin: origin, store: store, photos: photos)
        frames = ShareFrameAvailability.frames(for: context)
        availability = ShareFrameAvailability.availability(for: context)
        lockedForRail = ShareFrameAvailability.lockedForRail(availability)
        transform = layoutStore.transform(for: origin, format: .story)
        reloadLayouts()
    }

    #if DEBUG
    /// A model over a hand-built context, for fixtures and the debug entry
    /// point. Never used at runtime.
    init(fixtureContext: ShareContext, assets: StoryAssets, origin: ShareOrigin) {
        self.origin = origin
        layoutStore = StoryLayoutStore(defaults: UserDefaults(suiteName: "gymlock.share.fixture") ?? .standard)
        context = fixtureContext
        frames = ShareFrameAvailability.frames(for: fixtureContext)
        availability = ShareFrameAvailability.availability(for: fixtureContext)
        lockedForRail = ShareFrameAvailability.lockedForRail(availability)
        transform = .default
        self.assets = assets
        isLoadingAssets = false
        reloadLayouts()
    }
    #endif

    /// Where a frame stands for this share.
    func state(of frame: ShareFrame) -> FrameAvailability {
        availability.first { $0.frame == frame }?.state ?? .notToday
    }

    /// The arrangement a thumbnail of `frame` draws: the user's own, when
    /// they have one, so the miniature is the export.
    func layouts(for frame: ShareFrame) -> StoryElementLayouts {
        layouts[frame] ?? .defaults(for: frame, format: format)
    }

    /// Selects a frame by identity. Locked and not-today frames are refused
    /// here, so no path into the model can land on one.
    func select(_ frame: ShareFrame) {
        guard let index = frames.firstIndex(of: frame) else { return }
        dismissLockExplanation()
        select(frameAt: index)
    }

    // MARK: Locked frames

    /// Shows why a frame is locked, above its cell, for a moment. Nothing
    /// else changes: the canvas keeps the frame it had.
    func explainLock(on frame: ShareFrame) {
        guard state(of: frame).isLocked else { return }
        Haptics.soft()
        lockExplanationFade?.cancel()
        withAnimation(Theme.stateChange) { explainedLock = frame }
        lockExplanationFade = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismissLockExplanation()
        }
    }

    func dismissLockExplanation() {
        guard explainedLock != nil else { return }
        lockExplanationFade?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { explainedLock = nil }
    }

    // MARK: Assets

    /// Decodes the working image and the Day 0 thumbnail, once.
    func loadAssets() async {
        guard isLoadingAssets else { return }
        defer { isLoadingAssets = false }
        let loader = ProgressPhotoImageLoader.shared

        var loaded = StoryAssets.none
        if let photo = context.photo {
            // The 2400 px full copy is the working image. The thumbnail is
            // only a fallback for a photo whose full file has gone missing —
            // a soft export beats no export.
            if let full = await loader.image(named: photo.fileName) {
                loaded.photo = full
            } else {
                loaded.photo = await loader.image(named: photo.thumbnailName)
            }
        }
        if let dayZero = context.journey?.dayZeroPhoto {
            loaded.dayZero = await loader.image(named: dayZero.thumbnailName)
        }
        assets = loaded
    }

    // MARK: Format

    func setFormat(_ newFormat: StoryFormat) {
        guard newFormat != format else { return }
        Haptics.selection()
        dismissLockExplanation()
        format = newFormat
        transform = layoutStore.transform(for: origin, format: newFormat)
        selectedElement = nil
        reloadLayouts()
    }

    private func reloadLayouts() {
        var fresh: [ShareFrame: StoryElementLayouts] = [:]
        for frame in frames {
            fresh[frame] = layoutStore.layouts(for: origin, frame: frame, format: format)
        }
        layouts = fresh
    }

    // MARK: Paging

    func select(frameAt newIndex: Int) {
        guard !frames.isEmpty else { return }
        let clamped = min(max(newIndex, 0), frames.count - 1)
        guard clamped != index else { return }
        Haptics.selection()
        index = clamped
        selectedElement = nil
    }

    // MARK: Transform

    func commitTransform() {
        layoutStore.setTransform(transform, for: origin, format: format)
    }

    // MARK: Elements

    func layout(for kind: StoryElementKind) -> StoryElementLayout? {
        currentLayouts[kind]
    }

    func elementSize(_ kind: StoryElementKind) -> CGSize? {
        elementSizes[frame]?[kind]
    }

    func setElementSize(_ size: CGSize, for kind: StoryElementKind, on frame: ShareFrame) {
        guard elementSizes[frame]?[kind] != size else { return }
        elementSizes[frame, default: [:]][kind] = size
    }

    func update(_ kind: StoryElementKind, _ change: (inout StoryElementLayout) -> Void) {
        var all = currentLayouts
        guard var element = all[kind] else { return }
        change(&element)
        all[kind] = element
        layouts[frame] = all
    }

    func commitLayouts() {
        layoutStore.setLayouts(currentLayouts, for: origin, frame: frame, format: format)
    }

    func remove(_ kind: StoryElementKind) {
        guard kind.isRemovable else { return }
        Haptics.tap()
        update(kind) { $0.isHidden = true }
        selectedElement = nil
        commitLayouts()
    }

    func resetLayout() {
        Haptics.tap()
        layouts[frame] = .defaults(for: frame, format: format)
        selectedElement = nil
        layoutStore.resetLayouts(for: origin, frame: frame, format: format)
    }

    /// The smallest scale an element may be pinched to. Only the mark has a
    /// floor beyond the general range.
    func minimumScale(for kind: StoryElementKind) -> Double {
        kind == .mark ? StoryMarkView.minimumScale : StoryElementLayout.scaleRange.lowerBound
    }

    // MARK: Export

    /// Renders the current frame and hands it to the share sheet.
    ///
    /// Rendering happens here and only here — never on a swipe. A failure
    /// leaves the editor exactly as it was, with an inline message and the
    /// button ready to try again; an empty share sheet is never shown.
    func share() async {
        guard !isRendering else { return }
        isRendering = true
        renderError = nil
        // Let the button repaint before the synchronous render occupies the
        // main thread.
        try? await Task.sleep(for: .milliseconds(16))

        do {
            let data = try StoryRenderer.renderImage(
                context: context,
                frame: frame,
                format: format,
                assets: assets,
                transform: transform,
                layouts: currentLayouts
            )
            shareItem = RenderedStory(data: data, fileName: format.fileName)
        } catch {
            renderError = error.localizedDescription
        }
        isRendering = false
    }

    /// Renders the overlay alone and copies it for pasting over the user's
    /// own photo elsewhere.
    func copySticker() async {
        guard !isRendering else { return }
        isRendering = true
        renderError = nil
        try? await Task.sleep(for: .milliseconds(16))

        do {
            let png = try StoryRenderer.renderSticker(
                context: context,
                frame: frame,
                format: format,
                assets: assets,
                layouts: currentLayouts
            )
            ShareService.copySticker(png)
            showToast("sticker copied · paste it on your story")
        } catch {
            renderError = error.localizedDescription
        }
        isRendering = false
    }

    func shareToInstagram() async {
        guard !isRendering else { return }
        isRendering = true
        try? await Task.sleep(for: .milliseconds(16))
        if let data = try? StoryRenderer.renderImage(
            context: context, frame: frame, format: format,
            assets: assets, transform: transform, layouts: currentLayouts
        ) {
            ShareService.shareToInstagramStories(background: data)
        } else {
            renderError = StoryRenderer.RenderError.noImage.localizedDescription
        }
        isRendering = false
    }

    // MARK: Toast

    func showToast(_ message: String, for seconds: Double = 2.2) {
        toastFade?.cancel()
        withAnimation(Theme.stateChange) { toast = message }
        toastFade = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
        }
    }
}
