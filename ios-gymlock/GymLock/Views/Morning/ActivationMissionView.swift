import SwiftUI

/// The mission screen: one tiny physical action between "I'm going" and the countdown.
///
/// The mission is not exercise and it is not a test. It is a way of getting the body out of the
/// position it was arguing from, which is why every mission takes under a minute.
///
/// **One mission, and the swap is earned.** The user is given a single mission and sees no
/// alternatives. "Try a different one" appears only after that mission has failed twice (counted in
/// `MissionAttemptLedger`, per session and mission, so a relaunch keeps it), or at once when the
/// mission cannot run at all on this phone (permission denied, no camera, motion or speech
/// unsupported). "Skip and start my window" stays as quiet text: someone who already said yes must
/// never be trapped here.
///
/// The page is laid out in a 390 x 844 design scaled by `MissionLayout`, so it looks the same on
/// every iPhone and iPad, in the user's hero card style (Matrix dots or the Ridge world).
struct ActivationMissionView: View {
    let session: GymSession
    let onComplete: () -> Void
    let onChoose: (ActivationMissionType) -> Void
    let onReroll: (Set<MissionCapability>) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @Environment(AppStore.self) private var store

    @AppStorage(HeroCardStyle.storageKey) private var cardStyleRaw = HeroCardStyle.default.rawValue

    @State private var camera = MissionCameraModel()
    @State private var motion = MotionMissionMonitor()
    @State private var speech = SpeechMissionVerifier()
    @State private var isRunning = false
    @State private var isSwapOpen = false
    /// Set when a swap was picked from this page's sheet, so the runner opens once the sheet is gone.
    @State private var startsAfterSwap = false
    /// Bumped when the runner closes, so the earned-swap state is read again from the ledger.
    @State private var attemptRevision = 0

    /// What this device can honestly verify right now.
    private var capabilities: Set<MissionCapability> {
        var set: Set<MissionCapability> = []
        if camera.canVerify { set.insert(.camera) }
        if motion.canVerify { set.insert(.motion) }
        if speech.canVerify { set.insert(.speech) }
        // Never empty: the walk-to-door fallback needs only the pedometer, and
        // an empty pool would leave the user staring at nothing.
        if set.isEmpty { set.insert(.motion) }
        return set
    }

    private var mission: ActivationMissionType {
        session.mission ?? .universalFallback
    }

    private var style: MissionStyle {
        MissionStyle(HeroCardStyle(rawValue: cardStyleRaw) ?? .default)
    }

    /// The missions the user could swap to: everything verifiable except the current one.
    private var swapChoices: [ActivationMissionType] {
        ActivationMissionType.candidates(
            available: capabilities,
            excluding: mission,
            allowingOwnershipMissions: store.usesGymBag
        )
        .filter { $0 != mission }
    }

    /// The same pool without excluding anything, handed to the runner (which filters its own
    /// active mission, so a swapped-away mission can still be offered back).
    private var swapPool: [ActivationMissionType] {
        ActivationMissionType.candidates(
            available: capabilities,
            excluding: nil,
            allowingOwnershipMissions: store.usesGymBag
        )
    }

    /// The assigned mission cannot run at all here, so the swap is offered at once.
    private var cannotRunHere: Bool {
        switch mission.capability {
        case .camera:
            return isCameraBlocked
        case .motion:
            return motion.availability == .denied || motion.availability == .unsupported
        case .speech:
            return speech.availability == .denied || speech.availability == .unsupported
        }
    }

    private var isCameraBlocked: Bool {
        switch camera.availability {
        case .permissionDenied, .noCameraFound, .failed: true
        case .preparing, .ready: false
        }
    }

    private var isSwapEarned: Bool {
        _ = attemptRevision
        return MissionAttemptLedger.isSwapEarned(sessionID: session.id, mission: mission)
    }

    /// "Try a different one": earned, or the mission cannot run, and there is somewhere to go.
    private var offersSwap: Bool {
        guard isSwapEarned || cannotRunHere else { return false }
        return !swapChoices.isEmpty || mission != .universalFallback
    }

    /// "7:05", from the session's arrival target (or its deadline). Nil leaves the step out.
    private var gymTimeText: String? {
        guard let date = session.arrivalTarget ?? session.deadline else { return nil }
        return date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute())
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            GeometryReader { proxy in
                page(MissionMetrics(proxy))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .task {
            camera.refreshAvailability()
            motion.refreshAvailability()
            await speech.refreshAvailability()
        }
        // The "I'm up" wake page: once per session, over this screen's first frame.
        // Its mission capsule spins through the missions this device can verify, lands on one,
        // and starts it exactly as the card's "start" does (choosing it first if it changed).
        .overlay {
            WakeIntroPresenter(
                session: session,
                route: .mission,
                missionChoices: ActivationMissionType.candidates(
                    available: capabilities,
                    excluding: nil,
                    allowingOwnershipMissions: store.usesGymBag
                )
            ) { landed in
                if let landed, landed != mission { onChoose(landed) }
                isRunning = true
            }
        }
        .fullScreenCover(isPresented: $isRunning, onDismiss: { attemptRevision += 1 }) {
            MissionRunnerView(
                mission: mission,
                phrase: session.mirrorPhrase,
                camera: camera,
                motion: motion,
                speech: speech,
                sessionID: session.id,
                swapChoices: swapPool,
                onVerified: {
                    isRunning = false
                    onComplete()
                },
                onAnotherMission: { picked in
                    // The runner has already started it; this records the choice.
                    onChoose(picked)
                },
                onDismiss: { isRunning = false }
            )
        }
        .sheet(
            isPresented: $isSwapOpen,
            onDismiss: {
                if startsAfterSwap {
                    startsAfterSwap = false
                    isRunning = true
                }
            }
        ) {
            MissionSwapSheet(
                missions: swapChoices,
                style: style,
                onPick: { picked in
                    startsAfterSwap = true
                    isSwapOpen = false
                    onChoose(picked)
                },
                onSkip: {
                    isSwapOpen = false
                    onSkip()
                }
            )
        }
    }

    // MARK: - Page

    private func page(_ m: MissionMetrics) -> some View {
        let height = m.size.height
        // The actions stack: Start (64 design points), then 56 pt quiet buttons (never below 56 pt on
        // screen, so `tapSize`), 8 design points between each, plus the optional notice (16 + 8,
        // and the 8 before Start).
        let quietCount: CGFloat = offersSwap ? 2 : 1
        let noticeHeight: CGFloat = cannotRunHere ? m(32) : 0
        let actionsHeight = m(64) + quietCount * (m.tapSize + m(8)) + noticeHeight
        // Top row, top and bottom padding, and 24 design points of air between the three blocks.
        let reserved = m.tapSize + m(8) + actionsHeight + m(12) + m(24)
        let heroHeight = max(m(280), min(height * 0.62, height - reserved))

        return VStack(spacing: 0) {
            topRow(m)

            Spacer(minLength: 0)

            MissionHeroCard(metrics: m, mission: mission, style: style)
                .frame(height: heroHeight)

            Spacer(minLength: 0)

            actions(m)
        }
        .padding(.top, m(8))
        .padding(.horizontal, m(18))
        .padding(.bottom, m(12))
        .frame(width: m.columnWidth, height: height)
        .frame(width: m.size.width, height: height)
    }

    private func topRow(_ m: MissionMetrics) -> some View {
        HStack(spacing: m(16)) {
            Button {
                MissionHaptic.selection.play()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: m(17)))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(minWidth: m.tapSize, minHeight: m.tapSize, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // On the narrowest phones the last step ("Gym 7:05") drops out rather than collide with Cancel.
            ViewThatFits(in: .horizontal) {
                MissionProgressRow(metrics: m, gymTime: gymTimeText, usesCoral: style == .matrix)
                MissionProgressRow(metrics: m, gymTime: nil, usesCoral: style == .matrix)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: m.tapSize)
    }

    private func actions(_ m: MissionMetrics) -> some View {
        VStack(spacing: m(8)) {
            if cannotRunHere {
                Text("This one can't run on your phone right now.")
                    .font(.system(size: m(13)))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .frame(height: m(16))
                    .padding(.bottom, m(8))
            }

            MissionStartButton(
                metrics: m,
                figure: MissionFigure(mission),
                style: style,
                seconds: mission.estimatedSeconds
            ) {
                isRunning = true
            }

            if offersSwap {
                MissionQuietButton(
                    metrics: m,
                    title: "Try a different one",
                    isEmphasised: true,
                    tint: Theme.ink
                ) {
                    swapOrReroll()
                }
            }

            // Always present. An accessibility need, a dead sensor, or simply a bad morning must
            // not be able to strand someone who already said yes.
            MissionQuietButton(metrics: m, title: "Skip and start my window") {
                onSkip()
            }
        }
    }

    /// Opens the swap sheet. With nothing else to offer, the coordinator's reroll falls back to the
    /// walk to the door, which needs only the pedometer.
    private func swapOrReroll() {
        if swapChoices.isEmpty {
            onReroll(capabilities)
        } else {
            isSwapOpen = true
        }
    }
}
