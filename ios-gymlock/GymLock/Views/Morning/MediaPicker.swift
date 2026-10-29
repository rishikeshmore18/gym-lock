import MediaPlayer
import SwiftUI

/// Whether the music library can be shown, and how to ask.
///
/// Checked before the picker is ever presented: a denied library shows an
/// empty picker with no explanation, which reads as a broken app.
nonisolated enum MusicLibraryAccess {
    enum Decision: Equatable {
        /// Authorised: present the picker.
        case present
        /// Never asked: ask once, then present if granted.
        case request
        /// Denied or restricted: explain inline and offer Settings. Never re-ask.
        case blocked
    }

    static func decision(for status: MPMediaLibraryAuthorizationStatus) -> Decision {
        switch status {
        case .authorized: .present
        case .notDetermined: .request
        case .denied, .restricted: .blocked
        @unknown default: .blocked
        }
    }

    static var currentStatus: MPMediaLibraryAuthorizationStatus {
        MPMediaLibrary.authorizationStatus()
    }

    /// The system prompt, as a value. The handler arrives on a background
    /// queue, so it is explicitly `@Sendable` and only resumes.
    static func requestAuthorization() async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// The system music-library picker, wrapped for SwiftUI.
///
/// It reports `assetURL`, which is the one thing the trimmer must know before
/// the user invests any time: DRM-protected tracks have no exportable asset
/// at all, and their `assetURL` is nil. Protected items are also hidden from
/// the list itself, so most people never meet the error.
struct MediaPicker: UIViewControllerRepresentable {
    struct Picked {
        var assetURL: URL?
        var title: String
        var hasProtectedAsset: Bool = false
    }

    /// The URL the trimmer may use, or nil when the item cannot be trimmed.
    nonisolated static func trimmableURL(assetURL: URL?, hasProtectedAsset: Bool) -> URL? {
        guard !hasProtectedAsset, let assetURL else { return nil }
        return assetURL
    }

    static func trimmableURL(for picked: Picked) -> URL? {
        trimmableURL(assetURL: picked.assetURL, hasProtectedAsset: picked.hasProtectedAsset)
    }

    var onPick: (Picked?) -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.showsItemsWithProtectedAssets = false
        picker.prompt = "pick a track you own"
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        private let onPick: (Picked?) -> Void

        init(onPick: @escaping (Picked?) -> Void) {
            self.onPick = onPick
        }

        func mediaPicker(
            _ mediaPicker: MPMediaPickerController,
            didPickMediaItems mediaItemCollection: MPMediaItemCollection
        ) {
            guard let item = mediaItemCollection.items.first else {
                onPick(nil)
                return
            }

            onPick(
                Picked(
                    assetURL: item.assetURL,
                    title: item.title ?? "your track",
                    hasProtectedAsset: item.hasProtectedAsset
                )
            )
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            onPick(nil)
        }
    }
}
