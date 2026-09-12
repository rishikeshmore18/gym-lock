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
    /// re-sorting, and so "first" and "latest" always mean what they say even
    /// if a photo is imported with an older capture date than one already
    /// stored.
    private(set) var photos: [ProgressPhoto] = []
    /// True while a photo is being decoded and written.
    private(set) var isImporting = false
    /// Set when an import fails, for the alert. Cleared on dismissal.
    var failureMessage: String?
    /// A photo held back because that day already has one.
    ///
    /// Nothing touches the disk while this is set: the new photo waits in
    /// memory until the user has compared the two and decided, so backing out
    /// costs nothing and neither photograph can be lost by accident.
    private(set) var pendingReplacement: PendingProgressPhoto?

    /// The day the user started, which is what "Day 0" actually refers to.
    let installDate: Date

    private let defaults: UserDefaults
    private static let storageKey = "gymlock.progressPhotos"
    private static let dayZeroImportKey = "gymlock.progressPhotos.day0Imported"
    /// Longest edge of the stored thumbnail, in pixels.
    ///
    /// The card draws a photo at roughly 120pt wide; 600px covers that at 3x
    /// with room for the focused card's scale-up, and is a fraction of the
    /// 48-megapixel original it is made from.
    private nonisolated static let thumbnailPixels: CGFloat = 600
    /// Longest edge of the stored full-size copy.
    ///
    /// Large enough for a full-screen comparison on any iPhone, and far
    /// smaller than a modern camera original — a user photographing themselves
    /// every day for a year should not quietly fill their device.
    private nonisolated static let fullPixels: CGFloat = 2400
    /// Longest edge of the preview shown in the replace comparison.
    private nonisolated static let previewPixels: CGFloat = 1200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        installDate = AppInstallDate.resolve(defaults)
        load()
        reconcile()
    }

    // MARK: - Reading

    /// Whether the user has any real photos. Drives the demo stack.
    var hasPhotos: Bool { !photos.isEmpty }

    /// The cards the resting stack shows.
    var slides: [ProgressPhotoSlide] {
        ProgressPhotoSlide.slides(for: photos, installDate: installDate)
    }

    /// The photo already stored for a given day, if there is one.
    ///
    /// One photo per day is what keeps the card meaningful: the stack is a
    /// comparison across time, and ten photos from one morning are ten copies
    /// of the same moment crowding out the months on either side of them.
    ///
    /// Returns the *newest* photo of that day, not the oldest. This has to
    /// agree with the card, which labels the newest one "Latest" and draws it
    /// in front — answering with the oldest meant the comparison sheet showed
    /// the user a photograph that was not the one on their screen, and then
    /// replaced that one instead. It also made the duplicate permanent: if a
    /// day ever held two photos, every new photo replaced the older of them
    /// and the day was left holding two again.
    func photo(on date: Date) -> ProgressPhoto? {
        let calendar = Calendar.current
        return photos.last { calendar.isDate($0.createdAt, inSameDayAs: date) }
    }

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

    /// Repairs a history that earlier versions could leave inconsistent.
    ///
    /// Two faults are cleaned up here, both of which the user could see and
    /// neither of which they could fix:
    ///
    /// - **Rows with no files behind them.** These drew as a permanent grey
    ///   placeholder in the stack and as "Can't open this photo" in the
    ///   comparison. There is nothing to recover — the image is gone — so the
    ///   row goes too rather than occupying one of the four cards forever.
    /// - **More than one photo on a day.** The day rule is enforced on the way
    ///   in, but a history that predates the fix above still holds duplicates,
    ///   and the rule alone would never remove them.
    ///
    /// Runs at load, so a user who already has a broken stack is repaired by
    /// opening the app rather than by reinstalling it.
    private func reconcile() {
        let kept = Self.collapsingDuplicateDays(in: photos.filter(Self.hasFiles))
        guard kept != photos else { return }

        let discarded = photos.filter { photo in !kept.contains { $0.id == photo.id } }
        photos = kept
        persist()

        // Only the bytes of rows we dropped, and only after the index is
        // already consistent — a crash mid-cleanup must not be able to leave a
        // row pointing at a file that is no longer there.
        let names = discarded.flatMap { [$0.fileName, $0.thumbnailName] }
        Task.detached(priority: .utility) {
            for name in names {
                try? FileManager.default.removeItem(at: Self.url(forFileName: name))
            }
        }
    }

    /// Whether both files backing a photo are still on disk.
    ///
    /// Existence only, deliberately — not a decode. Reading and decoding every
    /// photo at launch would put the user's whole history through ImageIO
    /// before the first frame, and a transient read failure must never be
    /// grounds for deleting someone's photograph.
    private nonisolated static func hasFiles(_ photo: ProgressPhoto) -> Bool {
        let manager = FileManager.default
        return manager.fileExists(atPath: url(forFileName: photo.fileName).path)
            && manager.fileExists(atPath: url(forFileName: photo.thumbnailName).path)
    }

    /// Reduces each day to its newest photo.
    ///
    /// The newest wins because it is the one the card has been showing as
    /// "Latest", so the repair removes the photos the user was not looking at.
    /// Day 0 standing is carried over to the survivor: the fact that a day is
    /// the user's before-picture belongs to the day, not to whichever file
    /// happened to be kept.
    private nonisolated static func collapsingDuplicateDays(
        in photos: [ProgressPhoto]
    ) -> [ProgressPhoto] {
        let calendar = Calendar.current
        var byDay: [Date: ProgressPhoto] = [:]

        for photo in photos.sorted(by: { $0.createdAt < $1.createdAt }) {
            let day = calendar.startOfDay(for: photo.createdAt)
            var winner = photo
            if let previous = byDay[day] {
                winner.isDayZero = previous.isDayZero || photo.isDayZero
            }
            byDay[day] = winner
        }

        return byDay.values.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Writing

    /// Takes a photo from any of the three sources.
    ///
    /// Stops at the day check and hands the decision back to the user when that
    /// day is already spoken for; otherwise it writes straight through.
    func add(
        imageData: Data,
        source: ProgressPhotoSource,
        createdAt: Date?,
        isDayZero: Bool = false
    ) async {
        guard !isImporting, pendingReplacement == nil else { return }

        let date = createdAt ?? Date()
        if let existing = photo(on: date) {
            await holdForComparison(
                imageData: imageData,
                source: source,
                createdAt: date,
                existing: existing
            )
            return
        }

        await commit(
            imageData: imageData,
            source: source,
            createdAt: date,
            isDayZero: isDayZero
        )
    }

    /// Prepares the side-by-side comparison without writing anything.
    ///
    /// The preview is built here, off the main actor, rather than in the sheet:
    /// decoding a 48-megapixel camera photo while a sheet is animating in is
    /// exactly how a presentation ends up dropping frames.
    private func holdForComparison(
        imageData: Data,
        source: ProgressPhotoSource,
        createdAt: Date,
        existing: ProgressPhoto
    ) async {
        isImporting = true
        let pixels = Self.previewPixels
        let preview = await Task.detached(priority: .userInitiated) {
            Self.uprightJPEG(from: imageData, maxPixels: pixels)
        }.value
        isImporting = false

        guard let preview else {
            failureMessage = "Couldn't add this photo."
            return
        }

        pendingReplacement = PendingProgressPhoto(
            imageData: imageData,
            previewData: preview,
            source: source,
            createdAt: createdAt,
            existing: existing
        )
    }

    /// Swaps the day's existing photo for the one waiting.
    ///
    /// The replacement is written before the original is deleted, so a failed
    /// write leaves the user with the photo they already had rather than with
    /// nothing at all. Nothing here is reachable until the user has explicitly
    /// confirmed in the comparison sheet.
    func confirmReplacement() async {
        guard let request = pendingReplacement else { return }
        pendingReplacement = nil

        let before = photos.count
        await commit(
            imageData: request.imageData,
            source: request.source,
            createdAt: request.createdAt,
            // A replacement inherits the standing of the photo it replaces: if
            // the user is redoing their Day 0, the new one is still Day 0.
            isDayZero: request.existing.isDayZero
        )
        guard photos.count > before else { return }
        await remove(request.existing)
    }

    /// Throws the waiting photo away, keeping the one already saved.
    ///
    /// Deliberately synchronous and total: the new photo only ever existed in
    /// memory, so declining leaves the stored one untouched by construction
    /// rather than by careful cleanup.
    func cancelReplacement() {
        pendingReplacement = nil
    }

    /// Deletes a photo and the files behind it.
    func remove(_ photo: ProgressPhoto) async {
        photos.removeAll { $0.id == photo.id }
        persist()

        await ProgressPhotoImageLoader.shared.invalidate(photo.thumbnailName)
        await ProgressPhotoImageLoader.shared.invalidate(photo.fileName)

        let names = [photo.fileName, photo.thumbnailName]
        await Task.detached(priority: .utility) {
            for name in names {
                try? FileManager.default.removeItem(at: Self.url(forFileName: name))
            }
        }.value
    }

    /// Decodes, downsamples, writes and records one photo.
    ///
    /// The whole operation is funnelled through here — camera, library, files
    /// and the onboarding capture all end up on this path — so there is exactly
    /// one place where a photo can be created and exactly one definition of
    /// "saved".
    ///
    /// `isImporting` also acts as the re-entrancy guard: SwiftUI can deliver a
    /// picker result more than once as the view reloads, and without this a
    /// single selection could be written twice.
    private func commit(
        imageData: Data,
        source: ProgressPhotoSource,
        createdAt: Date,
        isDayZero: Bool
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
            createdAt: createdAt,
            fileName: fileName,
            thumbnailName: thumbnailName,
            source: source,
            isDayZero: isDayZero
        )

        photos.append(photo)
        photos.sort { $0.createdAt < $1.createdAt }
        persist()
        Haptics.commit()
    }

    // MARK: - Day 0

    /// Brings the onboarding Day 0 photograph into the stack, once.
    ///
    /// The user took that photo as their before-picture; making them take
    /// another one to start the comparison would be asking for the same thing
    /// twice. Video captures are skipped — the stack compares stills, and a
    /// frame grabbed from a clip is not what the user framed.
    ///
    /// Guarded by a flag rather than by "is there already a Day 0", so a user
    /// who deliberately deletes it does not have it silently reappear.
    func adoptDayZeroIfNeeded(_ media: Day0Media?) async {
        guard let media,
              media.kind == .photo,
              !defaults.bool(forKey: Self.dayZeroImportKey),
              let url = media.fileURL,
              let data = try? Data(contentsOf: url)
        else { return }

        // Already represented for that day: mark it done and leave the
        // existing photo alone. Straight to `commit` below rather than `add`,
        // because a comparison sheet appearing unprompted on first open of the
        // Progress tab would be baffling.
        guard photo(on: media.capturedAt) == nil else {
            defaults.set(true, forKey: Self.dayZeroImportKey)
            return
        }

        let before = photos.count
        await commit(
            imageData: data,
            source: .camera,
            createdAt: media.capturedAt,
            isDayZero: true
        )

        // The flag is only set once the photo is genuinely stored. Setting it
        // up front meant an adoption that lost the re-entrancy race — `commit`
        // returns silently while another import is in flight — was recorded as
        // done, and the user's before-picture was dropped for good.
        guard photos.count > before else { return }
        defaults.set(true, forKey: Self.dayZeroImportKey)
    }

    // MARK: - Files

    /// Writes the full-size copy and its thumbnail, cleaning up if either
    /// fails.
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

            guard let full = uprightJPEG(from: imageData, maxPixels: fullPixels),
                  let thumbnail = uprightJPEG(from: imageData, maxPixels: thumbnailPixels)
            else { return false }

            try full.write(to: fileURL, options: .atomic)
            try thumbnail.write(to: thumbURL, options: .atomic)

            // Read BOTH files back before declaring the photo saved. The card
            // draws from the thumbnail and the comparison sheet draws from the
            // full copy, so a row whose files cannot be decoded is
            // indistinguishable, on screen, from a photo that was never taken
            // — which is the worst possible outcome for a feature built on the
            // user trusting that their photos are kept. Verifying only the
            // thumbnail is what let a photo look saved on the card and then
            // have nothing to show when it was compared against.
            guard isReadable(fileURL), isReadable(thumbURL) else {
                try? FileManager.default.removeItem(at: fileURL)
                try? FileManager.default.removeItem(at: thumbURL)
                return false
            }

            return true
        } catch {
            // Never leave one half of the pair behind.
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: thumbURL)
            return false
        }
    }

    /// Whether a written file exists and decodes back into an image.
    private nonisolated static func isReadable(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        return UIImage(data: data) != nil
    }

    /// Re-encodes any image the system can read into an upright JPEG.
    ///
    /// Built on ImageIO rather than `UIImage(data:)` on purpose. ImageIO reads
    /// the formats a camera actually produces — HEIC, HEIF, ProRAW — decodes
    /// straight to the requested size so a 48-megapixel original never exists
    /// in memory at full size, and bakes the EXIF rotation into the pixels so
    /// the card cannot draw a portrait photo on its side.
    ///
    /// `UIImage` remains as a fallback for the rare source ImageIO declines,
    /// so an unusual file degrades to a slower path instead of to a photo the
    /// user is told could not be added.
    nonisolated static func uprightJPEG(from data: Data, maxPixels: CGFloat) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                // Applies the EXIF rotation to the pixels themselves.
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ] as [CFString: Any] as CFDictionary

            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                return UIImage(cgImage: image).jpegData(compressionQuality: 0.85)
            }
        }

        guard let fallback = UIImage(data: data) else { return nil }
        return fallback.uprightJPEGData(maxPixels: maxPixels)
    }

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
    /// Writes through `commit`, the same path a genuine import ends on, rather
    /// than injecting metadata directly — a fixture that skips the write is a
    /// fixture that cannot catch a bug in the write. It deliberately steps over
    /// the one-per-day check in `add`, which a dense fixture would otherwise
    /// trip on its second photo and stall waiting for an answer.
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
            await commit(
                imageData: data,
                source: .camera,
                createdAt: now.addingTimeInterval(-daysAgo * 86_400),
                isDayZero: step == 0
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
        pendingReplacement = nil
        persist()
    }
    #endif
}

// MARK: - Orientation

private extension UIImage {
    /// Redraws the image upright and no larger than `maxPixels` on its longest
    /// edge, baking the orientation into the pixels.
    ///
    /// `nonisolated` so it can run on the import task alongside the ImageIO
    /// path it backs up; drawing into an off-screen renderer needs no main
    /// actor.
    nonisolated func uprightJPEGData(maxPixels: CGFloat, quality: CGFloat = 0.85) -> Data? {
        let longest = max(size.width, size.height)
        let ratio = longest > maxPixels ? maxPixels / longest : 1
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let upright = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return upright.jpegData(compressionQuality: quality)
    }
}
