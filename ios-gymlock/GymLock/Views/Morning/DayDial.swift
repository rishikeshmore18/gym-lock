import SwiftUI

// MARK: - Pure model

/// The maths behind the Day Dial, kept out of the view so every rule is
/// testable without a screen or a running clock.
///
/// The dial's convention matches `RhythmDial`: midnight at the top, the day
/// running clockwise, values snapped to five minutes.
enum DayDialModel {
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

    /// Screen offset for a handle sitting at `minutes` on a ring of `radius`,
    /// with an optional extra rotation for rubber-band overshoot.
    static func offset(minutes: Int, radius: CGFloat, extraDegrees: Double = 0) -> CGSize {
        let angle = (angleDegrees(minutes: minutes) - 90 + extraDegrees) * .pi / 180
        return CGSize(width: radius * cos(angle), height: radius * sin(angle))
    }

    /// Travel minutes implied by a dragged gym-by position.
    ///
    /// The handle can ask for any window on the circle; this is where it is
    /// clamped to the product range. It never touches wake time — the caller
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
}

// MARK: - The dial

/// The Day Dial: the 24-hour ring from `RhythmDial`, extended with a second,
/// inner arc for the gym window and a third handle for gym-by.
///
/// The outer arc is sleep, bedtime to wake time, drawn in ink. The inner arc
/// is the gym window, wake time to gym-by, and it is the one coral accent on
/// the screen. Dragging the moon or sun moves the sleep window; dragging the
/// dumbbell changes travel minutes and never touches wake time.
///
/// Gestures follow `docs/UI-RULES.md` §6: 1:1 tracking, a drag-start handle
/// lock so the finger cannot jump between handles mid-gesture, rubber-banding
/// at the travel limits, and velocity handed off on release.
struct DayDial: View {
    @Binding var bedtime: TimeOfDay
    @Binding var wakeTime: TimeOfDay
    @Binding var travelMinutes: Int
    let getReadyMinutes: Int

    var size: CGFloat = 290

    /// Called when a gesture ends and momentum has been applied: the moment a
    /// rhythm change should be committed and checked against the night lock.
    var onSettle: (() -> Void)?

    private enum Handle { case bedtime, wake, gym }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which handle the current drag owns, chosen once at drag start so the
    /// finger cannot jump between them mid-gesture.
    @State private var dragging: Handle?
    @State private var lastTickKey: Int = -1
    /// Visual overshoot, in minutes of arc, while the gym handle is held past
    /// its clamped value. Springs back to zero on release.
    @State private var gymOvershootMinutes: CGFloat = 0

    // MARK: Metrics

    private var outerWidth: CGFloat { size * 0.105 }
    private var outerRadius: CGFloat { (size - outerWidth) / 2 }
    private var innerWidth: CGFloat { max(9, size * 0.036) }
    /// Concentric, never overlapping: the inner band sits outside the outer
    /// band with a gap wide enough for the hour labels.
    private var innerRadius: CGFloat { outerRadius - outerWidth * 1.55 - innerWidth / 2 }

    // MARK: Derived

    private var sleepMinutes: Int {
        (wakeTime.minutesFromMidnight - bedtime.minutesFromMidnight + 1440) % 1440
    }

    private var windowMinutes: Int { getReadyMinutes + travelMinutes }

    private var gymByMinutes: Int {
        (wakeTime.minutesFromMidnight + windowMinutes) % 1440
    }

    private var settleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.30, dampingFraction: 0.86)
    }

    var body: some View {
        ZStack {
            outerTrack
            sleepArc
            innerTrack
            gymArc
            tickMarks
            hourLabels
            handle(.bedtime)
            handle(.wake)
            handle(.gym)
            centreReadout
        }
        .frame(width: size, height: size)
        .contentShape(.circle)
        .gesture(drag)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("day dial")
    }

    // MARK: - Layers

    private var outerTrack: some View {
        Circle()
            .strokeBorder(Theme.surfaceMuted, lineWidth: outerWidth)
            .frame(width: outerRadius * 2 + outerWidth, height: outerRadius * 2 + outerWidth)
            .overlay {
                Circle()
                    .strokeBorder(Theme.border.opacity(0.7), lineWidth: 1)
            }
            .overlay {
                Circle()
                    .inset(by: outerWidth)
                    .strokeBorder(Theme.border.opacity(0.5), lineWidth: 1)
            }
    }

    /// The sleep window, bedtime to wake time, in ink at low opacity.
    ///
    /// Deliberately not coral: the gym window owns the accent, and two coral
    /// arcs would blur which fact the screen is for.
    private var sleepArc: some View {
        let start = Double(bedtime.minutesFromMidnight) / 1440
        let span = Double(sleepMinutes) / 1440

        return Circle()
            .trim(from: 0, to: max(span, 0.001))
            .stroke(
                Theme.ink.opacity(0.16),
                style: StrokeStyle(lineWidth: outerWidth, lineCap: .round)
            )
            .frame(width: outerRadius * 2 + outerWidth, height: outerRadius * 2 + outerWidth)
            .rotationEffect(.degrees(start * 360 - 90))
    }

    private var innerTrack: some View {
        Circle()
            .strokeBorder(Theme.surfaceMuted.opacity(0.55), lineWidth: innerWidth)
            .frame(width: innerRadius * 2 + innerWidth, height: innerRadius * 2 + innerWidth)
            .overlay {
                Circle()
                    .strokeBorder(Theme.border.opacity(0.4), lineWidth: 1)
            }
    }

    /// The gym window, wake time to gym-by. The one coral accent on the screen,
    /// and the right one: this window is what the app is for.
    private var gymArc: some View {
        let start = Double(wakeTime.minutesFromMidnight) / 1440
        let span = Double(windowMinutes) / 1440

        return Circle()
            .trim(from: 0, to: max(span, 0.001))
            .stroke(
                Theme.accent,
                style: StrokeStyle(lineWidth: innerWidth, lineCap: .round)
            )
            .frame(width: innerRadius * 2 + innerWidth, height: innerRadius * 2 + innerWidth)
            .rotationEffect(.degrees(start * 360 - 90))
            .shadow(color: Theme.accent.opacity(0.22), radius: 8)
    }

    /// Hour ticks on the outer band, quarter-day marks drawn longer.
    private var tickMarks: some View {
        ZStack {
            ForEach(0..<24, id: \.self) { hour in
                let isMajor = hour % 6 == 0

                Capsule()
                    .fill(isMajor ? Theme.inkTertiary : Theme.border)
                    .frame(width: isMajor ? 2 : 1, height: isMajor ? 10 : 6)
                    .offset(y: -(outerRadius - outerWidth * 0.95))
                    .rotationEffect(.degrees(Double(hour) / 24 * 360))
            }
        }
    }

    /// Hour labels sitting in the gap between the two bands, positioned by
    /// polar offset so every label stays upright.
    private var hourLabels: some View {
        let radius = (outerRadius - outerWidth / 2 + innerRadius + innerWidth / 2) / 2

        return ZStack {
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                let angle = (Double(hour) / 24 * 360 - 90) * .pi / 180

                Text(hourLabel(hour))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.inkTertiary)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: "12a"
        case 6: "6a"
        case 12: "12p"
        default: "6p"
        }
    }

    // MARK: - Handles

    @ViewBuilder
    private func handle(_ which: Handle) -> some View {
        let isDragging = dragging == which

        switch which {
        case .bedtime, .wake:
            let minutes = which == .bedtime ? bedtime.minutesFromMidnight : wakeTime.minutesFromMidnight
            let offset = DayDialModel.offset(minutes: minutes, radius: outerRadius)

            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: outerWidth * 1.55, height: outerWidth * 1.55)
                    .shadow(color: .black.opacity(0.16), radius: isDragging ? 10 : 5, y: 2)

                Image(systemName: which == .bedtime ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: outerWidth * 0.62, weight: .bold))
                    .foregroundStyle(which == .bedtime ? Theme.night : Theme.accentWarm)
            }
            .scaleEffect(isDragging && !reduceMotion ? 1.12 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isDragging)
            .offset(offset)
            .accessibilityElement()
            .accessibilityLabel(which == .bedtime ? "Bedtime" : "Wake time")
            .accessibilityValue(time(at: minutes).displayString)
            .accessibilityAdjustableAction { direction in
                adjust(which, byMinutes: direction == .increment ? 5 : -5)
            }

        case .gym:
            // Rubber-banded overshoot is visual only: the value stays clamped.
            let extraDegrees = Double(
                DayDialModel.rubberband(gymOvershootMinutes * 0.25, dimension: size)
            )
            let offset = DayDialModel.offset(
                minutes: gymByMinutes,
                radius: innerRadius,
                extraDegrees: extraDegrees
            )

            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: innerWidth * 2.6, height: innerWidth * 2.6)
                    .shadow(color: .black.opacity(0.16), radius: isDragging ? 9 : 4, y: 2)

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: innerWidth * 1.15, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .scaleEffect(isDragging && !reduceMotion ? 1.12 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isDragging)
            .offset(offset)
            .accessibilityElement()
            .accessibilityLabel("Gym by")
            .accessibilityValue(time(at: gymByMinutes).displayString)
            .accessibilityAdjustableAction { direction in
                adjust(.gym, byMinutes: direction == .increment ? 5 : -5)
            }
        }
    }

    private func time(at minutes: Int) -> TimeOfDay {
        TimeOfDay(hour: minutes / 60, minute: minutes % 60)
    }

    // MARK: - Centre readout

    @ViewBuilder
    private var centreReadout: some View {
        VStack(spacing: 10) {
            if dragging == .gym {
                metric(value: "\(windowMinutes)", unit: "min", caption: "to the gym", tint: Theme.accent, isLarge: true)
            } else if dragging == .bedtime || dragging == .wake {
                metric(value: sleepText, unit: "", caption: "sleep", tint: Theme.ink, isLarge: true)
            } else {
                metric(value: sleepText, unit: "", caption: "sleep", tint: Theme.ink, isLarge: false)
                metric(value: "\(windowMinutes)", unit: "min", caption: "to the gym", tint: Theme.accent, isLarge: false)
            }
        }
        .frame(width: size * 0.52)
        .animation(settleAnimation, value: dragging)
        .accessibilityElement(children: .combine)
    }

    private var sleepText: String {
        "\(sleepMinutes / 60)h \(sleepMinutes % 60)m"
    }

    private func metric(
        value: String,
        unit: String,
        caption: String,
        tint: Color,
        isLarge: Bool
    ) -> some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: isLarge ? 44 : 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: isLarge ? 16 : 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .contentTransition(.numericText())

            Text(caption)
                .font(.system(size: isLarge ? 13 : 11, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    // MARK: - Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let centre = CGPoint(x: size / 2, y: size / 2)

                if dragging == nil {
                    dragging = handle(at: value.location, centre: centre)
                    Haptics.prepareSelection()
                }

                guard let dragging else { return }
                let minutes = DayDialModel.minutes(at: value.location, centre: centre)
                apply(dragging, fingerMinutes: minutes)
            }
            .onEnded { value in
                settle(with: value)
            }
    }

    /// Which handle a touch belongs to.
    ///
    /// The gym handle lives on the inner band, so a touch near that radius
    /// always means the gym handle. That keeps a finger from stealing the sun
    /// when the window is short and the two handles sit close together.
    private func handle(at point: CGPoint, centre: CGPoint) -> Handle {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let distance = sqrt(dx * dx + dy * dy)

        if abs(distance - innerRadius) <= size * 0.09 { return .gym }

        let minutes = DayDialModel.minutes(at: point, centre: centre)

        func angularDistance(_ time: TimeOfDay) -> Int {
            let delta = abs(time.minutesFromMidnight - minutes)
            return min(delta, 1440 - delta)
        }

        return angularDistance(bedtime) <= angularDistance(wakeTime) ? .bedtime : .wake
    }

    private func apply(_ handle: Handle, fingerMinutes: Int) {
        let finger = time(at: fingerMinutes)

        switch handle {
        case .bedtime:
            guard bedtime != finger else { return }
            bedtime = finger
        case .wake:
            guard wakeTime != finger else { return }
            wakeTime = finger
        case .gym:
            let desired = wakeTime.minutes(until: finger)
            let travel = DayDialModel.travelMinutes(
                desiredWindow: desired,
                getReadyMinutes: getReadyMinutes
            )
            guard travel != travelMinutes || gymOvershootMinutes != 0 else { return }
            travelMinutes = travel
            // What the finger asked for beyond the clamp, shown as a small
            // visual overshoot rather than a hard stop.
            gymOvershootMinutes = CGFloat(desired - windowMinutes)
        }

        // One tick per five-minute step of *value*, never per frame: a finger
        // pinned against the clamp spins without changing anything and must
        // not buzz.
        if valueKey(for: handle) != lastTickKey {
            lastTickKey = valueKey(for: handle)
            Haptics.selection()
        }
    }

    private func valueKey(for handle: Handle) -> Int {
        switch handle {
        case .bedtime: bedtime.minutesFromMidnight
        case .wake: wakeTime.minutesFromMidnight
        case .gym: windowMinutes
        }
    }

    /// Hands the flick's velocity off: project where the gesture was heading,
    /// snap the projection to the five-minute grid, and let the spring settle.
    private func settle(with value: DragGesture.Value) {
        guard let handle = dragging else { return }
        dragging = nil
        lastTickKey = -1

        let angle: Double
        let radius: CGFloat
        switch handle {
        case .bedtime:
            angle = DayDialModel.angleDegrees(minutes: bedtime.minutesFromMidnight)
            radius = outerRadius
        case .wake:
            angle = DayDialModel.angleDegrees(minutes: wakeTime.minutesFromMidnight)
            radius = outerRadius
        case .gym:
            angle = DayDialModel.angleDegrees(minutes: gymByMinutes)
            radius = innerRadius
        }

        let projected = DayDialModel.projectedMinutes(
            translation: value.predictedEndTranslation,
            handleAngleDegrees: angle,
            radius: radius
        )

        withAnimation(settleAnimation) {
            gymOvershootMinutes = 0

            if abs(projected) >= 5 {
                let delta = DayDialModel.snappedToTick(projected)
                switch handle {
                case .bedtime:
                    bedtime = bedtime.offset(byMinutes: delta)
                case .wake:
                    wakeTime = wakeTime.offset(byMinutes: delta)
                case .gym:
                    let desired = windowMinutes + delta
                    travelMinutes = DayDialModel.travelMinutes(
                        desiredWindow: desired,
                        getReadyMinutes: getReadyMinutes
                    )
                }
            }
        }

        onSettle?()
    }

    /// VoiceOver: every value is reachable without a drag.
    private func adjust(_ handle: Handle, byMinutes delta: Int) {
        withAnimation(settleAnimation) {
            switch handle {
            case .bedtime:
                bedtime = bedtime.offset(byMinutes: delta)
            case .wake:
                wakeTime = wakeTime.offset(byMinutes: delta)
            case .gym:
                let requested = travelMinutes + delta
                travelMinutes = min(
                    max(requested, MorningRhythm.travelRange.lowerBound),
                    MorningRhythm.travelRange.upperBound
                )
            }
        }
        Haptics.selection()
    }
}
