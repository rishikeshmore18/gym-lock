import Foundation

/// The Hall of Fame's haptic cues, one call per event.
///
/// Every cue is named for the moment it marks rather than the feel it has, so
/// the screen reads as a list of events and the strengths live in one place.
/// Each is fired once per event, never per animation frame, and never during a
/// drag except `pinchLimit`, which is the one cue that belongs to a live finger.
enum HallOfFameHaptics {
    /// Pre-warms the generators when the screen appears, so the first tick on
    /// a level change is not late.
    static func prepare() {
        Haptics.prepareSelection()
        Haptics.preparePress()
    }

    /// Tap on the card that opens the screen.
    static func open() {
        Haptics.tap()
    }

    /// The reel settling at the centre after its roll-in. Half strength: it is
    /// the first beat of a longer sequence, not the headline.
    static func reelLands() {
        Haptics.tap(intensity: 0.5)
    }

    /// The last letter of the title landing.
    static func titleComplete() {
        Haptics.soft()
    }

    /// One full turn of the reel rolling toward the camera. The caller caps
    /// these at three per intro; at this strength they read as a ratchet.
    static func reelRevolution() {
        Haptics.tap(intensity: 0.3)
    }

    /// The film landing flat as the live scroll, the end of the intro.
    static func stripSeated() {
        Haptics.boundary()
    }

    /// A level committed, from a pinch release or from the capsule.
    static func levelChanged() {
        Haptics.selection()
    }

    /// The first push past the rubber-band limit, once per pinch rather than
    /// continuously while the finger stays there.
    static func pinchLimit() {
        Haptics.boundary()
    }

    /// Photo level snapping to a different photo.
    static func pageChanged() {
        Haptics.selection()
    }

    /// Tapping a frame to open it at Photo level.
    static func openPhoto() {
        Haptics.tap()
    }

    /// The "Where it started" end scrolling into view, once per visit. Soft,
    /// because arriving at the beginning is a quiet moment.
    static func reachedStart() {
        Haptics.soft()
    }

    /// Close pressed. Slightly under full strength: the screen is about to
    /// play its own exit and the tap should not compete with it.
    static func close() {
        Haptics.tap(intensity: 0.7)
    }
}
