import SwiftUI

/// The exit that is always available.
///
/// "Can't today" is never removed, never hidden behind a confirmation maze, and
/// never punished. Illness, injury, a child up all night, a shift that moved —
/// these are not failures of discipline, and an app that treats them as such is
/// one people lie to.
///
/// The only thing that changes past the allowance is how deliberate the decision
/// has to be. One extra screen, three visible doors, no guilt language, and
/// nothing blocked.
struct CantTodayView: View {
    let voice: SessionVoice
    let hasEasySkipRemaining: Bool
    let skipsUsed: Int
    let allowance: Int
    let isComebackModeOn: Bool
    let onReschedule: () -> Void
    let onQuickWorkout: () -> Void
    let onTakeTheDayOff: () -> Void
    let onBack: () -> Void

    var body: some View {
        MorningScreen(trailingTitle: "Back", trailingAction: onBack) {
            VStack(spacing: 22) {
                HaloedGlyph(
                    systemName: hasEasySkipRemaining ? "heart.fill" : "arrow.triangle.branch",
                    size: 82
                )
                .frame(height: 158)

                heading

                actions

                if isComebackModeOn { comebackNote }

                allowanceNote
            }
        } footer: {
            EmptyView()
        }
    }

    // MARK: - Copy

    private var heading: some View {
        VStack(spacing: 8) {
            Text(hasEasySkipRemaining ? "life happens." : "want to keep some momentum today?")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                hasEasySkipRemaining
                    ? "the next opportunity still counts."
                    : "you've used your \(allowance == 1 ? "easy skip" : "\(allowance) easy skips") this month."
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// All three options stay on screen in both branches. Past the allowance the
    /// *order* changes — the home workout is promoted — but nothing is taken
    /// away.
    @ViewBuilder
    private var actions: some View {
        if hasEasySkipRemaining {
            VStack(spacing: 12) {
                MorningChoiceRow(
                    title: "reschedule within 24h",
                    subtitle: voice.rescheduleDetail,
                    systemImage: "calendar.badge.clock"
                ) {
                    onReschedule()
                }

                MorningChoiceRow(
                    title: "quick workout",
                    subtitle: "keeps your momentum",
                    systemImage: "house.fill"
                ) {
                    onQuickWorkout()
                }

                MorningChoiceRow(
                    title: "take today off",
                    subtitle: voice.dayOffDetail,
                    systemImage: "moon.zzz.fill"
                ) {
                    onTakeTheDayOff()
                }
            }
        } else {
            VStack(spacing: 12) {
                MorningPrimaryButton(
                    title: "20-min workout at home",
                    systemImage: "house.fill",
                    trailingImage: nil
                ) {
                    onQuickWorkout()
                }

                MorningChoiceRow(
                    title: "reschedule within 24h",
                    subtitle: voice.rescheduleDetail,
                    systemImage: "calendar.badge.clock"
                ) {
                    onReschedule()
                }

                MorningChoiceRow(
                    title: "I really need today off",
                    subtitle: "that's allowed too",
                    systemImage: "moon.zzz.fill"
                ) {
                    onTakeTheDayOff()
                }
            }
        }
    }

    private var comebackNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("comeback mode is on")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("your next realistic session is already set. nothing to make up.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.07), in: .rect(cornerRadius: 16))
    }

    /// States the rule as what it is: a product decision about friction, not a
    /// scientific threshold.
    private var allowanceNote: some View {
        Text("\(skipsUsed) of \(allowance) easy skips used in the last 28 days. this is just how GymLock paces things — not a rule about your body.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.inkTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }
}
