import Lottie
import SwiftUI

/// The supplied dotLottie flame.
///
/// The source asset is square (800×800), so it is rendered with a locked 1:1
/// aspect ratio — a flame stretched to fill a rectangle reads as a bug no
/// matter how good the rest of the screen is.
///
/// The view is only ever mounted while the streak intro is on screen. Taking it
/// out of the hierarchy is what stops playback: there is no paused player left
/// running behind the home screen.
struct FlameAnimationView: View {
    /// Whether to play. When false the flame is held at a representative frame,
    /// which is what Reduce Motion gets.
    var isAnimating: Bool = true

    /// The source animation runs about 4.4s, which is far longer than the
    /// entrance should ever hold the user. Playing it faster keeps the whole
    /// intro inside its budget without cutting the flame off mid-shape.
    private static let playbackSpeed: CGFloat = 3

    /// Frame the flame settles on when motion is reduced — past the ignition,
    /// into the part of the loop that reads as a burning flame.
    private static let restingProgress: CGFloat = 0.55

    var body: some View {
        animation.accessibilityHidden(true)
    }

    /// `resizable()` and the aspect lock are applied inside each branch because
    /// they are `LottieView`'s own modifiers, and the branch erases the type.
    @ViewBuilder
    private var animation: some View {
        if isAnimating {
            base
                .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .loop)))
                .configure { $0.animationSpeed = Self.playbackSpeed }
                .resizable()
                .aspectRatio(1, contentMode: .fit)
        } else {
            base
                .currentProgress(Self.restingProgress)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private var base: LottieView<FlameGlow> {
        LottieView {
            await Self.load()
        } placeholder: {
            FlameGlow()
        }
    }

    /// Loads the bundled file, degrading quietly if it is ever missing.
    ///
    /// A failure here must not leave the streak number floating on a blank
    /// card, so the placeholder glow stays up instead. It is a backdrop, not a
    /// substitute flame.
    private static func load() async -> DotLottieFile? {
        do {
            return try await DotLottieFile.named(FlameAsset.name)
        } catch {
            #if DEBUG
            print("[GymLock] streak flame unavailable: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}

/// Warm halo shown while the flame decodes.
struct FlameGlow: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1, green: 0.451, blue: 0).opacity(0.22),
                        Color(red: 1, green: 0.451, blue: 0).opacity(0),
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: 66
                )
            )
            .accessibilityHidden(true)
    }
}

/// Where the flame lives in the bundle.
enum FlameAsset {
    /// The `.lottie` file shipped in `Resources`, without its extension.
    static let name = "flame_streak"
}
