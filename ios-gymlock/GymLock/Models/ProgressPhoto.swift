import Foundation

/// Where a progress photo came from. Recorded for diagnostics only — the card
/// treats every photo the same regardless of how it arrived.
nonisolated enum ProgressPhotoSource: String, Codable, Hashable {
    case camera
    case library
    case files
}

/// One progress photo belonging to the user.
///
/// Only metadata lives here. The image itself is a file in the app's own
/// Documents directory, exactly as Day 0 already works: file *names* are stored
/// rather than paths, because the container path changes between launches and
/// app updates and a stored absolute path would break on the next install.
nonisolated struct ProgressPhoto: Codable, Hashable, Identifiable {
    let id: UUID
    /// When the photo was taken — the original capture date when the file
    /// carried one, otherwise the time it was imported.
    var createdAt: Date
    /// Full-resolution original, inside `Documents/ProgressPhotos`.
    var fileName: String
    /// Downsampled copy used by the card, in the same directory.
    var thumbnailName: String
    var source: ProgressPhotoSource
    /// True for the photograph taken during onboarding, which is the user's
    /// real before-picture no matter what its date turns out to be.
    var isDayZero: Bool = false
}

extension ProgressPhoto {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, fileName, thumbnailName, source, isDayZero
    }

    /// Decoded by hand so that photos saved before `isDayZero` existed still
    /// load. A synthesised decoder would throw on the missing key, and because
    /// the whole array is decoded in one go, one old row would wipe out the
    /// user's entire photo history.
    ///
    /// `nonisolated` because decoding happens off the main actor — the store
    /// reads this on a background task, and an implicitly main-actor decoder
    /// would be a data race the moment it did.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fileName = try container.decode(String.self, forKey: .fileName)
        thumbnailName = try container.decode(String.self, forKey: .thumbnailName)
        source = try container.decode(ProgressPhotoSource.self, forKey: .source)
        isDayZero = try container.decodeIfPresent(Bool.self, forKey: .isDayZero) ?? false
    }
}

// MARK: - Choosing what to show

/// Picks the handful of photos the resting card displays.
///
/// The card shows at most four cards, but the user may have a hundred photos.
/// Showing the four *newest* would be the easy thing and the wrong thing: after
/// a few months every card would look the same and the feature's whole promise
/// — seeing change — would quietly disappear. So the middle two are chosen by
/// date rather than by position, which keeps the first and the latest at the
/// ends and puts genuine elapsed time between the cards in between.
nonisolated enum ProgressPhotoSelection {
    /// How many cards the resting stack shows at most.
    static let displayCount = 4

    /// Fractions of the total elapsed time the middle cards aim for.
    private static let targets: [Double] = [1.0 / 3.0, 2.0 / 3.0]

    /// Returns up to four photos, oldest first, spread across the journey.
    ///
    /// Four or fewer photos are all returned as they are: there is nothing to
    /// sample, and every photo is representative of itself.
    static func representative(from photos: [ProgressPhoto]) -> [ProgressPhoto] {
        let sorted = photos.sorted { $0.createdAt < $1.createdAt }
        return representativeIndices(in: sorted).map { sorted[$0] }
    }

    /// The chosen positions within an already-sorted array.
    ///
    /// Split out so the arithmetic can be tested and previewed without needing
    /// real files on disk behind it. Always returns distinct, ascending
    /// positions, and always includes the first and the last photo.
    static func representativeIndices(in sorted: [ProgressPhoto]) -> [Int] {
        guard sorted.count > displayCount else { return Array(sorted.indices) }

        let last = sorted.count - 1
        var chosen = [0, last]

        // The two interior cards are picked by *date*, not by position. Someone
        // who photographed themselves daily for a fortnight and then monthly
        // for a year has their history bunched at one end of the array, and
        // sampling by position would spend three of the four cards on that
        // fortnight.
        let span = sorted[last].createdAt.timeIntervalSince(sorted[0].createdAt)
        if span.isFinite, span > 0 {
            for fraction in targets {
                let target = sorted[0].createdAt.addingTimeInterval(span * fraction)
                guard let best = nearest(to: target, in: sorted, excluding: chosen) else { continue }
                chosen.append(best)
            }
        }

        return filled(chosen, last: last)
    }

    /// The photo closest in time to a target date, ignoring the ends.
    ///
    /// The ends are already spoken for, and letting one of them win a midpoint
    /// would spend two of the four slots on the same photograph.
    private static func nearest(
        to target: Date,
        in sorted: [ProgressPhoto],
        excluding taken: [Int]
    ) -> Int? {
        let last = sorted.count - 1
        guard last > 1 else { return nil }
        return (1..<last)
            .filter { !taken.contains($0) }
            .min {
                abs(sorted[$0].createdAt.timeIntervalSince(target))
                    < abs(sorted[$1].createdAt.timeIntervalSince(target))
            }
    }

    /// The four positions shown while the user is browsing their history.
    ///
    /// The resting stack samples across time, but once someone starts dragging
    /// they are looking for a specific moment, so the focused photo must be on
    /// screen even when it is not one of the four representatives. The ends are
    /// always kept — they are what the whole card is comparing.
    static func window(around focus: Int, in sorted: [ProgressPhoto]) -> [Int] {
        guard sorted.count > displayCount else { return Array(sorted.indices) }

        let last = sorted.count - 1
        let clampedFocus = min(max(focus, 0), last)
        var chosen = [0, last]
        if !chosen.contains(clampedFocus) { chosen.append(clampedFocus) }

        for index in representativeIndices(in: sorted)
        where chosen.count < displayCount && !chosen.contains(index) {
            chosen.append(index)
        }

        return filled(chosen, last: last)
    }

    /// Tops a selection up to exactly four distinct, ascending positions.
    ///
    /// Time sampling can come up short when many photos share a timestamp, and
    /// a stack that silently shows three cards for a user with forty photos
    /// would look like a bug. Nothing is ever repeated to reach four — with
    /// fewer than four photos available the selection simply stays short.
    private static func filled(_ chosen: [Int], last: Int) -> [Int] {
        var result = chosen

        if result.count < displayCount {
            for index in quantileIndices(last: last) where !result.contains(index) {
                result.append(index)
                if result.count == displayCount { break }
            }
        }
        if result.count < displayCount {
            for index in 0...last where !result.contains(index) {
                result.append(index)
                if result.count == displayCount { break }
            }
        }

        return Array(result.sorted().prefix(displayCount))
    }

    /// Evenly spaced positions, used when the dates cannot be trusted.
    private static func quantileIndices(last: Int) -> [Int] {
        let steps = displayCount - 1
        var result: [Int] = []
        for step in 0...steps {
            let position = (Double(step) * Double(last) / Double(steps)).rounded()
            let index = min(max(Int(position), 0), last)
            if !result.contains(index) { result.append(index) }
        }
        return result
    }
}

// MARK: - What a card in the stack draws

/// A single card in the photo stack.
///
/// Real photos and the bundled demo images both become slides, so the stack
/// itself never needs to know which it is drawing — only the card's label and
/// image source differ.
struct ProgressPhotoSlide: Identifiable, Hashable {
    /// Which end of the journey this card sits at, if either.
    enum Marker: Hashable {
        /// The user's genuine before-picture: taken the day they installed
        /// GymLock, or captured during onboarding.
        case dayZero
        /// The oldest photo of a user who started later. Calling this one
        /// "Day 0" would be a small lie the user can immediately check, and it
        /// would make every comparison against it read as a bigger result than
        /// it is.
        case first
        case latest
    }

    enum Content: Hashable {
        case photo(ProgressPhoto)
        /// One quarter of the bundled demonstration strip.
        case demo(index: Int)
    }

    let id: String
    let content: Content
    let marker: Marker?
    /// Nil for demo cards: they must never imply a real date.
    let date: Date?

    var isDemo: Bool {
        if case .demo = content { return true }
        return false
    }

    var markerText: String? {
        switch marker {
        case .dayZero: "Day 0"
        case .first: "1st"
        case .latest: "Latest"
        case nil: nil
        }
    }

    /// Builds the stack from the user's real photos.
    ///
    /// Pass `focus` to keep a specific photo on screen while the user drags
    /// through a long history; omit it for the resting, time-sampled view.
    ///
    /// Only the two ends are ever labelled, and never both on one card — with a
    /// single photo the user is at the start of the journey, not the end of it.
    static func slides(
        for photos: [ProgressPhoto],
        focus: Int? = nil,
        installDate: Date
    ) -> [ProgressPhotoSlide] {
        let sorted = photos.sorted { $0.createdAt < $1.createdAt }
        guard !sorted.isEmpty else { return demoSlides }

        let shown: [ProgressPhoto] = if let focus {
            ProgressPhotoSelection.window(around: focus, in: sorted).map { sorted[$0] }
        } else {
            ProgressPhotoSelection.representative(from: sorted)
        }

        let lastIndex = shown.count - 1
        let opening = openingMarker(for: sorted[0], installDate: installDate)

        return shown.enumerated().map { index, photo in
            let marker: Marker? = if index == 0 {
                opening
            } else if index == lastIndex {
                .latest
            } else {
                nil
            }
            return ProgressPhotoSlide(
                id: photo.id.uuidString,
                content: .photo(photo),
                marker: marker,
                date: photo.createdAt
            )
        }
    }

    /// Whether the oldest photo has earned the words "Day 0".
    ///
    /// Either it is the onboarding capture, or it was taken on the day the app
    /// was installed. Anything else is simply the first photo the user has.
    static func openingMarker(for oldest: ProgressPhoto, installDate: Date) -> Marker {
        if oldest.isDayZero { return .dayZero }
        return Calendar.current.isDate(oldest.createdAt, inSameDayAs: installDate)
            ? .dayZero
            : .first
    }

    /// The placeholder stack, shown only until the first real photo exists.
    static let demoSlides: [ProgressPhotoSlide] = (0..<4).map { index in
        ProgressPhotoSlide(
            id: "demo-\(index)",
            content: .demo(index: index),
            marker: index == 0 ? .dayZero : (index == 3 ? .latest : nil),
            date: nil
        )
    }
}
