import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The system Files picker for one audio file, wrapped for SwiftUI.
///
/// Used instead of `.fileImporter`, whose selection was not delivered when
/// presented from the pushed song page: the picker stayed open and tapping a
/// song did nothing. Here the delegate is called directly by UIKit.
///
/// `asCopy: true` asks the system to download (iCloud and other providers)
/// and copy the file into this app before calling back, so the URL handed
/// over is already local and readable.
struct AudioFilePicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.audio],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
