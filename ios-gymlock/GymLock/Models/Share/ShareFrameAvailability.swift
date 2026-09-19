import Foundation

/// Which frames a context can honestly support.
///
/// A frame appears only when every field it renders is present. There are no
/// placeholders and no "Week 1" variants invented for users who have not
/// earned the real thing — a first-week user gets Showed Up, and Momentum
/// arrives when there is momentum to show.
///
/// `availability(for:)` goes one step further and says *why* a frame is
/// absent: never earned (locked, shown dimmed) or earned before but not about
/// this day (hidden). Comeback is the deliberate exception — its condition is
/// missing a session, and that is never dangled as a goal.
enum ShareFrameAvailability {
    static let maximumFrames = 6

    /// When more than six qualify, these go first, in this order. The frames
    /// not listed here are never dropped.
    static let dropOrder: [ShareFrame] = [.journey, .milestone, .comeback]

    /// Journey needs enough history to be a journey.
    static let journeyMinimumDay = 14
    static let journeyMinimumDue = 4

    /// At most this many locked frames sit in the rail. Two reads as "there
    /// is more here"; six reads as "you have nothing".
    static let maximumLockedInRail = 2

    /// Frames whose unlock condition is not something to encourage. Never
    /// shown as locked, anywhere.
    static let neverLocked: Set<ShareFrame> = [.comeback]

    static func frames(for context: ShareContext) -> [ShareFrame] {
        var offered: Set<ShareFrame> = []
        let hasPhoto = context.hasPhoto
        let hasMomentum = context.streak.weeks >= 1

        if hasPhoto { offered.insert(.clean) }

        switch context.outcome?.kind {
        case .showedUp:
            offered.insert(.showedUp)
            if context.receipt != nil { offered.insert(.receipt) }
            if hasMomentum { offered.insert(.momentum) }
            if context.comeback != nil { offered.insert(.comeback) }
            if context.milestone != nil { offered.insert(.milestone) }
            if hasPhoto, isJourneyEligible(context) { offered.insert(.journey) }

        case .homeWorkout:
            offered.insert(.quickSave)
            if hasMomentum { offered.insert(.momentum) }
            if context.comeback != nil { offered.insert(.comeback) }

        default:
            // No session that day: a first photo, an imported old one, or a
            // rest day. Only the frames that are about the photo or about
            // the user's standing, never about a morning that did not happen.
            if hasPhoto, isJourneyEligible(context) { offered.insert(.journey) }
            if hasMomentum { offered.insert(.momentum) }
        }

        var ordered = ShareFrame.allCases.filter { offered.contains($0) }

        for frame in dropOrder where ordered.count > maximumFrames {
            ordered.removeAll { $0 == frame }
        }

        return ordered
    }

    static func isJourneyEligible(_ context: ShareContext) -> Bool {
        guard let journey = context.journey else { return false }
        return journey.dayNumber >= journeyMinimumDay && journey.due >= journeyMinimumDue
    }

    // MARK: Locked / not today

    /// Every frame, in `allCases` order, with where it stands for this share.
    static func availability(for context: ShareContext) -> [(frame: ShareFrame, state: FrameAvailability)] {
        let offered = Set(frames(for: context))
        return ShareFrame.allCases.map { frame in
            if offered.contains(frame) { return (frame, .available) }
            if let lock = lock(for: frame, context: context) { return (frame, .locked(lock)) }
            return (frame, .notToday)
        }
    }

    /// The locked frames to show in the rail: nearest to unlocking first,
    /// capped.
    static func lockedForRail(_ availability: [(frame: ShareFrame, state: FrameAvailability)]) -> [(frame: ShareFrame, lock: FrameLock)] {
        Array(lockedFrames(availability).prefix(maximumLockedInRail))
    }

    /// All locked frames, nearest to unlocking first.
    static func lockedFrames(_ availability: [(frame: ShareFrame, state: FrameAvailability)]) -> [(frame: ShareFrame, lock: FrameLock)] {
        availability
            .compactMap { entry -> (frame: ShareFrame, lock: FrameLock)? in
                guard let lock = entry.state.lock else { return nil }
                return (entry.frame, lock)
            }
            .sorted { $0.lock.closeness > $1.lock.closeness }
    }

    /// The lock on a frame that is not offered, or nil when the frame has
    /// been earned before and simply does not apply to this day.
    static func lock(for frame: ShareFrame, context: ShareContext) -> FrameLock? {
        guard !neverLocked.contains(frame) else { return nil }
        let history = context.history

        switch frame {
        case .clean, .comeback:
            return nil

        case .showedUp:
            guard !history.hasVerifiedVisit else { return nil }
            return FrameLock(
                requirement: "unlocks the first morning GymLock verifies you at the gym",
                progress: nil,
                closeness: 0
            )

        case .receipt:
            guard !history.hasReceipt else { return nil }
            return FrameLock(
                requirement: "unlocks when one morning records your alarm, leaving and arrival",
                progress: nil,
                closeness: history.hasVerifiedVisit ? 0.5 : 0
            )

        case .momentum:
            guard context.streak.weeks == 0, !history.hasKeptWeek else { return nil }
            let goal = max(context.streak.weeklyGoal, 1)
            let done = min(context.streak.thisWeekSessionDays, goal)
            return FrameLock(
                requirement: "unlocks when you keep your first week",
                progress: "\(done) of \(goal) this week",
                closeness: Double(done) / Double(goal)
            )

        case .journey:
            return journeyLock(context)

        case .milestone:
            guard history.verifiedVisitsEver == 0, !history.hasKeptWeek else { return nil }
            return milestoneLock(verifiedVisits: history.verifiedVisitsEver)

        case .quickSave:
            guard !history.hasHomeWorkout else { return nil }
            return FrameLock(
                requirement: "appears when a quick 20 saves your day",
                progress: nil,
                closeness: 0
            )
        }
    }

    /// Day 14 first, then four due sessions. Once both are met the frame is
    /// earned, and its absence on a photo-less share is not a lock.
    private static func journeyLock(_ context: ShareContext) -> FrameLock? {
        let dayNumber = context.journey?.dayNumber ?? 1
        let due = context.journey?.due ?? 0
        if dayNumber < journeyMinimumDay {
            return FrameLock(
                requirement: "unlocks on day \(journeyMinimumDay)",
                progress: "day \(max(dayNumber, 1)) of \(journeyMinimumDay)",
                closeness: Double(max(dayNumber, 1)) / Double(journeyMinimumDay)
            )
        }
        if due < journeyMinimumDue {
            return FrameLock(
                requirement: "unlocks after \(journeyMinimumDue) planned sessions",
                progress: "\(due) of \(journeyMinimumDue)",
                closeness: Double(due) / Double(journeyMinimumDue)
            )
        }
        return nil
    }

    /// Names the *next* uncrossed visit threshold, whatever it is.
    static func milestoneLock(verifiedVisits: Int) -> FrameLock {
        let next = Milestone.visitThresholds.first { $0 > verifiedVisits } ?? Milestone.visitThresholds.last ?? 1
        let requirement = next == 1
            ? "unlocks at your first verified visit"
            : "unlocks at \(next) verified visits"
        return FrameLock(
            requirement: requirement,
            progress: "\(verifiedVisits) of \(next)",
            closeness: Double(verifiedVisits) / Double(next)
        )
    }
}
