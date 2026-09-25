import SwiftUI

// MARK: - Pure model

/// The maths behind the Day Dial, kept out of the view so every rule is
/// testable without a screen or a running clock.
///
/// Midnight at the top, the day running clockwise, values snapped to five
/// minutes. Two independent bars share one gutter: the night (bedtime to
/// wake) and the gym visit (arrive to done). The empty gutter between them is
/// the alarm-to-gym window.
enum DayDialModel {
    /// What a touch in the gutter has taken hold of.
    enum Grab: Equatable {
        case bedtime
        case wake
        case sleepBody
        case gymStart
        case gymEnd
        case gymBody

        var isSleep: Bool { self == .bedtime || self == .wake || self == .sleepBody }
        var isGym: Bool { !isSleep }
    }

    /// Which part of a bar a finger is on.
    enum Zone: Equatable {
        case start
        case body
        case end
    }

    /// One bar as the grab test sees it.
    ///
    /// `start`/`span` are the values. `drawnStart`/`drawnSpan` are the pill as
    /// it actually appears, which is not the same thing: round caps give every
    /// bar a minimum on-screen length, so a short visit is drawn wider than
    /// its value. A finger lands on pixels, so the pixels are what gets
    /// hit-tested. Testing the value instead was the reason grabbing the
    /// visible end of a short bar slid the bar instead of resizing it.
    struct Bar: Equatable {
        let start: Int
        let span: Int
        let drawnStart: Int
        let drawnSpan: Int
        let startGrab: Grab
        let endGrab: Grab
        let bodyGrab: Grab
    }

    /// The shortest night the dial will let a user set.
    static let minimumSleepMinutes = 60
    /// Gap kept between the end of the gym visit and the next bedtime so the
    /// two bars never lap.
    static let minimumGapMinutes = 30
    /// The smallest gap the dial allows between the alarm and the gym. Not the
    /// lock window — just enough room that the two icons are not on top of
    /// each other. The same rule applies when the alarm is set by hand, so
    /// both read it from one place.
    static let minimumLeadMinutes = MorningRhythm.minimumGymLead

    /// Converts a touch point to a minute-of-day, snapped to five minutes.
    static func minutes(at point: CGPoint, centre: CGPoint) -> Int {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }

        let raw = degrees / 360 * 1440
        return snapped(raw)
    }

    /// Snaps to the five-minute grid, wrapping 23:58 back through midnight.
    static func snapped(_ rawMinutes: Double) -> Int {
        (Int((rawMinutes / 5).rounded()) * 5) % 1440
    }

    static func snappedToTick(_ minutes: Int) -> Int {
        Int((Double(minutes) / 5).rounded()) * 5
    }

    /// Minute-of-day as degrees clockwise from midnight-at-top.
    static func angleDegrees(minutes: Int) -> Double {
        Double(minutes) / 1440 * 360
    }

    /// Screen offset for something sitting at `minutes` on a ring of
    /// `radius`, with an optional extra rotation for rubber-band overshoot.
    static func offset(minutes: Double, radius: CGFloat, extraDegrees: Double = 0) -> CGSize {
        let angle = (minutes / 1440 * 360 - 90 + extraDegrees) * .pi / 180
        return CGSize(width: radius * cos(angle), height: radius * sin(angle))
    }

    static func offset(minutes: Int, radius: CGFloat, extraDegrees: Double = 0) -> CGSize {
        offset(minutes: Double(minutes), radius: radius, extraDegrees: extraDegrees)
    }

    /// Arc length, in points, of a span of minutes on a ring of `radius`.
    static func arcLength(minutes: Int, radius: CGFloat) -> CGFloat {
        CGFloat(Double(minutes) / 1440 * 2 * .pi) * radius
    }

    // MARK: Drawn geometry

    /// The pill as drawn, in minutes of arc.
    ///
    /// A stroke with round caps can never be shorter than it is wide, so a
    /// span under two cap-radii still draws at that minimum, centred on the
    /// middle of the span. Everything the finger touches is measured against
    /// this, not against the value.
    static func drawnExtent(start: Int, span: Int, capMinutes: Int) -> (start: Int, span: Int) {
        let minimum = 2 * capMinutes
        guard span < minimum else { return ((start % 1440 + 1440) % 1440, span) }
        let centre = start + span / 2
        return (((centre - capMinutes) % 1440 + 1440) % 1440, minimum)
    }

    /// On-screen length of a bar, never less than the bar is wide.
    static func drawnArcLength(spanMinutes: Int, radius: CGFloat, barWidth: CGFloat) -> CGFloat {
        max(arcLength(minutes: spanMinutes, radius: radius), barWidth)
    }

    /// Whether a bar is long enough, as drawn, to carry an icon at each end.
    ///
    /// Both glyphs sit half a round cap inside the pill's ends, so the room
    /// they need is one bar width (the two half caps) plus one glyph plus a
    /// gap between them. Below that the second icon is not drawn at all and
    /// the first moves to the middle of the pill.
    ///
    /// `wasShowing` widens the gap on the way in and narrows it on the way
    /// out, so a bar dragged back and forth across the threshold cannot
    /// flicker.
    static func showsBothIcons(
        drawnArcLength: CGFloat,
        barWidth: CGFloat,
        glyphWidth: CGFloat,
        wasShowing: Bool
    ) -> Bool {
        let gap = glyphWidth * (wasShowing ? 0.3 : 0.8)
        return drawnArcLength >= barWidth + glyphWidth + gap
    }

    /// Signed shortest distance around the dial from `a` to `b`, in minutes.
    /// A finger that crosses midnight must read as a small step, not a jump
    /// of a whole day.
    static func wrappedDelta(from a: Int, to b: Int) -> Int {
        var delta = (b - a) % 1440
        if delta > 720 { delta -= 1440 }
        if delta <= -720 { delta += 1440 }
        return delta
    }

    /// Minutes clockwise from `a` to `b`, always 0..<1440.
    static func clockwiseSpan(from a: Int, to b: Int) -> Int {
        (b - a + 1440) % 1440
    }

    // MARK: Hit testing

    /// Which third of a bar the finger is on, or nil if it is not on the bar.
    ///
    /// One rule for every bar, long or short: the pill you can see is split
    /// into a leading end, a body, and a trailing end. End zones are capped
    /// at `tolerance` so a full night does not end up with two-hour handles,
    /// and can never take more than a third each, so even the shortest pill
    /// keeps a middle to slide by.
    static func zone(fingerMinutes finger: Int, bar: Bar, tolerance: Int) -> Zone? {
        let total = bar.drawnSpan
        guard total > 0 else { return nil }

        let into = clockwiseSpan(from: bar.drawnStart, to: finger)
        guard into <= total else { return nil }

        let cap = max(1, min(tolerance, total / 3))
        if into <= cap { return .start }
        if into >= total - cap { return .end }
        return .body
    }

    /// Decides what a touch in the gutter grabbed.
    ///
    /// Anything actually under the finger wins first, in drawing order, so
    /// the answer always matches the pill the user can see — which is the only answer
    /// that matches what the user can see.
    ///
    /// An end beats a body, so where two pills overlap the buried end stays
    /// reachable instead of being swallowed whole.
    ///
    /// Only when the finger is on no pill at all does `slop` come into play,
    /// and then it takes the *nearest* end rather than the topmost bar. That
    /// is what stops the gym bar claiming a touch that plainly belongs to the
    /// alarm sitting a few minutes away from it.
    static func grab(fingerMinutes finger: Int, bars: [Bar], tolerance: Int, slop: Int = 0) -> Grab? {
        var body: Grab?
        for bar in bars {
            guard let zone = zone(fingerMinutes: finger, bar: bar, tolerance: tolerance) else {
                continue
            }
            switch zone {
            case .start: return bar.startGrab
            case .end: return bar.endGrab
            case .body: if body == nil { body = bar.bodyGrab }
            }
        }
        if let body { return body }

        guard slop > 0 else { return nil }
        var best: (grab: Grab, distance: Int)?
        for bar in bars {
            let drawnEnd = (bar.drawnStart + bar.drawnSpan) % 1440
            let ends: [(Grab, Int)] = [
                (bar.startGrab, abs(wrappedDelta(from: bar.drawnStart, to: finger))),
                (bar.endGrab, abs(wrappedDelta(from: drawnEnd, to: finger))),
            ]
            for end in ends where end.1 <= slop {
                if end.1 < (best?.distance ?? .max) { best = (end.0, end.1) }
            }
        }
        return best?.grab
    }

    // MARK: Clamps

    /// Every clamp below works in one frame of reference: minutes clockwise
    /// from the alarm. `awakeSpan` is the stretch between getting up and going
    /// to bed, `gap` is alarm to gym, `session` is the length of the visit.
    ///
    /// Nothing here moves anything. Each bar is clamped against where the
    /// other one already is, so a drag that runs out of room stops — it never
    /// pushes or tows the other bar. That independence is the point: the two
    /// bars are two separate decisions.

    /// The longest night allowed alongside this gym plan: the visit must
    /// still end a gap before the next bedtime.
    static func maximumSleepMinutes(gapMinutes: Int, sessionMinutes: Int) -> Int {
        1440 - gapMinutes - sessionMinutes - minimumGapMinutes
    }

    /// Clamps a night whose bedtime is moving. Bedtime coming earlier is what
    /// closes on the end of the gym visit.
    static func clampedSleep(_ sleep: Int, gapMinutes: Int, sessionMinutes: Int) -> Int {
        let ceiling = maximumSleepMinutes(gapMinutes: gapMinutes, sessionMinutes: sessionMinutes)
        return min(max(sleep, minimumSleepMinutes), max(ceiling, minimumSleepMinutes))
    }

    /// Where the gym visit may sit, as minutes after the alarm.
    ///
    /// There is deliberately no two-hour ceiling here. The visit may be placed
    /// anywhere in the waking day; the only limits are a few minutes of lead
    /// after the alarm and not running into bedtime.
    static func clampedGap(_ desired: Int, awakeSpan: Int, sessionMinutes: Int) -> Int {
        let floor = minimumLeadMinutes
        let ceiling = awakeSpan - sessionMinutes - minimumGapMinutes
        return min(max(desired, floor), max(ceiling, floor))
    }

    /// Clamps the length of the gym visit to the room left before bedtime.
    static func clampedSession(_ desired: Int, awakeSpan: Int, gapMinutes: Int) -> Int {
        let floor = MorningRhythm.sessionRange.lowerBound
        let ceiling = min(
            MorningRhythm.sessionRange.upperBound,
            awakeSpan - gapMinutes - minimumGapMinutes
        )
        return min(max(desired, floor), max(ceiling, floor))
    }

    /// How far the alarm may actually move when it is dragged.
    ///
    /// Later means a shorter run-up to a gym time that is staying put, so the
    /// alarm stops a few minutes short of the visit instead of shoving it.
    static func clampedWakeShift(_ delta: Int, sleepMinutes: Int, gapMinutes: Int) -> Int {
        let latest = gapMinutes - minimumLeadMinutes
        let earliest = minimumSleepMinutes - sleepMinutes
        return min(max(delta, min(earliest, 0)), max(latest, 0))
    }

    /// How far the whole night may slide, with the gym visit standing still.
    /// Bounded by the alarm closing on the visit in one direction and bedtime
    /// closing on it in the other.
    static func clampedNightShift(
        _ delta: Int,
        awakeSpan: Int,
        gapMinutes: Int,
        sessionMinutes: Int
    ) -> Int {
        let latest = gapMinutes - minimumLeadMinutes
        let tail = awakeSpan - gapMinutes - sessionMinutes
        let earliest = minimumGapMinutes - tail
        return min(max(delta, min(earliest, 0)), max(latest, 0))
    }

    /// Travel minutes implied by the gap the user has drawn.
    ///
    /// The bar can be placed anywhere in the day, but the *lock* is still a
    /// run-up: it never holds apps for longer than the product allows, and
    /// `ShieldPolicy` caps it again on the way out. So the window follows the
    /// gap up to that ceiling and then stops, which is why a visit at noon
    /// does not mean a five-hour block.
    static func travelMinutes(gapMinutes: Int, getReadyMinutes: Int) -> Int {
        let ceiling = min(
            MorningRhythm.travelRange.upperBound,
            MorningRhythm.absoluteMaximumWindow - getReadyMinutes
        )
        let requested = gapMinutes - getReadyMinutes
        return min(max(requested, MorningRhythm.travelRange.lowerBound), max(ceiling, 0))
    }

    /// Apple's rubber-band curve: progressive resistance at a boundary, so a
    /// hard stop never reads as frozen.
    static func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    /// "7 hr 15 min", the way Apple's sleep schedule reads it.
    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) hr" }
        return "\(hours) hr \(rest) min"
    }
}

// MARK: - The dial

/// The Day Dial, after Apple's Change Wake Up screen.
///
/// One wide gutter around a bare 24-hour face. Two independent bars lie in
/// it: the night in ink (bedtime to wake) and the gym visit in coral (arrive
/// to done).
///
/// Every bar obeys one rule, however long it is: grab either end of the pill
/// to move that end, grab the middle to slide the whole thing. The zones are
/// measured on the pill you can see, not on the underlying value, so the ends
/// of a short visit are exactly where they look like they are.
///
/// A bar only shows two icons when it is drawn long enough to hold them
/// apart. A short one shows a single icon in the middle of its pill, which is
/// also its slide handle. The second icon springs in the moment there is room.
///
/// Bars follow the finger 1:1 from the point they were picked up and stop
/// where the finger lifts. No momentum: a schedule is not a scroll view.
struct DayDial: View {
    @Binding var rhythm: MorningRhythm

    var size: CGFloat = 320

    /// Reports what the finger is holding so the surrounding card can change
    /// its readout while the drag is live.
    var onGrabChange: ((DayDialModel.Grab?) -> Void)?

    /// Called when a gesture ends.
    var onSettle: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var grab: DayDialModel.Grab?
    /// Where the finger and the values were when the grab began. Every frame
    /// is applied as a delta from here, so the bar stays glued to the finger
    /// at the point it was picked up.
    @State private var grabFingerMinutes: Int = 0
    @State private var grabRhythm: MorningRhythm = .default
    @State private var lastTickKey: Int = -1
    @State private var didKnock = false
    /// Visual overshoot, in minutes of arc, while an end is held past its
    /// clamp. Springs back to zero on release.
    @State private var overshootMinutes: CGFloat = 0
    /// Whether each bar currently has room for an icon at both ends. Held in
    /// state rather than recomputed inline so the threshold can have
    /// hysteresis and the change can be animated.
    @State private var sleepShowsBothIcons = true
    @State private var gymShowsBothIcons = false

    // MARK: Opening pulse

    /// Minutes the gym bar is drawn longer than it really is, while the
    /// opening pulse stretches it out and lets it settle back. Drawing only:
    /// never written to the rhythm, never used for hit testing or VoiceOver.
    @State private var introExtraMinutes: Double = 0
    /// How far the pulse stretches it at the top.
    @State private var introAmount: Double = 0
    /// When the pulse begins. Nil when no intro is running.
    @State private var introBegins: Date?
    @State private var introIsRunning = false
    /// Which half-hour step the far end is on, so each crossing ticks once.
    @State private var introTickStep: Int = 0
    /// Once per presentation, not again on coming back from Sound.
    @State private var introHasPlayed = false

    // MARK: Metrics

    private var gutterWidth: CGFloat { size * 0.18 }
    private var gutterRadius: CGFloat { (size - gutterWidth) / 2 }
    private var barWidth: CGFloat { gutterWidth * 0.86 }
    private var iconSize: CGFloat { barWidth * 0.48 }
    private var faceRadius: CGFloat { gutterRadius - gutterWidth / 2 - size * 0.012 }

    /// Minutes of arc per point along the bar centreline.
    private var minutesPerPoint: Double { 1440 / (2 * .pi * Double(gutterRadius)) }
    /// Half a round cap, in minutes: how far the stroke centreline must stop
    /// short of a bar's true start and end so the cap lands exactly on them,
    /// and therefore also how far a too-short pill spills past its own value.
    private var capMinutes: Double { Double(barWidth / 2) * minutesPerPoint }
    private var capMinutesRounded: Int { max(1, Int(capMinutes.rounded())) }

    /// The widest an end zone may be: one bar width, the size of the icon
    /// that sits there.
    private var grabTolerance: Int {
        max(30, Int(Double(barWidth) * minutesPerPoint))
    }

    /// How far outside a pill still counts as touching it. A fingertip is
    /// bigger than a hairline.
    private var grabSlop: Int {
        max(8, Int(Double(barWidth) * 0.28 * minutesPerPoint))
    }

    /// The spring the icons use when a bar crosses the two-icon threshold.
    /// Slightly bouncy, because something appearing should look alive.
    private var iconFitAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .bouncy(duration: 0.42, extraBounce: 0.2)
    }

    // MARK: Derived

    private var bedtimeMinutes: Int { rhythm.bedtime.minutesFromMidnight }
    private var wakeMinutes: Int { rhythm.wakeTime.minutesFromMidnight }
    private var sleepMinutes: Int { DayDialModel.clockwiseSpan(from: bedtimeMinutes, to: wakeMinutes) }
    /// The waking stretch: getting up to going to bed. Both bars are clamped
    /// inside this, which is the only thing they share.
    private var awakeSpan: Int { 1440 - sleepMinutes }
    private var sessionMinutes: Int { rhythm.gymSessionMinutes }
    /// The gym bar's own value. Read from the rhythm rather than added onto
    /// the alarm, which is what makes the two bars independent.
    private var gymByMinutes: Int { rhythm.gymByTime.minutesFromMidnight }
    private var gymDoneMinutes: Int { (gymByMinutes + sessionMinutes) % 1440 }
    private var gapMinutes: Int { DayDialModel.clockwiseSpan(from: wakeMinutes, to: gymByMinutes) }
    /// The visit as drawn: its real length plus whatever the opening pulse
    /// currently adds.
    private var displayedSessionMinutes: Int {
        max(1, sessionMinutes + Int(introExtraMinutes.rounded()))
    }

    private var overshootDegrees: Double {
        Double(DayDialModel.rubberband(overshootMinutes * 0.25, dimension: size))
    }

    private var settleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.28, dampingFraction: 0.92)
    }

    private func makeBar(
        start: Int,
        span: Int,
        startGrab: DayDialModel.Grab,
        endGrab: DayDialModel.Grab,
        bodyGrab: DayDialModel.Grab
    ) -> DayDialModel.Bar {
        let drawn = DayDialModel.drawnExtent(start: start, span: span, capMinutes: capMinutesRounded)
        return DayDialModel.Bar(
            start: start,
            span: span,
            drawnStart: drawn.start,
            drawnSpan: drawn.span,
            startGrab: startGrab,
            endGrab: endGrab,
            bodyGrab: bodyGrab
        )
    }

    /// The bars, topmost first. The gym bar is drawn over the night, so it is
    /// also the one a touch on an overlap goes to.
    private var bars: [DayDialModel.Bar] {
        [
            makeBar(
                start: gymByMinutes,
                span: sessionMinutes,
                startGrab: .gymStart,
                endGrab: .gymEnd,
                bodyGrab: .gymBody
            ),
            makeBar(
                start: bedtimeMinutes,
                span: sleepMinutes,
                startGrab: .bedtime,
                endGrab: .wake,
                bodyGrab: .sleepBody
            ),
        ]
    }

    /// Where a bar's stroke centreline really runs, once its round caps are
    /// pulled inside its span, with rubber-band overshoot on whichever end
    /// is being held past its limit.
    private func centreline(start: Int, span: Double, startGrab: DayDialModel.Grab, endGrab: DayDialModel.Grab) -> (start: Double, span: Double) {
        let inset = min(capMinutes, span / 2)
        var s = Double(start) + inset
        var length = max(span - 2 * inset, 0.05)
        let extra = overshootDegrees / 360 * 1440
        if grab == startGrab { s += extra; length -= extra }
        if grab == endGrab { length += extra }
        return (s, max(length, 0.05))
    }

    private var sleepLine: (start: Double, span: Double) {
        centreline(start: bedtimeMinutes, span: Double(sleepMinutes), startGrab: .bedtime, endGrab: .wake)
    }

    private var gymLine: (start: Double, span: Double) {
        // A Double, so the contraction glides rather than stepping a minute
        // at a time as it slows.
        centreline(
            start: gymByMinutes,
            span: max(Double(sessionMinutes) + introExtraMinutes, 1),
            startGrab: .gymStart,
            endGrab: .gymEnd
        )
    }

    var body: some View {
        ZStack {
            gutter
            face
            bar(sleepLine, colour: Theme.ink)
            bar(gymLine, colour: Theme.accent)
            hatching
            barIcon(.bedtime)
            if sleepShowsBothIcons {
                barIcon(.wake)
                    .transition(iconTransition)
            }
            if gymShowsBothIcons {
                barIcon(.gymEnd)
                    .transition(iconTransition)
            }
            barIcon(.gymStart)
        }
        .frame(width: size, height: size)
        .contentShape(.circle)
        .gesture(drag)
        .background { introDriver }
        .onAppear {
            startIntroIfNeeded()
            refreshIconFit(animated: false)
        }
        .onChange(of: sleepMinutes) { _, _ in refreshIconFit() }
        .onChange(of: displayedSessionMinutes) { _, _ in refreshIconFit() }
        .onChange(of: size) { _, _ in refreshIconFit() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("day dial")
    }

    /// The second icon does not fade in, it arrives: small, then past size,
    /// then settled, on the same spring that slides its partner outward.
    private var iconTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.25).combined(with: .opacity)
    }

    /// Recomputes whether each bar has room for two icons. Only the crossing
    /// is animated; the positions themselves keep tracking the finger 1:1.
    private func refreshIconFit(animated: Bool = true) {
        let sleepFits = DayDialModel.showsBothIcons(
            drawnArcLength: DayDialModel.drawnArcLength(spanMinutes: sleepMinutes, radius: gutterRadius, barWidth: barWidth),
            barWidth: barWidth,
            glyphWidth: iconSize,
            wasShowing: sleepShowsBothIcons
        )
        let gymFits = DayDialModel.showsBothIcons(
            drawnArcLength: DayDialModel.drawnArcLength(spanMinutes: displayedSessionMinutes, radius: gutterRadius, barWidth: barWidth),
            barWidth: barWidth,
            glyphWidth: iconSize,
            wasShowing: gymShowsBothIcons
        )
        guard sleepFits != sleepShowsBothIcons || gymFits != gymShowsBothIcons else { return }

        if animated {
            withAnimation(iconFitAnimation) {
                sleepShowsBothIcons = sleepFits
                gymShowsBothIcons = gymFits
            }
        } else {
            sleepShowsBothIcons = sleepFits
            gymShowsBothIcons = gymFits
        }
    }

    // MARK: - Layers

    private var gutter: some View {
        Circle()
            .strokeBorder(Theme.surfaceMuted, lineWidth: gutterWidth)
            .frame(width: size, height: size)
    }

    /// The bare clock face: hour numbers, quarter-hour ticks, the moon under
    /// midnight and the sun above noon. Nothing here is interactive.
    private var face: some View {
        ZStack {
            Circle()
                .fill(Theme.surface)
                .frame(width: faceRadius * 2, height: faceRadius * 2)
                .overlay {
                    Circle().strokeBorder(Theme.border, lineWidth: 1)
                }

            Canvas { context, canvasSize in
                let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outer = faceRadius - size * 0.02

                for tick in 0..<96 {
                    let isHour = tick % 4 == 0
                    let length: CGFloat = isHour ? size * 0.024 : size * 0.012
                    let angle = (Double(tick) / 96 * 360 - 90) * .pi / 180
                    var path = Path()
                    path.move(to: CGPoint(
                        x: centre.x + (outer - length) * cos(angle),
                        y: centre.y + (outer - length) * sin(angle)
                    ))
                    path.addLine(to: CGPoint(
                        x: centre.x + outer * cos(angle),
                        y: centre.y + outer * sin(angle)
                    ))
                    context.stroke(
                        path,
                        with: .color(isHour ? Theme.inkTertiary.opacity(0.9) : Theme.border),
                        style: StrokeStyle(lineWidth: isHour ? 1.5 : 1, lineCap: .round)
                    )
                }
            }
            .frame(width: faceRadius * 2, height: faceRadius * 2)

            hourNumbers

            Image(systemName: "moon.fill")
                .font(.system(size: size * 0.05, weight: .bold))
                .foregroundStyle(Theme.night)
                .offset(y: -faceRadius * 0.52)

            // Yellow, not coral: the single accent on this screen belongs to
            // the gym bar, and a sun is the one thing nobody reads as an
            // accent anyway.
            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.055, weight: .bold))
                .foregroundStyle(Theme.sun)
                .offset(y: faceRadius * 0.52)
        }
        .allowsHitTesting(false)
    }

    private var hourNumbers: some View {
        let radius = faceRadius * 0.80

        return ZStack {
            ForEach(Array(stride(from: 0, to: 24, by: 2)), id: \.self) { hour in
                let angle = (Double(hour) / 24 * 360 - 90) * .pi / 180
                let isMajor = hour % 6 == 0

                Text("\(hour)")
                    .font(.system(size: isMajor ? size * 0.056 : size * 0.05, weight: isMajor ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isMajor ? Theme.ink : Theme.inkTertiary)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
    }

    private func bar(_ line: (start: Double, span: Double), colour: Color) -> some View {
        Circle()
            .trim(from: 0, to: max(line.span / 1440, 0.0005))
            .stroke(colour, style: StrokeStyle(lineWidth: barWidth, lineCap: .round))
            .frame(width: gutterRadius * 2, height: gutterRadius * 2)
            .rotationEffect(.degrees(line.start / 1440 * 360 - 90))
    }

    /// The fine radial lines along both bars, as on Apple's dial. Drawn in one
    /// canvas so a drag never rebuilds a hundred views a frame.
    private var hatching: some View {
        Canvas { context, canvasSize in
            let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let length = barWidth * 0.42
            // Kept clear of whichever icons the bar is showing.
            let clearance = capMinutesRounded + 8

            func hatch(from start: Int, span: Int, showsBothIcons: Bool, colour: Color) {
                guard showsBothIcons else { return }
                var minute = 8
                while minute < span - clearance {
                    if minute > clearance {
                        let angle = (DayDialModel.angleDegrees(minutes: start + minute) - 90) * .pi / 180
                        var path = Path()
                        path.move(to: CGPoint(
                            x: centre.x + (gutterRadius - length / 2) * cos(angle),
                            y: centre.y + (gutterRadius - length / 2) * sin(angle)
                        ))
                        path.addLine(to: CGPoint(
                            x: centre.x + (gutterRadius + length / 2) * cos(angle),
                            y: centre.y + (gutterRadius + length / 2) * sin(angle)
                        ))
                        context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                    minute += 8
                }
            }

            hatch(
                from: bedtimeMinutes,
                span: sleepMinutes,
                showsBothIcons: sleepShowsBothIcons,
                colour: Theme.surface.opacity(0.28)
            )
            hatch(
                from: gymByMinutes,
                span: displayedSessionMinutes,
                showsBothIcons: gymShowsBothIcons,
                colour: Theme.surface.opacity(0.42)
            )
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    // MARK: - Icons

    private struct IconSpec {
        let minutes: Double
        let symbol: String
        let label: String
        let value: Int
    }

    /// Whether the bar this icon belongs to is currently showing both ends.
    private func showsBoth(_ which: DayDialModel.Grab) -> Bool {
        which.isSleep ? sleepShowsBothIcons : gymShowsBothIcons
    }

    /// Where an icon sits: on its own end when the bar is long enough, in the
    /// middle of the pill when it is not.
    private func iconMinutes(
        _ line: (start: Double, span: Double),
        isEnd: Bool,
        showsBoth: Bool
    ) -> Double {
        guard showsBoth else { return line.start + line.span / 2 }
        return isEnd ? line.start + line.span : line.start
    }

    private func iconSpec(_ which: DayDialModel.Grab) -> IconSpec {
        switch which {
        case .bedtime, .sleepBody:
            IconSpec(
                minutes: iconMinutes(sleepLine, isEnd: false, showsBoth: sleepShowsBothIcons),
                symbol: "bed.double.fill",
                label: "Bedtime",
                value: bedtimeMinutes
            )
        case .wake:
            IconSpec(
                minutes: iconMinutes(sleepLine, isEnd: true, showsBoth: sleepShowsBothIcons),
                symbol: "alarm.fill",
                label: "Wake up",
                value: wakeMinutes
            )
        case .gymStart, .gymBody:
            IconSpec(
                minutes: iconMinutes(gymLine, isEnd: false, showsBoth: gymShowsBothIcons),
                symbol: "figure.strengthtraining.traditional",
                label: "Gym by",
                value: gymByMinutes
            )
        case .gymEnd:
            IconSpec(
                minutes: iconMinutes(gymLine, isEnd: true, showsBoth: gymShowsBothIcons),
                symbol: "flag.checkered",
                label: "Gym done",
                value: gymDoneMinutes
            )
        }
    }

    private func isHeld(_ which: DayDialModel.Grab) -> Bool {
        guard let grab else { return false }
        if grab == which { return true }
        if grab == .sleepBody { return which == .bedtime || which == .wake }
        if grab == .gymBody { return which == .gymStart || which == .gymEnd }
        return false
    }

    /// The icon at the end of a bar. It is the end of the bar, not a handle
    /// floating above it, so it is drawn in the bar's own light-on-dark.
    private func barIcon(_ which: DayDialModel.Grab) -> some View {
        let spec = iconSpec(which)
        let held = isHeld(which)
        let both = showsBoth(which)
        let isCollapsedLead = !both && (which == .bedtime || which == .gymStart)

        return Image(systemName: spec.symbol)
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(Theme.surface)
            .frame(width: barWidth, height: barWidth)
            .scaleEffect(held && !reduceMotion ? 1.16 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: held)
            .offset(DayDialModel.offset(minutes: spec.minutes, radius: gutterRadius))
            // Only the collapse crossing animates. Everything else tracks the
            // finger with no lag.
            .animation(iconFitAnimation, value: both)
            .accessibilityElement()
            .accessibilityLabel(spec.label)
            .accessibilityValue(time(at: spec.value).displayString)
            .accessibilityAdjustableAction { direction in
                adjust(which, byMinutes: direction == .increment ? 5 : -5)
            }
            // A collapsed bar hides its far end, so its length has to stay
            // reachable some other way.
            .accessibilityActions {
                if isCollapsedLead {
                    Button("lengthen") { adjust(farEnd(of: which), byMinutes: 15) }
                    Button("shorten") { adjust(farEnd(of: which), byMinutes: -15) }
                }
            }
    }

    private func farEnd(of which: DayDialModel.Grab) -> DayDialModel.Grab {
        which.isSleep ? .wake : .gymEnd
    }

    private func time(at minutes: Int) -> TimeOfDay {
        TimeOfDay(hour: ((minutes % 1440) + 1440) % 1440 / 60, minute: ((minutes % 60) + 60) % 60)
    }

    // MARK: - Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let centre = CGPoint(x: size / 2, y: size / 2)

                if grab == nil {
                    guard let picked = grab(at: value.startLocation, centre: centre) else { return }
                    // A finger on the dial ends the intro at once, so what
                    // it picks up is exactly what it can see.
                    if introBegins != nil { cancelIntro() }
                    grab = picked
                    grabFingerMinutes = DayDialModel.minutes(at: value.startLocation, centre: centre)
                    grabRhythm = rhythm
                    didKnock = false
                    lastTickKey = valueKey(for: picked)
                    Haptics.prepareSelection()
                    Haptics.press(intensity: 0.7)
                    onGrabChange?(picked)
                }

                guard let grab else { return }
                let finger = DayDialModel.minutes(at: value.location, centre: centre)
                apply(grab, delta: DayDialModel.wrappedDelta(from: grabFingerMinutes, to: finger))
            }
            .onEnded { _ in
                settle()
            }
    }

    /// Only the gutter is live. The face is a clock, not a control.
    private func grab(at point: CGPoint, centre: CGPoint) -> DayDialModel.Grab? {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let distance = sqrt(dx * dx + dy * dy)
        guard abs(distance - gutterRadius) <= gutterWidth / 2 + 12 else { return nil }

        return DayDialModel.grab(
            fingerMinutes: DayDialModel.minutes(at: point, centre: centre),
            bars: bars,
            tolerance: grabTolerance,
            slop: grabSlop
        )
    }

    private func apply(_ grab: DayDialModel.Grab, delta: Int) {
        let base = grabRhythm
        let baseBed = base.bedtime.minutesFromMidnight
        let baseWake = base.wakeTime.minutesFromMidnight
        let baseSleep = DayDialModel.clockwiseSpan(from: baseBed, to: baseWake)
        let baseAwake = 1440 - baseSleep
        let baseGym = base.gymByTime.minutesFromMidnight
        let baseGap = DayDialModel.clockwiseSpan(from: baseWake, to: baseGym)
        let baseSession = base.gymSessionMinutes
        var next = rhythm
        var overshoot = 0

        // Both bars are written explicitly on every drag, even the one that is
        // not moving. Pinning the still bar is what guarantees it cannot drift
        // as a side effect of the other one, and it also gives a plan saved
        // before the gym bar had its own value a real value the first time it
        // is touched.
        next.gymTime = time(at: baseGym)

        /// The lock window follows the gap the user drew, up to its own
        /// ceiling. Called whenever the gap changes, from either end.
        func syncWindow(gap: Int) {
            next.travelMinutes = DayDialModel.travelMinutes(
                gapMinutes: gap,
                getReadyMinutes: base.getReadyMinutes
            )
        }

        switch grab {
        case .bedtime:
            // Bedtime sets the length of the night; the alarm stays put, so
            // the gap to the gym is untouched. Pulling bedtime earlier runs
            // into the end of the gym visit, and stops there.
            let desired = baseSleep - delta
            let sleep = DayDialModel.clampedSleep(
                desired,
                gapMinutes: baseGap,
                sessionMinutes: baseSession
            )
            overshoot = desired - sleep
            next.bedtime = time(at: baseWake - sleep + 1440)

        case .wake:
            // The alarm moves on its own. Later eats into the run-up to a gym
            // time that is standing still, so it stops a few minutes short of
            // the visit rather than shoving it along.
            let shift = DayDialModel.clampedWakeShift(
                delta,
                sleepMinutes: baseSleep,
                gapMinutes: baseGap
            )
            overshoot = delta - shift
            next.wakeTime = time(at: baseWake + shift)
            syncWindow(gap: baseGap - shift)

        case .sleepBody:
            // The whole night slides with its length intact. The gym visit
            // does not come with it: the alarm closing on the visit stops the
            // drag one way, bedtime closing on it stops the drag the other.
            let shift = DayDialModel.clampedNightShift(
                delta,
                awakeSpan: baseAwake,
                gapMinutes: baseGap,
                sessionMinutes: baseSession
            )
            overshoot = delta - shift
            next.bedtime = time(at: baseBed + shift + 1440)
            next.wakeTime = time(at: baseWake + shift + 1440)
            syncWindow(gap: baseGap - shift)

        case .gymStart:
            // This end says where the visit begins; the far end stays put. So
            // pulling it later shortens the visit and pulling it earlier
            // lengthens it, until the visit hits its own limits.
            let endGap = baseGap + baseSession
            let desiredGap = baseGap + delta
            let session = min(
                max(endGap - desiredGap, MorningRhythm.sessionRange.lowerBound),
                max(min(MorningRhythm.sessionRange.upperBound, endGap - DayDialModel.minimumLeadMinutes), MorningRhythm.sessionRange.lowerBound)
            )
            let gap = endGap - session
            overshoot = desiredGap - gap
            next.gymSessionMinutes = session
            next.gymTime = time(at: baseWake + gap)
            syncWindow(gap: gap)

        case .gymBody:
            // The whole visit slides, anywhere in the waking day. There is no
            // two-hour wall here any more; it only stops where the night is.
            let desiredGap = baseGap + delta
            let gap = DayDialModel.clampedGap(
                desiredGap,
                awakeSpan: baseAwake,
                sessionMinutes: baseSession
            )
            overshoot = desiredGap - gap
            next.gymTime = time(at: baseWake + gap)
            syncWindow(gap: gap)

        case .gymEnd:
            let desired = baseSession + delta
            let session = DayDialModel.clampedSession(
                desired,
                awakeSpan: baseAwake,
                gapMinutes: baseGap
            )
            overshoot = desired - session
            next.gymSessionMinutes = session
        }

        if next != rhythm { rhythm = next }
        overshootMinutes = CGFloat(overshoot)

        // One tick per five-minute step of value, never per frame: a finger
        // pinned against a limit spins without changing anything and must not
        // buzz.
        let key = valueKey(for: grab)
        if key != lastTickKey {
            lastTickKey = key
            Haptics.selection()
        }

        // One knock the moment the limit is first reached, then silence until
        // the finger comes back inside and pushes again.
        if overshoot != 0 {
            if !didKnock {
                didKnock = true
                Haptics.boundary()
            }
        } else {
            didKnock = false
        }
    }

    private func valueKey(for grab: DayDialModel.Grab) -> Int {
        switch grab {
        case .bedtime: bedtimeMinutes
        case .wake, .sleepBody: wakeMinutes
        case .gymStart, .gymBody: gymByMinutes
        case .gymEnd: gymDoneMinutes
        }
    }

    /// The finger lifted. The bar is already where the finger left it; the
    /// only thing to do is let any overshoot spring back.
    private func settle() {
        guard grab != nil else { return }
        grab = nil
        lastTickKey = -1
        didKnock = false
        onGrabChange?(nil)
        Haptics.tap(intensity: 0.6)

        withAnimation(settleAnimation) {
            overshootMinutes = 0
        }

        onSettle?()
    }

    // MARK: - Opening pulse

    /// How long the bar rests at its real length when the page opens, before
    /// the pulse begins, so it moves on a settled page rather than under the
    /// cover's zoom-in.
    private static let introRestHold: Double = 0.4
    /// The stretch out: critically damped, so it rises to full length without
    /// overshoot and hands over to the release with no visible seam.
    private static let introOutResponse: Double = 0.4
    private static let introOutDuration: Double = 0.55
    /// A beat at full stretch before the bar lets go.
    private static let introTopHold: Double = 0.18
    /// The spring the bar contracts on: quick to start, a hair of undershoot,
    /// then still. Solved in closed form so every frame knows exactly where
    /// the end is, which is what the icons, hatching and ticks follow.
    private static let introResponse: Double = 0.72
    private static let introDamping: Double = 0.8
    private static let introDuration: Double = 1.3
    /// One tick per half hour the end crosses, on the way out or back.
    private static let introTickMinutes: Double = 30

    /// Drives the pulse frame by frame while it runs, and is gone otherwise,
    /// so an idle dial costs nothing.
    @ViewBuilder
    private var introDriver: some View {
        if introIsRunning, let begins = introBegins {
            TimelineView(.animation) { context in
                Color.clear
                    .onChange(of: context.date) { _, now in
                        stepIntro(now: now, begins: begins)
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Opens with the gym bar at the length the user chose, stretches it to
    /// its longest, then lets it settle back. Once per presentation, and not
    /// at all with Reduce Motion or VoiceOver's need for a still dial.
    private func startIntroIfNeeded() {
        guard !introHasPlayed else { return }
        introHasPlayed = true
        guard !reduceMotion else { return }

        // As long as the visit could be drawn right now: the longest session
        // allowed, stopped short of bedtime so it never covers the night.
        let longest = DayDialModel.clampedSession(
            MorningRhythm.sessionRange.upperBound,
            awakeSpan: awakeSpan,
            gapMinutes: gapMinutes
        )
        let extra = Double(longest - sessionMinutes)
        // Too little travel reads as a glitch, not a gesture.
        guard extra >= 30 else { return }

        introAmount = extra
        introExtraMinutes = 0
        introTickStep = 0
        introBegins = Date()
        introIsRunning = true
        Haptics.prepareSelection()
    }

    private func stepIntro(now: Date, begins: Date) {
        let t = now.timeIntervalSince(begins)
        guard t >= 0 else { return }

        // Resting at its real length while the page settles.
        guard t >= Self.introRestHold else {
            introExtraMinutes = 0
            return
        }

        let pulse = t - Self.introRestHold

        // Stretching out: critically damped rise, no overshoot.
        if pulse < Self.introOutDuration {
            let omega = 2 * Double.pi / Self.introOutResponse
            let progress = 1 - (1 + omega * pulse) * exp(-omega * pulse)
            setIntroExtra(introAmount * progress)
            return
        }

        // A beat at full stretch, then the release.
        let release = pulse - Self.introTopHold
        guard release >= 0 else {
            setIntroExtra(introAmount)
            return
        }
        guard release < Self.introDuration else {
            finishIntro()
            // The bar landing on its real length.
            Haptics.tap(intensity: 0.6)
            return
        }

        // Underdamped spring from 1 to 0.
        let omega = 2 * Double.pi / Self.introResponse
        let zeta = Self.introDamping
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let remaining = exp(-zeta * omega * release)
            * (cos(omegaD * release) + zeta * omega / omegaD * sin(omegaD * release))
        setIntroExtra(introAmount * remaining)
    }

    /// Writes the drawn length and ticks once per half hour the end crosses,
    /// out or back, like a ratchet. The floor at zero keeps the spring's tiny
    /// undershoot from ticking.
    private func setIntroExtra(_ extra: Double) {
        introExtraMinutes = extra
        let step = max(0, Int(extra / Self.introTickMinutes))
        if step != introTickStep {
            introTickStep = step
            Haptics.selection()
        }
    }

    private func finishIntro() {
        introIsRunning = false
        introBegins = nil
        introExtraMinutes = 0
        introAmount = 0
    }

    /// A finger landed mid-pulse: snap to the real length silently.
    private func cancelIntro() {
        finishIntro()
    }

    /// VoiceOver: every value is reachable without a drag.
    private func adjust(_ which: DayDialModel.Grab, byMinutes delta: Int) {
        grabRhythm = rhythm
        withAnimation(settleAnimation) {
            apply(which, delta: delta)
            overshootMinutes = 0
        }
        onSettle?()
    }
}
