import SwiftUI

/// Liquid Glass where the OS supports it, an honest fallback where it doesn't.
///
/// Deliberately narrow in scope. Glass earns its place on the few elements that
/// float above content — the streak capsule and the tab bar — and nowhere else.
/// Applying it to every card would flatten the hierarchy it exists to create.
struct GlassCapsuleBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            // Opaque by request: no blur, no translucency, full contrast.
            content
                .background(Theme.surface, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(Theme.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
        }
    }
}

extension View {
    /// Floating capsule treatment used by the streak control.
    func glassCapsule() -> some View {
        modifier(GlassCapsuleBackground())
    }
}
