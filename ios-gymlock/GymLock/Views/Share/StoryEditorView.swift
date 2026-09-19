import SwiftUI

/// The Story editor.
///
/// Full-screen, black, dark scheme. The canvas is the whole point; everything
/// else floats over it as glass and stays out of the export. There is no Save
/// button — the photo was saved before this screen appeared — and Close never
/// asks whether the user is sure, because closing costs nothing.
struct StoryEditorView: View {
    @State private var model: StoryEditorModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var canvasArea: CGSize = .zero
    @State private var hasSettled = false
    @State private var shareURL: URL?

    /// The same nudge above true centre that Home gives its card.
    private static let opticalCentreLift: CGFloat = 12

    init(
        origin: ShareOrigin,
        store: AppStore,
        photos: ProgressPhotoStore?,
        layoutStore: StoryLayoutStore,
        onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: StoryEditorModel(
            origin: origin,
            store: store,
            photos: photos,
            layoutStore: layoutStore
        ))
        self.onClose = onClose
    }

    /// The largest canvas of the current format that fits the area measured
    /// between the top row and the pills. The measured size scales the
    /// preview; it never redefines a layout.
    private var canvasSize: CGSize {
        guard canvasArea.width > 0, canvasArea.height > 0 else { return .zero }
        let ratio = model.format.ratio
        let byHeight = CGSize(width: canvasArea.height * ratio, height: canvasArea.height)
        guard byHeight.width <= canvasArea.width else {
            return CGSize(width: canvasArea.width, height: canvasArea.width / ratio)
        }
        return byHeight
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topRow
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                canvasRegion
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                resetRow
                    .frame(height: 30)
                    .padding(.top, 4)

                if let error = model.renderError {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)
                        .transition(.opacity)
                }

                ShareBar(
                    isRendering: model.isRendering,
                    showsInstagram: ShareService.canShareToInstagramStories,
                    onSticker: { Task { await model.copySticker() } },
                    onInstagram: { Task { await model.shareToInstagram() } },
                    onShare: { Task { await model.share() } }
                )
                .disabled(!model.hasFrames)
                .opacity(model.hasFrames ? 1 : 0.4)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                EditorToast(message: toast)
                    .padding(.top, 62)
            }
        }
        .sheet(isPresented: $model.isShowingAllFrames) {
            AllFramesSheet(model: model) { frame in
                withAnimation(pageAnimation) { model.select(frame) }
            }
        }
        .preferredColorScheme(.dark)
        .scaleEffect(hasSettled || reduceMotion ? 1 : 0.96)
        .opacity(hasSettled ? 1 : 0)
        .task {
            await model.loadAssets()
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Theme.settle) { hasSettled = true }
            if model.origin.justSaved {
                // The store already fired the success haptic on save; this is
                // the same event, so the toast is silent.
                model.showToast("saved to progress ✓")
            }
        }
        .onChange(of: model.shareItem) { _, item in
            guard let item else { return }
            shareURL = try? item.writeToTemporaryFile()
            if shareURL == nil { model.renderError = StoryRenderer.RenderError.encodingFailed.localizedDescription }
        }
        .sheet(item: Binding(
            get: { shareURL.map(ShareFile.init) },
            set: { if $0 == nil { shareURL = nil; model.shareItem = nil } }
        )) { file in
            // The system sheet handles destinations. Cancel or complete, the
            // editor is still here afterwards — the user may want a second
            // frame.
            ActivityShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    // MARK: Pieces

    private var topRow: some View {
        ZStack {
            HStack {
                EditorCloseButton(action: onClose)
                Spacer()
            }
            FormatToggle(format: model.format) { format in
                withAnimation(pageAnimation) { model.setFormat(format) }
            }
        }
    }

    private var canvasRegion: some View {
        GeometryReader { proxy in
            ZStack {
                if !model.hasFrames {
                    // A session with nothing recorded has nothing honest to
                    // say. Stated plainly rather than filled with a frame.
                    Text("nothing to share for this day yet.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                } else if canvasSize.width > 0 {
                    if model.isLoadingAssets {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Color(white: 0.08))
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .overlay { ProgressView().tint(.white) }
                    } else {
                        StoryEditableCanvas(model: model, canvasSize: canvasSize)
                            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
                            .simultaneousGesture(TapGesture().onEnded { model.dismissLockExplanation() })
                            .overlay(alignment: .bottom) {
                                // Floats over the photo like Instagram's
                                // filter row. Hidden while an element is
                                // being edited so it never fights the
                                // bounding box; not part of the export.
                                FramePreviewRail(model: model) { frame in
                                    withAnimation(pageAnimation) { model.select(frame) }
                                }
                                .frame(width: canvasSize.width)
                                .padding(.bottom, 10)
                                .opacity(model.selectedElement == nil ? 1 : 0)
                                .animation(Theme.stateChange, value: model.selectedElement == nil)
                            }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .offset(y: -Self.opticalCentreLift)
            .onAppear { canvasArea = proxy.size }
            .onChange(of: proxy.size) { _, size in canvasArea = size }
        }
    }

    /// Appears only once something on this frame has been moved, resized or
    /// removed. Snaps the arrangement back to its defaults.
    @ViewBuilder
    private var resetRow: some View {
        if model.isLayoutModified {
            Button("reset layout") {
                withAnimation(Theme.stateChange) { model.resetLayout() }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .transition(.opacity)
            .accessibilityLabel("Reset layout to default")
        }
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.86)
    }
}

// MARK: - Share sheet

private struct ShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet, given a JPEG file.
///
/// `UIActivityViewController` rather than `ShareLink`: the sheet has to be
/// raised from a button that first renders, and `ShareLink` wants its item up
/// front. A file URL is what makes Instagram, WhatsApp, Messages, AirDrop and
/// Save Image all behave.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Presentation

/// The one way the editor is presented.
///
/// A full-screen cover keyed on the origin, owned by whichever screen can
/// raise it — the tab shell for Progress, the morning flow for the success
/// screens. Both use this same modifier, so there is exactly one presenter.
struct StoryEditorPresenter: ViewModifier {
    @Binding var origin: ShareOrigin?
    let photos: ProgressPhotoStore?
    /// When set, a share raised from the stack zooms out of its card.
    let transitionNamespace: Namespace.ID?

    @Environment(AppStore.self) private var store
    @State private var layoutStore = StoryLayoutStore()

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $origin) { origin in
            StoryEditorView(
                origin: origin,
                store: store,
                photos: photos,
                layoutStore: layoutStore,
                onClose: { self.origin = nil }
            )
            .modifier(ZoomFromCard(origin: origin, namespace: transitionNamespace))
        }
    }
}

/// The system zoom from the stack card into the editor, on iOS 18.
///
/// Only for shares that came from a card that is on screen: a photo that was
/// just saved from the review screen has no card to grow out of yet, and the
/// editor crossfades in instead.
private struct ZoomFromCard: ViewModifier {
    let origin: ShareOrigin
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace, let photo = origin.photo, !origin.justSaved {
            content.navigationTransition(.zoom(sourceID: photo.id.uuidString, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// Presents the Story editor whenever `origin` is set.
    func storyEditor(
        origin: Binding<ShareOrigin?>,
        photos: ProgressPhotoStore? = nil,
        transitionNamespace: Namespace.ID? = nil
    ) -> some View {
        modifier(StoryEditorPresenter(origin: origin, photos: photos, transitionNamespace: transitionNamespace))
    }
}
