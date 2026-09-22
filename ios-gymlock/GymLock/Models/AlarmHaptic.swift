import Foundation

/// The vibration that plays alongside the alarm track while it rings in the
/// app, after Apple's own Haptics list in Clock.
///
/// Only the in-app ringer can play these. The system alarm and the
/// notification fallback vibrate the way iOS decides, and the Haptics screen
/// says so rather than implying otherwise.
///
/// Stored as pure timing data rather than Core Haptics events so it stays
/// Codable, testable and free of any framework; `AlarmRinger.events(for:)`
/// turns it into something the engine can play.
enum AlarmHaptic: String, Codable, CaseIterable, Identifiable, Hashable {
    case synchronized
    case accent
    case alert
    case heartbeat
    case quick
    case rapid
    case sos
    case staccato
    case symphony
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .synchronized: "Synchronized"
        case .accent: "Accent"
        case .alert: "Alert"
        case .heartbeat: "Heartbeat"
        case .quick: "Quick"
        case .rapid: "Rapid"
        case .sos: "S.O.S."
        case .staccato: "Staccato"
        case .symphony: "Symphony"
        case .none: "None"
        }
    }

    /// The list under "standard", in Apple's order.
    static let standard: [AlarmHaptic] = [
        .accent, .alert, .heartbeat, .quick, .rapid, .sos, .staccato, .symphony,
    ]

    /// One tap or buzz in the pattern.
    struct Beat: Hashable {
        let time: Double
        let intensity: Float
        let sharpness: Float
        /// Zero for a single tap; above zero for a sustained buzz.
        var duration: Double = 0

        var isContinuous: Bool { duration > 0 }
    }

    /// One cycle of the pattern. The ringer loops it.
    var beats: [Beat] {
        switch self {
        case .synchronized:
            // The ringer's original pulse: two knocks and a buzz, the shape of
            // a phone vibrating on wood.
            [
                Beat(time: 0, intensity: 1, sharpness: 0.7),
                Beat(time: 0.16, intensity: 0.85, sharpness: 0.7),
                Beat(time: 0.32, intensity: 0.7, sharpness: 0.4, duration: 0.45),
            ]
        case .accent:
            [
                Beat(time: 0, intensity: 1, sharpness: 0.9),
                Beat(time: 0.14, intensity: 0.45, sharpness: 0.5),
            ]
        case .alert:
            [0, 0.14, 0.28].map { Beat(time: $0, intensity: 1, sharpness: 1) }
        case .heartbeat:
            [
                Beat(time: 0, intensity: 1, sharpness: 0.25),
                Beat(time: 0.2, intensity: 0.65, sharpness: 0.2),
            ]
        case .quick:
            [Beat(time: 0, intensity: 0.9, sharpness: 0.85)]
        case .rapid:
            stride(from: 0.0, through: 0.7, by: 0.1).map {
                Beat(time: $0, intensity: 0.85, sharpness: 0.9)
            }
        case .sos:
            // Three short, three long, three short.
            [0, 0.2, 0.4].map { Beat(time: $0, intensity: 1, sharpness: 0.9) }
                + [0.7, 1.15, 1.6].map { Beat(time: $0, intensity: 1, sharpness: 0.5, duration: 0.3) }
                + [2.05, 2.25, 2.45].map { Beat(time: $0, intensity: 1, sharpness: 0.9) }
        case .staccato:
            [0, 0.22, 0.44, 0.66].map { Beat(time: $0, intensity: 0.8, sharpness: 1) }
        case .symphony:
            [
                Beat(time: 0, intensity: 0.45, sharpness: 0.2, duration: 0.35),
                Beat(time: 0.45, intensity: 0.7, sharpness: 0.35, duration: 0.35),
                Beat(time: 0.95, intensity: 1, sharpness: 0.8),
                Beat(time: 1.1, intensity: 0.6, sharpness: 0.6),
            ]
        case .none:
            []
        }
    }

    /// Length of one cycle including the rest before it repeats. The pause is
    /// what makes the next pulse read as a new demand rather than as noise.
    var cycleLength: Double {
        switch self {
        case .synchronized: 1.5
        case .accent: 1.3
        case .alert: 1.2
        case .heartbeat: 1.0
        case .quick: 0.7
        case .rapid: 1.2
        case .sos: 3.4
        case .staccato: 1.4
        case .symphony: 2.0
        case .none: 1.0
        }
    }
}
