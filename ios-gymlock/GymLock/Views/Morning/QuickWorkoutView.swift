import SwiftUI

/// The home fallback picker.
///
/// The line that matters on this screen is the small one: a gym visit will not
/// be counted today, but momentum will. Blurring those two would make the
/// numbers meaningless, and the numbers are the only reason the streak has any
/// weight.
struct QuickWorkoutView: View {
    let homeWorkoutsUsed: Int
    let isAtCap: Bool
    let onStart: (Int) -> Void
    let onBack: () -> Void

    /// 20 is the default (FLOW, Flow 4); the 15-minute option is gone.
    private static let options = HomeWorkoutRules.options
    private static let recommended = HomeWorkoutRules.defaultMinutes

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

                capNote

                honestyNote
            }
        } footer: {
            // PLACEHOLDER UI: designed in Step 3
            if isAtCap {
                MorningPrimaryButton(
                    title: HomeWorkoutRules.capMessage,
                    systemImage: "house.fill",
                    trailingImage: nil,
                    isEnabled: false
                ) {}
            } else {
                MorningPrimaryButton(
                    title: "start home workout",
                    systemImage: "play.fill"
                ) {
                    onStart(selection)
                }
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

    /// The monthly limit, said once, without apology.
    private var capNote: some View {
        Text("\(homeWorkoutsUsed) of \(HomeWorkoutRules.monthlyLimit) home workouts used this month.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.inkTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The distinction, stated plainly and without apology.
    private var honestyNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: .circle)

            Text("a home workout counts as a full workout once it's verified.")
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
/// credit, no guilt, no argument. The proof check happens after the timer, on
/// the screen that follows.
struct QuickWorkoutActiveView: View {
    let session: GymSession
    let onFinish: (Bool) -> Void

    @State private var isConfirmingEnd = false

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

                MorningPrimaryButton(
                    title: "I'm done",
                    systemImage: "checkmark",
                    trailingImage: nil,
                    isEnabled: true
                ) {
                    finish(completed: true)
                }

                Text("when the timer ends, apple health or a progress photo counts it.")
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

    private func finish(completed: Bool) {
        onFinish(completed)
    }
}
