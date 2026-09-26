import SwiftUI

/// System screen 21 — the last look before switching it on.
///
/// The line at the top is the whole argument: the user is not being sold
/// anything new here, they are being shown what they already decided. If they
/// took a Day 0 photo it leads the screen, because their own face is more
/// persuasive than any copy. If they skipped it, the screen simply does not
/// mention it — an empty placeholder would only advertise the gap.
struct FinalCommitmentPage: View {
    let isActive: Bool
    let onActivate: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false
    @State private var checksShown = false

    private var profile: OnboardingProfile { store.profile }

    private var checklist: [(icon: String, label: String)] {
        var items: [(String, String)] = [
            ("bell.fill", "persistent alarm"),
            ("lock.fill", "distracting apps"),
            ("checkmark.shield.fill", "gym verification"),
        ]

        if profile.comebackModeEnabled {
            items.append(("arrow.uturn.left", "comeback mode"))
        }
        items.append(("moon.fill", "night lock"))
        return items
    }

    var body: some View {
        SystemScene(topAnchor: 0.07, contentSpacing: 18) {
            SceneHeading(
                title: "you already decided what you want.",
                highlighted: ["what you want."],
                size: 31
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 16) {
                if let media = profile.day0Media {
                    Day0Thumbnail(media: media, height: 176)
                        .staggered(1, isShown: contentShown)
                }

                goalBlock
                    .staggered(2, isShown: contentShown)

                VStack(spacing: 7) {
                    ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                        checkRow(icon: item.icon, label: item.label)
                            .staggered(index, isShown: checksShown, step: 0.07)
                    }
                }
            }
        } footer: {
            VStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    onActivate()
                } label: {
                    Text("turn on my GymLock")
                }
                .buttonStyle(PrimaryCTAStyle(isEnabled: true))

                Text("everything stays editable.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
            .staggered(7, isShown: checksShown, step: 0.05)
        }
        .task(id: isActive) { await run() }
    }

    private var goalBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(profile.targetWorkoutsPerWeek)")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("workouts / week")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }

            Text("your system is ready.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func checkRow(icon: String, label: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 13))
        .accessibilityElement(children: .combine)
    }

    private func run() async {
        guard isActive else {
            contentShown = false
            checksShown = false
            return
        }

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        try? await Task.sleep(for: .milliseconds(460))
        guard !Task.isCancelled else { return }
        checksShown = true
    }
}
