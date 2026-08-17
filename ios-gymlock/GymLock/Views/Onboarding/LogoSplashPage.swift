import SwiftUI

/// Page 1 — the professional logo introduction.
/// The mark settles in first, the wordmark follows, then the swipe hint.
struct LogoSplashPage: View {
    let isActive: Bool

    @State private var markShown = false
    @State private var wordmarkShown = false
    @State private var hintShown = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            logoMark
                .opacity(markShown ? 1 : 0)
                .scaleEffect(markShown ? 1 : 0.94)

            Text("GymLock")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 26)
                .opacity(wordmarkShown ? 1 : 0)

            Text("show up. then scroll.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 8)
                .opacity(wordmarkShown ? 1 : 0)

            Spacer()

            SwipeUpHint(isActive: isActive && hintShown)
                .opacity(hintShown ? 1 : 0)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .task(id: isActive) {
            guard isActive else { return }
            withAnimation(Theme.settle) { markShown = true }
            try? await Task.sleep(for: .milliseconds(340))
            withAnimation(Theme.settle) { wordmarkShown = true }
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeOut(duration: 0.45)) { hintShown = true }
        }
    }

    private var logoMark: some View {
        Image("GymLockLogo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 148, height: 148)
            .clipShape(.rect(cornerRadius: 36))
            .overlay {
                RoundedRectangle(cornerRadius: 36)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 26, x: 0, y: 14)
            .accessibilityLabel("GymLock logo")
    }
}
