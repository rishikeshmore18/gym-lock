import SwiftUI

/// A drag-driven picker wheel in the manner of the iOS date picker, styled in
/// GymLock's language: the selected value is large, bold and coral, and its
/// neighbours shrink, grey out, and fade away above and below it.
///
/// The rows are drawn by an `Animatable` subview so that every frame of a
/// settling animation re-derives each row's size, colour and opacity from its
/// distance to the centre. Without that, the rows would snap to their final
/// styling and merely slide, which reads as a list being nudged rather than a
/// wheel coming to rest.
///
/// Unlike the onboarding word reels, this wheel does not wrap: it has a first
/// and a last value, and it rubber-bands at both ends so the range is legible
/// by feel.
struct ValueWheel: View {
    let labels: [String]
    @Binding var selection: Int

    /// Point spacing between rows.
    var rowHeight: CGFloat = 54
    /// Rows drawn either side of the centre.
    var reach: Int = 2
    /// Font size of the centred value.
    var activeSize: CGFloat = 46
    /// Accessibility description of what is being chosen.
    var accessibilityTitle: String = "Value"

    @Environment(PagerInteractionLock.self) private var pagerLock: PagerInteractionLock?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Continuous wheel position. Whole numbers centre that index.
    @State private var position: Double = 0
    @State private var dragStart: Double?
    @State private var lastTick: Int = 0
    @State private var token = UUID().uuidString

    private var lastIndex: Int { max(labels.count - 1, 0) }

    var body: some View {
        WheelRows(
            labels: labels,
            position: position,
            rowHeight: rowHeight,
            reach: reach,
            activeSize: activeSize
        )
        .frame(height: rowHeight * CGFloat(reach * 2 + 1))
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .overlay(alignment: .center) { selectionRule }
        .mask(fadeMask)
        .gesture(drag)
        .onAppear {
            position = Double(selection)
            lastTick = selection
        }
        .onChange(of: selection) { _, new in
            // Only follow an external change; the drag drives `selection`
            // itself and must not be fought by this.
            guard dragStart == nil, abs(position - Double(new)) > 0.001 else { return }
            withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.34)) {
                position = Double(new)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(labels.indices.contains(selection) ? labels[selection] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commit(to: selection + 1)
            case .decrement: commit(to: selection - 1)
            @unknown default: break
            }
        }
    }

    /// The two hairlines marking the selected row, as on a native picker.
    private var selectionRule: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)
            Spacer()
            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .frame(height: rowHeight)
        .allowsHitTesting(false)
    }

    /// Softens the top and bottom of the wheel so rows dissolve rather than
    /// being cut off by a hard edge.
    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.28),
                .init(color: .black, location: 0.72),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = position
                    pagerLock?.hold(token)
                }

                let raw = (dragStart ?? position) - Double(value.translation.height / rowHeight)
                position = rubberBanded(raw)

                let nearest = Int(position.rounded())
                if nearest != lastTick, labels.indices.contains(nearest) {
                    lastTick = nearest
                    Haptics.selection()
                }
            }
            .onEnded { value in
                // Carry a little of the flick through, so a quick swipe travels
                // further than a slow drag of the same length.
                let momentum = Double(value.predictedEndTranslation.height - value.translation.height)
                let projected = position - momentum / Double(rowHeight) * 0.35
                let target = min(max(Int(projected.rounded()), 0), lastIndex)

                dragStart = nil
                pagerLock?.release(token)
                commit(to: target)
            }
    }

    /// Applies increasing resistance past either end of the range.
    private func rubberBanded(_ raw: Double) -> Double {
        if raw < 0 { return raw * 0.28 }
        if raw > Double(lastIndex) { return Double(lastIndex) + (raw - Double(lastIndex)) * 0.28 }
        return raw
    }

    private func commit(to index: Int) {
        let clamped = min(max(index, 0), lastIndex)

        if clamped != selection {
            selection = clamped
            Haptics.selection()
        }
        lastTick = clamped

        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.2)
                : .spring(response: 0.34, dampingFraction: 0.82)
        ) {
            position = Double(clamped)
        }
    }
}

// MARK: - Rows

/// The rows themselves, re-evaluated every animation frame.
private struct WheelRows: View, Animatable {
    let labels: [String]
    var position: Double
    let rowHeight: CGFloat
    let reach: Int
    let activeSize: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        ZStack {
            ForEach(visibleRows, id: \.self) { index in
                row(at: index)
            }
        }
    }

    private var visibleRows: [Int] {
        let centre = Int(position.rounded())
        return ((centre - reach - 1)...(centre + reach + 1)).filter { labels.indices.contains($0) }
    }

    private func row(at index: Int) -> some View {
        let delta = Double(index) - position
        let distance = abs(delta)
        let focus = max(0, 1 - min(distance, 1))

        // Size and colour both track focus, so the centre row is unmistakably
        // the chosen one even mid-flick.
        let size = activeSize * (0.52 + 0.48 * focus)
        let tint = Theme.accent.mix(with: Theme.inkTertiary, by: 1 - focus)

        return Text(labels[index])
            .font(.system(size: size, weight: focus > 0.5 ? .bold : .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .opacity(opacity(at: distance))
            .offset(y: CGFloat(delta) * rowHeight)
    }

    private func opacity(at distance: Double) -> Double {
        let edge = Double(reach) + 1
        guard distance < edge else { return 0 }
        return pow(0.55, distance) * Double(smoothstep(CGFloat((edge - distance) / 0.9)))
    }
}

// MARK: - Time

/// An hour / minute / AM-PM wheel built from three `ValueWheel`s, so the time
/// pickers speak exactly the same visual language as the number pickers.
struct TimeWheel: View {
    @Binding var time: TimeOfDay
    var accessibilityTitle: String = "Time"

    private static let hours: [String] = (1...12).map { "\($0)" }
    private static let minutes: [String] = stride(from: 0, to: 60, by: 5).map {
        String(format: "%02d", $0)
    }
    private static let meridiems: [String] = ["AM", "PM"]

    var body: some View {
        HStack(spacing: 2) {
            ValueWheel(
                labels: Self.hours,
                selection: hourBinding,
                rowHeight: 50,
                activeSize: 38,
                accessibilityTitle: "\(accessibilityTitle) hour"
            )

            Text(":")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.accent)
                .offset(y: -2)

            ValueWheel(
                labels: Self.minutes,
                selection: minuteBinding,
                rowHeight: 50,
                activeSize: 38,
                accessibilityTitle: "\(accessibilityTitle) minute"
            )

            ValueWheel(
                labels: Self.meridiems,
                selection: meridiemBinding,
                rowHeight: 50,
                activeSize: 26,
                accessibilityTitle: "\(accessibilityTitle) morning or afternoon"
            )
        }
    }

    /// 12-hour clock index, 0 meaning 12 o'clock.
    private var hourBinding: Binding<Int> {
        Binding(
            get: { (time.hour % 12 + 11) % 12 },
            set: { new in
                let isAfternoon = time.hour >= 12
                let hour12 = new + 1
                let normalised = hour12 == 12 ? 0 : hour12
                time.hour = normalised + (isAfternoon ? 12 : 0)
            }
        )
    }

    /// Minutes snap to five, which is how people actually describe the time
    /// they lose.
    private var minuteBinding: Binding<Int> {
        Binding(
            get: { min(time.minute / 5, Self.minutes.count - 1) },
            set: { time.minute = $0 * 5 }
        )
    }

    private var meridiemBinding: Binding<Int> {
        Binding(
            get: { time.hour >= 12 ? 1 : 0 },
            set: { new in
                let base = time.hour % 12
                time.hour = base + (new == 1 ? 12 : 0)
            }
        )
    }
}
