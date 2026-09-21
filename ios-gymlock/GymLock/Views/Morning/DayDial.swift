import SwiftUI

// MARK: - Pure model

/// The maths behind the Day Dial, kept out of the view so every rule is
/// testable without a screen or a running clock.
///
/// Midnight at the top, the day running clockwise, values snapped to five
/// minutes.
enum DayDialModel {
    /// What a touch in the gutter has taken hold of.
    ///
    /// Grabbing an icon moves that end. Grabbing the body of the sleep arc
    /// slides the whole night, bedtime and wake together, which is how the
    /// bar in Apple's Change Wake Up screen behaves.
    enum Grab: Equatable {
        case bedtime
        case wake
        case gym
        case sleepBody
    }

    /// The shortest night the dial will let a user set. Below this the two
    /// icons sit on top of each other and neither can be grabbed.
    static let minimumSleepMinutes = 60
    /// Gap kept between gym-by and the next bedtime so the arcs never lap.
    static let minimumAwakeGapMinutes = 30

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
    static func offset(minutes: Int, radius: CGFloat, extraDegrees: Double = 0) -> CGSize {
        let angle = (angleDegrees(minutes: minutes) - 90 + extraDegrees) * .pi / 180
        return CGSize(width: radius * cos(angle), height: radius * sin(angle))
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
    /// Icons win when the finger is within `tolerance` minutes of one. Then
    /// the body of the sleep arc, then the body of the gym arc. Anywhere else
    /// on the ring is nothing, so a stray touch cannot move the night.
    static func grab(
        fingerMinutes finger: Int,
        bedtime: Int,
        wake: Int,
        gymBy: Int,
        tolerance: Int
    ) -> Grab? {
        let toBedtime = abs(wrappedDelta(from: bedtime, to: finger))
        let toWake = abs(wrappedDelta(from: wake, to: finger))
        let toGym = abs(wrappedDelta(from: gymBy, to: finger))

        let nearest = min(toBedtime, toWake, toGym)
        if nearest <= tolerance {
            // On a short window wake and gym-by sit close; the gym icon is on
            // top visually, so it wins ties.
            if toGym == nearest { return .gym }
            if toWake == nearest { return .wake }
            return .bedtime
        }

        if clockwiseSpan(from: bedtime, to: finger) <= clockwiseSpan(from: bedtime, to: wake) {
            return .sleepBody
        }
        if clockwiseSpan(from: wake, to: finger) <= clockwiseSpan(from: wake, to: gymBy) {
            return .gym
        }
        return nil
    }

    /// The longest night allowed with this gym window: the gym-by mark must
    /// still leave a gap before the next bedtime.
    static func maximumSleepMinutes(windowMinutes: Int) -> Int {
        1440 - windowMinutes - minimumAwakeGapMinutes
    }

    /// Clamps a night to what the dial can show.
    static func clampedSleep(_ sleep: Int, windowMinutes: Int) -> Int {
        min(max(sleep, minimumSleepMinutes), maximumSleepMinutes(windowMinutes: windowMinutes))
    }

    /// Travel minutes implied by a dragged gym-by position.
    ///
    /// The handle can ask for any window on the circle; this is where it is
    /// clamped to the product range. It never touches wake time. The caller
    /// only ever receives a travel value.
    static func travelMinutes(desiredWindow: Int, getReadyMinutes: Int) -> Int {
        let requested = desiredWindow - getReadyMinutes
        return min(max(requested, MorningRhythm.travelRange.lowerBound), MorningRhythm.travelRange.upperBound)
    }

    /// Apple's rubber-band curve: progressive resistance at a boundary, so a
    /// hard stop never reads as frozen.
    static func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    /// Momentum projection: how many minutes a flick was heading for, read
    /// from the component of `predictedEndTranslation` along the handle's
    /// tangent. Damped so a light flick does not leap.
    static func projectedMinutes(
        translation: CGSize,
        handleAngleDegrees: Double,
        radius: CGFloat,
        damping: Double = 0.6
    ) -> Int {
        let angle = (handleAngleDegrees - 90) * .pi / 180
        // Unit tangent in the direction of increasing minutes (clockwise on
        // screen, where y grows downward).
        let tx = -sin(angle)
        let ty = cos(angle)
        let along = Double(translation.width * tx + translation.height * ty)
        let circumference = 2 * .pi * Double(radius)
        return Int((along / circumference * 1440 * damping).rounded())
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
/// One wide gutter around a bare 24-hour face. Two bars live inside that
/// gutter and share it: the night in ink, bedtime to wake, and the gym
/// window in coral, wake to gym-by. The icons are the ends of the bars, not
/// separate handles floating on top. Drag an icon to move that end, drag the
/// body of the night to slide the whole night.
///
/// Gestures follow `docs/UI-RULES.md` §6: 1:1 tracking with the grab offset
/// preserved, one grab per gesture, rubber-banding at the travel limits, and
/// velocity handed off on release.
struct DayDial: View {
    @Binding var bedtime: TimeOfDay
    @Binding var wakeTime: TimeOfDay
    @Binding var travelMinutes: Int
    let getReadyMinutes: Int

    var size: CGFloat = 320

    /// Reports what the finger is holding so the surrounding card can change
    /// its readout while the drag is live.
    var onGrabChange: ((DayDialModel.Grab?) -> Void)?

    /// Called when a gesture ends and momentum has been applied: the moment a
    /// rhythm change should be committed and checked against the night lock.
    var onSettle: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var grab: DayDialModel.Grab?
    /// Where the finger and the values were when the grab began. Every frame
    /// is applied as a delta from here, so the bar stays glued to the finger
    /// at the point it was picked up.
    @State private var grabFingerMinutes: Int = 0
    @State private var grabBedtime: Int = 0
    @State private var grabWake: Int = 0
    @State private var grabTravel: Int = 0
    @State private var lastTickKey: Int = -1
    @State private var didKnock = false
    /// Visual overshoot, in minutes of arc, while the gym end is held past
    /// its clamp. Springs back to zero on release.
    @State private var gymOvershootMinutes: CGFloat = 0

    // MARK: Metrics

    private var gutterWidth: CGFloat { size * 0.18 }
    private var gutterRadius: CGFloat { (size - gutterWidth) / 2 }
    private var barWidth: CGFloat { gutterWidth * 0.86 }
    private var iconSize: CGFloat { barWidth * 0.5 }
    private var faceRadius: CGFloat { gutterRadius - gutterWidth / 2 - size * 0.012 }

    /// Minutes of arc per point along the bar centreline.
    private var minutesPerPoint: Double { 1440 / (2 * .pi * Double(gutterRadius)) }
    /// Half a round cap, in minutes: how far the stroke centreline must stop
    /// short of a bar's true start and end so the cap lands exactly on them.
    private var capMinutes: Double { Double(barWidth / 2) * minutesPerPoint }
    /// Daylight between the night bar and the gym bar at wake, so the two read
    /// as two pills sharing one gutter and never as one bent shape.
    private var gapMinutes: Double { Double(size * 0.022) * minutesPerPoint }

    /// Where a bar's stroke centreline really runs, once its round caps are
    /// pulled inside its span. Very short spans collapse to a dot at the
    /// span's middle rather than poking past their ends.
    private func barCentreline(startMinutes: Double, spanMinutes: Double) -> (start: Double, span: Double) {
        let inset = min(capMinutes, spanMinutes / 2)
        return (startMinutes + inset, max(spanMinutes - 2 * inset, 0.05))
    }

    private var sleepCentreline: (start: Double, span: Double) {
        barCentreline(startMinutes: Double(bedtimeMinutes), spanMinutes: Double(sleepMinutes))
    }

    private var gymCentreline: (start: Double, span: Double) {
        barCentreline(
            startMinutes: Double(wakeMinutes) + gapMinutes,
            spanMinutes: max(Double(windowMinutes) - gapMinutes, 1)
        )
    }

    /// How close, in minutes of arc, a finger must be to an icon to grab it.
    private var grabTolerance: Int {
        let arc = barWidth * 0.85
        return max(35, Int(arc / gutterRadius * 1440 / (2 * .pi)))
    }

    // MARK: Derived

    private var bedtimeMinutes: Int { bedtime.minutesFromMidnight }
    private var wakeMinutes: Int { wakeTime.minutesFromMidnight }
    private var sleepMinutes: Int { DayDialModel.clockwiseSpan(from: bedtimeMinutes, to: wakeMinutes) }
    private var windowMinutes: Int { getReadyMinutes + travelMinutes }
    private var gymByMinutes: Int { (wakeMinutes + windowMinutes) % 1440 }

    private var settleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.32, dampingFraction: 0.86)
    }

    var body: some View {
        ZStack {
            gutter
            face
            sleepBar
            gymBar
            hatching
            barIcon(.bedtime)
            barIcon(.gym)
            barIcon(.wake)
        }
        .frame(width: size, height: size)
        .contentShape(.circle)
        .gesture(drag)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("day dial")
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

    /// The night, bedtime to wake, in ink. Round-capped so it reads as a bar
    /// lying in the gutter rather than a slice of ring.
    private var sleepBar: some View {
        let line = sleepCentreline
        return bar(startMinutes: line.start, spanMinutes: line.span, colour: Theme.ink)
    }

    /// The gym window, wake to gym-by. The one coral element on the screen,
    /// and the right one: this window is what the app is for.
    private var gymBar: some View {
        let extra = Double(DayDialModel.rubberband(gymOvershootMinutes * 0.25, dimension: size))
        let line = gymCentreline
        return bar(startMinutes: line.start, spanMinutes: line.span + extra, colour: Theme.accent)
    }

    private func bar(startMinutes: Double, spanMinutes: Double, colour: Color) -> some View {
        Circle()
            .trim(from: 0, to: max(spanMinutes / 1440, 0.0005))
            .stroke(colour, style: StrokeStyle(lineWidth: barWidth, lineCap: .round))
            .frame(width: gutterRadius * 2, height: gutterRadius * 2)
            .rotationEffect(.degrees(startMinutes / 1440 * 360 - 90))
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
            hatch(
                from: wakeMinutes + Int(gapMinutes.rounded()),
                span: windowMinutes - Int(gapMinutes.rounded()),
                colour: Theme.surface.opacity(0.42)
            )
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    // MARK: - Icons

    /// The icon at the end of a bar. It is the end of the bar, not a handle
    /// floating above it, so it is drawn in the bar's own light-on-dark.
    private struct IconSpec {
        let minutes: Int
        let symbol: String
        let label: String
        let extraDegrees: Double
    }

    private func iconSpec(_ which: DayDialModel.Grab) -> IconSpec {
        switch which {
        case .bedtime:
            IconSpec(minutes: Int(sleepCentreline.start.rounded()), symbol: "bed.double.fill", label: "Bedtime", extraDegrees: 0)
        case .wake, .sleepBody:
            IconSpec(
                minutes: Int((sleepCentreline.start + sleepCentreline.span).rounded()),
                symbol: "alarm.fill",
                label: "Wake up",
                extraDegrees: 0
            )
        case .gym:
            IconSpec(
                minutes: Int((gymCentreline.start + gymCentreline.span).rounded()),
                symbol: "figure.strengthtraining.traditional",
                label: "Gym by",
                extraDegrees: Double(DayDialModel.rubberband(gymOvershootMinutes * 0.25, dimension: size))
            )
        }
    }

    private func barIcon(_ which: DayDialModel.Grab) -> some View {
        let isHeld = grab == which || (which == .bedtime && grab == .sleepBody) || (which == .wake && grab == .sleepBody)
        let spec = iconSpec(which)
        let minutes = spec.minutes
        let symbol = spec.symbol
        let label = spec.label
        let extraDegrees = spec.extraDegrees

        return Image(systemName: symbol)
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(Theme.surface)
            .frame(width: barWidth, height: barWidth)
            .contentShape(.circle)
            .scaleEffect(isHeld && !reduceMotion ? 1.18 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHeld)
            .offset(DayDialModel.offset(minutes: minutes, radius: gutterRadius, extraDegrees: extraDegrees))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(time(at: accessibilityMinutes(which)).displayString)
            .accessibilityAdjustableAction { direction in
                adjust(which, byMinutes: direction == .increment ? 5 : -5)
            }
    }

    /// The icon is drawn at the bar's cap centre; VoiceOver still speaks the
    /// real time it stands for.
    private func accessibilityMinutes(_ which: DayDialModel.Grab) -> Int {
        switch which {
        case .bedtime: bedtimeMinutes
        case .wake, .sleepBody: wakeMinutes
        case .gym: gymByMinutes
        }
    }

    private func time(at minutes: Int) -> TimeOfDay {
        TimeOfDay(hour: (minutes % 1440) / 60, minute: minutes % 60)
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
                    grabBedtime = bedtimeMinutes
                    grabWake = wakeMinutes
                    grabTravel = travelMinutes
                    didKnock = false
                    Haptics.prepareSelection()
                    Haptics.press(intensity: 0.7)
                    onGrabChange?(picked)
                }

                guard let grab else { return }
                let finger = DayDialModel.minutes(at: value.location, centre: centre)
                apply(grab, delta: DayDialModel.wrappedDelta(from: grabFingerMinutes, to: finger))
            }
            .onEnded { value in
                settle(with: value)
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
            bedtime: bedtimeMinutes,
            wake: wakeMinutes,
            gymBy: gymByMinutes,
            tolerance: grabTolerance
        )
    }

    private func apply(_ grab: DayDialModel.Grab, delta: Int) {
        var hitLimit = false

        switch grab {
        case .bedtime:
            let desired = grabBedtime + delta
            let sleep = DayDialModel.clockwiseSpan(from: desired, to: grabWake)
            let clamped = DayDialModel.clampedSleep(sleep, windowMinutes: windowMinutes)
            hitLimit = clamped != sleep
            let newBedtime = (grabWake - clamped + 1440) % 1440
            if newBedtime != bedtimeMinutes { bedtime = time(at: newBedtime) }

        case .wake:
            let desired = grabWake + delta
            let sleep = DayDialModel.clockwiseSpan(from: grabBedtime, to: desired)
            let clamped = DayDialModel.clampedSleep(sleep, windowMinutes: windowMinutes)
            hitLimit = clamped != sleep
            let newWake = (grabBedtime + clamped) % 1440
            if newWake != wakeMinutes { wakeTime = time(at: newWake) }

        case .sleepBody:
            let newBedtime = (grabBedtime + delta + 1440) % 1440
            let newWake = (grabWake + delta + 1440) % 1440
            if newBedtime != bedtimeMinutes { bedtime = time(at: newBedtime) }
            if newWake != wakeMinutes { wakeTime = time(at: newWake) }

        case .gym:
            let desiredWindow = getReadyMinutes + grabTravel + delta
            let travel = DayDialModel.travelMinutes(
                desiredWindow: desiredWindow,
                getReadyMinutes: getReadyMinutes
            )
            hitLimit = travel + getReadyMinutes != desiredWindow
            if travel != travelMinutes { travelMinutes = travel }
            // What the finger asked for beyond the clamp, shown as a small
            // visual overshoot rather than a hard stop.
            gymOvershootMinutes = CGFloat(desiredWindow - windowMinutes)
        }

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
        if hitLimit {
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
        case .gym: windowMinutes
        }
    }

    /// Hands the flick's velocity off: project where the gesture was heading,
    /// snap the projection to the five-minute grid, and let the spring settle.
    private func settle(with value: DragGesture.Value) {
        guard let held = grab else { return }
        grab = nil
        lastTickKey = -1
        didKnock = false
        onGrabChange?(nil)
        Haptics.tap(intensity: 0.6)

        let angle: Double
        switch held {
        case .bedtime: angle = DayDialModel.angleDegrees(minutes: bedtimeMinutes)
        case .wake, .sleepBody: angle = DayDialModel.angleDegrees(minutes: wakeMinutes)
        case .gym: angle = DayDialModel.angleDegrees(minutes: gymByMinutes)
        }

        let projected = DayDialModel.projectedMinutes(
            translation: value.predictedEndTranslation,
            handleAngleDegrees: angle,
            radius: gutterRadius
        )

        withAnimation(settleAnimation) {
            gymOvershootMinutes = 0

            if abs(projected) >= 5 {
                let delta = DayDialModel.snappedToTick(projected)
                switch held {
                case .bedtime:
                    let sleep = DayDialModel.clampedSleep(sleepMinutes - delta, windowMinutes: windowMinutes)
                    bedtime = time(at: (wakeMinutes - sleep + 1440) % 1440)
                case .wake:
                    let sleep = DayDialModel.clampedSleep(sleepMinutes + delta, windowMinutes: windowMinutes)
                    wakeTime = time(at: (bedtimeMinutes + sleep) % 1440)
                case .sleepBody:
                    bedtime = bedtime.offset(byMinutes: delta)
                    wakeTime = wakeTime.offset(byMinutes: delta)
                case .gym:
                    travelMinutes = DayDialModel.travelMinutes(
                        desiredWindow: windowMinutes + delta,
                        getReadyMinutes: getReadyMinutes
                    )
                }
            }
        }

        onSettle?()
    }

    /// VoiceOver: every value is reachable without a drag.
    private func adjust(_ which: DayDialModel.Grab, byMinutes delta: Int) {
        withAnimation(settleAnimation) {
            switch which {
            case .bedtime:
                let sleep = DayDialModel.clampedSleep(sleepMinutes - delta, windowMinutes: windowMinutes)
                bedtime = time(at: (wakeMinutes - sleep + 1440) % 1440)
            case .wake, .sleepBody:
                let sleep = DayDialModel.clampedSleep(sleepMinutes + delta, windowMinutes: windowMinutes)
                wakeTime = time(at: (bedtimeMinutes + sleep) % 1440)
            case .gym:
                let requested = travelMinutes + delta
                travelMinutes = min(
                    max(requested, MorningRhythm.travelRange.lowerBound),
                    MorningRhythm.travelRange.upperBound
                )
            }
        }
        Haptics.selection()
        onSettle?()
    }
}
