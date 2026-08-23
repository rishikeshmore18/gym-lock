import SwiftUI

/// The live window: how long is left to be standing in the gym.
///
/// The number on this screen is derived from an absolute deadline stored on the
/// session, never from a timer counting down in memory. Kill the app, reboot the
/// phone, or leave it in a pocket for twenty minutes and reopening shows the
/// truth — not a fresh 45:00.
///
/// `TimelineView` drives the redraw, which means the clock stays correct even
/// when the app has been suspended and no code of ours was running.
struct GymWindowView: View {
    let session: GymSession
    let lockedApps: [DistractingApp]
    let onDeparted: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(trailingTitle: "End", trailingAction: onEnd)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(at: context.date)
                }
            }
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let remaining = session.remaining(at: now)
        let fraction = 1 - session.elapsedFraction(at: now)
        let stage = session.stage(at: now)
        let hasLeft = session.departedAt != nil

        ScrollView {
            VStack(spacing: 20) {
                heading(hasLeft: hasLeft)

                ZStack {
                    CountdownRing(remainingFraction: fraction, size: 268)

                    VStack(spacing: 2) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.bottom, 6)

                        Text(Self.clock(remaining))
                            .font(.system(size: 56, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText(countsDown: true))

                        Text("time remaining")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(height: 286)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time remaining")
                .accessibilityValue(Self.spokenClock(remaining))

                PreparationRail(
                    current: stage,
                    getReadyMinutes: session.getReadyMinutes,
                    travelMinutes: session.travelMinutes
                )

                if !hasLeft {
                    MorningPrimaryButton(
                        title: "I've left",
                        systemImage: "figure.walk.departure",
                        trailingImage: nil
                    ) {
                        onDeparted()
                    }
                }

                if !lockedApps.isEmpty { lockPreview }

                encouragement(hasLeft: hasLeft)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 6)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Pieces

    private func heading(hasLeft: Bool) -> some View {
        VStack(spacing: 4) {
            Text(hasLeft ? "on your way" : "gym window started")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text(hasLeft ? "finish the trip." : "stay locked in. you've got this.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// A preview of what the user asked to have locked.
    ///
    /// Labelled as a plan rather than as a fact, because nothing is being
    /// blocked yet. Claiming otherwise would be found out the first time
    /// somebody opened Instagram during their window.
    private var lockPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("your lock list")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(lockedApps.count) apps · blocking arrives soon")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ForEach(lockedApps.prefix(6)) { app in
                    AppGlyph(app: app, size: 42, lockProgress: 0.85)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 20)
    }

    private func encouragement(hasLeft: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: hasLeft ? "flame.fill" : "bolt.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasLeft ? "you're moving" : "stay locked in")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(hasLeft ? "the hard part is behind you." : "you're building discipline.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.07), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
        }
    }

    // MARK: - Formatting

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func spokenClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        if minutes >= 1 { return "\(minutes) minutes" }
        return "\(total) seconds"
    }
}
