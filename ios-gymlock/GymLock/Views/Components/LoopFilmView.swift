import SwiftUI

/// The loop artwork played as a film rather than shown as a slideshow.
///
/// The seven supplied frames are used exactly as drawn — nothing is redrawn,
/// recomposed, or replaced. What changes is *how* they are played:
///
/// 1. **The camera never stops.** A continuous, un-looping drift (three sine
///    waves on different periods, plus a hair of sway) runs off a `TimelineView`
///    clock, so the image is always in motion. A slideshow reads as a slideshow
///    mainly because motion *stops* between frames; here it never does, and the
///    eye reads the whole thing as one moving shot.
/// 2. **Frames dissolve on a camera push.** Each change comes with a short
///    push-in that rises and falls, plus a touch of blur at its peak. The pose
///    changes while the camera is moving, which is what makes the character read
///    as moving rather than as being swapped.
/// 3. **Every frame stays mounted.** All seven are resident and cross-dissolved
///    by opacity, so no decode ever lands mid-dissolve and stutters the motion.
///
/// The push and blur are computed from elapsed time, not driven by the animation
/// system, so they are frame-accurate and cannot desynchronise from the dissolve.
struct LoopFilmView: View {
    let state: LoopState
    /// Whether the clock should run. Paused when the scene is off screen.
    var isPlaying: Bool = true

    /// Seconds the push-in takes to reach its peak.
    private static let pushPeak: Double = 0.36
    /// Baseline overscan, which gives the drift room to move inside the window.
    private static let overscan: CGFloat = 1.075

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lastCut: Date = .distantPast

    var body: some View {
        Group {
            if reduceMotion {
                LoopFrameStack(state: state, crossfade: 0.26)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
                    film(at: context.date)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 26))
        .onChange(of: state.id) { _, _ in lastCut = .now }
        .onAppear { lastCut = .now }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func film(at date: Date) -> some View {
        let clock = date.timeIntervalSinceReferenceDate
        let sinceCut = max(0, date.timeIntervalSince(lastCut))
        let push = pushEnvelope(sinceCut)

        return LoopFrameStack(state: state, crossfade: 0.3)
            .scaleEffect(Self.overscan + drift(clock, period: 5.5, amount: 0.014) + push * 0.02)
            .offset(
                x: drift(clock, period: 9.0, amount: 5, phase: 0.4),
                y: drift(clock, period: 6.5, amount: 4, phase: 1.1)
            )
            .rotationEffect(.degrees(drift(clock, period: 11.0, amount: 0.3)))
            .blur(radius: push * 1.4)
    }

    /// One strand of the camera drift. Periods are deliberately co-prime-ish, so
    /// the combined path never visibly repeats.
    private func drift(_ clock: Double, period: Double, amount: CGFloat, phase: Double = 0) -> CGFloat {
        amount * CGFloat(sin(clock * 2 * .pi / period + phase))
    }

    /// A 0→1→0 bump: zero at the cut, peaking a third of a second later, then
    /// settling. Starting at zero is what keeps the push from popping.
    private func pushEnvelope(_ elapsed: Double) -> CGFloat {
        let normalised = elapsed / Self.pushPeak
        guard normalised < 6 else { return 0 }
        return CGFloat(normalised * exp(1 - normalised))
    }

    private var accessibilityDescription: String {
        if let number = state.nodeNumber {
            return "Loop step \(number) of 6. \(state.caption)"
        }
        return "The missed-workout loop. \(state.caption)"
    }
}

/// All frames of the sequence, cross-dissolved by opacity.
///
/// Keeping them mounted costs a little memory and buys smooth playback: every
/// frame is shown on every lap anyway, so nothing here is wasted.
private struct LoopFrameStack: View {
    let state: LoopState
    let crossfade: Double

    var body: some View {
        ZStack {
            ForEach(LoopState.sequence) { frame in
                IllustrationView(
                    illustration: frame.illustration,
                    cornerRadius: 0,
                    isBreathing: false
                )
                .opacity(frame.id == state.id ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: crossfade), value: state.id)
    }
}
