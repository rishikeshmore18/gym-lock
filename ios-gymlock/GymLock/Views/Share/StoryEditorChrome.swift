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

/// The frame picker, floating over the bottom of the photo the way the
/// filter row does in Instagram and Snapchat.
///
/// A single row of small circles, no tray, no labels. Each circle is the
/// same `StoryCanvasView` the big canvas and the export draw, cropped to its
/// bottom band so the statement is what shows. The selected frame is a
/// little larger with a white ring, and its name sits as one small caption
/// above the row. Available frames first, then at most two locked ones
/// dimmed, then the All Frames circle.
///
/// It lives as an overlay on the canvas rather than in the column below
/// it, so the photo keeps the screen; the row is `height` tall in total.
struct FramePreviewRail: View {
    @Bindable var model: StoryEditorModel
    let onSelect: (ShareFrame) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Stable scroll identity for the trailing cell.
    private static let allFramesID = "all-frames"
    private static let circle: CGFloat = 50
    private static let selectedCircle: CGFloat = 62
    private static let ring: CGFloat = 2.5
    /// Every cell reserves the selected size so selection never reflows
    /// its neighbours; only the circle inside grows.
    private static let slot: CGFloat = selectedCircle + ring * 2 + 4
    private static let captionHeight: CGFloat = 20

    /// Row plus caption, for anyone budgeting around it.
    static let height: CGFloat = slot + captionHeight + 4

    var body: some View {
        VStack(spacing: 4) {
            caption
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
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
                    .padding(.horizontal, 16)
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
            .frame(height: Self.slot)
        }
        .overlay(alignment: .top) { tooltip }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frames")
    }

    // MARK: Caption

    /// The selected frame's name, the way Instagram names the filter above
    /// the row. Text shadow rather than a pill: it reads over any photo
    /// without adding a box.
    private var caption: some View {
        Text(model.hasFrames ? model.frame.title : "")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
            .frame(height: Self.captionHeight)
            .contentTransition(.opacity)
            .animation(selectionAnimation, value: model.frame)
            .accessibilityHidden(true)
    }

    // MARK: Cells

    private func availableCell(_ frame: ShareFrame) -> some View {
        let isSelected = frame == model.frame
        let diameter = isSelected ? Self.selectedCircle : Self.circle
        return Button {
            onSelect(frame)
        } label: {
            thumbnail(frame, isLocked: false, diameter: diameter)
                .overlay {
                    // White ring with a hairline of photo showing between
                    // ring and image, as on Instagram's selected filter.
                    if isSelected {
                        Circle()
                            .strokeBorder(.white, lineWidth: Self.ring)
                            .padding(-(Self.ring + 2))
                    }
                }
                .frame(width: Self.slot, height: Self.slot)
                .contentShape(.circle)
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
            thumbnail(frame, isLocked: true, diameter: Self.circle)
                .modifier(LockedTreatment(symbolSize: 14))
                .clipShape(.circle)
                .frame(width: Self.slot, height: Self.slot)
                .contentShape(.circle)
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
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Self.circle, height: Self.circle)
                .background(Color.black.opacity(0.35), in: .circle)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5) }
                .frame(width: Self.slot, height: Self.slot)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All frames")
        .accessibilityHint("Browse every frame")
    }

    /// The miniature, cropped to a circle. Same view, same layouts, same
    /// image as the export; the crop is anchored to the bottom band because
    /// that is where the frames differ.
    private func thumbnail(_ frame: ShareFrame, isLocked: Bool, diameter: CGFloat) -> some View {
        FrameThumbnail(
            model: model,
            frame: frame,
            isLocked: isLocked,
            size: CGSize(width: diameter, height: (diameter / model.format.ratio).rounded()),
            cornerRadius: 0
        )
        .frame(width: diameter, height: diameter, alignment: .bottom)
        .clipShape(.circle)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    // MARK: Tooltip

    /// Why a frame is locked, above the row. Positioned over the row rather
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
            .offset(y: -40)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .allowsHitTesting(false)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.3, dampingFraction: 0.86)
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
