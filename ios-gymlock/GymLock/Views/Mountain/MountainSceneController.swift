import Foundation
import Observation
import RealityKit
import SwiftUI
import UIKit
import simd

/// Owns the RealityKit scene graph for the living mountain.
///
/// The controller outlives the view. Switching tabs tears the `RealityView`
/// down so the renderer stops doing work, but the entities, materials and
/// camera state stay here — coming back to Home re-attaches a world that is
/// already built rather than rebuilding a mountain.
@Observable
@MainActor
final class MountainSceneController {
    // MARK: - Lifecycle state

    enum Phase: Equatable {
        case idle
        case building
        case ready
        case failed
    }

    private(set) var phase: Phase = .idle
    /// Bumped whenever marker world positions change, so the 2D overlay knows
    /// to recompute its projections.
    private(set) var layoutVersion = 0

    /// World-space anchor for every visible checkpoint, keyed by week id.
    private(set) var pinAnchors: [Int: SIMD3<Float>] = [:]
    private(set) var basePosition: SIMD3<Float> = .zero
    private(set) var summitPosition: SIMD3<Float> = .zero
    private(set) var currentMarkerPosition: SIMD3<Float> = .zero

    /// The look currently on screen, including mid-crossfade values.
    private(set) var palette: EnvironmentPalette = .make(for: .neutral)
    private(set) var environment: EnvironmentState = .neutral

    var reduceMotion = false {
        didSet {
            guard oldValue != reduceMotion else { return }
            applyMotionPreference()
        }
    }

    // MARK: - Scene graph

    let root = Entity()

    private let worldsRoot = Entity()
    private let lightsRoot = Entity()
    private let skyEntity = ModelEntity()
    private let weatherEntity = Entity()
    private let cameraEntity = PerspectiveCamera()

    private var keyLight = Entity()
    private var fillLight = Entity()
    private var bounceLight = Entity()

    private var terrainEntities: [ModelEntity] = []
    private var forestEntities: [ModelEntity] = []
    private var boulderEntities: [ModelEntity] = []
    private var trailEntities: [TrailRole: [ModelEntity]] = [:]
    private var animatedEntities: [Entity] = []

    private enum TrailRole: Hashable {
        case completed
        case current
        case future
    }

    // MARK: - Materials

    private var terrainMaterial = PhysicallyBasedMaterial()
    private var forestMaterial = PhysicallyBasedMaterial()
    private var boulderMaterial = PhysicallyBasedMaterial()
    private var skyMaterial = UnlitMaterial()

    private var builtSpec: MountainWorldSpec?
    private var crossfadeTask: Task<Void, Never>?
    private var isPaused = false
    private var hasAppliedPalette = false

    /// Set once the opening shot has been framed. Lives here rather than in the
    /// view so returning to Home from another tab restores the user's own
    /// viewpoint instead of snapping them back to the default.
    var hasFramedCamera = false

    // MARK: - Init

    init() {
        root.addChild(worldsRoot)
        root.addChild(lightsRoot)
        root.addChild(skyEntity)
        root.addChild(weatherEntity)
        root.addChild(cameraEntity)

        setUpLights()
        setUpCamera()
        setUpSky()
    }

    var camera: PerspectiveCamera { cameraEntity }

    // MARK: - Building

    /// Builds (or rebuilds) the world for a progress snapshot.
    ///
    /// Nothing happens when the spec is unchanged, so a re-render of Home never
    /// costs a rebuild.
    func build(spec: MountainWorldSpec) async {
        guard builtSpec != spec else { return }
        guard phase != .building else { return }

        let isFirstBuild = builtSpec == nil
        if isFirstBuild { phase = .building }

        let geometry = await MountainGeometryBuilder.build(spec: spec)

        do {
            try install(geometry: geometry, spec: spec)
            builtSpec = spec
            phase = .ready
        } catch {
            // A mountain that cannot be built must not take Home down with it.
            print("[GymLock] mountain build failed: \(error.localizedDescription)")
            phase = .failed
        }
    }

    private func install(geometry: MountainGeometry, spec: MountainWorldSpec) throws {
        worldsRoot.children.removeAll()
        terrainEntities.removeAll()
        forestEntities.removeAll()
        boulderEntities.removeAll()
        trailEntities.removeAll()
        animatedEntities.removeAll()
        pinAnchors.removeAll()

        if let sky = try? resource(from: geometry.sky) {
            skyEntity.model = ModelComponent(mesh: sky, materials: [skyMaterial])
        }

        for expedition in geometry.expeditions {
            let world = Entity()
            world.position = MountainWorldSpec.origin(of: expedition.expedition)
            worldsRoot.addChild(world)

            let terrain = ModelEntity(mesh: try resource(from: expedition.terrain), materials: [terrainMaterial])
            world.addChild(terrain)
            terrainEntities.append(terrain)

            if !expedition.forest.isEmpty {
                let forest = ModelEntity(mesh: try resource(from: expedition.forest), materials: [forestMaterial])
                world.addChild(forest)
                forestEntities.append(forest)
            }

            try addTrail(expedition, to: world)
            addMarkers(expedition, spec: spec, to: world)
            try addBoulders(expedition, to: world)
            try addSummitFlag(expedition, to: world)

            // Absolute anchors for the 2D label layer.
            for (week, local) in expedition.pinPositions {
                pinAnchors[week] = local + world.position
            }

            if expedition.expedition == spec.focusExpedition {
                basePosition = expedition.basePosition + world.position
                summitPosition = expedition.summit + world.position
                currentMarkerPosition = expedition.currentPosition + world.position
            }
        }

        applyPalette(palette)
        applyMotionPreference()
        layoutVersion += 1
    }

    private func resource(from raw: RawMesh) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "gymlock.mesh")
        descriptor.positions = MeshBuffers.Positions(raw.positions)
        descriptor.normals = MeshBuffers.Normals(raw.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(raw.uvs)
        descriptor.primitives = .triangles(raw.indices)
        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - Trail

    private func addTrail(_ geometry: ExpeditionGeometry, to world: Entity) throws {
        func add(_ mesh: RawMesh, role: TrailRole) throws {
            guard !mesh.isEmpty else { return }
            let entity = ModelEntity(mesh: try resource(from: mesh), materials: [trailMaterial(for: role)])
            world.addChild(entity)
            trailEntities[role, default: []].append(entity)

            if role == .current {
                // The live segment breathes rather than blinks — a slow opacity
                // swing that draws the eye without ever becoming a strobe.
                entity.components.set(OpacityComponent(opacity: 1))
                animatedEntities.append(entity)
            }
        }

        try add(geometry.trailCompleted, role: .completed)
        try add(geometry.trailCurrent, role: .current)
        try add(geometry.trailFuture, role: .future)
    }

    private func trailMaterial(for role: TrailRole) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.roughness = 0.72
        material.metallic = 0.0

        switch role {
        case .completed:
            material.baseColor = .init(tint: UIColor(Theme.accent))
            material.emissiveColor = .init(color: UIColor(Theme.accent))
            material.emissiveIntensity = palette.trailGlow
        case .current:
            material.baseColor = .init(tint: UIColor(red: 1.0, green: 0.47, blue: 0.36, alpha: 1))
            material.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.52, blue: 0.40, alpha: 1))
            material.emissiveIntensity = 0.35 + palette.trailGlow
        case .future:
            // Desaturated and translucent, so the route ahead is legible as a
            // plan rather than as progress the user has not earned.
            material.baseColor = .init(tint: UIColor(red: 0.78, green: 0.63, blue: 0.58, alpha: 0.55))
            material.blending = .transparent(opacity: 0.55)
            material.emissiveIntensity = palette.trailGlow * 0.35
        }
        return material
    }

    // MARK: - Markers

    private func addMarkers(_ geometry: ExpeditionGeometry, spec: MountainWorldSpec, to world: Entity) {
        for pin in spec.pins(in: geometry.expedition) {
            guard let position = geometry.pinPositions[pin.id] else { continue }

            let anchor = Entity()
            anchor.position = position + SIMD3<Float>(0, 0.06, 0)
            world.addChild(anchor)

            switch pin.state {
            case .completed, .partial:
                addRing(to: anchor, inner: 0.72, outer: 1.28, colour: UIColor(Theme.accent), opacity: 1)
                addDisc(to: anchor, radius: 0.72, colour: UIColor(Theme.accent), opacity: pin.state == .completed ? 1 : 0.35)
            case .current:
                addRing(to: anchor, inner: 0.95, outer: 1.45, colour: UIColor(Theme.accent), opacity: 1)
                // A second, larger ring breathes outward from the marker.
                let halo = addRing(to: anchor, inner: 1.5, outer: 1.78, colour: UIColor(Theme.accent), opacity: 0.5)
                halo.components.set(OpacityComponent(opacity: 0.5))
                animatedEntities.append(halo)
            case .upcoming:
                addRing(to: anchor, inner: 0.85, outer: 1.15, colour: UIColor(white: 0.62, alpha: 1), opacity: 0.5)
            case .missed:
                addRing(to: anchor, inner: 0.85, outer: 1.15, colour: UIColor(white: 0.55, alpha: 1), opacity: 0.6)
            case .start:
                break
            }
        }

        // Day 0 always gets a marker, even before the first week is done.
        let start = Entity()
        start.position = geometry.basePosition + SIMD3<Float>(0, 0.06, 0)
        world.addChild(start)
        addRing(to: start, inner: 0.8, outer: 1.25, colour: UIColor(Theme.accent), opacity: 1)
        addFlag(to: start, height: 3.4, colour: UIColor(Theme.accent), scale: 0.7)
    }

    @discardableResult
    private func addRing(
        to parent: Entity,
        inner: Float,
        outer: Float,
        colour: UIColor,
        opacity: Float
    ) -> ModelEntity {
        let mesh = MountainMeshFactory.ring(inner: inner, outer: outer)
        var material = UnlitMaterial(color: colour)
        if opacity < 0.999 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        let entity = ModelEntity(
            mesh: (try? resource(from: mesh)) ?? .generatePlane(width: 0.01, depth: 0.01),
            materials: [material]
        )
        parent.addChild(entity)
        return entity
    }

    @discardableResult
    private func addDisc(
        to parent: Entity,
        radius: Float,
        colour: UIColor,
        opacity: Float
    ) -> ModelEntity {
        let mesh = MountainMeshFactory.disc(radius: radius)
        var material = UnlitMaterial(color: colour)
        if opacity < 0.999 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        let entity = ModelEntity(
            mesh: (try? resource(from: mesh)) ?? .generatePlane(width: 0.01, depth: 0.01),
            materials: [material]
        )
        entity.position.y = 0.02
        parent.addChild(entity)
        return entity
    }

    private func addBoulders(_ geometry: ExpeditionGeometry, to world: Entity) throws {
        for boulder in geometry.boulders {
            let entity = ModelEntity(mesh: try resource(from: boulder.mesh), materials: [boulderMaterial])
            entity.position = boulder.position
            world.addChild(entity)
            boulderEntities.append(entity)
        }
    }

    private func addSummitFlag(_ geometry: ExpeditionGeometry, to world: Entity) throws {
        let anchor = Entity()
        anchor.position = geometry.summit
        world.addChild(anchor)
        addFlag(to: anchor, height: 6.2, colour: UIColor(Theme.accent), scale: 1)
    }

    private func addFlag(to parent: Entity, height: Float, colour: UIColor, scale: Float) {
        let poleMesh = MountainMeshFactory.cylinder(radius: 0.12 * scale, height: height, sides: 6)
        var poleMaterial = PhysicallyBasedMaterial()
        poleMaterial.baseColor = .init(tint: UIColor(white: 0.22, alpha: 1))
        poleMaterial.roughness = 0.6

        if let mesh = try? resource(from: poleMesh) {
            parent.addChild(ModelEntity(mesh: mesh, materials: [poleMaterial]))
        }

        let clothMesh = MountainMeshFactory.quad(width: 2.4 * scale, height: 1.5 * scale)
        var clothMaterial = UnlitMaterial(color: colour)
        clothMaterial.faceCulling = .none

        if let mesh = try? resource(from: clothMesh) {
            let cloth = ModelEntity(mesh: mesh, materials: [clothMaterial])
            cloth.position = SIMD3<Float>(0, height - 1.7 * scale, 0)
            let pivot = Entity()
            pivot.addChild(cloth)
            parent.addChild(pivot)

            // A slow flutter, driven by RealityKit's own animation system so it
            // stops the moment the scene is paused.
            animatedEntities.append(pivot)
        }
    }

    // MARK: - Lighting and sky

    private func setUpLights() {
        for light in [keyLight, fillLight, bounceLight] {
            lightsRoot.addChild(light)
        }
        // Only the key light casts shadows; two shadow-casting directionals
        // would double the shadow pass for no visible gain.
        keyLight.components.set(DirectionalLightComponent.Shadow(
            maximumDistance: 260,
            depthBias: 3.5
        ))
    }

    private func setUpCamera() {
        cameraEntity.camera.fieldOfViewInDegrees = MountainCameraState.fieldOfView
        cameraEntity.camera.fieldOfViewOrientation = .vertical
        cameraEntity.camera.near = 1
        cameraEntity.camera.far = 2400
    }

    private func setUpSky() {
        skyMaterial = UnlitMaterial(color: .white)
        skyEntity.model = ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [skyMaterial])
    }

    /// Points the camera and keeps the sky and weather layers centred on it.
    func apply(cameraState: MountainCameraState) {
        let eye = cameraState.eye
        cameraEntity.transform = Transform(matrix: cameraState.worldMatrix)
        // The dome and the precipitation volume travel with the viewer, which
        // is what lets a 900-unit sky feel infinite and a 180-unit rain volume
        // feel like weather.
        skyEntity.position = eye
        weatherEntity.position = eye + SIMD3<Float>(0, 42, 0)
    }

    // MARK: - Environment

    /// Moves the scene to a new environment, crossfading rather than cutting.
    func setEnvironment(_ state: EnvironmentState, animated: Bool = true) {
        // Nothing to do when the look is already on screen. Without this the
        // scene would restage itself on every re-render of Home.
        guard state != environment || !hasAppliedPalette else { return }

        crossfadeTask?.cancel()
        let from = palette
        let to = EnvironmentPalette.make(for: state)
        let isFirstApplication = !hasAppliedPalette
        environment = state
        hasAppliedPalette = true

        guard animated && !isFirstApplication && !reduceMotion else {
            applyPalette(to)
            return
        }

        crossfadeTask = Task { [weak self] in
            let duration: Double = 1.5
            let steps = 22
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000) / steps))
                guard let self, !Task.isCancelled else { return }

                let t = Float(step) / Float(steps)
                // Ease so the change starts and lands softly — a linear weather
                // fade reads as a slider being dragged.
                let eased = t * t * (3 - 2 * t)
                // Textures are the expensive part of the blend, so they step at
                // a third of the rate the lights do. The eye cannot tell.
                self.applyPalette(from.blended(with: to, t: eased), redrawTextures: step % 3 == 0 || step == steps)
            }
        }
    }

    private func applyPalette(_ new: EnvironmentPalette, redrawTextures: Bool = true) {
        palette = new

        // Lights
        configure(keyLight, colour: new.sunColor, intensity: new.sunIntensity, direction: new.sunDirection)
        configure(fillLight, colour: new.fillColor, intensity: new.fillIntensity, direction: normalize(SIMD3<Float>(0.6, -0.35, 0.72)))
        configure(bounceLight, colour: new.bounceColor, intensity: new.bounceIntensity, direction: normalize(SIMD3<Float>(0.1, 0.85, 0.2)))

        // Trail emissives keep the route legible as the light drops away.
        for (role, entities) in trailEntities {
            let material = trailMaterial(for: role)
            for entity in entities {
                entity.model?.materials = [material]
            }
        }

        forestMaterial.baseColor = .init(tint: UIColor(
            red: CGFloat(new.grassShade.x * 0.78),
            green: CGFloat(new.grassShade.y * 0.86),
            blue: CGFloat(new.grassShade.z * 0.74),
            alpha: 1
        ))
        forestMaterial.roughness = 0.95
        for entity in forestEntities { entity.model?.materials = [forestMaterial] }

        boulderMaterial.baseColor = .init(tint: UIColor(
            red: CGFloat(new.rockShade.x * 0.92),
            green: CGFloat(new.rockShade.y * 0.92),
            blue: CGFloat(new.rockShade.z * 0.94),
            alpha: 1
        ))
        boulderMaterial.roughness = 0.98
        for entity in boulderEntities { entity.model?.materials = [boulderMaterial] }

        if redrawTextures {
            redrawEnvironmentTextures(new)
        }

        updatePrecipitation(new.precipitation)
    }

    private func configure(_ entity: Entity, colour: SIMD3<Float>, intensity: Float, direction: SIMD3<Float>) {
        var component = DirectionalLightComponent(
            color: UIColor(
                red: CGFloat(min(colour.x, 1)),
                green: CGFloat(min(colour.y, 1)),
                blue: CGFloat(min(colour.z, 1)),
                alpha: 1
            ),
            intensity: max(intensity, 0)
        )
        component.isRealWorldProxy = false
        entity.components.set(component)
        // A directional light shines along its own -Z.
        entity.look(at: direction, from: .zero, relativeTo: nil)
    }

    private func redrawEnvironmentTextures(_ new: EnvironmentPalette) {
        if let ramp = MountainTextures.terrainRamp(palette: new),
           let texture = try? TextureResource(image: ramp, options: .init(semantic: .color)) {
            terrainMaterial.baseColor = .init(tint: .white, texture: .init(texture))
            terrainMaterial.roughness = 0.94
            terrainMaterial.metallic = 0.0
            for entity in terrainEntities { entity.model?.materials = [terrainMaterial] }
        }

        if let sky = MountainTextures.sky(palette: new),
           let texture = try? TextureResource(image: sky, options: .init(semantic: .color)) {
            skyMaterial = UnlitMaterial(color: .white)
            skyMaterial.color = .init(tint: .white, texture: .init(texture))
            skyEntity.model?.materials = [skyMaterial]
        }
    }

    // MARK: - Precipitation

    private func updatePrecipitation(_ kind: PrecipitationKind) {
        switch kind {
        case .none:
            weatherEntity.components.remove(ParticleEmitterComponent.self)

        case .rain(let intensity):
            var emitter = ParticleEmitterComponent()
            emitter.emitterShape = .box
            emitter.emitterShapeSize = [190, 6, 190]
            emitter.birthLocation = .volume
            emitter.birthDirection = .world
            emitter.emissionDirection = [0, -1, 0]
            emitter.speed = 46
            emitter.speedVariation = 10
            emitter.particlesInheritTransform = false
            emitter.mainEmitter.birthRate = 520 * particleBudget * intensity
            emitter.mainEmitter.size = 0.09
            emitter.mainEmitter.lifeSpan = 2.0
            emitter.mainEmitter.lifeSpanVariation = 0.4
            emitter.mainEmitter.spreadingAngle = 0.04
            emitter.mainEmitter.color = .constant(.single(UIColor(white: 0.92, alpha: 0.45)))
            weatherEntity.components.set(emitter)

        case .snow(let intensity):
            var emitter = ParticleEmitterComponent()
            emitter.emitterShape = .box
            emitter.emitterShapeSize = [190, 6, 190]
            emitter.birthLocation = .volume
            emitter.birthDirection = .world
            emitter.emissionDirection = [0, -1, 0]
            emitter.speed = 5.5
            emitter.speedVariation = 2.2
            emitter.particlesInheritTransform = false
            emitter.mainEmitter.birthRate = 190 * particleBudget * intensity
            emitter.mainEmitter.size = 0.34
            emitter.mainEmitter.sizeVariation = 0.16
            emitter.mainEmitter.lifeSpan = 9
            emitter.mainEmitter.lifeSpanVariation = 2
            emitter.mainEmitter.spreadingAngle = 0.5
            emitter.mainEmitter.vortexStrength = 0.4
            emitter.mainEmitter.color = .constant(.single(UIColor(white: 1, alpha: 0.9)))
            weatherEntity.components.set(emitter)
        }

        if isPaused {
            setEmitting(false)
        }
    }

    /// Scales particle counts down on devices with fewer cores, and again when
    /// the system is conserving power.
    private var particleBudget: Float {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return 0.35 }
        return ProcessInfo.processInfo.activeProcessorCount >= 6 ? 1.0 : 0.55
    }

    // MARK: - Pausing

    /// Stops all scene work when the mountain is off screen or backgrounded.
    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused

        setEmitting(!paused)

        for entity in animatedEntities {
            if paused {
                entity.stopAllAnimations()
            }
        }
        if !paused { applyMotionPreference() }

        if paused { crossfadeTask?.cancel() }
    }

    private func setEmitting(_ isEmitting: Bool) {
        guard var emitter = weatherEntity.components[ParticleEmitterComponent.self] else { return }
        emitter.isEmitting = isEmitting
        weatherEntity.components.set(emitter)
    }

    /// Starts or stops the decorative loops. Reduce Motion silences all of
    /// them without removing anything from the scene.
    private func applyMotionPreference() {
        for entity in animatedEntities {
            entity.stopAllAnimations()
            guard !reduceMotion, !isPaused else { continue }

            if entity.components.has(OpacityComponent.self) {
                let definition = FromToByAnimation<Float>(
                    name: "breathe",
                    from: 0.45,
                    to: 1.0,
                    duration: 1.9,
                    timing: .easeInOut,
                    bindTarget: .opacity,
                    repeatMode: .autoReverse
                )
                if let animation = try? AnimationResource.generate(with: definition) {
                    entity.playAnimation(animation)
                }
            } else {
                // Flag pivots: a shallow rotation that reads as wind.
                let definition = FromToByAnimation<Transform>(
                    name: "flutter",
                    from: Transform(rotation: simd_quatf(angle: -0.14, axis: [0, 1, 0])),
                    to: Transform(rotation: simd_quatf(angle: 0.16, axis: [0, 1, 0])),
                    duration: 2.6,
                    timing: .easeInOut,
                    bindTarget: .transform,
                    repeatMode: .autoReverse
                )
                if let animation = try? AnimationResource.generate(with: definition) {
                    entity.playAnimation(animation)
                }
            }
        }
    }

    // MARK: - Progress reactions

    /// A soft acknowledgement when a session is verified: the live segment and
    /// its marker pulse once. No confetti, no fireworks.
    func celebrateVerifiedWorkout() {
        guard !reduceMotion else { return }

        for entity in trailEntities[.current] ?? [] {
            let definition = FromToByAnimation<Float>(
                name: "verified",
                from: 1.0,
                to: 0.35,
                duration: 0.42,
                timing: .easeInOut,
                bindTarget: .opacity,
                repeatMode: .autoReverse
            )
            if let animation = try? AnimationResource.generate(with: definition) {
                entity.playAnimation(animation)
            }
        }

        // Hand the loop back once the one-shot has played out.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.applyMotionPreference()
        }
    }
}
