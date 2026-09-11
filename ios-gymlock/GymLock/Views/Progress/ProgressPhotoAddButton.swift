import SwiftUI

/// Which source the user picked from the Add Photo menu.
///
/// A request rather than a boolean per source: the card raises one of these and
/// the importer decides how to satisfy it, so there is still exactly one route
/// into the store.
enum ProgressPhotoSourceChoice: String, Identifiable, Hashable {
    case camera
    case library
    case files

    var id: String { rawValue }
}

/// The Add Photo control: a glass bubble that opens the system menu.
///
/// This is a `Menu`, not a button that raises a sheet, and that is the whole
/// point. On iOS 26 the system grows the menu out of the button in Liquid
/// Glass — the bubble stretches into the floating panel and collapses back
/// into it on dismissal. Hand-rolling that morph would mean rebuilding
/// dismissal, off-screen flipping, keyboard control and VoiceOver ordering,
/// and it would still drift from the platform the next time Apple retunes it.
struct ProgressPhotoAddButton: View {
    @Binding var pendingSource: ProgressPhotoSourceChoice?
    let isBusy: Bool
    /// Whether a camera exists; the option is hidden rather than shown broken.
    let hasCamera: Bool

    var body: some View {
        Menu {
            if hasCamera {
                Button {
                    pendingSource = .camera
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button {
                pendingSource = .library
            } label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                pendingSource = .files
            } label: {
                Label("Choose from Files", systemImage: "folder")
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add Photo")
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .menuStyle(.button)
        .adaptiveGlassMenuButton(isBusy: isBusy)
        .disabled(isBusy)
        .accessibilityLabel("Add progress photo")
        .accessibilityHint("Choose Camera, Photos, or Files.")
    }
}

// MARK: - Bubble

private extension View {
    /// Native glass on iOS 26, a hand-built bubble everywhere else.
    ///
    /// The native `.glass` style is used rather than a hand-applied material
    /// because the bubble-to-menu morph is the system's, not ours: iOS grows
    /// the panel out of the glass control and collapses it back in. Painting
    /// the material on manually gets the look but forfeits the transition,
    /// which is the part worth having.
    @ViewBuilder
    func adaptiveGlassMenuButton(isBusy: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Theme.ink)
                .opacity(isBusy ? 0.55 : 1)
        } else {
            buttonStyle(BubbleButtonStyle(isBusy: isBusy))
        }
    }
}

/// Pre-iOS 26 stand-in: a frosted capsule that squishes under the finger and
/// releases with a little bounce, so the control still feels soft rather than
/// like a flat rectangle that happens to open a menu.
private struct BubbleButtonStyle: ButtonStyle {
    let isBusy: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            // Padding before the material, so it fills the whole control
            // instead of leaving a gap around the text.
            .padding(.horizontal, 16)
            // Clears the 44pt minimum target without a hit-test hack.
            .frame(height: 44)
            .background { bubble }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(isBusy ? 0.55 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.28, dampingFraction: 0.58),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                // On the way down, so the bubble answers the finger rather
                // than the menu that follows it. Read from the style's own
                // press state rather than a tap gesture, which would compete
                // with the menu for the same touch.
                if isPressed { Haptics.soft() }
            }
    }

    @ViewBuilder
    private var bubble: some View {
        if reduceTransparency {
            // Opaque by request: no blur, full contrast.
            Capsule()
                .fill(Theme.surfaceMuted)
                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1) }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
    }
}

#Preview("Add button") {
    VStack(spacing: 20) {
        ProgressPhotoAddButton(pendingSource: .constant(nil), isBusy: false, hasCamera: true)
        ProgressPhotoAddButton(pendingSource: .constant(nil), isBusy: true, hasCamera: true)
        ProgressPhotoAddButton(pendingSource: .constant(nil), isBusy: false, hasCamera: false)
    }
    .padding(40)
    .background(Theme.surface)
}
