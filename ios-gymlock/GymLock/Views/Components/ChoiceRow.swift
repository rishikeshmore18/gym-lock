import SwiftUI

/// The single option control used by every question in the system-building part
/// of onboarding.
///
/// Selection is expressed the same way whether the question takes one answer or
/// several: a coral border, a faint coral wash, and a mark on the right. The
/// mark is the only difference — a circled tick for "one of these" and a square
/// tick for "as many as apply" — which is the same distinction the platform
/// makes and needs no explaining.
struct ChoiceRow: View {
    let label: String
    var icon: String?
    var isSelected: Bool
    var allowsMultiple: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.inkSecondary)
                        .frame(width: 26)
                }

                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                mark
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                isSelected ? Theme.accent.opacity(0.08) : Theme.surface,
                in: .rect(cornerRadius: Theme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        isSelected ? Theme.accent : Theme.border,
                        lineWidth: isSelected ? 1.6 : 1
                    )
            }
        }
        .buttonStyle(PressableRowStyle())
        .animation(Theme.stateChange, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var mark: some View {
        ZStack {
            // Branching on the concrete shape rather than erasing to `AnyShape`:
            // the erased type loses `InsettableShape`, and with it the inward
            // `strokeBorder` that keeps the outline inside the 22pt frame.
            if allowsMultiple {
                markBody(RoundedRectangle(cornerRadius: 6))
            } else {
                markBody(Circle())
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
    }

    /// A filled shape with its own inset border, sized to the mark.
    private func markBody<S: InsettableShape>(_ shape: S) -> some View {
        shape
            .fill(isSelected ? Theme.accent : Color.clear)
            .overlay {
                shape.strokeBorder(
                    isSelected ? Theme.accent : Theme.border,
                    lineWidth: 1.6
                )
            }
            .frame(width: 22, height: 22)
    }
}

/// A restrained press response for full-width rows: the surface dims slightly,
/// with no scaling, matching the CTA's colour-only feedback.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The inline "tell us more" field that opens under an `Other` choice.
///
/// It claims the pager's drag while focused, because otherwise a swipe to
/// dismiss the keyboard would also turn the page.
struct OtherDetailField: View {
    let placeholder: String
    @Binding var text: String
    var isShown: Bool

    @Environment(PagerInteractionLock.self) private var pagerLock: PagerInteractionLock?
    @FocusState private var isFocused: Bool
    @State private var token = UUID().uuidString

    var body: some View {
        Group {
            if isShown {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.accent)
                    .focused($isFocused)
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .onSubmit { isFocused = false }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(Theme.surfaceMuted, in: .rect(cornerRadius: Theme.controlRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .strokeBorder(
                                isFocused ? Theme.accent.opacity(0.6) : Theme.border,
                                lineWidth: 1
                            )
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        )
                    )
            }
        }
        .animation(Theme.settle, value: isShown)
        .animation(Theme.stateChange, value: isFocused)
        .claimsPagerDrag(pagerLock, token: token, isActive: isFocused)
        .onChange(of: isShown) { _, shown in
            if !shown { isFocused = false }
        }
        .onDisappear {
            isFocused = false
            pagerLock?.release(token)
        }
    }
}
