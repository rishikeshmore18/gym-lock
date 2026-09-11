import Foundation

/// The day GymLock was first installed on this iPhone.
///
/// "Day 0" is a claim about the programme, not about the photograph: it means
/// the day the user started. Anchoring that here is what lets the Progress
/// Photos card tell a genuine before-picture apart from the oldest photo of
/// someone who only started taking them in week six.
///
/// Resolved at launch rather than the first time the Progress tab is opened —
/// a value first read three weeks in would record the wrong day, and nothing
/// afterwards could tell that it was wrong.
nonisolated enum AppInstallDate {
    static let key = "gymlock.installedAt"

    /// The stored install date, recording one the first time it is asked for.
    @discardableResult
    static func resolve(_ defaults: UserDefaults = .standard) -> Date {
        if let stored = defaults.object(forKey: key) as? Date { return stored }
        let resolved = containerCreationDate() ?? Date()
        defaults.set(resolved, forKey: key)
        return resolved
    }

    /// When iOS created this app's Documents directory — in practice, when the
    /// app was installed.
    ///
    /// Used for users who were already running GymLock before this was stored,
    /// who would otherwise have "today" recorded as their install date and
    /// would see an unrelated photo labelled Day 0.
    private static func containerCreationDate() -> Date? {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
              created <= Date()
        else { return nil }
        return created
    }
}
