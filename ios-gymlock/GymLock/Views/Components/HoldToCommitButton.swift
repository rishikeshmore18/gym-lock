import SwiftUI

/// A button you have to mean.
///
/// A tap is cheap, and this is the moment the user agrees to be held to
/// something, so the control asks for a sustained press instead. The instant a
/// finger lands the button turns inside out — white fill, coral border, coral
/// label — and then refills with coral from the left as the press is held. The
/// user is quite literally watching their own commitment fill in.
///
/// Releasing early drains the fill and restores the resting state, with no
/// scolding: the door stays open.
struct HoldToCommitButton: View {
    let title: String
    let caption: String
    /// Seconds of sustained press required.
    var duration: Double = 0.8
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHolding = false
    @State private var progress: Double = 0
    @State private var hasCompleted = false
    /// Ticks already fired this press, so the quarter marks never repeat.
    @State private var ticksFired = 0
    @State private var driver: Task<Void, Never>?

    /// Where the encouraging ticks land during the hold.
    private static let tickPoints: [Double] = [0.25, 0.5, 0.75]

    var body: some View {
        VStack(spacing: 10) {
            button
            Text(caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
        .onDisappear { cancelHold(reset: true) }
    }

    private var button: some View {
        ZStack {
            // The inverted state underneath: white with a coral edge.
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .fill(isInverted ? Theme.surface : Theme.accent)

            // The commitment filling in from the left.
            GeometryReader { proxy in
                Theme.accent
                    .frame(width: proxy.size.width * progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(.rect(cornerRadius: Theme.controlRadius))

            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(Theme.accent, lineWidth: isInverted ? 1.8 : 0)

            // Two copies of the label, cross-masked at the fill edge, so each
            // letter flips from coral to white exactly as the fill passes it —
            // one label that changed colour, not two labels fading.
            GeometryReader { proxy in
                let edge = proxy.size.width * progress

                ZStack {
                    label(.white)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: edge)
                        }

                    label(isInverted ? Theme.accent : .white)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: max(0, proxy.size.width - edge))
                        }
                }
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .contentShape(.rect(cornerRadius: Theme.controlRadius))
        .gesture(pressGesture)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("Press and hold to continue")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            // VoiceOver users get a plain activation; a timed hold is not a
            // reasonable thing to ask of an assistive gesture.
            complete()
        }
    }

    /// White-on-coral at rest, coral-on-white while being pressed.
    private var isInverted: Bool { isHolding || progress > 0 }

    private func label(_ color: Color) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isHolding, !hasCompleted else { return }
                beginHold()
            }
            .onEnded { _ in
                guard !hasCompleted else { return }
                cancelHold(reset: true)
            }
    }

    private func beginHold() {
        isHolding = true
        ticksFired = 0
        Haptics.tap()

        driver?.cancel()
        driver = Task { await runHold() }
    }

    /// Advances the fill on a timer rather than with a single long animation,
    /// because the quarter-point haptics have to fire against the *actual*
    /// progress — an animation would leave them guessing.
    private func runHold() async {
        let step = 1.0 / 60.0
        let increment = step / max(duration, 0.1)

        while !Task.isCancelled, progress < 1 {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { return }

            withAnimation(.linear(duration: step)) {
                progress = min(1, progress + increment)
            }

            if ticksFired < Self.tickPoints.count, progress >= Self.tickPoints[ticksFired] {
                ticksFired += 1
                Haptics.tap()
            }
        }

        guard !Task.isCancelled else { return }
        complete()
    }

    private func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        driver?.cancel()

        withAnimation(.easeOut(duration: 0.14)) { progress = 1 }
        isHolding = false
        Haptics.commit()

        Task {
            try? await Task.sleep(for: .milliseconds(150))
            onComplete()
        }
    }

    private func cancelHold(reset: Bool) {
        driver?.cancel()
        driver = nil
        isHolding = false

        guard reset, !hasCompleted else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .easeOut(duration: 0.28)) {
            progress = 0
        }
    }
}
