import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// An imported image waiting on the review screen.
///
/// Held in memory only. Nothing reaches the store until the user has looked at
/// the photograph and chosen what to do with it.
private struct PendingReview: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
    let source: ProgressPhotoSource
    let createdAt: Date?
    /// Which picker to reopen if the user asks for another.
    let choice: ProgressPhotoSourceChoice
}

/// Everything needed to get one image into the store, from any of the three
/// sources, attached to the Progress Photos card as a single modifier.
///
/// The three import paths are deliberately funnelled into one `deliver` call:
/// there is exactly one place where a photo becomes real, which is what keeps
/// a duplicate from slipping in when SwiftUI re-delivers a picker result. And
/// since the review step, every path also passes through exactly one review.
struct ProgressPhotoImporter: ViewModifier {
    let store: ProgressPhotoStore
    /// Set by the Add Photo menu, cleared as soon as it has been acted on.
    @Binding var pendingSource: ProgressPhotoSourceChoice?
    /// Opens the Story editor on a photo that has just been saved.
    let onShare: (ProgressPhoto) -> Void

    @State private var isShowingCamera = false
    @State private var isShowingFiles = false
    @State private var isShowingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var cameraDenied = false
    /// A Photos or Files import on the review screen.
    @State private var review: PendingReview?
    /// Set when the user chose Share and the day turned out to be taken. The
    /// comparison sheet decides; if it confirms, the editor opens on the
    /// photo that was actually written.
    @State private var wantsShareAfterReplacement = false

    func body(content: Content) -> some View {
        content
            .onChange(of: pendingSource) { _, choice in
                guard let choice else { return }
                // Cleared straight away so picking the same source twice in a
                // row still registers as a change.
                pendingSource = nil
                route(choice)
            }
            .photosPicker(
                isPresented: $isShowingLibrary,
                selection: $libraryItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .fullScreenCover(isPresented: $isShowingCamera) {
                // The sheet only calls back once the user has reviewed the
                // frame and chosen, so everything arriving here is already
                // approved.
                ProgressPhotoCaptureSheet(isSaving: store.isImporting) { data, intent in
                    isShowingCamera = false
                    deliver(data: data, source: .camera, createdAt: Date(), intent: intent)
                } onCancel: {
                    isShowingCamera = false
                }
            }
            .fullScreenCover(item: $review) { pending in
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressPhotoReviewView(
                        image: pending.image,
                        retakeTitle: "Choose another",
                        isBusy: store.isImporting,
                        onRetake: {
                            review = nil
                            present { route(pending.choice) }
                        },
                        onChoose: { intent in
                            review = nil
                            deliver(
                                data: pending.data,
                                source: pending.source,
                                createdAt: pending.createdAt,
                                intent: intent
                            )
                        },
                        onCancel: { review = nil }
                    )
                }
                .preferredColorScheme(.dark)
            }
            .fileImporter(
                isPresented: $isShowingFiles,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                // Cleared immediately so re-selecting the same asset later
                // still registers as a change.
                libraryItem = nil
                loadFromLibrary(item)
            }
            .alert(
                "Camera access is off",
                isPresented: $cameraDenied
            ) {
                Button("Open Settings") { openSettings() }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("GymLock needs camera access to take a progress photo. You can turn it on in Settings.")
            }
            .alert(
                "Couldn't add this photo.",
                isPresented: Binding(
                    get: { store.failureMessage != nil },
                    set: { if !$0 { store.failureMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { store.failureMessage = nil }
            }
            .progressPhotoReplaceSheet(store: store) { replaced in
                guard wantsShareAfterReplacement else { return }
                wantsShareAfterReplacement = false
                // The comparison sheet is still dismissing; same rule as
                // everywhere else, or the editor is silently dropped.
                present { onShare(replaced) }
            }
    }

    // MARK: Sources

    private func route(_ choice: ProgressPhotoSourceChoice) {
        switch choice {
        case .camera: present { startCamera() }
        case .library: present { isShowingLibrary = true }
        case .files: present { isShowingFiles = true }
        }
    }

    /// Presents after the menu has finished collapsing.
    ///
    /// Raising a sheet in the same runloop turn that dismisses another
    /// presentation is the classic way to get it silently dropped — the user
    /// taps "Choose from Photos" and nothing happens.
    private func present(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            action()
        }
    }

    /// Asks for camera permission before presenting anything.
    ///
    /// A denied user is told once, with a route to Settings, rather than being
    /// re-prompted — iOS ignores repeat requests anyway, so asking again would
    /// simply do nothing and look broken.
    private func startCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    isShowingCamera = true
                } else {
                    cameraDenied = true
                }
            }
        default:
            cameraDenied = true
        }
    }

    private func loadFromLibrary(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                store.failureMessage = "Couldn't add this photo."
                return
            }
            // PhotosPicker hands over the chosen asset without the app ever
            // holding library-wide permission, so no authorisation is
            // requested here.
            await openReview(data: data, source: .library, createdAt: nil, choice: .library)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            Task { await copyFromFiles(url) }
        case .failure:
            // Cancelling the importer surfaces as a failure too, and a user who
            // changed their mind should not be shown an error.
            break
        }
    }

    /// Copies an external file into the app's own storage.
    ///
    /// The security-scoped URL is only valid inside this access window, and the
    /// file may live in iCloud Drive or another app's container, so the bytes
    /// are read now rather than the URL being stored and reopened later.
    private func copyFromFiles(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            store.failureMessage = "Couldn't add this photo."
            return
        }

        let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        await openReview(data: data, source: .files, createdAt: created, choice: .files)
    }

    /// Puts an imported image on the review screen.
    ///
    /// The image is decoded once here, off the main actor, so the cover has
    /// something to draw on its first frame rather than a black screen while
    /// a large file is read. A file the system cannot decode fails here, with
    /// the same alert a failed save would show.
    private func openReview(
        data: Data,
        source: ProgressPhotoSource,
        createdAt: Date?,
        choice: ProgressPhotoSourceChoice
    ) async {
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value

        guard let image else {
            store.failureMessage = "Couldn't add this photo."
            return
        }

        present {
            review = PendingReview(
                data: data,
                image: image,
                source: source,
                createdAt: createdAt,
                choice: choice
            )
        }
    }

    /// Hands one approved image to the store, then does what the user asked.
    ///
    /// Waits for the review to finish dismissing first. `add` may decide the
    /// day is taken and raise the comparison sheet, and a sheet presented in
    /// the same runloop turn that dismisses a full-screen cover is silently
    /// dropped — the user would tap Use Photo and see nothing happen at all.
    ///
    /// Sharing always saves first. The editor only ever opens on a photo the
    /// store has actually written, and a failed save shows the failure alert
    /// and no editor.
    private func deliver(
        data: Data,
        source: ProgressPhotoSource,
        createdAt: Date?,
        intent: ProgressPhotoIntent
    ) {
        present {
            Task {
                let result = await store.add(imageData: data, source: source, createdAt: createdAt)
                guard intent == .saveAndShare else { return }

                switch result {
                case let .saved(photo):
                    onShare(photo)
                case .needsDecision:
                    wantsShareAfterReplacement = true
                case .failed:
                    break
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension View {
    /// Attaches the photo import flow to a view.
    func progressPhotoImporter(
        store: ProgressPhotoStore,
        pendingSource: Binding<ProgressPhotoSourceChoice?>,
        onShare: @escaping (ProgressPhoto) -> Void
    ) -> some View {
        modifier(ProgressPhotoImporter(store: store, pendingSource: pendingSource, onShare: onShare))
    }
}

// MARK: - Camera availability

/// Whether this device can take a photo at all.
///
/// The cloud simulator publishes the host webcam as an *external* device, so
/// that type is included rather than the check being disabled on simulator.
enum ProgressPhotoCameraAvailability {
    static var hasCamera: Bool {
        !AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInDualWideCamera,
                .builtInTrueDepthCamera,
                .external,
            ],
            mediaType: .video,
            position: .unspecified
        ).devices.isEmpty
    }
}
