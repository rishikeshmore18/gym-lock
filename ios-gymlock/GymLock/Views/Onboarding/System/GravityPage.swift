import SwiftUI

/// System screen 15 — what the gap actually costs.
///
/// This is the emotional hinge of the whole flow, and it is built entirely out
/// of the user's own two numbers. Every figure is arithmetic on `target` minus
/// `current`, with the one assumption behind it printed on the screen. There are
/// no invented "progress lost" percentages and no physiological claims, because
/// a number the user can verify in their head is far heavier than one they have
/// to take on faith.
///
/// A user already meeting their target sees a different screen entirely. Showing
/// them a zero, or worse a negative, would be both wrong and insulting.
struct GravityPage: View {
    let isActive: Bool
    let name: String
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false
    @State private var countProgress: Double = 0
    @State private var heroShown = false

    private var profile: OnboardingProfile { store.profile }

    var body: some View {
        SystemScene(topAnchor: 0.08, contentSpacing: 16) {
            SceneHeading(
                title: profile.isAlreadyOnTarget
                    ? "\(name), you're already hitting your target."
                    : "\(name), here's what the gap actually costs.",
                highlighted: profile.isAlreadyOnTarget
                    ? ["already hitting your target."]
                    : ["the gap actually costs."],
                size: 28
            )
            .staggered(0, isShown: contentShown)
        } content: {
            if profile.isAlreadyOnTarget {
                onTargetContent
            } else {
                gapContent
            }
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(6, isShown: heroShown)
        }
        .task(id: isActive) { await run() }
    }

    // MARK: - The gap

    private var gapContent: some View {
        VStack(spacing: 14) {
            targetVersusCurrent
                .staggered(1, isShown: contentShown)

            HStack(spacing: 10) {
                statBlock(
                    value: profile.monthlyMissedWorkouts,
                    decimals: 1,
                    caption: "planned workouts missed / month"
                )
                statBlock(
                    value: profile.monthlyMissedMinutes,
                    decimals: 0,
                    caption: "minutes of planned training / month"
                )
            }
            .staggered(2, isShown: contentShown)

            // The yearly figure gets the whole width and its own beat. Months
            // are easy to shrug off; a year is not.
            heroBlock
                .staggered(3, isShown: contentShown)

            HStack(spacing: 10) {
                statBlock(
                    value: profile.yearlyMissedWorkouts,
                    decimals: 0,
                    caption: "planned workouts / year"
                )
                statBlock(
                    value: profile.yearlyMissedDays,
                    decimals: 1,
                    caption: "full days of planned gym time / year"
                )
            }
            .staggered(4, isShown: contentShown)

            Text("based on a \(Int(OnboardingProfile.minutesPerWorkout))-minute planned workout")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity)
                .staggered(5, isShown: contentShown)
        }
    }

    private var targetVersusCurrent: some View {
        HStack(spacing: 10) {
            miniStat(
                title: "your target",
                value: "\(profile.targetWorkoutsPerWeek) / week",
                tint: Theme.ink
            )
            miniStat(
                title: "your current average",
                value: "\(profile.currentWorkoutsPerWeek) / week",
                tint: Theme.inkSecondary
            )
        }
    }

    private func miniStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
    }

    private func statBlock(value: Double, decimals: Int, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CountingNumber(
                value: value * countProgress,
                decimals: decimals,
                size: 30,
                prefix: "≈"
            )

            Text(caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(minHeight: 92, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }

    private var heroBlock: some View {
        HStack(alignment: .center, spacing: 14) {
            CountingNumber(
                value: profile.yearlyMissedHours * countProgress,
                decimals: 0,
                size: 52,
                color: .white,
                prefix: "≈"
            )

            Text("hours of planned training,\nevery year.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.accent, in: .rect(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Already on target

    private var onTargetContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            targetVersusCurrent
                .staggered(1, isShown: contentShown)

            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)

                Text("you're already hitting your target.")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text("GymLock's job is to protect it — the weeks that get busy are the ones that quietly take it back.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Theme.accent, in: .rect(cornerRadius: Theme.cardRadius))
            .staggered(2, isShown: contentShown)
        }
    }

    // MARK: - Timeline

    private func run() async {
        guard isActive else {
            contentShown = false
            heroShown = false
            countProgress = 0
            return
        }

        countProgress = 0

        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        guard !profile.isAlreadyOnTarget else {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.settle) { heroShown = true }
            return
        }

        // Every figure climbs off the same driver, so the whole board
        // accumulates together rather than as five separate tickers.
        try? await Task.sleep(for: .milliseconds(620))
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.15, 0.85, 0.2, 1, duration: 1.5)) {
            countProgress = 1
        }

        // Lands as the yearly number finishes climbing.
        try? await Task.sleep(for: .milliseconds(1400))
        guard !Task.isCancelled else { return }
        Haptics.medium()

        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { heroShown = true }
    }
}
