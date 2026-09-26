import SwiftUI

/// System screen 16 — where GymLock steps in.
///
/// The first screen that should feel unmistakably built for this specific user:
/// every row carries a time they chose, an app they named, or a track they
/// picked. Nothing on it is a sample value, and the night lock row simply does
/// not exist for someone who said the scroll does not follow them to bed.
struct InterventionTimelinePage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false
    @State private var rowsShown = false

    private struct Moment: Identifiable {
        let id: Int
        let time: String
        let icon: String
        let text: String
        let isAccented: Bool
    }

    private var moments: [Moment] {
        let profile = store.profile
        var built: [Moment] = []

        built.append(
            Moment(
                id: 0,
                time: profile.alarmTime.displayString.lowercased(),
                icon: "music.note",
                text: "gym alarm — \(profile.alarmSoundLabel.lowercased())",
                isAccented: true
            )
        )

        built.append(
            Moment(
                id: 1,
                time: profile.failureTime.displayString.lowercased(),
                icon: "lock.fill",
                text: "\(profile.lockedAppsSummary) locked",
                isAccented: true
            )
        )

        built.append(
            Moment(id: 2, time: "gym arrival", icon: "mappin.and.ellipse", text: "location confirmed", isAccented: false)
        )

        built.append(
            Moment(id: 3, time: "workout starts", icon: "heart.fill", text: "Apple Health workout confirmed", isAccented: false)
        )

        built.append(
            Moment(id: 4, time: "then", icon: "lock.open.fill", text: "apps unlock", isAccented: true)
        )

        built.append(
            Moment(
                id: 5,
                time: profile.bedtime.displayString.lowercased(),
                icon: "moon.fill",
                text: "night lock starts",
                isAccented: true
            )
        )

        return built
    }

    var body: some View {
        SystemScene(topAnchor: 0.08, contentSpacing: 18) {
            SceneHeading(
                title: "so that's exactly where GymLock steps in.",
                highlighted: ["where GymLock steps in."],
                subtitle: "your day, with the negotiation removed.",
                size: 28
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 0) {
                ForEach(moments) { moment in
                    row(moment)
                        .staggered(moment.id, isShown: rowsShown, step: 0.09)
                }
            }
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(8, isShown: rowsShown, step: 0.06)
        }
        .task(id: isActive) { await run() }
    }

    private func row(_ moment: Moment) -> some View {
        let isLast = moment.id == (moments.last?.id ?? 0)

        return HStack(alignment: .top, spacing: 14) {
            // The rail: a dot per moment, joined by a line, so the column reads
            // as one continuous day rather than a stack of cards.
            VStack(spacing: 0) {
                Circle()
                    .fill(moment.isAccented ? Theme.accent : Theme.surface)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle().strokeBorder(
                            moment.isAccented ? Color.clear : Theme.border,
                            lineWidth: 1.4
                        )
                    }
                    .overlay {
                        Image(systemName: moment.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(moment.isAccented ? .white : Theme.inkSecondary)
                    }

                if !isLast {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(moment.time)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text(moment.text)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 16)

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
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

        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        rowsShown = true
    }
}
