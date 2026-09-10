import SwiftUI

/// The streak emblem: a flame with a few sparks around it, as it appears on the
/// stat tile. The gradient runs hot core to deep tip, the same flame that lives
/// in the home header — one fire, two views of it.
struct FlameEmblem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTwinkling = false

    /// Matches the chip's flame so the icon never changes colour between screens.
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 0.847, green: 0.153, blue: 0.075),
            Color(red: 1, green: 0.451, blue: 0),
            Color(red: 1, green: 0.769, blue: 0.180),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        ZStack {
            Image(systemName: "flame.fill")
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(Self.gradient)
                .shadow(color: Color(red: 1, green: 0.451, blue: 0).opacity(0.32), radius: 10, y: 4)

            spark
                .frame(width: 12, height: 12)
                .offset(x: -34, y: -30)
                .twinkle($isTwinkling, delay: 0)

            spark
                .frame(width: 16, height: 16)
                .offset(x: 32, y: -26)
                .twinkle($isTwinkling, delay: 0.55)

            spark
                .frame(width: 8, height: 8)
                .offset(x: -42, y: 4)
                .twinkle($isTwinkling, delay: 1.1)
        }
        .task {
            guard !reduceMotion else { return }
            isTwinkling = true
        }
    }

    private var spark: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(Theme.accentWarm)
            .opacity(isTwinkling ? 1 : 0.45)
    }
}

private extension View {
    /// A slow, quiet twinkle. The sparks are punctuation, not fireworks.
    func twinkle(_ state: Binding<Bool>, delay: Double) -> some View {
        animation(
            .easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(delay),
            value: state.wrappedValue
        )
    }
}

#Preview {
    FlameEmblem()
        .padding(40)
        .background(Theme.surface)
}
