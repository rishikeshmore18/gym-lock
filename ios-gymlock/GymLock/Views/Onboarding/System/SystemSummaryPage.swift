import SwiftUI

/// System screen 17 — the whole thing, on one card.
///
/// Everything here is read from the profile. It is the receipt for the last
/// fifteen screens, and its job is to make the user feel that they built
/// something rather than answered a questionnaire — which is also what makes the
/// activation screen at the end persuasive without any pressure tactics.
struct SystemSummaryPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false
    @State private var rowsShown = false

    private struct Line: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let value: String
    }

    private var lines: [Line] {
        let profile = store.profile
        var built: [Line] = []

        built.append(
            Line(
                id: 0,
                icon: "target",
                title: "goal",
                value: "\(profile.targetWorkoutsPerWeek)× / week"
            )
        )

        let window = profile.failureWindow?.shortLabel ?? "your window"
        built.append(
            Line(
                id: 1,
                icon: "exclamationmark.triangle.fill",
                title: "critical window",
                value: "\(window) · \(profile.failureTime.displayString.lowercased())"
            )
        )

        built.append(
            Line(
                id: 2,
                icon: "bell.fill",
                title: "alarm",
                value: "persistent · \(profile.alarmSoundLabel.lowercased())"
            )
        )

        built.append(
            Line(
                id: 3,
                icon: "lock.fill",
                title: "locked apps",
                value: profile.lockedAppsSummary
            )
        )

        built.append(
            Line(
                id: 4,
                icon: "checkmark.shield.fill",
                title: "unlock condition",
                value: "gym location + Apple Health workout"
            )
        )

        built.append(
            Line(
                id: 5,
                icon: "moon.fill",
                title: "night lock",
                value: profile.wantsNightLock
                    ? profile.bedtime.displayString.lowercased()
                    : "not needed"
            )
        )

        built.append(
            Line(
                id: 6,
                icon: "arrow.uturn.left",
                title: "missed day",
                value: profile.comebackModeEnabled ? "comeback mode" : "no safety net"
            )
        )

        built.append(
            Line(
                id: 7,
                icon: "photo.fill",
                title: "progress",
                value: profile.day0Media == nil ? "starts today" : "day 0 saved"
            )
        )

        return built
    }

    var body: some View {
        SystemScene(topAnchor: 0.08, contentSpacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                AccentedText(full: "your GymLock", highlighted: ["GymLock"], size: 34)

                Text("built from your answers, not a template.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 0) {
                ForEach(lines) { line in
                    row(line)
                        .staggered(line.id, isShown: rowsShown, step: 0.055)

                    if line.id != (lines.last?.id ?? 0) {
                        Divider()
                            .overlay(Theme.border)
                            .padding(.leading, 42)
                            .opacity(rowsShown ? 1 : 0)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
        } footer: {
            SceneContinueButton(title: "try my GymLock", action: onContinue)
                .staggered(9, isShown: rowsShown, step: 0.05)
        }
        .task(id: isActive) { await run() }
    }

    private func row(_ line: Line) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: line.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
                .padding(.top, 1)

            Text(line.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)

            Spacer(minLength: 10)

            Text(line.value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func run() async {
        guard isActive else {
            contentShown = false
            rowsShown = false
            return
        }

        try? await Task.sleep(for: .milliseconds(170))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        try? await Task.sleep(for: .milliseconds(340))
        guard !Task.isCancelled else { return }
        rowsShown = true
    }
}
