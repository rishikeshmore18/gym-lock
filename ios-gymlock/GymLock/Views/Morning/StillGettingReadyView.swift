import SwiftUI

/// The one nudge, shown at roughly three-quarters of the preparation window.
///
/// It appears once and never again. The user has already committed, so this is
/// not another sales pitch — it is a small, warm check that offers three honest
/// ways forward and then gets out of the way.
///
/// The extension is capped and single-use. An unlimited "+10" loop would let a
/// morning dissolve one tap at a time, which is precisely the failure mode
/// GymLock exists to interrupt.
struct StillGettingReadyView: View {
    let session: GymSession
    let onLeaving: () -> Void
    let onExtend: () -> Void
    let onQuickWorkout: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(trailingTitle: "Done", trailingAction: onDismiss)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ScrollView {
                        VStack(spacing: 22) {
                            dial(at: context.date)
                            heading
                            actions
                            footnote
                        }
                        .padding(.horizontal, Theme.pageMargin)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    // MARK: - Pieces

    private func dial(at now: Date) -> some View {
        let remaining = session.remaining(at: now)
        let fraction = 1 - session.elapsedFraction(at: now)
        let minutes = max(0, Int((remaining / 60).rounded(.up)))

        return ZStack {
            CountdownRing(remainingFraction: fraction, size: 240)

            VStack(spacing: -2) {
                Text("Leaving in")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%02d", minutes))
                        .font(.system(size: 62, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("min")
                        .font(.system(size: 22, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)

                Text("to reach your gym on time")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .frame(width: 170)
        }
        .frame(height: 252)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Leaving in \(minutes) minutes")
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text("still getting ready?")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text("you've got this. let's make today a good one.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            MorningPrimaryButton(
                title: "I'm leaving",
                systemImage: "figure.run",
                trailingImage: nil
            ) {
                onLeaving()
            }

            // Only offered while an extension is still available. Once used, the
            // row disappears rather than sitting there disabled — a dead button
            // invites tapping it.
            if session.canExtend {
                MorningChoiceRow(
                    title: "+\(GymSession.defaultExtensionMinutes) min",
                    subtitle: "one extension, then the window closes",
                    systemImage: "clock.fill"
                ) {
                    onExtend()
                }
            }

            MorningChoiceRow(
                title: "20-min workout at home",
                subtitle: "keep today's momentum",
                systemImage: "house.fill"
            ) {
                onQuickWorkout()
            }
        }
    }

    private var footnote: some View {
        HStack(spacing: 7) {
            Image(systemName: "shield.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(
                session.canExtend
                    ? "your workout is locked in"
                    : "you've used today's extension"
            )
            .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Theme.inkTertiary)
    }
}
