import SwiftUI

/// Scene 9 — the payoff. The lock opens, the three mechanics land one by one,
/// and only then does the commitment become tappable.
struct SolutionPage: View {
    let isActive: Bool
    let onCommit: () -> Void

    @State private var isUnlocked = false
    @State private var bulletsShown = false
    @State private var ctaShown = false

    private let bullets: [(icon: String, text: String)] = [
        ("iphone.slash", "your distracting apps lock until you show up."),
        ("checkmark.shield.fill", "location and Apple Health verify it. no fake check-ins."),
        ("moon.fill", "they lock again at night, so tomorrow starts rested."),
    ]

    var body: some View {
        OnboardingScene(topAnchor: 0.09, heroMaxHeightFraction: 0.34) {
            VStack(alignment: .leading, spacing: 14) {
                lockBadge

                AccentedText(
                    full: "so we take the decision away.",
                    highlighted: ["take the decision away."],
                    size: 32
                )
            }
            .sceneElement(.headline)
        } hero: {
            IllustrationView(illustration: .celebrationJump)
                .sceneElement(.hero)
        } footer: {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                        bulletRow(icon: bullet.icon, text: bullet.text)
                            .opacity(bulletsShown ? 1 : 0)
                            .offset(y: bulletsShown ? 0 : 8)
                            .animation(
                                Theme.settle.delay(Double(index) * 0.09),
                                value: bulletsShown
                            )
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        Haptics.commit()
                        onCommit()
                    } label: {
                        Text("let's lock it in")
                    }
                    .buttonStyle(PrimaryCTAStyle(isEnabled: true))

                    Text("you can adjust everything later.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .opacity(ctaShown ? 1 : 0)
                .offset(y: ctaShown ? 0 : 10)
            }
            .sceneElement(.footer)
        }
        .task(id: isActive) {
            guard isActive else {
                isUnlocked = false
                bulletsShown = false
                ctaShown = false
                return
            }

            try? await Task.sleep(for: .milliseconds(680))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { isUnlocked = true }
            Haptics.soft()
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(Theme.settle) { bulletsShown = true }
            try? await Task.sleep(for: .milliseconds(560))
            withAnimation(Theme.settle) { ctaShown = true }
        }
    }

    /// The single micro-payoff of the scene: the lock opens.
    private var lockBadge: some View {
        HStack(spacing: 9) {
            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .contentTransition(.symbolEffect(.replace))

            Text(isUnlocked ? "unlocked" : "locked")
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .contentTransition(.opacity)
        }
        .foregroundStyle(isUnlocked ? Theme.accent : Theme.inkTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            (isUnlocked ? Theme.accent : Theme.inkTertiary).opacity(0.11),
            in: .capsule
        )
        .accessibilityHidden(true)
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 27, height: 27)
                .background(Theme.accent.opacity(0.11), in: .circle)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
