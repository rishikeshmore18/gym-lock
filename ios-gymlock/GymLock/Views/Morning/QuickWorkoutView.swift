import SwiftUI

/// The home fallback picker.
///
/// The line that matters on this screen is the small one: a gym visit will not
/// be counted today, but momentum will. Blurring those two would make the
/// numbers meaningless, and the numbers are the only reason the streak has any
/// weight.
struct QuickWorkoutView: View {
    let onStart: (Int) -> Void
    let onBack: () -> Void

    /// 20 is the recommended middle: long enough to be a workout, short enough
    /// that nobody talks themselves out of it.
    private static let options = [15, 20, 30]
    private static let recommended = 20

    @State private var selection = QuickWorkoutView.recommended

    var body: some View {
        MorningScreen(trailingTitle: "Back", trailingAction: onBack) {
            VStack(spacing: 22) {
                modePill

                VStack(spacing: 8) {
                    Text("plans changed?")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    Text("keep today's momentum.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }

                houseIllustration

                Text("pick your quick workout")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)

                options

                honestyNote
            }
        } footer: {
            MorningPrimaryButton(
                title: "start quick workout",
                systemImage: "play.fill"
            ) {
                onStart(selection)
            }
        }
    }

    // MARK: - Pieces

    private var modePill: some View {
        HStack(spacing: 7) {
            Image(systemName: "house.fill")
                .font(.system(size: 11, weight: .bold))
            Text("HOME-WORKOUT MODE")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.7)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.surface, in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1) }
    }

    private var houseIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Theme.accentWash, Theme.accentWash.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 22) {
                Image(systemName: "house.fill")
                    .font(.system(size: 62, weight: .bold))
                    .foregroundStyle(Theme.accentWarm)

                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Theme.accent.opacity(0.7))
                    .offset(y: 14)
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }

    private var options: some View {
        HStack(spacing: 10) {
            ForEach(Self.options, id: \.self) { minutes in
                optionCard(minutes)
            }
        }
    }

    private func optionCard(_ minutes: Int) -> some View {
        let isSelected = selection == minutes
        let isRecommended = minutes == Self.recommended

        return Button {
            guard selection != minutes else { return }
            withAnimation(Theme.stateChange) { selection = minutes }
            Haptics.selection()
        } label: {
            VStack(spacing: 6) {
                Text("\(minutes)")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Theme.accent : Theme.ink)

                Text("min")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)

                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.inkTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        (isSelected ? Theme.accent : Theme.inkTertiary).opacity(0.12),
                        in: .circle
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.surface, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? Theme.accent : Theme.border,
                        lineWidth: isSelected ? 1.8 : 1
                    )
            }
            .overlay(alignment: .top) {
                if isRecommended {
                    Text("Recommended")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.accent, in: .capsule)
                        .offset(y: -9)
                }
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minute workout\(isRecommended ? ", recommended" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The distinction, stated plainly and without apology.
    private var honestyNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: .circle)

            Text("gym visit won't count today, but your momentum will.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Active workout

/// The running home workout.
///
/// Ending early is always allowed and is recorded honestly as unfinished — no
/// credit, no guilt, no argument.
struct QuickWorkoutActiveView: View {
    let session: GymSession
    let verifier: any WorkoutVerificationProviding
    let onFinish: (Bool) -> Void

    @State private var isConfirmingEnd = false
    @State private var checkMessage: String?

    private var totalMinutes: Int { session.quickWorkoutMinutes ?? 20 }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(
                    trailingTitle: "End",
                    trailingAction: { isConfirmingEnd = true },
                    leadingSymbol: "house.fill"
                )

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    body(at: context.date)
                }
            }
        }
        .confirmationDialog(
            "End this workout?",
            isPresented: $isConfirmingEnd,
            titleVisibility: .visible
        ) {
            Button("I finished it") { finish(completed: true) }
            Button("End without finishing", role: .destructive) { onFinish(false) }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Stopping early is fine. It just won't be recorded as finished.")
        }
    }

    @ViewBuilder
    private func body(at now: Date) -> some View {
        let deadline = session.quickWorkoutDeadline ?? now
        let started = session.quickWorkoutStartedAt ?? now
        let total = max(1, deadline.timeIntervalSince(started))
        let remaining = max(0, deadline.timeIntervalSince(now))
        let fraction = remaining / total
        let isDone = remaining <= 0

        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text(isDone ? "time's up" : "\(totalMinutes)-minute workout")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(isDone ? "nice. log it and keep your momentum." : "move at your own pace.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }

                ZStack {
                    CountdownRing(remainingFraction: fraction, size: 262)

                    VStack(spacing: 2) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.bottom, 6)

                        Text(GymWindowView.clock(remaining))
                            .font(.system(size: 54, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText(countsDown: true))

                        Text("remaining")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(height: 280)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Workout time remaining")
                .accessibilityValue(GymWindowView.spokenClock(remaining))

                if let checkMessage {
                    Text(checkMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                MorningPrimaryButton(
                    title: "I'm done",
                    systemImage: "checkmark",
                    trailingImage: nil,
                    isEnabled: true
                ) {
                    finish(completed: true)
                }

                Text(verificationNote)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 6)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
    }

    /// States exactly how this workout is being confirmed. When no real
    /// verification exists, it says so rather than implying a sensor is
    /// watching.
    private var verificationNote: String {
        verifier.isAvailable
            ? "checked by \(verifier.methodDescription)."
            : "self-reported for now — workout verification is coming."
    }

    private func finish(completed: Bool) {
        guard completed else {
            onFinish(false)
            return
        }

        Task {
            let started = session.quickWorkoutStartedAt ?? Date()
            let outcome = await verifier.verifyWorkout(
                startedAt: started,
                minimumMinutes: totalMinutes
            )

            switch outcome {
            case .verified, .unavailable:
                // Unavailable means nobody is checking, so the user's own word
                // stands. That is honest; inventing a sensor reading would not
                // be.
                onFinish(true)

            case let .notEnoughEvidence(message):
                checkMessage = message
            }
        }
    }
}
