//
//  WakeIntroView.swift
//  GymLock · the "I'm up" wake page (native port of web/morning2 stage.tsx, ui.tsx, settled.tsx)
//
//  One page, one clock. Layers, bottom to top:
//
//    page     the settled page in the user's appearance: "Today" and the real StreakChip, the card's
//             slot, the plan (A) or the week and the run (B), "Apps open at …", the mission capsule
//             and "Plans changed". Native layout, Dynamic Type capped, always laid out so the card's
//             slot is known before the stage condenses into it; each element fades in on its cue.
//    veil     Reduce Motion only: the dark around the card fades to the page in 200 ms.
//    stage    a full-screen Canvas: the dark stage clipped to a rect that contracts into the card's
//             slot, with the renderer (MatrixWakeStage / RidgeWakeStage) drawing inside it.
//    words    the chapter's eyebrow and big kinetic line, the labels beside the board's objects, the
//             progress ticks, "Tap to skip", and the card's own copy; clipped with the stage.
//    day      light appearance only: the card wiping to its day look (a second renderer pass with
//             `dark: false` and the card copy in ink), clipped to a diagonal band that sweeps across.
//    tap      during the intro, a tap anywhere settles the page at once.
//
//  Time: `TimelineView(.animation)` drives a `WakeClock` that only advances while the page is on
//  screen and the app is active. Returning from the background mid-intro settles the page (nobody
//  watched the rest). Haptics tick on the same `t` (WakeHaptics). VoiceOver starts settled.
//
//  Sizes: one fit for everything (`WakeLayout.fit`): the prototype's 390 x 844 box scaled by
//  min(width/390, height/844, 1.25), top-aligned and centred in a column (`m.ox`). Words, card slot,
//  buttons and the renderers use it; the stage and backgrounds stay full-bleed. The intro's top rows
//  are nudged below the status bar where a phone's safe area is taller than the prototype's. The
//  settled page is native layout inside that column (laid out in design units, scaled uniformly).
//
//  120 Hz: ProMotion iPhones cap TimelineView at 60 Hz unless Info.plist has
//  `CADisableMinimumFrameDurationOnPhone = YES` (the hero card needs the same key).
//
//  Depends on: WakeStage.swift, WakeHaptics.swift, WakeFactsProvider.swift (symbols), Theme,
//  StreakChip, HeroMotion (RidgeCardView.swift), and the renderers MatrixWakeStage / RidgeWakeStage.
//

import SwiftUI
import UIKit

private typealias E = WakeEase

// MARK: - The page

struct WakeIntroView: View {
    private let showsLockLine: Bool
    private let startsSettled: Bool
    private let isPaused: Bool
    private let onPrimary: () -> Void
    private let onPlansChanged: () -> Void

    @State private var engine: WakeIntroEngine
    @State private var isOnScreen = false
    @State private var isSettled = false
    @State private var slot: CGRect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - concept: which concept plays (WakeFactsProvider.concept).
    ///   - facts: the real facts (WakeFactsProvider.facts). Read once; later values are ignored.
    ///   - showsLockLine: false when no apps are locked, so "Apps open at …" is not shown.
    ///   - startsSettled: skip the intro (the page was already seen).
    ///   - isPaused: something covers the page (a sheet); the clock stops.
    ///   - onPrimary: the mission capsule. The page plays its tap haptic itself.
    ///   - onPlansChanged: "Plans changed".
    init(
        concept: WakeConcept,
        facts: WakeFacts,
        showsLockLine: Bool = true,
        startsSettled: Bool = false,
        isPaused: Bool = false,
        onPrimary: @escaping () -> Void,
        onPlansChanged: @escaping () -> Void
    ) {
        _engine = State(initialValue: WakeIntroEngine(concept: concept, facts: facts))
        self.showsLockLine = showsLockLine
        self.startsSettled = startsSettled
        self.isPaused = isPaused
        self.onPrimary = onPrimary
        self.onPlansChanged = onPlansChanged
    }

    private var isRunning: Bool { isOnScreen && !isPaused && scenePhase == .active }

    /// The display's rate during the intro (30 Hz in Low Power Mode or when hot), 60 Hz for the
    /// idle loop.
    private var frameInterval: Double? {
        let base = HeroMotion.minimumInterval
        return isSettled ? max(base ?? 0, 1.0 / 60) : base
    }
    private var look: WakeLook { colorScheme == .dark ? .dark : .light }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let insets = proxy.safeAreaInsets
            TimelineView(.animation(minimumInterval: frameInterval, paused: !isRunning)) { timeline in
                let now = engine.sync(
                    timeline.date,
                    running: isRunning,
                    reduceMotion: reduceMotion,
                    startSettled: startsSettled || voiceOver
                )
                page(now: now, size: size, insets: insets)
                    // Once settled the idle loop runs at 60 Hz (the schedule is read by the outer body).
                    .onChange(of: now.t >= now.plan.introEnd, initial: true) { _, settled in
                        if settled != isSettled { isSettled = settled }
                    }
            }
        }
        .ignoresSafeArea()
        .onAppear { isOnScreen = true }
        .onDisappear {
            isOnScreen = false
            engine.halt(at: Date())
        }
        .onChange(of: isRunning, initial: true) { _, running in
            engine.setRunning(running, at: Date())
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { engine.noteBackgrounded() }
        }
    }

    // MARK: Composition

    @ViewBuilder
    private func page(now: WakeNow, size: CGSize, insets: EdgeInsets) -> some View {
        let m = WakeMoment(now: now, size: size, insets: insets, slot: slot, dark: look.dark, clocks: engine.clocks)
        let facts = engine.facts
        let copy = engine.copy
        let concept = engine.concept

        ZStack(alignment: .topLeading) {
            look.bg

            WakeSettledPage(
                m: m,
                facts: facts,
                copy: copy,
                concept: concept,
                look: look,
                showsLockLine: showsLockLine,
                onSlot: { rect in if slot != rect { slot = rect } },
                onPrimary: {
                    engine.tap()
                    onPrimary()
                },
                onPlansChanged: {
                    engine.tap()
                    onPlansChanged()
                }
            )
            .frame(width: size.width, height: size.height)

            stageCanvas(m: m)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            WakeStageWords(m: m, facts: facts, copy: copy, concept: concept, anchors: engine.anchors)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipShape(WakeStageClip(rect: m.stageRect, radius: m.radius))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if m.dayCard {
                dayCard(m: m)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .modifier(WakeWipe(m: m))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if m.t < m.plan.introEnd {
                Color.clear
                    .contentShape(.rect)
                    .frame(width: size.width, height: size.height)
                    .onTapGesture { engine.skip(at: Date()) }
                    .accessibilityElement()
                    .accessibilityLabel(copy.greet)
                    .accessibilityHint("Tap to skip")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default) { engine.skip(at: Date()) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(.named(WakeLayout.pageSpace))
    }

    /// The dark stage, contracting into the card's slot.
    private func stageCanvas(m: WakeMoment) -> some View {
        let stageEngine = engine
        let pageLook = look
        let frame = stageEngine.frame(m: m, dark: true, rect: m.stageRect)
        // Resolved here, on the main actor, so the Canvas closure touches no actor-isolated state.
        let renderer = stageEngine.renderer
        return Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, canvasSize in
            if m.veil > 0 {
                ctx.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(WakePalette.stage.opacity(m.veil)))
            }
            let cardPath = Path(roundedRect: m.cardRect, cornerRadius: WakeLayout.cardRadius, style: .continuous)
            if m.dayCard {
                // The card's soft lift on the page, under the stage (stage.tsx: the zIndex -1 shadow).
                var shadow = ctx
                shadow.addFilter(.shadow(color: .black.opacity(0.05 * m.wipe), radius: 7, x: 0, y: 6))
                shadow.fill(cardPath, with: .color(pageLook.card))
            }
            var stage = ctx
            let clip = Path(roundedRect: m.stageRect, cornerRadius: m.radius, style: .continuous)
            stage.clip(to: clip)
            stage.fill(clip, with: .color(m.stageBackground))
            // Once the day look covers the card the night pass is hidden; skip drawing it.
            if !(m.dayCard && m.wipe >= 1) {
                WakeIntroView.drawFaded(&stage, opacity: m.contentOpacity) { layer in
                    renderer.draw(&layer, size: canvasSize, frame: frame)
                }
            }
            if pageLook.dark && m.k > 0.98 {
                let hairline = Path(roundedRect: m.cardRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: WakeLayout.cardRadius - 0.5, style: .continuous)
                ctx.stroke(hairline, with: .color(pageLook.hair), lineWidth: 1)
            }
        }
    }

    /// Draws a renderer pass at `opacity` as one layer (so overlapping marks fade together). At full
    /// opacity, which is every frame without Reduce Motion, it draws straight into the context: no
    /// full-screen offscreen layer per frame.
    private nonisolated static func drawFaded(_ ctx: inout GraphicsContext, opacity: Double, _ body: (inout GraphicsContext) -> Void) {
        if opacity >= 1 {
            body(&ctx)
        } else if opacity > 0 {
            ctx.drawLayer { layer in
                layer.opacity = opacity
                body(&layer)
            }
        }
    }

    /// Light appearance: the card in its day look (ink on Theme.surface), revealed by the wipe.
    private func dayCard(m: WakeMoment) -> some View {
        let dayEngine = engine
        let frame = dayEngine.frame(m: m, dark: false, rect: m.cardRect)
        let renderer = dayEngine.renderer
        return ZStack(alignment: .topLeading) {
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, canvasSize in
                let path = Path(roundedRect: m.cardRect, cornerRadius: WakeLayout.cardRadius, style: .continuous)
                var card = ctx
                card.clip(to: path)
                card.fill(path, with: .color(Theme.surface))
                // Reduce Motion's content fade applies to the day look too (the night pass has it).
                WakeIntroView.drawFaded(&card, opacity: m.contentOpacity) { layer in
                    renderer.draw(&layer, size: canvasSize, frame: frame)
                }
                let hairline = Path(roundedRect: m.cardRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: WakeLayout.cardRadius - 0.5, style: .continuous)
                ctx.stroke(hairline, with: .color(Theme.border), lineWidth: 1)
            }

            WakeCardCopy(
                copy: dayEngine.copy,
                matrix: dayEngine.concept.isMatrix,
                lf: m.since(m.plan.cardCopyAt),
                ink: Theme.ink,
                ink2: Theme.ink.opacity(0.62),
                reduce: m.plan.reduceMotion,
                cardSize: m.cardRect.size
            )
            .offset(x: m.cardRect.minX, y: m.cardRect.minY)
        }
    }
}

// MARK: - The engine: clock, plan, renderer, haptics

/// The clock value and the plan for one drawn frame.
struct WakeNow {
    let t: Double
    let plan: WakePlan
}

/// Owns everything that must outlive a body evaluation. Held in `@State`; cheap to create (the
/// renderer is made on first use).
@MainActor
final class WakeIntroEngine {
    let concept: WakeConcept
    let facts: WakeFacts
    let copy: WakeCopy
    /// The gym and leave-by clock strings, formatted once (the locale lookup is not per-frame work).
    let clocks: WakeClocks

    private(set) var plan: WakePlan?
    private let clock = WakeClock()
    private var haptics: WakeHaptics?
    private var wasBackgrounded = false

    /// The visual, made once for the page's whole life.
    private(set) lazy var renderer: any WakeStageRenderer = WakeStageFactory.make(concept)

    init(concept: WakeConcept, facts: WakeFacts) {
        let normalized = facts.normalized()
        self.concept = concept
        self.facts = normalized
        self.copy = WakeCopy.make(concept: concept, facts: normalized)
        self.clocks = WakeClocks(gym: normalized.gymClock, leave: normalized.leaveClock)
    }

    /// The tap haptic of the page's two buttons, under the app's haptics switch.
    func tap() {
        guard HeroHapticPlayer.shared.isEnabled else { return }
        Haptics.tap()
    }

    /// The renderer's own idea of where its objects are, when it has one.
    var anchors: (any WakeStageAnchoring)? { renderer as? any WakeStageAnchoring }

    /// Advances the clock for a drawn frame and plays any haptic it crossed.
    func sync(_ date: Date, running: Bool, reduceMotion: Bool, startSettled: Bool) -> WakeNow {
        let plan = preparedPlan(reduceMotion: reduceMotion)
        if !clock.isStarted {
            // The clock starts on the first frame the page is actually running.
            guard running else { return WakeNow(t: startSettled ? plan.introEnd : 0, plan: plan) }
            clock.start(at: date)
            if startSettled { clock.jump(to: plan.introEnd, at: date) }
            haptics?.resync(to: clock.t(at: date))
        }
        let t = clock.t(at: date)
        haptics?.tick(t)
        return WakeNow(t: t, plan: plan)
    }

    /// The frame handed to the renderer.
    func frame(m: WakeMoment, dark: Bool, rect: CGRect) -> WakeFrame {
        WakeFrame(t: m.t, plan: m.plan, facts: facts, copy: copy, concept: concept, dark: dark, stageRect: rect, idleT: m.idleT)
    }

    /// Visible and active, or not. Returning from the background mid-intro settles the page.
    func setRunning(_ running: Bool, at date: Date) {
        guard clock.isStarted else { return }
        if running {
            if wasBackgrounded, let plan, clock.t(at: date) < plan.introEnd {
                clock.jump(to: plan.introEnd, at: date)
            }
            wasBackgrounded = false
            clock.resume(at: date)
            haptics?.resume(at: clock.t(at: date))
        } else {
            clock.pause(at: date)
        }
    }

    func noteBackgrounded() {
        wasBackgrounded = true
    }

    /// The page left the screen: stop the clock and never buzz again from here.
    func halt(at date: Date) {
        clock.pause(at: date)
        haptics?.stop()
    }

    /// Tap to skip: jump to the settled page; the jumped-over cues are dropped.
    func skip(at date: Date) {
        guard let plan, clock.isStarted else { return }
        guard clock.t(at: date) < plan.introEnd else { return }
        clock.jump(to: plan.introEnd, at: date)
        haptics?.resync(to: plan.introEnd)
    }

    private func preparedPlan(reduceMotion: Bool) -> WakePlan {
        if let plan { return plan }
        // Built once: Reduce Motion is read when the page starts, so the plan never changes mid-play.
        let built = WakePlan.build(concept: concept, facts: facts, reduceMotion: reduceMotion)
        plan = built
        haptics = WakeHaptics(plan: built)
        return built
    }
}

/// Seconds on screen. Advances only while running; jumps for skip and resume.
@MainActor
final class WakeClock {
    private var base: Double = 0
    private var resumedAt: Date?
    private(set) var isStarted = false

    func t(at date: Date) -> Double {
        guard let resumedAt else { return base }
        return base + max(0, date.timeIntervalSince(resumedAt))
    }

    func start(at date: Date) {
        guard !isStarted else { return }
        isStarted = true
        base = 0
        resumedAt = date
    }

    func pause(at date: Date) {
        guard isStarted, resumedAt != nil else { return }
        base = t(at: date)
        resumedAt = nil
    }

    func resume(at date: Date) {
        guard isStarted, resumedAt == nil else { return }
        resumedAt = date
    }

    func jump(to t: Double, at date: Date) {
        base = t
        if resumedAt != nil { resumedAt = date }
    }
}

// MARK: - Per-frame values (stage.tsx, verbatim)

/// The facts' clock strings ("7:05"), formatted once per page.
struct WakeClocks {
    let gym: String
    let leave: String?
}

/// Everything one frame derives from the clock, computed once and shared by the layers.
struct WakeMoment {
    let t: Double
    /// `t` in prototype frames (30 fps), so the ported expressions read like the source.
    let f: Double
    let plan: WakePlan
    let size: CGSize
    let insets: EdgeInsets
    /// Points per design unit.
    let s: CGFloat
    /// Left edge of the 390-unit column (centres it on wide screens).
    let ox: CGFloat
    /// 0 full screen, 1 in the card's slot.
    let k: Double
    let cardRect: CGRect
    let stageRect: CGRect
    let radius: CGFloat
    let stageBackground: Color
    /// Reduce Motion: the visual's crossfades.
    let contentOpacity: Double
    /// Reduce Motion: the dark around the card, fading to the page.
    let veil: Double
    let beat: WakeBeat?
    /// Light appearance, from the wipe on: the card's day look is showing.
    let dayCard: Bool
    /// The wipe's progress, 0 to 1.
    let wipe: Double
    let idleT: Double
    /// Top of the progress ticks, below the status bar.
    let barsY: CGFloat
    /// Top of the chapter's words.
    let textY: CGFloat
    /// "7:05": the gym time.
    let gymClock: String
    /// The leave-by time, nil when there is none.
    let leaveClock: String?

    init(now: WakeNow, size: CGSize, insets: EdgeInsets, slot: CGRect?, dark: Bool, clocks: WakeClocks) {
        let plan = now.plan
        let t = now.t
        let f = t * WakePlan.fps
        let rm = plan.reduceMotion
        let condense = plan.condenseAt * WakePlan.fps
        let fit = WakeLayout.fit(size)
        let s = fit.scale
        let card = slot ?? WakeLayout.fallbackCardRect(size, topInset: insets.top)
        let k = plan.condenseProgress(at: t)
        let beat = plan.beat(at: t)

        self.t = t
        self.f = f
        self.plan = plan
        self.size = size
        self.insets = insets
        self.s = s
        self.ox = fit.originX
        self.k = k
        self.beat = beat
        cardRect = card

        let kk = CGFloat(k)
        func towardCard(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * kk }
        stageRect = CGRect(
            x: towardCard(0, card.minX),
            y: towardCard(0, card.minY),
            width: towardCard(size.width, card.width),
            height: towardCard(size.height, card.height)
        )
        radius = WakeLayout.cardRadius * CGFloat(k)
        stageBackground = WakePalette.mix(WakePalette.stageRGB, dark ? WakePalette.darkCardRGB : WakePalette.nightCardOnLightRGB, k)

        // A short dip as chapters swap under Reduce Motion.
        var swap = 1.0
        if rm, let beat, beat.index > 0 {
            swap = E.cl(abs(f - beat.start * WakePlan.fps + 0.5) / 3)
        }
        if !rm {
            contentOpacity = 1
        } else if f < condense {
            contentOpacity = swap
        } else if f < condense + 3 {
            contentOpacity = 1 - (f - condense) / 3
        } else {
            contentOpacity = E.cl((f - condense - 9) / 5)
        }
        veil = rm ? 1 - E.cl((f - condense - 3) / 6) : 0

        dayCard = !dark && t >= plan.wipe.lowerBound
        let wipeFrom = plan.wipe.lowerBound
        wipe = rm
            ? E.cl((f - wipeFrom * WakePlan.fps) / 6)
            : E.ramp(t, plan.wipe.lowerBound, plan.wipe.upperBound, { E.eio($0) })
        idleT = E.idleT(t, introEnd: plan.introEnd, length: plan.idleLength)

        let bars = max(58 * s, insets.top + 6)
        barsY = bars
        textY = max(92 * s, bars + 34 * s)
        gymClock = clocks.gym
        leaveClock = clocks.leave
    }

    /// Frames since a plan time (seconds).
    func since(_ seconds: Double) -> Double { f - seconds * WakePlan.fps }
    var condenseF: Double { plan.condenseAt * WakePlan.fps }
}

// MARK: - Tokens (prototype plan.ts C, ui.tsx LOOK; UI-RULES §2 dark surfaces)

enum WakePalette {
    typealias RGB = (r: Double, g: Double, b: Double)

    static func rgb(_ hex: UInt32) -> RGB {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
    static func color(_ c: RGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }
    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> Color {
        let k = E.cl(t)
        return Color(red: a.r + (b.r - a.r) * k, green: a.g + (b.g - a.g) * k, blue: a.b + (b.b - a.b) * k)
    }

    /// The intro's stage, #0A0A0B.
    static let stageRGB = rgb(0x0A0A0B)
    /// The card in dark appearance, #151517.
    static let darkCardRGB = rgb(0x151517)
    /// The night card in light appearance before it wipes to day, #161618.
    static let nightCardOnLightRGB = rgb(0x161618)

    static var stage: Color { color(stageRGB) }
    /// The intro's ink, #F4F4F2, at 100% and 60%.
    static var chapterInk: Color { color(rgb(0xF4F4F2)) }
    static var chapterInk2: Color { chapterInk.opacity(0.6) }
    /// The night card's copy: #F4F4F2 at 100% and 66%.
    static var cardNightInk2: Color { chapterInk.opacity(0.66) }
    /// The streak flame (StreakChip's gradient).
    static var flame: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.847, green: 0.153, blue: 0.075), Color(red: 1, green: 0.451, blue: 0), Color(red: 1, green: 0.769, blue: 0.180)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The settled page's look in the user's appearance (ui.tsx LOOK).
struct WakeLook: Sendable {
    let dark: Bool
    let bg: Color
    let card: Color
    let ink: Color
    let ink2: Color
    let line: Color
    let hair: Color
    let button: Color
    let buttonInk: Color
    /// The ring of a stop still to come.
    let nodeRing: Color
    /// The dashed ring of a planned session.
    let dashed: Color
    /// The run's days still ahead.
    let tickOff: Color

    static let light = WakeLook(
        dark: false,
        bg: Theme.canvas,
        card: Theme.surface,
        ink: Theme.ink,
        ink2: Theme.inkSecondary,
        line: Theme.border,
        hair: Color.black.opacity(0.07),
        button: Theme.ink,
        buttonInk: Theme.surface,
        nodeRing: WakePalette.color(WakePalette.rgb(0xCFCFCB)),
        dashed: WakePalette.color(WakePalette.rgb(0xC9C8C3)),
        tickOff: WakePalette.color(WakePalette.rgb(0xE3E2DD))
    )

    static let dark = WakeLook(
        dark: true,
        bg: WakePalette.color(WakePalette.rgb(0x0B0B0C)),
        card: WakePalette.color(WakePalette.darkCardRGB),
        ink: WakePalette.color(WakePalette.rgb(0xF2F2F0)),
        ink2: WakePalette.color(WakePalette.rgb(0xF2F2F0)).opacity(0.62),
        line: Color.white.opacity(0.1),
        hair: Color.white.opacity(0.08),
        button: WakePalette.color(WakePalette.rgb(0xF2F2F0)),
        buttonInk: WakePalette.color(WakePalette.rgb(0x111112)),
        nodeRing: Color.white.opacity(0.28),
        dashed: Color.white.opacity(0.3),
        tickOff: Color.white.opacity(0.14)
    )
}

// MARK: - Text metrics (plan.ts measure, fit, twoLines)

@MainActor
enum WakeTextMetrics {
    /// Hashable keys, not formatted strings: these are looked up every frame.
    private struct WidthKey: Hashable {
        let text: String
        let rounded: Bool
        let weight: CGFloat
    }
    private struct LinesKey: Hashable {
        let text: String
        let rounded: Bool
        let weight: CGFloat
    }
    private static var widths: [WidthKey: CGFloat] = [:]
    private static var lineCache: [LinesKey: [String]] = [:]

    static func uiFont(rounded: Bool, weight: UIFont.Weight, size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Width of `text` at 100 pt.
    static func width(_ text: String, rounded: Bool, weight: UIFont.Weight) -> CGFloat {
        let key = WidthKey(text: text, rounded: rounded, weight: weight.rawValue)
        if let cached = widths[key] { return cached }
        let font = uiFont(rounded: rounded, weight: weight, size: 100)
        let measured = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        if widths.count > 256 { widths.removeAll() }
        widths[key] = measured
        return measured
    }

    /// The biggest size up to `max` at which every line fits `maxWidth` (design units).
    static func fit(_ lines: [String], rounded: Bool, weight: UIFont.Weight, max maxSize: CGFloat, maxWidth: CGFloat, tracking: CGFloat) -> CGFloat {
        let em = lines.map { width($0, rounded: rounded, weight: weight) / 100 + tracking * CGFloat($0.count) }.max() ?? 1
        return min(maxSize, floor(maxWidth / Swift.max(0.01, em)))
    }

    /// A short sentence as at most two balanced lines; two sentences split between them.
    static func twoLines(_ text: String, rounded: Bool, weight: UIFont.Weight) -> [String] {
        // Called for every chapter line on every frame: the split is worked out once per text.
        let key = LinesKey(text: text, rounded: rounded, weight: weight.rawValue)
        if let cached = lineCache[key] { return cached }
        let lines = splitTwoLines(text, rounded: rounded, weight: weight)
        if lineCache.count > 64 { lineCache.removeAll() }
        lineCache[key] = lines
        return lines
    }

    private static func splitTwoLines(_ text: String, rounded: Bool, weight: UIFont.Weight) -> [String] {
        if let r = text.range(of: ". ") {
            let k = text.distance(from: text.startIndex, to: r.lowerBound)
            if k > 0 && k < text.count - 2 {
                return [String(text[..<r.lowerBound]) + ".", String(text[r.upperBound...])]
            }
        }
        let words = text.components(separatedBy: " ")
        guard words.count >= 3 else { return [text] }
        var best = [text]
        var bestWidth = CGFloat.greatestFiniteMagnitude
        for i in 1..<words.count {
            let a = words[0..<i].joined(separator: " ")
            let b = words[i...].joined(separator: " ")
            let penalty: CGFloat = i == words.count - 1 ? 1.25 : 1
            let m = Swift.max(width(a, rounded: rounded, weight: weight), width(b, rounded: rounded, weight: weight)) * penalty
            if m < bestWidth {
                bestWidth = m
                best = [a, b]
            }
        }
        return best
    }

    /// "7:05", "18:00": a clock the card can flip.
    static func isClock(_ s: String) -> Bool {
        // Per frame: a plain scan, no regular expression to compile.
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2 else { return false }
        return parts.allSatisfy { part in part.allSatisfy { $0.isASCII && $0.isNumber } }
    }
}

// MARK: - Kinetic type (hero13/kin13 Kinetic, Eyebrow, FlipClock; ui.tsx CenterSlam)

/// One line of big kinetic type. `f` is frames since the line started (30 fps).
private struct WakeKineticLine: View {
    enum Style { case slam, centerSlam, stamp, wipe, rise, drop, track }

    let text: String
    let style: Style
    let f: Double
    let size: CGFloat
    let color: Color
    let rounded: Bool
    let weight: Font.Weight
    /// Letter spacing in em.
    let tracking: CGFloat
    let reduce: Bool
    /// Points per design unit, for the few fixed pixel values (the wipe's coral bar).
    let unit: CGFloat

    private var font: Font { .system(size: size, weight: weight, design: rounded ? .rounded : .default) }

    var body: some View {
        if reduce {
            plain(tracking).opacity(E.cl((f - 3) / 6))
        } else {
            switch style {
            case .slam: slam
            case .centerSlam: centerSlam
            case .stamp: stamp
            case .wipe: wipe
            case .rise: rise
            case .drop: drop
            case .track: track
            }
        }
    }

    private func plain(_ em: CGFloat) -> some View {
        Text(text)
            .font(font)
            .tracking(em * size)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private var slam: some View {
        let x = (f - 3) / 30
        let scale = 1.6 - 0.6 * E.spr(x * 1.2, w: 13, z: 6)
        return plain(tracking + 0.12 * CGFloat(1 - E.ez(x * 3)))
            .scaleEffect(CGFloat(scale), anchor: UnitPoint(x: 0, y: 0.8))
            .opacity(E.cl((f - 3) / 2.5))
    }

    /// kin13's slam anchored at the centre, for centred chapters (ui.tsx CenterSlam).
    private var centerSlam: some View {
        let x = (f - 3) / 30
        let scale = 1.3 - 0.3 * E.spr(x * 1.2, w: 13, z: 6)
        return plain(-0.03 + 0.1 * CGFloat(1 - E.ez(x * 3)))
            .scaleEffect(CGFloat(scale), anchor: UnitPoint(x: 0.5, y: 0.8))
            .opacity(E.cl((f - 3) / 2.5))
    }

    private var stamp: some View {
        let p = E.ez((f - 3) / 6)
        let anchor = UnitPoint(x: 0, y: 0.6)
        return plain(tracking)
            .scaleEffect(CGFloat(1.28 - 0.28 * p), anchor: anchor)
            .rotationEffect(.degrees(-3 * (1 - p)), anchor: anchor)
            .opacity(E.cl((f - 3) / 2))
    }

    private var wipe: some View {
        let p = E.ez((f - 3) / 14)
        let barWidth = 6 * unit
        return plain(tracking)
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: CGFloat(max(0.0001, p)), y: 1, anchor: .leading)
            }
            .overlay(alignment: .topLeading) {
                if p < 1 {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(Theme.accent)
                            .frame(width: barWidth, height: g.size.height * 0.84)
                            .offset(x: g.size.width * CGFloat(p) - barWidth / 2, y: g.size.height * 0.08)
                            .opacity(1 - p * 0.6)
                    }
                }
            }
    }

    private var rise: some View {
        let words = text.components(separatedBy: " ")
        let lineHeight = size * 1.2
        return HStack(alignment: .firstTextBaseline, spacing: 0.24 * size) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let p = E.back((f - 3 - Double(i) * 3) / 11, 1.3)
                Text(word)
                    .font(font)
                    .tracking(tracking * size)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .fixedSize()
                    .offset(y: CGFloat(1 - p) * 1.1 * lineHeight)
                    .padding(.bottom, 0.12 * size)
                    .clipped()
                    .padding(.bottom, -0.12 * size)
            }
        }
    }

    private var drop: some View {
        let chars = Array(text)
        return HStack(alignment: .firstTextBaseline, spacing: tracking * size) {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                let d = f - 3 - Double(i) * 1.3
                let p = E.back(d / 11, 2.2)
                Text(String(ch))
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .fixedSize()
                    .opacity(E.cl(d / 2))
                    .offset(y: -CGFloat(1 - p) * size * 0.7)
            }
        }
    }

    private var track: some View {
        let chars = Array(text)
        let spacing = (tracking + 0.55 * CGFloat(1 - E.ez((f - 3) / 18))) * size
        return HStack(alignment: .firstTextBaseline, spacing: spacing) {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .fixedSize()
                    .opacity(E.cl((f - 3 - Double(i) * 0.9) / 6))
            }
        }
    }
}

/// The eyebrow: a short rule draws out, then the words slide in after it (kin13 Eyebrow).
private struct WakeEyebrow: View {
    let text: String
    let f: Double
    let color: Color
    let size: CGFloat
    let weight: Font.Weight
    let unit: CGFloat
    let reduce: Bool

    var body: some View {
        let line = CGFloat(reduce ? 1 : E.ez((f - 1) / 6))
        let tx = reduce ? 1 : E.ez((f - 4) / 8)
        HStack(spacing: 12 * unit) {
            Capsule()
                .fill(color)
                .opacity(0.85)
                .frame(width: 26 * unit * line, height: 3 * unit)
                .padding(.trailing, (2 - 14 * (1 - line)) * unit)
            Text(text)
                .font(.system(size: size, weight: weight))
                .tracking(CGFloat(0.06 + (1 - tx) * 0.22) * size)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .opacity(tx)
                .offset(x: CGFloat(1 - tx) * -10 * unit)
        }
    }
}

/// Digits that flip in: the last one rises into place (kin13 FlipClock).
private struct WakeFlipClock: View {
    let text: String
    /// 0 right after the last digit changed, 1 just before the next change.
    let frac: Double
    let size: CGFloat
    let color: Color
    let rounded: Bool
    let weight: Font.Weight

    var body: some View {
        let p = E.ez(frac / 0.22)
        let chars = Array(text)
        HStack(alignment: .firstTextBaseline, spacing: -0.03 * size) {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                let last = i == chars.count - 1
                Text(String(ch))
                    .font(.system(size: size, weight: weight, design: rounded ? .rounded : .default))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .fixedSize()
                    .offset(y: last ? CGFloat(1 - p) * 0.6 * size * 1.2 : 0)
                    .opacity(last ? 0.3 + 0.7 * p : 1)
                    .clipped()
            }
        }
    }
}

// MARK: - The stage's words (stage.tsx Stage, ChapterText, StoryBars, MatrixExtras, ridgeLabels)

private struct WakeStageWords: View {
    let m: WakeMoment
    let facts: WakeFacts
    let copy: WakeCopy
    let concept: WakeConcept
    let anchors: (any WakeStageAnchoring)?

    private var rm: Bool { m.plan.reduceMotion }
    private var s: CGFloat { m.s }

    var body: some View {
        let beats = m.plan.beats
        let b = m.beat
        let lf = b.map { m.since($0.start) } ?? 0
        let condenseF = m.condenseF
        let afterCondense = m.f - condenseF

        ZStack(alignment: .topLeading) {
            // The words beside the board's objects.
            if let b {
                extras(b.id, lt: rm ? 6 : lf / 30, out: 0)
            } else if let last = beats.last, afterCondense < 8 {
                extras(last.id, lt: m.since(last.start) / 30, out: afterCondense)
            }

            // The chapter's line: the incoming one waits a beat (longer for the wipe) after the
            // outgoing one starts leaving.
            if let b, b.index == 0 || rm || lf - 4 >= (Self.style(b.id) == .wipe ? 3 : 1) {
                chapter(b.id, lf: b.index > 0 && !rm ? lf - 4 : lf, out: 0)
            }
            if let b, b.index > 0, lf < 6 {
                let prev = beats[b.index - 1]
                chapter(prev.id, lf: m.since(prev.start), out: lf)
            }
            if b == nil, let last = beats.last, afterCondense < 6 {
                chapter(last.id, lf: m.since(last.start), out: afterCondense)
            }

            bars(b: b)

            if !rm && m.f > 24 && m.f < condenseF + 6 {
                skipHint
            }

            if m.t >= m.plan.cardCopyAt, !(m.dayCard && m.wipe >= 1) {
                WakeCardCopy(
                    copy: copy,
                    matrix: concept.isMatrix,
                    lf: m.since(m.plan.cardCopyAt),
                    ink: WakePalette.chapterInk,
                    ink2: WakePalette.cardNightInk2,
                    reduce: rm,
                    cardSize: m.cardRect.size
                )
                .opacity(rm ? m.contentOpacity : 1)
                .offset(x: m.cardRect.minX, y: m.cardRect.minY)
            }
        }
    }

    // MARK: Chapters

    private static func style(_ id: WakeBeatID) -> WakeKineticLine.Style {
        switch id {
        case .greet: .rise
        case .commit: .slam
        case .leave: .wipe
        case .mission: .track
        case .day: .drop
        case .week: .stamp
        }
    }

    private func text(for id: WakeBeatID) -> (eyebrow: String, text: String) {
        switch id {
        case .greet: ("", copy.greet)
        case .commit: (copy.commitEyebrow, copy.commit)
        case .leave: ("The plan", copy.leave)
        case .mission: (copy.missionEyebrow, copy.mission)
        case .day: (copy.dayEyebrow, copy.day)
        case .week: (copy.weekEyebrow, copy.week)
        }
    }

    /// One chapter's type: eyebrow and a big kinetic line or two (ui.tsx ChapterText).
    private func chapter(_ id: WakeBeatID, lf: Double, out: Double) -> some View {
        let words = text(for: id)
        let center = concept.isMatrix
        let display = !concept.isMatrix
        let uiWeight: UIFont.Weight = display ? .black : .heavy
        let weight: Font.Weight = display ? .black : .heavy
        let tracking: CGFloat = display ? -0.035 : -0.03
        let lines = WakeTextMetrics.twoLines(words.text, rounded: !display, weight: uiWeight)
        let size = WakeTextMetrics.fit(lines, rounded: !display, weight: uiWeight, max: 62, maxWidth: WakeLayout.designWidth - 56, tracking: tracking) * s
        let o = 1 - E.ez(out / 5)
        let ty = -22 * CGFloat(E.ez(out / 5)) * s
        let eb = rm ? 1 : E.ez((lf - 1) / 8)
        let base = Self.style(id)
        let style: WakeKineticLine.Style = base == .slam && center ? .centerSlam : base
        let alignment: HorizontalAlignment = center ? .center : .leading
        let frameAlignment: Alignment = center ? .center : .leading

        return VStack(alignment: alignment, spacing: 0) {
            if words.eyebrow.isEmpty {
                Color.clear.frame(height: 26 * s)
            } else {
                WakeEyebrow(text: words.eyebrow.uppercased(), f: lf, color: WakePalette.chapterInk2, size: 13 * s, weight: .bold, unit: s, reduce: rm)
                    .opacity(eb)
                    .frame(height: 20 * s)
                    .padding(.bottom, 6 * s)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                WakeKineticLine(
                    text: line,
                    style: style,
                    f: lf - Double(i) * 4,
                    size: size,
                    color: WakePalette.chapterInk,
                    rounded: !display,
                    weight: weight,
                    tracking: tracking,
                    reduce: rm,
                    unit: s
                )
                .frame(height: size * 1.04)
            }
        }
        .frame(width: (WakeLayout.designWidth - 56) * s, alignment: frameAlignment)
        .opacity(o)
        .offset(x: m.ox + 28 * s, y: m.textY + ty)
    }

    // MARK: Progress ticks and the skip hint

    private func bars(b: WakeBeat?) -> some View {
        let beats = m.plan.beats
        let n = max(1, beats.count)
        let index = b?.index ?? n
        let progress = b.map { E.cl((m.t - $0.start) / max(1e-6, $0.end - $0.start)) } ?? 1
        let opacity = b != nil ? E.cl(m.f / 6) : 1 - E.cl((m.f - m.condenseF) / 6)
        let gap = 5 * s
        let total = (WakeLayout.designWidth - 44) * s
        let width = max(1, (total - gap * CGFloat(n - 1)) / CGFloat(n))
        let ink = WakePalette.chapterInk
        return HStack(spacing: gap) {
            ForEach(0..<n, id: \.self) { i in
                let fill: Double = i < index ? 1 : i > index ? 0 : progress
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.2))
                    Capsule().fill(ink).frame(width: width * CGFloat(fill))
                }
                .frame(width: width, height: 3 * s)
            }
        }
        .opacity(opacity)
        .offset(x: m.ox + 22 * s, y: m.barsY)
    }

    private var skipHint: some View {
        let a = 0.36 * E.cl((m.f - 24) / 12) * (1 - E.cl((m.f - m.condenseF) / 6))
        let bottom = max(18 * s, m.insets.bottom + 6)
        return Text("Tap to skip")
            .font(.system(size: 12 * s, weight: .semibold))
            .tracking(0.04 * 12 * s)
            .foregroundStyle(WakePalette.chapterInk.opacity(a))
            .frame(width: m.size.width, height: m.size.height - bottom, alignment: .bottom)
    }

    // MARK: Labels beside the board's objects

    @ViewBuilder
    private func extras(_ id: WakeBeatID, lt: Double, out: Double) -> some View {
        if concept.isMatrix {
            matrixExtras(id, lt: lt, out: out)
        } else {
            ridgeLabels(id, lt: lt, out: out)
        }
    }

    private func point(_ anchor: WakeAnchor, fallback: CGPoint?) -> CGPoint? {
        if let anchors {
            let frame = WakeFrame(t: m.t, plan: m.plan, facts: facts, copy: copy, concept: concept, dark: true, stageRect: m.stageRect, idleT: m.idleT)
            if let p = anchors.anchor(anchor, size: m.size, frame: frame) { return p }
        }
        return fallback
    }

    /// mx2.ts board geometry: 7.5 design units per cell.
    private func cell(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: m.ox + CGFloat(x * 7.5) * s, y: CGFloat(y * 7.5) * s)
    }

    /// MatrixExtras: node labels, the step count, "of 66", the streak.
    @ViewBuilder
    private func matrixExtras(_ id: WakeBeatID, lt: Double, out: Double) -> some View {
        let o = 1 - E.ez(out / 7)
        let ink = WakePalette.chapterInk
        switch id {
        case .leave:
            // mx2.ts NODES and TRACK: the label sits 4.2 cells under the track.
            let nodes: [Double] = [6, 19, 33, 46]
            let labels: [(label: String, value: String?, done: Bool)] = [
                ("Up", nil, true),
                ("Ready", nil, false),
                ("Leave", m.leaveClock, false),
                ("Gym", m.gymClock, false),
            ]
            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { k in
                    if let p = point(.trackNode(k), fallback: cell(nodes[k] + 0.5, 93 + 4.2)) {
                        let a = E.ez((lt - 0.45 - Double(k) * 0.2) / 0.3) * o
                        let row = labels[k]
                        let strong = row.done || k == 2
                        VStack(spacing: 1 * s) {
                            Text(row.label)
                                .font(.system(size: 14 * s, weight: .bold))
                                .foregroundStyle(strong ? ink : ink.opacity(0.6))
                            if let value = row.value {
                                Text(value)
                                    .font(.system(size: 17 * s, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(k == 2 ? ink : ink.opacity(0.6))
                            }
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 80 * s)
                        .opacity(a)
                        .offset(x: p.x - 40 * s, y: p.y + CGFloat(1 - a) * 6 * s)
                    }
                }
            }
        case .mission:
            if facts.missionKind == .steps, let p = point(.stepCounter, fallback: cell(38, 64 + 15.5)) {
                let a = E.ez((lt - 0.5) / 0.4) * o
                caption("OF \(min(24, max(4, facts.missionSteps))) STEPS")
                    .frame(width: 180 * s)
                    .opacity(a)
                    .offset(x: p.x - 90 * s, y: p.y)
            }
        case .day:
            if facts.habitDay <= 66, let p = point(.runCaption, fallback: CGPoint(x: m.size.width / 2, y: CGFloat((76 + 15.5) * 7.5) * s)) {
                let a = E.ez((lt - 0.6) / 0.4) * o
                caption("OF 66")
                    .frame(width: 180 * s)
                    .opacity(a)
                    .offset(x: p.x - 90 * s, y: p.y)
            }
        case .week:
            if let p = point(.weekRow, fallback: CGPoint(x: m.size.width / 2, y: CGFloat((66 + 9) * 7.5) * s)) {
                let a = E.ez((lt - 0.9) / 0.4) * o
                Group {
                    if facts.streakWeeks >= 2 {
                        WakeIntroStreakChip(label: "\(facts.streakWeeks) week streak", scale: 1.15 * s)
                    } else {
                        caption("\(facts.weekDone) OF \(facts.weekGoal)")
                    }
                }
                .frame(width: 300 * s)
                .scaleEffect(CGFloat(0.94 + 0.06 * a))
                .opacity(a)
                .offset(x: p.x - 150 * s, y: p.y + CGFloat(1 - a) * 10 * s)
            }
        default:
            EmptyView()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15 * s, weight: .bold))
            .tracking(0.14 * 15 * s)
            .foregroundStyle(WakePalette.chapterInk.opacity(0.55))
            .lineLimit(1)
            .fixedSize()
    }

    /// ridgeLabels: the big time, the trail tags, the summit, the week as flames.
    @ViewBuilder
    private func ridgeLabels(_ id: WakeBeatID, lt: Double, out: Double) -> some View {
        let o = 1 - E.ez(out / 7)
        switch id {
        case .commit:
            WakeKineticLine(
                text: m.gymClock,
                style: .slam,
                f: lt * 30 - 8,
                size: 132 * s,
                color: WakePalette.chapterInk,
                rounded: false,
                weight: .black,
                tracking: -0.045,
                reduce: rm,
                unit: s
            )
            .opacity(o)
            .offset(x: m.ox + 26 * s, y: 196 * s)
        case .leave:
            ZStack(alignment: .topLeading) {
                if let leave = m.leaveClock, let p = point(.ridgeLeave, fallback: nil) {
                    tag(p, a: E.ez((lt - 1.6) / 0.3) * o, title: "Leave", value: leave, right: true)
                }
                if let p = point(.ridgeGym, fallback: nil) {
                    tag(p, a: E.ez((lt - 1.8) / 0.3) * o, title: facts.gymName ?? "Gym", value: m.gymClock, right: false)
                }
            }
        case .day:
            if facts.habitDay <= 66, let p = point(.ridgeSummit, fallback: nil) {
                tag(p, a: E.ez((lt - 1.6) / 0.3) * o, title: "Day", value: "66", right: true)
            }
        case .week:
            ridgeWeek(lt: lt)
                .opacity(o)
                .frame(width: (WakeLayout.designWidth - 56) * s, alignment: .leading)
                .offset(x: m.ox + 28 * s, y: 248 * s)
        default:
            EmptyView()
        }
    }

    /// A tag beside a point on the trail: a small title over a big value.
    private func tag(_ p: CGPoint, a: Double, title: String, value: String, right: Bool) -> some View {
        let ink = WakePalette.chapterInk
        let stack = VStack(alignment: right ? .leading : .trailing, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 13 * s, weight: .bold))
                .tracking(0.1 * 13 * s)
                .foregroundStyle(ink.opacity(0.7))
            Text(value)
                .font(.system(size: 26 * s, weight: .black))
                .tracking(-0.02 * 26 * s)
                .monospacedDigit()
                .foregroundStyle(ink)
        }
        .lineLimit(1)
        .fixedSize()
        .opacity(a)
        .offset(x: CGFloat(1 - a) * (right ? -8 : 8) * s)

        return Group {
            if right {
                stack.offset(x: p.x + 22 * s, y: p.y - 22 * s)
            } else {
                stack
                    .frame(width: max(0, p.x - 16 * s), alignment: .trailing)
                    .offset(y: p.y - 22 * s)
            }
        }
    }

    /// The week as flames in the sky, and the streak (ridgeLabels 'week').
    private func ridgeWeek(lt: Double) -> some View {
        let n = facts.weekGoal
        let size: CGFloat = (n <= 4 ? 64 : n <= 5 ? 56 : 44) * s
        let ink = WakePalette.chapterInk
        return VStack(alignment: .leading, spacing: 22 * s) {
            HStack(spacing: 0) {
                ForEach(0..<n, id: \.self) { k in
                    let a = rm ? 1 : E.spr(lt - 0.25 - Double(k) * 0.12, w: 13, z: 8)
                    ZStack {
                        if k < facts.weekDone {
                            Circle().fill(Color.white.opacity(0.14))
                            Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            Image(systemName: "flame.fill")
                                .font(.system(size: size * 0.5))
                                .foregroundStyle(WakePalette.flame)
                        } else if k == facts.weekDone {
                            Circle().strokeBorder(ink, lineWidth: 2.5)
                            Circle().fill(ink).frame(width: size * 0.22, height: size * 0.22)
                        } else {
                            Circle().strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }
                    }
                    .frame(width: size, height: size)
                    .scaleEffect(CGFloat(0.6 + 0.4 * a))
                    .opacity(E.cl(a * 2))
                    if k < n - 1 { Spacer(minLength: 0) }
                }
            }
            if facts.streakWeeks >= 2 {
                WakeIntroStreakChip(label: "\(facts.streakWeeks) week streak", scale: 1.1 * s)
                    .opacity(E.ez((lt - 0.9) / 0.4))
            }
        }
    }
}

/// The streak on the dark stage: flame and words in a dark glass capsule (ui.tsx StreakChip, onDark).
/// The app's StreakChip draws ink for the light canvas and only a number, so the intro draws its own.
private struct WakeIntroStreakChip: View {
    let label: String
    /// Points per prototype pixel, including the chip's own scale.
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(WakePalette.flame)
                .shadow(color: Color(red: 1, green: 0.451, blue: 0).opacity(0.45), radius: 4 * scale, y: 1)
            Text(label)
                .font(.system(size: 16 * scale, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WakePalette.chapterInk)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 9 * scale)
        .padding(.horizontal, 14 * scale)
        .background(Color.white.opacity(0.1), in: .capsule)
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
        .shadow(color: .black.opacity(0.25), radius: 5 * scale, y: 4 * scale)
    }
}

// MARK: - The card's copy (stage.tsx CardCopy: card13m for Matrix, card13 for Ridge)

/// The hero card's copy column, in the card's 1000-unit design space scaled to the slot.
private struct WakeCardCopy: View {
    let copy: WakeCopy
    let matrix: Bool
    /// Frames since the card's copy started.
    let lf: Double
    let ink: Color
    let ink2: Color
    let reduce: Bool
    let cardSize: CGSize

    var body: some View {
        let u = cardSize.width / 1000
        let base: CGFloat = matrix ? 92 : 100
        let uiWeight: UIFont.Weight = matrix ? .bold : .black
        let weight: Font.Weight = matrix ? .bold : .black
        let measured = WakeTextMetrics.width(copy.cardHead, rounded: matrix, weight: uiWeight)
        let headSize = min(base, 440 * 100 / max(1, measured)) * u
        let isClock = WakeTextMetrics.isClock(copy.cardHead)
        let sub = E.ez((lf - 9) / 12)

        VStack(alignment: .leading, spacing: 0) {
            WakeEyebrow(
                text: copy.cardEyebrow.uppercased(),
                f: lf,
                color: ink2,
                size: (matrix ? 27 : 24) * u,
                weight: matrix ? .bold : .heavy,
                unit: u,
                reduce: reduce
            )
            .opacity(E.ez((lf - 2) / 7))

            Group {
                if isClock && !reduce {
                    WakeFlipClock(text: copy.cardHead, frac: E.cl((lf - 3) / 18), size: headSize, color: ink, rounded: matrix, weight: weight)
                        .opacity(E.cl((lf - 3) / 4))
                } else {
                    WakeKineticLine(
                        text: copy.cardHead,
                        style: matrix ? .rise : .slam,
                        f: lf,
                        size: headSize,
                        color: ink,
                        rounded: matrix,
                        weight: weight,
                        tracking: matrix ? -0.02 : -0.03,
                        reduce: reduce,
                        unit: u
                    )
                }
            }
            .padding(.top, 8 * u)

            Text(subText)
                .font(.system(size: (matrix ? 35 : 32) * u, weight: .medium))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 430 * u, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(sub)
                .offset(y: CGFloat(1 - sub) * 10 * u)
                .padding(.top, 10 * u)
        }
        .frame(width: 470 * u, alignment: .leading)
        .padding(.leading, 52 * u)
        .frame(width: cardSize.width, height: cardSize.height, alignment: .leading)
    }

    /// `**bold**` runs bold in ink, the rest medium in the secondary ink (one Text, as AccentedText).
    private var subText: AttributedString {
        var out = AttributedString()
        for (i, part) in copy.cardSub.components(separatedBy: "**").enumerated() {
            var run = AttributedString(part)
            let bold = i % 2 == 1
            if bold { run.inlinePresentationIntent = .stronglyEmphasized }
            run.foregroundColor = bold ? ink : ink2
            out.append(run)
        }
        return out
    }
}

// MARK: - Clips

/// The stage's rounded rect, in the page's coordinates.
private struct WakeStageClip: Shape {
    let rect: CGRect
    let radius: CGFloat

    func path(in _: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
}

/// The diagonal band the card's day look is revealed through (stage.tsx clipPath polygon).
private struct WakeWipeBand: Shape {
    let card: CGRect
    let progress: Double
    let s: CGFloat

    func path(in bounds: CGRect) -> Path {
        let w = CGFloat(progress)
        let span = card.width + 200 * s
        var path = Path()
        path.move(to: CGPoint(x: card.minX - 80 * s, y: 0))
        path.addLine(to: CGPoint(x: card.minX - 80 * s + span * w, y: 0))
        path.addLine(to: CGPoint(x: card.minX - 160 * s + span * w, y: bounds.height))
        path.addLine(to: CGPoint(x: card.minX - 160 * s, y: bounds.height))
        path.closeSubpath()
        return path
    }
}

/// The wipe, or under Reduce Motion a 200 ms crossfade.
private struct WakeWipe: ViewModifier {
    let m: WakeMoment

    @ViewBuilder
    func body(content: Content) -> some View {
        if m.plan.reduceMotion {
            content.opacity(m.wipe)
        } else {
            content.clipShape(WakeWipeBand(card: m.cardRect, progress: m.wipe, s: m.s))
        }
    }
}

// MARK: - The settled page (settled.tsx, in the app's components)

/// Page entrance: 0.97 and opacity, travelling 16 pt up on Theme.settle (UI-RULES 5.5, 5.6).
/// Reduce Motion: a 200 ms fade, nothing travels.
private struct WakeEntrance: ViewModifier {
    let f: Double
    /// The cue, in frames.
    let at: Double
    let reduce: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduce {
            content.opacity(E.cl((f - at) / 6))
        } else {
            let k = (f - at) / 30
            let p = E.settle(k / 0.55)
            content
                .opacity(E.ez(k / 0.3))
                .scaleEffect(CGFloat(0.97 + 0.03 * p))
                .offset(y: CGFloat(1 - p) * 16)
        }
    }
}

/// A size that follows Dynamic Type (the page caps Dynamic Type itself).
private struct WakeFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(_ size: CGFloat, _ weight: Font.Weight, design: Font.Design = .default, relativeTo style: Font.TextStyle = .body) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

private extension View {
    func wakeFont(_ size: CGFloat, _ weight: Font.Weight, design: Font.Design = .default, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(WakeFont(size, weight, design: design, relativeTo: style))
    }

    func wakeEntrance(_ m: WakeMoment, at frame: Double) -> some View {
        modifier(WakeEntrance(f: m.f, at: frame, reduce: m.plan.reduceMotion))
    }
}

private struct WakeSettledPage: View {
    let m: WakeMoment
    let facts: WakeFacts
    let copy: WakeCopy
    let concept: WakeConcept
    let look: WakeLook
    let showsLockLine: Bool
    let onSlot: (CGRect) -> Void
    let onPrimary: () -> Void
    let onPlansChanged: () -> Void

    private var stagger: Double { m.plan.staggerAt * WakePlan.fps }

    var body: some View {
        // The page is laid out in design units: 390 wide, as tall as the screen is at the shared scale
        // (844 when the height sets the scale, so SE, 15 and Pro Max all lay out the same 390 x 844
        // page), then scaled uniformly and centred in the column. It scrolls only if it must.
        let s = m.s
        let design = CGSize(width: WakeLayout.designWidth, height: m.size.height / s)
        ViewThatFits(in: .vertical) {
            column(scrolls: false)
            ScrollView(.vertical) {
                column(scrolls: true)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .ignoresSafeArea()
        .frame(width: design.width, height: design.height)
        .coordinateSpace(.named(WakeLayout.designSpace))
        .scaleEffect(s, anchor: .topLeading)
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .offset(x: m.ox)
        .ignoresSafeArea()
    }

    private func column(scrolls: Bool) -> some View {
        VStack(spacing: 0) {
            header
                .wakeEntrance(m, at: stagger)

            slot
                .padding(.top, 8)

            module
                .padding(.top, 19)

            if scrolls {
                Color.clear.frame(height: 24)
            } else {
                Spacer(minLength: 16)
            }

            if showsLockLine {
                fineLine
                    .wakeEntrance(m, at: stagger + 10)
            }

            primary
                .padding(.top, 14)
                .wakeEntrance(m, at: stagger + 12)

            plansLink
                .padding(.top, 4)
                .wakeEntrance(m, at: stagger + 14)
        }
        .padding(.horizontal, 18)
        // safe-area insets are screen points; the column is in design units
        .padding(.top, m.insets.top / m.s + 2)
        .padding(.bottom, max(m.insets.bottom / m.s, 10))
    }

    // MARK: Header: "Today" and the streak, as on Home

    private var header: some View {
        HStack(alignment: .center) {
            Text("Today")
                .wakeFont(28, .bold, relativeTo: .largeTitle)
                .tracking(-0.28)
                .foregroundStyle(look.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if facts.streakWeeks >= 1 {
                StreakChip(streak: facts.streakWeeks)
            }
        }
        .padding(.leading, 4)
        .frame(minHeight: 48)
    }

    // MARK: The card's slot (the stage draws the card into it)

    private var slot: some View {
        Color.clear
            .aspectRatio(WakeLayout.cardAspect, contentMode: .fit)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGRect.self) { [ox = m.ox, s = m.s] proxy in
                // design units to page space (the stage condenses into this rect); the scale is part
                // of the value, so a change of screen size re-reports it
                let r = proxy.frame(in: .named(WakeLayout.designSpace))
                return CGRect(x: ox + r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
            } action: { rect in
                onSlot(rect)
            }
            .accessibilityElement()
            .accessibilityLabel([copy.cardEyebrow, copy.cardHead, copy.cardSubPlain].joined(separator: ", "))
    }

    // MARK: Module: the plan (A) or the week and the run (B)

    @ViewBuilder
    private var module: some View {
        if concept.isPlan {
            WakeMorningTimeline(m: m, facts: facts, look: look, stagger: stagger)
                .wakeEntrance(m, at: stagger + 2)
        } else {
            VStack(spacing: 12) {
                WakeWeekCard(m: m, facts: facts, copy: copy, look: look, stagger: stagger)
                    .wakeEntrance(m, at: stagger + 2)
                WakeRunCard(m: m, facts: facts, look: look, stagger: stagger)
                    .wakeEntrance(m, at: stagger + 4)
            }
        }
    }

    // MARK: Fine print, the mission, plans changed

    private var fineLine: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .wakeFont(13, .semibold, relativeTo: .subheadline)
            Text(copy.fine)
                .wakeFont(15, .medium, relativeTo: .subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(look.ink2)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var missionLabel: String {
        facts.missionTitle.hasSuffix(".") ? String(facts.missionTitle.dropLast()) : facts.missionTitle
    }

    private var primary: some View {
        Button(action: onPrimary) {
            HStack(spacing: 14) {
                Image(systemName: WakeFactsProvider.symbol(for: facts.missionKind))
                    .wakeFont(18, .semibold, relativeTo: .headline)
                    .frame(width: 40, height: 40)
                    .background(look.buttonInk.opacity(0.16), in: .circle)
                Text(missionLabel)
                    .wakeFont(19, .bold, relativeTo: .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .wakeFont(17, .bold, relativeTo: .headline)
                    .opacity(0.9)
            }
            .foregroundStyle(look.buttonInk)
            .padding(.leading, 13)
            .padding(.trailing, 22)
            .frame(maxWidth: .infinity, minHeight: 66)
        }
        .buttonStyle(WakePrimaryCapsuleStyle(fill: look.button))
        .accessibilityLabel(missionLabel)
        .accessibilityHint("Starts your mission")
    }

    private var plansLink: some View {
        Button(action: onPlansChanged) {
            Text("Plans changed")
                .wakeFont(16, .semibold)
                .foregroundStyle(look.ink2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The warm card in either look (Theme.surface, radius 24, hairline, soft lift; dark: a hairline only).
private struct WakeWarmCard: ViewModifier {
    let look: WakeLook

    func body(content: Content) -> some View {
        content
            .background(look.card, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(look.dark ? look.hair : look.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(look.dark ? 0 : 0.05), radius: 8, y: 6)
    }
}

/// A: the morning as a track. Up (done), Get ready (now), Leave, the gym. The current stop breathes
/// and a soft light travels the line every 6 s (on the 12 s loop); nothing moves under Reduce Motion.
private struct WakeMorningTimeline: View {
    let m: WakeMoment
    let facts: WakeFacts
    let look: WakeLook
    let stagger: Double

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 62

    private enum Stop { case done, now, next }
    private struct Row {
        let label: String
        let value: String
        let state: Stop
        let strong: Bool
    }

    private var rows: [Row] {
        var rows = [
            Row(label: "Up", value: "done", state: .done, strong: false),
            Row(label: "Get ready", value: "now", state: .now, strong: false),
        ]
        // No leave-by: the row is dropped (settled.tsx `rows.splice(2, 1)`).
        if let leave = m.leaveClock {
            rows.append(Row(label: "Leave", value: leave, state: .next, strong: false))
        }
        rows.append(Row(label: facts.gymName ?? "Gym", value: m.gymClock, state: .next, strong: true))
        return rows
    }

    private let pad: CGFloat = 18
    /// The node column's centre, from the card's leading edge.
    private var nodeX: CGFloat { pad + 22 }

    var body: some View {
        let list = rows
        let live = m.t >= m.plan.introEnd && !m.plan.reduceMotion
        let t = m.idleT
        let breathe = live ? 0.5 - 0.5 * cos(t / 3 * 2 * .pi) : 0
        let travel = live ? (t.truncatingRemainder(dividingBy: 6) / 6) * 1.6 - 0.3 : -1
        let n = CGFloat(list.count)
        let ink = look.ink

        ZStack(alignment: .topLeading) {
            // The line, the part already walked, and the travelling light.
            Capsule()
                .fill(look.line)
                .frame(width: 2, height: rowHeight * (n - 1))
                .offset(x: nodeX - 1, y: pad + rowHeight / 2)
            Capsule()
                .fill(ink)
                .frame(width: 2, height: rowHeight)
                .offset(x: nodeX - 1, y: pad + rowHeight / 2)
            if travel > 0 && travel < 1 {
                Capsule()
                    .fill(LinearGradient(colors: [ink.opacity(0), ink.opacity(0.55), ink.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 28)
                    .offset(x: nodeX - 2, y: pad + rowHeight * 1.5 + CGFloat(travel) * rowHeight * (n - 2) - 14)
            }

            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, row in
                    rowView(row, breathe: breathe)
                        .frame(height: rowHeight)
                        .wakeEntrance(m, at: stagger + 2 + Double(i))
                }
            }
            .padding(.horizontal, pad)
            .padding(.vertical, pad)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(WakeWarmCard(look: look))
        .accessibilityElement(children: .combine)
    }

    private func rowView(_ row: Row, breathe: Double) -> some View {
        let isTime = row.state == .next
        return HStack(spacing: 0) {
            node(row.state, breathe: breathe)
                .frame(width: 44)
            Text(row.label)
                .wakeFont(row.state == .now ? 19 : 17, row.state == .now || row.strong ? .bold : .semibold)
                .foregroundStyle(row.state == .done ? look.ink2 : look.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 10)
            Spacer(minLength: 8)
            Group {
                if isTime {
                    Text(row.value)
                        .wakeFont(row.strong ? 26 : 22, .heavy, design: .rounded)
                        .tracking(-0.02 * (row.strong ? 26 : 22))
                        .monospacedDigit()
                } else {
                    Text(row.value)
                        .wakeFont(15, .semibold)
                }
            }
            .foregroundStyle(row.state == .done ? look.ink2 : look.ink)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func node(_ state: Stop, breathe: Double) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(look.card)
                .frame(width: 26, height: 26)
                .background(look.ink, in: .circle)
        case .now:
            ZStack {
                Circle()
                    .stroke(look.ink.opacity(0.25 * (1 - breathe)), lineWidth: 1.5)
                    .frame(width: 26 + 12 * breathe, height: 26 + 12 * breathe)
                Circle().fill(look.card).frame(width: 26, height: 26)
                Circle().strokeBorder(look.ink, lineWidth: 2).frame(width: 26, height: 26)
                Circle().fill(look.ink).frame(width: 10, height: 10)
            }
        case .next:
            Circle()
                .fill(look.card)
                .overlay { Circle().strokeBorder(look.nodeRing, lineWidth: 1.5) }
                .frame(width: 18, height: 18)
        }
    }
}

/// B: this week. Filled flames for counted sessions, a solid ring for today, dashed for the rest
/// (CalendarStripView's markers), the week's line under it.
private struct WakeWeekCard: View {
    let m: WakeMoment
    let facts: WakeFacts
    let copy: WakeCopy
    let look: WakeLook
    let stagger: Double

    var body: some View {
        let n = facts.weekGoal
        let size: CGFloat = n <= 4 ? 52 : n <= 5 ? 46 : 38
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .wakeFont(17, .bold)
                    .foregroundStyle(look.ink)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("\(facts.weekDone)")
                        .wakeFont(17, .heavy, design: .rounded)
                        .foregroundStyle(look.ink)
                    Text("of \(n)")
                        .wakeFont(17, .bold, design: .rounded)
                        .foregroundStyle(look.ink2)
                }
                .monospacedDigit()
            }

            HStack(spacing: 0) {
                ForEach(0..<n, id: \.self) { k in
                    marker(k, size: size)
                    if k < n - 1 { Spacer(minLength: 4) }
                }
            }

            Text(copy.affirm ?? copy.week)
                .wakeFont(15, .semibold)
                .foregroundStyle(look.ink2)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WakeWarmCard(look: look))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week, \(facts.weekDone) of \(n). \(copy.affirm ?? copy.week)")
    }

    private func marker(_ k: Int, size: CGFloat) -> some View {
        let at = stagger + 3 + Double(k) * 2
        let pop = m.plan.reduceMotion ? E.cl((m.f - at) / 6) : E.spr((m.f - at) / 30, w: 13, z: 8)
        return ZStack {
            if k < facts.weekDone {
                Circle().fill(look.ink)
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.46))
                    .foregroundStyle(WakePalette.flame)
            } else if k == facts.weekDone {
                Circle().strokeBorder(look.ink, lineWidth: 2)
                Text("today")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(look.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(3)
            } else {
                Circle().strokeBorder(look.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(CGFloat(0.9 + 0.1 * pop))
        .opacity(E.cl((m.f - at) / 4))
    }
}

/// B: the 66-day run. Lived days filled, today tall, the rest to come; a slow sheen passes every 6 s.
private struct WakeRunCard: View {
    let m: WakeMoment
    let facts: WakeFacts
    let look: WakeLook
    let stagger: Double

    var body: some View {
        let day = facts.habitDay
        let rm = m.plan.reduceMotion
        let live = m.t >= m.plan.introEnd && !rm
        let fill = rm ? 1 : E.ez((m.f - stagger - 6) / 24)
        let sweep = live ? (m.idleT.truncatingRemainder(dividingBy: 6) / 6) * 1.4 - 0.2 : -9
        let lived = Double(min(66, day - 1))
        let ink = look.ink
        let off = look.tickOff
        let beyond = day > 66

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Day \(day)")
                    .wakeFont(40, .heavy, design: .rounded, relativeTo: .largeTitle)
                    .tracking(-1.2)
                    .monospacedDigit()
                    .foregroundStyle(look.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !beyond {
                    Text("of 66")
                        .wakeFont(17, .semibold)
                        .foregroundStyle(look.ink2)
                }
            }

            Canvas { ctx, size in
                let step = size.width / 66
                let barWidth = max(2, step - 1.8)
                for k in 0..<66 {
                    let isToday = !beyond && k == min(66, day) - 1
                    let on = Double(k) < lived * fill || beyond
                    let u = Double(k) / 65
                    let sheen = exp(-pow((u - sweep) / 0.06, 2))
                    let height: CGFloat = isToday ? 26 : on ? 18 : 12
                    let rect = CGRect(x: CGFloat(k) * step, y: size.height - height, width: barWidth, height: height)
                    let color: Color = isToday ? ink : on ? ink.opacity(0.78 + 0.22 * sheen) : off
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                }
            }
            .frame(height: 26)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WakeWarmCard(look: look))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(beyond ? "Day \(day)" : "Day \(day) of 66")
    }
}

// MARK: - The primary capsule

/// The mission capsule: ink-tinted Liquid Glass on iOS 26, a solid ink capsule with a springy press
/// on iOS 18 and under Reduce Transparency. The same mechanics as AlarmGlassCapsuleButtonStyle, in
/// ink instead of coral so the card's coral stays the page's one accent (RESEARCH §4.2, conflict 5).
struct WakePrimaryCapsuleStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        WakePrimaryCapsuleBody(configuration: configuration, fill: fill)
    }
}

private struct WakePrimaryCapsuleBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            configuration.label
                .contentShape(.capsule)
                .glassEffect(.regular.tint(fill).interactive(), in: .capsule)
        } else {
            let pressed = configuration.isPressed
            configuration.label
                .background(fill.opacity(pressed ? 0.88 : 1), in: .capsule)
                .contentShape(.capsule)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 10)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .animation(
                    pressed
                        ? .spring(response: 0.18, dampingFraction: 0.9)
                        : .spring(response: 0.42, dampingFraction: 0.6),
                    value: pressed
                )
        }
    }
}

#if DEBUG
#Preview("Wake page, Ridge A") {
    WakeIntroView(
        concept: .ridgeA,
        facts: WakeFacts(
            name: "Sam",
            gymName: "Northside Gym",
            gymTime: Calendar.current.date(bySettingHour: 7, minute: 5, second: 0, of: Date()) ?? Date(),
            leaveBy: nil,
            missionTitle: "Take 20 steps",
            missionKind: .steps,
            missionSteps: 20,
            weekDone: 2,
            weekGoal: 4,
            habitDay: 23,
            streakWeeks: 3,
            isFirst: false,
            isComeback: false,
            snoozed: false
        ),
        onPrimary: {},
        onPlansChanged: {}
    )
}
#endif
