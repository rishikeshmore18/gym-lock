import SwiftUI

/// System screen 18 — the lock, demonstrated.
///
/// Describing the mechanism has not worked so far in this category, so this
/// screen simply performs it. The user taps "i'm going" and watches their own
/// two apps drain of colour and take a lock badge. The next screen reverses it.
/// Together they are the product in ten seconds.
struct LockedStatePage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentShown = false
    @State private var alarmShown = false
    @State private var hasCommitted = false
    @State private var lockProgress: Double = 0
    @State private var statusShown = false

    private var profile: OnboardingProfile { store.profile }

    var body: some View {
        SystemScene(topAnchor: 0.08, contentSpacing: 16) {
            SceneHeading(
                title: "let's try it.",
                highlighted: ["try it."],
                subtitle: "here's what happens when your gym window starts.",
                size: 32
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 16) {
                alarmCard

                LockDemoStrip(apps: profile.demoApps, lockProgress: lockProgress)
                    .padding(.vertical, 4)

                if statusShown {
                    VStack(spacing: 8) {
                        VerificationRow(icon: "mappin.and.ellipse", title: "gym", isVerified: false)
                        VerificationRow(icon: "heart.fill", title: "workout", isVerified: false)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        } footer: {
            SceneContinueButton(
                caption: hasCommitted ? nil : "tap \u{201C}i'm going\u{201D} to see it work.",
                isEnabled: hasCommitted,
                action: onContinue
            )
            .staggered(2, isShown: contentShown)
        }
        .task(id: isActive) { await run() }
    }

    /// The alarm as the user will actually meet it, with their own time and
    /// track on it.
    private var alarmCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 13) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("gym window · \(profile.alarmTime.displayString.lowercased())")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(profile.alarmSoundLabel.lowercased())
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }

                Spacer()
            }

            if !hasCommitted {
                Button {
                    commit()
                } label: {
                    Text("i'm going")
                }
                .buttonStyle(PrimaryCTAStyle(isEnabled: true))
                .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(profile.lockedAppsSummary) locked until you show up")
                        .font(.system(size: 13.5, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.accent)
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .warmCard()
        .opacity(alarmShown ? 1 : 0)
        .scaleEffect(alarmShown || reduceMotion ? 1 : 0.97)
        .offset(y: alarmShown || reduceMotion ? 0 : 12)
        .animation(Theme.settle, value: alarmShown)
        .animation(Theme.settle, value: hasCommitted)
    }

    private func commit() {
        guard !hasCommitted else { return }
        hasCommitted = true

        // One firm impact as the locks land, not one per icon: it is a single
        // event happening to the whole phone.
        Haptics.medium()

        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.3)
                : .timingCurve(0.3, 0.8, 0.25, 1, duration: 0.55)
        ) {
            lockProgress = 1
        }

        Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.settle) { statusShown = true }
        }
    }

    private func run() async {
        guard isActive else {
            contentShown = false
            alarmShown = false
            hasCommitted = false
            statusShown = false
            lockProgress = 0
            return
        }

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { alarmShown = true }
        Haptics.medium()
    }
}
