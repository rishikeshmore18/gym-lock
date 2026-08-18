import SwiftUI

// MARK: - Scene reveal

private struct SceneRevealKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// How arrived the surrounding scene is: `0` when it sits a full page away
    /// from the viewport, `1` when it is settled and dominant.
    ///
    /// The pager publishes this per page, so animations derive from scroll
    /// position rather than from `onAppear` and reverse naturally when the user
    /// swipes back up.
    var sceneReveal: CGFloat {
        get { self[SceneRevealKey.self] }
        set { self[SceneRevealKey.self] = newValue }
    }
}

// MARK: - Scene step

private struct SceneStepKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Continuous position within a pinned page's sub-steps: `1.4` means the
    /// page is settled on sub-step 1 and 40% of the way towards sub-step 2
    /// under the user's finger.
    ///
    /// Unlike the discrete sub-step index, this tracks the live drag, so a
    /// scene can map a multi-phase animation onto scroll position and have it
    /// reverse naturally when the user scrolls back.
    var sceneStep: CGFloat {
        get { self[SceneStepKey.self] }
        set { self[SceneStepKey.self] = newValue }
    }
}

/// Smoothly eased 0...1 ramp, used to keep phase transitions from starting or
/// stopping abruptly.
func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

/// The four content roles in a scene, each with its own reveal window so the
/// headline always lands slightly before the hero visual.
enum SceneRole {
    case headline
    case support
    case hero
    case footer

    /// Reveal window this role animates across.
    private var window: ClosedRange<CGFloat> {
        switch self {
        case .headline: return 0.26...0.70
        case .support: return 0.34...0.78
        case .hero: return 0.42...0.90
        case .footer: return 0.56...0.98
        }
    }

    /// Vertical travel in points — deliberately small, per the motion language.
    var travel: CGFloat {
        switch self {
        case .headline: return 20
        case .support: return 16
        case .hero: return 26
        case .footer: return 14
        }
    }

    /// Only the hero scales, and only slightly.
    func scale(at progress: CGFloat) -> CGFloat {
        switch self {
        case .hero: return 0.94 + 0.06 * progress
        default: return 1
        }
    }

    /// Smoothly eased 0...1 progress for this role at a given scene reveal.
    func progress(at reveal: CGFloat) -> CGFloat {
        let range = window
        let raw = (reveal - range.lowerBound) / (range.upperBound - range.lowerBound)
        return smoothstep(raw)
    }
}

private struct SceneElementModifier: ViewModifier {
    let role: SceneRole

    @Environment(\.sceneReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let progress = role.progress(at: reveal)

        return content
            .opacity(Double(progress))
            .scaleEffect(reduceMotion ? 1 : role.scale(at: progress))
            .offset(y: reduceMotion ? 0 : (1 - progress) * role.travel)
    }
}

extension View {
    /// Ties this element's entrance to the scene's scroll position.
    func sceneElement(_ role: SceneRole) -> some View {
        modifier(SceneElementModifier(role: role))
    }
}

// MARK: - Settled artwork motion

/// A very slow breathing drift for settled artwork: enough to feel alive,
/// far too small to read as an animation. Suppressed under Reduce Motion.
private struct BreathingModifier: ViewModifier {
    let isEnabled: Bool
    let amplitude: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLifted = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isLifted ? 1.012 : 1)
            .offset(y: isLifted ? -amplitude : amplitude)
            .onChange(of: isEnabled && !reduceMotion, initial: true) { _, active in
                guard active else {
                    withAnimation(.easeOut(duration: 0.4)) { isLifted = false }
                    return
                }
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    isLifted = true
                }
            }
    }
}

extension View {
    /// Applies the settled-artwork breathing drift.
    func breathing(_ isEnabled: Bool = true, amplitude: CGFloat = 3) -> some View {
        modifier(BreathingModifier(isEnabled: isEnabled, amplitude: amplitude))
    }
}

// MARK: - Micro payoff

/// One-shot pulse used for a single meaningful event per settled scene.
/// `1 → 1.025 → 1`, never more.
private struct PulseModifier: ViewModifier {
    let trigger: Bool
    let repeatCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .task(id: trigger) {
                guard trigger, !reduceMotion else { return }
                for _ in 0..<repeatCount {
                    withAnimation(.easeOut(duration: 0.18)) { scale = 1.025 }
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.easeIn(duration: 0.2)) { scale = 1 }
                    try? await Task.sleep(for: .milliseconds(420))
                }
            }
    }
}

extension View {
    /// Pulses subtly when `trigger` becomes true.
    func subtlePulse(_ trigger: Bool, repeatCount: Int = 2) -> some View {
        modifier(PulseModifier(trigger: trigger, repeatCount: repeatCount))
    }
}
