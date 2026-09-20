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

    /// The three destinations that live inside the glass capsule, in the order
    /// they sit on the track. Order matters here — the sliding selection maps a
    /// finger position onto this array.
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

/// The track's own coordinate space. Declared at file scope because a generic
/// type cannot hold a static stored property.
private let tabTrackSpace = "RootTabTrack"

// MARK: - Motion

/// The bar's motion language, in one place so the selection, the press and the
/// screen behind them can never disagree about how fast the bar is.
private enum TabMotion {
    /// The selection settling onto a tab after a tap or after the finger lifts.
    ///
    /// Under-damped on purpose. Liquid Glass reads as a material with mass — it
    /// arrives, overshoots very slightly and settles. A critically damped curve
    /// here is what made the old bar feel like a web control.
    static let settle: Animation = .spring(response: 0.36, dampingFraction: 0.7)

    /// The selection chasing a finger that is still down.
    ///
    /// Fast, but deliberately not instant: the tiny lag is what makes the blob
    /// feel like liquid being dragged rather than a rectangle glued to a touch
    /// point. `interactiveSpring` is retargeted every frame without restarting.
    static let track: Animation = .interactiveSpring(response: 0.16, dampingFraction: 0.86)

    /// The elongation and re-forming of the blob as it travels.
    static let surge: Animation = .spring(response: 0.2, dampingFraction: 0.75)

    /// Same jobs, no bounce and shorter, for Reduce Motion.
    static let reduced: Animation = .easeInOut(duration: 0.2)

    /// The give under a finger.
    static let press: Animation = .spring(response: 0.22, dampingFraction: 0.65)
}

// MARK: - Item contents

/// Icon and label. Knows nothing about glass or gestures — both bar
/// implementations draw the same contents so they can never drift apart.
private struct TabItemLabel: View {
    let tab: RootTab
    let isSelected: Bool
    let isPressed: Bool
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
        .scaleEffect(isPressed && !reduceMotion ? 0.9 : 1)
        .animation(TabMotion.press, value: isPressed)
        .contentShape(.capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .onChange(of: isSelected) { _, selected in
            guard selected, !reduceMotion else { return }
            bounce += 1
        }
    }
}

// MARK: - The sliding track

/// The three capsule tabs and the selection blob that travels between them.
///
/// This is the part that makes the bar feel like a material instead of three
/// buttons. One gesture owns the whole track:
///
/// - Touch down gives the soft give of glass accepting a press, and nothing
///   moves yet, so a tap still reads as a tap.
/// - Past a few points of travel the gesture becomes a slide: the blob leaves
///   its tab, chases the finger with a short spring so it trails slightly like
///   liquid, stretches with the speed of the drag, and the destination changes
///   live as you cross each tab — with a tick per crossing.
/// - Releasing settles the blob onto the tab under the finger. Releasing
///   without sliding glides it there from wherever it was.
///
/// Both the glass bar and the fallback bar use this, so sliding is not a
/// feature that quietly disappears on iOS 18 or with Reduce Transparency; only
/// the blob's material differs.
private struct TabTrack<Bubble: View>: View {
    let selection: RootTab
    let reduceMotion: Bool
    let onSelect: (RootTab) -> Void
    @ViewBuilder var bubble: () -> Bubble

    @State private var trackWidth: CGFloat = 0
    /// Where the finger is, in track space. `nil` whenever nothing is sliding,
    /// which is also what tells the blob to go home to its tab.
    @State private var fingerX: CGFloat?
    /// Where the finger first landed, and therefore which tab a tap belongs to.
    @State private var touchDownX: CGFloat?
    @State private var isSliding = false
    @State private var pressedTab: RootTab?
    /// Horizontal scale of the blob: 1 at rest, higher while it is moving fast.
    @State private var stretch: CGFloat = 1

    private var itemWidth: CGFloat {
        guard trackWidth > 0 else { return 0 }
        return trackWidth / CGFloat(RootTab.capsuleTabs.count)
    }

    private var bubbleWidth: CGFloat { max(itemWidth - 4, 0) }

    /// True while Profile is current — the blob has no home on this track then.
    private var isParked: Bool { !RootTab.capsuleTabs.contains(selection) }

    var body: some View {
        ZStack(alignment: .leading) {
            bubbleLayer
            itemsLayer
        }
        .frame(height: RootTabBar.barHeight)
        .coordinateSpace(.named(tabTrackSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trackWidth = $0 }
        .gesture(trackGesture)
    }

    // MARK: Layers

    private var bubbleLayer: some View {
        bubble()
            .frame(width: bubbleWidth, height: RootTabBar.itemHeight)
            // Stretched along travel and thinned across it, so the blob conserves
            // its bulk the way a liquid would instead of simply getting bigger.
            .scaleEffect(x: stretch, y: 1 - (stretch - 1) * 0.45, anchor: .center)
            .offset(x: bubbleX - bubbleWidth / 2)
            // Absorbed by the Profile circle rather than switched off: it shrinks
            // away at the end of the track it was last travelling toward.
            .scaleEffect(isParked ? 0.55 : 1)
            .opacity(isParked ? 0 : 1)
            .animation(positionAnimation, value: bubbleX)
            .animation(reduceMotion ? TabMotion.reduced : TabMotion.surge, value: stretch)
            .animation(reduceMotion ? TabMotion.reduced : TabMotion.settle, value: isParked)
            .allowsHitTesting(false)
    }

    private var itemsLayer: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.capsuleTabs, id: \.self) { tab in
                TabItemLabel(
                    tab: tab,
                    isSelected: selection == tab,
                    isPressed: pressedTab == tab,
                    reduceMotion: reduceMotion
                )
                .accessibilityAction { onSelect(tab) }
            }
        }
    }

    // MARK: Position

    /// Where the blob is drawn: under the finger while sliding, otherwise
    /// centred on its tab.
    private var bubbleX: CGFloat {
        guard let fingerX else { return restingX }
        return rubberBanded(fingerX)
    }

    private var restingX: CGFloat {
        guard let index = RootTab.capsuleTabs.firstIndex(of: selection) else {
            // Profile: park at the end nearest the circle so the blob looks like
            // it left in that direction.
            return trackWidth - itemWidth / 2
        }
        return itemWidth * (CGFloat(index) + 0.5)
    }

    private var positionAnimation: Animation {
        if reduceMotion { return TabMotion.reduced }
        return isSliding ? TabMotion.track : TabMotion.settle
    }

    /// Past the first and last tab the blob keeps moving, but with sharply
    /// diminishing returns — the resistance of a material being stretched
    /// rather than a hard stop.
    private func rubberBanded(_ x: CGFloat) -> CGFloat {
        let first = itemWidth / 2
        let last = trackWidth - itemWidth / 2
        if x < first { return first - give(first - x) }
        if x > last { return last + give(x - last) }
        return x
    }

    private func give(_ distance: CGFloat) -> CGFloat {
        14 * (1 - exp(-distance / 40))
    }

    private func tab(at x: CGFloat) -> RootTab {
        guard itemWidth > 0 else { return RootTab.capsuleTabs[0] }
        let raw = Int((x / itemWidth).rounded(.down))
        let index = min(max(raw, 0), RootTab.capsuleTabs.count - 1)
        return RootTab.capsuleTabs[index]
    }

    // MARK: Gesture

    private var trackGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(tabTrackSpace))
            .onChanged { value in
                if touchDownX == nil {
                    touchDownX = value.location.x
                    pressedTab = tab(at: value.location.x)
                    // The give of the material, felt the instant the finger
                    // lands — including on the tab you are already on.
                    Haptics.press()
                }

                // A few points of slack keeps a tap a tap. Without it the blob
                // would teleport under the finger before the finger had said
                // anything, and tapping a far tab would never glide.
                if !isSliding, abs(value.translation.width) > 6 {
                    isSliding = true
                    pressedTab = nil
                }

                guard isSliding else {
                    // Still a press: track which item the finger is over so the
                    // squish follows it if the finger slides a hair.
                    pressedTab = tab(at: value.location.x)
                    return
                }

                fingerX = value.location.x
                stretch = reduceMotion ? 1 : liquidStretch(for: value.velocity.width)
                onSelect(tab(at: rubberBanded(value.location.x)))
            }
            .onEnded { value in
                let landing = tab(at: rubberBanded(value.location.x))
                let wasSliding = isSliding
                let origin = bubbleX

                isSliding = false
                fingerX = nil
                touchDownX = nil
                pressedTab = nil

                onSelect(landing)

                guard !reduceMotion else {
                    stretch = 1
                    return
                }

                if wasSliding {
                    // Let go mid-flight: the blob keeps a little of the drag's
                    // speed as it re-forms on its tab.
                    stretch = liquidStretch(for: value.velocity.width * 0.5)
                    relaxStretch()
                } else {
                    surge(distance: abs(restingX(for: landing) - origin))
                }
            }
    }

    private func restingX(for tab: RootTab) -> CGFloat {
        guard let index = RootTab.capsuleTabs.firstIndex(of: tab) else { return restingX }
        return itemWidth * (CGFloat(index) + 0.5)
    }

    private func liquidStretch(for velocity: CGFloat) -> CGFloat {
        1 + min(abs(velocity) / 3600, 0.26)
    }

    /// A tapped jump has no finger velocity to borrow, so the elongation is
    /// derived from how far the blob is about to travel and then released —
    /// it leaves long and lands round.
    private func surge(distance: CGFloat) {
        guard distance > 1, itemWidth > 0 else { return }
        stretch = 1 + min(distance / (itemWidth * 4), 0.3)
        relaxStretch()
    }

    private func relaxStretch() {
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            stretch = 1
        }
    }
}

// MARK: - iOS 26 Liquid Glass

/// The real thing: one `GlassEffectContainer` holding the bar's glass, with a
/// selection blob that is itself glass moving inside it.
///
/// Container spacing is kept below the gap to the Profile circle so the two
/// shapes stay separate at rest, while the blob — which overlaps the capsule
/// completely — fuses with it and reads as one body of liquid moving inside
/// another. `.interactive()` lets that glass flex under a finger rather than
/// only the contents scaling.
@available(iOS 26.0, *)
private struct LiquidGlassBar: View {
    let selection: RootTab
    let reduceMotion: Bool
    let onSelect: (RootTab) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: RootTabBar.gap) {
                TabTrack(selection: selection, reduceMotion: reduceMotion, onSelect: onSelect) {
                    // A faint ink wash *inside* the glass rather than a grey
                    // capsule behind it: over a near-white canvas glass on glass
                    // is invisible, and this is the darkening the material would
                    // pick up from content beneath.
                    Capsule()
                        .fill(Theme.ink.opacity(0.07))
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.horizontal, 6)
                .glassEffect(.regular, in: .capsule)

                profileCircle
            }
        }
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
        .buttonStyle(CirclePressStyle(reduceMotion: reduceMotion))
        .glassEffect(
            isSelected ? .regular.tint(Theme.ink).interactive() : .regular.interactive(),
            in: .circle
        )
        .accessibilityLabel("Profile")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Pre-26 and Reduce Transparency

/// The same bar, and the same sliding selection, without the material: blurred
/// on iOS 18, fully opaque for anyone who has asked for reduced transparency.
private struct MaterialTabBar: View {
    let selection: RootTab
    let reduceMotion: Bool
    let isOpaque: Bool
    let onSelect: (RootTab) -> Void

    var body: some View {
        HStack(spacing: RootTabBar.gap) {
            TabTrack(selection: selection, reduceMotion: reduceMotion, onSelect: onSelect) {
                Capsule().fill(Theme.ink.opacity(0.08))
            }
            .padding(.horizontal, 6)
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
        .buttonStyle(CirclePressStyle(reduceMotion: reduceMotion))
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

// MARK: - Press behaviour for the detached circle

/// Squish on finger-down with the soft haptic of a material yielding.
///
/// The track has its own press handling inside the gesture; this is only for
/// the Profile circle, which is a real button because it is not on the track.
private struct CirclePressStyle: ButtonStyle {
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

// MARK: - Bar

/// The floating tab bar.
///
/// Hand-drawn rather than the system `TabView` bar for one reason: the profile
/// control has to sit *outside* the capsule as its own circle, which the system
/// bar cannot express. Everything the system bar would have given us is kept —
/// real Liquid Glass, a selection you can drag as well as tap, the
/// press-then-select haptic pair, Reduce Transparency and Reduce Motion, and
/// correct safe areas, because the bar is installed as a bottom safe-area inset
/// so content scrolls beneath the material and has something to refract.
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
                LiquidGlassBar(selection: selection, reduceMotion: reduceMotion, onSelect: select)
            } else {
                MaterialTabBar(
                    selection: selection,
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

    /// Commits a destination. Called on tap, and on every tab the finger
    /// crosses during a slide.
    private func select(_ tab: RootTab) {
        // Silent when the destination has not changed: the press haptic has
        // already acknowledged the touch, and confirming a change that did not
        // happen is just noise — during a slide that would be a tick per frame.
        guard tab != selection else { return }
        Haptics.selection()
        withAnimation(reduceMotion ? TabMotion.reduced : TabMotion.settle) {
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
