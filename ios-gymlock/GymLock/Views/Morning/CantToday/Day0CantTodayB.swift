//
//  Day0CantTodayB.swift
//  GymLock · the "can't today" screen · Day 0 look ("b": the polaroid promise)
//
//  Plays at the worst moment to skip (PauseFacts.isCritical). The user's own day 0 photo or video sits
//  in a polaroid with the week's flames on it. Under it a day reel, then a time reel, to promise their
//  day 0 self a new time. Cost chips with labels, home workout and skip (a 1.5 s hold when skipping
//  costs the week) sit around it, in FLOW order. Port of the approved prototype v-day0-b.html (the
//  can't-today part only; the 30 second video-first wait is the pause's).
//
//  Real data only: `input.data` (heading, targets, allowance, cost, week, order), `input.facts.day0`.
//  A missing value hides its element. Nothing here invents a number or a line of copy.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Palette, easing, small helpers

private enum D0B {
    /// The Day 0 surface (same as Day0PauseStage).
    static let surface = Color(red: 0.043, green: 0.043, blue: 0.047)
    /// The polaroid paper (#EFEDE8) and the ink on it (#1B1B1D).
    static let paper = Color(red: 0.937, green: 0.929, blue: 0.910)
    static let ink = Color(red: 0.106, green: 0.106, blue: 0.114)
    /// Light fills on dark (#F2F2F0) and light text (#F5F5F5).
    static let cream = Color(red: 0.949, green: 0.949, blue: 0.941)
    static let text = Color(red: 0.961, green: 0.961, blue: 0.961)
    /// The photo window's own dark (#101011).
    static let window = Color(red: 0.063, green: 0.063, blue: 0.067)

    /// Same colours as the pause's streak flame.
    static let flameOrange = Color(red: 1, green: 0.451, blue: 0)
    static let flameGradient = LinearGradient(
        colors: [
            Color(red: 0.847, green: 0.153, blue: 0.075),
            Color(red: 1, green: 0.451, blue: 0),
            Color(red: 1, green: 0.769, blue: 0.180),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The prototype's --ease: cubic-bezier(.2,.9,.25,1).
    static func curve(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.9, 0.25, 1, duration: duration)
    }

    static func ease(_ p: Double) -> Double {
        let q = min(1, max(0, p))
        return 1 - pow(1 - q, 3)
    }
}

private struct D0BFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Sizes (the prototype's three CSS size sets)

private struct D0BMetrics {
    let rh: CGFloat
    let rf: CGFloat
    let rf2: CGFloat
    let wh: CGFloat
    let polWidth: CGFloat
    let polPad: CGFloat
    let polPadBottom: CGFloat
    let miniW: CGFloat
    let miniH: CGFloat
    let miniGap: CGFloat
    let miniInset: CGFloat
    let bigW: CGFloat
    let bigH: CGFloat
    let noneW: CGFloat
    let noneH: CGFloat
    let chipH: CGFloat
    let chipPad: CGFloat
    let coreGap: CGFloat
    let headSize: CGFloat
    let ctaH: CGFloat
    let dchipH: CGFloat
    let dchipFont: CGFloat
    let labelFont: CGFloat
    let bottomPad: CGFloat
    let compact: Bool

    init(layout: CantTodayLayout) {
        let compact = layout.isCompact
        let large = layout.size.height >= 900
        self.compact = compact
        if compact {
            rh = 46; rf = 40; rf2 = 19; wh = 128
            polPad = 10; polPadBottom = 2
            miniW = 12; miniH = 14; miniGap = 5; miniInset = 10
            bigW = 84; bigH = 98; noneW = 60; noneH = 70
            chipH = 44; chipPad = 11; coreGap = 14
            headSize = 25; ctaH = 52; dchipH = 38; dchipFont = 15; labelFont = 13
            bottomPad = 54
        } else if large {
            rh = 70; rf = 58; rf2 = 28; wh = 230
            polPad = 12; polPadBottom = 4
            miniW = 15; miniH = 18; miniGap = 7; miniInset = 12
            bigW = 116; bigH = 136; noneW = 80; noneH = 94
            chipH = 48; chipPad = 13; coreGap = 16
            headSize = 33; ctaH = 56; dchipH = 42; dchipFont = 17; labelFont = 15
            bottomPad = 58
        } else {
            rh = 62; rf = 50; rf2 = 24; wh = 190
            polPad = 12; polPadBottom = 4
            miniW = 15; miniH = 18; miniGap = 7; miniInset = 12
            bigW = 116; bigH = 136; noneW = 80; noneH = 94
            chipH = 48; chipPad = 13; coreGap = 16
            headSize = 30; ctaH = 56; dchipH = 42; dchipFont = 17; labelFont = 15
            bottomPad = 58
        }
        polWidth = min(large ? 340 : 312, max(0, layout.size.width - 56))
    }

    var innerWidth: CGFloat { polWidth - polPad * 2 }
    var reelHeight: CGFloat { rh * 3.2 }
}

// MARK: - Time model (hour, minute and am/pm reels, 5 minute steps)

private enum D0BReel {
    case hour, minute, meridiem
}

private enum D0BBeat: Hashable {
    case day, time
}

private struct D0BResched: Equatable {
    let day: String
    let h: String
    let m: String
    let ap: String
    let weekIndex: Int
}

private enum D0BAnswer: Equatable {
    case reschedule(D0BResched)
    case home
    case skip
    case close
}

private enum D0BTime {
    static func minutes(h: Int, m: Int, p: Int) -> Int {
        (((h + 1) % 12) + (p == 1 ? 12 : 0)) * 60 + m * 5
    }

    /// Reel indices for a time of day: hour 0...11 (1 to 12), minute 0...11 (steps of 5), am/pm 0...1.
    static func parts(_ minutes: Int) -> (h: Int, m: Int, p: Int) {
        let stepped = Int((Double(minutes) / 5.0).rounded()) * 5
        let w = CantTodayClock.wrap(stepped)
        let h24 = w / 60
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return (h12 - 1, (w % 60) / 5, h24 >= 12 ? 1 : 0)
    }

    /// The closest time the rule allows, searching outward in 5 minute steps.
    static func nearest(_ data: CantTodayData, _ target: CantTodayTarget, from c: Int) -> Int {
        var s = 5
        while s <= 720 {
            for sign in [1, -1] {
                let m = CantTodayClock.wrap(c + sign * s)
                if data.allowed(target, minutes: m).isOK { return m }
            }
            s += 5
        }
        return c
    }

    /// Where the reels open for a target: its default time, or the nearest allowed one.
    static func start(_ data: CantTodayData, _ target: CantTodayTarget) -> Int {
        let base = CantTodayClock.wrap(target.defaultMinutes)
        if data.allowed(target, minutes: base).isOK { return base }
        return nearest(data, target, from: base)
    }

    static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

// MARK: - The flame (the prototype's own path, 24 x 28)

private struct D0BFlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 28
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: p(13, 1))
        path.addCurve(to: p(19.8, 16), control1: p(14.6, 5.6), control2: p(19.6, 9))
        path.addCurve(to: p(12, 26.6), control1: p(20, 21.6), control2: p(16.6, 26.6))
        path.addCurve(to: p(4.2, 17), control1: p(7.4, 26.6), control2: p(4, 22.6))
        path.addCurve(to: p(7.8, 9.2), control1: p(4.3, 13.6), control2: p(6, 11))
        path.addCurve(to: p(9.8, 12.4), control1: p(8, 11), control2: p(8.8, 12))
        path.addCurve(to: p(13, 1), control1: p(9, 8), control2: p(10.4, 4.2))
        path.closeSubpath()
        path.move(to: p(12, 24.2))
        path.addCurve(to: p(8.6, 20.8), control1: p(9.9, 24.2), control2: p(8.6, 22.6))
        path.addCurve(to: p(11.4, 15.6), control1: p(8.6, 18.6), control2: p(10.5, 17.4))
        path.addCurve(to: p(13.4, 18), control1: p(11.7, 16.8), control2: p(12.6, 17.2))
        path.addCurve(to: p(15.4, 20.8), control1: p(14.2, 18.8), control2: p(15.4, 19.4))
        path.addCurve(to: p(12, 24.2), control1: p(15.4, 22.6), control2: p(14.1, 24.2))
        path.closeSubpath()
        return path
    }
}

/// One flame on the polaroid's week row.
private struct D0BMiniFlame: View {
    enum Look {
        case lit, today, planned, free, past, rest
    }

    let look: Look
    let selected: Bool
    let width: CGFloat
    let height: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let lit = look == .lit || selected
        ZStack {
            D0BFlameShape()
                .fill(D0B.flameGradient, style: FillStyle(eoFill: true))
                .opacity(lit ? 1 : 0)
            D0BFlameShape()
                .stroke(strokeColor, style: strokeStyle)
                .opacity(lit ? 0 : 1)
        }
        .frame(width: width, height: height)
        .shadow(color: selected ? D0B.flameOrange.opacity(0.7) : Color.clear, radius: 5, y: 3)
        .scaleEffect(selected && !reduceMotion ? 1.18 : 1)
        .offset(y: selected && !reduceMotion ? -3 : 0)
        .animation(D0B.curve(0.3), value: selected)
        .animation(.linear(duration: 0.2), value: lit)
    }

    private var strokeColor: Color {
        switch look {
        case .lit: return Color.white.opacity(0.42)
        case .today: return Color.white
        case .planned: return Color.white.opacity(0.75)
        case .free: return Color.white.opacity(0.85)
        case .past: return Color.white.opacity(0.22)
        case .rest: return Color.white.opacity(0.42)
        }
    }

    private var strokeStyle: StrokeStyle {
        if look == .planned {
            return StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [2.6, 2.8])
        }
        return StrokeStyle(lineWidth: 1.5, lineJoin: .round)
    }
}

// MARK: - Styles and modifiers

/// Press feedback on touch-down (scale), and a callback so the nudges stop at once.
private struct D0BPressStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    var onPress: (Bool) -> Void = { _ in }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPress(pressed)
            }
    }
}

/// The "touch me" wave on a chip or a round control: lift, a touch of light, a faint ring of glow.
private struct D0BLift: ViewModifier {
    let amount: Double
    let ink: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let a = min(1.15, max(0, amount))
        let glow = ink ? D0B.ink.opacity(0.28 * a) : Color.white.opacity(0.34 * a)
        content
            .offset(y: reduceMotion ? 0 : CGFloat(-4 * a))
            .scaleEffect(reduceMotion ? 1 : CGFloat(1 + 0.04 * a))
            .brightness(0.22 * a)
            .shadow(color: glow, radius: 8)
    }
}

private struct D0BIntro: ViewModifier {
    let appeared: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: (appeared || reduceMotion) ? 0 : 14)
            .animation(D0B.curve(0.42).delay(delay), value: appeared)
    }
}

/// Everything the per-frame pieces need, computed once per frame.
private struct D0BCtx {
    let t: Double
    let m: D0BMetrics
    /// Skip-hold progress through the look (0...1).
    let h: Double
    let nz: [String: Double]
    let done: Bool
}

// MARK: - The screen

struct Day0CantTodayB: View {
    let input: CantTodayInput

    @State private var holder = Day0PauseVideoHolder()
    @State private var photo: UIImage?
    @State private var nudger: CantTodayNudger
    @State private var t0: Double = Date().timeIntervalSinceReferenceDate

    @State private var beat: D0BBeat
    @State private var appeared: Bool
    @State private var dayIdx: Int
    @State private var hIdx: Int
    @State private var mIdx: Int
    @State private var pIdx: Int
    @State private var dayBusy = false
    @State private var hBusy = false
    @State private var mBusy = false
    @State private var pBusy = false

    @State private var noteText = ""
    @State private var noteOn = false
    @State private var noteToken = 0

    @State private var holdProgress = 0.0
    @State private var isHolding = false
    @State private var holdStep = 0
    @State private var bump = 0.0
    @State private var skipLocked = false

    @State private var answer: D0BAnswer?
    @State private var polFrame: CGRect = .zero
    @State private var polFlat = false
    @State private var bigIn = false
    @State private var winB = 0.0
    @State private var winS = 1.0

    init(input: CantTodayInput) {
        self.input = input
        let data = input.data
        let opensOnTime = input.startsOnReschedule && !data.targets.isEmpty
        var day = 0
        if opensOnTime { day = data.targets.firstIndex { $0.isToday } ?? 0 }
        var parts = (h: 0, m: 0, p: 0)
        if data.targets.indices.contains(day) {
            parts = D0BTime.parts(D0BTime.start(data, data.targets[day]))
        }
        _nudger = State(initialValue: CantTodayNudger(haptics: input.haptics, reduceMotion: input.reduceMotion))
        _beat = State(initialValue: opensOnTime ? .time : .day)
        _appeared = State(initialValue: input.startsOnReschedule)
        _dayIdx = State(initialValue: day)
        _hIdx = State(initialValue: parts.h)
        _mIdx = State(initialValue: parts.m)
        _pIdx = State(initialValue: parts.p)
    }

    // MARK: Derived

    private var reduce: Bool { input.reduceMotion }

    private var target: CantTodayTarget? {
        let tg = input.data.targets
        guard !tg.isEmpty else { return nil }
        return tg[min(max(dayIdx, 0), tg.count - 1)]
    }

    private var currentMinutes: Int { D0BTime.minutes(h: hIdx, m: mIdx, p: pIdx) }

    private var timeIsOK: Bool {
        guard let target else { return false }
        return input.data.allowed(target, minutes: currentMinutes).isOK
    }

    private var reelsBusy: Bool { dayBusy || hBusy || mBusy || pBusy }

    private var closing: Bool { answer == .close }

    private func clock() -> Double { Date().timeIntervalSinceReferenceDate - t0 }

    // MARK: Body

    var body: some View {
        TimelineView(.animation(paused: answer != nil)) { ctx in
            screen(t: ctx.date.timeIntervalSinceReferenceDate - t0)
        }
        .onAppear {
            appeared = true
            startVideo()
        }
        .onDisappear { holder.stop() }
        .task(id: input.facts.day0?.fileName) { await loadPhoto() }
        .task(id: beat) { await armNudges() }
        .onChange(of: reelsBusy) { _, busy in
            if busy {
                nudger.cancel()
                nudger.touched(kind: "reel")
            } else {
                nudger.rest(at: clock())
                noteIfBlocked()
            }
        }
        .onChange(of: holdProgress) { _, p in
            guard isHolding else { return }
            if p > 0.33, holdStep < 1 {
                holdStep = 1
                input.haptics.play(.light)
            }
            if p > 0.66, holdStep < 2 {
                holdStep = 2
                input.haptics.play(.light)
            }
        }
    }

    @ViewBuilder
    private func screen(t: Double) -> some View {
        let layout = input.layout
        let m = D0BMetrics(layout: layout)
        let done = answer != nil
        let h = skipLocked ? 1.0 : D0B.ease(holdProgress)
        let c = D0BCtx(t: t, m: m, h: h, nz: nudgeAmounts(t), done: done)

        ZStack(alignment: .topLeading) {
            D0B.surface

            VStack(spacing: 0) {
                headingView(c)
                    .modifier(D0BIntro(appeared: appeared, delay: 0, reduceMotion: reduce))
                    .opacity(done ? 0 : 1)
                    .animation(.linear(duration: 0.22), value: done)
                coreView(c)
                    .modifier(D0BIntro(appeared: appeared, delay: 0.06, reduceMotion: reduce))
                bottomRow(c)
                    .modifier(D0BIntro(appeared: appeared, delay: 0.14, reduceMotion: reduce))
                    .opacity(done ? 0 : 1)
                    .animation(.linear(duration: 0.22), value: done)
            }
            .padding(.top, layout.contentTop)
            .padding(.bottom, layout.safeArea.bottom + m.bottomPad)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .opacity(closing ? 0 : 1)
            .animation(.linear(duration: 0.4), value: closing)

            progressBar(done: done)
                .opacity(closing ? 0 : 1)
            closeButton
            endText
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .clipped()
        .onPreferenceChange(D0BFrameKey.self) { frame in
            if frame != polFrame { polFrame = frame }
        }
    }

    // MARK: Chrome

    private func headingView(_ c: D0BCtx) -> some View {
        Text(input.data.heading)
            .font(.system(size: c.m.headSize, weight: .heavy))
            .tracking(-0.025 * c.m.headSize)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: Color.black.opacity(0.5), radius: 7, y: 1)
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    /// Two segments: day (always full), time (fills when the time reel opens).
    private func progressBar(done: Bool) -> some View {
        let layout = input.layout
        return HStack(spacing: 4) {
            segment(full: true)
            segment(full: beat == .time)
        }
        .frame(height: 2)
        .padding(.horizontal, 16)
        .padding(.top, layout.safeArea.top + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(appeared && !done ? 1 : 0)
        .animation(.linear(duration: 0.3), value: done)
        .animation(.linear(duration: 0.4), value: appeared)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func segment(full: Bool) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.25))
            Capsule()
                .fill(Color.white)
                .scaleEffect(x: full ? 1 : 0.0001, y: 1, anchor: .leading)
                .animation(D0B.curve(0.42), value: full)
        }
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        let layout = input.layout
        return Button {
            closeTap()
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.16))
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 36, height: 36)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(D0BPressStyle(scale: 0.95))
        .accessibilityLabel("close, keep going")
        .padding(.top, layout.safeArea.top + 6)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .opacity(closing ? 0 : 1)
        .animation(.linear(duration: 0.3), value: closing)
        .allowsHitTesting(answer == nil)
    }

    private var endText: some View {
        Text("closed. still going.")
            .font(.system(size: 19))
            .foregroundStyle(Color.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(closing ? 1 : 0)
            .animation(D0B.curve(0.6), value: closing)
            .allowsHitTesting(false)
            .accessibilityHidden(!closing)
    }

    // MARK: Core: polaroid + cost chips

    private func coreView(_ c: D0BCtx) -> some View {
        VStack(spacing: c.m.coreGap) {
            polaroid(c)
            if !input.data.cost.isEmpty {
                chipsRow(c)
                    .frame(height: 40)
                    .opacity(c.done || beat == .time ? 0 : 1)
                    .animation(.linear(duration: 0.25), value: beat)
                    .animation(.linear(duration: 0.22), value: c.done)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func polaroid(_ c: D0BCtx) -> some View {
        let m = c.m
        let dy: CGFloat = polFrame == .zero ? 0 : input.layout.size.height / 2 - polFrame.midY + 4
        let flat = polFlat
        let drop: CGFloat = reduce ? 0 : CGFloat(5 * c.h)
        return VStack(spacing: 0) {
            windowView(c)
            magicView(c)
                .padding(.top, 6)
        }
        .padding(.horizontal, m.polPad)
        .padding(.top, m.polPad)
        .padding(.bottom, m.polPadBottom)
        .frame(width: m.polWidth)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(D0B.paper)
                .shadow(color: Color.black.opacity(0.45), radius: 20, y: 18)
        )
        .background(
            GeometryReader { g in
                Color.clear.preference(key: D0BFrameKey.self, value: g.frame(in: .global))
            }
        )
        .rotationEffect(.degrees(flat ? 0 : -1.6))
        .offset(y: flat ? dy : drop)
        .scaleEffect(flat ? 1.04 : 1)
        .animation(D0B.curve(0.56), value: polFlat)
    }

    // MARK: The photo window

    private func windowView(_ c: D0BCtx) -> some View {
        let m = c.m
        let inner = m.innerWidth
        let day0 = input.facts.day0
        let bigY = m.wh * 0.46
        let radius = hypot(inner, m.wh) / 2
        return ZStack(alignment: .topLeading) {
            D0B.window

            if let day0 {
                mediaLayer(day0, width: inner, height: m.wh)
                    .opacity(0.8)
            } else {
                D0BFlameShape()
                    .stroke(Color.white.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .frame(width: m.noneW, height: m.noneH)
                    .position(x: inner / 2, y: bigY)
                    .opacity(c.done ? 0 : 1)
                    .animation(.linear(duration: 0.22), value: c.done)
            }

            // Vignette and a shade at the top, so the week's flames always read.
            RadialGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.6)],
                center: UnitPoint(x: 0.5, y: 0.46),
                startRadius: radius * 0.36,
                endRadius: radius
            )
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: m.wh * 0.46)

            miniWeek(c)
                .padding(.leading, m.miniInset)
                .padding(.top, m.miniInset)
                .opacity(c.done ? 0 : 1 - 0.7 * c.h)
                .animation(.linear(duration: 0.22), value: c.done)

            bigGlyph(c)

            if let day0 {
                HStack(spacing: 0) {
                    Text("you, day 0 ")
                        .fontWeight(.heavy)
                    Text("· " + day0.capturedAt.formatted(.dateTime.month(.abbreviated).day()).lowercased())
                        .fontWeight(.bold)
                        .opacity(0.8)
                }
                .font(.system(size: m.labelFont, design: .rounded))
                .foregroundStyle(D0B.text)
                .shadow(color: Color.black.opacity(0.7), radius: 4, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, 11)
            }
        }
        .frame(width: inner, height: m.wh)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .saturation(max(0, (1 - 0.9 * c.h) * winS))
        .brightness(-0.6 * c.h + bump + winB)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mediaLayer(_ day0: Day0Media, width: CGFloat, height: CGFloat) -> some View {
        switch day0.kind {
        case .video:
            D0BPlayerView(player: holder.player)
                .frame(width: width, height: height)
                .clipped()
        case .photo:
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            }
        }
    }

    private func miniWeek(_ c: D0BCtx) -> some View {
        let data = input.data
        let free = Set(data.targets.map { $0.weekIndex })
        let selected = target?.weekIndex
        let today = data.todayIndex ?? 0
        return HStack(spacing: c.m.miniGap) {
            ForEach(Array(data.week.enumerated()), id: \.offset) { i, day in
                D0BMiniFlame(
                    look: miniLook(i, day, free: free, today: today),
                    selected: selected == i,
                    width: c.m.miniW,
                    height: c.m.miniH,
                    reduceMotion: reduce
                )
            }
        }
    }

    private func miniLook(_ i: Int, _ day: PauseWeekDay, free: Set<Int>, today: Int) -> D0BMiniFlame.Look {
        switch day.state {
        case .done: return .lit
        case .today: return .today
        case .planned: return .planned
        case .missed: return .past
        case .rest:
            if free.contains(i) { return .free }
            return i < today ? .past : .rest
        }
    }

    /// What lands in the window once an answer is taken.
    @ViewBuilder
    private func bigGlyph(_ c: D0BCtx) -> some View {
        let m = c.m
        let inner = m.innerWidth
        let y = m.wh * 0.46
        if let answer {
            switch answer {
            case .reschedule(let r):
                let mx = m.miniInset + CGFloat(r.weekIndex) * (m.miniW + m.miniGap) + m.miniW / 2
                let my = m.miniInset + m.miniH / 2
                D0BFlameShape()
                    .fill(D0B.flameGradient, style: FillStyle(eoFill: true))
                    .frame(width: m.bigW, height: m.bigH)
                    .shadow(color: D0B.flameOrange.opacity(0.65), radius: 14, y: 10)
                    .offset(x: bigIn || reduce ? 0 : mx - inner / 2, y: bigIn || reduce ? 0 : my - y)
                    .scaleEffect(bigIn || reduce ? 1 : m.miniW / m.bigW)
                    .opacity(reduce && !bigIn ? 0 : 1)
                    .position(x: inner / 2, y: y)
                    .onAppear { raiseBig(flies: true) }
            case .home:
                VStack(spacing: m.compact ? 10 : 14) {
                    Image(systemName: "house")
                        .font(.system(size: m.compact ? 56 : 76, weight: .semibold))
                        .foregroundStyle(D0B.text)
                    pips(filled: max(0, input.data.homeLeft - 1), total: input.data.homeOf, size: 8, line: 1.5, gap: 5)
                }
                .scaleEffect(bigIn || reduce ? 1 : 0.8)
                .opacity(bigIn ? 1 : 0)
                .position(x: inner / 2, y: y - 12)
                .onAppear { raiseBig(flies: false) }
            case .skip:
                D0BFlameShape()
                    .stroke(Color.white.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .frame(width: m.bigW, height: m.bigH)
                    .position(x: inner / 2, y: y)
            case .close:
                EmptyView()
            }
        }
    }

    // MARK: The reel area under the photo

    private func magicView(_ c: D0BCtx) -> some View {
        let m = c.m
        let hasT = !input.data.targets.isEmpty
        let isTime = beat == .time
        let slide: CGFloat = reduce ? 0 : 18
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(D0B.ink.opacity(0.07))
                .frame(height: m.rh)
                .padding(.horizontal, 6)

            if hasT {
                dayReel(c)
                    .opacity(isTime || c.done ? 0 : 1)
                    .offset(y: isTime ? -slide : 0)
                    .allowsHitTesting(!isTime && !c.done)
                    .accessibilityHidden(isTime || c.done)

                timeRow(c)
                    .opacity(isTime && !c.done ? 1 : 0)
                    .offset(y: isTime ? 0 : slide)
                    .allowsHitTesting(isTime && !c.done)
                    .accessibilityHidden(!isTime || c.done)
            }

            finView(c)
                .opacity(c.done && !closing ? 1 : 0)

            Text(noteText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(D0B.ink.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 2)
                .opacity(noteOn && !c.done ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(height: m.reelHeight)
        .animation(D0B.curve(0.4), value: beat)
        .animation(.linear(duration: 0.3), value: c.done)
    }

    // Day reel

    private func dayReel(_ c: D0BCtx) -> some View {
        let tg = input.data.targets
        let wraps = tg.count >= 3
        let a = c.nz["dr"] ?? 0
        let sign: CGFloat = (!wraps && dayIdx >= tg.count - 1) ? -1 : 1
        return CantTodayDrum(
            count: tg.count,
            selection: $dayIdx,
            rowHeight: c.m.rh,
            visibleRows: 3,
            wraps: wraps,
            isBlocked: { _ in false },
            onBlocked: { _ in },
            onDetent: { input.haptics.play(.light) },
            isInteracting: $dayBusy
        ) { index, dist in
            reelRow(
                index < tg.count ? tg[index].short : "",
                dist: dist,
                size: c.m.rf * 1.25,
                tracking: -0.03 * c.m.rf * 1.25,
                align: .center,
                dim: false,
                rowHeight: c.m.rh,
                nudge: a,
                sign: sign
            )
        }
        .frame(height: c.m.reelHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("day")
        .accessibilityValue(target?.name ?? "")
        .accessibilityAdjustableAction { direction in adjustDay(direction) }
    }

    // Time row: day chip, hour, colon, minute, am/pm

    private func timeRow(_ c: D0BCtx) -> some View {
        let m = c.m
        return HStack(spacing: 0) {
            dayChip(c)
                .padding(.trailing, 6)
            timeReel(.hour, c)
                .frame(width: m.rf * 1.3)
            Text(":")
                .font(.system(size: m.rf, weight: .heavy, design: .rounded))
                .foregroundStyle(D0B.ink.opacity(0.9))
                .frame(width: m.rf * 0.26, height: m.rh)
                .offset(y: -m.rf * 0.04)
                .accessibilityHidden(true)
            timeReel(.minute, c)
                .frame(width: m.rf * 1.35)
            timeReel(.meridiem, c)
                .frame(width: m.rf2 * 1.9)
                .padding(.leading, 4)
        }
        .frame(height: m.reelHeight)
    }

    private func dayChip(_ c: D0BCtx) -> some View {
        let m = c.m
        let a = c.nz["dchip"] ?? 0
        return Button {
            nudger.touched(kind: "chip")
            goDay()
        } label: {
            Text(target?.short ?? "")
                .font(.system(size: m.dchipFont, weight: .heavy, design: .rounded))
                .foregroundStyle(D0B.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(minWidth: m.compact ? 48 : 52)
                .frame(height: m.dchipH)
                .background(Capsule().fill(D0B.ink))
                .modifier(D0BLift(amount: a, ink: true, reduceMotion: reduce))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(D0BPressStyle(scale: 0.95, onPress: { pressed in
            if pressed {
                nudger.cancel()
                nudger.touched(kind: "chip")
            } else {
                nudger.rest(at: clock())
            }
        }))
        .accessibilityLabel("change day")
        .accessibilityValue(target?.name ?? "")
    }

    private func timeReel(_ r: D0BReel, _ c: D0BCtx) -> some View {
        let m = c.m
        let key: String
        let count: Int
        let label: String
        switch r {
        case .hour: key = "rh"; count = 12; label = "hour"
        case .minute: key = "rm"; count = 12; label = "minute"
        case .meridiem: key = "rpp"; count = 2; label = "am or pm"
        }
        let a = c.nz[key] ?? 0
        let wraps = r != .meridiem
        let sign: CGFloat = (!wraps && pIdx >= 1) ? -1 : 1
        return CantTodayDrum(
            count: count,
            selection: binding(r),
            rowHeight: m.rh,
            visibleRows: 3,
            wraps: wraps,
            // Every value can be picked. A time that can't be an alarm stays dim, says why, and
            // "set alarm" waits until the time is a valid one (Rishi, 2026-11-25).
            isBlocked: { _ in false },
            onBlocked: { _ in },
            onDetent: { input.haptics.play(.light) },
            isInteracting: busyBinding(r)
        ) { index, dist in
            reelRow(
                reelText(r, index),
                dist: dist,
                size: r == .meridiem ? m.rf2 : m.rf,
                tracking: r == .meridiem ? 0 : -0.025 * m.rf,
                align: r == .hour ? .trailing : (r == .minute ? .leading : .center),
                dim: !timeIsOK,
                rowHeight: m.rh,
                nudge: a,
                sign: sign
            )
        }
        .frame(height: m.reelHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(reelText(r, index(of: r)))
        .accessibilityAdjustableAction { direction in adjustTime(r, direction) }
    }

    private func reelText(_ r: D0BReel, _ i: Int) -> String {
        switch r {
        case .hour: return "\(i + 1)"
        case .minute: return D0BTime.pad(i * 5)
        case .meridiem: return i == 0 ? "am" : "pm"
        }
    }

    /// One drum row: shrinks and fades away from the centre, tips back like the prototype's 3D drum.
    private func reelRow(
        _ text: String,
        dist: CGFloat,
        size: CGFloat,
        tracking: CGFloat,
        align: Alignment,
        dim: Bool,
        rowHeight: CGFloat,
        nudge: Double,
        sign: CGFloat
    ) -> some View {
        let a = Double(abs(dist))
        let scale = 1 - 0.27 * min(a, 1.7)
        let op = pow(max(0, 1 - a * 0.43), 1.5)
        let tilt = max(-70, min(70, Double(-dist) * 34))
        let n = min(1.15, max(0, nudge))
        let shift: CGFloat = reduce ? 0 : -sign * CGFloat(n) * 0.6 * rowHeight
        let fade: Double = reduce ? 1 - 0.45 * min(1, n) : 1
        return Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .tracking(tracking)
            .foregroundStyle(D0B.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: align)
            .frame(height: rowHeight)
            .scaleEffect(CGFloat(scale))
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .offset(y: shift)
            .opacity(op * (dim ? 0.34 : 1) * fade)
    }

    // Confirm line under the photo (the polaroid's caption)

    private func finView(_ c: D0BCtx) -> some View {
        let m = c.m
        return HStack(spacing: 10) {
            if let a = answer {
            switch a {
            case .reschedule(let r):
                Text(r.day)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(D0B.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 15)
                    .frame(height: 40)
                    .background(Capsule().fill(D0B.ink))
                Text("\(r.h):\(r.m)")
                    .font(.system(size: m.rf * 1.08, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.03 * m.rf)
                    .foregroundStyle(D0B.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(r.ap)
                    .font(.system(size: m.rf2 * 1.1, weight: .heavy, design: .rounded))
                    .foregroundStyle(D0B.ink)
            case .home:
                Text("\(input.data.homeMinutes ?? 0)")
                    .font(.system(size: m.rf * 1.08, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.03 * m.rf)
                    .foregroundStyle(D0B.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("min")
                    .font(.system(size: m.rf2 * 1.1, weight: .heavy, design: .rounded))
                    .foregroundStyle(D0B.ink)
            case .skip:
                Text("skipped")
                    .font(.system(size: m.rf * 0.9, weight: .heavy, design: .rounded))
                    .tracking(-0.03 * m.rf)
                    .foregroundStyle(D0B.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            case .close:
                EmptyView()
            }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!c.done)
    }

    // MARK: Cost chips

    private func chipsRow(_ c: D0BCtx) -> some View {
        HStack(spacing: 8) {
            ForEach(input.data.cost) { cost in
                chip(cost, c)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    private func chip(_ cost: CantTodayCost, _ c: D0BCtx) -> some View {
        let m = c.m
        let label: String
        switch cost.kind {
        case .week: label = "this week"
        case .row: label = "in a row"
        case .streak: label = input.data.streakWeeks == 1 ? "week" : "weeks"
        }
        let fore = cost.hot ? Theme.accent : D0B.text
        let labelColor = cost.hot ? Theme.accent.opacity(0.85) : Color.white.opacity(0.62)
        let fill = cost.hot ? Theme.accent.opacity(0.16) : Color.white.opacity(0.13)
        let h = c.h
        // The streak flame shrinks and gutters while the skip is held; its number fades.
        let flicker = 0.6 + 0.4 * abs(sin(c.t * 31) * sin(c.t * 17 + 1))
        let flameScale: Double = reduce ? 1 : 1 - 0.5 * h + bump
        let flameOpacity: Double = (cost.hot && h > 0 && !reduce) ? 1 - h * (0.2 + 0.5 * (1 - flicker)) : 1
        let numberOpacity: Double = cost.hot ? 1 - h * 0.9 : 1

        return HStack(spacing: 7) {
            Group {
                switch cost.kind {
                case .week:
                    Image(systemName: "calendar")
                        .font(.system(size: 19, weight: .semibold))
                case .row:
                    Image(systemName: "repeat")
                        .font(.system(size: 19, weight: .semibold))
                case .streak:
                    D0BFlameShape()
                        .fill(fore, style: FillStyle(eoFill: true))
                        .frame(width: 17, height: 20)
                        .scaleEffect(CGFloat(flameScale), anchor: .bottom)
                        .opacity(flameOpacity)
                }
            }
            .foregroundStyle(fore)

            VStack(alignment: .leading, spacing: 1) {
                Text(cost.big)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.2)
                    .foregroundStyle(fore)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(numberOpacity)
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, m.chipPad)
        .frame(height: m.chipH)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cost.text)
    }

    // MARK: Bottom row: doors in FLOW order, reschedule in the middle

    @ViewBuilder
    private func bottomRow(_ c: D0BCtx) -> some View {
        let data = input.data
        let rest = data.order.filter { $0 != .reschedule }
        if !data.targets.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                sideSlot(rest.first, c)
                backSlot(c)
                ctaButton(c)
                sideSlot(rest.count > 1 ? rest[1] : nil, c)
            }
            .padding(.horizontal, 22)
            .frame(height: 56, alignment: .top)
        } else {
            HStack(alignment: .top, spacing: 28) {
                if let first = rest.first {
                    side(first, c)
                }
                if rest.count > 1 {
                    side(rest[1], c)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56, alignment: .top)
        }
    }

    /// A side slot closes up in the time beat so the "set alarm" button can widen.
    private func sideSlot(_ door: CantTodayDoor?, _ c: D0BCtx) -> some View {
        let isTime = beat == .time
        return Group {
            if let door {
                side(door, c)
            } else {
                Color.clear.frame(width: 72, height: 56)
            }
        }
        .frame(width: isTime ? 0 : 72, height: 56, alignment: .top)
        .padding(.horizontal, isTime ? -6 : 0)
        .opacity(isTime ? 0 : 1)
        .offset(y: isTime && !reduce ? 8 : 0)
        .allowsHitTesting(!isTime)
        .accessibilityHidden(isTime)
        .animation(.linear(duration: 0.25), value: beat)
        .animation(D0B.curve(0.3), value: beat)
    }

    /// Back to the day step, beside "set alarm" in the time beat: (<-) (set alarm), about a fifth
    /// and four fifths of the row. In the day beat it closes up to nothing, like the side slots.
    private func backSlot(_ c: D0BCtx) -> some View {
        let isTime = beat == .time
        let shown = isTime && answer == nil
        let row = max(0, input.layout.size.width - 44 - 12)
        let width = (row * 0.2).rounded()
        return Button {
            goDay()
        } label: {
            ZStack {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(D0B.text)
            }
            .frame(height: c.m.ctaH)
            .contentShape(Capsule())
        }
        .buttonStyle(D0BPressStyle(scale: 0.96))
        .accessibilityLabel("back, pick another day")
        .frame(width: isTime ? width : 0, height: c.m.ctaH)
        .padding(.horizontal, isTime ? 0 : -6)
        .opacity(isTime ? 1 : 0)
        .clipped()
        .allowsHitTesting(shown)
        .accessibilityHidden(!isTime)
        .animation(.linear(duration: 0.22), value: beat)
        .animation(D0B.curve(0.3), value: beat)
    }

    @ViewBuilder
    private func side(_ door: CantTodayDoor, _ c: D0BCtx) -> some View {
        switch door {
        case .home: homeSide(c)
        case .skip: skipSide(c)
        case .reschedule: EmptyView()
        }
    }

    private func homeSide(_ c: D0BCtx) -> some View {
        let data = input.data
        let minutes = data.homeMinutes ?? 0
        let a = c.nz["chome"] ?? 0
        return Button {
            nudger.touched(kind: "tap")
            commit(.home) { input.actions.homeWorkout() }
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.14))
                Image(systemName: "house")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(D0B.text)
            }
            .frame(width: 56, height: 56)
            .modifier(D0BLift(amount: a, ink: false, reduceMotion: reduce))
            .contentShape(Circle())
        }
        .buttonStyle(D0BPressStyle(scale: 0.95, onPress: { pressed in tapPress(pressed) }))
        .frame(width: 72, height: 56)
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                pips(filled: data.homeLeft, total: data.homeOf, size: 6, line: 1.2, gap: 5)
                Text("\(minutes) min")
                    .font(.system(size: c.m.compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }
            .fixedSize()
            .offset(y: 60)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("home workout, \(minutes) minutes, \(data.homeLeft) of \(data.homeOf) left")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { commit(.home) { input.actions.homeWorkout() } }
    }

    private func skipSide(_ c: D0BCtx) -> some View {
        let needsHold = input.data.skipNeedsHold
        let a = c.nz["cskip"] ?? 0
        let label = needsHold ? "hold to skip" : "skip"
        return Group {
            if needsHold {
                skipCircle(c, nudge: a)
                    .scaleEffect(isHolding ? 0.95 : 1)
                    .animation(.easeOut(duration: 0.14), value: isHolding)
                    .cantTodayHold(
                        duration: 1.5,
                        progress: $holdProgress,
                        isHolding: $isHolding,
                        onBegan: {
                            holdStep = 0
                            nudger.cancel()
                            nudger.touched(kind: "hold")
                            input.haptics.play(.soft)
                        },
                        onComplete: {
                            skipLocked = true
                            commit(.skip) { input.actions.skip() }
                        },
                        onCancel: {
                            relight(from: holdProgress)
                            nudger.rest(at: clock())
                        }
                    )
            } else {
                Button {
                    nudger.touched(kind: "tap")
                    commit(.skip) { input.actions.skip() }
                } label: {
                    skipCircle(c, nudge: a)
                        .contentShape(Circle())
                }
                .buttonStyle(D0BPressStyle(scale: 0.95, onPress: { pressed in tapPress(pressed) }))
            }
        }
        .frame(width: 72, height: 56)
        .overlay(alignment: .top) {
            Text(label)
                .font(.system(size: c.m.compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
                .fixedSize()
                .offset(y: 60)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(needsHold ? "hold to skip" : "skip today")
        .accessibilityHint(needsHold ? "press and hold for one and a half seconds" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { commit(.skip) { input.actions.skip() } }
    }

    private func skipCircle(_ c: D0BCtx, nudge: Double) -> some View {
        let needsHold = input.data.skipNeedsHold
        let n = min(1.15, max(0, nudge))
        let ring = needsHold ? max(holdProgress, 0.25 * min(1, n)) : 0
        return ZStack {
            Circle().fill(Color.white.opacity(0.14))
            Circle()
                .trim(from: 0, to: CGFloat(min(1, ring)))
                .stroke(D0B.text, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1.5)
            D0BFlameShape()
                .stroke(D0B.text, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                .frame(width: 22, height: 26)
        }
        .frame(width: 56, height: 56)
        .modifier(D0BLift(amount: needsHold ? n * 0.6 : n, ink: false, reduceMotion: reduce))
        .contentShape(Circle())
    }

    private func pips(filled: Int, total: Int, size: CGFloat, line: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                Circle()
                    .strokeBorder(i < filled ? D0B.text : Color.white.opacity(0.6), lineWidth: line)
                    .background(Circle().fill(i < filled ? D0B.text : Color.clear))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func ctaButton(_ c: D0BCtx) -> some View {
        let isTime = beat == .time
        let disabled = isTime && !timeIsOK
        return Button {
            ctaTap()
        } label: {
            ZStack {
                HStack(spacing: 8) {
                    Text("next")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                }
                .opacity(isTime ? 0 : 1)
                Text("set alarm")
                    .opacity(isTime ? 1 : 0)
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(D0B.ink)
            .frame(maxWidth: .infinity)
            .frame(height: c.m.ctaH)
            .background(Capsule().fill(D0B.cream))
            .contentShape(Capsule())
        }
        .buttonStyle(D0BPressStyle(scale: 0.98))
        .opacity(disabled ? 0.32 : 1)
        .disabled(disabled)
        .animation(.linear(duration: 0.2), value: disabled)
        .animation(.linear(duration: 0.22), value: beat)
        .accessibilityLabel(isTime ? "set alarm" : "next")
    }

    // MARK: Actions

    private func ctaTap() {
        guard answer == nil else { return }
        if beat == .day {
            goTime()
        } else {
            finishReschedule()
        }
    }

    private func goTime() {
        guard answer == nil, let tgt = target, !dayBusy else { return }
        nudger.cancel()
        let parts = D0BTime.parts(D0BTime.start(input.data, tgt))
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            hIdx = parts.h
            mIdx = parts.m
            pIdx = parts.p
        }
        input.haptics.play(.rigid)
        beat = .time
    }

    private func goDay() {
        guard answer == nil, beat == .time else { return }
        nudger.cancel()
        input.haptics.play(.rigid)
        beat = .day
    }

    private func finishReschedule() {
        guard answer == nil, let tgt = target else { return }
        let minutes = currentMinutes
        guard input.data.allowed(tgt, minutes: minutes).isOK else { return }
        let r = D0BResched(
            day: tgt.short,
            h: "\(CantTodayClock.hour12(minutes))",
            m: D0BTime.pad(CantTodayClock.minute(minutes)),
            ap: CantTodayClock.isPM(minutes) ? "pm" : "am",
            weekIndex: tgt.weekIndex
        )
        let day = tgt.day
        let time = CantTodayClock.timeOfDay(minutes)
        commit(.reschedule(r)) { input.actions.reschedule(day, time) }
    }

    private func closeTap() {
        guard answer == nil else { return }
        commit(.close) { input.actions.close() }
    }

    /// The answer beat: heavy tap, the polaroid settles to the middle, then (about 0.45 s later) the action runs.
    private func commit(_ a: D0BAnswer, _ action: @escaping () -> Void) {
        guard answer == nil else { return }
        input.haptics.play(.heavy)
        nudger.cancel()
        answer = a
        if case .reschedule = a, !reduce {
            // The window flares up as the flame lands (the prototype's brightness 0.8 to 1.1).
            winB = -0.2
            winS = 0.8
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000)
                withAnimation(.easeOut(duration: 0.7)) {
                    winB = 0.1
                    winS = 1.1
                }
            }
        }
        if a != .close, !reduce {
            withAnimation(D0B.curve(0.56)) { polFlat = true }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            action()
        }
    }

    private func raiseBig(flies: Bool) {
        guard !bigIn else { return }
        if reduce {
            withAnimation(.easeOut(duration: 0.2)) { bigIn = true }
        } else if flies {
            withAnimation(D0B.curve(0.56).delay(0.06)) { bigIn = true }
        } else {
            withAnimation(D0B.curve(0.42).delay(0.14)) { bigIn = true }
        }
    }

    private func tapPress(_ pressed: Bool) {
        if pressed {
            nudger.cancel()
            nudger.touched(kind: "tap")
        } else {
            nudger.rest(at: clock())
        }
    }

    /// The hold was let go early: the photo comes back to life with a small breath of light.
    private func relight(from p0: Double) {
        guard !reduce, p0 > 0.02 else { return }
        let amount = 0.1 * min(1, p0 * 3)
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.28)) { bump = amount }
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.easeOut(duration: 0.28)) { bump = 0 }
        }
    }

    // MARK: Reel plumbing

    private func binding(_ r: D0BReel) -> Binding<Int> {
        switch r {
        case .hour: return $hIdx
        case .minute: return $mIdx
        case .meridiem: return $pIdx
        }
    }

    private func busyBinding(_ r: D0BReel) -> Binding<Bool> {
        switch r {
        case .hour: return $hBusy
        case .minute: return $mBusy
        case .meridiem: return $pBusy
        }
    }

    private func index(of r: D0BReel) -> Int {
        switch r {
        case .hour: return hIdx
        case .minute: return mIdx
        case .meridiem: return pIdx
        }
    }

    private func minutes(_ r: D0BReel, at i: Int) -> Int {
        switch r {
        case .hour: return D0BTime.minutes(h: i, m: mIdx, p: pIdx)
        case .minute: return D0BTime.minutes(h: hIdx, m: i, p: pIdx)
        case .meridiem: return D0BTime.minutes(h: hIdx, m: mIdx, p: i)
        }
    }

    private func isAllowed(_ r: D0BReel, at i: Int) -> Bool {
        guard let tgt = target else { return true }
        return input.data.allowed(tgt, minutes: minutes(r, at: i)).isOK
    }

    private func handleBlocked(_ r: D0BReel, _ i: Int) {
        input.haptics.play(.soft)
        guard let tgt = target else { return }
        if case .blocked(let text) = input.data.allowed(tgt, minutes: minutes(r, at: i)) {
            showNote(text)
        }
    }

    /// After the reels stop: if the time can't be an alarm, say why (the time itself is left alone).
    private func noteIfBlocked() {
        guard let tgt = target else { return }
        if case .blocked(let text) = input.data.allowed(tgt, minutes: currentMinutes) {
            input.haptics.play(.soft)
            showNote(text)
        }
    }

    private func showNote(_ text: String) {
        noteText = text
        withAnimation(.linear(duration: 0.25)) { noteOn = true }
        noteToken += 1
        let token = noteToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            if token == noteToken {
                withAnimation(.linear(duration: 0.25)) { noteOn = false }
            }
        }
    }

    private func adjustDay(_ direction: AccessibilityAdjustmentDirection) {
        let n = input.data.targets.count
        guard n > 0 else { return }
        let wraps = n >= 3
        switch direction {
        case .increment:
            dayIdx = wraps ? (dayIdx + 1) % n : min(n - 1, dayIdx + 1)
        case .decrement:
            dayIdx = wraps ? (dayIdx - 1 + n) % n : max(0, dayIdx - 1)
        @unknown default:
            break
        }
    }

    private func adjustTime(_ r: D0BReel, _ direction: AccessibilityAdjustmentDirection) {
        let n = r == .meridiem ? 2 : 12
        let wraps = r != .meridiem
        let cur = index(of: r)
        var next = cur
        switch direction {
        case .increment:
            next = wraps ? (cur + 1) % n : min(n - 1, cur + 1)
        case .decrement:
            next = wraps ? (cur - 1 + n) % n : max(0, cur - 1)
        @unknown default:
            break
        }
        guard next != cur else { return }
        binding(r).wrappedValue = next
        noteIfBlocked()
    }

    // MARK: Nudges (the "this is interactive" wave)

    private func nudgeIDs(_ b: D0BBeat) -> [String] {
        let data = input.data
        switch b {
        case .day:
            var ids: [String] = []
            if !data.targets.isEmpty { ids.append("dr") }
            if data.order.contains(.home) { ids.append("chome") }
            if data.order.contains(.skip) { ids.append("cskip") }
            return ids
        case .time:
            return ["dchip", "rh", "rm", "rpp"]
        }
    }

    private func nudgeKinds(_ b: D0BBeat) -> [String: String] {
        switch b {
        case .day:
            return [
                "dr": "reel",
                "chome": "tap",
                "cskip": input.data.skipNeedsHold ? "hold" : "tap",
            ]
        case .time:
            return ["dchip": "chip", "rh": "reel", "rm": "reel", "rpp": "reel"]
        }
    }

    private func nudgeAmounts(_ t: Double) -> [String: Double] {
        guard answer == nil, appeared else { return [:] }
        var out: [String: Double] = [:]
        for id in nudgeIDs(beat) {
            out[id] = nudger.amount(id, at: t)
        }
        return out
    }

    /// Sets the wave's items for this beat, and starts it once the beat has settled.
    private func armNudges() async {
        nudger.cancel()
        nudger.setItems(nudgeIDs(beat), kinds: nudgeKinds(beat))
        let wait: UInt64 = appeared ? 450_000_000 : 560_000_000
        try? await Task.sleep(nanoseconds: wait)
        guard !Task.isCancelled, answer == nil else { return }
        nudger.settle(at: clock())
    }

    // MARK: Media

    private func startVideo() {
        guard let media = input.facts.day0, media.kind == .video, let url = media.fileURL else { return }
        holder.start(url: url, playing: true)
    }

    private func loadPhoto() async {
        guard let media = input.facts.day0, media.kind == .photo, let url = media.fileURL else { return }
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.28)) { photo = loaded }
    }
}

// MARK: - Video layer (a private copy of the pause's, which keeps its own private)

private final class D0BPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass guarantees the type.
        layer as! AVPlayerLayer
    }
}

private struct D0BPlayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> D0BPlayerUIView {
        let view = D0BPlayerUIView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: D0BPlayerUIView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}
