#if DEBUG
import SwiftUI

// MARK: - Dial frame

/// The shared shell of the three dials: a ring, a value in the middle and a
/// caption under it. Read-only unless a control sits beneath it.
private struct SimDialShell<Ring: View>: View {
    let title: String
    let value: String
    let caption: String
    let isActive: Bool
    @ViewBuilder var ring: () -> Ring

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.heavy))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ZStack {
                ring()
                Text(value)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? Theme.ink : Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(14)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 120)

            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value), \(caption)")
    }
}

// MARK: - Time dial

/// A 24 hour face with one coral mark at the scenario's time.
struct SimTimeDial: View {
    let time: TimeOfDay?
    let caption: String

    var body: some View {
        SimDialShell(title: "Time", value: time?.clockString ?? "n/a", caption: caption, isActive: time != nil) {
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Circle()
                        .strokeBorder(Theme.border, lineWidth: 6)
                    ForEach(0..<24, id: \.self) { hour in
                        Capsule()
                            .fill(hour % 6 == 0 ? Theme.inkTertiary : Theme.border)
                            .frame(width: 2, height: hour % 6 == 0 ? 7 : 4)
                            .offset(y: -size / 2 + 12)
                            .rotationEffect(.degrees(Double(hour) * 15))
                    }
                    if let time {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 12, height: 12)
                            .offset(y: -size / 2 + 3)
                            .rotationEffect(.degrees(Double(time.hour * 60 + time.minute) / 4))
                    }
                }
                .frame(width: size, height: size)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

// MARK: - Distance ring

/// Four steps from home to a confirmed arrival. Display only.
struct SimDistanceRing: View {
    let reading: SimJourneyReading?

    private var progress: Double {
        guard let reading else { return 0 }
        return Double(reading.state.rawValue) / Double(SimJourney.confirmed.rawValue)
    }

    var body: some View {
        SimDialShell(
            title: "Distance",
            value: reading?.state.title ?? "n/a",
            caption: reading.map { "\($0.verified ? "Verified" : "Not verified") · \($0.note)" } ?? "Not part of this test",
            isActive: reading != nil
        ) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.border, lineWidth: 6)
                Circle()
                    .inset(by: 3)
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if reading?.verified == true {
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
                        .padding(12)
                }
            }
        }
    }
}

// MARK: - Time at gym

/// Minutes at the gym against the 20 minute mark the proof rules use. The
/// mark is the rules' own constant; the dial never decides anything.
struct SimGymDialView: View {
    let minutes: Int?
    let caption: String

    private var fraction: Double {
        guard let minutes else { return 0 }
        return min(Double(minutes) / Double(SimGymDial.range.upperBound), 1)
    }

    var body: some View {
        SimDialShell(
            title: "At gym",
            value: minutes.map { "\($0) min" } ?? "n/a",
            caption: caption,
            isActive: minutes != nil
        ) {
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let markAngle = Double(SimGymDial.mark) / Double(SimGymDial.range.upperBound) * 360
                ZStack {
                    Circle()
                        .strokeBorder(Theme.border, lineWidth: 6)
                    Circle()
                        .inset(by: 3)
                        .trim(from: 0, to: fraction)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: 2.5, height: 12)
                        .offset(y: -size / 2 + 3)
                        .rotationEffect(.degrees(markAngle))
                }
                .frame(width: size, height: size)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}
#endif
