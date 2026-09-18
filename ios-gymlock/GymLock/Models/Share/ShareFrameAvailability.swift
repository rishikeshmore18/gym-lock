import Foundation

/// Which frames a context can honestly support.
///
/// A frame appears only when every field it renders is present. There are no
/// placeholders and no "Week 1" variants invented for users who have not
/// earned the real thing — a first-week user gets Showed Up, and Momentum
/// arrives when there is momentum to show.
enum ShareFrameAvailability {
    static let maximumFrames = 6

    /// When more than six qualify, these go first, in this order. The frames
    /// not listed here are never dropped.
    static let dropOrder: [ShareFrame] = [.journey, .milestone, .comeback]

    /// Journey needs enough history to be a journey.
    static let journeyMinimumDay = 14
    static let journeyMinimumDue = 4

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
}
