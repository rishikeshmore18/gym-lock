import SwiftUI

/// What a cold launch opens on: the canvas and the real logo, nothing else.
///
/// It carries on from the system's icon zoom. The logo arrives a touch small
/// and settles, holds while the app prepares underneath, then lifts very
/// slightly as the whole cover fades to reveal it. No text, no spinner: its
/// only job is to stop anyone watching home assemble itself.
///
/// Decorative, so VoiceOver never lands on it. It blocks touches only while
/// it is opaque.
struct GymLockLaunchIntroView: View {
    let phase: LaunchCover.Phase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    /// The same size and corners as the logo that opens onboarding, so a new
    /// user's first two frames show the same mark.
    private static let logoSize: CGFloat = 148
    private static let logoRadius: CGFloat = 36
    /// A mark on the exact midpoint reads as slightly low.
    private static let opticalLift: CGFloat = 12

    private static let arrivalScale: CGFloat = 0.92
    private static let departureScale: CGFloat = 1.04

    private var isLeaving: Bool { phase != .covering }

    var body: some View {
        ZStack {
            Theme.canvas

            logo
                .scaleEffect(logoScale)
                .offset(y: -Self.opticalLift)
        }
        .ignoresSafeArea()
        .opacity(isLeaving ? 0 : 1)
        .animation(exitAnimation, value: isLeaving)
        .contentShape(.rect)
        .allowsHitTesting(!isLeaving)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            // Continues the movement of the system's icon zoom. Fully damped:
            // it settles, it does not bounce.
            withAnimation(.spring(response: 0.3, dampingFraction: 1)) { hasLanded = true }
        }
    }

    private var logo: some View {
        Image("GymLockLogo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.logoSize, height: Self.logoSize)
            .clipShape(.rect(cornerRadius: Self.logoRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Self.logoRadius)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 26, x: 0, y: 14)
    }

    /// Reduce Motion holds the logo still; the reveal is a plain crossfade.
    private var logoScale: CGFloat {
        guard !reduceMotion else { return 1 }
        if isLeaving { return Self.departureScale }
        return hasLanded ? 1 : Self.arrivalScale
    }

    private var exitAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.22)
    }
}

#Preview("Launch intro") {
    GymLockLaunchIntroView(phase: .covering)
}
