import MediaPlayer
import SwiftUI

/// The system music-library picker, wrapped for SwiftUI.
///
/// It reports `assetURL`, which is the one thing the trimmer must know before
/// the user invests any time: DRM-protected Apple Music tracks have no
/// exportable asset at all, and their `assetURL` is nil. Surfacing it here lets
/// the caller say so immediately rather than failing at export.
struct MediaPicker: UIViewControllerRepresentable {
    struct Picked {
        var assetURL: URL?
        var title: String
    }

    var onPick: (Picked?) -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
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
                    title: item.title ?? "your track"
                )
            )
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            onPick(nil)
        }
    }
}
