import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The rendered Story, ready for the share sheet.
///
/// Handed over as a JPEG *file* with a sensible name rather than as image
/// data: Instagram, WhatsApp, Messages, AirDrop and Save Image all behave when
/// given a named file, and several of them misbehave when given a `UIImage`.
nonisolated struct RenderedStory: Identifiable, Hashable {
    let id = UUID()
    let data: Data
    let fileName: String

    /// Writes the file the share sheet will offer. Overwrites the previous
    /// export of the same format, so the temp directory never accumulates.
    func writeToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Getting a rendered Story out of the app.
@MainActor
enum ShareService {
    /// How long a sticker stays on the clipboard before iOS clears it.
    private static let pasteboardLifetime: TimeInterval = 5 * 60

    /// Copies a transparent PNG for the user to paste over their own photo.
    static func copySticker(_ png: Data) {
        UIPasteboard.general.setItems(
            [[UTType.png.identifier: png]],
            options: [.expirationDate: Date().addingTimeInterval(pasteboardLifetime)]
        )
        Haptics.soft()
    }

    // MARK: Instagram Stories

    private static let instagramStoriesScheme = "instagram-stories://share"

    /// Whether the Instagram quick action may be shown: configured *and*
    /// Instagram is installed.
    static var canShareToInstagramStories: Bool {
        guard ShareConfiguration.isInstagramStoriesConfigured,
              let url = URL(string: instagramStoriesScheme)
        else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Hands a Story straight to Instagram's composer.
    ///
    /// Instagram reads the pasteboard on launch; the items expire so the
    /// image does not sit on the clipboard afterwards.
    static func shareToInstagramStories(background jpeg: Data) {
        guard let appID = ShareConfiguration.metaAppID,
              let url = URL(string: "\(instagramStoriesScheme)?source_application=\(appID)")
        else { return }

        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": jpeg]],
            options: [.expirationDate: Date().addingTimeInterval(pasteboardLifetime)]
        )
        UIApplication.shared.open(url)
    }
}
