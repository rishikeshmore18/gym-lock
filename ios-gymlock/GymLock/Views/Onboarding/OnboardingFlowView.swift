import SwiftUI

/// The onboarding story: thirty-one scenes on one continuous vertical scroll.
///
/// It runs in two halves that share a single gesture, a single visual language,
/// and a single sense of momentum:
///
/// 1. **The story** (logo → caution) establishes the problem and asks the user
///    to opt in. Scenes here play themselves and open the way forward when they
///    are done, so a swipe always means "next scene".
/// 2. **The system** (commitment → activation) turns that agreement into a
///    configured product. These scenes take input, so several of them hold the
///    story until they have an answer.
///
/// One scene does not merely turn: leaving the loop breaks the screen. See
/// `breakTheLoop()`.
struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Scene: Int, CaseIterable {
        // The story.
        case logo, name, greeting, problem, guilt, loop, excuses, chart, caution

        // The system.
        case commitment, dayZero, targetFrequency, currentFrequency
        case failureWindow, failureTime, failureReasons, distractingApps, nightLoop
        case persistentAlarm, alarmSound, mechanisms, comebackMode, buildingSystem
        case gravity, interventionTimeline, systemSummary
        case lockedState, unlockedState, firstWeek, finalCommitment, activation
    }

    /// How long the glass takes to heave, break, and clear the screen.
    private static let shatterDuration: Double = 1.35

    @State private var index = 0
    @State private var isEditingName = false
    /// The loop scene holds the story until it has played to its halfway mark.
    @State private var isLoopUnlocked = false
    /// The press-and-hold on the commitment screen holds the system half.
    @State private var hasCommitted = false

    /// Shared services for the system half.
    @State private var pagerLock = PagerInteractionLock()
    @State private var alarmPlayer = AlarmSoundPlayer()
    @State private var subscriptions = SubscriptionStore()

    /// The captured screen currently breaking apart, if any.
    @State private var shatterImage: Image?
    @State private var shatterProgress: Double = 0
    /// The break is a one-time event; swiping back through the loop later just
    /// turns the page like every other scene.
    @State private var hasShattered = false
    /// Nil while the story needs to cut rather than slide. See `breakTheLoop()`.
    @State private var pageAnimation: Animation? = Theme.pageTurn
    /// True while the break owns the incoming scene's entrance.
    @State private var isGlassTransition = false
    /// The incoming scene's hand-driven reveal, ramped as the glass clears.
    @State private var incomingReveal: Double = 1
    /// The scene whose own timeline is being held back behind the glass.
    @State private var heldScene: Int?

    private var profile: OnboardingProfile { store.profile }

    /// The furthest scene the user has earned.
    ///
    /// Each gate is a question that later screens genuinely depend on. Anything
    /// with a sensible default — the frequency wheels, the alarm sound, the
    /// toggles — is deliberately not gated, because forcing a tap on a screen
    /// that is already correct is just friction.
    private var maxReachableIndex: Int {
        guard store.hasName else { return Scene.name.rawValue }
        guard isLoopUnlocked else { return Scene.loop.rawValue }
        guard hasCommitted else { return Scene.commitment.rawValue }
        if profile.failureWindow == nil { return Scene.failureWindow.rawValue }
        if profile.failureReasons.isEmpty { return Scene.failureReasons.rawValue }
        if profile.selectedDistractingApps.isEmpty { return Scene.distractingApps.rawValue }
        if profile.nightScrollingFrequency == nil { return Scene.nightLoop.rawValue }
        return Scene.allCases.count - 1
    }

    /// The loop hands its exit transition to this view so the screen can break.
    private var interceptedPages: Set<Int> {
        guard isLoopUnlocked, !hasShattered, !reduceMotion else { return [] }
        return [Scene.loop.rawValue]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.canvas.ignoresSafeArea()

            VerticalPager(
                index: $index,
                pageCount: Scene.allCases.count,
                maxReachableIndex: maxReachableIndex,
                isDragDisabled: isEditingName || pagerLock.isLocked,
                interceptedPages: interceptedPages,
                onInterceptedAdvance: { _ in breakTheLoop() },
                pageAnimation: pageAnimation,
                sceneRevealOverride: isGlassTransition ? incomingReveal : nil
            ) { pageIndex in
                scene(at: pageIndex)
            }

            progressRail
                .padding(.trailing, 10)
                .opacity(index == 0 ? 0 : 1)
                .animation(Theme.settle, value: index)

            if let shatterImage {
                GeometryReader { proxy in
                    GlassShatterView(
                        image: shatterImage,
                        size: proxy.size,
                        progress: shatterProgress
                    )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .environment(pagerLock)
        .environment(alarmPlayer)
        .environment(subscriptions)
    }

    @ViewBuilder
    private func scene(at pageIndex: Int) -> some View {
        // A held scene is mounted but not yet running. Starting a scene's
        // timeline while it is buried under falling glass would mean the user
        // misses the opening of it entirely.
        let isActive = index == pageIndex && heldScene != pageIndex

        switch Scene(rawValue: pageIndex) ?? .logo {
        // MARK: The story

        case .logo:
            LogoSplashPage(isActive: isActive)
        case .name:
            NamePage(
                isActive: isActive,
                name: Binding(
                    get: { store.userName },
                    set: { store.userName = $0 }
                ),
                isEditing: $isEditingName,
                onContinue: advance
            )
        case .greeting:
            GreetingPage(isActive: isActive, name: store.greetingName)
        case .problem:
            ProblemReelPage(isActive: isActive)
        case .guilt:
            GuiltPage(isActive: isActive, name: store.greetingName)
        case .loop:
            LoopPage(isActive: isActive) {
                withAnimation(Theme.settle) { isLoopUnlocked = true }
            }
            .allowsHitTesting(!isGlassTransition)
        case .excuses:
            ExcusesPage(isActive: isActive, name: store.greetingName)
        case .chart:
            ChartPage(isActive: isActive)
        case .caution:
            CautionPage(isActive: isActive)

        // MARK: The system

        case .commitment:
            CommitmentPage(isActive: isActive) {
                withAnimation(Theme.settle) { hasCommitted = true }
                advance()
            }
        case .dayZero:
            DayZeroPage(isActive: isActive, onContinue: advance)
        case .targetFrequency:
            TargetFrequencyPage(isActive: isActive, onContinue: advance)
        case .currentFrequency:
            CurrentFrequencyPage(isActive: isActive, onContinue: advance)
        case .failureWindow:
            FailureWindowPage(isActive: isActive, onContinue: advance)
        case .failureTime:
            FailureTimePage(isActive: isActive, onContinue: advance)
        case .failureReasons:
            FailureReasonsPage(isActive: isActive, onContinue: advance)
        case .distractingApps:
            DistractingAppsPage(isActive: isActive, onContinue: advance)
        case .nightLoop:
            NightLoopPage(isActive: isActive, onContinue: advance)
        case .persistentAlarm:
            PersistentAlarmPage(isActive: isActive, onContinue: advance)
        case .alarmSound:
            AlarmSoundPage(isActive: isActive, onContinue: advance)
        case .mechanisms:
            MechanismsPage(isActive: isActive, onContinue: advance)
        case .comebackMode:
            ComebackModePage(isActive: isActive, onContinue: advance)
        case .buildingSystem:
            BuildingSystemPage(isActive: isActive, onContinue: advance)
        case .gravity:
            GravityPage(isActive: isActive, name: store.greetingName, onContinue: advance)
        case .interventionTimeline:
            InterventionTimelinePage(isActive: isActive, onContinue: advance)
        case .systemSummary:
            SystemSummaryPage(isActive: isActive, onContinue: advance)
        case .lockedState:
            LockedStatePage(isActive: isActive, onContinue: advance)
        case .unlockedState:
            UnlockedStatePage(isActive: isActive, onContinue: advance)
        case .firstWeek:
            FirstWeekPage(isActive: isActive, onContinue: advance)
        case .finalCommitment:
            FinalCommitmentPage(isActive: isActive, onActivate: advance)
        case .activation:
            ActivationPage(isActive: isActive) {
                store.stage = .home
            }
        }
    }

    /// A quiet rail showing position in the story.
    ///
    /// The marks shrink as the flow grows so the rail always fits the viewport
    /// without becoming its own scrolling problem — the language is unchanged,
    /// only the scale.
    private var progressRail: some View {
        let count = Scene.allCases.count - 1
        let dot: CGFloat = count > 20 ? 4 : 8
        let gap: CGFloat = count > 20 ? 3 : 6

        return VStack(spacing: gap) {
            ForEach(Scene.allCases.dropFirst(), id: \.rawValue) { scene in
                let isCurrent = index == scene.rawValue

                Capsule()
                    .fill(isCurrent ? Theme.accent : Theme.ink.opacity(0.14))
                    .frame(width: 3, height: isCurrent ? dot * 2.6 : dot)
                    .animation(Theme.settle, value: isCurrent)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityHidden(true)
    }

    private func advance() {
        withAnimation(Theme.pageTurn) {
            index = min(index + 1, maxReachableIndex)
        }
    }

    // MARK: - Breaking the loop

    /// The one transition in the story that is not a page turn.
    ///
    /// The screen the user is looking at is photographed, the story cuts
    /// instantly to the next scene underneath, and the photograph is then heaved
    /// upward and broken apart on top of it. Because the cut happens before the
    /// first shard moves, the glass is still whole when the next scene arrives,
    /// and that scene is uncovered through the widening gaps rather than sliding
    /// in behind them.
    ///
    /// Two details make it hold together: the snapshot is taken before `index`
    /// changes, and `pageAnimation` is dropped for that one state change so the
    /// pager cuts instead of sliding — a slide would be visible through the gaps.
    private func breakTheLoop() {
        guard !hasShattered, let snapshot = ScreenSnapshot.capture() else {
            advance()
            return
        }

        hasShattered = true
        shatterImage = Image(uiImage: snapshot)
        shatterProgress = 0

        // One state update, so the pager renders the next scene with no
        // animation at all while the glass is still perfectly intact on top.
        // The incoming scene is parked at the very start of its entrance and
        // held there — the break is what will bring it in.
        pageAnimation = nil
        isGlassTransition = true
        incomingReveal = 0
        index = min(index + 1, maxReachableIndex)
        heldScene = index

        // Fired on the finger leaving the screen rather than on the first
        // animation frame: the swipe is the cause, and any delay between the
        // gesture and the crack reads as lag.
        Haptics.glassBreak()

        Task { await playShatter() }
    }

    /// Runs the break and, underneath it, the arrival of the next scene.
    ///
    /// The two are staged against each other on purpose. The scene's elements
    /// stagger in while the glass is still in the air, so the gaps open onto
    /// something assembling itself, and the scene's own timeline is released
    /// while the last pieces are still falling — by the time the screen is clear
    /// it is already running, not waiting to start.
    private func playShatter() async {
        // One frame with everything settled and the glass unbroken, so the break
        // starts from an intact screen instead of mid-cut.
        try? await Task.sleep(for: .milliseconds(16))

        withAnimation(.linear(duration: Self.shatterDuration)) {
            shatterProgress = 1
        }

        // Ordinary page turns work again as soon as the cut has committed.
        try? await Task.sleep(for: .milliseconds(120))
        pageAnimation = Theme.pageTurn

        // Starts as the pane fails and the first pieces leave.
        try? await Task.sleep(for: .milliseconds(80))
        withAnimation(.timingCurve(0.2, 0.85, 0.25, 1, duration: 0.66)) {
            incomingReveal = 1
        }

        try? await Task.sleep(for: .milliseconds(340))
        heldScene = nil

        try? await Task.sleep(for: .seconds(Self.shatterDuration))
        shatterImage = nil
        shatterProgress = 0
        isGlassTransition = false
        incomingReveal = 1
    }
}
