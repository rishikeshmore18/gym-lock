import Foundation

/// Where one frame stands for one share.
///
/// Three states, because "not offered" hides two different truths. A frame
/// the user has never once earned is *locked*: worth showing dimmed, so the
/// feature is discoverable and the way to it is stated. A frame the user has
/// earned before but which does not apply to this photo or day is *not
/// today*: hidden entirely, because a Receipt on a rest-day photo is not
/// locked, it simply is not about that day.
nonisolated enum FrameAvailability: Hashable {
    /// Usable right now, on this photo.
    case available
    /// Never satisfied anywhere in the user's history.
    case locked(FrameLock)
    /// Satisfied before, just not on this day or photo.
    case notToday

    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }

    var lock: FrameLock? {
        if case let .locked(lock) = self { return lock }
        return nil
    }
}

/// The true fact that stands between the user and a frame.
///
/// Copy is always forward-looking — what unlocks it, never what was missed.
/// `closeness` orders locks so the nearest one is shown first; it is never
/// drawn as a number or a ring.
nonisolated struct FrameLock: Hashable {
    /// "unlocks on day 14"
    let requirement: String
    /// "day 3 of 14" — nil when the condition is not countable.
    let progress: String?
    /// 0...1, how near to unlocking. For ordering only.
    let closeness: Double
}

/// What the whole record says has ever happened, for deciding locked versus
/// not-today. Built once alongside the context; every flag traces to the
/// ledger or the event log.
nonisolated struct FrameHistory: Hashable {
    /// Any `.showedUp` outcome, ever.
    let hasVerifiedVisit: Bool
    /// Any morning with alarm, departure and arrival logged in order, ever.
    let hasReceipt: Bool
    /// Any Monday-first week that met the weekly goal, ever.
    let hasKeptWeek: Bool
    /// Any `.homeWorkout` outcome, ever.
    let hasHomeWorkout: Bool
    /// Verified visits across the whole record, not only up to the
    /// reference day, so the next milestone threshold is the real next one.
    let verifiedVisitsEver: Int

    static let none = FrameHistory(
        hasVerifiedVisit: false,
        hasReceipt: false,
        hasKeptWeek: false,
        hasHomeWorkout: false,
        verifiedVisitsEver: 0
    )

    /// A record in which everything has happened at least once, so no frame
    /// is ever locked. Used by fixtures and by tests of the not-today path.
    static let everything = FrameHistory(
        hasVerifiedVisit: true,
        hasReceipt: true,
        hasKeptWeek: true,
        hasHomeWorkout: true,
        verifiedVisitsEver: 100
    )
}
