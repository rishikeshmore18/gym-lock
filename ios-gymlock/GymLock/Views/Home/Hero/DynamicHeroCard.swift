import SwiftUI

/// The Dynamic hero card on Home (02-experience-spec §2, §5, §6).
///
/// Resolves the moment once a minute from the real record, draws it in the chosen style (Ridge by
/// default, Matrix in Profile > Preferences > Card style), and owns the card's side of the done flow:
/// it reports its frame so the flow can collapse into it, holds the pre-verified state until the
/// collapse is 70% home, and replays today's flow when the verified card is tapped.
struct DynamicHeroCard: View {
    let store: AppStore
    let coordinator: GymSessionCoordinator

    @AppStorage(HeroCardStyle.storageKey) private var styleRaw = HeroCardStyle.ridge.rawValue

    private var style: HeroCardStyle { HeroCardStyle(rawValue: styleRaw) ?? .ridge }
    private var queue: CelebrationQueue { .shared }

    var body: some View {
        // The card's size is fixed here, at the outermost layer, the same way the mini cards size
        // themselves: full row width (up to the cap) at the card's proportion. Left to the aspect
        // ratio deep inside the face, the scroll view's open-ended height made it come out narrower
        // than the row below it.
        Color.clear
            .frame(maxWidth: HeroMetrics.maxWidth)
            .aspectRatio(MatrixCardGeometry.aspect, contentMode: .fit)
            .overlay {
                TimelineView(.everyMinute) { tl in
                    let resolved = resolve(tl.date)
                    DynamicHeroFace(
                        state: resolved.state,
                        style: style,
                        isHeldBeforeFlow: resolved.held,
                        canReplay: !resolved.held && Self.verifiedMoments.contains(resolved.state.moment) && queue.canReplay(now: tl.date),
                        onReplay: { queue.replay(store: store, coordinator: coordinator, style: style) }
                    )
                }
            }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            queue.cardFrame = frame
        }
    }

    static let verifiedMoments: Set<MatrixMoment> = [.verified, .halfway, .automatic]

    /// While today's flow is waiting, or running and not yet 70% home, the card keeps showing the
    /// moment before the proof, so the flow is what reveals verified (spec §3.5).
    private func resolve(_ now: Date) -> (state: HeroMomentState, held: Bool) {
        let start = CFAbsoluteTimeGetCurrent()
        let state = HeroMomentResolver.resolve(store: store, coordinator: coordinator, now: now)
        HeroTrace.log("hero.resolve moment=\(state.moment.rawValue) style=\(style) ms=\(HeroTrace.ms(since: start))")
        guard Self.verifiedMoments.contains(state.moment) else { return (state, false) }
        let running = queue.presentation.map { !$0.isReplay && queue.landedSessionID != $0.sessionID } ?? false
        guard queue.hasPendingFlow || running else { return (state, false) }
        let cal = HeroMomentResolver.displayCalendar()
        let facts = HeroMomentResolver.gather(store: store, coordinator: coordinator, now: now, cal: cal, rotation: .shared)
        let held = HeroMomentResolver.assemble(.atgym, f: facts, theme: state.theme, missedToday: false, cal: cal)
        return (held, true)
    }
}

/// The drawn card plus its play-once haptic gate (spec §6.2): scene haptics play once per state per
/// display day, only while the card is visible, the app is active and nothing covers it.
private struct DynamicHeroFace: View {
    let state: HeroMomentState
    let style: HeroCardStyle
    let isHeldBeforeFlow: Bool
    let canReplay: Bool
    let onReplay: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.heroMotionPaused) private var motionPaused
    @State private var allowed = false
    @State private var visible = true
    @State private var revoke: Task<Void, Never>?

    private var queue: CelebrationQueue { .shared }
    private var rotation: HeroRotationStore { .shared }
    private var entry: String { state.hapticsEntry(style: style) }

    private var hapticsEnabled: Bool {
        allowed
            && scenePhase == .active
            && !motionPaused
            && !isHeldBeforeFlow
            && !queue.holdsHomeHaptics
            && !(DynamicHeroCard.verifiedMoments.contains(state.moment) && queue.flowRan(dayKey: state.dayKey))
    }

    /// Anything that could open the gate.
    private var gateKey: String {
        "\(entry)|\(visible)|\(scenePhase == .active)|\(motionPaused)|\(queue.holdsHomeHaptics)|\(isHeldBeforeFlow)"
    }

    var body: some View {
        ZStack {
            card
                .id(style)
                // the old style fades out in 150 ms while the new one plays its 600 ms entrance
                .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.15))))
        }
        .animation(.easeOut(duration: 0.15), value: style)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
        .contentShape(.rect(cornerRadius: 24))
        .onTapGesture {
            guard canReplay else { return }
            Haptics.selection()
            onReplay()
        }
        .onScrollVisibilityChange(threshold: 0.5) { visible = $0 }
        .onChange(of: gateKey, initial: true) { _, _ in openGateIfDue() }
        .onChange(of: state.dayKey + state.moment.rawValue, initial: true) { _, _ in markBuiltIfDue() }
        .onChange(of: queue.hasPendingFlow) { _, _ in markBuiltIfDue() }
        .onDisappear { revoke?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityAddTraits(canReplay ? .isButton : [])
        .accessibilityHint(canReplay ? "Replays today's finish" : "")
    }

    @ViewBuilder
    private var card: some View {
        let input = state.input(hapticsEnabled: hapticsEnabled)
        switch style {
        case .ridge: RidgeCardView(input: input)
        case .matrix: MatrixCardView(input: input)
        }
    }

    private func openGateIfDue() {
        guard visible, scenePhase == .active, !motionPaused, !isHeldBeforeFlow, !queue.holdsHomeHaptics else { return }
        guard !rotation.hapticsPlayed(entry) else { return }
        rotation.markHapticsPlayed(entry)
        allowed = true
        revoke?.cancel()
        // the entrance cues are inside the first seconds; the idle loop never taps
        revoke = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            allowed = false
        }
    }

    /// A verified day without a flow (seeded history, a flow consumed elsewhere) still builds its theme.
    private func markBuiltIfDue() {
        guard DynamicHeroCard.verifiedMoments.contains(state.moment), !isHeldBeforeFlow,
              !queue.hasPendingFlow, queue.presentation == nil else { return }
        rotation.markBuilt(state.theme, dayKey: state.dayKey)
    }
}
