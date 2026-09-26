import SwiftUI

/// System screen 14 — assembling what the user just described.
///
/// This is honest processing, not a fake network spinner: every line names
/// something the user actually provided, and each one is shown with the value
/// they gave. The percentage is deliberately uneven — 18, 37, 58, 79 — because
/// a perfectly linear bar is the tell of a progress animation with nothing
/// behind it.
struct BuildingSystemPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentShown = false
    @State private var completedCount = 0
    @State private var percent: Double = 0

    /// Checkpoint percentages, one per line, ending at a hundred.
    private static let checkpoints: [Double] = [18, 37, 58, 79, 100]

    private struct Step: Identifiable {
        let id: Int
        let label: String
        let value: String
    }

    private var steps: [Step] {
        let profile = store.profile

        return [
            Step(
                id: 0,
                label: "gym days",
                value: "\(profile.targetWorkoutsPerWeek)× / week"
            ),
            Step(
                id: 1,
                label: "failure window",
                value: profile.failureTime.displayString.lowercased()
            ),
            Step(
                id: 2,
                label: "distracting apps",
                value: profile.selectedDistractingApps.isEmpty
                    ? "none picked"
                    : "\(profile.selectedDistractingApps.count) locked"
            ),
            Step(
                id: 3,
                label: "gym alarm",
                value: profile.alarmSoundLabel.lowercased()
            ),
            Step(
                id: 4,
                label: "night lock",
                value: profile.bedtime.displayString.lowercased()
            ),
            Step(
                id: 5,
                label: "comeback mode",
                value: profile.comebackModeEnabled ? "on" : "off"
            ),
        ]
    }

    var body: some View {
        SystemScene(topAnchor: 0.12, contentSpacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                AccentedText(
                    full: "building your GymLock system…",
                    highlighted: ["your GymLock system…"],
                    size: 30
                )

                percentReadout
            }
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 9) {
                ForEach(steps) { step in
                    row(step)
                }
            }
            .staggered(1, isShown: contentShown)
        } footer: {
            // No button: the screen advances itself once it reaches a hundred.
            Color.clear.frame(height: 1)
        }
        .task(id: isActive) { await run() }
    }

    private var percentReadout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                CountingNumber(value: percent, size: 44, color: Theme.accent)
                Text("%")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.10))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: proxy.size.width * (percent / 100))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement()
        .accessibilityLabel("Building your system")
        .accessibilityValue("\(Int(percent)) percent")
    }

    private func row(_ step: Step) -> some View {
        let isDone = completedCount > step.id

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? Color.clear : Theme.border, lineWidth: 1.4)
                    .frame(width: 24, height: 24)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 24, height: 24)
                    .scaleEffect(isDone ? 1 : 0.4)
                    .opacity(isDone ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .scaleEffect(isDone ? 1 : 0.5)
                    .opacity(isDone ? 1 : 0)
            }

            Text(step.label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isDone ? Theme.ink : Theme.inkTertiary)

            Spacer(minLength: 8)

            Text(step.value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isDone ? Theme.accent : .clear)
                .lineLimit(1)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.7),
            value: isDone
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Timeline

    private func run() async {
        guard isActive else {
            contentShown = false
            completedCount = 0
            percent = 0
            return
        }

        completedCount = 0
        percent = 0

        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        try? await Task.sleep(for: .milliseconds(340))

        // Six lines tick over five checkpoints, spread across roughly two and a
        // half seconds — long enough to read, short enough not to be a wait.
        let total = steps.count
        for index in 0..<total {
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                completedCount = index + 1
            }
            Haptics.tap()

            let checkpoint = Self.checkpoints[min(index, Self.checkpoints.count - 1)]
            withAnimation(.easeInOut(duration: 0.34)) { percent = checkpoint }

            try? await Task.sleep(for: .milliseconds(index == total - 1 ? 240 : 380))
        }

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { percent = 100 }
        Haptics.commit()

        try? await Task.sleep(for: .milliseconds(620))
        guard !Task.isCancelled else { return }
        onContinue()
    }
}
