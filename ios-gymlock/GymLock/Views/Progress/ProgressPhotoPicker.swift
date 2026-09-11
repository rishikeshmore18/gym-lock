import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Everything needed to get one image into the store, from any of the three
/// sources, attached to the Progress Photos card as a single modifier.
///
/// The three import paths are deliberately funnelled into one `deliver` call:
/// there is exactly one place where a photo becomes real, which is what keeps
/// a duplicate from slipping in when SwiftUI re-delivers a picker result.
struct ProgressPhotoImporter: ViewModifier {
    let store: ProgressPhotoStore
    @Binding var isShowingSourceDialog: Bool

    @State private var isShowingCamera = false
    @State private var isShowingFiles = false
    @State private var isShowingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var cameraDenied = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Add progress photo",
                isPresented: $isShowingSourceDialog,
                titleVisibility: .visible
            ) {
                // Offered only where a camera actually exists, so the user is
                // never sent into a dead end.
                if ProgressPhotoCameraAvailability.hasCamera {
                    Button("Take Photo") { present { startCamera() } }
                }
                Button("Choose from Photos") { present { isShowingLibrary = true } }
                Button("Choose from Files") { present { isShowingFiles = true } }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(
                isPresented: $isShowingLibrary,
                selection: $libraryItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .fullScreenCover(isPresented: $isShowingCamera) {
                ProgressPhotoCaptureSheet { data in
                    isShowingCamera = false
                    deliver(data: data, source: .camera, createdAt: Date())
                } onCancel: {
                    isShowingCamera = false
                }
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
    }

    // MARK: Sources

    /// Presents after the confirmation dialog has finished dismissing.
    ///
    /// Raising a sheet in the same runloop turn that dismisses another one is
    /// the classic way to get a presentation silently dropped — the user taps
    /// "Choose from Photos" and nothing happens.
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
            await store.add(imageData: data, source: .library, createdAt: nil)
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
        await store.add(imageData: data, source: .files, createdAt: created)
    }

    private func deliver(data: Data, source: ProgressPhotoSource, createdAt: Date?) {
        Task { await store.add(imageData: data, source: source, createdAt: createdAt) }
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
        isShowingSourceDialog: Binding<Bool>
    ) -> some View {
        modifier(
            ProgressPhotoImporter(store: store, isShowingSourceDialog: isShowingSourceDialog)
        )
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
