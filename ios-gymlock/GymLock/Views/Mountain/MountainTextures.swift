import CoreGraphics
import Foundation
import UIKit
import simd

/// Draws the two small textures that carry the whole look of the mountain.
///
/// Between them these replace what would otherwise be authored HDR environment
/// maps and multiple terrain materials. Both are tiny — a few kilobytes — which
/// is what makes a weather change affordable as a crossfade: the scene never
/// reloads a model, it just re-draws two ramps.
enum MountainTextures {
    /// Terrain lookup: U is steepness, V is inverse altitude.
    ///
    /// Reading altitude out of a texture instead of baking colours into vertices
    /// means the snow line can slide down the mountain when it starts snowing
    /// without touching a single vertex.
    static func terrainRamp(palette: EnvironmentPalette, size: CGSize = CGSize(width: 64, height: 256)) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let snowLine = palette.snowLine
        let grass = palette.grassShade
        let rock = palette.rockShade
        let snow = palette.snowShade

        for row in 0..<height {
            // V of 0 is the top of the image, which is the summit.
            let altitude = 1 - Float(row) / Float(height - 1)

            for column in 0..<width {
                let steepness = Float(column) / Float(width - 1)

                // Grass gives way to rock as the ground tilts and rises.
                let rockBlend = smoothstep(0.18, 0.52, steepness)
                    + smoothstep(snowLine - 0.34, snowLine - 0.02, altitude)
                var colour = mix(grass, rock, min(rockBlend, 1))

                // Snow settles above the line, but never on a cliff face — that
                // single rule is what stops a snowy mountain becoming a white
                // blob and keeps the ridges readable.
                let snowAltitude = smoothstep(snowLine - 0.05, snowLine + 0.11, altitude)
                let snowHold = 1 - smoothstep(0.46, 0.78, steepness)
                colour = mix(colour, snow, snowAltitude * snowHold)

                colour *= palette.terrainTint

                // A whisper of banding breaks up the flatness of a pure ramp.
                let band = 1 + sin(altitude * 46) * 0.012

                let offset = (row * width + column) * 4
                pixels[offset] = channel(colour.x * band)
                pixels[offset + 1] = channel(colour.y * band)
                pixels[offset + 2] = channel(colour.z * band)
                pixels[offset + 3] = 255
            }
        }

        return image(from: &pixels, width: width, height: height)
    }

    /// Sky gradient with stars baked in at night.
    ///
    /// V of 0 is the zenith and V of 1 the nadir, matching the dome's UVs.
    static func sky(palette: EnvironmentPalette, size: CGSize = CGSize(width: 128, height: 256)) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for row in 0..<height {
            let v = Float(row) / Float(height - 1)
            // The horizon sits at the equator of the dome.
            let horizon = smoothstep(0.30, 0.52, v)
            var band = mix(palette.skyTop, palette.skyHorizon, horizon)
            band = mix(band, palette.skyGround, smoothstep(0.52, 0.72, v))

            for column in 0..<width {
                var colour = band

                // Stars: a sparse deterministic scatter, only in the upper dome
                // and only when the palette asks for them.
                if palette.starOpacity > 0.01 && v < 0.48 {
                    let n = hash(UInt32(column) &* 1973 &+ UInt32(row) &* 9277)
                    if n > 0.9975 {
                        let twinkle = 0.55 + hash(UInt32(row) &* 61 &+ UInt32(column)) * 0.45
                        let strength = palette.starOpacity * twinkle * (1 - v / 0.48)
                        colour = mix(colour, SIMD3<Float>(1, 1, 1), strength)
                    }
                }

                // Soft cloud banding near the horizon.
                if palette.cloudOpacity > 0.02 {
                    let u = Float(column) / Float(width - 1)
                    let cloud = (sin(u * 11.3 + v * 24) * 0.5 + 0.5)
                        * (sin(u * 27.7 - v * 9) * 0.5 + 0.5)
                    let mask = smoothstep(0.16, 0.42, v) * (1 - smoothstep(0.46, 0.58, v))
                    let strength = cloud * mask * palette.cloudOpacity * 0.55
                    let cloudColour = mix(palette.skyHorizon, SIMD3<Float>(1, 1, 1), 0.35)
                    colour = mix(colour, cloudColour, strength)
                }

                let offset = (row * width + column) * 4
                pixels[offset] = channel(colour.x)
                pixels[offset + 1] = channel(colour.y)
                pixels[offset + 2] = channel(colour.z)
                pixels[offset + 3] = 255
            }
        }

        return image(from: &pixels, width: width, height: height)
    }

    /// A soft round sprite used for snowflakes, so flakes are discs rather than
    /// hard squares.
    static func softDot(size: Int = 32) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let centre = Float(size - 1) / 2
        for row in 0..<size {
            for column in 0..<size {
                let dx = (Float(column) - centre) / centre
                let dy = (Float(row) - centre) / centre
                let distance = sqrt(dx * dx + dy * dy)
                let alpha = 1 - smoothstep(0.35, 1.0, distance)
                let offset = (row * size + column) * 4
                pixels[offset] = 255
                pixels[offset + 1] = 255
                pixels[offset + 2] = 255
                pixels[offset + 3] = channel(alpha)
            }
        }
        return image(from: &pixels, width: size, height: size)
    }

    /// Renders an SF Symbol into a texture, used for the tick inside a
    /// completed checkpoint.
    static func symbol(_ name: String, pointSize: CGFloat = 96, colour: UIColor = .white) -> CGImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .heavy)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }

        let side = pointSize * 1.6
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let rendered = renderer.image { _ in
            let tinted = symbol.withTintColor(colour, renderingMode: .alwaysOriginal)
            let rect = CGRect(
                x: (side - symbol.size.width) / 2,
                y: (side - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            tinted.draw(in: rect)
        }
        return rendered.cgImage
    }

    // MARK: - Helpers

    private static func image(from pixels: inout [UInt8], width: Int, height: Int) -> CGImage? {
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colourSpace,
                      bitmapInfo: info.rawValue
                  )
            else { return nil }
            return context.makeImage()
        }
    }

    private static func channel(_ value: Float) -> UInt8 {
        UInt8(min(max(value, 0), 1) * 255)
    }

    private static func hash(_ value: UInt32) -> Float {
        var h = value &* 0x27D4_EB2D
        h = (h ^ (h >> 15)) &* 0x85EB_CA6B
        h = (h ^ (h >> 13)) &* 0xC2B2_AE35
        h = h ^ (h >> 16)
        return Float(h) * (1.0 / Float(UInt32.max))
    }
}

/// Hermite interpolation between two edges.
func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
