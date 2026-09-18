import Foundation

/// Third-party integration switches.
///
/// The Instagram Stories quick action is built and wired, but it needs a Meta
/// app ID to open Instagram's share sheet, and there is none yet. Until one is
/// set here the button is not drawn — a control that opens nothing is worse
/// than no control.
enum ShareConfiguration {
    /// The Meta app ID passed as `source_application`. `nil` hides the
    /// Instagram Stories button entirely.
    static let metaAppID: String? = nil

    static var isInstagramStoriesConfigured: Bool { metaAppID != nil }
}
