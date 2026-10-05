import SwiftUI

/// The Progress spotlight's presentation state (FLOW, Flow 3, "The Progress
/// spotlight").
///
/// Presentation only, and no geometry at all: the screen dims each of its own
/// sections in place and leaves the Progress Photos card undimmed once it has
/// landed, so nothing here needs to know where anything is on screen.
///
/// The business handoff is the coordinator's `pendingSpotlightDay`, which
/// survives a cold launch in defaults; this takes it exactly once, when the
/// tab shell switches to Progress for that tap, so opening Progress by hand
/// never shows it and nothing replays it.
///
/// Owned by the tab shell rather than the Progress tab so it is armed in the
/// same update that selects Progress: the first frame of Progress anyone sees
/// is already dimmed.
@Observable
final class ProgressSpotlightModel {
    enum Phase: Equatable {
        case inactive
        /// Everything dimmed, the photos card included, while the page
        /// travels to the card.
        case scrolling
        /// The photos card is undimmed and live; everything else stays dim.
        case focused
    }

    /// The scroll anchor on the real Progress Photos card.
    static let cardID = "progressPhotos"

    /// The page's travel to the card.
    static let travelAnimation: Animation = .timingCurve(0.2, 0.85, 0.2, 1, duration: 0.3)
    /// How long the travel takes, so the landing waits for it.
    static let travelDuration: Duration = .milliseconds(300)
    /// The photos card brightening as it lands.
    static let revealAnimation: Animation = .easeOut(duration: 0.2)
    /// Every dimmed surface and the line fading back to normal together.
    static let dismissAnimation: Animation = .easeOut(duration: 0.17)

    private(set) var day: Date?
    private(set) var phase: Phase = .inactive
    /// Bumped by every accepted tap, so a second notification travels again.
    private(set) var requestCount = 0
    /// How many times a request has landed. One per request at most.
    @ObservationIgnored private(set) var focusCount = 0

    @ObservationIgnored private var hasStartedTravel = false
    @ObservationIgnored private var focusTask: Task<Void, Never>?

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
        focusTask?.cancel()
        focusTask = nil
        self.day = day
        hasStartedTravel = false
        phase = .scrolling
        requestCount += 1
    }

    /// Claims this request's single travel and schedules its landing for
    /// when the travel ends. False if it has already started or nothing is
    /// travelling, so neither the scroll nor its haptic can run twice.
    @discardableResult
    func startTravel(animated: Bool) -> Bool {
        guard phase == .scrolling, !hasStartedTravel else { return false }
        hasStartedTravel = true
        let request = requestCount
        let delay: Duration = animated ? Self.travelDuration : .zero
        focusTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            self?.focus(request: request)
        }
        return true
    }

    /// Ends the spotlight at once. Cancels a pending landing, so a tap during
    /// the travel can never be followed by the line or the landing haptic.
    func dismiss() {
        focusTask?.cancel()
        focusTask = nil
        day = nil
        phase = .inactive
    }

    /// Lands only the request that scheduled it, and only if nothing has
    /// dismissed or replaced it since.
    private func focus(request: Int) {
        guard phase == .scrolling, request == requestCount else { return }
        focusTask = nil
        focusCount += 1
        withAnimation(Self.revealAnimation) { phase = .focused }
    }
}
