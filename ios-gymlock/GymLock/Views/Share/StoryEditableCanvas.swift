import SwiftUI

/// The canvas as the editor shows it: the photo, the current frame's
/// elements, and every gesture that can touch either.
///
/// Three intents share one surface and are resolved without a mode switch:
///
/// - **Nothing selected.** Two fingers zoom and pan the photo. One finger
///   moving mostly sideways pages between frames — the photo stays still and
///   only the overlay slides. One finger moving mostly up or down pans the
///   photo. Once the photo is zoomed past `PhotoTransform.panTakeoverZoom`,
///   one finger always pans and the pills switch frames.
/// - **An element selected.** One finger drags it, two fingers (or the corner
///   handle) resize it. Tapping empty canvas deselects.
/// - **A tap on an element** selects it.
///
/// Taps are recognised by the same drag gesture that does everything else,
/// by measuring how far the touch travelled before it lifted — a separate tap
/// recogniser would lose every race against a zero-distance drag. The
/// interactive layer is drawn by the same `StoryCanvasView` the renderer
/// uses; what changes here is only the gesture handling and the selection
/// chrome, neither of which is exported.
struct StoryEditableCanvas: View {
    @Bindable var model: StoryEditorModel
    let canvasSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Horizontal paging offset while a finger is down, in points.
    @State private var pageTranslation: CGFloat = 0
    /// Which axis the current one-finger gesture was judged to be on.
    @State private var gestureAxis: Axis?
    /// True while two fingers are down, so the one-finger gesture that the
    /// first finger also started does not page or pan underneath the pinch.
    @State private var isPinching = false
    /// The transform when a pan or pinch began.
    @State private var transformAtStart: PhotoTransform?
    /// The element layout, its normalized size, and the handle's rect when a
    /// drag or pinch on an element began.
    @State private var elementAtStart: StoryElementLayout?
    @State private var elementSizeAtStart: CGSize = .zero
    @State private var handleRectAtStart: CGRect = .zero
    @State private var pinchStartScale: Double = 1

    private var layout: StoryLayout { StoryLayout(format: model.format, canvasSize: canvasSize) }
    private var isPhotoZoomed: Bool { model.transform.zoom >= PhotoTransform.panTakeoverZoom }

    /// Travel, in points, at which a one-finger gesture picks an axis — or,
    /// if it lifts before this, counts as a tap.
    private static let axisThreshold: CGFloat = 12
    /// Travel before a selected element starts to move under the finger, so
    /// a tap does not nudge it by a pixel.
    private static let elementDragThreshold: CGFloat = 3

    /// The frames on screen: the current one, plus the neighbour sliding in.
    private var visibleIndices: [Int] {
        guard pageTranslation != 0, let incoming = incomingIndex else { return [model.index] }
        return [model.index, incoming]
    }

    private var incomingIndex: Int? {
        let next = pageTranslation < 0 ? model.index + 1 : model.index - 1
        return model.frames.indices.contains(next) ? next : nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The photograph never moves during paging.
            StoryCanvasView(
                context: model.context,
                frame: model.frame,
                format: model.format,
                assets: model.assets,
                transform: model.transform,
                layouts: model.currentLayouts,
                canvasSize: canvasSize,
                isAnimated: false,
                layers: [.photo, .band]
            )

            // Keyed by frame index so the overlay that slid in during a drag
            // is the same view after the commit — its entrance has already
            // played and its elements are already measured.
            ForEach(visibleIndices, id: \.self) { index in
                overlay(for: index)
                    .offset(x: overlayOffset(for: index))
                    .opacity(overlayOpacity(for: index))
                    .allowsHitTesting(index == model.index)
            }

            selectionChrome
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipShape(.rect(cornerRadius: 28))
        .contentShape(.rect)
        .gesture(oneFinger)
        .simultaneousGesture(twoFingers)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.frame.title) frame, \(model.index + 1) of \(model.frames.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.select(frameAt: model.index + 1)
            case .decrement: model.select(frameAt: model.index - 1)
            @unknown default: break
            }
        }
    }

    /// The elements of one frame, live-animated in preview.
    private func overlay(for index: Int) -> some View {
        let frame = model.frames[index]
        return StoryCanvasView(
            context: model.context,
            frame: frame,
            format: model.format,
            assets: model.assets,
            transform: model.transform,
            layouts: model.layouts[frame] ?? .defaults(for: frame, format: model.format),
            canvasSize: canvasSize,
            isAnimated: !reduceMotion,
            layers: .elements,
            onElementSize: { kind, size in model.setElementSize(size, for: kind, on: frame) }
        )
    }

    private func overlayOffset(for index: Int) -> CGFloat {
        guard index != model.index else { return pageTranslation }
        return pageTranslation + (pageTranslation < 0 ? canvasSize.width : -canvasSize.width)
    }

    private func overlayOpacity(for index: Int) -> Double {
        let progress = Double(min(abs(pageTranslation) / max(canvasSize.width, 1), 1))
        return index == model.index ? 1 - progress * 0.8 : progress
    }

    // MARK: Selection chrome

    /// The light bounding box, the delete button and the resize handle.
    ///
    /// Drawn over the element rather than around it in the layout, so the
    /// element's own measured frame stays what the export uses.
    @ViewBuilder
    private var selectionChrome: some View {
        if let kind = model.selectedElement, let rect = selectionRect(for: kind) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)

            if kind.isRemovable {
                Button {
                    model.remove(kind)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(.white, in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .offset(x: rect.minX - 22, y: rect.minY - 22)
                .accessibilityLabel("Remove \(kind.accessibilityName)")
            }

            // Corner handle. Dragging it scales about the element's centre;
            // the model clamps to the element's floor, so the handle simply
            // stops rather than snapping when the mark hits its minimum.
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .overlay { Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1) }
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .offset(x: rect.maxX - 22, y: rect.maxY - 22)
                .gesture(handleDrag(for: kind))
                .accessibilityLabel("Resize \(kind.accessibilityName)")
        }
    }

    /// The selected element's drawn rectangle, in canvas points, padded a
    /// little so the box does not touch the glyphs.
    private func selectionRect(for kind: StoryElementKind) -> CGRect? {
        guard let element = model.layout(for: kind), !element.isHidden,
              let size = model.elementSize(kind)
        else { return nil }
        return CGRect(
            origin: layout.point(element.origin),
            size: CGSize(width: layout.x(size.width), height: layout.y(size.height))
        )
        .insetBy(dx: -6, dy: -6)
    }

    private func handleDrag(for kind: StoryElementKind) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if elementAtStart == nil {
                    guard let start = model.layout(for: kind),
                          let size = model.elementSize(kind),
                          let rect = selectionRect(for: kind)
                    else { return }
                    elementAtStart = start
                    elementSizeAtStart = size
                    handleRectAtStart = rect
                    pinchStartScale = start.scale
                }
                guard let start = elementAtStart else { return }

                // Everything measured against the rect at gesture start: the
                // element is scaling about its centre while the finger moves,
                // so the live rect would keep moving the goalposts.
                let rect = handleRectAtStart
                let centre = CGPoint(x: rect.midX, y: rect.midY)
                let startDistance = hypot(rect.maxX - centre.x, rect.maxY - centre.y)
                let now = CGPoint(x: rect.maxX + value.translation.width, y: rect.maxY + value.translation.height)
                let distance = hypot(now.x - centre.x, now.y - centre.y)
                guard startDistance > 0 else { return }

                let proposed = pinchStartScale * Double(distance / startDistance)
                model.update(kind) {
                    $0 = start.scaled(
                        to: proposed,
                        currentSize: elementSizeAtStart,
                        minimumScale: model.minimumScale(for: kind)
                    )
                }
            }
            .onEnded { _ in
                elementAtStart = nil
                model.commitLayouts()
            }
    }

    // MARK: Gestures

    private var oneFinger: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isPinching else { return }

                if let kind = model.selectedElement {
                    dragElement(kind, value: value)
                    return
                }

                if gestureAxis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) >= Self.axisThreshold else { return }
                    // Zoomed in, one finger is always the photo.
                    gestureAxis = (isPhotoZoomed || dy > dx) ? .vertical : .horizontal
                    if gestureAxis == .vertical { transformAtStart = model.transform }
                }

                switch gestureAxis {
                case .horizontal:
                    pageTranslation = rubberBanded(value.translation.width)
                case .vertical:
                    panPhoto(by: value.translation)
                case nil:
                    break
                }
            }
            .onEnded { value in
                let axis = gestureAxis
                gestureAxis = nil

                guard !isPinching else { return }

                let travelled = hypot(value.translation.width, value.translation.height)

                if let kind = model.selectedElement {
                    if travelled < Self.axisThreshold {
                        // A tap, not a drag: put the element back where it was
                        // and treat the touch as a selection change.
                        if let start = elementAtStart { model.update(kind) { $0 = start } }
                        elementAtStart = nil
                        handleTap(at: value.startLocation)
                    } else {
                        elementAtStart = nil
                        model.commitLayouts()
                    }
                    return
                }

                switch axis {
                case .horizontal:
                    finishPaging(value)
                case .vertical:
                    settlePhoto()
                case nil:
                    // Never moved far enough to be a drag.
                    if travelled < Self.axisThreshold { handleTap(at: value.startLocation) }
                }
            }
    }

    private var twoFingers: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    // The first finger may already have started a page or a
                    // pan; a pinch overrides both.
                    if pageTranslation != 0 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { pageTranslation = 0 }
                    }
                    gestureAxis = nil
                }

                if let kind = model.selectedElement {
                    if elementAtStart == nil {
                        guard let start = model.layout(for: kind), let size = model.elementSize(kind) else { return }
                        elementAtStart = start
                        elementSizeAtStart = size
                        pinchStartScale = start.scale
                    }
                    guard let start = elementAtStart else { return }
                    model.update(kind) {
                        $0 = start.scaled(
                            to: pinchStartScale * Double(value.magnification),
                            currentSize: elementSizeAtStart,
                            minimumScale: model.minimumScale(for: kind)
                        )
                    }
                    return
                }

                guard let image = model.assets.photo else { return }
                if transformAtStart == nil { transformAtStart = model.transform }
                guard let start = transformAtStart else { return }
                let anchor = CGPoint(
                    x: value.startAnchor.x * canvasSize.width,
                    y: value.startAnchor.y * canvasSize.height
                )
                model.transform = start.zoomed(
                    to: start.zoom * Double(value.magnification),
                    about: anchor,
                    imageSize: image.size,
                    canvasSize: canvasSize
                )
            }
            .onEnded { _ in
                isPinching = false
                if model.selectedElement != nil {
                    elementAtStart = nil
                    model.commitLayouts()
                } else {
                    settlePhoto()
                }
            }
    }

    // MARK: Element drag

    private func dragElement(_ kind: StoryElementKind, value: DragGesture.Value) {
        if elementAtStart == nil {
            guard let start = model.layout(for: kind), let size = model.elementSize(kind) else { return }
            elementAtStart = start
            elementSizeAtStart = size
        }
        guard let start = elementAtStart,
              hypot(value.translation.width, value.translation.height) >= Self.elementDragThreshold
        else { return }
        let translation = layout.normalized(CGSize(width: value.translation.width, height: value.translation.height))
        model.update(kind) { $0 = start.moved(by: translation, currentSize: elementSizeAtStart) }
    }

    // MARK: Photo pan

    private func panPhoto(by translation: CGSize) {
        guard let image = model.assets.photo, let start = transformAtStart else { return }
        let panned = start.panned(by: translation, imageSize: image.size, canvasSize: canvasSize)
        // Rubber-band past the edge: the user feels the limit rather than
        // hitting a wall.
        let clamped = panned.clamped(imageSize: image.size, canvasSize: canvasSize)
        model.transform = PhotoTransform(
            focalX: clamped.focalX + (panned.focalX - clamped.focalX) * 0.35,
            focalY: clamped.focalY + (panned.focalY - clamped.focalY) * 0.35,
            zoom: panned.zoom
        )
    }

    private func settlePhoto() {
        transformAtStart = nil
        guard let image = model.assets.photo else { return }
        let settled = model.transform.clamped(imageSize: image.size, canvasSize: canvasSize)
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.3, dampingFraction: 0.86)) {
            model.transform = settled
        }
        model.commitTransform()
    }

    // MARK: Paging

    private func rubberBanded(_ translation: CGFloat) -> CGFloat {
        let atStart = model.index == 0 && translation > 0
        let atEnd = model.index == model.frames.count - 1 && translation < 0
        return (atStart || atEnd) ? translation * 0.35 : translation
    }

    private func finishPaging(_ value: DragGesture.Value) {
        let width = canvasSize.width
        let predicted = value.predictedEndTranslation.width
        let velocity = value.velocity.width
        let commits = abs(predicted) > width * 0.35 || abs(velocity) > 500
        let target = pageTranslation < 0 ? model.index + 1 : model.index - 1

        guard commits, model.frames.indices.contains(target) else {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.86)) {
                pageTranslation = 0
            }
            return
        }

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.18)) {
                model.select(frameAt: target)
                pageTranslation = 0
            }
            return
        }

        // Carry the outgoing overlay off, then swap the index with the
        // translation reset in one un-animated transaction: the incoming
        // overlay is already at offset zero, so nothing on screen moves.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            pageTranslation = pageTranslation < 0 ? -width : width
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.select(frameAt: target)
                pageTranslation = 0
            }
        }
    }

    // MARK: Tap

    private func handleTap(at location: CGPoint) {
        // Topmost element under the finger wins; the selection chrome's own
        // controls never reach here because they take their taps first.
        let hit = StoryCanvasView.activeElements(frame: model.frame, context: model.context)
            .reversed()
            .first { kind in
                guard let rect = selectionRect(for: kind) else { return false }
                return rect.insetBy(dx: -6, dy: -6).contains(location)
            }

        if hit != model.selectedElement { Haptics.tap(intensity: 0.6) }
        withAnimation(Theme.stateChange) { model.selectedElement = hit }
    }
}
