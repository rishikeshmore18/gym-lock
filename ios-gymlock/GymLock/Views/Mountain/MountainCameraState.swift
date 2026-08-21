import CoreGraphics
import Foundation
import simd

/// The viewer's position on the mountain, expressed as an orbit around a focus
/// point rather than as a free camera.
///
/// Every field is clamped. The user can look around the journey but can never
/// end up inside the mountain, under the terrain, or staring at empty sky
/// wondering how to get back — which is the failure mode of an unconstrained
/// orbit control in a screen people open every morning.
struct MountainCameraState: Equatable {
    /// Vertical field of view, matched to the RealityKit camera so the 2D label
    /// layer projects exactly onto the 3D world.
    static let fieldOfView: Float = 42

    /// Rotation around the focus point. Zero is the designed hero angle.
    var yaw: Float = 0
    /// Elevation above the horizon.
    var pitch: Float = 0.40
    /// Distance from the focus point.
    var distance: Float = 132
    /// The point the camera looks at.
    var target: SIMD3<Float> = .zero

    // MARK: - Limits

    /// Roughly ±25°, enough to feel the parallax of a real object without ever
    /// swinging round the back of the peak.
    static let yawLimit: Float = 25 * .pi / 180
    /// Never below the horizon of the terrain, never straight down.
    static let pitchRange: ClosedRange<Float> = (8 * .pi / 180)...(54 * .pi / 180)
    /// Close enough to read one checkpoint, far enough to see a whole
    /// twelve-week expedition.
    static let distanceRange: ClosedRange<Float> = 46...240

    /// How far the focus point may wander from the journey line, so panning
    /// explores history instead of getting lost in empty space.
    var targetBounds = TargetBounds.default

    /// The box the focus point is confined to.
    struct TargetBounds: Equatable {
        var min: SIMD3<Float>
        var max: SIMD3<Float>

        static let `default` = TargetBounds(
            min: SIMD3<Float>(-40, 0, -40),
            max: SIMD3<Float>(40, 46, 40)
        )
    }

    mutating func clamp() {
        yaw = Swift.min(Swift.max(yaw, -Self.yawLimit), Self.yawLimit)
        pitch = Swift.min(Swift.max(pitch, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
        distance = Swift.min(Swift.max(distance, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
        target.x = Swift.min(Swift.max(target.x, targetBounds.min.x), targetBounds.max.x)
        target.y = Swift.min(Swift.max(target.y, targetBounds.min.y), targetBounds.max.y)
        target.z = Swift.min(Swift.max(target.z, targetBounds.min.z), targetBounds.max.z)
    }

    // MARK: - Derived

    /// Camera position in world space.
    var eye: SIMD3<Float> {
        let horizontal = cos(pitch) * distance
        return target + SIMD3<Float>(
            sin(yaw) * horizontal,
            sin(pitch) * distance,
            cos(yaw) * horizontal
        )
    }

    /// The camera entity's transform: -Z points at the target.
    var worldMatrix: float4x4 {
        let position = eye
        let forward = normalize(target - position)
        let zAxis = -forward
        let up = SIMD3<Float>(0, 1, 0)
        // Guard the degenerate case of looking straight down the up vector.
        let xAxis = normalize(cross(abs(dot(up, zAxis)) > 0.999 ? SIMD3<Float>(0, 0, 1) : up, zAxis))
        let yAxis = cross(zAxis, xAxis)

        return float4x4(
            SIMD4<Float>(xAxis.x, xAxis.y, xAxis.z, 0),
            SIMD4<Float>(yAxis.x, yAxis.y, yAxis.z, 0),
            SIMD4<Float>(zAxis.x, zAxis.y, zAxis.z, 0),
            SIMD4<Float>(position.x, position.y, position.z, 1)
        )
    }

    /// How zoomed in the camera is, 0 at the widest and 1 at the closest.
    var zoomFraction: Float {
        let range = Self.distanceRange
        return 1 - (distance - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    // MARK: - Projection

    /// Projects a world point into view coordinates.
    ///
    /// The 2D label layer lives in SwiftUI rather than in the scene, which keeps
    /// text crisp at every zoom level and — more importantly — keeps every
    /// checkpoint reachable by VoiceOver. That only works if this matches the
    /// renderer's camera exactly, which is why the field of view is a shared
    /// constant rather than two numbers that have to be kept in step.
    func project(_ point: SIMD3<Float>, in size: CGSize) -> ProjectedPoint? {
        guard size.width > 1, size.height > 1 else { return nil }

        let view = worldMatrix.inverse
        let viewSpace = view * SIMD4<Float>(point.x, point.y, point.z, 1)
        // Anything at or behind the eye plane has no meaningful screen position.
        guard viewSpace.z < -0.01 else { return nil }

        let aspect = Float(size.width / size.height)
        let f = 1 / tan(Self.fieldOfView * .pi / 180 / 2)
        let ndcX = (f / aspect) * viewSpace.x / -viewSpace.z
        let ndcY = f * viewSpace.y / -viewSpace.z

        return ProjectedPoint(
            location: CGPoint(
                x: CGFloat(ndcX * 0.5 + 0.5) * size.width,
                y: CGFloat(1 - (ndcY * 0.5 + 0.5)) * size.height
            ),
            depth: -viewSpace.z
        )
    }
}

/// A world point resolved onto the screen, with its distance from the camera so
/// overlapping labels can be ordered back-to-front.
struct ProjectedPoint: Equatable {
    let location: CGPoint
    let depth: Float
}
