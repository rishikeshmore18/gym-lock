import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// Owns the user's progress photos: the files on disk and the metadata index.
///
/// The split follows what the app already does for Day 0 and for imported alarm
/// tracks — bytes go to the filesystem, and only small metadata goes to
/// `UserDefaults`. Image data must never be written into `UserDefaults`: it is
/// loaded wholesale into memory at launch, and a handful of camera photos would
/// make every app start slower for as long as the user keeps them.
@Observable
@MainActor
final class ProgressPhotoStore {
    /// Everything the user has saved, oldest first.
    ///
    /// Sorted on the way in so the rest of the app can trust the order without
    /// re-sorting, and so "oldest" and "latest" always mean what they say even
    /// if a photo is imported with an older capture date than one already
    /// stored.
    private(set) var photos: [ProgressPhoto] = []
    /// True while a photo is being decoded and written.
    private(set) var isImporting = false
    /// Set when an import fails, for the alert. Cleared on dismissal.
    var failureMessage: String?

    private let defaults: UserDefaults
    private static let storageKey = "gymlock.progressPhotos"
    /// Longest edge of the stored thumbnail, in pixels.
    ///
    /// The card draws a photo at roughly 120pt wide; 600px covers that at 3x
    /// with room for the focused card's scale-up, and is a fraction of the
    /// 48-megapixel original it is made from.
    private static let thumbnailPixels: CGFloat = 600

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Reading

    /// Whether the user has any real photos. Drives the demo stack.
    var hasPhotos: Bool { !photos.isEmpty }

    /// The cards the resting stack shows.
    var slides: [ProgressPhotoSlide] { ProgressPhotoSlide.slides(for: photos) }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ProgressPhoto].self, from: data)
        else { return }
        photos = decoded.sorted { $0.createdAt < $1.createdAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(photos) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - Writing

    /// Decodes, downsamples, writes and records one photo.
    ///
    /// The whole operation is funnelled through here — camera, library and
    /// files all end up on this path — so there is exactly one place where a
    /// photo can be created and exactly one definition of "saved".
    ///
    /// `isImporting` also acts as the re-entrancy guard: SwiftUI can deliver a
    /// picker result more than once as the view reloads, and without this a
    /// single selection could be written twice.
    func add(
        imageData: Data,
        source: ProgressPhotoSource,
        createdAt: Date?
    ) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let id = UUID()
        let fileName = "progress-\(id.uuidString).jpg"
        let thumbnailName = "progress-\(id.uuidString)-thumb.jpg"
        let directory = Self.directoryURL

        let outcome = await Task.detached(priority: .userInitiated) { () -> Bool in
            Self.write(
                imageData: imageData,
                to: directory,
                fileName: fileName,
                thumbnailName: thumbnailName
            )
        }.value

        guard outcome else {
            failureMessage = "Couldn't add this photo."
            return
        }

        let photo = ProgressPhoto(
            id: id,
            createdAt: createdAt ?? Date(),
            fileName: fileName,
            thumbnailName: thumbnailName,
            source: source
        )

        photos.append(photo)
        photos.sort { $0.createdAt < $1.createdAt }
        persist()
        Haptics.commit()
    }

    /// Writes the original and its thumbnail, cleaning up if either fails.
    ///
    /// Returning a bool rather than throwing keeps the failure handling in one
    /// place: the caller only ever has to answer "is there a usable pair of
    /// files on disk", and a half-written pair is deleted here rather than
    /// becoming a metadata row that points at a file the card cannot open.
    private nonisolated static func write(
        imageData: Data,
        to directory: URL,
        fileName: String,
        thumbnailName: String
    ) -> Bool {
        let fileURL = directory.appendingPathComponent(fileName)
        let thumbURL = directory.appendingPathComponent(thumbnailName)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            // Re-encoding normalises orientation. A photo carrying an EXIF
            // rotation flag would otherwise draw sideways in the card, because
            // the flag travels with the file and not with the pixels.
            guard let decoded = UIImage(data: imageData),
                  let normalised = decoded.normalizedJPEGData()
            else { return false }

            try normalised.write(to: fileURL, options: .atomic)

            guard let thumbnail = downsampledJPEG(from: imageData) else {
                try? FileManager.default.removeItem(at: fileURL)
                return false
            }
            try thumbnail.write(to: thumbURL, options: .atomic)
            return true
        } catch {
            // Never leave one half of the pair behind.
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: thumbURL)
            return false
        }
    }

    /// Builds the card-sized copy with ImageIO.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` decodes straight to the requested
    /// size, so a 48-megapixel HEIC never has to exist in memory at full size.
    /// Handing the original to `UIImage` and scaling it afterwards would
    /// allocate close to 200MB for the same result.
    private nonisolated static func downsampledJPEG(from data: Data) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies the EXIF rotation to the pixels themselves.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
        ] as [CFString: Any] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.82)
    }

    // MARK: - Files

    /// The app-owned directory holding every progress photo.
    ///
    /// Inside Documents, so the photos survive updates and are covered by the
    /// user's device backup, and entirely inside the app's container — these
    /// images are private and there is no upload path anywhere near them.
    nonisolated static var directoryURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ProgressPhotos", isDirectory: true)
    }

    nonisolated static func url(forFileName name: String) -> URL {
        directoryURL.appendingPathComponent(name)
    }

    #if DEBUG
    /// Fills the store with real files so the photo-count states can be seen.
    ///
    /// Goes through the same `add` path as a genuine import rather than
    /// injecting metadata directly — a fixture that skips the write is a
    /// fixture that cannot catch a bug in the write.
    func debugSeed(count: Int) async {
        await debugClear()

        let now = Date()
        for step in 0..<count {
            // Spread backwards over ~12 weeks so the time-based sampling has
            // something real to sample.
            let daysAgo = Double(count - 1 - step) * (84.0 / Double(max(count - 1, 1)))
            let frame = ProgressPhotoDemoArtwork.frame(
                step * ProgressPhotoDemoArtwork.frameCount / max(count, 1)
            )
            guard let data = frame?.jpegData(compressionQuality: 0.9) else { continue }
            await add(
                imageData: data,
                source: .camera,
                createdAt: now.addingTimeInterval(-daysAgo * 86_400)
            )
        }
    }

    /// Removes every stored photo and its files.
    func debugClear() async {
        let directory = Self.directoryURL
        await Task.detached {
            try? FileManager.default.removeItem(at: directory)
        }.value
        photos = []
        persist()
    }
    #endif
}

// MARK: - Orientation

private extension UIImage {
    /// Redraws the image with its orientation baked into the pixels.
    ///
    /// Returns the data unchanged when it is already upright, avoiding a
    /// pointless re-encode of an untouched camera photo.
    func normalizedJPEGData(quality: CGFloat = 0.92) -> Data? {
        guard imageOrientation != .up else { return jpegData(compressionQuality: quality) }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let upright = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return upright.jpegData(compressionQuality: quality)
    }
}
