import SwiftUI

/// A small, static picture of an alarm screen style, for the picker only.
///
/// This is not the ringing screen and does nothing. It is kept as a pure
/// view with no environment, so its internals can be swapped for a scaled
/// render of the real screens once they exist without touching the picker.
///
/// Drawn on a fixed canvas that scales with its width, so it looks the same
/// on an SE and a Pro Max. Like an export surface, it does not grow with
/// Dynamic Type; the labels under it do.
struct AlarmScreenPreview: View {
    let style: AlarmScreenStyle
    /// The user's own alarm time, already formatted, so the preview shows
    /// something true rather than a sample.
    let time: String

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                switch style {
                case .sunrise: sunriseBackdrop(size)
                case .focus: focusBackdrop(size)
                }
                content(size)
            }
            .frame(width: size.width, height: size.height)
        }
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .accessibilityHidden(true)
    }

    // MARK: Backdrops

    /// Light at the top, dawn through the middle, dark underneath. The warm
    /// band and the sun are this style's one accent.
    private func sunriseBackdrop(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Theme.surface, location: 0),
                    .init(color: Theme.surface, location: 0.2),
                    .init(color: Theme.accentWash, location: 0.42),
                    .init(color: Theme.accentWarm, location: 0.6),
                    .init(color: Theme.night, location: 0.8),
                    .init(color: Theme.logoBackdrop, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Theme.accentWarm)
                .frame(width: size.width * 0.34)
                .position(x: size.width / 2, y: size.height * 0.64)

            // The ground the sun is rising behind.
            Ellipse()
                .fill(Theme.night)
                .frame(width: size.width * 2.2, height: size.height * 0.5)
                .position(x: size.width / 2, y: size.height * 0.9)
        }
    }

    /// Near-black, with the edge of a dark sphere catching a thin rim of
    /// light at the foot of the frame.
    private func focusBackdrop(_ size: CGSize) -> some View {
        ZStack {
            Theme.logoBackdrop

            Circle()
                .fill(Theme.ink)
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1.5
                    )
                }
                .frame(width: size.width * 1.7, height: size.width * 1.7)
                .position(x: size.width / 2, y: size.height * 0.62 + size.width * 0.85)
        }
    }

    // MARK: Content

    private func content(_ size: CGSize) -> some View {
        let w = size.width
        let isSunrise = style == .sunrise

        return VStack(spacing: 0) {
            Text("GYMLOCK")
                .font(.system(size: w * 0.045, weight: .semibold))
                .tracking(w * 0.012)
                .foregroundStyle(isSunrise ? Theme.inkTertiary : .white.opacity(0.55))
                .padding(.top, size.height * 0.08)

            Text(time)
                .font(.system(size: w * 0.3, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isSunrise ? Theme.ink : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, w * 0.06)
                .padding(.top, size.height * 0.02)

            Spacer(minLength: 0)

            Text("i'm up")
                .font(.system(size: w * 0.075, weight: .semibold))
                .foregroundStyle(isSunrise ? Theme.ink : .white)
                .frame(width: w * 0.72, height: size.height * 0.075)
                .background(isSunrise ? Theme.surface : Theme.accent, in: .capsule)

            Text("snooze")
                .font(.system(size: w * 0.055, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, size.height * 0.025)
                .padding(.bottom, size.height * 0.06)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One choice in the alarm screen picker: the preview, a selection mark
/// under it, and its name and mood.
///
/// The preview is content, so it is never glass. Selection is quiet: a thin
/// ink outline around the preview and a filled mark under it. Ink, not
/// coral, because the previews already carry the accent.
struct AlarmScreenPreviewCard: View {
    let style: AlarmScreenStyle
    let time: String
    let isSelected: Bool

    /// The gap between the preview and its selection outline.
    private static let ringGap: CGFloat = 5

    var body: some View {
        VStack(spacing: 14) {
            AlarmScreenPreview(style: style, time: time)
                .aspectRatio(9 / 19.5, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
                .padding(Self.ringGap)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius + Self.ringGap)
                        .strokeBorder(Theme.ink, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                Circle()
                    .strokeBorder(Theme.border, lineWidth: 1.5)
                    .opacity(isSelected ? 0 : 1)
                Circle()
                    .fill(Theme.ink)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.surface)
                    }
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: 24, height: 24)

            VStack(spacing: 3) {
                Text(style.label)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(style.mood)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
        }
        // A colour and opacity flip only: nothing scales on selection.
        .animation(Theme.stateChange, value: isSelected)
    }
}

#if DEBUG
#Preview("Alarm screen previews") {
    HStack(spacing: 14) {
        AlarmScreenPreviewCard(style: .sunrise, time: "7:00", isSelected: true)
        AlarmScreenPreviewCard(style: .focus, time: "7:00", isSelected: false)
    }
    .padding(20)
    .background(Theme.canvas)
}
#endif
