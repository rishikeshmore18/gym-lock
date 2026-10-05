import SwiftUI

/// The Progress spotlight's presentation state (FLOW, Flow 3, "The Progress
/// spotlight").
///
/// Presentation only. The business handoff is the coordinator's
/// `pendingSpotlightDay`, which survives a cold launch in defaults; this takes
/// it exactly once, when the tab shell switches to Progress for that tap, so
/// opening Progress by hand never shows it and nothing replays it.
///
/// Owned by the tab shell rather than the Progress tab so it is armed in the
/// same update that selects Progress: the first frame of Progress anyone sees
/// is already dimmed.
@Observable
final class ProgressSpotlightModel {
    enum Phase: Equatable {
        case inactive
        /// Dimmed with no hole while the page travels to the card.
        case scrolling
        /// The card is in place, lit and live.
        case focused
    }

    /// The scroll anchor on the real Progress Photos card.
    static let cardID = "progressPhotos"
    /// The one coordinate space the card and the overlay are both measured
    /// in. Declared by the tab shell, which contains both.
    static let coordinateSpaceName = "progressSpotlight"

    /// The page's travel to the card. Focus never lands before it could end.
    static let travelAnimation: Animation = .timingCurve(0.2, 0.85, 0.2, 1, duration: 0.3)
    private static let travelDuration: Duration = .milliseconds(300)
    /// The hole erasing in once the card has landed.
    static let revealAnimation: Animation = .easeOut(duration: 0.2)
    /// Scrim, line and hit areas fading away together.
    static let dismissAnimation: Animation = .easeOut(duration: 0.17)

    private(set) var day: Date?
    private(set) var phase: Phase = .inactive
    /// The real card's frame in the spotlight coordinate space. Published
    /// only while the spotlight is up, so scrolling the page normally redraws
    /// nothing here.
    private(set) var cardFrame: CGRect = .zero
    /// Whether the card has been lit for this request. Kept through the exit
    /// fade, so the hole and the line fade out with the scrim instead of the
    /// card dimming first.
    private(set) var isRevealed = false
    /// Bumped by every accepted tap, so a second notification travels again.
    private(set) var requestCount = 0
    /// How many times a request has landed. One per request at most.
    @ObservationIgnored private(set) var focusCount = 0

    @ObservationIgnored private var latestCardFrame: CGRect = .zero
    @ObservationIgnored private var hasStartedTravel = false
    @ObservationIgnored private var earliestFocus: ContinuousClock.Instant = .now
    @ObservationIgnored private var settle: Task<Void, Never>?

    var isActive: Bool { phase != .inactive }

    /// Takes the coordinator's pending spotlight when a notification asked for
    /// Progress. Any other tab, or no pending day, leaves everything alone.
    @discardableResult
    func accept(requestedTab: RootTab, from coordinator: GymSessionCoordinator) -> Bool {
        guard requestedTab == .progress,
              let day = coordinator.takePendingSpotlightDay()
        else { return false }
        arm(day: day)
        return true
    }

    /// The only place the one-shot guards reset: a new notification.
    func arm(day: Date) {
        settle?.cancel()
        settle = nil
        self.day = day
        hasStartedTravel = false
        isRevealed = false
        cardFrame = latestCardFrame
        phase = .scrolling
        requestCount += 1
    }

    /// Claims this request's single travel. False if it has already started
    /// or the spotlight is not travelling, so neither the scroll nor its
    /// haptic can run twice.
    @discardableResult
    func startTravel(animated: Bool) -> Bool {
        guard phase == .scrolling, !hasStartedTravel else { return false }
        hasStartedTravel = true
        earliestFocus = .now + (animated ? Self.travelDuration : .zero)
        scheduleFocus(after: .milliseconds(60))
        return true
    }

    /// Every geometry change of the real card. While travelling, each one
    /// pushes the focus back: the card is in place once it stops moving.
    func cardMoved(to frame: CGRect) {
        latestCardFrame = frame
        guard isActive, frame != cardFrame else { return }
        cardFrame = frame
        guard phase == .scrolling, hasStartedTravel else { return }
        scheduleFocus(after: .milliseconds(90))
    }

    /// Ends the spotlight at once. Cancels a pending landing, so an early tap
    /// can never be followed by the line or the landing haptic.
    func dismiss() {
        settle?.cancel()
        settle = nil
        day = nil
        phase = .inactive
    }

    private func scheduleFocus(after delay: Duration) {
        let target = max(ContinuousClock.now + delay, earliestFocus)
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(until: target, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.focus()
        }
    }

    private func focus() {
        guard phase == .scrolling else { return }
        settle = nil
        focusCount += 1
        withAnimation(Self.revealAnimation) {
            phase = .focused
            isRevealed = true
        }
    }

    // MARK: - Geometry

    /// The card's rectangle in the overlay's own drawing space.
    ///
    /// Both frames come from the same named coordinate space, so this is a
    /// plain translation by wherever the overlay's canvas starts. A canvas
    /// that runs under the status bar starts above the space's origin, and
    /// the translation moves the hole down by exactly that much.
    static func localHole(cardFrame: CGRect, canvasOrigin: CGPoint) -> CGRect {
        cardFrame.offsetBy(dx: -canvasOrigin.x, dy: -canvasOrigin.y)
    }

    /// The dark area around the card as up to four rectangles: above, below,
    /// left and right. They catch outside taps; the card's own rectangle is
    /// left uncovered so the real card keeps every touch.
    static func outsideRegions(around hole: CGRect, in bounds: CGRect) -> [CGRect] {
        let hole = hole.intersection(bounds)
        guard !hole.isNull, !hole.isEmpty else { return [bounds] }
        return [
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: hole.minY - bounds.minY),
            CGRect(x: bounds.minX, y: hole.maxY, width: bounds.width, height: bounds.maxY - hole.maxY),
            CGRect(x: bounds.minX, y: hole.minY, width: hole.minX - bounds.minX, height: hole.height),
            CGRect(x: hole.maxX, y: hole.minY, width: bounds.maxX - hole.maxX, height: hole.height),
        ]
        .filter { $0.width > 0 && $0.height > 0 }
    }
}
