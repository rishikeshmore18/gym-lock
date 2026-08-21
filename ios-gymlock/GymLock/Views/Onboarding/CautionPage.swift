import SwiftUI

/// Scene 8 — the gate. A quiet, honest filter before the commitment, and the one
/// place in the story where the artwork is allowed to hit hard.
///
/// This screen is a warning, so its illustration does not drift in politely: the
/// sign is *planted*. It drops, overshoots, and rocks itself still on its base
/// while a shockwave rings out from underneath it. That is the whole point of the
/// scene — the user is being asked to reconsider, and a sign that lands with
/// weight says so before the copy does.
struct CautionPage: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Incremented to fire the sign's reaction. Driving it off a counter rather
    /// than a flag lets the sign be struck more than once in the scene.
    @State private var jolt = 0
    @State private var warningShown = false
    @State private var shockScale: CGFloat = 0.5
    @State private var shockOpacity: Double = 0

    var body: some View {
        // A slightly shorter hero than its neighbours: the sign lifts and
        // overshoots, and it needs the headroom to do that without colliding
        // with the headline.
        OnboardingScene(topAnchor: 0.12, heroMaxHeightFraction: 0.38) {
            AccentedText(
                full: "GymLock is not a motivation app.",
                highlighted: ["not a motivation app."],
                size: 32
            )
            .sceneElement(.headline)
        } hero: {
            sign
                .sceneElement(.hero)
        } footer: {
            VStack(alignment: .leading, spacing: 14) {
                Text("it removes the negotiation.\nthat only helps if you actually want to go.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(5)
                    .opacity(warningShown ? 1 : 0)
                    .offset(y: warningShown ? 0 : 10)

                SwipeUpHint(label: "i'm serious", isActive: isActive && warningShown)
                    .frame(maxWidth: .infinity)
                    .opacity(warningShown ? 1 : 0)
            }
            .sceneElement(.footer)
        }
        .task(id: isActive) { await run() }
    }

    // MARK: - The sign

    @ViewBuilder
    private var sign: some View {
        ZStack {
            shockwave

            if reduceMotion {
                IllustrationView(illustration: .cautionSign, isBreathing: false)
            } else {
                KeyframeAnimator(initialValue: SignImpact(), trigger: jolt) { impact in
                    IllustrationView(illustration: .cautionSign, isBreathing: false)
                        // Anchored at the base so the sign pivots like something
                        // standing on the ground, not something spinning in space.
                        .scaleEffect(impact.scale, anchor: .bottom)
                        .rotationEffect(.degrees(impact.rotation), anchor: .bottom)
                        .offset(y: impact.lift)
                } keyframes: { _ in
                    KeyframeTrack(\.rotation) {
                        SpringKeyframe(-7.5, duration: 0.13, spring: .snappy)
                        SpringKeyframe(5.4, duration: 0.17, spring: .bouncy)
                        SpringKeyframe(-3.1, duration: 0.17)
                        SpringKeyframe(1.6, duration: 0.17)
                        SpringKeyframe(-0.6, duration: 0.16)
                        SpringKeyframe(0, duration: 0.20)
                    }
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.075, duration: 0.14, spring: .snappy)
                        SpringKeyframe(0.982, duration: 0.17)
                        SpringKeyframe(1.016, duration: 0.20)
                        SpringKeyframe(1.0, duration: 0.29)
                    }
                    KeyframeTrack(\.lift) {
                        SpringKeyframe(-17, duration: 0.13, spring: .snappy)
                        SpringKeyframe(5, duration: 0.16)
                        SpringKeyframe(-1.5, duration: 0.18)
                        SpringKeyframe(0, duration: 0.23)
                    }
                }
            }
        }
    }

    /// The ring that leaves the base on impact. It reads as the force of the
    /// landing rather than as decoration, so it only ever fires with the jolt.
    private var shockwave: some View {
        Circle()
            .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 3)
            .scaleEffect(shockScale)
            .opacity(shockOpacity)
            .blendMode(.multiply)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Timeline

    private func run() async {
        guard isActive else {
            warningShown = false
            shockOpacity = 0
            return
        }

        try? await Task.sleep(for: .milliseconds(540))
        guard !Task.isCancelled else { return }
        strike(force: .medium)

        try? await Task.sleep(for: .milliseconds(760))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { warningShown = true }

        // A second, lighter knock as the warning copy lands, so the sign is
        // still present in the scene instead of having gone inert.
        try? await Task.sleep(for: .milliseconds(1400))
        guard !Task.isCancelled else { return }
        strike(force: .soft)
    }

    private enum Force {
        case medium, soft

        var ringStart: CGFloat { self == .medium ? 0.50 : 0.66 }
        var ringEnd: CGFloat { self == .medium ? 1.24 : 1.05 }
        var ringAlpha: Double { self == .medium ? 0.55 : 0.28 }
    }

    private func strike(force: Force) {
        jolt += 1

        switch force {
        case .medium: Haptics.medium()
        case .soft: Haptics.soft()
        }

        guard !reduceMotion else { return }

        shockScale = force.ringStart
        shockOpacity = force.ringAlpha

        withAnimation(.easeOut(duration: 0.72)) {
            shockScale = force.ringEnd
            shockOpacity = 0
        }
    }
}

/// The animatable state of the sign as it lands and rocks itself still.
private struct SignImpact {
    var rotation: Double = 0
    var scale: CGFloat = 1
    var lift: CGFloat = 0
}
