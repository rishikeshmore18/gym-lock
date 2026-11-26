import SwiftUI

/// Whether this morning's session has already shown the 30-second pause, so a later X on the trip
/// page goes straight to the can't today screen.
@MainActor
enum PauseSeenLedger {
    static let key = "gymlock.morning.pauseSeenSession"

    static func hasSeen(_ sessionID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: key) == sessionID.uuidString
    }

    static func markSeen(_ sessionID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(sessionID.uuidString, forKey: key)
    }
}

/// "Plans changed": a 30-second pause, then straight on to the can't today screen.
///
/// The user is about to bail on the gym, usually at 6 or 7 in the morning and half awake. The screen
/// spends 30 seconds making today's stakes concrete (their own words from day 0, this week, the
/// streak, the 66 visits). "continue" then opens the can't today screen, which holds every way
/// forward (make it up, home workout, skip), and none is hidden (FLOW, Flow 4: skipping is always
/// allowed). The X works at any moment and always means "keep going": friction sits only on the way
/// to skipping, never on the way to the gym.
///
/// Three looks draw the same script (PauseScript):
///   - Ridge or Matrix printer, following the hero card style (`gymlock.home.cardStyle`)
///   - Day 0, whatever the style, at the worst moment to skip (PauseFacts.isCritical: the skip
///     would break a running streak, or it would be the second skip in a row). It plays the user's
///     own day 0 video or photo when there is one.
///
/// The screen owns the clock, the chrome (close, pips, the timer button and the two choice buttons)
/// and the doors' actions; the looks only draw. Approved prototype:
/// docs/prototypes/plans-changed-pause.html.
struct PlansChangedView: View {
    let session: GymSession
    let context: PauseFacts.Context
    let onStillGoing: () -> Void
    let onQuickWorkout: () -> Void
    let onCantToday: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HeroCardStyle.storageKey) private var cardStyleRaw = HeroCardStyle.default.rawValue

    /// Read once when the screen opens, so nothing shifts under the user while they read.
    @State private var model: PauseModel?
    @State private var startedAt = Date()
    @State private var phase: PausePhase = .waiting
    @State private var haptics = PauseHaptics()
    @State private var earlyTapShake = 0
    @State private var didAct = false
    @State private var leaving = false
    /// Matrix only: the receipt is tearing off at the perforation before the can't today screen.
    @State private var tearing = false

    var body: some View {
        GeometryReader { geo in
            // The reader respects the safe area; the screen itself is drawn full bleed, so the layout
            // works in full-screen points with the insets carried alongside.
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)
            let layout = PauseLayout(size: full, safeArea: insets, look: model?.look ?? .ridge)
            ZStack {
                (model?.look.isDark ?? true ? Color(red: 0.043, green: 0.043, blue: 0.047) : Theme.canvas)

                if let model {
                    TimelineView(.animation(paused: isSettled)) { timeline in
                        let t = max(0, timeline.date.timeIntervalSince(startedAt))
                        let input = PauseStageInput(
                            facts: model.facts,
                            script: model.script,
                            t: t,
                            phase: phase,
                            layout: layout,
                            reduceMotion: reduceMotion,
                            haptics: haptics
                        )
                        ZStack {
                            stage(model.look, input)
                            if !tearing { chrome(model, input) }
                        }
                        .onChange(of: t >= PauseScript.wait) { _, ready in
                            if ready { haptics.cue("ready", .medium) }
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .opacity(leaving ? 0 : 1)
        }
        .onAppear(perform: start)
        .onDisappear { haptics.stop() }
        // The Home hero card underneath stays silent while this is up.
        .blocksHeroHaptics("plansChanged")
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Stages

    @ViewBuilder
    private func stage(_ look: PauseLook, _ input: PauseStageInput) -> some View {
        switch look {
        case .ridge: RidgePauseStage(input: input)
        case .matrixPrinter: MatrixPrinterPauseStage(input: input)
        case .day0: Day0PauseStage(input: input)
        }
    }

    // MARK: Chrome

    private func chrome(_ model: PauseModel, _ input: PauseStageInput) -> some View {
        let dark = model.look.isDark
        let layout = input.layout
        return ZStack(alignment: .top) {
            // Top row: the existing header on the light look, the close button on all of them.
            ZStack {
                if !dark { MorningHeader() }
                HStack {
                    Spacer()
                    GlassCircleButton(symbol: "xmark", label: "Close, keep going", diameter: 44) {
                        close()
                    }
                }
                .padding(.trailing, 16)
            }
            .frame(height: 44)
            .padding(.top, layout.safeArea.top + PauseLayout.topRowOffset)

            if case .choosing(let index, _, _) = phase {
                pips(count: model.script.choices.count, index: index, dark: dark)
                    .padding(.top, layout.pipsY)
                    .transition(.opacity)
            }

            VStack(spacing: 4) {
                Spacer(minLength: 0)
                bottomControls(model, input, dark: dark)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, layout.safeArea.bottom + 12)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
    }

    @ViewBuilder
    private func bottomControls(_ model: PauseModel, _ input: PauseStageInput, dark: Bool) -> some View {
        switch phase {
        case .waiting:
            let ready = input.t >= PauseScript.wait
            PauseTimerButton(
                progress: min(1, input.t / PauseScript.wait),
                label: PauseScript.timerLabel(elapsed: input.t),
                isReady: ready,
                isDark: dark,
                shake: earlyTapShake
            ) {
                if ready {
                    proceed(at: input.t)
                } else {
                    // Tapping early does nothing but say "not yet".
                    withAnimation(.linear(duration: 0.24)) { earlyTapShake += 1 }
                }
            }
            Text("close to keep going. no wait.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(dark ? Color.white.opacity(0.55) : Theme.inkTertiary)
                .frame(height: 44)
                .opacity(ready ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: ready)
                .accessibilityHidden(ready)

        case .choosing(let index, _, _):
            let choice = model.script.choices[index]
            PauseCapsuleButton(title: choice.primary, isDark: dark, isProminent: true) {
                commit(choice.key, at: input.t)
            }
            Button {
                haptics.play(.rigid)
                let next = (index + 1) % model.script.choices.count
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.settle) {
                    phase = .choosing(index: next, since: input.t, from: index)
                }
            } label: {
                Text(choice.secondary)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(dark ? Color.white.opacity(0.7) : Theme.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

        case .committed:
            Color.clear.frame(height: 56 + 4 + 44)
        }
    }

    private func pips(count: Int, index: Int, dark: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? (dark ? Color.white : Theme.ink) : (dark ? Color.white.opacity(0.35) : Theme.border))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : Theme.settle, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("option \(index + 1) of \(count)")
    }

    // MARK: Actions

    /// Nothing animates once a door is taken; the timeline can rest.
    private var isSettled: Bool {
        if case .committed = phase { return didAct }
        return false
    }

    private func start() {
        guard model == nil else { return }
        PauseSeenLedger.markSeen(session.id)
        let facts = PauseFactsProvider.facts(store: store, coordinator: coordinator, session: session, context: context)
        let style = HeroCardStyle(rawValue: cardStyleRaw) ?? .default
        let look: PauseLook = facts.isCritical ? .day0 : (style == .matrix ? .matrixPrinter : .ridge)
        model = PauseModel(facts: facts, script: PauseScript(facts: facts), look: look)
        startedAt = Date()
        haptics.prepare()
    }

    private func close() {
        guard !didAct else { return }
        didAct = true
        haptics.stop()
        onStillGoing()
    }

    /// The 30 seconds are up and they tapped "continue": straight to the can't today screen, which now
    /// holds every way forward (make it up, home workout, skip). The three door slips are gone, so the
    /// way to the gym is the X.
    private func proceed(at t: Double) {
        guard !didAct, !tearing else { return }
        haptics.play(.rigid)
        // The printer tears the receipt off at the perforation first, so the next page is a new
        // sheet (the stage's own receipt fly-off). The other looks just fade.
        let tears = model?.look == .matrixPrinter && !reduceMotion
        if tears {
            tearing = true
            phase = .choosing(index: 0, since: t, from: nil)
            haptics.play(.medium)
        }
        Task { @MainActor in
            if tears { try? await Task.sleep(for: .milliseconds(380)) }
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.2)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 220))
            guard !didAct else { return }
            didAct = true
            haptics.stop()
            onCantToday()
        }
    }

    /// The door is taken: a heavy tap, a beat for the look to answer, then the real action.
    private func commit(_ key: PauseChoice.Key, at t: Double) {
        guard !didAct else { return }
        haptics.play(.heavy)
        withAnimation(.easeOut(duration: 0.2)) { phase = .committed(key: key, since: t) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 450))
            guard !didAct else { return }
            didAct = true
            haptics.stop()
            switch key {
            case .gym: onStillGoing()
            case .home: onQuickWorkout()
            case .cant: onCantToday()
            }
        }
    }
}

// MARK: - The shared model the looks draw from

enum PauseLook: Hashable {
    case ridge
    case matrixPrinter
    case day0

    var isDark: Bool { self != .matrixPrinter }
}

struct PauseModel: Hashable {
    let facts: PauseFacts
    let script: PauseScript
    let look: PauseLook
}

/// Where the pause is. Times are seconds on the pause's own clock (`PauseStageInput.t`).
enum PausePhase: Equatable {
    /// The 30 seconds, and after them until "continue" is tapped.
    case waiting
    /// One door on screen. `since` is when it appeared; `from` is the door it replaced.
    case choosing(index: Int, since: Double, from: Int?)
    /// A door was taken; the look may answer it for a moment before the screen goes.
    case committed(key: PauseChoice.Key, since: Double)
}

/// The space a look may draw in. Looks draw full bleed (art may run under the chrome), but their
/// words and objects stay between `contentTop` and `contentBottom`, clear of the close button, the
/// pips and the bottom buttons, on every iPhone.
struct PauseLayout {
    /// The close button's row sits this far below the safe area's top.
    static let topRowOffset: CGFloat = 6
    /// The timer or primary button, the gap, and the secondary button or fine print.
    static let bottomControlsHeight: CGFloat = 56 + 4 + 44

    let size: CGSize
    let safeArea: EdgeInsets
    let look: PauseLook

    /// The pips' top edge, under the close button's row.
    var pipsY: CGFloat { safeArea.top + Self.topRowOffset + 44 + 8 }
    /// Below the close button's row and the pips.
    var contentTop: CGFloat { pipsY + 6 + 14 }
    /// Above the bottom buttons.
    var contentBottom: CGFloat { size.height - safeArea.bottom - 12 - Self.bottomControlsHeight - 16 }
    var contentHeight: CGFloat { max(0, contentBottom - contentTop) }
    /// Content may span the screen minus the page margins.
    var contentWidth: CGFloat { max(0, size.width - Theme.pageMargin * 2) }
}

/// What every look receives, once per frame.
struct PauseStageInput {
    let facts: PauseFacts
    let script: PauseScript
    /// Seconds since the pause opened.
    let t: Double
    let phase: PausePhase
    let layout: PauseLayout
    let reduceMotion: Bool
    let haptics: PauseHaptics

    var isReady: Bool { t >= PauseScript.wait }

    /// The door on screen, and how long it has been there.
    var choice: (choice: PauseChoice, index: Int, age: Double, from: Int?)? {
        switch phase {
        case .choosing(let index, let since, let from):
            return (script.choices[index], index, max(0, t - since), from)
        case .committed(let key, _):
            guard let index = script.choices.firstIndex(where: { $0.key == key }) else { return nil }
            return (script.choices[index], index, 10, nil)
        case .waiting:
            return nil
        }
    }

    /// Seconds since a door was taken, or nil.
    var committedAge: Double? {
        if case .committed(_, let since) = phase { return max(0, t - since) }
        return nil
    }

    /// The line on screen during the wait (the last one holds until "continue").
    var currentLine: PauseLine? {
        script.lines.last { t >= $0.start }
    }
}

// MARK: - Buttons

/// The 30-second button: a quiet capsule that fills left to right with the countdown in it, then
/// turns into the screen's primary button ("continue").
private struct PauseTimerButton: View {
    let progress: Double
    let label: String
    let isReady: Bool
    let isDark: Bool
    let shake: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                GeometryReader { g in
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(56, g.size.width * progress))
                }
                .opacity(isReady ? 0 : 1)
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.identity)
            }
            .frame(height: 56)
            .animation(Theme.stateChange, value: isReady)
        }
        .buttonStyle(PausePressStyle(isEnabled: isReady))
        .modifier(ShakeEffect(shakes: CGFloat(shake)))
        .accessibilityLabel(isReady ? "continue" : "continue, available in \(label.replacingOccurrences(of: "0:", with: "")) seconds")
    }

    private var trackColor: Color {
        if isReady { return isDark ? .white : Theme.ink }
        return isDark ? Color.white.opacity(0.12) : Theme.surfaceMuted
    }
    private var fillColor: Color { isDark ? Color.white.opacity(0.16) : Theme.ink.opacity(0.06) }
    private var labelColor: Color {
        if isReady { return isDark ? Theme.ink : .white }
        return isDark ? Color.white.opacity(0.75) : Theme.inkSecondary
    }
}

/// The primary button of a door: ink on the light look, white on the dark ones.
private struct PauseCapsuleButton: View {
    let title: String
    let isDark: Bool
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isDark ? Theme.ink : .white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(isDark ? Color.white : Theme.ink, in: .capsule)
        }
        .buttonStyle(PausePressStyle(isEnabled: true))
    }
}

private struct PausePressStyle: ButtonStyle {
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A 1 pt side-to-side "not yet" for an early tap on the timer.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(shakes * .pi * 4) * 1.5, y: 0))
    }
}
