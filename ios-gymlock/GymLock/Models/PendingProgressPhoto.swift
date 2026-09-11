import Foundation

/// A photo waiting on the user's decision because its day is already taken.
///
/// Holds the raw bytes rather than a saved file: nothing is written until the
/// user chooses, so backing out leaves no orphaned files behind and there is
/// never a moment where the same day owns two photographs.
nonisolated struct PendingProgressPhoto: Identifiable {
    let id = UUID()
    let imageData: Data
    let source: ProgressPhotoSource
    /// The day being claimed.
    let createdAt: Date
    /// The photo already stored for that day.
    let existing: ProgressPhoto

    /// How the day is named in the prompt — "today" reads better than a date
    /// when it is today, which is when this is hit most often.
    var dayDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) { return "today" }
        if calendar.isDateInYesterday(createdAt) { return "yesterday" }
        return createdAt.formatted(.dateTime.month(.wide).day())
    }
}
