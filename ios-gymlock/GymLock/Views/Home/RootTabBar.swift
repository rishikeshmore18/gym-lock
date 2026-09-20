import SwiftUI

/// The four destinations of the main app.
///
/// `profile` is deliberately not part of `capsuleTabs`: it is drawn as its own
/// detached glass circle beside the bar, the way a floating control sits beside
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

// MARK: - Motion

/// The bar's motion language, in one place so the pill, the press and the
/// screen behind them can never disagree about how fast the bar is.
private enum TabMotion {
    /// The selection travelling between tabs.
    ///
    /// Under-damped on purpose. Liquid Glass is supposed to read as a material
    /// with mass — it arrives, overshoots very slightly and settles. A critically
    /// damped curve here is what made the old bar feel like a web control.
    static let morph: Animation = .spring(response: 0.34, dampingFraction: 0.68)
    /// Same job, no bounce and shorter, for Reduce Motion.
    static let morphReduced: Animation = .easeInOut(duration: 0.2)
    /// The give under a finger.
    static let press: Animation = .spring(response: 0.22, dampingFraction: 0.65)
}

// MARK: - Press behaviour

/// Squish on finger-down, spring back on release, with the soft haptic that
/// goes with a material yielding.
///
/// Separate from the selection tick deliberately: pressing gives you the give
/// immediately, even on the tab you are already on, and only an actual change
/// of destination earns the selection tick.
private struct TabPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .animation(TabMotion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard isPressed else { return }
                Haptics.press()
            }
    }
}

// MARK: - Item contents

/// Icon and label. Knows nothing about glass — both bar implementations draw
/// the same contents so they can never drift apart.
private struct TabItemLabel: View {
    let tab: RootTab
    let isSelected: Bool
    let reduceMotion: Bool

    /// Counted rather than bound to `isSelected`, so the icon bounces when a
    /// tab becomes current and stays still when it is abandoned.
    @State private var bounce = 0

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: tab.symbol)
                .font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, options: .speed(1.4), value: bounce)
                .scaleEffect(isSelected ? 1.05 : 1)

            Text(tab.title)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isSelected ? Theme.ink : Theme.inkTertiary)
        .frame(maxWidth: .infinity)
        .frame(height: RootTabBar.itemHeight)
        .onChange(of: isSelected) { _, selected in
            guard selected, !reduceMotion else { return }
            bounce += 1
        }
    }
}

// MARK: - iOS 26 Liquid Glass

/// The real thing: one `GlassEffectContainer`, and a selection that is itself
/// a piece of glass carrying a `glassEffectID`.
///
/// That identity is the whole difference. Because the same glass element is
/// removed from one tab and inserted into the next inside a single animated
/// transaction, the system does not slide a rectangle — it morphs the material,
/// stretching and re-forming it between positions, with the lensing and
/// specular edge recomputed the entire way. `.interactive()` then lets the
/// glass itself flex under the finger rather than only the contents scaling.
@available(iOS 26.0, *)
private struct LiquidGlassBar: View {
    @Binding var selection: RootTab
    let reduceMotion: Bool
    let onSelect: (RootTab) -> Void

    @Namespace private var glass

    var body: some View {
        // Wide enough that the capsule and the profile circle sense each other
        // and their edges lens together as the selection approaches the end of
        // the bar, without the two ever merging into one shape at rest.
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: RootTabBar.gap) {
                HStack(spacing: 2) {
                    ForEach(RootTab.capsuleTabs, id: \.self) { tab in
                        Button {
                            onSelect(tab)
                        } label: {
                            TabItemLabel(tab: tab, isSelected: selection == tab, reduceMotion: reduceMotion)
                                .background {
                                    if selection == tab {
                                        selectionGlass
                                    }
                                }
                                .contentShape(.capsule)
                        }
                        .buttonStyle(TabPressStyle(reduceMotion: reduceMotion))
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: RootTabBar.barHeight)
                .glassEffect(.regular, in: .capsule)

                profileCircle
            }
        }
    }

    /// A faint ink wash *inside* the glass rather than a grey capsule behind
    /// it: over a near-white canvas pure glass on glass is invisible, and this
    /// is the darkening the material itself would pick up from content beneath.
    private var selectionGlass: some View {
        Capsule()
            .fill(Theme.ink.opacity(0.05))
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("selection", in: glass)
    }

    /// Tinted glass when current, rather than a flat black disc — it stays a
    /// lens over whatever is scrolling beneath it either way.
    private var profileCircle: some View {
        let isSelected = selection == .profile

        return Button {
            onSelect(.profile)
        } label: {
            Image(systemName: isSelected ? "person.fill" : "person")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: RootTabBar.barHeight, height: RootTabBar.barHeight)
                .contentShape(.circle)
        }
        .buttonStyle(TabPressStyle(reduceMotion: reduceMotion))
        .glassEffect(
            isSelected ? .regular.tint(Theme.ink).interactive() : .regular.interactive(),
            in: .circle
        )
        .glassEffectID("profile", in: glass)
        .accessibilityLabel("Profile")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Pre-26 and Reduce Transparency

/// The same bar without the material: blurred on iOS 18, fully opaque for
/// anyone who has asked for reduced transparency. The selection still travels —
/// it just slides instead of morphing, because nothing here is glass to morph.
private struct MaterialTabBar: View {
    @Binding var selection: RootTab
    let reduceMotion: Bool
    let isOpaque: Bool
    let onSelect: (RootTab) -> Void

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: RootTabBar.gap) {
            HStack(spacing: 2) {
                ForEach(RootTab.capsuleTabs, id: \.self) { tab in
                    Button {
                        onSelect(tab)
                    } label: {
                        TabItemLabel(tab: tab, isSelected: selection == tab, reduceMotion: reduceMotion)
                            .background {
                                if selection == tab {
                                    Capsule()
                                        .fill(Theme.ink.opacity(0.07))
                                        .matchedGeometryEffect(id: "selection", in: highlight)
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(TabPressStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: RootTabBar.barHeight)
            .background(surface, in: .capsule)
            .overlay { Capsule().strokeBorder(edge, lineWidth: 1) }
            .shadow(color: .black.opacity(isOpaque ? 0.10 : 0.12), radius: 14, y: 5)

            profileCircle
        }
    }

    private var profileCircle: some View {
        let isSelected = selection == .profile

        return Button {
            onSelect(.profile)
        } label: {
            Image(systemName: isSelected ? "person.fill" : "person")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: RootTabBar.barHeight, height: RootTabBar.barHeight)
                .background {
                    if isSelected { Circle().fill(Theme.ink) }
                }
                .contentShape(.circle)
        }
        .buttonStyle(TabPressStyle(reduceMotion: reduceMotion))
        .background(surface, in: .circle)
        .overlay { Circle().strokeBorder(edge, lineWidth: 1) }
        .shadow(color: .black.opacity(isOpaque ? 0.10 : 0.12), radius: 14, y: 5)
        .accessibilityLabel("Profile")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Type-erased because the two branches are different shape styles; a
    /// `@ViewBuilder` cannot produce a `ShapeStyle`.
    private var surface: AnyShapeStyle {
        isOpaque ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(.ultraThinMaterial)
    }

    private var edge: Color {
        isOpaque ? Theme.border : Color.white.opacity(0.55)
    }
}

// MARK: - Bar

/// The floating tab bar.
///
/// Hand-drawn rather than the system `TabView` bar for one reason: the profile
/// control has to sit *outside* the capsule as its own circle, which the system
/// bar cannot express. Everything the system bar would have given us is kept —
/// real Liquid Glass with a morphing selection, the press-then-select haptic
/// pair, Reduce Transparency and Reduce Motion, and correct safe areas, because
/// the bar is installed as a bottom safe-area inset so content scrolls beneath
/// the material and actually has something to refract.
struct RootTabBar: View {
    @Binding var selection: RootTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Matches the system bar closely enough that nothing shifts vertically
    /// when the screen behind it changes.
    static let barHeight: CGFloat = 58
    static let itemHeight: CGFloat = 46
    static let gap: CGFloat = 12

    var body: some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency {
                LiquidGlassBar(selection: $selection, reduceMotion: reduceMotion, onSelect: select)
            } else {
                MaterialTabBar(
                    selection: $selection,
                    reduceMotion: reduceMotion,
                    isOpaque: reduceTransparency,
                    onSelect: select
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .task { Haptics.preparePress() }
    }

    private func select(_ tab: RootTab) {
        // Silent when you tap the tab you are already on: the press haptic has
        // already acknowledged the touch, and confirming a change that did not
        // happen is just noise.
        guard tab != selection else { return }
        Haptics.selection()
        withAnimation(reduceMotion ? TabMotion.morphReduced : TabMotion.morph) {
            selection = tab
        }
    }
}

#Preview("Tab bar") {
    @Previewable @State var selection: RootTab = .home

    return ZStack(alignment: .bottom) {
        Theme.canvas.ignoresSafeArea()
        RootTabBar(selection: $selection)
    }
}
