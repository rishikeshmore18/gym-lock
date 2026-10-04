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

    private(set) var day: Date?
    private(set) var phase: Phase = .inactive
    /// The real card's frame in global coordinates. Published only while the
    /// spotlight is up, so scrolling the page normally redraws nothing here.
    private(set) var cardFrame: CGRect = .zero
    /// Bumped by every accepted tap, so a second notification scrolls again.
    private(set) var requestCount = 0

    @ObservationIgnored private var latestCardFrame: CGRect = .zero
    @ObservationIgnored private var hasStartedScroll = false
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

    func arm(day: Date) {
        settle?.cancel()
        self.day = day
        hasStartedScroll = false
        cardFrame = latestCardFrame
        phase = .scrolling
        requestCount += 1
    }

    /// The page has been told to travel to the card. Focus waits for the card
    /// to stop moving, and never lands before the travel animation could.
    func scrollStarted(animated: Bool) {
        guard phase == .scrolling else { return }
        hasStartedScroll = true
        earliestFocus = .now + (animated ? .milliseconds(300) : .zero)
        scheduleFocus(after: .milliseconds(60))
    }

    /// Every geometry change of the real card. While travelling, each one
    /// pushes the focus back: the card is in place once it stops moving.
    func cardMoved(to frame: CGRect) {
        latestCardFrame = frame
        guard isActive, frame != cardFrame else { return }
        cardFrame = frame
        guard phase == .scrolling, hasStartedScroll else { return }
        scheduleFocus(after: .milliseconds(90))
    }

    func dismiss() {
        settle?.cancel()
        settle = nil
        hasStartedScroll = false
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
        withAnimation(.easeOut(duration: 0.2)) { phase = .focused }
    }

    // MARK: - Hit regions

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
