import RealityKit
import SwiftUI
import simd

/// The interactive mountain.
///
/// Gestures are attached to this view only, so a pinch inside the viewport
/// explores the world while a tap anywhere else on Home behaves normally. The
/// camera is never handed to RealityKit's own controls — it is driven entirely
/// from `MountainCameraState`, because the label layer above has to agree with
/// the renderer down to the pixel.
struct MountainView: View {
    let spec: MountainWorldSpec
    let pins: [WeekPin]
    var onSelectWeek: (WeekPin) -> Void

    @Environment(MountainSceneController.self) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var camera: MountainCameraState

    /// Live gesture values, kept apart from the committed camera so a cancelled
    /// gesture cannot leave the camera somewhere strange.
    @State private var dragAnchor: MountainCameraState?
    @State private var pinchAnchor: Float?
    @State private var inertia: Task<Void, Never>?
    @State private var viewportSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                sceneLayer(size: proxy.size)

                if scene.phase == .failed {
                    MountainFallbackView(palette: scene.palette)
                } else {
                    atmosphere
                    labelLayer(size: proxy.size)
                }

                if scene.phase == .building || scene.phase == .idle {
                    MountainSkeletonView()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.45), value: scene.phase)
            .onAppear { viewportSize = proxy.size }
            .onChange(of: proxy.size) { _, size in viewportSize = size }
        }
        .contentShape(.rect)
        .gesture(explorationGesture)
        .simultaneousGesture(recenterGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your journey")
        .accessibilityHint("Pinch to zoom, drag to explore.")
    }

    // MARK: - 3D

    private func sceneLayer(size: CGSize) -> some View {
        RealityView { content in
            // Explicitly non-AR: this is a miniature world on a card, not a
            // camera pass-through.
            content.camera = .virtual
            content.add(scene.root)
            scene.apply(cameraState: camera)
        } update: { _ in
            scene.apply(cameraState: camera)
        }
        .opacity(scene.phase == .ready ? 1 : 0)
        .task {
            scene.reduceMotion = reduceMotion
            await scene.build(spec: spec)
            // Frame the user where they actually are, plus a little of the road
            // ahead — never the whole mountain when they are on week ten. Done
            // once per launch: coming back from another tab keeps whatever
            // viewpoint the user left behind.
            guard !scene.hasFramedCamera else { return }
            scene.hasFramedCamera = true
            withAnimation(.easeOut(duration: 0.6)) {
                camera = MountainCameraFraming.initial(for: scene, spec: spec)
            }
        }
        .onChange(of: reduceMotion) { _, value in scene.reduceMotion = value }
        .onChange(of: spec) { _, value in
            Task { await scene.build(spec: value) }
        }
    }

    /// Depth haze and weather wash, drawn over the render but under the labels
    /// so progress can never be fogged out.
    private var atmosphere: some View {
        let palette = scene.palette
        let haze = Color(
            red: Double(palette.hazeColor.x),
            green: Double(palette.hazeColor.y),
            blue: Double(palette.hazeColor.z)
        )

        return LinearGradient(
            colors: [
                haze.opacity(Double(palette.hazeOpacity) * 0.35),
                haze.opacity(Double(palette.hazeOpacity)),
                haze.opacity(Double(palette.hazeOpacity) * 1.25),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.2), value: palette.hazeOpacity)
    }

    // MARK: - Labels

    private func labelLayer(size: CGSize) -> some View {
        // Back-to-front so a nearer checkpoint always wins an overlap, and
        // thinned out when zoomed away so distant weeks never pile into an
        // unreadable stack of chips.
        let visible = projectedPins(in: size)

        return ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.pin.id) { item in
                CheckpointLabel(
                    pin: item.pin,
                    isDark: scene.palette.prefersDarkChrome,
                    scale: item.scale
                ) {
                    onSelectWeek(item.pin)
                }
                .position(item.point.location)
            }
        }
        .allowsHitTesting(true)
    }

    private struct ProjectedPin {
        let pin: WeekPin
        let point: ProjectedPoint
        let scale: CGFloat
    }

    private func projectedPins(in size: CGSize) -> [ProjectedPin] {
        guard scene.phase == .ready else { return [] }

        // Label density follows zoom: wide shots show only the milestones that
        // matter, close shots show every week.
        let zoom = camera.zoomFraction
        let step: Int = zoom > 0.55 ? 1 : (zoom > 0.28 ? 2 : 3)

        var results: [ProjectedPin] = []
        for pin in pins {
            let isAlwaysShown = pin.state == .current || pin.state == .missed
            guard isAlwaysShown || pin.id % step == 0 else { continue }
            guard let anchor = scene.pinAnchors[pin.id] else { continue }
            guard let point = camera.project(anchor + SIMD3<Float>(0, 2.6, 0), in: size) else { continue }

            let margin: CGFloat = 60
            guard point.location.x > -margin, point.location.x < size.width + margin,
                  point.location.y > -margin, point.location.y < size.height + margin
            else { continue }

            // Chips shrink with distance, which is what stops a far mountain's
            // labels from looking the same size as the one underfoot.
            let scale = CGFloat(min(max(1.35 - point.depth / 420, 0.62), 1.0))
            results.append(ProjectedPin(pin: pin, point: point, scale: scale))
        }

        return results.sorted { $0.point.depth > $1.point.depth }
    }

    // MARK: - Gestures

    /// A drag orbits and pans; a pinch dollies. Both are recognised together so
    /// a two-finger gesture does not have to be started perfectly.
    private var explorationGesture: some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 1),
            MagnifyGesture(minimumScaleDelta: 0.005)
        )
        .onChanged { value in
            inertia?.cancel()

            var next = dragAnchor ?? camera
            if dragAnchor == nil { dragAnchor = camera }

            if let drag = value.first {
                let anchor = dragAnchor ?? camera
                // Horizontal drag orbits; vertical drag lifts the eye up the
                // slope. Both are scaled by distance so the world moves the
                // same amount under the finger at every zoom.
                next.yaw = anchor.yaw - Float(drag.translation.width) * 0.0022
                next.pitch = anchor.pitch + Float(drag.translation.height) * 0.0016
                let panScale = anchor.distance * 0.0038
                next.target.x = anchor.target.x - Float(drag.translation.width) * panScale * 0.55
                next.target.y = anchor.target.y + Float(drag.translation.height) * panScale * 0.30
            }

            if let magnify = value.second {
                if pinchAnchor == nil { pinchAnchor = (dragAnchor ?? camera).distance }
                next.distance = (pinchAnchor ?? camera.distance) / Float(magnify.magnification)
            }

            next.clamp()
            camera = next
        }
        .onEnded { value in
            let start = dragAnchor ?? camera
            dragAnchor = nil
            pinchAnchor = nil

            guard let drag = value.first else { return }
            // Momentum, but the polite kind: it carries a short way and settles
            // rather than spinning on.
            let velocity = CGSize(
                width: drag.predictedEndTranslation.width - drag.translation.width,
                height: drag.predictedEndTranslation.height - drag.translation.height
            )
            glide(from: camera, anchor: start, velocity: velocity)
        }
    }

    /// Double tap re-frames on where the user actually is.
    private var recenterGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            Haptics.tap()
            recenter()
        }
    }

    func recenter() {
        inertia?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
            camera = MountainCameraFraming.initial(for: scene, spec: spec)
        }
    }

    private func glide(from current: MountainCameraState, anchor: MountainCameraState, velocity: CGSize) {
        let speed = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
        guard speed > 12, !reduceMotion else { return }

        inertia = Task {
            var state = current
            var vx = Float(velocity.width)
            var vy = Float(velocity.height)
            let panScale = state.distance * 0.0038

            // ~0.55s of decay at 60Hz. Short, and always converging.
            for _ in 0..<34 {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }

                vx *= 0.90
                vy *= 0.90
                state.yaw -= vx * 0.0022 * 0.16
                state.pitch += vy * 0.0016 * 0.16
                state.target.x -= vx * panScale * 0.55 * 0.16
                state.target.y += vy * panScale * 0.30 * 0.16
                state.clamp()
                camera = state
            }
        }
    }
}

/// Chooses the opening camera.
enum MountainCameraFraming {
    /// Frames the current position with a little of the route ahead visible.
    @MainActor
    static func initial(for scene: MountainSceneController, spec: MountainWorldSpec) -> MountainCameraState {
        var state = MountainCameraState()

        let focus = spec.hasStarted ? scene.currentMarkerPosition : scene.basePosition
        let ahead = scene.summitPosition
        // Bias the look-at a little up the mountain: the journey should read as
        // going somewhere, not as ending where the user is standing.
        let target = mix(focus, ahead, 0.28) + SIMD3<Float>(0, 5, 0)

        let origin = MountainWorldSpec.origin(of: spec.focusExpedition)
        state.targetBounds = MountainCameraState.TargetBounds(
            min: SIMD3<Float>(origin.x - MountainWorldSpec.expeditionSpacing * 1.6, -4, -70),
            max: SIMD3<Float>(origin.x + MountainWorldSpec.expeditionSpacing * 0.7, 62, 70)
        )
        state.target = target
        state.yaw = -0.10
        state.pitch = 0.34
        // Pull back further early on, closer once there is a climb to inspect.
        state.distance = spec.hasStarted ? 122 : 148
        state.clamp()
        return state
    }
}
