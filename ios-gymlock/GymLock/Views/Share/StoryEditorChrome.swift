import SwiftUI

/// The controls that float over the editor: close, the format toggle, the
/// frame rail, the share bar and the toast.
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

/// One glass capsule with a sliding white selection. The editor's only
/// segmented control: `Story · Post` at the top, `All · Available · Locked`
/// in the All Frames sheet.
struct GlassSegmentedControl<Option: Hashable & Identifiable>: View {
    let options: [Option]
    let selected: Option
    let title: (Option) -> String
    var accessibilityLabel: ((Option) -> String)? = nil
    let onSelect: (Option) -> Void

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { candidate in
                let isSelected = candidate == selected
                Button {
                    onSelect(candidate)
                } label: {
                    Text(title(candidate))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : .white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.white)
                                    .matchedGeometryEffect(id: "segment", in: selection)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel?(candidate) ?? title(candidate))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .editorGlass(in: .capsule, isInteractive: false)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selected)
    }
}

/// `Story · Post`.
struct FormatToggle: View {
    let format: StoryFormat
    let onSelect: (StoryFormat) -> Void

    var body: some View {
        GlassSegmentedControl(
            options: StoryFormat.allCases,
            selected: format,
            title: { $0.title.lowercased() },
            accessibilityLabel: { $0.accessibilityLabel },
            onSelect: onSelect
        )
    }
}

// MARK: - Frame rail

/// The frames under the canvas, as live miniatures of the user's own photo.
///
/// Each cell is the same `StoryCanvasView` the big canvas and the export
/// draw, at 112 points wide, so choosing a frame is recognising a finished
/// result rather than reading a name. Available frames first, then at most
/// two locked ones dimmed with the result still visible beneath, then the
/// All Frames cell. One glass tray around all of it; the cells carry no
/// glass of their own.
struct FramePreviewRail: View {
    @Bindable var model: StoryEditorModel
    /// Cell width; 112 normally, 96 on compact heights so the canvas keeps
    /// enough of the screen.
    let cellWidth: CGFloat
    let onSelect: (ShareFrame) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Stable scroll identity for the trailing cell.
    private static let allFramesID = "all-frames"
    static let trayInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    /// Reserved for the title so an accessibility-size wrap does not move the
    /// cells.
    static let titleHeight: CGFloat = 34

    private var cellHeight: CGFloat { (cellWidth / model.format.ratio).rounded() }

    /// The rail's full height for a given cell width, so the editor can
    /// budget the canvas area before the rail is measured.
    static func height(cellWidth: CGFloat, format: StoryFormat) -> CGFloat {
        (cellWidth / format.ratio).rounded() + 6 + titleHeight + trayInsets.top + trayInsets.bottom
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(model.frames) { frame in
                        availableCell(frame)
                            .id(frame)
                    }
                    ForEach(model.lockedForRail, id: \.frame) { entry in
                        lockedCell(entry.frame, lock: entry.lock)
                            .id(entry.frame)
                    }
                    allFramesCell
                        .id(Self.allFramesID)
                }
                .padding(.horizontal, 14)
                .scrollTargetLayout()
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
            .onScrollPhaseChange { _, phase in
                if phase != .idle { model.dismissLockExplanation() }
            }
            .onChange(of: model.frame) { _, frame in
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
                    proxy.scrollTo(frame, anchor: .center)
                }
            }
        }
        .padding(Self.trayInsets)
        .modifier(RailTray())
        .overlay(alignment: .top) { tooltip }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frames")
    }

    // MARK: Cells

    private func availableCell(_ frame: ShareFrame) -> some View {
        let isSelected = frame == model.frame
        return Button {
            onSelect(frame)
        } label: {
            VStack(spacing: 6) {
                thumbnail(frame, isLocked: false)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Theme.accent, lineWidth: 2)
                                .padding(1)
                        }
                    }
                    .opacity(isSelected ? 1 : 0.82)
                    .scaleEffect(isSelected && !reduceMotion ? 1.04 : 1)
                cellTitle(frame.title, color: isSelected ? .white : .white.opacity(0.7), isBold: isSelected)
            }
            .frame(width: cellWidth)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(selectionAnimation, value: isSelected)
        .accessibilityLabel("\(frame.title) frame")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func lockedCell(_ frame: ShareFrame, lock: FrameLock) -> some View {
        Button {
            if model.explainedLock == frame {
                model.dismissLockExplanation()
            } else {
                model.explainLock(on: frame)
            }
        } label: {
            VStack(spacing: 6) {
                thumbnail(frame, isLocked: true)
                    .modifier(LockedTreatment())
                cellTitle(frame.title, color: .white.opacity(0.5), isBold: false)
            }
            .frame(width: cellWidth)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(frame.title) frame, locked")
        .accessibilityHint([lock.requirement, lock.progress].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    private var allFramesCell: some View {
        Button {
            Haptics.tap()
            model.dismissLockExplanation()
            model.isShowingAllFrames = true
        } label: {
            VStack(spacing: 6) {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 22, weight: .medium))
                    Text("All frames")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: cellWidth, height: cellHeight)
                .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
                cellTitle("All", color: .white.opacity(0.7), isBold: false)
            }
            .frame(width: cellWidth)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All frames")
        .accessibilityHint("Browse every frame")
    }

    /// The miniature. Same view, same layouts, same image as the export.
    private func thumbnail(_ frame: ShareFrame, isLocked: Bool) -> some View {
        FrameThumbnail(
            model: model,
            frame: frame,
            isLocked: isLocked,
            size: CGSize(width: cellWidth, height: cellHeight),
            cornerRadius: 12
        )
    }

    private func cellTitle(_ text: String, color: Color, isBold: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: isBold ? .bold : .semibold))
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(height: Self.titleHeight, alignment: .top)
    }

    // MARK: Tooltip

    /// Why a frame is locked, above the rail. Positioned over the rail rather
    /// than anchored to a scrolling cell so it stays legible at the edges.
    @ViewBuilder
    private var tooltip: some View {
        if let frame = model.explainedLock, let lock = model.state(of: frame).lock {
            VStack(spacing: 3) {
                Text(lock.requirement)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let progress = lock.progress {
                    Text(progress)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .editorGlass(in: .rect(cornerRadius: 12), isInteractive: false)
            .padding(.horizontal, 20)
            .offset(y: -26)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .allowsHitTesting(false)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.3, dampingFraction: 0.86)
    }
}

/// The one glass tray around the rail: clear glass on iOS 26, material
/// below, opaque under Reduce Transparency.
private struct RailTray: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24)
        if reduceTransparency {
            content
                .background(Color.white.opacity(0.06), in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
        }
    }
}

/// A live miniature of one frame over the user's own photo.
///
/// Not a bitmap: it is `StoryCanvasView` given a small size, drawing the
/// same decoded image the big canvas holds. If a thumbnail is wrong, the
/// export is wrong in the same way, which is the property worth having.
struct FrameThumbnail: View {
    let model: StoryEditorModel
    let frame: ShareFrame
    let isLocked: Bool
    let size: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        StoryCanvasView(
            context: model.context,
            frame: frame,
            format: model.format,
            assets: model.assets,
            transform: model.transform,
            layouts: model.layouts(for: frame),
            canvasSize: size,
            isAnimated: false,
            isLockedPreview: isLocked
        )
        .clipShape(.rect(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }
}

/// Dimmed and desaturated with a lock over it. The frame stays visible
/// underneath: the user must see what they would get.
struct LockedTreatment: ViewModifier {
    var symbolSize: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .saturation(0.15)
            .opacity(0.45)
            .overlay { Color.black.opacity(0.3) }
            .overlay {
                Image(systemName: "lock.fill")
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
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
