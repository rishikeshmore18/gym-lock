import SwiftUI

/// System screen 20 — what the first week actually looks like.
///
/// A preview of app behaviour, not a promise of outcomes. There is no "21 days
/// to a habit", no weight figure, and no guaranteed result anywhere on this
/// screen — every line describes something GymLock will *do*, which is the only
/// thing it can honestly commit to.
struct FirstWeekPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false
    @State private var rowsShown = false

    private struct Beat: Identifiable {
        let id: Int
        let marker: String
        let title: String
        let detail: String
        let icon: String
    }

    private var beats: [Beat] {
        let profile = store.profile

        return [
            Beat(
                id: 0,
                marker: "day 1",
                title: "first gym alarm",
                detail: "\(profile.alarmTime.displayString.lowercased()) · \(profile.alarmSoundLabel.lowercased())",
                icon: "bell.fill"
            ),
            Beat(
                id: 1,
                marker: "day 2",
                title: "you feel the urge to delay",
                detail: "GymLock catches the moment and asks for a decision.",
                icon: "hand.raised.fill"
            ),
            Beat(
                id: 2,
                marker: "first miss",
                title: profile.comebackModeEnabled ? "comeback mode takes over" : "the miss is logged, plainly",
                detail: profile.comebackModeEnabled
                    ? "your next opportunity becomes the priority."
                    : "no streak to protect — just the next session.",
                icon: "arrow.uturn.left"
            ),
            Beat(
                id: 3,
                marker: "end of week",
                title: "see how many times you showed up",
                detail: "counted from real check-ins, not intentions.",
                icon: "chart.bar.fill"
            ),
            Beat(
                id: 4,
                marker: "month 1",
                title: profile.day0Media == nil ? "your first month, side by side" : "compare against your day 0",
                detail: profile.day0Media == nil
                    ? "add a photo any time to start the comparison."
                    : "the photo you took today, next to today's.",
                icon: "photo.on.rectangle.angled"
            ),
        ]
    }

    var body: some View {
        SystemScene(topAnchor: 0.08, contentSpacing: 18) {
            SceneHeading(
                title: "here's what your first week looks like.",
                highlighted: ["your first week"],
                subtitle: "no promises about results. just what the app will do.",
                size: 29
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 8) {
                ForEach(beats) { beat in
                    row(beat)
                        .staggered(beat.id, isShown: rowsShown, step: 0.08)
                }
            }
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(7, isShown: rowsShown, step: 0.06)
        }
        .task(id: isActive) { await run() }
    }

    private func row(_ beat: Beat) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: beat.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.11), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(beat.marker)
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.7)
                    .foregroundStyle(Theme.accent)

                Text(beat.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(beat.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func run() async {
        guard isActive else {
            contentShown = false
            rowsShown = false
            return
        }

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        try? await Task.sleep(for: .milliseconds(380))
        guard !Task.isCancelled else { return }
        rowsShown = true
    }
}
