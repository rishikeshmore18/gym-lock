import SwiftUI

/// The recurring bottom-edge affordance that teaches the vertical page gesture.
/// A slow, low-amplitude drift — enough to read as "keep going", never busy.
struct SwipeUpHint: View {
    var label: String = "swipe up"
    var isActive: Bool

    @State private var lift = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .offset(y: lift ? -3 : 3)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Swipe up to continue")
        .onChange(of: isActive, initial: true) { _, active in
            guard active else {
                lift = false
                return
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                lift = true
            }
        }
    }
}
