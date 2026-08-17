import SwiftUI

/// Page 7 — the payoff. GymLock is named as the mechanism that breaks the loop.
struct SolutionPage: View {
    let isActive: Bool
    let onCommit: () -> Void

    @State private var headlineShown = false
    @State private var bulletsShown = false
    @State private var ctaShown = false

    private let bullets: [(icon: String, text: String)] = [
        ("lock.fill", "lock your distracting apps until you verify the gym."),
        ("checkmark.shield.fill", "location + Apple Health. no fake check-ins."),
        ("moon.fill", "lock them again at night until bedtime."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 28)

            AccentedText(
                full: "GymLock is the forcing function.",
                highlighted: ["forcing function"],
                size: 34
            )
            .opacity(headlineShown ? 1 : 0)
            .offset(y: headlineShown ? 0 : 12)

            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                    bulletRow(icon: bullet.icon, text: bullet.text)
                        .opacity(bulletsShown ? 1 : 0)
                        .offset(y: bulletsShown ? 0 : 10)
                        .animation(
                            Theme.settle.delay(Double(index) * 0.09),
                            value: bulletsShown
                        )
                }
            }
            .padding(.top, 34)

            Text("no guilt. no streak-shaming. just show up.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 30)
                .opacity(bulletsShown ? 1 : 0)

            Spacer()

            Button {
                Haptics.commit()
                onCommit()
            } label: {
                Text("let's lock it in")
            }
            .buttonStyle(PrimaryCTAStyle(isEnabled: true))
            .opacity(ctaShown ? 1 : 0)

            Text("you can adjust this anytime.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .opacity(ctaShown ? 1 : 0)
        }
        .padding(.horizontal, Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: isActive) {
            guard isActive else { return }
            withAnimation(Theme.settle) { headlineShown = true }
            try? await Task.sleep(for: .milliseconds(260))
            withAnimation(Theme.settle) { bulletsShown = true }
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(Theme.settle) { ctaShown = true }
        }
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.11), in: .circle)

            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
