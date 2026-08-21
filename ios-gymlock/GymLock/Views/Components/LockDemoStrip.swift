import SwiftUI

/// The row of app icons shared by the lock and unlock demonstrations.
///
/// Screens 18 and 19 are one continuous idea split across two pages, so they
/// draw the strip from the same component with the same geometry. Only
/// `lockProgress` differs, which is what lets the icons appear to stay put while
/// the state around them changes.
struct LockDemoStrip: View {
    let apps: [DistractingApp]
    /// 0 = available, 1 = locked.
    let lockProgress: Double
    var iconSize: CGFloat = 58

    var body: some View {
        HStack(spacing: 18) {
            ForEach(apps) { app in
                VStack(spacing: 8) {
                    AppGlyph(app: app, size: iconSize, lockProgress: lockProgress)
                        // The subtle shrink on locking, and the recovery to full
                        // size on unlocking, is what stops the colour change
                        // from reading as a simple crossfade.
                        .scaleEffect(1 - 0.04 * lockProgress)

                    Text(app.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            Theme.inkSecondary.mix(with: Theme.inkTertiary, by: lockProgress)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: 92)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// One "waiting / verified" line in the demonstration.
struct VerificationRow: View {
    let icon: String
    let title: String
    let isVerified: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isVerified ? .white : Theme.inkTertiary)
                .frame(width: 30, height: 30)
                .background(isVerified ? Theme.accent : Theme.surfaceMuted, in: .circle)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            if isVerified {
                HStack(spacing: 5) {
                    Text("verified")
                        .font(.system(size: 14, weight: .bold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(Theme.accent)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.8))
                )
            } else {
                Text("waiting…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            isVerified ? Theme.accent.opacity(0.07) : Theme.surface,
            in: .rect(cornerRadius: Theme.controlRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(isVerified ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1)
        }
        .animation(Theme.settle, value: isVerified)
        .accessibilityElement(children: .combine)
    }
}

extension OnboardingProfile {
    /// The apps used in the lock demonstration.
    ///
    /// Two is the right number to show: enough to read as "your apps", few
    /// enough that both icons stay large enough to recognise. `Other` is dropped
    /// because a generic tile teaches nothing.
    var demoApps: [DistractingApp] {
        let chosen = orderedDistractingApps.filter { $0 != .other }
        guard !chosen.isEmpty else { return [.instagram, .tiktok] }
        return Array(chosen.prefix(2))
    }
}
