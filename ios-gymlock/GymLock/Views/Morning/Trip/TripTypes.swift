import CoreLocation
import SwiftUI

/// Where the trip stands. Derived by `TripView` from the session's route, never stored.
enum TripPhase: Equatable {
    /// The window is open and the phone has not seen the user leave yet.
    case atHome
    /// Left home (detected or "I've left"), not at the gym yet.
    case onTheWay
    /// Inside the gym area, the two-minute dwell is running.
    case verifying
    /// Arrival confirmed. Plays the short finale, then the arrival screen takes over.
    case verified

    var hasLeft: Bool { self != .atHome }
}

/// Everything a trip style draws that is not map geometry, already derived and
/// already worded. The styles only lay it out and animate it.
struct TripFrame {
    var phase: TripPhase
    /// Seconds to the session deadline (the gym time). Never negative.
    var remaining: TimeInterval
    /// The gym time, e.g. "15:51". Nil when the session has no deadline.
    var gymBy: String?
    /// "2.4 km · 9 min", "850 m", or nil when there is no route yet.
    var distanceLine: String?
    var gymName: String?
    /// SessionVoice heading and support line for this phase.
    var heading: String
    var support: String
    /// True once the style should play its entry: straight away, or after the
    /// wake page's "Let's go" when that page is on top.
    var entryStarted: Bool
    /// 0...1 through the two-minute dwell. Read it with the frame's own date.
    var verifyProgress: (Date) -> Double

    /// Seconds of dwell still to go at `date`.
    func verifySecondsLeft(at date: Date) -> Int {
        Int((ArrivalTuning.dwellSeconds * (1 - verifyProgress(date))).rounded(.up))
    }
}

/// The doors out of the trip screen.
struct TripActions {
    /// "I've left": the manual fallback when the phone has not noticed yet.
    var left: () -> Void
    /// "End": the can't-today flow.
    var end: () -> Void
    /// "having trouble?" while verifying.
    var trouble: () -> Void
    /// The verified finale has finished; show the arrival screen.
    var finaleDone: () -> Void
}

/// Words shared by both styles. Exact copy lives here so the two never drift.
enum TripCopy {
    static let youreHere = "you're here."
    static let verifying = "verifying"
    static let verified = "verified"
    static let stayInside = "stay inside for 2 minutes. your apps unlock on their own."
    static let unlocked = "apps unlocked. go train."
    static let leftButton = "I've left"
    static let statusLeft = "left home"
    static let statusNext = "gym next"
    static let trouble = "having trouble?"
    static func gymBy(_ time: String) -> String { "gym by \(time)" }
}

enum TripFormat {
    /// "34:20", "07:05", "127:00".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// "1:42" for the dwell.
    static func short(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        return minutes >= 1 ? "\(minutes) minutes" : "\(total) seconds"
    }

    /// "2.4 km · 9 min" or "1.5 mi · 9 min", following the phone's unit system.
    /// The time is left off when it is not known.
    static func distanceLine(metres: CLLocationDistance?, seconds: TimeInterval?) -> String? {
        guard let metres else { return nil }
        var parts = [distance(metres)]
        if let seconds {
            parts.append("\(max(1, Int((seconds / 60).rounded(.up)))) min")
        }
        return parts.joined(separator: " · ")
    }

    static func distance(_ metres: CLLocationDistance) -> String {
        if Locale.current.measurementSystem == .metric {
            if metres < 1_000 { return "\(max(10, Int((metres / 10).rounded()) * 10)) m" }
            return String(format: "%.1f km", metres / 1_000)
        }
        let feet = metres * 3.28084
        if feet < 1_000 { return "\(max(10, Int((feet / 10).rounded()) * 10)) ft" }
        return String(format: "%.1f mi", metres / 1_609.344)
    }
}

/// The one ink button of the trip screen. Ink fill, white label (UI-RULES §1).
struct TripPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.ink, in: .rect(cornerRadius: Theme.controlRadius))
            .contentShape(.rect(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(TripPressStyle())
    }
}

/// Press feedback for the trip's own buttons: a short scale, asymmetric (UI-RULES §5.6).
struct TripPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                configuration.isPressed
                    ? Animation.spring(response: 0.18, dampingFraction: 1)
                    : Animation.spring(response: 0.28, dampingFraction: 0.58),
                value: configuration.isPressed
            )
    }
}

/// "left home · gym next": the quiet row that replaces "I've left".
struct TripStatusRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Text(TripCopy.statusLeft)
            Rectangle().fill(Theme.ink.opacity(0.28)).frame(width: 1, height: 16)
            Text(TripCopy.statusNext)
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .accessibilityElement(children: .combine)
    }
}
