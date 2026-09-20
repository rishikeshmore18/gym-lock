import SwiftUI

/// The four destinations of the main app.
///
/// `profile` is deliberately not part of `capsuleTabs`: it is drawn as its own
/// detached circle beside the bar, the way a floating action button sits beside
/// a Liquid Glass tab bar on iOS 26.
enum RootTab: Hashable, CaseIterable {
    case home
    case progress
    case community
    case profile

    /// The three destinations that live inside the glass capsule.
    static let capsuleTabs: [RootTab] = [.home, .progress, .community]

    var title: String {
        switch self {
        case .home: "Home"
        case .progress: "Progress"
        case .community: "Community"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .progress: "chart.bar.fill"
        case .community: "person.2.fill"
        case .profile: "person.fill"
        }
    }
}

// MARK: - Glass

/// Liquid Glass where the OS has it, a material where it doesn't, and an
/// opaque surface for anyone who has asked for less transparency.
///
/// Kept separate from `glassCapsule()` because the tab bar floats over live,
/// scrolling content and needs the interactive variant plus a lift shadow,
/// while the streak capsule sits on a still header.
private struct FloatingGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.surface, in: shape)
                .overlay { shape.stroke(Theme.border, lineWidth: 1) }
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(Color.white.opacity(0.55), lineWidth: 1) }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
    }
}

private extension View {
    func floatingGlass<S: Shape>(in shape: S) -> some View {
        modifier(FloatingGlass(shape: shape))
    }
}

// MARK: - Bar

/// The floating tab bar.
///
/// Hand-drawn rather than the system `TabView` bar for one reason: the profile
/// control has to sit *outside* the capsule as its own circle, which the system
/// bar cannot express. Everything else the system bar gave us is kept by hand —
/// the glass, the sliding selection pill, the selection haptic, Reduce
/// Transparency and Reduce Motion — and the bar is installed as a bottom safe
/// area inset, so content still scrolls underneath it and every scroll view
/// still ends above it.
struct RootTabBar: View {
    @Binding var selection: RootTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    /// Matches the system bar closely enough that nothing shifts vertically
    /// when the screen behind it changes.
    private static let capsuleHeight: CGFloat = 58
    private static let circleSize: CGFloat = 58

    private var selectionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // Lets the capsule and the profile circle sense each other, so
                // their glass reads as one piece of material rather than two
                // unrelated panes sitting side by side.
                GlassEffectContainer(spacing: 16) { bar }
            } else {
                bar
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var bar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(RootTab.capsuleTabs, id: \.self) { tab in
                    item(tab)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: Self.capsuleHeight)
            .floatingGlass(in: .capsule)

            profileButton
        }
    }

    private func item(_ tab: RootTab) -> some View {
        let isSelected = selection == tab

        return Button {
            select(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: .semibold))

                Text(tab.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.ink : Theme.inkTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: Self.capsuleHeight - 10)
            .background {
                // One pill that travels between items instead of three that
                // fade in and out — the movement is what tells you the bar
                // responded to your tap.
                if isSelected {
                    Capsule()
                        .fill(Theme.ink.opacity(0.07))
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The detached circle. Filled when it is the active destination, so it
    /// still reads as a tab and not as an action button that did nothing.
    private var profileButton: some View {
        let isSelected = selection == .profile

        return Button {
            select(.profile)
        } label: {
            Image(systemName: isSelected ? "person.fill" : "person")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.ink)
                .frame(width: Self.circleSize, height: Self.circleSize)
                .background {
                    if isSelected {
                        Circle().fill(Theme.ink)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .floatingGlass(in: .circle)
        .accessibilityLabel("Profile")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ tab: RootTab) {
        // Silent when you tap the tab you are already on: a confirmation of
        // nothing is just noise.
        guard tab != selection else { return }
        Haptics.selection()
        withAnimation(selectionAnimation) { selection = tab }
    }
}

#Preview("Tab bar") {
    @Previewable @State var selection: RootTab = .home

    return ZStack(alignment: .bottom) {
        Theme.canvas.ignoresSafeArea()
        RootTabBar(selection: $selection)
    }
}
