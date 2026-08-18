import SwiftUI

/// The loop artwork played back as a fixed shot.
///
/// The frame never moves. There is no camera drift, no push, no blur and no
/// breathing — the artwork sits in exactly the same place for the whole scene and
/// the *only* thing that changes is which drawing is showing. Because the seven
/// frames were drawn on identical geometry, holding the window still is what lets
/// the character read as moving: every pixel that changes between two frames is a
/// pixel the illustrator meant to change.
///
/// Two implementation details carry the playback:
///
/// - **Every frame stays mounted** and is switched by opacity alone, so no decode
///   ever lands mid-change and stutters the cut.
/// - **The dissolve is deliberately short.** A slow crossfade double-exposes two
///   poses and reads as a slideshow; a quick one reads as a cut in a film.
struct LoopFilmView: View {
    let state: LoopState

    /// Seconds each change takes. Short on purpose — see above.
    private static let dissolve: Double = 0.16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(
            .easeInOut(duration: reduceMotion ? 0.28 : Self.dissolve),
            value: state.id
        )
        .clipShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if let number = state.nodeNumber {
            return "Loop step \(number) of 6. \(state.caption)"
        }
        return "The missed-workout loop. \(state.caption)"
    }
}
