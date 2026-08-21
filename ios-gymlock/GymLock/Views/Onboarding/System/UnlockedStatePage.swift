import SwiftUI

/// System screen 19 — the unlock, demonstrated.
///
/// Deliberately opens in exactly the state the previous screen ended in: the
/// same two icons, still drained, still badged. Then the two verifications land
/// a beat apart, the badges let go, and the colour floods back. The contrast
/// between this screen and the one before it is the entire product argument, so
/// nothing else competes for attention here.
struct UnlockedStatePage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentShown = false
    @State private var gymVerified = false
    @State private var workoutVerified = false
    @State private var lockProgress: Double = 1
    @State private var unlockedShown = false

    private var profile: OnboardingProfile { store.profile }

    var body: some View {
        SystemScene(topAnchor: 0.08, contentSpacing: 16) {
            SceneHeading(
                title: "verified. you're back in.",
                highlighted: ["you're back in."],
                subtitle: "location and Apple Health did the checking. no honour system.",
                size: 32
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    VerificationRow(
                        icon: "mappin.and.ellipse",
                        title: "gym",
                        isVerified: gymVerified
                    )
                    VerificationRow(
                        icon: "heart.fill",
                        title: "workout",
                        isVerified: workoutVerified
                    )
                }

                LockDemoStrip(apps: profile.demoApps, lockProgress: lockProgress)
                    .padding(.vertical, 2)

                unlockedBanner
            }
        } footer: {
            SceneContinueButton(isEnabled: unlockedShown, action: onContinue)
                .staggered(2, isShown: contentShown)
        }
        .task(id: isActive) { await run() }
    }

    private var unlockedBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 13, weight: .bold))
            Text("apps unlocked")
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.accent, in: .capsule)
        .opacity(unlockedShown ? 1 : 0)
        .scaleEffect(unlockedShown || reduceMotion ? 1 : 0.9)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: unlockedShown)
    }

    private func run() async {
        guard isActive else {
            contentShown = false
            gymVerified = false
            workoutVerified = false
            unlockedShown = false
            lockProgress = 1
            return
        }

        // Reset to the locked state so the screen always starts where screen 18
        // left off, even if the user swipes back and forth.
        gymVerified = false
        workoutVerified = false
        unlockedShown = false
        lockProgress = 1

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        try? await Task.sleep(for: .milliseconds(520))
        guard !Task.isCancelled else { return }
        gymVerified = true
        Haptics.soft()

        // The gap between the two checks is what makes them feel like two
        // independent confirmations rather than one animation.
        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        workoutVerified = true
        Haptics.soft()

        try? await Task.sleep(for: .milliseconds(340))
        guard !Task.isCancelled else { return }

        // Slower than the lock. Locking is abrupt because it is imposed;
        // unlocking is earned, and is allowed to take its time.
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.35)
                : .timingCurve(0.2, 0.85, 0.2, 1, duration: 0.75)
        ) {
            lockProgress = 0
        }

        try? await Task.sleep(for: .milliseconds(520))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { unlockedShown = true }
        Haptics.commit()
    }
}
