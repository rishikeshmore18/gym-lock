import SwiftUI

/// GymLock's warm, Airbnb-inspired design system.
/// A single source of truth for colour, radius, and motion so every
/// onboarding page and app screen shares one visual language.
enum Theme {
    // MARK: - Palette

    /// Warm off-white app canvas.
    static let canvas = Color(red: 0.980, green: 0.976, blue: 0.965)
    /// Elevated white card surface.
    static let surface = Color.white
    /// Slightly warmer surface used for inset rows.
    static let surfaceMuted = Color(red: 0.961, green: 0.953, blue: 0.937)
    /// Grounded coral accent — the only saturated colour in the app.
    static let accent = Color(red: 0.910, green: 0.365, blue: 0.306)
    /// Primary near-black text.
    static let ink = Color(red: 0.102, green: 0.102, blue: 0.102)
    /// Secondary grey text.
    static let inkSecondary = Color(red: 0.420, green: 0.420, blue: 0.420)
    /// Tertiary grey used for axis labels and fine print.
    static let inkTertiary = Color(red: 0.600, green: 0.600, blue: 0.600)
    /// Hairline border.
    static let border = Color(red: 0.910, green: 0.910, blue: 0.910)
    /// Dark surface used behind the logo mark.
    static let logoBackdrop = Color(red: 0.071, green: 0.071, blue: 0.075)

    // MARK: - Morning palette

    /// Warmer, brighter end of the accent, used only as the far stop of a
    /// gradient so coral stays the colour the eye reads.
    static let accentWarm = Color(red: 0.965, green: 0.541, blue: 0.267)
    /// Deeper end of the accent, for the leading edge of a fill.
    static let accentDeep = Color(red: 0.847, green: 0.286, blue: 0.220)
    /// Barely-there accent wash for haloes and inactive arcs.
    static let accentWash = Color(red: 0.976, green: 0.918, blue: 0.886)
    /// Deep blue reserved for the inside of the celestial illustration.
    /// The app canvas never becomes this — only the artwork does.
    static let night = Color(red: 0.141, green: 0.169, blue: 0.271)
    /// Warm yellow for the sun on a clock face. Paired with `night` as a
    /// celestial marker, never used as an accent.
    static let sun = Color(red: 0.976, green: 0.780, blue: 0.180)

    // MARK: - Morning motion

    /// The night-to-morning transition. Slow enough to read as a sunrise,
    /// short enough not to hold up the flow.
    static let celestial: Animation = .timingCurve(0.25, 0.85, 0.28, 1, duration: 0.95)

    // MARK: - Radii

    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 16

    // MARK: - Spacing

    static let pageMargin: CGFloat = 28

    // MARK: - Motion

    /// Restrained ease used for page-level content settling.
    static let settle: Animation = .timingCurve(0.22, 0.9, 0.24, 1, duration: 0.55)
    /// Fast colour/state transition for controls — no scale, no bounce.
    static let stateChange: Animation = .easeInOut(duration: 0.18)
    /// Vertical page transition, TikTok-like: quick with no visible bounce.
    static let pageTurn: Animation = .timingCurve(0.2, 0.85, 0.2, 1, duration: 0.42)
}

// MARK: - Shared modifiers

extension View {
    /// Applies the standard warm card treatment: white surface, generous
    /// radius, hairline border, and a soft lifted shadow.
    func warmCard(radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

// MARK: - Primary call to action

/// The single button style used across onboarding and setup.
/// Communicates readiness through colour saturation only — never scale.
struct PrimaryCTAStyle: ButtonStyle {
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.32),
                in: .rect(cornerRadius: Theme.controlRadius)
            )
            .animation(Theme.stateChange, value: isEnabled)
            .animation(Theme.stateChange, value: configuration.isPressed)
    }
}
