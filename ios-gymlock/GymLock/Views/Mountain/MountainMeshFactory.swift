import Foundation
import simd

/// Raw geometry, free of any RealityKit type.
///
/// Meshes are built off the main actor — a full-resolution terrain is roughly
/// fifteen thousand vertices and would drop frames if it were generated inside
/// a view update. `MeshResource` itself is main-actor bound, so the split is
/// deliberate: heavy arithmetic happens anywhere, and only the final upload
/// touches the main thread.
nonisolated struct RawMesh: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    /// Appends another mesh, offsetting its indices. Used to bake hundreds of
    /// trees or rocks into a single draw call.
    mutating func append(_ other: RawMesh) {
        let offset = UInt32(positions.count)
        positions.append(contentsOf: other.positions)
        normals.append(contentsOf: other.normals)
        uvs.append(contentsOf: other.uvs)
        indices.append(contentsOf: other.indices.map { $0 + offset })
    }

    /// Copies the mesh with every vertex transformed — the cheap way to place
    /// many instances of one prototype into a merged mesh.
    func transformed(by matrix: float4x4) -> RawMesh {
        var copy = self
        let rotation = float3x3(
            SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
        copy.positions = positions.map {
            let v = matrix * SIMD4<Float>($0.x, $0.y, $0.z, 1)
            return SIMD3<Float>(v.x, v.y, v.z)
        }
        copy.normals = normals.map { normalize(rotation * $0) }
        return copy
    }
}

/// Builds every piece of mountain geometry.
///
/// All methods are `nonisolated` and pure: given the same field and inputs they
/// return the same vertices, which is what makes the world stable across
/// launches without persisting geometry.
nonisolated enum MountainMeshFactory {
    // MARK: - Terrain

    /// A square patch of terrain.
    ///
    /// UVs are not a surface parameterisation — they are a *material lookup*:
    /// U is steepness and V is inverse altitude, so a small ramp texture decides
    /// where grass becomes rock and rock becomes snow. Changing the season or
    /// the weather then costs one 64×256 texture swap instead of a rebuild.
    nonisolated static func terrain(
        field: TerrainField,
        resolution: Int,
        extent: Float
    ) -> RawMesh {
        var mesh = RawMesh()
        let count = max(resolution, 8)
        let vertexCount = (count + 1) * (count + 1)
        mesh.positions.reserveCapacity(vertexCount)
        mesh.normals.reserveCapacity(vertexCount)
        mesh.uvs.reserveCapacity(vertexCount)
        mesh.indices.reserveCapacity(count * count * 6)

        let summit = field.summitHeight
        let step = (extent * 2) / Float(count)

        for row in 0...count {
            let z = -extent + Float(row) * step
            for column in 0...count {
                let x = -extent + Float(column) * step
                let y = field.height(x, z)

                mesh.positions.append(SIMD3<Float>(x, y, z))
                mesh.normals.append(field.normal(x, z, step: step * 0.85))
                mesh.uvs.append(SIMD2<Float>(
                    min(max(field.steepness(x, z), 0), 1),
                    1 - min(max(y / summit, 0), 1)
                ))
            }
        }

        let stride = count + 1
        for row in 0..<count {
            for column in 0..<count {
                let a = UInt32(row * stride + column)
                let b = a + 1
                let c = a + UInt32(stride)
                let d = c + 1
                mesh.indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        return mesh
    }

    // MARK: - Trail

    /// A ribbon that follows the route between two arc positions.
    ///
    /// Every vertex — including the two edges — has its height read from the
    /// terrain rather than from the centre line. On a side slope that keeps the
    /// downhill edge of the path pinned to the ground instead of letting the
    /// ribbon hover off the hillside.
    nonisolated static func trailRibbon(
        route: MountainRoute,
        field: TerrainField,
        from startT: Float,
        to endT: Float,
        width: Float,
        lift: Float,
        segments: Int = 140
    ) -> RawMesh {
        var mesh = RawMesh()
        guard endT > startT else { return mesh }

        let count = max(8, Int(Float(segments) * (endT - startT)) + 8)
        mesh.positions.reserveCapacity((count + 1) * 2)

        for index in 0...count {
            let t = startT + (endT - startT) * Float(index) / Float(count)
            let centre = route.point(at: t)
            let tangent = route.tangent(at: t)
            let side = normalize(cross(SIMD3<Float>(0, 1, 0), tangent))
            let half = width * 0.5

            for sign in [Float(-1), Float(1)] {
                let offset = centre + side * (half * sign)
                let y = field.height(offset.x, offset.z) + lift
                mesh.positions.append(SIMD3<Float>(offset.x, y, offset.z))
                mesh.normals.append(field.normal(offset.x, offset.z))
                mesh.uvs.append(SIMD2<Float>(sign > 0 ? 1 : 0, t))
            }
        }

        for index in 0..<count {
            let a = UInt32(index * 2)
            let b = a + 1
            let c = a + 2
            let d = a + 3
            mesh.indices.append(contentsOf: [a, c, b, b, c, d])
        }

        return mesh
    }

    // MARK: - Primitives

    /// A flat-shaded, irregular boulder.
    ///
    /// Built by jittering a subdivided octahedron with the same deterministic
    /// hash the terrain uses, so a given week's rock is always the same rock.
    nonisolated static func boulder(seed: UInt32, radius: Float) -> RawMesh {
        var base: [SIMD3<Float>] = [
            [0, 1, 0], [0, -1, 0],
            [1, 0, 0], [-1, 0, 0],
            [0, 0, 1], [0, 0, -1],
        ]
        var faces: [(Int, Int, Int)] = [
            (0, 4, 2), (0, 2, 5), (0, 5, 3), (0, 3, 4),
            (1, 2, 4), (1, 5, 2), (1, 3, 5), (1, 4, 3),
        ]

        // One subdivision is enough for a stylised rock and keeps the triangle
        // count at 32 per boulder.
        var midpoints: [String: Int] = [:]
        var subdivided: [(Int, Int, Int)] = []
        func midpoint(_ a: Int, _ b: Int) -> Int {
            let key = a < b ? "\(a)-\(b)" : "\(b)-\(a)"
            if let existing = midpoints[key] { return existing }
            let point = normalize((base[a] + base[b]) * 0.5)
            base.append(point)
            let index = base.count - 1
            midpoints[key] = index
            return index
        }
        for face in faces {
            let ab = midpoint(face.0, face.1)
            let bc = midpoint(face.1, face.2)
            let ca = midpoint(face.2, face.0)
            subdivided.append(contentsOf: [
                (face.0, ab, ca), (face.1, bc, ab), (face.2, ca, bc), (ab, bc, ca),
            ])
        }
        faces = subdivided

        // Deterministic per-vertex jitter.
        var state = seed | 1
        func next() -> Float {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return Float(state) * (1.0 / Float(UInt32.max))
        }
        let jittered = base.map { point -> SIMD3<Float> in
            let scale = 0.72 + next() * 0.46
            return point * radius * scale * SIMD3<Float>(1.1, 0.78, 1.0)
        }

        // Duplicated vertices per face give hard facets, which is what makes a
        // low-poly rock read as stone rather than as a lumpy ball.
        var mesh = RawMesh()
        for face in faces {
            let a = jittered[face.0]
            let b = jittered[face.1]
            let c = jittered[face.2]
            let normal = normalize(cross(b - a, c - a))
            let offset = UInt32(mesh.positions.count)
            mesh.positions.append(contentsOf: [a, b, c])
            mesh.normals.append(contentsOf: [normal, normal, normal])
            mesh.uvs.append(contentsOf: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0.5, 1)])
            mesh.indices.append(contentsOf: [offset, offset + 1, offset + 2])
        }
        return mesh
    }

    /// A stylised conifer: a trunk and two stacked cones.
    nonisolated static func conifer(height: Float, radius: Float) -> RawMesh {
        var mesh = RawMesh()
        mesh.append(cylinder(radius: radius * 0.16, height: height * 0.3, sides: 5))
        mesh.append(cone(radius: radius, height: height * 0.55, sides: 7)
            .transformed(by: translation([0, height * 0.24, 0])))
        mesh.append(cone(radius: radius * 0.7, height: height * 0.45, sides: 7)
            .transformed(by: translation([0, height * 0.56, 0])))
        return mesh
    }

    nonisolated static func cone(radius: Float, height: Float, sides: Int) -> RawMesh {
        var mesh = RawMesh()
        let apex = SIMD3<Float>(0, height, 0)
        for index in 0..<sides {
            let a0 = Float(index) / Float(sides) * 2 * .pi
            let a1 = Float(index + 1) / Float(sides) * 2 * .pi
            let p0 = SIMD3<Float>(cos(a0) * radius, 0, sin(a0) * radius)
            let p1 = SIMD3<Float>(cos(a1) * radius, 0, sin(a1) * radius)
            let normal = normalize(cross(p1 - p0, apex - p0))
            let offset = UInt32(mesh.positions.count)
            mesh.positions.append(contentsOf: [p0, p1, apex])
            mesh.normals.append(contentsOf: [normal, normal, normal])
            mesh.uvs.append(contentsOf: [SIMD2<Float>(0, 1), SIMD2<Float>(1, 1), SIMD2<Float>(0.5, 0)])
            mesh.indices.append(contentsOf: [offset, offset + 1, offset + 2])
        }
        return mesh
    }

    nonisolated static func cylinder(radius: Float, height: Float, sides: Int) -> RawMesh {
        var mesh = RawMesh()
        for index in 0..<sides {
            let a0 = Float(index) / Float(sides) * 2 * .pi
            let a1 = Float(index + 1) / Float(sides) * 2 * .pi
            let d0 = SIMD3<Float>(cos(a0), 0, sin(a0))
            let d1 = SIMD3<Float>(cos(a1), 0, sin(a1))
            let b0 = d0 * radius
            let b1 = d1 * radius
            let t0 = b0 + SIMD3<Float>(0, height, 0)
            let t1 = b1 + SIMD3<Float>(0, height, 0)
            let offset = UInt32(mesh.positions.count)
            mesh.positions.append(contentsOf: [b0, b1, t0, t1])
            mesh.normals.append(contentsOf: [d0, d1, d0, d1])
            mesh.uvs.append(contentsOf: [
                SIMD2<Float>(0, 1), SIMD2<Float>(1, 1), SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
            ])
            mesh.indices.append(contentsOf: [
                offset, offset + 1, offset + 2,
                offset + 1, offset + 3, offset + 2,
            ])
        }
        return mesh
    }

    /// A flat disc lying in the XZ plane — the base of every checkpoint marker.
    nonisolated static func disc(radius: Float, sides: Int = 28) -> RawMesh {
        var mesh = RawMesh()
        mesh.positions.append(SIMD3<Float>(0, 0, 0))
        mesh.normals.append(SIMD3<Float>(0, 1, 0))
        mesh.uvs.append(SIMD2<Float>(0.5, 0.5))

        for index in 0...sides {
            let angle = Float(index) / Float(sides) * 2 * .pi
            mesh.positions.append(SIMD3<Float>(cos(angle) * radius, 0, sin(angle) * radius))
            mesh.normals.append(SIMD3<Float>(0, 1, 0))
            mesh.uvs.append(SIMD2<Float>(cos(angle) * 0.5 + 0.5, sin(angle) * 0.5 + 0.5))
        }
        for index in 1...sides {
            mesh.indices.append(contentsOf: [0, UInt32(index), UInt32(index + 1)])
        }
        return mesh
    }

    /// A flat annulus — the hollow ring used for the current and future weeks.
    nonisolated static func ring(inner: Float, outer: Float, sides: Int = 32) -> RawMesh {
        var mesh = RawMesh()
        for index in 0...sides {
            let angle = Float(index) / Float(sides) * 2 * .pi
            let direction = SIMD3<Float>(cos(angle), 0, sin(angle))
            mesh.positions.append(direction * inner)
            mesh.positions.append(direction * outer)
            mesh.normals.append(contentsOf: [SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 1, 0)])
            mesh.uvs.append(contentsOf: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 1)])
        }
        for index in 0..<sides {
            let a = UInt32(index * 2)
            mesh.indices.append(contentsOf: [a, a + 1, a + 2, a + 1, a + 3, a + 2])
        }
        return mesh
    }

    /// A vertical quad, used for the flag cloth.
    nonisolated static func quad(width: Float, height: Float) -> RawMesh {
        var mesh = RawMesh()
        mesh.positions = [
            SIMD3<Float>(0, 0, 0), SIMD3<Float>(width, 0, 0),
            SIMD3<Float>(0, height, 0), SIMD3<Float>(width, height, 0),
        ]
        mesh.normals = Array(repeating: SIMD3<Float>(0, 0, 1), count: 4)
        mesh.uvs = [
            SIMD2<Float>(0, 1), SIMD2<Float>(1, 1), SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
        ]
        mesh.indices = [0, 1, 2, 1, 3, 2]
        return mesh
    }

    /// An inward-facing sphere for the sky.
    ///
    /// The winding is reversed on purpose so the dome is visible from inside
    /// without relying on double-sided materials, and V runs 0 at the zenith to
    /// 1 at the horizon so a simple vertical gradient texture maps straight on.
    nonisolated static func skyDome(radius: Float, rings: Int = 24, sectors: Int = 36) -> RawMesh {
        var mesh = RawMesh()
        for ring in 0...rings {
            let v = Float(ring) / Float(rings)
            let phi = v * .pi
            for sector in 0...sectors {
                let u = Float(sector) / Float(sectors)
                let theta = u * 2 * .pi
                let direction = SIMD3<Float>(
                    sin(phi) * cos(theta),
                    cos(phi),
                    sin(phi) * sin(theta)
                )
                mesh.positions.append(direction * radius)
                mesh.normals.append(-direction)
                mesh.uvs.append(SIMD2<Float>(u, v))
            }
        }

        let stride = sectors + 1
        for ring in 0..<rings {
            for sector in 0..<sectors {
                let a = UInt32(ring * stride + sector)
                let b = a + 1
                let c = a + UInt32(stride)
                let d = c + 1
                mesh.indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        return mesh
    }

    // MARK: - Scattering

    /// Deterministically scatters conifers over the buildable parts of a slope.
    ///
    /// Trees avoid the snow line, cliff faces and — importantly — the route
    /// itself, so nothing ever sprouts through the middle of the trail.
    nonisolated static func forest(
        field: TerrainField,
        route: MountainRoute,
        maxTrees: Int,
        snowLine: Float
    ) -> RawMesh {
        var mesh = RawMesh()
        let prototype = conifer(height: 3.4, radius: 1.05)
        let summit = field.summitHeight
        var state: UInt32 = field.seed | 1
        func next() -> Float {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return Float(state) * (1.0 / Float(UInt32.max))
        }

        // A coarse sample of the route is enough for a distance test and avoids
        // an O(trees × route) scan.
        let routeSamples = stride(from: 0, to: 1.0, by: 0.02).map { route.point(at: Float($0)) }

        var placed = 0
        var attempts = 0
        while placed < maxTrees && attempts < maxTrees * 8 {
            attempts += 1
            let angle = next() * 2 * .pi
            let radius = sqrt(next()) * field.radius * 1.22
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let y = field.height(x, z)

            let altitude = y / summit
            guard altitude < snowLine - 0.06, altitude > 0.02 else { continue }
            guard field.steepness(x, z) < 0.42 else { continue }

            let position = SIMD3<Float>(x, y, z)
            var tooClose = false
            for sample in routeSamples where distance_squared(sample, position) < 30 {
                tooClose = true
                break
            }
            guard !tooClose else { continue }

            // Trees thin out with altitude rather than stopping at a hard line.
            guard next() > altitude * 1.5 else { continue }

            let scale = 0.75 + next() * 0.85
            let spin = next() * 2 * .pi
            let matrix = translation(position) * rotationY(spin) * scaling(SIMD3<Float>(scale, scale * 1.15, scale))
            mesh.append(prototype.transformed(by: matrix))
            placed += 1
        }

        return mesh
    }
}

// MARK: - Matrix helpers

nonisolated func translation(_ offset: SIMD3<Float>) -> float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.3 = SIMD4<Float>(offset.x, offset.y, offset.z, 1)
    return matrix
}

nonisolated func scaling(_ scale: SIMD3<Float>) -> float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.0.x = scale.x
    matrix.columns.1.y = scale.y
    matrix.columns.2.z = scale.z
    return matrix
}

nonisolated func rotationY(_ radians: Float) -> float4x4 {
    let c = cos(radians)
    let s = sin(radians)
    return float4x4(
        SIMD4<Float>(c, 0, -s, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(s, 0, c, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}
