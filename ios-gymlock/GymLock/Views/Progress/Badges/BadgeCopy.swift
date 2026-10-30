import Foundation

/// Every string the badges screens show or speak, in one place. Only words:
/// the numbers come from `BadgeState`.
enum BadgeCopy {
    /// The short progress line on a locked card, e.g. "63 / 100 DAYS".
    /// Nil when there is nothing yet to show, so the card keeps its rule.
    static func cardProgress(_ progress: BadgeProgress?) -> String? {
        guard let progress, progress.current > 0 else { return nil }
        switch progress.unit {
        case .weeksInARow, .cleanWeeks: return "\(progress.current) / \(progress.target) WEEKS"
        case .workoutDays: return "\(progress.current) / \(progress.target) DAYS"
        case .gymWorkouts: return "\(progress.current) / \(progress.target)"
        }
    }

    /// What earns it, as a sentence.
    static func requirement(_ badge: BadgeDefinition) -> String {
        switch badge.group {
        case .streak:
            let weeks = badge.number ?? 0
            return weeks == 1 ? "Keep your first week." : "Keep \(weeks) weeks in a row."
        case .days:
            return "Work out on \(badge.number ?? 0) different days."
        case .achievement:
            return badge.rule
        }
    }

    /// Spoken requirement for VoiceOver, e.g. "Four week streak milestone".
    static func spokenMilestone(_ badge: BadgeDefinition) -> String {
        let number = badge.number.map { spelled($0) } ?? ""
        switch badge.group {
        case .streak: return "\(number) week streak milestone"
        case .days: return "\(number) workout days milestone"
        case .achievement: return badge.rule.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
    }

    static func spokenProgress(_ progress: BadgeProgress) -> String {
        let pair = "\(progress.current) of \(progress.target)"
        switch progress.unit {
        case .weeksInARow: return "\(pair) weeks in a row"
        case .workoutDays: return "\(pair) workout days"
        case .gymWorkouts: return "\(pair) verified gym workouts"
        case .cleanWeeks: return "\(pair) weeks without a freeze"
        }
    }

    /// "Locked In badge. Four week streak milestone. Earned."
    /// "Century badge. 63 of 100 workout days. Locked."
    static func accessibilityLabel(_ badge: BadgeDefinition, state: BadgeState) -> String {
        switch state {
        case .earned:
            return "\(badge.name) badge. \(spokenMilestone(badge)). Earned."
        case let .locked(progress):
            let detail = progress.flatMap { $0.current > 0 ? spokenProgress($0) : nil } ?? spokenMilestone(badge)
            return "\(badge.name) badge. \(detail). Locked."
        }
    }

    // MARK: Detail sheet

    static func tierName(_ tier: BadgeTier) -> String { tier.rawValue }

    static func earnedLine(_ date: Date?) -> String {
        guard let date else { return "earned" }
        return "earned \(date.formatted(.dateTime.day().month(.abbreviated).year()).lowercased())"
    }

    static func progressLine(_ progress: BadgeProgress) -> String {
        let pair = "\(progress.current) of \(progress.target)"
        switch progress.unit {
        case .weeksInARow: return "\(pair) weeks in a row"
        case .workoutDays: return "\(pair) workout days"
        case .gymWorkouts: return "\(pair) verified gym workouts"
        case .cleanWeeks: return "\(pair) clean weeks"
        }
    }

    static func remainingLine(_ progress: BadgeProgress) -> String {
        let left = progress.remaining
        switch progress.unit {
        case .weeksInARow, .cleanWeeks: return left == 1 ? "one more kept week." : "\(left) more kept weeks."
        case .workoutDays: return left == 1 ? "one more workout day." : "\(left) more workout days."
        case .gymWorkouts: return left == 1 ? "one more gym workout." : "\(left) more gym workouts."
        }
    }

    static let firstTimeLine = "unlocks the first time it happens."

    private static func spelled(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        let word = formatter.string(from: NSNumber(value: number)) ?? "\(number)"
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
