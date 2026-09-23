import Foundation

/// Which screen the user wants to wake up to when the alarm rings.
///
/// Two, and only two. The choice is stored on `MorningPlan` so the Alarm
/// screen, the picker and (later) the ringing screen all read one value.
/// Nothing reads this at ring time yet: the real screens come in a later pass.
enum AlarmScreenStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    /// Light at the top, dawn through the middle, dark underneath.
    case sunrise
    /// Near-black and cinematic.
    case focus

    var id: String { rawValue }

    /// Lowercase, as every value on the Alarm screen is.
    var label: String {
        switch self {
        case .sunrise: "sunrise"
        case .focus: "focus"
        }
    }

    /// The two words under each preview in the picker.
    var mood: String {
        switch self {
        case .sunrise: "calm · uplifting"
        case .focus: "bold · focused"
        }
    }

    /// What VoiceOver reads for a preview. The middle dot is read badly, so
    /// this spells it out.
    var accessibilityDescription: String {
        switch self {
        case .sunrise: "sunrise alarm screen, calm and uplifting"
        case .focus: "focus alarm screen, bold and focused"
        }
    }
}

/// The picker's working copy of the choice, so browsing can be undone.
///
/// The picker changes this, never the plan. Going back throws it away.
/// Only `commit(to:)` writes to a plan, and that is only called from Done.
/// Kept as a plain value so both halves are testable without a view.
struct AlarmScreenDraft: Equatable {
    /// What was saved when the picker opened.
    let stored: AlarmScreenStyle
    /// What the user is looking at now.
    private(set) var selection: AlarmScreenStyle

    init(stored: AlarmScreenStyle) {
        self.stored = stored
        self.selection = stored
    }

    var hasChanges: Bool { selection != stored }

    /// Returns true only when the selection actually changed, which is the
    /// one moment a selection haptic belongs to.
    @discardableResult
    mutating func select(_ style: AlarmScreenStyle) -> Bool {
        guard style != selection else { return false }
        selection = style
        return true
    }

    /// Writes the selection into `plan`. Returns false when the plan already
    /// had it, so the caller can skip a pointless save.
    @discardableResult
    func commit(to plan: inout MorningPlan) -> Bool {
        guard plan.alarmScreenStyle != selection else { return false }
        plan.alarmScreenStyle = selection
        return true
    }
}
