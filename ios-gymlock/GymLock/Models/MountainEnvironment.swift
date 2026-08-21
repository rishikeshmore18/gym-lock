import Foundation
import simd

/// The four lighting moods the mountain moves through in a day.
enum DayPhase: String, Codable, CaseIterable, Sendable {
    case morning
    case day
    case evening
    case night

    /// Derived from the device clock, which always works — no permission, no
    /// network, no waiting.
    static func current(at date: Date = Date(), calendar: Calendar = .current) -> DayPhase {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<10: return .morning
        case 10..<17: return .day
        case 17..<20: return .evening
        default: return .night
        }
    }

    var label: String {
        switch self {
        case .morning: "morning"
        case .day: "day"
        case .evening: "evening"
        case .night: "night"
        }
    }
}

/// A deliberately small set of weather looks.
///
/// Real weather has hundreds of condition codes; the mountain has six states.
/// Collapsing to a small set is what keeps transitions stable — a drizzle
/// upgrading to light rain must not restage the whole scene.
enum SkyCondition: String, Codable, CaseIterable, Sendable {
    case clear
    case cloudy
    case rain
    case snow
    case fog
    case storm

    var label: String {
        switch self {
        case .clear: "clear"
        case .cloudy: "cloudy"
        case .rain: "rain"
        case .snow: "snow"
        case .fog: "fog"
        case .storm: "storm"
        }
    }
}

/// Which particle layer the scene should be running.
enum PrecipitationKind: Equatable, Sendable {
    case none
    case rain(intensity: Float)
    case snow(intensity: Float)
}

/// The complete environment the mountain is rendered under.
struct EnvironmentState: Equatable, Codable, Sendable {
    var phase: DayPhase
    var condition: SkyCondition

    static let neutral = EnvironmentState(phase: .day, condition: .clear)

    /// Short line for the weather affordance, e.g. "evening · light snow".
    var summary: String { "\(phase.label) · \(condition.label)" }
}

/// Every value the renderer needs to dress the scene, as plain numbers that can
/// be interpolated.
///
/// Keeping the whole look in one interpolatable struct is what makes a weather
/// change a *crossfade* rather than a rebuild: the geometry never moves, only
/// these numbers travel from one set to another.
struct EnvironmentPalette: Sendable {
    var skyTop: SIMD3<Float>
    var skyHorizon: SIMD3<Float>
    var skyGround: SIMD3<Float>

    var sunColor: SIMD3<Float>
    var sunIntensity: Float
    /// Direction the key light travels, in world space.
    var sunDirection: SIMD3<Float>

    var fillColor: SIMD3<Float>
    var fillIntensity: Float
    var bounceColor: SIMD3<Float>
    var bounceIntensity: Float

    /// Multiplies the terrain ramp texture.
    var terrainTint: SIMD3<Float>
    /// Normalised altitude at which snow begins, 0 (base) to 1 (summit).
    var snowLine: Float
    /// Warmth of the snow and rock, so night reads blue without turning black.
    var rockShade: SIMD3<Float>
    var grassShade: SIMD3<Float>
    var snowShade: SIMD3<Float>

    /// Atmospheric wash drawn over the viewport, never above the labels.
    var hazeColor: SIMD3<Float>
    var hazeOpacity: Float
    /// How luminous the completed trail becomes, so it survives darkness.
    var trailGlow: Float
    var starOpacity: Float
    var cloudOpacity: Float

    var precipitation: PrecipitationKind
    /// Whether label chips need the dark treatment to stay legible.
    var prefersDarkChrome: Bool

    // MARK: - Construction

    static func make(for state: EnvironmentState) -> EnvironmentPalette {
        var palette = base(for: state.phase)
        apply(state.condition, to: &palette, phase: state.phase)
        return palette
    }

    private static func base(for phase: DayPhase) -> EnvironmentPalette {
        switch phase {
        case .morning:
            EnvironmentPalette(
                skyTop: [0.62, 0.74, 0.88],
                skyHorizon: [0.99, 0.87, 0.76],
                skyGround: [0.94, 0.88, 0.82],
                sunColor: [1.0, 0.89, 0.75],
                sunIntensity: 3400,
                sunDirection: normalize([-0.62, -0.30, -0.72]),
                fillColor: [0.70, 0.80, 0.95],
                fillIntensity: 900,
                bounceColor: [0.95, 0.86, 0.76],
                bounceIntensity: 340,
                terrainTint: [1.02, 0.99, 0.95],
                snowLine: 0.60,
                rockShade: [0.55, 0.54, 0.55],
                grassShade: [0.44, 0.50, 0.42],
                snowShade: [0.98, 0.97, 0.98],
                hazeColor: [0.99, 0.91, 0.83],
                hazeOpacity: 0.10,
                trailGlow: 0.10,
                starOpacity: 0,
                cloudOpacity: 0.30,
                precipitation: .none,
                prefersDarkChrome: false
            )
        case .day:
            EnvironmentPalette(
                skyTop: [0.42, 0.62, 0.86],
                skyHorizon: [0.84, 0.90, 0.96],
                skyGround: [0.90, 0.91, 0.90],
                sunColor: [1.0, 0.98, 0.94],
                sunIntensity: 4900,
                sunDirection: normalize([-0.38, -0.72, -0.58]),
                fillColor: [0.74, 0.83, 0.96],
                fillIntensity: 1100,
                bounceColor: [0.88, 0.87, 0.82],
                bounceIntensity: 380,
                terrainTint: [1.0, 1.0, 1.0],
                snowLine: 0.62,
                rockShade: [0.57, 0.56, 0.56],
                grassShade: [0.42, 0.50, 0.39],
                snowShade: [1.0, 1.0, 1.0],
                hazeColor: [0.88, 0.92, 0.97],
                hazeOpacity: 0.06,
                trailGlow: 0.06,
                starOpacity: 0,
                cloudOpacity: 0.22,
                precipitation: .none,
                prefersDarkChrome: false
            )
        case .evening:
            EnvironmentPalette(
                skyTop: [0.30, 0.36, 0.60],
                skyHorizon: [0.98, 0.66, 0.44],
                skyGround: [0.72, 0.58, 0.52],
                sunColor: [1.0, 0.72, 0.48],
                sunIntensity: 3000,
                sunDirection: normalize([0.78, -0.22, -0.58]),
                fillColor: [0.52, 0.58, 0.82],
                fillIntensity: 720,
                bounceColor: [0.92, 0.66, 0.50],
                bounceIntensity: 300,
                terrainTint: [1.05, 0.94, 0.88],
                snowLine: 0.60,
                rockShade: [0.52, 0.48, 0.49],
                grassShade: [0.38, 0.42, 0.35],
                snowShade: [0.98, 0.92, 0.90],
                hazeColor: [0.99, 0.76, 0.58],
                hazeOpacity: 0.13,
                trailGlow: 0.22,
                starOpacity: 0.10,
                cloudOpacity: 0.28,
                precipitation: .none,
                prefersDarkChrome: false
            )
        case .night:
            EnvironmentPalette(
                skyTop: [0.045, 0.065, 0.15],
                skyHorizon: [0.13, 0.17, 0.30],
                skyGround: [0.10, 0.12, 0.20],
                sunColor: [0.66, 0.76, 1.0],
                sunIntensity: 900,
                sunDirection: normalize([0.42, -0.56, -0.62]),
                fillColor: [0.30, 0.40, 0.68],
                fillIntensity: 420,
                bounceColor: [0.24, 0.28, 0.44],
                bounceIntensity: 190,
                terrainTint: [0.72, 0.78, 0.96],
                snowLine: 0.58,
                rockShade: [0.34, 0.36, 0.44],
                grassShade: [0.22, 0.27, 0.32],
                snowShade: [0.80, 0.85, 0.96],
                hazeColor: [0.10, 0.14, 0.26],
                hazeOpacity: 0.12,
                trailGlow: 0.85,
                starOpacity: 1.0,
                cloudOpacity: 0.18,
                precipitation: .none,
                prefersDarkChrome: true
            )
        }
    }

    /// Weather is applied as a modifier on top of the hour, so "rainy evening"
    /// still reads as evening rather than as a generic grey box.
    private static func apply(_ condition: SkyCondition, to palette: inout EnvironmentPalette, phase: DayPhase) {
        let isNight = phase == .night

        switch condition {
        case .clear:
            return

        case .cloudy:
            palette.sunIntensity *= 0.58
            palette.fillIntensity *= 1.25
            palette.skyTop = mix(palette.skyTop, [0.62, 0.65, 0.70], 0.55)
            palette.skyHorizon = mix(palette.skyHorizon, [0.78, 0.79, 0.82], 0.55)
            palette.hazeOpacity += 0.05
            palette.cloudOpacity = 0.72
            palette.starOpacity *= 0.2

        case .rain:
            palette.sunIntensity *= 0.40
            palette.fillIntensity *= 1.15
            palette.skyTop = mix(palette.skyTop, [0.44, 0.48, 0.55], 0.68)
            palette.skyHorizon = mix(palette.skyHorizon, [0.62, 0.65, 0.70], 0.68)
            palette.terrainTint *= 0.86
            palette.rockShade *= 0.82
            palette.grassShade *= 0.88
            palette.hazeColor = mix(palette.hazeColor, [0.55, 0.60, 0.66], 0.7)
            palette.hazeOpacity += 0.09
            palette.cloudOpacity = 0.80
            palette.trailGlow = max(palette.trailGlow, 0.28)
            palette.starOpacity = 0
            palette.precipitation = .rain(intensity: 1.0)

        case .snow:
            palette.sunIntensity *= 0.62
            palette.fillIntensity *= 1.30
            palette.skyTop = mix(palette.skyTop, [0.70, 0.73, 0.78], 0.60)
            palette.skyHorizon = mix(palette.skyHorizon, [0.88, 0.89, 0.92], 0.60)
            // Snow creeps down the mountain but never far enough to bury the
            // route the user is standing on.
            palette.snowLine = max(0.24, palette.snowLine - 0.30)
            palette.grassShade = mix(palette.grassShade, [0.72, 0.75, 0.78], 0.45)
            palette.hazeColor = mix(palette.hazeColor, [0.92, 0.94, 0.97], 0.7)
            palette.hazeOpacity += 0.07
            palette.cloudOpacity = 0.62
            palette.trailGlow = max(palette.trailGlow, 0.24)
            palette.starOpacity = 0
            palette.precipitation = .snow(intensity: 1.0)

        case .fog:
            palette.sunIntensity *= 0.50
            palette.fillIntensity *= 1.35
            palette.skyTop = mix(palette.skyTop, [0.78, 0.79, 0.80], 0.72)
            palette.skyHorizon = mix(palette.skyHorizon, [0.86, 0.87, 0.88], 0.80)
            // Capped deliberately: fog is atmosphere, not a blindfold.
            palette.hazeColor = mix(palette.hazeColor, [0.86, 0.88, 0.90], 0.85)
            palette.hazeOpacity = min(0.34, palette.hazeOpacity + 0.24)
            palette.cloudOpacity = 0.45
            palette.trailGlow = max(palette.trailGlow, 0.34)
            palette.starOpacity = 0

        case .storm:
            palette.sunIntensity *= 0.26
            palette.fillIntensity *= 1.05
            palette.skyTop = mix(palette.skyTop, [0.20, 0.22, 0.28], 0.78)
            palette.skyHorizon = mix(palette.skyHorizon, [0.38, 0.40, 0.46], 0.78)
            palette.terrainTint *= 0.76
            palette.rockShade *= 0.76
            palette.grassShade *= 0.80
            palette.hazeColor = mix(palette.hazeColor, [0.34, 0.37, 0.44], 0.8)
            palette.hazeOpacity += 0.12
            palette.cloudOpacity = 0.92
            palette.trailGlow = max(palette.trailGlow, 0.50)
            palette.starOpacity = 0
            palette.precipitation = .rain(intensity: 1.5)
            palette.prefersDarkChrome = true
        }

        if isNight {
            palette.prefersDarkChrome = true
            palette.trailGlow = max(palette.trailGlow, 0.7)
        }
    }

    // MARK: - Interpolation

    /// Blends two looks. `t` of 0 returns self, 1 returns `other`.
    func blended(with other: EnvironmentPalette, t rawT: Float) -> EnvironmentPalette {
        let t = min(max(rawT, 0), 1)
        var result = other

        result.skyTop = mix(skyTop, other.skyTop, t)
        result.skyHorizon = mix(skyHorizon, other.skyHorizon, t)
        result.skyGround = mix(skyGround, other.skyGround, t)
        result.sunColor = mix(sunColor, other.sunColor, t)
        result.sunIntensity = mixF(sunIntensity, other.sunIntensity, t)
        result.sunDirection = normalize(mix(sunDirection, other.sunDirection, t))
        result.fillColor = mix(fillColor, other.fillColor, t)
        result.fillIntensity = mixF(fillIntensity, other.fillIntensity, t)
        result.bounceColor = mix(bounceColor, other.bounceColor, t)
        result.bounceIntensity = mixF(bounceIntensity, other.bounceIntensity, t)
        result.terrainTint = mix(terrainTint, other.terrainTint, t)
        result.snowLine = mixF(snowLine, other.snowLine, t)
        result.rockShade = mix(rockShade, other.rockShade, t)
        result.grassShade = mix(grassShade, other.grassShade, t)
        result.snowShade = mix(snowShade, other.snowShade, t)
        result.hazeColor = mix(hazeColor, other.hazeColor, t)
        result.hazeOpacity = mixF(hazeOpacity, other.hazeOpacity, t)
        result.trailGlow = mixF(trailGlow, other.trailGlow, t)
        result.starOpacity = mixF(starOpacity, other.starOpacity, t)
        result.cloudOpacity = mixF(cloudOpacity, other.cloudOpacity, t)
        // Particles and chrome switch at the halfway point rather than fading
        // through a meaningless in-between state.
        result.precipitation = t < 0.5 ? precipitation : other.precipitation
        result.prefersDarkChrome = t < 0.5 ? prefersDarkChrome : other.prefersDarkChrome

        return result
    }
}

// MARK: - Small vector helpers

func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

func mixF(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}
