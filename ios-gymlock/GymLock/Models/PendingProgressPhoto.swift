import Foundation

/// A photo waiting on the user's decision because its day is already taken.
///
/// Holds the raw bytes rather than a saved file: nothing is written until the
/// user has seen both photographs side by side and confirmed, so backing out
/// leaves no orphaned files behind and the stored photo cannot be lost by
/// accident.
nonisolated struct PendingProgressPhoto: Identifiable, Equatable {
    let id = UUID()
    /// The original bytes, written only if the user confirms.
    let imageData: Data
    /// A screen-sized, upright copy for the comparison sheet.
    ///
    /// Prepared up front, off the main actor, because the alternative is
    /// decoding a 48-megapixel camera photo while the sheet is animating in.
    let previewData: Data
    let source: ProgressPhotoSource
    /// The day being claimed.
    let createdAt: Date
    /// The photo already stored for that day.
    let existing: ProgressPhoto

    static func == (lhs: PendingProgressPhoto, rhs: PendingProgressPhoto) -> Bool {
        lhs.id == rhs.id
    }

    /// How the day is named in the prompt — "today" reads better than a date
    /// when it is today, which is when this is hit most often.
    var dayDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) { return "today" }
        if calendar.isDateInYesterday(createdAt) { return "yesterday" }
        return createdAt.formatted(.dateTime.month(.wide).day())
    }
}
