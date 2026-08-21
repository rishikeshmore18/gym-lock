import SwiftUI

/// System screen 12 — how the loop actually gets broken.
///
/// Nothing to answer here. The user has just handed over the whole shape of
/// their failure, and this is the payoff: the six mechanisms that act on it,
/// each one sentence long. They arrive one after another rather than all at
/// once, so the grid reads as a system being assembled.
struct MechanismsPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @State private var contentShown = false
    @State private var tilesShown = false

    private struct Mechanism: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let detail: String
    }

    private static let mechanisms: [Mechanism] = [
        Mechanism(id: 0, icon: "bell.fill", title: "persistent alarm", detail: "forces the decision"),
        Mechanism(id: 1, icon: "lock.fill", title: "distraction lock", detail: "blocks the apps that usually win"),
        Mechanism(id: 2, icon: "mappin.and.ellipse", title: "real gym verification", detail: "location + workout confirm you went"),
        Mechanism(id: 3, icon: "moon.fill", title: "night lock", detail: "protects tomorrow before bed"),
        Mechanism(id: 4, icon: "arrow.uturn.left", title: "comeback mode", detail: "a miss doesn't become a spiral"),
        Mechanism(id: 5, icon: "chart.line.uptrend.xyaxis", title: "progress", detail: "see your consistency build"),
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        SystemScene(topAnchor: 0.09, contentSpacing: 20) {
            SceneHeading(
                title: "how will GymLock break your bad loop?",
                highlighted: ["break your bad loop?"],
                subtitle: "it changes the moment where you normally negotiate with yourself."
            )
            .staggered(0, isShown: contentShown)
        } content: {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.mechanisms) { mechanism in
                    tile(mechanism)
                        // 80ms apart: fast enough to feel like one gesture,
                        // slow enough that each tile is individually noticed.
                        .staggered(mechanism.id, isShown: tilesShown, step: 0.08)
                }
            }
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(7, isShown: tilesShown, step: 0.08)
        }
        .task(id: isActive) { await run() }
    }

    private func tile(_ mechanism: Mechanism) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: mechanism.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.11), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(mechanism.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(mechanism.detail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(minHeight: 128, alignment: .topLeading)
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
            tilesShown = false
            return
        }

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        // The heading lands first and is given a beat to be read before the
        // mechanisms start arriving underneath it.
        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        tilesShown = true
    }
}
