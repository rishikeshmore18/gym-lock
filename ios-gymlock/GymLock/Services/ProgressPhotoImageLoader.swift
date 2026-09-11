import UIKit

/// Loads and caches progress-photo thumbnails.
///
/// SwiftUI evaluates a view's body constantly — on every state change, every
/// drag frame, every parent redraw. Reading a file from disk inside that path
/// would decode the same JPEG dozens of times a second and make the Progress
/// screen stutter while the user drags the stack. Everything is therefore
/// decoded once, off the main actor, and held in an `NSCache` keyed by file
/// name, so a redraw is a dictionary lookup.
///
/// `NSCache` is used rather than a plain dictionary because it evicts itself
/// under memory pressure: a user with a hundred photos who drags through their
/// whole history should not accumulate every decoded image for the lifetime of
/// the app.
actor ProgressPhotoImageLoader {
    static let shared = ProgressPhotoImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    /// In-flight decodes, so two cards asking for the same file at the same
    /// moment share one read instead of racing.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 40
    }

    /// Returns the cached image immediately, if it is already decoded.
    ///
    /// Lets a view show a photo on its very first frame instead of flashing a
    /// placeholder for one runloop turn when scrolling back to it.
    nonisolated func cached(_ fileName: String) -> UIImage? {
        cache.object(forKey: fileName as NSString)
    }

    func image(named fileName: String) async -> UIImage? {
        if let hit = cache.object(forKey: fileName as NSString) { return hit }
        if let existing = inFlight[fileName] { return await existing.value }

        let task = Task<UIImage?, Never> { [cache] in
            let url = ProgressPhotoStore.url(forFileName: fileName)
            return await Task.detached(priority: .userInitiated) { () -> UIImage? in
                // A missing or corrupt file is an expected state, not a crash:
                // the user may have restored a backup without the container,
                // or a write may have been interrupted. The card shows a
                // neutral placeholder and the app carries on.
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data)
                else { return nil }
                cache.setObject(image, forKey: fileName as NSString)
                return image
            }.value
        }

        inFlight[fileName] = task
        let result = await task.value
        inFlight[fileName] = nil
        return result
    }

    /// Drops a file from the cache, used when a photo is replaced or removed.
    func invalidate(_ fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
    }
}

// MARK: - Demo artwork

/// Slices the bundled demonstration strip into its four frames.
///
/// The strip ships as one wide image containing four evenly spaced studio
/// frames of the same person. Cropping it at runtime keeps the asset catalog to
/// a single entry, and the four crops are cached after the first pass so the
/// cost is paid once per launch rather than on every redraw.
enum ProgressPhotoDemoArtwork {
    static let frameCount = 4
    private static let cache = NSCache<NSNumber, UIImage>()

    /// Returns one frame of the strip, or nil if the asset is missing.
    static func frame(_ index: Int) -> UIImage? {
        let clamped = min(max(index, 0), frameCount - 1)
        if let hit = cache.object(forKey: NSNumber(value: clamped)) { return hit }

        guard let strip = UIImage(named: "back_fitness_progress"),
              let cgImage = strip.cgImage
        else { return nil }

        let width = CGFloat(cgImage.width) / CGFloat(frameCount)
        let rect = CGRect(
            x: width * CGFloat(clamped),
            y: 0,
            width: width,
            height: CGFloat(cgImage.height)
        )

        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        let image = UIImage(cgImage: cropped, scale: strip.scale, orientation: .up)
        cache.setObject(image, forKey: NSNumber(value: clamped))
        return image
    }
}
