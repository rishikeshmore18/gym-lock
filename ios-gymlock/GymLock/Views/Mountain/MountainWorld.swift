import Foundation
import simd

/// One weekly checkpoint, resolved from real progress and pinned to a world
/// coordinate.
nonisolated struct WeekPin: Identifiable, Hashable, Sendable {
    /// Absolute week number since Day 0, zero-based.
    let id: Int
    let expedition: Int
    /// Position of this week within its twelve-week mountain.
    let indexInExpedition: Int
    let state: CheckpointState
    let verified: Int
    let planned: Int
    let hasPhoto: Bool

    /// Where along the route the checkpoint sits, 0 at the base and 1 at the
    /// summit. Week twelve *is* the summit, which is what makes finishing an
    /// expedition mean something.
    ///
    /// Day 0 is modelled as index -1, which lands it exactly at the base.
    var routePosition: Float {
        Float(indexInExpedition + 1) / Float(JourneyProgress.weeksPerExpedition)
    }

    var isStart: Bool { id < 0 }

    var title: String { isStart ? "Start" : "Week \(id + 1)" }

    var detail: String {
        switch state {
        case .start: "Begin here"
        case .completed: "Completed"
        case .partial: "\(verified) of \(planned)"
        case .missed: "Missed"
        case .current: "Up next"
        case .upcoming: "Upcoming"
        }
    }

    /// Full sentence for VoiceOver — progress must never be colour-only.
    var accessibilityDescription: String {
        switch state {
        case .start: "Start of your journey"
        case .completed: "\(title), completed, \(verified) of \(planned) sessions"
        case .partial: "\(title), partly completed, \(verified) of \(planned) sessions"
        case .missed: "\(title), missed"
        case .current: "\(title), up next, \(verified) of \(planned) sessions so far"
        case .upcoming: "\(title), upcoming"
        }
    }
}

/// Everything the renderer needs to lay out the world.
///
/// This is a pure value derived from the user's real history, so the scene has
/// no opinion of its own about progress — it can only draw what actually
/// happened.
nonisolated struct MountainWorldSpec: Sendable, Equatable {
    /// Distance between neighbouring peaks along X.
    static let expeditionSpacing: Float = 205

    /// Expedition indices to build, oldest first.
    let expeditions: [Int]
    /// The expedition the user is currently climbing.
    let focusExpedition: Int
    let pins: [WeekPin]
    /// How far up the current mountain the user stands, 0...1.
    let currentPosition: Float
    /// True once the user has actually started — before that the mountain shows
    /// only Day 0 and week one.
    let hasStarted: Bool

    nonisolated static func origin(of expedition: Int) -> SIMD3<Float> {
        SIMD3<Float>(Float(expedition) * expeditionSpacing, 0, 0)
    }

    /// Pins belonging to one mountain.
    func pins(in expedition: Int) -> [WeekPin] {
        pins.filter { $0.expedition == expedition }
    }

    static let placeholder = MountainWorldSpec(
        expeditions: [0],
        focusExpedition: 0,
        pins: [],
        currentPosition: 0,
        hasStarted: false
    )
}

/// Geometry for one mountain, produced away from the main actor.
nonisolated struct ExpeditionGeometry: Sendable {
    let expedition: Int
    let terrain: RawMesh
    let forest: RawMesh
    let trailCompleted: RawMesh
    let trailCurrent: RawMesh
    let trailFuture: RawMesh
    /// Boulders for missed weeks, already positioned in the mountain's space.
    let boulders: [(position: SIMD3<Float>, mesh: RawMesh)]
    let summit: SIMD3<Float>
    /// Marker anchor points, keyed by absolute week id.
    let pinPositions: [Int: SIMD3<Float>]
    let basePosition: SIMD3<Float>
    let currentPosition: SIMD3<Float>
    let isDetailed: Bool
}

nonisolated struct MountainGeometry: Sendable {
    let expeditions: [ExpeditionGeometry]
    let sky: RawMesh
}

/// Builds all world geometry.
///
/// Marked `nonisolated async` so the call hops straight off the main actor —
/// a detailed mountain is ~30k triangles and must never be generated inside a
/// view update.
nonisolated enum MountainGeometryBuilder {
    static func build(spec: MountainWorldSpec) async -> MountainGeometry {
        var built: [ExpeditionGeometry] = []
        built.reserveCapacity(spec.expeditions.count)

        for expedition in spec.expeditions {
            // Only the mountain being climbed is built at full resolution.
            // Older peaks are history: still there, still explorable, a third
            // of the triangles.
            let isDetailed = expedition == spec.focusExpedition
            built.append(buildExpedition(expedition, spec: spec, detailed: isDetailed))
            await Task.yield()
        }

        return MountainGeometry(
            expeditions: built,
            sky: MountainMeshFactory.skyDome(radius: 900)
        )
    }

    private static func buildExpedition(
        _ expedition: Int,
        spec: MountainWorldSpec,
        detailed: Bool
    ) -> ExpeditionGeometry {
        let field = TerrainField(expedition: expedition)
        let route = MountainRoute(field: field)

        let terrain = MountainMeshFactory.terrain(
            field: field,
            resolution: detailed ? 128 : 56,
            extent: field.radius * 1.34
        )

        let forest = MountainMeshFactory.forest(
            field: field,
            route: route,
            maxTrees: detailed ? 240 : 70,
            snowLine: 0.55
        )

        let pins = spec.pins(in: expedition)
        let isFocus = expedition == spec.focusExpedition
        // Past mountains are entirely walked; the current one is split at the
        // marker so the three trail states can each take their own material.
        let progress: Float = {
            if expedition < spec.focusExpedition { return 1 }
            if expedition > spec.focusExpedition { return 0 }
            return spec.currentPosition
        }()

        let trailWidth: Float = detailed ? 1.5 : 1.2
        let lift: Float = 0.22
        let currentBand: Float = isFocus ? 0.055 : 0

        let completedEnd = max(0, min(progress, 1))
        let currentEnd = min(1, completedEnd + currentBand)

        let trailCompleted = completedEnd > 0.001
            ? MountainMeshFactory.trailRibbon(
                route: route, field: field,
                from: 0, to: completedEnd,
                width: trailWidth, lift: lift,
                segments: detailed ? 420 : 180
            )
            : RawMesh()

        let trailCurrent = currentBand > 0
            ? MountainMeshFactory.trailRibbon(
                route: route, field: field,
                from: completedEnd, to: currentEnd,
                width: trailWidth * 1.18, lift: lift + 0.05,
                segments: detailed ? 420 : 180
            )
            : RawMesh()

        let trailFuture = currentEnd < 0.999
            ? MountainMeshFactory.trailRibbon(
                route: route, field: field,
                from: currentEnd, to: 1,
                width: trailWidth * 0.82, lift: lift,
                segments: detailed ? 420 : 180
            )
            : RawMesh()

        var pinPositions: [Int: SIMD3<Float>] = [:]
        var boulders: [(SIMD3<Float>, RawMesh)] = []

        for pin in pins {
            let position = route.point(at: pin.routePosition)
            pinPositions[pin.id] = position

            if pin.state == .missed {
                // The rock sits just off the centre line: it interrupts the
                // route without ever severing it, because the journey does not
                // end at a missed week.
                let tangent = route.tangent(at: pin.routePosition)
                let side = normalize(cross(SIMD3<Float>(0, 1, 0), tangent))
                let offset = position + side * 1.5
                let grounded = SIMD3<Float>(offset.x, field.height(offset.x, offset.z) + 0.9, offset.z)
                boulders.append((
                    grounded,
                    MountainMeshFactory.boulder(seed: UInt32(truncatingIfNeeded: pin.id &* 7919 &+ 13), radius: 1.9)
                ))
            }
        }

        return ExpeditionGeometry(
            expedition: expedition,
            terrain: terrain,
            forest: forest,
            trailCompleted: trailCompleted,
            trailCurrent: trailCurrent,
            trailFuture: trailFuture,
            boulders: boulders.map { (position: $0.0, mesh: $0.1) },
            summit: field.summit(),
            pinPositions: pinPositions,
            basePosition: route.point(at: 0),
            currentPosition: route.point(at: max(progress, 0.001)),
            isDetailed: detailed
        )
    }
}
