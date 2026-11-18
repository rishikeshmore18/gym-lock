//
//  WakeIntroPresenter.swift
//  GymLock · the "I'm up" wake page
//
//  Puts the wake page over the first frame of the screen "I'm up" leads to, once per session:
//
//    - missions on:  over ActivationMissionView (route .mission). The mission capsule starts the
//                    mission exactly as the mission card's "start" does (its `isRunning = true`).
//    - missions off: over GymWindowView (route .countdown). The capsule ("Shoes on") hands over to
//                    the countdown underneath.
//
//  When it plays (all must hold):
//    - the session ran in Wake & Go (`resolvedFlowMode == .wakeAndGo`): never on Go Later days
//    - the user committed less than 5 minutes ago (`committedAt`), and has not left yet
//    - it is not the "pick a day" skip offer (`isMakeUpOffer`)
//    - this session has not played it before (`gymlock.morning.wakeIntroPlayedSession`)
//
//  It never shows a second "I'm up": the commitment already happened in AlarmFiredView, and nothing
//  here calls `commitToGoing()`. It is marked as played the moment it appears, so a kill or a
//  relaunch mid-intro never replays it; the mission or countdown screen is simply there.
//
//  "Plans changed" opens the existing PlansChangedView in a sheet with the same doors the router
//  wires for it: a quick workout (`offerQuickWorkout()`) or can't today (`beginCantToday()`).
//  "still going" closes the sheet: the window is not over, so no grace period is spent.
//
//  Depends on: Core/ (WakeIntroView, WakeFactsProvider), AppStore, GymSessionCoordinator,
//  GymSession, MorningRoute, PlansChangedView, SessionVoice, Theme, `blocksHeroHaptics`.
//

import SwiftUI

// MARK: - Once per session

@MainActor
enum WakeIntroLedger {
    /// The id of the last session that played the wake page (gymlock.<area>.<name>).
    static let playedSessionKey = "gymlock.morning.wakeIntroPlayedSession"
    /// How long after "I'm up" the page may still start. Past this the user is mid-morning and
    /// a relaunch must land on the screen they were on, not on "Good morning".
    static let freshness: TimeInterval = 5 * 60

    static func hasPlayed(_ sessionID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: playedSessionKey) == sessionID.uuidString
    }

    static func markPlayed(_ sessionID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(sessionID.uuidString, forKey: playedSessionKey)
    }

    /// Whether the page should play now for this session on this screen.
    static func isEligible(_ session: GymSession, route: MorningRoute, now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard route == .mission || route == .countdown else { return false }
        // Go Later's alarm is "time to go"; the morning was a plain wake alarm (FLOW, Flow 2).
        guard session.resolvedFlowMode == .wakeAndGo else { return false }
        guard session.isMakeUpOffer != true else { return false }
        guard session.departedAt == nil else { return false }
        guard let committed = session.committedAt else { return false }
        let age = now.timeIntervalSince(committed)
        guard age >= -5, age < freshness else { return false }
        return !hasPlayed(session.id, defaults: defaults)
    }
}

// MARK: - The presenter

/// Drop in as `.overlay { WakeIntroPresenter(session: session, route: .mission) { … } }` on the
/// mission and countdown screens (see INTEGRATION.md). Draws nothing when the page should not play.
struct WakeIntroPresenter: View {
    private let session: GymSession
    private let route: MorningRoute
    private let missionChoices: [ActivationMissionType]
    private let onPrimary: (ActivationMissionType?) -> Void

    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the page is playing, captured once when it first appears.
    @State private var claimed: Snapshot?
    @State private var dismissedSessionID: UUID?
    @State private var isShowingPlansChanged = false
    /// The mission the capsule's reel landed on, if it spun.
    @State private var landedMission: ActivationMissionType?

    /// - Parameters:
    ///   - session: the live session (the screen's own `session`).
    ///   - route: the screen this sits on, `.mission` or `.countdown`.
    ///   - onPrimary: what the mission capsule does after the page closes. On the mission screen,
    ///     start the mission (`isRunning = true`); on the countdown, nothing (the countdown is there).
    ///     It receives the mission the reel landed on (nil when there was no reel).
    ///   - missionChoices: the missions the capsule spins through (two or more make it a reel).
    init(
        session: GymSession,
        route: MorningRoute,
        missionChoices: [ActivationMissionType] = [],
        onPrimary: @escaping (ActivationMissionType?) -> Void = { _ in }
    ) {
        self.session = session
        self.route = route
        self.missionChoices = missionChoices
        self.onPrimary = onPrimary
    }

    private struct Snapshot {
        let sessionID: UUID
        let concept: WakeConcept
        let facts: WakeFacts
        let showsLockLine: Bool
    }

    var body: some View {
        if let snapshot = visibleSnapshot {
            WakeIntroView(
                concept: snapshot.concept,
                facts: snapshot.facts,
                showsLockLine: snapshot.showsLockLine,
                isPaused: isShowingPlansChanged,
                missionReel: missionChoices.map(WakeFactsProvider.reelItem(for:)),
                onReelLanded: { id in landedMission = ActivationMissionType(rawValue: id) },
                onPrimary: { close(then: { onPrimary(landedMission) }) },
                onPlansChanged: { isShowingPlansChanged = true }
            )
            .transition(.opacity)
            // The screen underneath stays out of VoiceOver's reach while the page covers it.
            .accessibilityAddTraits(.isModal)
            // The Home hero card under the morning cover stays silent while this plays.
            .blocksHeroHaptics("wake")
            .onAppear { claim(snapshot) }
            .sheet(isPresented: $isShowingPlansChanged) {
                PlansChangedView(
                    voice: SessionVoice(session: session),
                    onStillGoing: { isShowingPlansChanged = false },
                    onQuickWorkout: {
                        isShowingPlansChanged = false
                        coordinator.offerQuickWorkout()
                    },
                    onCantToday: {
                        isShowingPlansChanged = false
                        coordinator.beginCantToday()
                    },
                    showsGraceNote: false
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: Private

    /// The snapshot to show: the claimed one for this session, or a fresh one if it may play.
    private var visibleSnapshot: Snapshot? {
        guard dismissedSessionID != session.id else { return nil }
        if let claimed, claimed.sessionID == session.id { return claimed }
        guard WakeIntroLedger.isEligible(session, route: route) else { return nil }
        return makeSnapshot()
    }

    private func makeSnapshot() -> Snapshot {
        let facts = WakeFactsProvider.facts(store: store, coordinator: coordinator, session: session)
        return Snapshot(
            sessionID: session.id,
            concept: WakeFactsProvider.concept(for: facts),
            facts: facts,
            // "Apps open at …" only when there is something locked (RESEARCH §4.1).
            showsLockLine: coordinator.shield.hasSelection
        )
    }

    /// Marks the session as played the moment the page is on screen.
    private func claim(_ snapshot: Snapshot) {
        guard claimed?.sessionID != snapshot.sessionID else { return }
        claimed = snapshot
        WakeIntroLedger.markPlayed(snapshot.sessionID)
    }

    /// Fades the page away onto the screen underneath, then runs that screen's action.
    private func close(then action: @escaping () -> Void) {
        withAnimation(reduceMotion ? Animation.easeOut(duration: 0.2) : Theme.settle) {
            dismissedSessionID = session.id
        }
        action()
    }
}
