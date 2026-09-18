import SwiftUI

/// The controls that float over the editor: close, the format toggle, the
/// frame pills, the share bar and the toast.
///
/// All of it is chrome, and all of it is glass — the one place in the app,
/// alongside the camera, where glass sits over media. None of it is exported.

// MARK: - Glass over the editor

/// Dark-editor glass: clear over the black backdrop on iOS 26, material
/// below, opaque under Reduce Transparency.
private struct EditorGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var isInteractive = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(white: 0.16), in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            if isInteractive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1) }
        }
    }
}

extension View {
    func editorGlass<S: InsettableShape>(in shape: S, isInteractive: Bool = true) -> some View {
        modifier(EditorGlass(shape: shape, isInteractive: isInteractive))
    }
}

// MARK: - Top row

struct EditorCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .editorGlass(in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Story editor")
    }
}

/// `Story · Post`, as one glass capsule with a sliding selection.
struct FormatToggle: View {
    let format: StoryFormat
    let onSelect: (StoryFormat) -> Void

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StoryFormat.allCases) { candidate in
                let isSelected = candidate == format
                Button {
                    onSelect(candidate)
                } label: {
                    Text(candidate.title.lowercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : .white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.white)
                                    .matchedGeometryEffect(id: "format", in: selection)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.accessibilityLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .editorGlass(in: .capsule, isInteractive: false)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: format)
    }
}

// MARK: - Frame pills

/// The frame names under the canvas.
///
/// On iOS 26 the pills live in one `GlassEffectContainer` and the selected
/// one carries a `glassEffectID`, so the selection morphs from pill to pill
/// as the system does it. Below, a filled capsule slides with
/// `matchedGeometryEffect`, which is the same idea drawn by hand.
struct FramePillStrip: View {
    let frames: [ShareFrame]
    let selected: ShareFrame
    let onSelect: (ShareFrame) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                pills
                    .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: selected) { _, frame in
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
                    proxy.scrollTo(frame, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var pills: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(frames) { frame in
                        pill(frame)
                            .glassEffect(
                                frame == selected ? .regular.tint(.white).interactive() : .regular.interactive(),
                                in: .capsule
                            )
                            .glassEffectID(frame == selected ? "selected" : frame.rawValue, in: namespace)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(frames) { frame in
                    pill(frame)
                        .background {
                            if frame == selected {
                                Capsule()
                                    .fill(.white)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: selected)
        }
    }

    private func pill(_ frame: ShareFrame) -> some View {
        let isSelected = frame == selected
        return Button {
            onSelect(frame)
        } label: {
            Text(frame.title.lowercased())
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 15)
                .frame(height: 36)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .id(frame)
        .accessibilityLabel("\(frame.title) frame")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Share bar

/// Sticker on the left, Share on the right, Instagram between them only
/// once it is configured.
struct ShareBar: View {
    let isRendering: Bool
    let showsInstagram: Bool
    let onSticker: () -> Void
    let onInstagram: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onSticker()
            } label: {
                Label("sticker", systemImage: "square.on.square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .editorGlass(in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isRendering)
            .accessibilityLabel("Copy sticker to clipboard")

            if showsInstagram {
                Button {
                    onInstagram()
                } label: {
                    Image(systemName: "camera.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .editorGlass(in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(isRendering)
                .accessibilityLabel("Share to Instagram Story")
            }

            Spacer(minLength: 0)

            shareButton
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        let label = HStack(spacing: 8) {
            if isRendering {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .offset(y: -1)
            }
            Text("share")
                .font(.system(size: 17, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26)
        .frame(height: 50)

        if #available(iOS 26.0, *) {
            Button(action: onShare) { label }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
                .disabled(isRendering)
                .accessibilityLabel("Share progress Story")
        } else {
            Button(action: onShare) {
                label.background(Theme.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isRendering)
            .accessibilityLabel("Share progress Story")
        }
    }
}

// MARK: - Toast

/// A glass capsule that says one short thing and goes.
struct EditorToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .editorGlass(in: .capsule, isInteractive: false)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
