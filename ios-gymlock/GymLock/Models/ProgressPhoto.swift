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
}

// MARK: - Choosing what to show

/// Picks the handful of photos the resting card displays.
///
/// The card shows at most four cards, but the user may have a hundred photos.
/// Showing the four *newest* would be the easy thing and the wrong thing: after
/// a few months every card would look the same and the feature's whole promise
/// — seeing change — would quietly disappear. So the middle two are sampled
/// across the elapsed time instead, which keeps the oldest and newest at the
/// ends and puts genuine distance between the cards in between.
nonisolated enum ProgressPhotoSelection {
    /// How many cards the resting stack shows at most.
    static let displayCount = 4

    /// Fractions of the total elapsed time the middle cards aim for.
    private static let targets: [Double] = [1.0 / 3.0, 2.0 / 3.0]

    /// Returns up to four photos, oldest first, spread across the journey.
    ///
    /// Fewer than five photos are all returned as-is — there is nothing to
    /// sample and every photo is representative of itself.
    static func representative(from photos: [ProgressPhoto]) -> [ProgressPhoto] {
        let sorted = photos.sorted { $0.createdAt < $1.createdAt }
        guard sorted.count > displayCount else { return sorted }

        let indices = representativeIndices(in: sorted)
        return indices.map { sorted[$0] }
    }

    /// The chosen positions within an already-sorted array.
    ///
    /// Split out so the arithmetic can be tested and previewed without needing
    /// real files on disk behind it.
    static func representativeIndices(in sorted: [ProgressPhoto]) -> [Int] {
        let last = sorted.count - 1
        guard last >= displayCount - 1 else { return Array(0...max(last, 0)) }

        let span = sorted[last].createdAt.timeIntervalSince(sorted[0].createdAt)

        // Timestamps have to be both present and sensible. A zero or negative
        // span means every photo claims the same moment, in which case time
        // carries no information and position is the honest fallback.
        guard span.isFinite, span > 0 else { return quantileIndices(last: last) }

        var chosen: [Int] = [0]
        for fraction in targets {
            let target = sorted[0].createdAt.addingTimeInterval(span * fraction)
            // Only interior photos are candidates: the ends are already spoken
            // for, and a duplicate would cost one of the four slots.
            let candidates = (1..<last).filter { !chosen.contains($0) }
            guard let best = candidates.min(by: {
                abs(sorted[$0].createdAt.timeIntervalSince(target))
                    < abs(sorted[$1].createdAt.timeIntervalSince(target))
            }) else { continue }
            chosen.append(best)
        }
        chosen.append(last)

        // Time sampling can still come up short when many photos share a
        // timestamp, so the quantile fallback tops the selection back up.
        if chosen.count < displayCount {
            for index in quantileIndices(last: last) where !chosen.contains(index) {
                chosen.append(index)
                if chosen.count == displayCount { break }
            }
        }

        return chosen.sorted()
    }

    /// The four positions shown while the user is browsing their history.
    ///
    /// The resting stack samples across time, but once someone starts dragging
    /// they are looking for a specific moment, so the focused photo must be on
    /// screen even when it is not one of the four representatives. The ends are
    /// always kept — they are what the whole card is comparing — and the
    /// remaining slots go to the time-sampled middles.
    static func window(around focus: Int, in sorted: [ProgressPhoto]) -> [Int] {
        guard sorted.count > displayCount else {
            return Array(0..<sorted.count)
        }

        let last = sorted.count - 1
        let clampedFocus = min(max(focus, 0), last)
        var chosen: [Int] = [0]
        if !chosen.contains(clampedFocus) { chosen.append(clampedFocus) }
        if !chosen.contains(last) { chosen.append(last) }

        for index in representativeIndices(in: sorted) where chosen.count < displayCount {
            if !chosen.contains(index) { chosen.append(index) }
        }

        // With many identical timestamps the sampler can repeat itself, so any
        // remaining slots are filled with whatever is still unused.
        if chosen.count < displayCount {
            for index in 0...last where chosen.count < displayCount {
                if !chosen.contains(index) { chosen.append(index) }
            }
        }

        return chosen.sorted()
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
        case dayZero
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
    /// single photo the user is at the start of the journey, not the end of it,
    /// so it reads "Day 0" alone.
    static func slides(
        for photos: [ProgressPhoto],
        focus: Int? = nil
    ) -> [ProgressPhotoSlide] {
        let sorted = photos.sorted { $0.createdAt < $1.createdAt }
        guard !sorted.isEmpty else { return demoSlides }

        let shown: [ProgressPhoto] = if let focus {
            ProgressPhotoSelection.window(around: focus, in: sorted).map { sorted[$0] }
        } else {
            ProgressPhotoSelection.representative(from: sorted)
        }

        let lastIndex = shown.count - 1
        return shown.enumerated().map { index, photo in
            let marker: Marker? = if index == 0 {
                .dayZero
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
