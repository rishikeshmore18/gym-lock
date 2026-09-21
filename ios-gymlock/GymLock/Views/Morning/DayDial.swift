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

    /// One bar as the grab test sees it.
    struct Bar: Equatable {
        let start: Int
        let span: Int
        let startGrab: Grab
        let endGrab: Grab
        let bodyGrab: Grab
        /// False when the bar is too short to carry an icon at each end. A
        /// collapsed bar is a pill you slide; its ends are reached from just
        /// outside it.
        let showsBothIcons: Bool
    }

    /// The shortest night the dial will let a user set. Below this the two
    /// icons sit on top of each other and neither can be grabbed.
    static let minimumSleepMinutes = 60
    /// Gap kept between the end of the gym visit and the next bedtime, and
    /// between wake and gym arrival, so the bars never lap.
    static let minimumGapMinutes = 30

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

    /// Whether a bar is long enough to carry an icon at each end.
    ///
    /// Both glyphs sit half a round cap inside the bar's ends, so the room
    /// they need is one bar width (the two half caps) plus one glyph plus a
    /// gap between them. Below that the second icon is not drawn at all and
    /// the first one moves to the middle of the pill.
    ///
    /// `wasShowing` widens the gap on the way in and narrows it on the way
    /// out, so a bar dragged back and forth across the threshold cannot
    /// flicker.
    static func showsBothIcons(
        spanMinutes: Int,
        radius: CGFloat,
        barWidth: CGFloat,
        glyphWidth: CGFloat,
        wasShowing: Bool
    ) -> Bool {
        let gap = glyphWidth * (wasShowing ? 0.3 : 0.8)
        return arcLength(minutes: spanMinutes, radius: radius) >= barWidth + glyphWidth + gap
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

    /// Decides what a touch in the gutter grabbed.
    ///
    /// `bars` is asked in drawing order, topmost first, so a bar drawn over
    /// another one wins a genuine tie.
    ///
    /// 1. Inside a collapsed bar is always that bar's body. A pill too short
    ///    to show two icons is a thing you slide, not a thing you stretch.
    /// 2. Otherwise the nearest bar end within reach. Because it is the
    ///    nearest that wins, the empty gutter between two bars is split down
    ///    the middle and neither bar can steal the other's end.
    /// 3. Otherwise the body of whichever bar the finger is inside.
    /// 4. Otherwise nothing, so a stray touch on bare gutter moves nothing.
    static func grab(fingerMinutes finger: Int, bars: [Bar], tolerance: Int) -> Grab? {
        func isInside(_ bar: Bar) -> Bool {
            clockwiseSpan(from: bar.start, to: finger) <= bar.span
        }

        for bar in bars where !bar.showsBothIcons && isInside(bar) {
            return bar.bodyGrab
        }

        var best: (grab: Grab, distance: Int)?
        for bar in bars {
            // An expanded bar keeps its middle third for the body, so a long
            // night can still be slid without resizing it.
            let reach = bar.showsBothIcons ? min(tolerance, max(bar.span / 3, 1)) : tolerance
            let candidates: [(Grab, Int)] = [
                (bar.startGrab, abs(wrappedDelta(from: bar.start, to: finger))),
                (bar.endGrab, abs(wrappedDelta(from: (bar.start + bar.span) % 1440, to: finger))),
            ]
            for candidate in candidates where candidate.1 <= reach {
                if best == nil || candidate.1 < (best?.distance ?? .max) {
                    best = (candidate.0, candidate.1)
                }
            }
        }
        if let best { return best.grab }

        for bar in bars where isInside(bar) {
            return bar.bodyGrab
        }
        return nil
    }

    // MARK: Clamps

    /// The longest night allowed alongside this gym plan: the visit must
    /// still end a gap before the next bedtime.
    static func maximumSleepMinutes(windowMinutes: Int, sessionMinutes: Int) -> Int {
        1440 - windowMinutes - sessionMinutes - minimumGapMinutes
    }

    /// Clamps a night to what the dial can show.
    static func clampedSleep(_ sleep: Int, windowMinutes: Int, sessionMinutes: Int) -> Int {
        let ceiling = maximumSleepMinutes(windowMinutes: windowMinutes, sessionMinutes: sessionMinutes)
        return min(max(sleep, minimumSleepMinutes), max(ceiling, minimumSleepMinutes))
    }

    /// Clamps an alarm-to-gym window to the product range and to the room
    /// left on the dial.
    static func clampedWindow(
        _ desired: Int,
        getReadyMinutes: Int,
        sleepMinutes: Int,
        sessionMinutes: Int
    ) -> Int {
        let floor = max(MorningRhythm.minimumWindow, getReadyMinutes + MorningRhythm.travelRange.lowerBound)
        let ceiling = min(
            MorningRhythm.absoluteMaximumWindow,
            getReadyMinutes + MorningRhythm.travelRange.upperBound,
            1440 - sleepMinutes - sessionMinutes - minimumGapMinutes
        )
        return min(max(desired, floor), max(ceiling, floor))
    }

    /// Clamps the length of the gym visit.
    static func clampedSession(_ desired: Int, sleepMinutes: Int, windowMinutes: Int) -> Int {
        let floor = MorningRhythm.sessionRange.lowerBound
        let ceiling = min(
            MorningRhythm.sessionRange.upperBound,
            1440 - sleepMinutes - windowMinutes - minimumGapMinutes
        )
        return min(max(desired, floor), max(ceiling, floor))
    }

    /// Travel minutes implied by a window, never outside the travel range and
    /// never past the absolute ceiling. Wake time is not touched.
    static func travelMinutes(desiredWindow: Int, getReadyMinutes: Int) -> Int {
        let ceiling = min(
            MorningRhythm.travelRange.upperBound,
            MorningRhythm.absoluteMaximumWindow - getReadyMinutes
        )
        let requested = desiredWindow - getReadyMinutes
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
/// to done). Each bar has two ends and a body. Drag an end to move that end,
/// drag a body to slide the whole bar.
///
/// A bar only shows two icons when it is long enough to hold them apart. A
/// short one shows a single icon in the middle of its pill and behaves like a
/// handle; pull just past either cap to stretch it. The second icon springs
/// in the moment there is room for it.
///
/// The bar follows the finger 1:1 with the grab offset preserved, and stops
/// exactly where the finger lifts. No momentum: a schedule is not a scroll
/// view, and a bar that drifts after release feels loose.
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

    // MARK: Metrics

    private var gutterWidth: CGFloat { size * 0.18 }
    private var gutterRadius: CGFloat { (size - gutterWidth) / 2 }
    private var barWidth: CGFloat { gutterWidth * 0.86 }
    private var iconSize: CGFloat { barWidth * 0.48 }
    private var faceRadius: CGFloat { gutterRadius - gutterWidth / 2 - size * 0.012 }

    /// Minutes of arc per point along the bar centreline.
    private var minutesPerPoint: Double { 1440 / (2 * .pi * Double(gutterRadius)) }
    /// Half a round cap, in minutes: how far the stroke centreline must stop
    /// short of a bar's true start and end so the cap lands exactly on them.
    private var capMinutes: Double { Double(barWidth / 2) * minutesPerPoint }

    /// How close, in minutes of arc, a finger must be to a bar end to take
    /// hold of it. One bar width, which is the size of the icon that sits
    /// there.
    private var grabTolerance: Int {
        max(30, Int(Double(barWidth) * minutesPerPoint))
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
    private var windowMinutes: Int { rhythm.windowMinutes }
    private var sessionMinutes: Int { rhythm.gymSessionMinutes }
    private var gymByMinutes: Int { (wakeMinutes + windowMinutes) % 1440 }
    private var gymDoneMinutes: Int { (gymByMinutes + sessionMinutes) % 1440 }

    private var overshootDegrees: Double {
        Double(DayDialModel.rubberband(overshootMinutes * 0.25, dimension: size))
    }

    private var settleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.28, dampingFraction: 0.92)
    }

    /// The bars, topmost first. The gym bar is drawn over the night, so it is
    /// also the one a tie goes to.
    private var bars: [DayDialModel.Bar] {
        [
            DayDialModel.Bar(
                start: gymByMinutes,
                span: sessionMinutes,
                startGrab: .gymStart,
                endGrab: .gymEnd,
                bodyGrab: .gymBody,
                showsBothIcons: gymShowsBothIcons
            ),
            DayDialModel.Bar(
                start: bedtimeMinutes,
                span: sleepMinutes,
                startGrab: .bedtime,
                endGrab: .wake,
                bodyGrab: .sleepBody,
                showsBothIcons: sleepShowsBothIcons
            ),
        ]
    }

    /// Where a bar's stroke centreline really runs, once its round caps are
    /// pulled inside its span, with rubber-band overshoot on whichever end
    /// is being held past its limit.
    private func centreline(start: Int, span: Int, startGrab: DayDialModel.Grab, endGrab: DayDialModel.Grab) -> (start: Double, span: Double) {
        let inset = min(capMinutes, Double(span) / 2)
        var s = Double(start) + inset
        var length = max(Double(span) - 2 * inset, 0.05)
        let extra = overshootDegrees / 360 * 1440
        if grab == startGrab { s += extra; length -= extra }
        if grab == endGrab { length += extra }
        return (s, max(length, 0.05))
    }

    private var sleepLine: (start: Double, span: Double) {
        centreline(start: bedtimeMinutes, span: sleepMinutes, startGrab: .bedtime, endGrab: .wake)
    }

    private var gymLine: (start: Double, span: Double) {
        centreline(start: gymByMinutes, span: sessionMinutes, startGrab: .gymStart, endGrab: .gymEnd)
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
        .onAppear { refreshIconFit(animated: false) }
        .onChange(of: sleepMinutes) { _, _ in refreshIconFit() }
        .onChange(of: sessionMinutes) { _, _ in refreshIconFit() }
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
            spanMinutes: sleepMinutes,
            radius: gutterRadius,
            barWidth: barWidth,
            glyphWidth: iconSize,
            wasShowing: sleepShowsBothIcons
        )
        let gymFits = DayDialModel.showsBothIcons(
            spanMinutes: sessionMinutes,
            radius: gutterRadius,
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

            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.055, weight: .bold))
                .foregroundStyle(Theme.accentWarm)
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
            let clearance = grabTolerance * 3 / 4

            func hatch(from start: Int, span: Int, colour: Color) {
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

            hatch(from: bedtimeMinutes, span: sleepMinutes, colour: Theme.surface.opacity(0.28))
            hatch(from: gymByMinutes, span: sessionMinutes, colour: Theme.surface.opacity(0.42))
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
            .contentShape(.circle)
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
            tolerance: grabTolerance
        )
    }

    private func apply(_ grab: DayDialModel.Grab, delta: Int) {
        let base = grabRhythm
        let baseBed = base.bedtime.minutesFromMidnight
        let baseWake = base.wakeTime.minutesFromMidnight
        let baseSleep = DayDialModel.clockwiseSpan(from: baseBed, to: baseWake)
        var next = rhythm
        var overshoot = 0

        switch grab {
        case .bedtime:
            let sleep = baseSleep - delta
            let clamped = DayDialModel.clampedSleep(sleep, windowMinutes: base.windowMinutes, sessionMinutes: base.gymSessionMinutes)
            overshoot = sleep - clamped
            next.bedtime = time(at: baseWake - clamped + 1440)

        case .wake:
            let sleep = baseSleep + delta
            let clamped = DayDialModel.clampedSleep(sleep, windowMinutes: base.windowMinutes, sessionMinutes: base.gymSessionMinutes)
            overshoot = sleep - clamped
            next.wakeTime = time(at: baseBed + clamped)

        case .sleepBody:
            next.bedtime = time(at: baseBed + delta + 1440)
            next.wakeTime = time(at: baseWake + delta + 1440)

        case .gymStart:
            // The far end stays put: pulling the start later shortens the
            // visit, pulling it earlier lengthens it.
            let endOffset = base.windowMinutes + base.gymSessionMinutes
            var window = DayDialModel.clampedWindow(
                base.windowMinutes + delta,
                getReadyMinutes: base.getReadyMinutes,
                sleepMinutes: baseSleep,
                sessionMinutes: MorningRhythm.sessionRange.lowerBound
            )
            window = min(window, endOffset - MorningRhythm.sessionRange.lowerBound)
            overshoot = (base.windowMinutes + delta) - window
            next.travelMinutes = window - base.getReadyMinutes
            next.gymSessionMinutes = endOffset - window

        case .gymBody:
            let window = DayDialModel.clampedWindow(
                base.windowMinutes + delta,
                getReadyMinutes: base.getReadyMinutes,
                sleepMinutes: baseSleep,
                sessionMinutes: base.gymSessionMinutes
            )
            overshoot = (base.windowMinutes + delta) - window
            next.travelMinutes = window - base.getReadyMinutes

        case .gymEnd:
            let session = DayDialModel.clampedSession(
                base.gymSessionMinutes + delta,
                sleepMinutes: baseSleep,
                windowMinutes: base.windowMinutes
            )
            overshoot = (base.gymSessionMinutes + delta) - session
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
