import SwiftUI

/// The 24-hour sleep dial: a moon at bedtime, a sun at wake time, and a coral
/// arc for the sleep between them.
///
/// Midnight sits at the top and the day runs clockwise, which is the convention
/// people already read fluently from every sleep app they have used. Both
/// handles are draggable and snap to five minutes, and the whole control is
/// operable by VoiceOver without any dragging at all.
///
/// The dial is a fast way to *shape* the window. It is not the only way to set
/// it — the cards underneath open a precise wheel — because a drag on a circle
/// is delightful and imprecise, and someone who needs 6:35 should not have to
/// fight for it.
struct RhythmDial: View {
    @Binding var bedtime: TimeOfDay
    @Binding var wakeTime: TimeOfDay

    var size: CGFloat = 290

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which handle the current drag owns, chosen once at drag start so the
    /// finger cannot jump between them mid-gesture.
    @State private var dragging: Handle?
    @State private var lastTickMinutes: Int = -1

    private enum Handle { case bedtime, wake }

    private var ringWidth: CGFloat { size * 0.105 }
    private var radius: CGFloat { (size - ringWidth) / 2 }

    var body: some View {
        ZStack {
            track
            sleepArc
            tickMarks
            handle(.bedtime)
            handle(.wake)
            centreReadout
        }
        .frame(width: size, height: size)
        .contentShape(.circle)
        .gesture(drag)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Layers

    private var track: some View {
        Circle()
            .strokeBorder(Theme.surfaceMuted, lineWidth: ringWidth)
            .overlay {
                Circle()
                    .strokeBorder(Theme.border.opacity(0.7), lineWidth: 1)
            }
            .overlay {
                Circle()
                    .inset(by: ringWidth)
                    .strokeBorder(Theme.border.opacity(0.5), lineWidth: 1)
            }
    }

    /// The sleep window itself, drawn from bedtime clockwise to wake time.
    ///
    /// Trimmed as a fraction of the whole circle rather than by angle, so a
    /// window that crosses midnight is one continuous arc rather than two pieces
    /// that have to be stitched together.
    private var sleepArc: some View {
        let start = Double(bedtime.minutesFromMidnight) / 1440
        let span = Double(sleepMinutes) / 1440

        return Circle()
            .trim(from: 0, to: max(span, 0.001))
            .stroke(
                AngularGradient(
                    colors: [Theme.accent, Theme.accentWarm, Theme.accent],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(start * 360 - 90))
            .padding(ringWidth / 2)
            .shadow(color: Theme.accent.opacity(0.22), radius: 10)
    }

    /// Hour ticks, with the quarter-day marks drawn longer.
    private var tickMarks: some View {
        ZStack {
            ForEach(0..<24, id: \.self) { hour in
                let isMajor = hour % 6 == 0

                Capsule()
                    .fill(isMajor ? Theme.inkTertiary : Theme.border)
                    .frame(width: isMajor ? 2 : 1, height: isMajor ? 10 : 6)
                    .offset(y: -(radius - ringWidth * 0.95))
                    .rotationEffect(.degrees(Double(hour) / 24 * 360))
            }

            // Positioned by polar offset rather than by rotating the text and
            // counter-rotating it, so every label stays upright and lands
            // exactly on its mark.
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                let angle = (Double(hour) / 24 * 360 - 90) * .pi / 180
                let r = radius - ringWidth * 1.9

                Text(hourLabel(hour))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.inkTertiary)
                    .offset(x: r * cos(angle), y: r * sin(angle))
            }
        }
    }

    private func handle(_ which: Handle) -> some View {
        let time = which == .bedtime ? bedtime : wakeTime
        let angle = Double(time.minutesFromMidnight) / 1440 * 360 - 90
        let isDragging = dragging == which

        return ZStack {
            Circle()
                .fill(Theme.surface)
                .frame(width: ringWidth * 1.55, height: ringWidth * 1.55)
                .shadow(color: .black.opacity(0.16), radius: isDragging ? 10 : 5, y: 2)

            Image(systemName: which == .bedtime ? "moon.fill" : "sun.max.fill")
                .font(.system(size: ringWidth * 0.62, weight: .bold))
                .foregroundStyle(which == .bedtime ? Theme.night : Theme.accentWarm)
        }
        .scaleEffect(isDragging && !reduceMotion ? 1.12 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isDragging)
        .offset(x: radius * cos(angle * .pi / 180), y: radius * sin(angle * .pi / 180))
        .accessibilityElement()
        .accessibilityLabel(which == .bedtime ? "Bedtime" : "Wake up")
        .accessibilityValue(time.displayString)
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 5 : -5
            adjust(which, byMinutes: step)
        }
    }

    private var centreReadout: some View {
        VStack(spacing: 2) {
            Text("time asleep")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(sleepMinutes / 60)")
                    .font(.system(size: 46, weight: .bold))
                    .monospacedDigit()
                Text("hr")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)

                Text("\(sleepMinutes % 60)")
                    .font(.system(size: 46, weight: .bold))
                    .monospacedDigit()
                Text("min")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
        }
        .frame(width: size * 0.62)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let centre = CGPoint(x: size / 2, y: size / 2)
                let minutes = minutesAt(point: value.location, centre: centre)

                if dragging == nil {
                    dragging = nearestHandle(to: minutes)
                    Haptics.prepareSelection()
                }

                guard let dragging else { return }
                set(dragging, toMinutes: minutes)
            }
            .onEnded { _ in
                dragging = nil
                lastTickMinutes = -1
            }
    }

    /// Converts a touch point to a minute-of-day, snapped to five minutes.
    private func minutesAt(point: CGPoint, centre: CGPoint) -> Int {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }

        let raw = degrees / 360 * 1440
        return (Int((raw / 5).rounded()) * 5) % 1440
    }

    /// Whichever handle is closer around the circle, measured the short way.
    private func nearestHandle(to minutes: Int) -> Handle {
        func distance(_ time: TimeOfDay) -> Int {
            let delta = abs(time.minutesFromMidnight - minutes)
            return min(delta, 1440 - delta)
        }
        return distance(bedtime) <= distance(wakeTime) ? .bedtime : .wake
    }

    private func set(_ handle: Handle, toMinutes minutes: Int) {
        let time = TimeOfDay(hour: minutes / 60, minute: minutes % 60)

        switch handle {
        case .bedtime:
            guard bedtime != time else { return }
            bedtime = time
        case .wake:
            guard wakeTime != time else { return }
            wakeTime = time
        }

        // One tick per five-minute step, never per frame.
        if minutes != lastTickMinutes {
            lastTickMinutes = minutes
            Haptics.selection()
        }
    }

    private func adjust(_ handle: Handle, byMinutes delta: Int) {
        switch handle {
        case .bedtime: bedtime = bedtime.offset(byMinutes: delta)
        case .wake: wakeTime = wakeTime.offset(byMinutes: delta)
        }
        Haptics.selection()
    }

    // MARK: - Helpers

    private var sleepMinutes: Int {
        (wakeTime.minutesFromMidnight - bedtime.minutesFromMidnight + 1440) % 1440
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: "12a"
        case 6: "6a"
        case 12: "12p"
        default: "6p"
        }
    }

}

// MARK: - Minute dial

/// The small circular minute picker used for get-ready and travel.
///
/// Modelled on the reference: a ticked ring, a coral arc, a knob with a symbol,
/// a big number in the middle, and a minus/plus pair underneath for precision.
/// The drag is for feel; the buttons are for accuracy.
struct MinuteDial: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var minutes: Int
    let range: ClosedRange<Int>

    var size: CGFloat = 132

    @State private var lastTick = -1

    private var ringWidth: CGFloat { 9 }
    private var radius: CGFloat { (size - ringWidth) / 2 }
    /// The dial sweeps 270°, leaving a gap at the bottom for the end labels.
    private var sweep: Double { 270 }

    private var fraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return Double(minutes - range.lowerBound) / span
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 52, alignment: .top)

            dial

            stepper
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .warmCard(radius: 22)
    }

    private var dial: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep / 360)
                .stroke(Theme.surfaceMuted, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: sweep / 360 * fraction)
                .stroke(
                    LinearGradient(
                        colors: [Theme.accentWarm, Theme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            knob

            VStack(spacing: -2) {
                Text("\(minutes)")
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text("min")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }

            endLabels
        }
        .frame(width: size, height: size)
        .contentShape(.circle)
        .gesture(drag)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 5 : -5)
        }
    }

    private var knob: some View {
        let angle = 135 + sweep * fraction

        return ZStack {
            Circle()
                .fill(Theme.surface)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .offset(
            x: radius * cos(angle * .pi / 180),
            y: radius * sin(angle * .pi / 180)
        )
    }

    private var endLabels: some View {
        HStack {
            Text("\(range.lowerBound)")
            Spacer()
            Text("\(range.upperBound)")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.inkTertiary)
        .frame(width: size * 1.06)
        .offset(y: size * 0.36)
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("minus", delta: -5, isEnabled: minutes > range.lowerBound)

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1, height: 22)

            stepButton("plus", delta: 5, isEnabled: minutes < range.upperBound)
        }
        .frame(height: 40)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1)
        }
    }

    private func stepButton(_ symbol: String, delta: Int, isEnabled: Bool) -> some View {
        Button {
            step(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isEnabled ? Theme.ink : Theme.inkTertiary.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(delta > 0 ? "Add 5 minutes" : "Remove 5 minutes")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let centre = CGPoint(x: size / 2, y: size / 2)
                let dx = value.location.x - centre.x
                let dy = value.location.y - centre.y

                var degrees = atan2(dy, dx) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                // Re-base onto the 270° sweep that starts at 135°.
                var travelled = degrees - 135
                if travelled < 0 { travelled += 360 }
                guard travelled <= sweep else { return }

                let span = Double(range.upperBound - range.lowerBound)
                let raw = Double(range.lowerBound) + travelled / sweep * span
                let snapped = min(max(Int((raw / 5).rounded()) * 5, range.lowerBound), range.upperBound)

                guard snapped != minutes else { return }
                minutes = snapped

                if snapped != lastTick {
                    lastTick = snapped
                    Haptics.selection()
                }
            }
            .onEnded { _ in lastTick = -1 }
    }

    private func step(_ delta: Int) {
        let next = min(max(minutes + delta, range.lowerBound), range.upperBound)
        guard next != minutes else { return }
        withAnimation(Theme.stateChange) { minutes = next }
        Haptics.selection()
    }
}

// MARK: - Countdown ring

/// The big progress ring behind the window countdown.
///
/// Draws down as the window closes — the arc is what remains, not what has
/// elapsed, because the number in the middle is also what remains and the two
/// have to agree.
struct CountdownRing: View {
    /// 1 at the start of the window, 0 when it closes.
    let remainingFraction: Double
    var size: CGFloat = 250
    var lineWidth: CGFloat = 16
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accentWash, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: max(0.001, min(1, remainingFraction)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Theme.accentWarm, tint]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.25), radius: 10)

            tickRing
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.9), value: remainingFraction)
    }

    /// The fine minute ticks inside the ring, which give the dial its clock-face
    /// character without adding numbers that would compete with the countdown.
    private var tickRing: some View {
        ZStack {
            ForEach(0..<60, id: \.self) { tick in
                let isMajor = tick % 5 == 0

                Capsule()
                    .fill(isMajor ? Theme.inkTertiary.opacity(0.55) : Theme.border)
                    .frame(width: isMajor ? 1.8 : 1, height: isMajor ? 11 : 6)
                    .offset(y: -(size / 2 - lineWidth - 14))
                    .rotationEffect(.degrees(Double(tick) / 60 * 360))
            }
        }
    }
}
