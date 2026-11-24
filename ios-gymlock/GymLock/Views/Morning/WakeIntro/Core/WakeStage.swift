//
//  WakeStage.swift
//  GymLock · the "I'm up" wake page (native port of web/morning2)
//
//  The shared contract between the page (WakeIntroView, owned by Core) and the two visual stages
//  (MatrixWakeStage, RidgeWakeStage), plus everything the three have to agree on:
//
//    - the plan:   an exact port of plan.ts `buildPlan` (30 fps frames converted to seconds)
//    - the copy:   an exact port of model.ts `facts`, `weekLine` and `copyFor`
//    - easing:     plan.ts `cl lerp ez ez5 eio settle spr`, plus kin13's `back` and `ramp`
//
//  Coordinate rules every renderer can rely on:
//    - `draw` is called with the Canvas's own context and size. The Canvas fills the whole screen,
//      safe areas included, so `size` is the screen and (0, 0) is its top-left corner.
//    - The intro is designed on a 390 pt wide phone and scaled uniformly by `WakeLayout.fit(size).scale` (min of width/390, height/844, 1.25),
//      top-aligned in one centred column (`WakeLayout.fit`: scale = min(width/390, height/844, 1.25)).
//      Every device shows the same composition; the stage and backgrounds stay full-bleed.
//    - `frame.stageRect` is the rect to draw in: the full screen during the chapters, contracting
//      into the hero card's slot during the condense, and exactly the card's slot once settled. The
//      page has already clipped the context to it (rounded) and filled the stage colour behind it.
//    - `frame.dark` is the look to draw in. The page passes `true` (night look on the dark stage) for
//      every pass, and in light appearance adds a second pass with `false` (the day look: ink on
//      Theme.surface) inside the card while the card wipes to its day look. A renderer can be called
//      twice in one frame with the same `t`, so stepping must be idempotent per `t`.
//    - Text is not the renderer's job. The page draws every word, including the labels that sit next
//      to board objects; a renderer that knows where those objects are can say so by also conforming
//      to `WakeStageAnchoring` (optional).
//
//  Depends on: SwiftUI, UIKit (only for the locale's 12/24 hour setting). Nothing else in the app.
//

import SwiftUI

// MARK: - The contract (verbatim)

/// Which wake page plays. A = the plan (place, time, leave, the next act), B = progress (the 66-day
/// run and the week).
enum WakeConcept: String, CaseIterable { case matrixA, matrixB, ridgeA, ridgeB }  // A = plan, B = progress

/// One full-screen chapter of the intro.
enum WakeBeatID { case greet, commit, leave, mission, day, week }

/// A chapter on the intro clock, in seconds since the page started.
struct WakeBeat: Equatable { let id: WakeBeatID; let start: Double; let end: Double; let index: Int }   // seconds

/// The two "Shoes on." drawings on the Matrix page: the runner in profile, or lacing up from above.
enum WakeShoeArt: String { case profile, laceUp }

/// What the mission's visual shows (plan.ts `missionKind`).
enum WakeMissionKind { case steps, bag, water, shoe }

/// Which impact a cue plays (WakeHaptics maps them to UIImpactFeedbackGenerator).
enum WakeHapticKind { case soft, medium, heavy }

/// One haptic on the intro clock.
struct WakeHaptic: Equatable { let t: Double; let kind: WakeHapticKind }

/// The intro's timeline, in seconds. Build it with `WakePlan.build(concept:facts:reduceMotion:)`.
struct WakePlan: Equatable {
    /// The chapters, in order.
    let beats: [WakeBeat]
    /// The visual starts contracting into the card's slot.
    let condenseAt: Double
    /// The card is in its slot.
    let landAt: Double
    /// Light appearance: the card wipes from its night look to its day look.
    let wipe: ClosedRange<Double>
    /// The settled page starts arriving under the card.
    let staggerAt: Double
    /// The intro is over; the calm idle loop runs from here.
    let introEnd: Double
    /// The settled page loops a 12 s idle; every idle motion divides it.
    var idleLength: Double = 12.0
    /// One cue per chapter plus the card landing (one heavy only, under Reduce Motion).
    let haptics: [WakeHaptic]
    /// Built for Reduce Motion: chapters swap by short crossfades, nothing travels or scales.
    let reduceMotion: Bool

    /// The chapter on screen at `t`, nil once the stage is condensing.
    func beat(at t: Double) -> WakeBeat? {
        guard t < condenseAt, var current = beats.first else { return nil }
        for candidate in beats where t >= candidate.start { current = candidate }
        return current
    }

    /// How far the stage has contracted into the card's slot: 0 full screen, 1 in the slot.
    /// Slow out of the gate so the visual leads the edges (plan.ts `condenseK`). Under Reduce Motion
    /// it cuts, 0.1 s after the condense starts, while the stage is empty.
    func condenseProgress(at t: Double) -> Double {
        if reduceMotion { return t >= condenseAt + 3.0 / WakePlan.fps ? 1 : 0 }
        return WakeEase.eio((t - condenseAt) / max(1e-6, landAt - condenseAt))
    }
}

/// The real data behind the page. Build it with `WakeFactsProvider` (Core) from the app state; the
/// page normalises it (`normalized()`) exactly as model.ts `facts()` does before anything reads it.
struct WakeFacts: Equatable {
    /// The user's name, only when they gave one (`AppStore.hasName`). Never "friend".
    var name: String?
    var gymName: String?
    /// When the user is due at the gym.
    var gymTime: Date
    /// When to leave. Nil when the app has no travel time, and the copy then says "Gym by".
    var leaveBy: Date?
    /// Sentence case, e.g. "Take 20 steps".
    var missionTitle: String
    var missionKind: WakeMissionKind
    /// Steps for a steps mission (1 to 40), 0 otherwise.
    var missionSteps: Int
    /// Counted sessions this week, before today's.
    var weekDone: Int
    /// This week's goal (the planned days).
    var weekGoal: Int
    /// Day of the 66-day habit run (1 on the first day).
    var habitDay: Int
    var streakWeeks: Int
    var isFirst: Bool
    var isComeback: Bool
    var snoozed: Bool
    /// False when persistent mode is off: there is no mission, and the capsule just says "Let's go".
    var hasMission: Bool = true
    /// Which shoe the Matrix "Shoes on." chapter draws. The two take turns (WakeShoeRotation).
    var shoeArt: WakeShoeArt = .profile

    /// The gym time as the prototype writes it: "7:05" (12-hour locales drop the AM/PM, 24-hour
    /// locales give "18:00").
    var gymClock: String { WakeClockText.string(gymTime) }
    /// The leave-by time in the same style, nil when there is none.
    var leaveClock: String? { leaveBy.map { WakeClockText.string($0) } }
}

/// Every word of the intro and the settled page (model.ts `copyFor`). Build it with
/// `WakeCopy.make(concept:facts:)`.
struct WakeCopy {
    var greet: String
    var commitEyebrow: String
    /// The place. The time is the big component of the chapter.
    var commit: String
    /// "Leave by 6:50." or "Gym by 7:05."
    var leave: String
    var missionEyebrow: String
    var mission: String
    var dayEyebrow: String
    var day: String
    var weekEyebrow: String
    var week: String
    var streak: String?
    // The settled card.
    var cardEyebrow: String
    var cardHead: String
    /// Contains `**bold**` runs, as the prototype does.
    var cardSub: String
    // The settled page.
    var fine: String
    var affirm: String?
}

/// Everything a renderer needs for one drawn frame.
struct WakeFrame {
    /// Seconds since the page started (the intro clock; it keeps running through the idle loop).
    let t: Double
    let plan: WakePlan
    /// Normalised facts.
    let facts: WakeFacts
    let copy: WakeCopy
    let concept: WakeConcept
    /// The look to draw in: true = night (the intro, and the card in dark appearance),
    /// false = the day look of the card in light appearance. The intro itself is always dark.
    let dark: Bool /* appearance of the settled page; intro is always dark */
    /// Full screen during chapters, shrinking to the card slot during condense, the card rect when settled.
    let stageRect: CGRect /* full screen during chapters, shrinking to the card slot during condense, the card rect when settled */
    /// Seconds into the 12 s idle loop, 0 before settle.
    let idleT: Double /* seconds into the 12 s idle loop, 0 before settle */
}

/// The visual stage: dots (Matrix) or the painted landscape (Ridge).
protocol WakeStageRenderer: AnyObject { init(); func draw(_ ctx: inout GraphicsContext, size: CGSize, frame: WakeFrame) }   // draws ONLY the visual (dots / landscape) for the current time inside frame.stageRect; text is not its job

// MARK: - Optional: where the words go

/// Points the page anchors its labels to. Matrix points are the top-centre of the label's first line;
/// Ridge points are the object itself (the tag sits beside it, prototype `ridgeLabels`).
enum WakeAnchor: Hashable {
    /// Matrix A, the morning track: node 0 (Up), 1 (Ready), 2 (Leave), 3 (Gym).
    case trackNode(Int)
    /// Matrix A, the LED step counter beside the march ("OF 20 STEPS").
    case stepCounter
    /// Matrix B, under the run's big day number ("OF 66").
    case runCaption
    /// Matrix B, under the week row (the streak chip or "2 OF 4").
    case weekRow
    /// Ridge A, the point on the walk where the user leaves.
    case ridgeLeave
    /// Ridge A, the gym at the end of the trail.
    case ridgeGym
    /// Ridge B, the summit (day 66).
    case ridgeSummit
}

/// A renderer that knows where its objects are on screen this frame (after its own camera moves).
/// When a renderer does not conform, Matrix labels fall back to the prototype's board geometry and
/// Ridge tags are left out rather than guessed.
protocol WakeStageAnchoring: AnyObject {
    func anchor(_ anchor: WakeAnchor, size: CGSize, frame: WakeFrame) -> CGPoint?
}

// MARK: - Concept helpers

extension WakeConcept {
    /// A concepts tell the plan; B concepts tell progress.
    var isPlan: Bool { self == .matrixA || self == .ridgeA }
    var isMatrix: Bool { self == .matrixA || self == .matrixB }
}

extension WakeHapticKind {
    /// When two cues land in one frame the strongest plays.
    var rank: Int {
        switch self {
        case .soft: 0
        case .medium: 1
        case .heavy: 2
        }
    }
}

// MARK: - Layout shared by the page and the renderers

nonisolated enum WakeLayout {
    /// The coordinate space the page's stage and the card's slot share (the page's full-screen root).
    static let pageSpace = "gymlock.wake.page"
    /// The prototype's phone.
    static let designWidth: CGFloat = 390
    static let designHeight: CGFloat = 844
    /// The coordinate space the settled page is laid out in (390 x height/scale design units), inside
    /// its uniform scale. Frames measured in it convert to page space with `fit`.
    static let designSpace = "gymlock.wake.design"
    /// The largest scale: on an iPad the page is a centred phone column, not a stretched phone.
    static let maxScale: CGFloat = 1.25
    /// The ONE fit every layer uses (words, card slot, buttons, Matrix board, Ridge overlays and
    /// anchors): the 390 x 844 design box, uniformly scaled so it fits the screen both ways (capped at
    /// `maxScale`), top-aligned, and centred horizontally in a column of 390 * scale. Backgrounds and the
    /// stage still fill the whole screen. Nothing in the design sits below y = 844, so nothing overflows.
    static func fit(_ size: CGSize) -> (scale: CGFloat, originX: CGFloat) {
        let w = max(1, size.width), h = max(1, size.height)
        let scale = max(0.1, min(w / designWidth, h / designHeight, maxScale))
        return (scale, max(0, (w - designWidth * scale) / 2))
    }
    /// Points per design unit on this screen (`fit(size).scale`).
    static func designScale(_ size: CGSize) -> CGFloat { fit(size).scale }
    /// The hero card's proportion (HeroMetrics.aspect; the prototype's 1000 x 488 card is the same).
    static let cardAspect: CGFloat = 2.05
    /// The card's corner radius once settled (Theme.cardRadius).
    static let cardRadius: CGFloat = 24
    /// The prototype's card slot on a 390 x 844 phone, for anything that needs it before layout.
    static func fallbackCardRect(_ size: CGSize, topInset: CGFloat) -> CGRect {
        let f = fit(size)
        let width = (designWidth - 36) * f.scale
        return CGRect(x: f.originX + 18 * f.scale, y: topInset + 58 * f.scale, width: width, height: width / cardAspect)
    }
}

// MARK: - Easing (plan.ts and kin13, verbatim)

nonisolated enum WakeEase {
    static func cl(_ x: Double) -> Double { min(1, max(0, x)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    /// Ease out, cubic.
    static func ez(_ x: Double) -> Double { 1 - pow(1 - cl(x), 3) }
    /// Ease out, quintic.
    static func ez5(_ x: Double) -> Double { 1 - pow(1 - cl(x), 5) }
    /// Ease in-out, cubic.
    static func eio(_ x: Double) -> Double {
        let k = cl(x)
        return k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
    }
    /// Theme.settle, timingCurve(0.22, 0.9, 0.24, 1), approximated as in the prototype.
    static func settle(_ x: Double) -> Double { 1 - pow(1 - cl(x), 3.6) }
    /// A spring 0 to 1 from x = 0 (seconds), small overshoot. plan.ts defaults w 13, z 7; kin13 uses z 6.
    static func spr(_ x: Double, w: Double = 13, z: Double = 7) -> Double {
        x <= 0 ? 0 : 1 - exp(-x * z) * cos(x * w)
    }
    /// kin13 `back`: overshoots and settles.
    static func back(_ x: Double, _ k: Double = 1.7) -> Double {
        let t = cl(x) - 1
        return 1 + (k + 1) * t * t * t + k * t * t
    }
    /// plan.ts `ramp`, in seconds: eased progress from `a` to `b` (at least one frame long).
    static func ramp(_ t: Double, _ a: Double, _ b: Double, _ ease: (Double) -> Double = { WakeEase.settle($0) }) -> Double {
        // 1/30 s: one prototype frame. Written out because this enum is nonisolated and must not
        // reach into the (default-isolated) contract types.
        ease((t - a) / max(1.0 / 30.0, b - a))
    }
    /// Seconds into the idle loop, 0 before the intro ends.
    static func idleT(_ t: Double, introEnd: Double, length: Double) -> Double {
        guard t >= introEnd, length > 0 else { return 0 }
        let x = (t - introEnd).truncatingRemainder(dividingBy: length)
        return x < 0 ? x + length : x
    }
}

// MARK: - The plan (plan.ts buildPlan, verbatim)

extension WakeBeatID {
    /// Chapter length in frames at 30 fps (plan.ts `LEN`).
    var frameLength: Int {
        switch self {
        case .greet: 66
        case .commit: 72
        case .leave: 68
        case .mission: 66
        case .day: 68
        case .week: 68
        }
    }
}

extension WakePlan {
    /// The prototype's clock rate. Every frame number in the port is divided by this.
    static let fps: Double = 30

    /// The intro as full-screen chapters on one clock:
    ///   A (plan):      greet, commit (place and time), leave (the morning track), mission (the next act)
    ///   B (progress):  greet, commit, day (the 66-day run), week (the week and the streak)
    ///   Snoozed:       no greeting, one plan or progress chapter, about 6.5 s
    ///   Reduce Motion: chapters swap by short crossfades, no travel or scale, about 3 s
    static func build(concept: WakeConcept, facts: WakeFacts, reduceMotion rm: Bool) -> WakePlan {
        let snoozed = facts.snoozed
        var ids: [WakeBeatID] = []
        if !snoozed && !rm { ids.append(.greet) }
        ids.append(.commit)
        if concept.isPlan {
            ids.append(.leave)
            if !(snoozed || rm) { ids.append(.mission) }
        } else {
            ids.append(.day)
            if !(snoozed || rm) { ids.append(.week) }
        }

        func sec(_ frames: Int) -> Double { Double(frames) / fps }

        var f = rm ? 0 : 6
        var beats: [WakeBeat] = []
        for (i, id) in ids.enumerated() {
            let length = rm ? 36 : id.frameLength - (snoozed ? 6 : 0)
            beats.append(WakeBeat(id: id, start: sec(f), end: sec(f + length), index: i))
            f += length
        }
        let condense = f
        let land = condense + (rm ? 3 : 24)
        // Reduce Motion: the dark around the card and the card itself go to the day look in one 200 ms crossfade.
        let wipeFrom = land
        let wipeTo = rm ? land + 6 : land + 12
        // The page arrives only once the card has landed.
        let stagger = rm ? land + 6 : land + 8
        let intro = stagger + (rm ? 12 : 30)

        let haptics: [WakeHaptic]
        if rm {
            haptics = [WakeHaptic(t: sec(2), kind: .heavy)]
        } else {
            haptics = beats.map { (beat: WakeBeat) -> WakeHaptic in
                let isCommit = beat.id == .commit
                return WakeHaptic(t: beat.start + sec(isCommit ? 10 : 8), kind: isCommit ? .heavy : .soft)
            } + [WakeHaptic(t: sec(land), kind: .medium)]
        }

        return WakePlan(
            beats: beats,
            condenseAt: sec(condense),
            landAt: sec(land),
            wipe: sec(wipeFrom)...sec(wipeTo),
            staggerAt: sec(stagger),
            introEnd: sec(intro),
            haptics: haptics,
            reduceMotion: rm
        )
    }

    /// The card's own copy starts arriving while the stage is still contracting (plan.ts `copyAt`).
    var cardCopyAt: Double { condenseAt + (reduceMotion ? 9 : 10) / WakePlan.fps }

    /// The chapter with this id, if the plan has one.
    func beat(_ id: WakeBeatID) -> WakeBeat? { beats.first { $0.id == id } }
}

// MARK: - Facts (model.ts facts, verbatim)

extension WakeFacts {
    /// model.ts `facts()`: trims the words, keeps the numbers in range, and applies the first-time rules
    /// (day 1, nothing done, no streak). Idempotent.
    func normalized() -> WakeFacts {
        func clean(_ s: String?) -> String? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{2014}", with: "-")
                .replacingOccurrences(of: "\u{2013}", with: "-")
            return t.isEmpty ? nil : t
        }
        func int(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }

        var f = self
        f.name = clean(name)
        f.gymName = clean(gymName)
        f.missionTitle = clean(missionTitle) ?? missionTitle
        let goal = int(weekGoal, 1, 7)
        f.weekGoal = goal
        f.weekDone = isFirst ? 0 : int(weekDone, 0, goal)
        f.habitDay = isFirst ? 1 : int(habitDay, 1, 999)
        f.streakWeeks = isFirst ? 0 : int(streakWeeks, 0, 999)
        f.missionSteps = missionKind == .steps ? int(missionSteps, 1, 40) : 0
        return f
    }
}

/// The prototype's clock string ("7:05") in the user's 12 or 24 hour setting.
nonisolated enum WakeClockText {
    static func string(_ date: Date, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let shown = usesTwelveHourClock(locale) ? (hour % 12 == 0 ? 12 : hour % 12) : hour
        return "\(shown):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }

    /// True when the locale writes hours as 1 to 12 ("h") or 0 to 11 ("K").
    static func usesTwelveHourClock(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        return format.contains("h") || format.contains("K")
    }
}

// MARK: - Copy (model.ts weekLine and copyFor, verbatim)

extension WakeCopy {
    /// The week sentence: comeback, fresh start, last session, or the plain count (gain framed).
    static func weekLine(_ f: WakeFacts) -> String {
        if f.isComeback { return "You came back." }
        if f.weekDone == 0 { return f.isFirst ? "Your first week starts." : "New week. This starts it." }
        if f.weekDone + 1 == f.weekGoal { return "This one keeps the week." }
        return "\(f.weekDone) of \(f.weekGoal) this week."
    }

    /// Every line of the page. Sentence case, no em dashes, about six words a line at most; a missing
    /// fact drops its words rather than filling in a placeholder.
    static func make(concept: WakeConcept, facts raw: WakeFacts) -> WakeCopy {
        let f = raw.normalized()
        let time = f.gymClock
        let leaveClock = f.leaveClock
        let greet = f.name.map { "Good morning, \($0)." } ?? "Good morning."
        let leave = leaveClock.map { "Leave by \($0)." } ?? "Gym by \(time)."
        let day = f.isFirst ? "Day 1. It starts today." : f.habitDay > 66 ? "Day \(f.habitDay)." : "Day \(f.habitDay) of 66."
        let week = weekLine(f)
        // model.ts tests the sentence against /^\d+ of \d+ this week\.$/: only the plain count.
        let plain = !f.isComeback && f.weekDone != 0 && f.weekDone + 1 != f.weekGoal
        let isPlan = concept.isPlan
        let mission = f.missionTitle.hasSuffix(".") ? String(f.missionTitle.dropLast()) : f.missionTitle

        let cardSub: String
        if isPlan {
            cardSub = leaveClock.map { "Leave by **\($0)**." } ?? "Gym by **\(time)**."
        } else {
            cardSub = "You're up. Day **\(f.habitDay)**."
        }

        let affirm: String?
        if isPlan {
            affirm = nil
        } else if f.isFirst {
            affirm = "It starts with today."
        } else if plain {
            affirm = "Today makes it \(f.weekDone + 1)."
        } else {
            affirm = nil
        }

        return WakeCopy(
            greet: greet,
            commitEyebrow: f.snoozed ? "Same plan" : "Today",
            commit: f.gymName.map { "\($0)." } ?? "The gym.",
            leave: leave,
            missionEyebrow: "Next",
            mission: "\(mission).",
            dayEyebrow: f.habitDay > 66 ? "Past the median" : "Your habit run",
            day: day,
            weekEyebrow: "So far",
            week: week,
            streak: f.streakWeeks >= 2 ? "\(f.streakWeeks) weeks" : nil,
            cardEyebrow: f.gymName ?? "Gym",
            cardHead: time,
            cardSub: cardSub,
            fine: f.gymName.map { "Apps open at \($0)." } ?? "Apps open at the gym.",
            affirm: affirm
        )
    }

    /// The card's sub line without the bold markers, for VoiceOver.
    var cardSubPlain: String { cardSub.replacingOccurrences(of: "**", with: "") }
}

// MARK: - Which renderer draws a concept

@MainActor
enum WakeStageFactory {
    /// A fresh renderer for the concept. The page keeps one for its whole life.
    static func make(_ concept: WakeConcept) -> any WakeStageRenderer {
        if concept.isMatrix {
            return MatrixWakeStage()
        } else {
            return RidgeWakeStage()
        }
    }
}
