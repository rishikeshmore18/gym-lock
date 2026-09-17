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

    /// The source animation runs about 4.4s. At this speed roughly one full
    /// cycle plays inside the time the card is on screen — fast enough to feel
    /// alive, slow enough to read as a burning flame rather than a flicker.
    private static let playbackSpeed: CGFloat = 1.8

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
            await FlameAsset.resolved()
        } placeholder: {
            FlameGlow()
        }
    }
}

/// Where the flame actually is inside the square it is drawn in.
///
/// Measured from the composition rather than guessed: the artwork fills only
/// 36% of its 800×800 canvas across and 49% down, and its centre of mass sits
/// slightly below and right of the canvas centre. Sizing a `frame` around the
/// canvas therefore produces a flame roughly half the size it looks like it
/// should be, surrounded by dead space — which is exactly what was happening.
/// These numbers let the flame be sized by the flame you can see.
enum FlameArtwork {
    // Measured 0.363 × 0.490 across every keyframe, rounded up a touch: the
    // measurement is taken from path vertices, and a curve can bulge slightly
    // past the points that define it. Overstating the fill makes the flame
    // render a hair inside its slot rather than a hair outside it.
    static let fillWidth: CGFloat = 0.375
    static let fillHeight: CGFloat = 0.505

    /// Offset of the artwork's centre from the canvas centre, as a fraction of
    /// the canvas.
    static let centreOffset = CGSize(width: 0.018, height: 0.049)

    /// Width over height of the visible flame.
    static var aspect: CGFloat { fillWidth / fillHeight }
}

/// The flame, sized by what you can see rather than by its canvas.
///
/// The Lottie is rendered at the larger canvas size it needs and allowed to
/// overflow its layout slot — the overflow is transparent margin, so nothing is
/// clipped and nothing collides. The slot the layout reserves is the flame
/// itself.
struct FlameFigure: View {
    /// Height of the visible flame.
    let visibleHeight: CGFloat
    var isAnimating: Bool = true

    var body: some View {
        let canvas = visibleHeight / FlameArtwork.fillHeight

        FlameAnimationView(isAnimating: isAnimating)
            .frame(width: canvas, height: canvas)
            .offset(
                x: -canvas * FlameArtwork.centreOffset.width,
                y: -canvas * FlameArtwork.centreOffset.height
            )
            .frame(
                width: visibleHeight * FlameArtwork.aspect,
                height: visibleHeight
            )
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

/// Loads and holds the one copy of the flame.
///
/// Parsed once and kept, so the first expansion is not also the first time the
/// file is read off disk — that decode is exactly what would show up as a stall
/// on the frame the card starts moving. Preparing it is not playing it: nothing
/// renders until a card mounts.
@MainActor
enum FlameAsset {
    /// The `.lottie` file shipped in `Resources`, without its extension.
    static let name = "flame_streak"

    private static var cached: DotLottieFile?
    /// The load in flight, if any. A card opened while the launch-time preload
    /// is still running joins it rather than being told there is no flame —
    /// which is what used to leave the very first open on a cold launch
    /// showing the placeholder glow for its whole duration.
    private static var loading: Task<DotLottieFile?, Never>?

    /// Call when home appears, so the composition is ready before it is needed.
    static func prepare() async {
        _ = await resolved()
    }

    static func resolved() async -> DotLottieFile? {
        if let cached { return cached }
        if let loading { return await loading.value }

        let task = Task<DotLottieFile?, Never> {
            do {
                let file = try await DotLottieFile.named(name)
                cached = file
                return file
            } catch {
                // A failure here must not leave the streak number floating on
                // a blank card — the placeholder glow stays up instead.
                #if DEBUG
                print("[GymLock] streak flame unavailable: \(error.localizedDescription)")
                #endif
                return nil
            }
        }
        loading = task
        let file = await task.value
        loading = nil
        return file
    }
}
