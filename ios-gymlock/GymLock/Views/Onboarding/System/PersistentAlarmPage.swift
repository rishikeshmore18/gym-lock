import SwiftUI

/// System screen 10 — the alarm, framed as a mechanism rather than a setting.
///
/// The user has just told GymLock the exact moment they lose. This screen
/// answers with the thing that shows up at that moment, and the preview lets
/// them feel it once — briefly, and only when asked — because an alarm that has
/// never been experienced is an abstraction.
struct PersistentAlarmPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(AlarmSoundPlayer.self) private var player: AlarmSoundPlayer?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentShown = false
    @State private var isPreviewing = false
    @State private var ringPhase = 0
    @State private var previewTask: Task<Void, Never>?

    private let bullets: [(icon: String, text: String)] = [
        ("arrow.trianglehead.clockwise", "keeps coming back until you act"),
        ("hand.raised.slash.fill", "no silent swipe-away"),
        ("arrow.triangle.branch", "forces a real decision: go, reschedule, or consciously skip"),
    ]

    var body: some View {
        SystemScene(topAnchor: 0.09, contentSpacing: 20) {
            SceneHeading(
                title: "how will we make you move?",
                highlighted: ["make you move?"],
                subtitle: "rings when your gym window starts."
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 16) {
                alarmHero
                    .staggered(1, isShown: contentShown)

                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                        bulletRow(icon: bullet.icon, text: bullet.text)
                            .staggered(index + 2, isShown: contentShown)
                    }
                }
            }
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(6, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
        .onDisappear { endPreview() }
        .onChange(of: isActive) { _, active in
            if !active { endPreview() }
        }
    }

    /// The card is the product feature made concrete: a bell that rings when
    /// asked, and stops the moment the preview is over.
    private var alarmHero: some View {
        VStack(spacing: 14) {
            ZStack {
                // Two rings leaving the bell, only while it is actually ringing.
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 2)
                        .frame(width: 66, height: 66)
                        .scaleEffect(isPreviewing ? 1.9 : 1)
                        .opacity(isPreviewing ? 0 : 0.9)
                        .animation(
                            isPreviewing && !reduceMotion
                                ? .easeOut(duration: 1.1)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(ring) * 0.55)
                                : .easeOut(duration: 0.2),
                            value: isPreviewing
                        )
                }

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 66, height: 66)
                    .overlay {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(shakeAngle))
                    }
            }
            .frame(height: 76)

            VStack(spacing: 5) {
                Text("strong persistent alarm")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text("fires at \(store.profile.alarmTime.displayString.lowercased()) — just before the moment you lose.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                togglePreview()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(isPreviewing ? "stop" : "preview alarm")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Theme.accent.opacity(0.11), in: .capsule)
            }
            .buttonStyle(PressableRowStyle())
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .warmCard()
    }

    /// A small, tight oscillation — a bell being struck, not a pendulum.
    private var shakeAngle: Double {
        guard isPreviewing, !reduceMotion else { return 0 }
        return ringPhase.isMultiple(of: 2) ? -13 : 13
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 25, height: 25)
                .background(Theme.accent.opacity(0.11), in: .circle)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Preview

    private func togglePreview() {
        if isPreviewing {
            endPreview()
        } else {
            startPreview()
        }
    }

    /// Deliberately short and self-terminating. A preview that outstays its
    /// welcome teaches the user to dread the real thing.
    private func startPreview() {
        isPreviewing = true
        player?.play(store.profile.alarmSound)

        previewTask?.cancel()
        previewTask = Task {
            let deadline = Date().addingTimeInterval(2.4)

            while !Task.isCancelled, Date() < deadline {
                withAnimation(.easeInOut(duration: 0.11)) { ringPhase += 1 }
                Haptics.medium()
                try? await Task.sleep(for: .milliseconds(230))
            }

            guard !Task.isCancelled else { return }
            endPreview()
        }
    }

    private func endPreview() {
        previewTask?.cancel()
        previewTask = nil
        player?.stop()

        withAnimation(.easeOut(duration: 0.2)) {
            isPreviewing = false
            ringPhase = 0
        }
    }
}
