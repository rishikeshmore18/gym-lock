import Foundation

/// The compositions a progress photo can be shared as.
///
/// Each is one statement, at most two facts, and the mark. They differ in
/// *which* true thing they say, not in decoration — and a frame whose data is
/// missing is not drawn with blanks, it is simply not offered (see
/// `ShareFrameAvailability`).
nonisolated enum ShareFrame: String, CaseIterable, Hashable, Identifiable, Codable {
    /// The photo and the mark. For people who do not want numbers.
    case clean
    case showedUp
    case momentum
    case receipt
    case journey
    case comeback
    /// The home fallback, named for what it is rather than for the gym.
    case quickSave
    case milestone

    var id: String { rawValue }

    /// The pill label in the editor.
    var title: String {
        switch self {
        case .clean: "Clean"
        case .showedUp: "Showed Up"
        case .momentum: "Momentum"
        case .receipt: "Receipt"
        case .journey: "Journey"
        case .comeback: "Comeback"
        case .quickSave: "The Save"
        case .milestone: "Milestone"
        }
    }

    /// One honest line for the All Frames gallery.
    var description: String {
        switch self {
        case .clean: "just the photo."
        case .showedUp: "the day you turned up."
        case .receipt: "alarm to gym, minute by minute."
        case .momentum: "weeks you kept."
        case .journey: "how far it has been."
        case .milestone: "a number worth saying."
        case .quickSave: "the day a quick 20 saved."
        case .comeback: "back after a miss."
        }
    }

    /// The single word a locked preview is allowed to draw, in the frame's
    /// own statement style. Never a number, never a date.
    var lockedPreviewWord: String {
        switch self {
        case .clean: ""
        case .showedUp: "SHOWED UP."
        case .receipt: "RECEIPT"
        case .momentum: "MOMENTUM"
        case .journey: "JOURNEY"
        case .milestone: "MILESTONE"
        case .quickSave: "THE SAVE"
        case .comeback: "COMEBACK"
        }
    }

    /// The movable pieces this frame is made of, in drawing order.
    var elements: [StoryElementKind] {
        switch self {
        case .clean: [.mark]
        case .journey: [.statement, .facts, .inset, .mark]
        default: [.statement, .facts, .mark]
        }
    }

    /// Whether the statement sits over the photograph and needs the soft
    /// darkening behind the text band. Clean has no text to protect.
    var usesLegibilityBand: Bool { self != .clean }
}
