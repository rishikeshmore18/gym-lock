//
//  MatrixStoryView.swift
//  GymLock · Matrix done flow (native port)
//
//  Native port of web/hero13/story13m.tsx (frame, copy, light) + web/hero13/mxstory.ts (the dots)
//  + the tap state machine in web/hero13/app13.tsx (onOverlayTap / onRockTap / collapse) + the screen
//  table CFG_M in web/hero12/screens12.ts.
//
//  The board:
//    - Design space: hero4/story4.tsx `fitComposition`. On every iPhone (aspect < 1080/1920) the
//      composition is 1080 wide and round(1080 / aspect / 2) * 2 tall; it is scaled by
//      s0 = viewWidth / 1080, so every phone shows the same picture, only taller or shorter.
//    - Grid: 52 x ceil(h / 21) cells at pitch 21 (ceil(1080 / 21) = 52), white at 0.07, radius 1.6.
//    - 1400 particles, dot radius 7.4, white and coral on #0A0A0B.
//    - The 1080 x 1920 text box is centred: ox = (w - 1080) / 2, oy = (h - 1920) / 2. The art centre
//      is cx = floor(w / 2 / 21) + 0.5, cy = floor((oy + 900) / 21) + 0.5 (cells).
//
//  The flow (app13.tsx):
//    - Screens: verified, today, week, [month], far, climax (month only in a month's first/last week).
//    - Nothing moves on by itself. A tap before the screen's `settle` finishes its animation; the next
//      tap goes to the next screen; a tap on the left 22% goes back.
//    - The last screen (climax) is built with N taps (5, or 7 for the week's last session and every
//      Sunday). The Nth tap seals it (sealT): heavy, heavy +70 ms, success +160 ms.
//    - At sealT + 1.6 s the finished object becomes the session count (`counted`, engine key "count").
//    - At sealT + 3.6 s (4.2 s on the month's last session) the overlay collapses into the home card
//      over 0.55 s; at 70% the card switches to `verified` (onLanded), at 100% it is gone (onFinished).
//
//  Ported fully: the frame, every copy layer (header, verified pill, today figures, week, month
//  figures and target picker, far, climax, month flourish, button), the tap and seal timings,
//  haptics per screen, the collapse, and every board screen. The board screens are transpiled from
//  mxstory.ts into Scenes/MXStory.swift and checked against the web by MatrixParity.runStoryAll().
//  The copy carries real values only: the prototype's sample heart rate, energy and week numbers
//  are not ported; MatrixStoryCopy supplies whatever GymLock actually measured.
//
//  Depends on: MatrixEngine.swift, MatrixBoard.swift, MatrixScene.swift, HeroHaptics.swift,
//              MatrixCardView.swift (MatrixGridRenderer, MatrixRGB, MatrixRich).
//

import SwiftUI
import Observation

// MARK: - Screens and timing (screens12.ts)

public enum MatrixStoryScreen: String, Sendable, CaseIterable {
    case verified, today, week, month, far, climax
}

public enum MatrixMonthPos: String, Sendable {
    case first, middle, last
}

public enum MatrixStoryConfig {
    /// `screens12(mp)`: five screens, six in a month's first and last weeks.
    public static func screens(_ mp: MatrixMonthPos) -> [MatrixStoryScreen] {
        mp == .middle ? [.verified, .today, .week, .far, .climax] : [.verified, .today, .week, .month, .far, .climax]
    }

    public struct Screen: Sendable {
        public let settle: Double
        public let haptics: [HapticCue]
    }

    /// CFG_M: seconds until the screen's animation has settled, and its haptics (screen seconds).
    public static func cfg(_ id: MatrixStoryScreen) -> Screen {
        func h(_ t: Double, _ k: HapticKind) -> HapticCue { HapticCue(t: t, kind: k) }
        switch id {
        case .verified:
            return Screen(settle: 1.5, haptics: [h(0.05, .medium), h(0.75, .heavy), h(0.8, .success)])
        case .today:
            return Screen(settle: 2.3, haptics: [h(0.05, .medium)] + (0..<13).map { h(0.3 + Double($0) * 0.14, .light) } + [h(2.12, .heavy)])
        case .week:
            return Screen(settle: 2.4, haptics: [h(0.05, .medium)] + (0..<8).map { h(0.2 + Double($0) * 0.18, .light) } + [h(1.9, .medium), h(2.15, .medium)])
        case .month:
            return Screen(settle: 1.8, haptics: [h(0.05, .medium)] + (0..<8).map { h(0.25 + Double($0) * 0.1, .light) } + [h(1.3, .heavy)])
        case .far:
            return Screen(settle: 1.9, haptics: [h(0.05, .medium), h(0.7, .heavy), h(0.75, .success), h(1.5, .light)])
        case .climax:
            return Screen(settle: 1.0, haptics: [h(0.05, .medium)])
        }
    }

    /// CFG_R (screens12.ts): the Ridge done screens.
    public static func cfgR(_ id: MatrixStoryScreen) -> Screen {
        func h(_ t: Double, _ k: HapticKind) -> HapticCue { HapticCue(t: t, kind: k) }
        switch id {
        case .verified:
            return Screen(settle: 2.0, haptics: [h(0.05, .light), h(0.5, .medium), h(0.9, .heavy), h(0.95, .success)] + (0..<3).map { h(1.3 + Double($0) * 0.12, .light) })
        case .today:
            return Screen(settle: 1.8, haptics: [h(0.05, .medium)] + (0..<8).map { h(0.25 + Double($0) * 0.12, .light) } + [h(1.3, .medium)])
        case .week:
            return Screen(settle: 1.8, haptics: [h(0.05, .medium)] + (0..<3).map { h(0.5 + Double($0) * 0.18, .medium) } + [h(1.3, .light)])
        case .month:
            return Screen(settle: 1.6, haptics: [h(0.05, .medium)] + (0..<6).map { h(0.25 + Double($0) * 0.1, .light) } + [h(1.1, .heavy)])
        case .far:
            return Screen(settle: 2.0, haptics: [h(0.05, .medium)] + (0..<7).map { h(0.3 + Double($0) * 0.13, .light) } + [h(1.4, .heavy)])
        case .climax:
            return Screen(settle: 1.0, haptics: [h(0.05, .medium)])
        }
    }

    static func cfg(_ id: MatrixStoryScreen, style: HeroCardStyle) -> Screen {
        style == .ridge ? cfgR(id) : cfg(id)
    }

    /// Seconds after the seal that the count takes over (story13m.tsx `counted`).
    public static let countAfter: Double = 1.6
    /// Seconds after the seal that the overlay collapses (app13.tsx, Matrix).
    public static func collapseAfter(mp: MatrixMonthPos, pos: MatrixWeekPos) -> Double { mp == .last && pos == .last ? 4.2 : 3.6 }
    /// app12.tsx: Ridge collapses sooner (S + 2.8 s), the month's last session still waits 4.2 s.
    static func collapseAfter(mp: MatrixMonthPos, pos: MatrixWeekPos, style: HeroCardStyle) -> Double {
        if mp == .last && pos == .last { return 4.2 }
        return style == .ridge ? 2.8 : 3.6
    }
    public static let collapseDuration: Double = 0.55
}

// MARK: - Climax copy (mxstory.ts MX_CLIMAX, days12.ts POS_TAIL / endFor)

public struct MatrixClimaxCopy: Sendable {
    public let eyebrow: String
    public let lastEyebrow: String
    public let title: String
    public let sub: @Sendable (Int) -> String
    public let idle: String
    public let mid: String
    public let end: String

    public static let byDay: [MatrixClimaxCopy] = [
        MatrixClimaxCopy(eyebrow: "TODAY'S SUNRISE", lastEyebrow: "THE WEEK'S LAST SUNRISE", title: "Raise it.", sub: { "Tap **\($0) times** to lift the sun over the horizon." }, idle: "Tap to raise the sun", mid: "Higher", end: "The sun is up, and so is the count."),
        MatrixClimaxCopy(eyebrow: "TODAY'S BLOCK", lastEyebrow: "THE WEEK'S LAST BLOCK", title: "Build it.", sub: { "Tap **\($0) times.** Every session is a block in the wall." }, idle: "Tap to place a block", mid: "Next block", end: "Set in place. The wall gets taller every session."),
        MatrixClimaxCopy(eyebrow: "TODAY'S CHARGE", lastEyebrow: "THE WEEK'S LAST CHARGE", title: "Charge it.", sub: { "Tap **\($0) times** to fill today's charge." }, idle: "Tap to charge", mid: "Charging", end: "Fully charged. Training gives back more than it takes."),
        MatrixClimaxCopy(eyebrow: "TODAY'S BAR", lastEyebrow: "THE WEEK'S LAST LIFT", title: "Load it.", sub: { "Tap **\($0) times.** Every tap adds a plate." }, idle: "Tap to add a plate", mid: "Add another", end: "Loaded and lifted. One more rep for the habit."),
        MatrixClimaxCopy(eyebrow: "TODAY'S PUSH", lastEyebrow: "THE WEEK'S LAST PUSH", title: "Push it.", sub: { "Tap **\($0) times** to push today to the top." }, idle: "Tap to push", mid: "Higher", end: "Top reached. One more on the count."),
        MatrixClimaxCopy(eyebrow: "TODAY'S RING", lastEyebrow: "THE WEEK'S LAST RING", title: "Close it.", sub: { "Tap **\($0) times** to close today's ring." }, idle: "Tap to close the ring", mid: "Keep closing", end: "Ring closed. Habits are loops you keep closing."),
        MatrixClimaxCopy(eyebrow: "THE WEEK'S SAND", lastEyebrow: "THE WEEK'S LAST GRAINS", title: "Turn it.", sub: { "Tap **\($0) times.** One day of sand for each." }, idle: "Tap to let a day fall", mid: "Next day", end: "Every day through. Turn it over and a new week starts."),
    ]

    public static let tally = ["SUNRISES", "BLOCKS LAID", "CHARGES", "BARS LIFTED", "PUSHES", "RINGS CLOSED", "WEEKS TURNED"]

    public static func posTail(_ pos: MatrixWeekPos) -> String {
        switch pos {
        case .first: return "The first of the week is the hardest to start."
        case .middle: return "The middle is where most people stop. **You didn't.**"
        case .last: return "A full week, finished on a high. **That's how it will be remembered.**"
        }
    }

    /// Real facts for the closing line (days12.ts `endFor`, with the prototype's sample numbers
    /// replaced by the user's own).
    public struct EndFacts: Sendable, Equatable {
        /// sessions this week, including today
        public var weekDone: Int
        /// the weekly goal (3...7)
        public var weekGoal: Int
        /// kept weeks in a row, counting this one once it is kept
        public var weekStreak: Int
        /// the next planned session, e.g. ("Thursday", "07:00"); nil when nothing is planned
        public var nextDay: String?
        public var nextTime: String?
        public init(weekDone: Int, weekGoal: Int, weekStreak: Int, nextDay: String? = nil, nextTime: String? = nil) {
            self.weekDone = weekDone
            self.weekGoal = weekGoal
            self.weekStreak = weekStreak
            self.nextDay = nextDay
            self.nextTime = nextTime
        }
    }

    /// `endFor(pos, day)`: the closing line and the button, from real values only.
    public static func end(pos: MatrixWeekPos, facts f: EndFacts) -> (sub: String, button: String) {
        let next: String? = f.nextDay.map { d in f.nextTime.map { "\(d), \($0)" } ?? d }
        if pos == .last {
            let streak = f.weekStreak > 0 ? " Week streak **\(f.weekStreak).**" : ""
            return ("Week **\(f.weekDone) of \(f.weekGoal).**\(streak) Rest up.", f.nextDay.map { "Week done. See you \($0)" } ?? "Week done")
        }
        let button = f.nextDay.map { "See you \($0)" } ?? "Done"
        let left = max(0, f.weekGoal - f.weekDone)
        if pos == .first {
            return (next.map { "Next: **\($0).** Keep it rolling." } ?? "Keep it rolling.", button)
        }
        let tail = left == 1 ? "Only 1 left." : "Only \(left) left."
        return (next.map { "Next: **\($0).** \(tail)" } ?? tail, button)
    }
}

/// Copy for the screens before the climax. Comes from the app's copy tables (DONE12, POS_WEEK,
/// monthScreen in the prototype). Captions accept **bold** markup.
public struct MatrixStoryCopy: Sendable {
    public struct Header: Sendable {
        public var eyebrow: String
        public var title: String
        public init(eyebrow: String, title: String) {
            self.eyebrow = eyebrow
            self.title = title
        }
    }
    public var headers: [MatrixStoryScreen: Header]
    /// The caption under the art (story13m.tsx: verified `V.sub`, week `PW.s2.sub`, month `MS.sub`, far line).
    public var captions: [MatrixStoryScreen: String]
    /// The quieter second line (week / month research notes).
    public var research: [MatrixStoryScreen: String]

    /// One figure in a stats row (story13m.tsx today / month rows). `roll` counts up to the value.
    public struct Stat: Sendable, Equatable {
        public var value: String
        public var roll: Int?
        public var unit: String?
        public var label: String
        public var coral: Bool
        public init(value: String, roll: Int? = nil, unit: String? = nil, label: String, coral: Bool = false) {
            self.value = value
            self.roll = roll
            self.unit = unit
            self.label = label
            self.coral = coral
        }
        public static func count(_ n: Int, unit: String? = nil, label: String, coral: Bool = false) -> Stat {
            Stat(value: String(n), roll: n, unit: unit, label: label, coral: coral)
        }
    }

    /// The today screen: when the session ran, a line about it, and real figures only (no heart
    /// rate or energy unless GymLock actually measured them).
    public struct Today: Sendable, Equatable {
        public var start: String
        public var end: String?
        public var caption: String?
        public var stats: [Stat]
        /// The session's measured length (Ridge today title rolls up to it). Nil when unknown.
        public var minutes: Int?
        public init(start: String, end: String? = nil, caption: String? = nil, stats: [Stat] = [], minutes: Int? = nil) {
            self.start = start
            self.end = end
            self.caption = caption
            self.stats = stats
            self.minutes = minutes
        }
    }

    /// One day of the current week (Ridge week pebbles): real sessions only.
    public struct WeekDay: Sendable, Equatable {
        public var label: String
        public var minutes: Int?
        public var done: Bool
        public var isToday: Bool
        public init(label: String, minutes: Int? = nil, done: Bool, isToday: Bool) {
            self.label = label
            self.minutes = minutes
            self.done = done
            self.isToday = isToday
        }
    }

    /// days12.ts MONTH_TARGETS
    public struct MonthTarget: Sendable, Equatable {
        public var n: Int
        public var label: String
        public init(n: Int, label: String) {
            self.n = n
            self.label = label
        }
    }

    public var today: Today?
    /// The verified screen's pill ("6 apps unlocked"). Nil hides it.
    public var appsUnlocked: Int?
    /// The month screen's figures when it is not asking for a target.
    public var monthStats: [Stat]
    /// The month screen's target choices (first week of a month, first session).
    public var monthTargets: [MonthTarget]
    /// "November": the climax flourish on the month's last session.
    public var monthName: String?
    /// The closing line and button after the seal.
    public var endSub: String
    public var endButton: String
    /// Ridge week screen: Monday-first days and the week's figures.
    public var weekDays: [WeekDay] = []
    public var weekStats: [Stat] = []
    /// Ridge far screen: minutes per week (oldest first, at most 8) and the long-run figures.
    public var farWeeks: [Int] = []
    public var farStats: [Stat] = []
    /// Total sessions after today's (the Ridge count rolls from `sessions - 1`).
    public var sessions: Int = 0

    public init(
        headers: [MatrixStoryScreen: Header],
        captions: [MatrixStoryScreen: String] = [:],
        research: [MatrixStoryScreen: String] = [:],
        today: Today? = nil,
        appsUnlocked: Int? = nil,
        monthStats: [Stat] = [],
        monthTargets: [MonthTarget] = [],
        monthName: String? = nil,
        endSub: String = "",
        endButton: String = "Done"
    ) {
        self.headers = headers
        self.captions = captions
        self.research = research
        self.today = today
        self.appsUnlocked = appsUnlocked
        self.monthStats = monthStats
        self.monthTargets = monthTargets
        self.monthName = monthName
        self.endSub = endSub
        self.endButton = endButton
    }
}

// MARK: - Story scene context (mxstory.ts SC / Out)

public struct MatrixStoryContext: Sendable {
    public var t: Double
    /// seconds since the current screen started
    public var lt: Double
    public var cx: Double
    public var cy: Double
    public var cols: Int
    public var rows: Int
    public var N: Int
    public var taps: Int
    public var tapTimes: [Double]
    public var tapAt: Double?
    public var sealT: Double?
    /// seconds since the seal, or -1
    public var since: Double
    public var D: MatrixDayData
    public var day: Int
    public var pos: MatrixWeekPos
    /// POS_WEEK `{done, today}`
    public var weekDone: Int
    public var weekToday: Int
    public var pick: Bool
    public var picked: Bool
    public var pickAt: Double?
    /// the month screen's calendar; without it the month screen draws nothing
    public var cal: MatrixStoryCal? = nil
}

public struct MatrixGlow: Sendable, Equatable {
    public var x: Double, y: Double, r: Double, a: Double
}

public struct MatrixStoryOut: Sendable {
    public var phase: String?
    public var opts: MatrixDealOptions?
    public var flash: Double = 0
    public var glow: [MatrixGlow] = []
}

// MARK: - mxstory.ts bridge
//
// Every screen is transpiled from hero13/mxstory.ts into `MX.Story` (Scenes/MXStory.swift). The
// TS context is all numbers, so the bridge mirrors it as `MXStoryContext` and maps the result back.

/// The month screen's calendar (hero13 `MCal`): Monday-first `lead` blanks, then one cell per day of
/// the month: "done", "today", "future", "miss" or "rest".
public struct MatrixStoryCal: Sendable, Equatable {
    public var lead: Int
    public var cells: [String]
    public var target: Int
    public var sessions: Int
    public init(lead: Int, cells: [String], target: Int, sessions: Int) {
        self.lead = lead
        self.cells = cells
        self.target = target
        self.sessions = sessions
    }
}

extension MX.Story {
    final class MXStoryDay {
        var day: Double
        var sessions: Double
        init(day: Double, sessions: Double) {
            self.day = day
            self.sessions = sessions
        }
    }

    final class MXStoryWeek {
        var done: Double
        var today: Double
        init(done: Double, today: Double) {
            self.done = done
            self.today = today
        }
    }

    final class MXStoryCal {
        var lead: Double
        var cells: [String]
        var target: Double
        var sessions: Double
        init(lead: Double, cells: [String], target: Double, sessions: Double) {
            self.lead = lead
            self.cells = cells
            self.target = target
            self.sessions = sessions
        }
    }

    /// mxstory.ts `SC`
    final class MXStoryContext {
        var t: Double, lt: Double, cx: Double, cy: Double, cols: Double, rows: Double
        var N: Double, taps: Double
        var tapTimes: [Double]
        var tapAt: Double?
        var sealT: Double?
        var since: Double
        var D: MXStoryDay
        var day: Double
        var pos: String
        var PW: MXStoryWeek
        var cal: MXStoryCal?
        var pick: Bool?
        var picked: Bool?
        var pickAt: Double?

        init(_ s: MatrixStoryContext) {
            t = s.t
            lt = s.lt
            cx = s.cx
            cy = s.cy
            cols = Double(s.cols)
            rows = Double(s.rows)
            N = Double(s.N)
            taps = Double(s.taps)
            tapTimes = s.tapTimes
            tapAt = s.tapAt
            sealT = s.sealT
            since = s.since
            D = MXStoryDay(day: Double(s.D.day), sessions: Double(s.D.sessions))
            day = Double(s.day)
            pos = s.pos.rawValue
            PW = MXStoryWeek(done: Double(s.weekDone), today: Double(s.weekToday))
            cal = s.cal.map { MXStoryCal(lead: Double($0.lead), cells: $0.cells, target: Double($0.target), sessions: Double($0.sessions)) }
            pick = s.pick
            picked = s.picked
            pickAt = s.pickAt
        }
    }

    /// mxstory.ts `Res`
    final class MXStoryRes {
        var ph: String?
        var o: MatrixDealOptions?
        var flash: Double?
        var glow: [MatrixGlow]?
        init(ph: String? = nil, o: MatrixDealOptions? = nil, flash: Double? = nil, glow: [MatrixGlow]? = nil) {
            self.ph = ph
            self.o = o
            self.flash = flash
            self.glow = glow
        }
    }
}

public enum MatrixStoryScenes {
    /// `mxStory(id, counted, s)`: draws the screen into `g` (reset by the caller, sized cols x rows,
    /// cap 1400) and returns its phase, deal options, flash and glows.
    public static func render(_ g: inout MatrixBoard, _ id: MatrixStoryScreen, counted: Bool, _ s: MatrixStoryContext) -> MatrixStoryOut {
        typealias S = MX.Story
        let sc = S.MXStoryContext(s)
        let times = s.tapTimes, now = s.t
        let age = { (k: Double) -> Double in
            let i = Int(k)
            return k >= 0 && i < times.count ? now - times[i] : -1
        }
        let dd = sc.D.day
        let day = max(0, min(6, s.day))
        let r: S.MXStoryRes?
        if counted {
            r = S.count(&g, sc)
        } else {
            switch id {
            case .verified:
                switch day {
                case 0: r = S.vMon(&g, sc)
                case 1: r = S.vTue(&g, sc)
                case 2: r = S.vWed(&g, sc)
                case 3: r = S.vThu(&g, sc)
                case 4: r = S.vFri(&g, sc)
                case 5: r = S.vSat(&g, sc)
                default: r = S.vSun(&g, sc)
                }
            case .today: r = S.today(&g, sc)
            case .week: r = S.week(&g, sc)
            case .month: r = S.month(&g, sc)
            case .far:
                // `s.day === 3 ? fThu(g, s) : [fMon, fTue, fWed, fMon, fFri, fSat, fSun][s.day](g, s, dd)`
                switch day {
                case 0: r = S.fMon(&g, sc, dd)
                case 1: r = S.fTue(&g, sc, dd)
                case 2: r = S.fWed(&g, sc, dd)
                case 3: r = S.fThu(&g, sc)
                case 4: r = S.fFri(&g, sc, dd)
                case 5: r = S.fSat(&g, sc, dd)
                default: r = S.fSun(&g, sc, dd)
                }
            case .climax:
                switch day {
                case 0: r = S.finMon(&g, sc, age)
                case 1: r = S.finTue(&g, sc, age)
                case 2: r = S.finWed(&g, sc, age)
                case 3: r = S.finThu(&g, sc, age)
                case 4: r = S.finFri(&g, sc, age)
                case 5: r = S.finSat(&g, sc, age)
                default: r = S.finSun(&g, sc, age)
                }
            }
        }
        return MatrixStoryOut(phase: r?.ph, opts: r?.o, flash: r?.flash ?? 0, glow: r?.glow ?? [])
    }
}

// MARK: - Flow model (app13.tsx overlay state)

@MainActor
@Observable
public final class MatrixStoryModel {
    public let day: Int
    public let pos: MatrixWeekPos
    public let monthPos: MatrixMonthPos
    public let dayData: MatrixDayData
    public let weekDone: Int
    public let weekToday: Int
    /// The month's first week of a month's first session: the month screen asks for a target.
    public let monthPick: Bool
    /// the month screen's calendar (real sessions this month); the target follows `pickTarget`
    public private(set) var cal: MatrixStoryCal?
    public let ids: [MatrixStoryScreen]
    public let copy: MatrixStoryCopy
    /// Dynamic camera (lean-in on taps and seal). Off under Reduce Motion regardless.
    public let dynamic: Bool
    /// Which done flow: the Matrix board or the Ridge world (timings and haptics differ).
    let style: HeroCardStyle

    public private(set) var idx = 0
    /// Closed with the X or a swipe before the seal.
    public private(set) var closedEarly = false
    public private(set) var start: Double = 0
    public private(set) var tapTimes: [Double] = []
    public private(set) var sealT: Double?
    public private(set) var collapseAt: Double?
    public private(set) var picked = false
    public private(set) var pickAt: Double?

    @ObservationIgnored public var onLanded: (() -> Void)?
    @ObservationIgnored public var onFinished: (() -> Void)?
    /// The month target buttons: persist the user's pick.
    @ObservationIgnored public var onPickTarget: ((Int) -> Void)?
    /// The month's last screen showed (`noteRecap`).
    @ObservationIgnored public var onScreen: ((MatrixStoryScreen) -> Void)?
    /// Any progress worth persisting (screen, taps, seal, pick): spec §3.4.
    @ObservationIgnored public var onProgress: (() -> Void)?
    /// Rank-up steps follow the count (spec §4.2): the collapse waits for `release(at:)`.
    @ObservationIgnored public var holdsCollapse = false
    @ObservationIgnored public var onHold: (() -> Void)?
    public private(set) var holdAt: Double?
    public private(set) var isHolding = false
    @ObservationIgnored let haptics = HeroHapticScheduler()
    @ObservationIgnored private var epoch: Date
    @ObservationIgnored private var frozenAt: Date?
    @ObservationIgnored private var landedFired = false
    @ObservationIgnored private var finishedFired = false

    /// - Parameters:
    ///   - short: the fatigue guard's short flow (verified, then the climax).
    ///   - resumeAtClimax: back after 10 min or more away: open on the climax.
    init(day: Int, pos: MatrixWeekPos, monthPos: MatrixMonthPos, dayData: MatrixDayData, weekDone: Int, weekToday: Int, monthPick: Bool, cal: MatrixStoryCal? = nil, copy: MatrixStoryCopy, dynamic: Bool = true, style: HeroCardStyle = .matrix, short: Bool = false, resumeAtClimax: Bool = false, resumeIndex: Int? = nil, restoredTaps: Int = 0, now: Date = Date()) {
        self.day = day
        self.pos = pos
        self.monthPos = monthPos
        self.dayData = dayData
        self.weekDone = weekDone
        self.weekToday = weekToday
        self.monthPick = monthPick
        self.cal = cal
        // Spec §4.3: short is verified → climax → count, plus any month screen.
        self.ids = short
            ? (monthPos == .middle ? [.verified, .climax] : [.verified, .month, .climax])
            : MatrixStoryConfig.screens(monthPos)
        self.copy = copy
        self.dynamic = dynamic
        self.style = style
        // headroom so engine timestamps are positive from the first frame
        self.epoch = now.addingTimeInterval(-2)
        let t = now.timeIntervalSince(epoch)
        start = t
        if resumeAtClimax, let c = ids.firstIndex(of: .climax) {
            idx = c
        } else if let r = resumeIndex, ids.indices.contains(r) {
            // back within 10 min: the same screen, already settled, no entrance haptics
            idx = r
            start = t - MatrixStoryConfig.cfg(ids[r], style: style).settle
        }
        if idx == ids.count - 1, restoredTaps > 0 {
            let n = min(restoredTaps, MatrixContext.taps(day: day, pos: pos) - 1)
            tapTimes = (0..<max(0, n)).map { t - 1 - Double(n - $0) * 0.1 }
        }
        if picked == false, monthPick, let r = resumeIndex, let m = ids.firstIndex(of: .month), r > m { picked = true }
        haptics.allowsSuccess = Self.allowsSuccess(ids[idx])
        haptics.reset(cues: Self.cues(for: ids[idx], style: style, start: t), at: t)
    }

    public func cfg(_ id: MatrixStoryScreen) -> MatrixStoryConfig.Screen { MatrixStoryConfig.cfg(id, style: style) }

    /// Spec §6.1: success only at the proof (verified) and the seal (climax).
    private static func allowsSuccess(_ id: MatrixStoryScreen) -> Bool { id == .verified || id == .climax }

    /// The glass X or a swipe down: skip what is left and collapse at once (spec §4.3, 0.55 s).
    public func close(at t: Double) {
        if let c = collapseAt, c <= t { return }
        if sealT == nil { closedEarly = true }
        haptics.isActive = false
        collapseAt = t
        onProgress?()
    }

    /// The rank-ups are done: the collapse starts 200 ms later.
    public func release(at t: Double) {
        guard collapseAt == nil else { return }
        isHolding = false
        holdAt = nil
        collapseAt = t + 0.2
    }

    /// Ends without the collapse (the overlay is already gone, or the day ended).
    public func finishNow() {
        haptics.isActive = false
        if !landedFired {
            landedFired = true
            onLanded?()
        }
        if !finishedFired {
            finishedFired = true
            onFinished?()
        }
    }

    /// Background: the overlay clock stops (spec §3.4 "it never jumps forward").
    public func freeze(_ date: Date = Date()) {
        guard frozenAt == nil else { return }
        frozenAt = date
        haptics.isActive = false
    }

    public func thaw(_ date: Date = Date()) {
        guard let f = frozenAt else { return }
        frozenAt = nil
        epoch = epoch.addingTimeInterval(max(0, date.timeIntervalSince(f)))
        if collapseAt == nil || !closedEarly { haptics.isActive = true }
        haptics.reset(cues: [], at: time(date))
    }

    public var isFrozen: Bool { frozenAt != nil }

    public var isSealed: Bool { sealT != nil }

    public var N: Int { MatrixContext.taps(day: day, pos: pos) }
    public var screen: MatrixStoryScreen { ids[idx] }
    public var isLast: Bool { idx == ids.count - 1 }

    public func time(_ date: Date) -> Double { (frozenAt.map { min($0, date) } ?? date).timeIntervalSince(epoch) }
    public func lt(_ t: Double) -> Double { t - start }
    public func settled(_ t: Double) -> Bool { lt(t) >= cfg(screen).settle }
    public func since(_ t: Double) -> Double { sealT.map { t - $0 } ?? -1 }
    public func counted(_ t: Double) -> Bool { sealT != nil && since(t) > MatrixStoryConfig.countAfter }
    /// 0...1 progress of the collapse into the card.
    public func collapse(_ t: Double) -> Double { collapseAt.map { MX.cl((t - $0) / MatrixStoryConfig.collapseDuration) } ?? 0 }

    private static func cues(for id: MatrixStoryScreen, style: HeroCardStyle, start: Double) -> [HapticCue] {
        MatrixStoryConfig.cfg(id, style: style).haptics.map { HapticCue(t: start + $0.t, kind: $0.kind) }
    }

    private func goTo(_ i: Int, start s: Double, now t: Double) {
        let changed = i != idx
        idx = i
        start = s
        haptics.allowsSuccess = Self.allowsSuccess(ids[i])
        haptics.reset(cues: Self.cues(for: ids[i], style: style, start: s), at: t)
        if changed { onScreen?(ids[i]) }
        onProgress?()
    }

    /// app13.tsx `onOverlayTap`. `xFraction` is the tap's x / screen width.
    public func tap(xFraction: Double, at t: Double) {
        guard collapseAt == nil, !closedEarly else { return }
        let settle = cfg(screen).settle
        if xFraction < 0.22 && idx > 0 {
            haptics.playNow(.light)
            goTo(idx - 1, start: t - cfg(ids[idx - 1]).settle, now: t)
            return
        }
        if isLast {
            sealTap(at: t)
            return
        }
        if screen == .month && monthPick && !picked {
            // the target buttons call `pickTarget`; a tap elsewhere accepts the default
            picked = true
            pickAt = t
            haptics.playNow(.heavy)
            if let n = cal?.target { onPickTarget?(n) }
            onProgress?()
            return
        }
        if !settled(t) {
            // the first tap finishes this screen's animation
            haptics.playNow(.light)
            goTo(idx, start: t - settle, now: t)
            return
        }
        haptics.playNow(.medium)
        goTo(idx + 1, start: t, now: t)
    }

    /// The month target buttons (month screen in a month's first week).
    public func pickTarget(_ n: Int, at t: Double) {
        guard collapseAt == nil, screen == .month, monthPick else { return }
        let first = !picked
        picked = true
        if cal?.target != n {
            cal?.target = n
            onPickTarget?(n)
        }
        pickAt = t
        haptics.playNow(first ? .heavy : .medium)
        if first { haptics.add(HapticCue(t: t + 0.12, kind: .success)) }
        onProgress?()
    }

    /// app13.tsx `onRockTap`: build the finish; the Nth tap seals it.
    private func sealTap(at t: Double) {
        guard sealT == nil else { return }
        let n = tapTimes.count + 1
        tapTimes.append(t)
        if n >= N {
            sealT = t
            haptics.playNow(.heavy)
            haptics.add(HapticCue(t: t + 0.07, kind: .heavy))
            haptics.add(HapticCue(t: t + 0.16, kind: .success))
            let after = t + MatrixStoryConfig.collapseAfter(mp: monthPos, pos: pos, style: style)
            if holdsCollapse { holdAt = after } else { collapseAt = after }
        } else {
            haptics.playNow(n >= N - 1 ? .heavy : Double(n) > Double(N) / 2 ? .medium : .light)
        }
        onProgress?()
    }

    /// Once per frame (from `.onChange(of: timeline.date)`): haptics on the frame, collapse callbacks.
    public func advance(to t: Double) {
        if let h = holdAt, collapseAt == nil, !isHolding, t >= h {
            isHolding = true
            onHold?()
        }
        if let c = collapseAt, t >= c {
            // the web stops screen haptics once the overlay leaves; the seal cues are already past
            haptics.isActive = false
        }
        haptics.tick(t)
        let cp = collapse(t)
        if !landedFired && cp >= 0.7 {
            landedFired = true
            onLanded?()
        }
        if !finishedFired && cp >= 1 {
            finishedFired = true
            onFinished?()
        }
    }
}

// MARK: - Runtime (engine, grid cache; not observable)

@MainActor
final class MatrixStoryRuntime {
    static let PITCH: Double = 21
    static let BOX_W: Double = 1080
    static let BOX_H: Double = 1920
    static let GY: Double = 900
    static let FOCUS_Y: Double = 880

    private var engine: MatrixEngine?
    private var board = MatrixBoard(width: 52, height: 92, cap: 1400)
    private var dims = (cols: 0, rows: 0)
    private var grid: (key: String, image: Image)?

    /// hero4/story4.tsx `fitComposition(vw, vh)`.
    static func composition(_ size: CGSize) -> CGSize {
        let vw = Double(size.width), vh = Double(size.height)
        guard vw > 0, vh > 0 else { return CGSize(width: BOX_W, height: BOX_H) }
        let a = vw / vh
        if a < BOX_W / BOX_H { return CGSize(width: BOX_W, height: JSMath.round(BOX_W / a / 2) * 2) }
        return CGSize(width: JSMath.round((BOX_H * a) / 2) * 2, height: BOX_H)
    }

    /// Bottom edge, in points, of the story's progress bars (top `max(oy,0)+90`, 7 tall, in
    /// composition units), so chrome laid over the story can sit clear of them.
    static func progressBottom(_ size: CGSize) -> CGFloat {
        let comp = composition(size)
        let s0 = Double(size.width) / max(1, Double(comp.width))
        let oy = (Double(comp.height) - BOX_H) / 2
        return CGFloat((max(oy, 0) + 90 + 7) * s0)
    }

    func render(_ ctx: inout GraphicsContext, size: CGSize, date: Date, model: MatrixStoryModel, reduceMotion: Bool, displayScale: CGFloat) {
        let comp = Self.composition(size)
        let w = Double(comp.width), h = Double(comp.height)
        let s0 = Double(size.width) / w
        guard s0 > 0, s0.isFinite else { return }
        let cols = Int((w / Self.PITCH).rounded(.up)), rows = Int((h / Self.PITCH).rounded(.up))
        let oy = (h - Self.BOX_H) / 2
        let cx = (w / 2 / Self.PITCH).rounded(.down) + 0.5
        let cy = ((oy + Self.GY) / Self.PITCH).rounded(.down) + 0.5

        if dims.cols != cols || dims.rows != rows || engine == nil {
            dims = (cols, rows)
            engine = MatrixEngine(n: 1400, cols: cols, rows: rows)
            board = MatrixBoard(width: cols, height: rows, cap: 1400)
            grid = nil
        }
        guard let engine else { return }

        let t = model.time(date)
        let lt = model.lt(t)
        let since = model.since(t)
        let counted = model.counted(t)
        let id = model.screen
        let tapAt = model.tapTimes.last

        ctx.scaleBy(x: s0, y: s0)
        // the board leans in a touch on entry, on each tap and on the seal; no shake
        let dz = model.dynamic && !reduceMotion
        if dz {
            var camS = 1 + 0.05 * (1 - MX.ez(lt / 0.7))
            if id == .climax, let tapAt, model.sealT == nil { camS += 0.012 * exp(-(t - tapAt) * 9) }
            if id == .climax, let sealT = model.sealT { camS += 0.025 * exp(-(t - sealT) * 5) }
            let px = w * 0.5, py = h * 0.47
            ctx.translateBy(x: px, y: py)
            ctx.scaleBy(x: camS, y: camS)
            ctx.translateBy(x: -px, y: -py)
        }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(.sRGB, red: 10 / 255, green: 10 / 255, blue: 11 / 255)))
        let pxScale = s0 * Double(displayScale)
        let gkey = "\(cols)x\(rows):\(Int((pxScale * 1000).rounded()))"
        if grid?.key != gkey, let cg = MatrixGridRenderer.makeImage(cols: cols, rows: rows, pitch: Self.PITCH, radius: 1.6, color: MatrixRGB(0xFFFFFF), alpha: 0.07, pxScale: pxScale) {
            grid = (gkey, Image(decorative: cg, scale: 1))
        }
        if let img = grid?.image {
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: Double(cols) * Self.PITCH, height: Double(rows) * Self.PITCH))
        }

        let sc = MatrixStoryContext(
            t: t, lt: lt, cx: cx, cy: cy, cols: cols, rows: rows, N: model.N, taps: model.tapTimes.count,
            tapTimes: model.tapTimes, tapAt: tapAt, sealT: model.sealT, since: since, D: model.dayData,
            day: model.day, pos: model.pos, weekDone: model.weekDone, weekToday: model.weekToday,
            pick: model.monthPick, picked: model.picked, pickAt: model.pickAt, cal: model.cal
        )
        board.reset()
        let mx = MatrixStoryScenes.render(&board, id, counted: counted, sc)
        let key = counted ? "count" : "\(id.rawValue)\(model.day):\(mx.phase ?? "")"

        // local light: a soft bloom behind the dots where the beat lands
        for gl in mx.glow where gl.a >= 0.01 {
            let X = gl.x * Self.PITCH, Y = gl.y * Self.PITCH, R = gl.r * Self.PITCH
            let grad = Gradient(colors: [Color.white.opacity(min(0.22, gl.a * 0.55)), Color.white.opacity(0)])
            ctx.fill(Path(CGRect(x: X - R, y: Y - R, width: 2 * R, height: 2 * R)), with: .radialGradient(grad, center: CGPoint(x: X, y: Y), startRadius: 0, endRadius: R))
        }
        engine.update(key: key, targets: board.out(), t: t, options: mx.opts ?? MatrixDealOptions(stagger: 0.25))
        engine.draw(in: ctx, ox: 0, oy: 0, pitch: Self.PITCH, ink: .white, coral: MatrixRGB.coral.color, radius: 7.4)

        // a full-screen flash only on the real peaks (the seal, the count)
        var fl = mx.flash
        if id == .climax && counted && since < 1.9 { fl += 0.1 * (1 - (since - 1.6) / 0.3) }
        if fl > 0.01 && !reduceMotion {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.white.opacity(min(0.25, fl))))
        }
    }
}

// MARK: - The view

/// Full-screen done flow. Present it as an overlay above the home screen (ignoring safe areas), not
/// as a fullScreenCover, so the collapse can fly into the card. Pass the card's frame in this view's
/// coordinate space as `cardFrame` for the exact web collapse; without it the overlay fades and shrinks.
public struct MatrixStoryView: View {
    public let model: MatrixStoryModel
    public var cardFrame: CGRect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var runtime = MatrixStoryRuntime()

    public init(model: MatrixStoryModel, cardFrame: CGRect? = nil) {
        self.model = model
        self.cardFrame = cardFrame
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation(minimumInterval: nil, paused: scenePhase != .active)) { tl in
                let t = model.time(tl.date)
                let cp = model.collapse(t)
                ZStack(alignment: .topLeading) {
                    Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, sz in
                        runtime.render(&ctx, size: sz, date: tl.date, model: model, reduceMotion: reduceMotion, displayScale: displayScale)
                    }
                    .accessibilityHidden(true)
                    MatrixStoryCopyLayer(model: model, t: t, size: size, reduceMotion: reduceMotion)
                    if model.screen == .month && model.monthPick && model.collapseAt == nil {
                        MatrixMonthPicker(model: model, t: t, size: size)
                    }
                }
                .modifier(StoryCollapseModifier(cp: cp, size: size, cardFrame: cardFrame))
                .onChange(of: tl.date) { _, d in model.advance(to: model.time(d)) }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                guard size.width > 0 else { return }
                model.tap(xFraction: Double(loc.x / size.width), at: model.time(Date()))
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(model.isLast ? "Tap to build today's finish" : "Tap to continue")
    }
}

/// app13.tsx: the overlay flies into the card. p = eio(cp); scale toward the card's width; clip to the
/// card's height around FOCUS_Y; fade over the last 28%.
struct StoryCollapseModifier: ViewModifier {
    let cp: Double
    let size: CGSize
    let cardFrame: CGRect?
    /// design-space y (in the 1920 box) the card crop centres on
    var focus: Double = MatrixStoryRuntime.FOCUS_Y

    func body(content: Content) -> some View {
        let opacity = 1 - MX.cl((cp - 0.72) / 0.28)
        if cp <= 0 {
            content
        } else if let r = cardFrame, size.width > 0 {
            let vw = Double(size.width), vh = Double(size.height)
            let comp = MatrixStoryRuntime.composition(size)
            let s0 = vw / Double(comp.width)
            let p = MX.eio(cp)
            let k = Double(r.width) / vw
            let focusY = ((Double(comp.height) - MatrixStoryRuntime.BOX_H) / 2 + focus) * s0
            let sc = 1 + (k - 1) * p
            let cx = vw / 2 + (Double(r.midX) - vw / 2) * p
            let cy = focusY + (Double(r.midY) - focusY) * p
            let hh = Double(r.height) / k / 2
            let top = p * max(0, focusY - hh), bottom = p * max(0, vh - focusY - hh)
            content
                .mask {
                    RoundedRectangle(cornerRadius: (p * 24) / k)
                        .padding(.top, top)
                        .padding(.bottom, bottom)
                }
                .scaleEffect(sc, anchor: .topLeading)
                .offset(x: cx - (vw / 2) * sc, y: cy - focusY * sc)
                .opacity(opacity)
        } else {
            content
                .scaleEffect(1 - 0.08 * MX.eio(cp))
                .opacity(opacity)
        }
    }
}

// MARK: - Copy layer (story13m.tsx HTML side)

private struct MatrixStoryCopyLayer: View {
    let model: MatrixStoryModel
    let t: Double
    let size: CGSize
    let reduceMotion: Bool

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }
    private static func springFast(_ frame: Double, _ fps: Double, stiffness k: Double = 100, damping c: Double = 10, mass m: Double = 1) -> Double {
        if frame <= 0 { return 0 }
        let tt = frame / fps, w0 = (k / m).squareRoot(), zeta = c / (2 * (k * m).squareRoot())
        if zeta < 1 {
            let wd = w0 * (1 - zeta * zeta).squareRoot()
            return 1 - exp(-zeta * w0 * tt) * (cos(wd * tt) + ((zeta * w0) / wd) * sin(wd * tt))
        }
        return 1 - exp(-w0 * tt) * (1 + w0 * tt)
    }

    var body: some View {
        let comp = MatrixStoryRuntime.composition(size)
        let cw = Double(comp.width), ch = Double(comp.height)
        let s0 = Double(size.width) / cw
        let ox = (cw - MatrixStoryRuntime.BOX_W) / 2, oy = (ch - MatrixStoryRuntime.BOX_H) / 2
        let lt = model.lt(t), since = model.since(t)
        let id = model.screen
        let leaving = model.collapseAt.map { t >= $0 } ?? false
        let a = { (at: Double, d: Double) -> Double in Self.eo((lt - at) / d) }
        let ca = { (at: Double, d: Double) -> Double in Self.eo((since - at) / d) }
        let white = Color.white
        let dz = model.dynamic && !reduceMotion
        let climax = MatrixClimaxCopy.byDay[max(0, min(6, model.day))]
        let copy = model.copy
        let cap40 = { (s: String) -> Text in MatrixRich.text(s, size: 40 * s0, weight: .medium, color: white.opacity(0.62), boldColor: white, boldWeight: .bold) }
        let taps = model.tapTimes.count, N = model.N
        let tapAt = model.tapTimes.last

        // design units (comp) -> points
        let u = { (v: Double) -> Double in v * s0 }

        let header: (eyebrow: String, title: String) = {
            if id == .climax {
                if model.sealT != nil { return (model.pos == .last ? "WEEK COMPLETE" : "SESSIONS", "") }
                return (model.pos == .last ? climax.lastEyebrow : climax.eyebrow, climax.title)
            }
            let h = model.copy.headers[id]
            return (h?.eyebrow ?? "", h?.title ?? "")
        }()

        ZStack(alignment: .topLeading) {
            // progress, one segment per screen
            HStack(spacing: u(12)) {
                ForEach(Array(model.ids.enumerated()), id: \.offset) { i, sid in
                    let fill = i < model.idx ? 1 : i > model.idx ? 0 : MX.cl(lt / model.cfg(sid).settle)
                    Capsule().fill(white.opacity(0.18))
                        .overlay(alignment: .leading) {
                            GeometryReader { g in Capsule().fill(white).frame(width: g.size.width * fill) }
                        }
                        .frame(height: u(7))
                }
            }
            .frame(width: u(cw - 120))
            .offset(x: u(60), y: u(max(oy, 0) + 90))
            .opacity(leaving ? 0 : 1)

            // the header
            VStack(spacing: 0) {
                if !header.eyebrow.isEmpty {
                    Text(header.eyebrow)
                        .font(.system(size: u(30), weight: .bold))
                        .tracking((0.16 + (1 - a(0.1, 0.3)) * 0.3) * u(30))
                        .foregroundStyle(white.opacity(0.55))
                }
                if !header.title.isEmpty {
                    let rise = 1 - Self.springFast(lt * 30 - 5, 30, stiffness: 220, damping: 11)
                    let pop = dz ? 1 + 0.25 * exp(-lt * 6) * cos(lt * 14) : 1
                    Text(header.title)
                        .font(.system(size: u(120), weight: .heavy, design: .rounded))
                        .tracking(-0.03 * u(120))
                        .foregroundStyle(white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, u(12))
                        .offset(y: u(rise * 50))
                        .scaleEffect(pop)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: u(960))
            .offset(x: u(ox + 60), y: u(oy + 250))
            .opacity(a(0.1, 0.3))

            // verified: the caption and the unlocked-apps pill
            if id == .verified {
                VStack(spacing: u(34)) {
                    if let cap = copy.captions[.verified] { cap40(cap) }
                    if let n = copy.appsUnlocked, n > 0 {
                        HStack(spacing: u(16)) {
                            Circle().fill(MatrixRGB.coral.color).frame(width: u(14), height: u(14))
                            Text(n == 1 ? "1 app unlocked" : "\(n) apps unlocked")
                                .font(.system(size: u(32), weight: .bold))
                                .foregroundStyle(white)
                        }
                        .padding(.vertical, u(20))
                        .padding(.horizontal, u(34))
                        .background(Capsule().fill(white.opacity(0.1)))
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: u(860))
                .offset(x: u(ox + 110), y: u(oy + 1350) + (1 - a(0.9, 0.4)) * u(20))
                .opacity(a(0.9, 0.4))
            }

            // today: when the session ran, its line and its real figures
            if id == .today, let td = copy.today {
                VStack(spacing: 0) {
                    Group {
                        if let e = td.end {
                            Text("\(Text(td.start)) \(Text("to").foregroundStyle(white.opacity(0.4))) \(Text(e))")
                        } else {
                            Text("\(Text("In at").foregroundStyle(white.opacity(0.4))) \(Text(td.start))")
                        }
                    }
                    .font(.system(size: u(64), weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(white)
                    if let c = td.caption {
                        cap40(c).padding(.top, u(14))
                    }
                    if !td.stats.isEmpty {
                        MatrixStatsRow(stats: td.stats, u: u, lt: lt, rollAt: 2.2, rollStep: 0.1)
                            .padding(.top, u(50))
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: u(860))
                .offset(x: u(ox + 110), y: u(oy + 1250))
                .opacity(a(2.1, 0.4))
            }

            // week: the caption and the research line
            if id == .week {
                VStack(spacing: u(30)) {
                    if let cap = copy.captions[.week] { cap40(cap) }
                    if let r = copy.research[.week] {
                        MatrixRich.text(r, size: u(30), weight: .medium, color: white.opacity(0.42), boldColor: white, boldWeight: .bold)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: u(860))
                .offset(x: u(ox + 110), y: u(oy + 1280) + (1 - a(0.8, 0.4)) * u(20))
                .opacity(a(0.8, 0.4))
            }

            // month (no target to pick): the caption, the month's figures, the research line.
            // With a target to pick, MatrixMonthPicker draws this block so its buttons take taps.
            if id == .month && !model.monthPick {
                MatrixMonthBlock(model: model, lt: lt, u: u, picker: nil)
                    .frame(width: u(900))
                    .offset(x: u(ox + 90), y: u(oy + 1230) + (1 - a(0.7, 0.4)) * u(20))
                    .opacity(a(0.7, 0.4))
            }

            // far: day of the habit and the sessions, then the quieter time line
            if id == .far, let cap = copy.captions[.far] {
                VStack(spacing: 0) {
                    cap40(cap)
                    if let r = copy.research[.far] {
                        MatrixRich.text(r, size: u(40), weight: .medium, color: white.opacity(0.42), boldColor: white.opacity(0.62), boldWeight: .bold)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: u(840))
                .offset(x: u(ox + 120), y: u(oy + 1340) + (1 - a(1.4, 0.4)) * u(20))
                .opacity(a(1.4, 0.4))
            }

            // the climax, before the seal: the instruction and one dot per tap
            if id == .climax && model.sealT == nil {
                VStack(spacing: u(40)) {
                    MatrixRich.text(climax.sub(N), size: u(40), weight: .medium, color: white.opacity(0.62), boldColor: white, boldWeight: .bold)
                        .multilineTextAlignment(.center)
                    HStack(spacing: u(16)) {
                        ForEach(0..<N, id: \.self) { k in
                            let pop = k == taps - 1 && tapAt != nil ? 1 + 0.4 * max(0, 1 - (t - (tapAt ?? t)) * 4) : 1
                            Circle()
                                .fill(k < taps ? white : .clear)
                                .overlay { if k >= taps { Circle().strokeBorder(white.opacity(0.4), lineWidth: u(3)) } }
                                .frame(width: u(30), height: u(30))
                                .scaleEffect(pop)
                        }
                    }
                }
                .frame(width: u(860))
                .offset(x: u(ox + 110), y: u(oy + 1300))
                .opacity(a(0.4, 0.4))
            }

            // the climax, after the seal: the end line and the week's tail
            if id == .climax && model.sealT != nil {
                VStack(spacing: u(24)) {
                    MatrixRich.text(climax.end, size: u(46), weight: .bold, color: white, boldColor: white, boldWeight: .bold)
                    MatrixRich.text([MatrixClimaxCopy.posTail(model.pos), copy.endSub].filter { !$0.isEmpty }.joined(separator: " "), size: u(36), weight: .medium, color: white.opacity(0.62), boldColor: white, boldWeight: .bold)
                }
                .multilineTextAlignment(.center)
                .frame(width: u(860))
                .offset(x: u(ox + 110), y: u(oy + 1300) + (1 - ca(1.7, 0.4)) * u(20))
                .opacity(ca(1.7, 0.4))
            }

            // the month's last session: the month closes on its own line above the art
            if id == .climax, model.sealT != nil, model.monthPos == .last, model.pos == .last,
               let cal = model.cal, let name = copy.monthName {
                let hit = cal.sessions >= cal.target
                let coral = MatrixRGB.coral.color
                Group {
                    if hit {
                        Text("\(name), \(Text("done.").foregroundStyle(coral))")
                    } else {
                        Text("\(name): \(Text(String(cal.sessions)).foregroundStyle(coral)) of \(cal.target).")
                    }
                }
                .font(.system(size: u(60), weight: .heavy, design: .rounded))
                .tracking(0.02 * u(60))
                .foregroundStyle(white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: u(1080))
                .scaleEffect(1 + 0.25 * (1 - ca(2.4, 0.6)))
                .offset(x: u(ox), y: u(oy + 560))
                .opacity(ca(2.4, 0.5))
            }

            // the foot: a hint, or on the last screen the button that fills with each tap
            Group {
                if !model.isLast {
                    let show = model.settled(t)
                    HStack(spacing: u(14)) {
                        Text(id == .month && model.monthPick && !model.picked ? "Pick a target" : "Tap to continue")
                            .font(.system(size: u(30), weight: .semibold))
                            .tracking(0.04 * u(30))
                        Image(systemName: "chevron.right")
                            .font(.system(size: u(22), weight: .bold))
                            .opacity(show ? 1 : 0)
                    }
                    .foregroundStyle(white.opacity(show ? 0.45 + 0.25 * sin(lt * 4) : 0))
                } else {
                    let fill = model.sealT != nil ? 1 : min(1, Double(taps) / Double(N))
                    let label = model.sealT != nil ? copy.endButton : taps > 0 ? (taps >= N - 1 ? "One more" : climax.mid) : climax.idle
                    Text(label)
                        .font(.system(size: u(38), weight: .bold))
                        .foregroundStyle(Color(.sRGB, red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255))
                        .padding(.vertical, u(30))
                        .padding(.horizontal, u(80))
                        .background {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    white
                                    MatrixRGB.coral.color.frame(width: g.size.width * fill)
                                }
                            }
                        }
                        .clipShape(Capsule())
                        .opacity(a(0.4, 0.3))
                }
            }
            .frame(width: size.width, height: u(300))
            .offset(y: Double(size.height) - u(300))
            .opacity(leaving ? 0 : 1)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A stats row (story13m.tsx): equal columns split by hairlines; counts roll up with eo5.
private struct MatrixStatsRow: View {
    let stats: [MatrixStoryCopy.Stat]
    let u: (Double) -> Double
    let lt: Double
    let rollAt: Double
    let rollStep: Double

    private static func eo5(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 5) }

    var body: some View {
        let white = Color.white
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { k, s in
                let v: String = s.roll.map { n in
                    String(Int(JSMath.round(Self.eo5((lt - rollAt - Double(k) * rollStep) / 0.8) * Double(n))))
                } ?? s.value
                VStack(spacing: u(10)) {
                    HStack(alignment: .firstTextBaseline, spacing: u(6)) {
                        Text(v)
                            .font(.system(size: u(72), weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(s.coral ? MatrixRGB.coral.color : white)
                        if let unit = s.unit {
                            Text(unit)
                                .font(.system(size: u(26), weight: .heavy, design: .rounded))
                                .foregroundStyle(white.opacity(0.5))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    Text(s.label.uppercased())
                        .font(.system(size: u(20), weight: .bold))
                        .tracking(0.16 * u(20))
                        .foregroundStyle(white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if k > 0 { Rectangle().fill(white.opacity(0.14)).frame(width: 1) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(s.value)\(s.unit.map { " \($0)" } ?? ""), \(s.label.lowercased())")
            }
        }
    }
}

/// The month screen's block below the art: caption, then the target buttons or the month's
/// figures, then the research line (story13m.tsx, `id === 'month'`).
private struct MatrixMonthBlock: View {
    let model: MatrixStoryModel
    let lt: Double
    let u: (Double) -> Double
    /// non-nil when the month asks for a target
    let picker: ((Int) -> Void)?

    var body: some View {
        let white = Color.white
        let copy = model.copy
        VStack(spacing: 0) {
            if let cap = copy.captions[.month] {
                MatrixRich.text(cap, size: u(36), weight: .medium, color: white.opacity(0.62), boldColor: white, boldWeight: .bold)
            }
            if let picker {
                HStack(spacing: u(18)) {
                    ForEach(copy.monthTargets, id: \.n) { m in
                        let sel = model.picked && model.cal?.target == m.n
                        Button {
                            picker(m.n)
                        } label: {
                            VStack(spacing: u(8)) {
                                Text("\(m.n)")
                                    .font(.system(size: u(64), weight: .heavy, design: .rounded))
                                    .foregroundStyle(sel ? Color(.sRGB, red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255) : white)
                                Text(m.label.uppercased())
                                    .font(.system(size: u(18), weight: .bold))
                                    .tracking(0.16 * u(18))
                                    .foregroundStyle(sel ? Color.black.opacity(0.55) : white.opacity(0.5))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, u(20))
                            .padding(.bottom, u(16))
                            .background(RoundedRectangle(cornerRadius: u(30), style: .continuous).fill(sel ? white : white.opacity(0.08)))
                            .contentShape(RoundedRectangle(cornerRadius: u(30), style: .continuous))
                        }
                        .buttonStyle(MatrixPressStyle())
                        .accessibilityLabel("\(m.n) sessions, \(m.label)")
                        .accessibilityAddTraits(sel ? .isSelected : [])
                    }
                }
                .padding(.top, u(34))
            } else if !copy.monthStats.isEmpty {
                MatrixStatsRow(stats: copy.monthStats, u: u, lt: lt, rollAt: 0.8, rollStep: 0)
                    .padding(.top, u(34))
            }
            if let r = copy.research[.month] {
                MatrixRich.text(r, size: u(28), weight: .medium, color: white.opacity(0.42), boldColor: white, boldWeight: .bold)
                    .padding(.top, u(30))
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// The month screen with a target to pick: same place as the passive block, but its buttons take
/// taps (everything else on the overlay passes taps to the flow).
private struct MatrixMonthPicker: View {
    let model: MatrixStoryModel
    let t: Double
    let size: CGSize

    private static func eo(_ x: Double) -> Double { 1 - pow(1 - MX.cl(x), 3) }

    var body: some View {
        let comp = MatrixStoryRuntime.composition(size)
        let cw = Double(comp.width), ch = Double(comp.height)
        let s0 = Double(size.width) / cw
        let ox = (cw - MatrixStoryRuntime.BOX_W) / 2, oy = (ch - MatrixStoryRuntime.BOX_H) / 2
        let u = { (v: Double) -> Double in v * s0 }
        let lt = model.lt(t)
        let a = Self.eo((lt - 0.7) / 0.4)
        MatrixMonthBlock(model: model, lt: lt, u: u) { n in
            model.pickTarget(n, at: model.time(Date()))
        }
        .frame(width: u(900))
        .offset(x: u(ox + 90), y: u(oy + 1230) + (1 - a) * u(20))
        .opacity(a)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

private struct MatrixPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Parity self-test for the story board

#if DEBUG
extension MatrixParity {
    /// Golden values from mxstory.ts (finWed and count on a 52 x 112 board, cx 25.5, cy 52.5).
    public static func runStory() -> [String] {
        var fail: [String] = []
        func ctx(t: Double, taps: [Double], sealT: Double?) -> MatrixStoryContext {
            MatrixStoryContext(t: t, lt: 3, cx: 25.5, cy: 52.5, cols: 52, rows: 112, N: 5, taps: taps.count, tapTimes: taps, tapAt: taps.last, sealT: sealT, since: sealT.map { t - $0 } ?? -1, D: MatrixDayData(day: 23, week: 3, sessions: 14), day: 2, pos: .middle, weekDone: 3, weekToday: 1, pick: false, picked: false, pickAt: nil)
        }
        let cases: [(String, MatrixStoryContext, Bool, Int, Double)] = [
            ("finWed 3 taps", ctx(t: 50, taps: [48, 48.6, 49.4], sealT: nil), false, 548, 40930.2730297),
            ("finWed sealed", ctx(t: 50.9, taps: [48, 48.6, 49.4, 49.8, 50.2], sealT: 50.2), false, 484, 36546.0007385),
            ("count", ctx(t: 52.6, taps: [48, 48.6, 49.4, 49.8, 50.2], sealT: 50.2), true, 365, 29348.8163033),
        ]
        for (name, s, counted, n, sum) in cases {
            var g = MatrixBoard(width: 52, height: 112, cap: 1400)
            _ = MatrixStoryScenes.render(&g, .climax, counted: counted, s)
            let out = g.out()
            if out.count != n { fail.append("\(name): \(out.count) targets, want \(n)") }
            let got = checksum(out)
            if abs(got - sum) > 1e-9 * max(1, abs(sum)) { fail.append("\(name) checksum: got \(got), want \(sum)") }
        }
        return fail + runStoryAll()
    }

    /// Every done-flow screen, every day, against MatrixParityStory.swift.
    public static func runStoryAll() -> [String] {
        var fail: [String] = []
        for (id, day, k, counted, n, sum, phase, flash) in storyGolden {
            let c = k < 0 ? storyCountContext : storyContexts[k]
            let s = MatrixStoryContext(
                t: c.t, lt: c.lt, cx: 25.5, cy: 52.5, cols: 52, rows: 112, N: c.N, taps: c.taps.count, tapTimes: c.taps,
                tapAt: c.taps.last, sealT: c.sealT, since: c.sealT.map { c.t - $0 } ?? -1,
                D: MatrixDayData(day: 23, week: 3, sessions: 14), day: day, pos: c.pos, weekDone: c.done, weekToday: c.today,
                pick: c.pick, picked: c.picked, pickAt: c.pickAt, cal: storyCal
            )
            guard let screen = MatrixStoryScreen(rawValue: id) else {
                fail.append("unknown screen \(id)")
                continue
            }
            var g = MatrixBoard(width: 52, height: 112, cap: 1400)
            let o = MatrixStoryScenes.render(&g, screen, counted: counted, s)
            let out = g.out()
            let name = "\(id) day \(day) ctx \(k)\(counted ? " counted" : "")"
            if out.count != n { fail.append("\(name): \(out.count) targets, want \(n)") }
            let got = checksum(out)
            if abs(got - sum) > 1e-9 * max(1, abs(sum)) { fail.append("\(name) checksum: got \(got), want \(sum)") }
            if o.phase != phase { fail.append("\(name) phase: got \(o.phase ?? "nil"), want \(phase ?? "nil")") }
            if abs(o.flash - flash) > 1e-9 { fail.append("\(name) flash: got \(o.flash), want \(flash)") }
        }
        return fail
    }
}
#endif
