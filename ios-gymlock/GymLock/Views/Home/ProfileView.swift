import SwiftUI

/// The Profile tab.
///
/// Reachable from the detached circle on the tab bar. It shows the two things
/// it can state truthfully — who the user said they are, and the streak the
/// ledger has ruled on — and is where the original home now lives, as "Home 2".
struct ProfileView: View {
    @Environment(AppStore.self) private var store

    /// The classic home, presented rather than pushed: it owns its own
    /// navigation stack and toolbar, and nesting one stack inside another
    /// would give it two back buttons and two titles.
    @State private var isShowingClassicHome = false

    private var streakLine: String {
        let weeks = store.streak.weeks
        return weeks == 1 ? "1 kept week" : "\(weeks) kept weeks"
    }

    var body: some View {
        // Same header treatment as the other tabs: this screen pushes nothing,
        // so it does not carry a navigation stack just to obtain a title.
        FloatingTitleScreen(title: "Profile") {
            VStack(spacing: 14) {
                identityCard
                shortcuts
            }
            .padding(.horizontal, 20)
        }
        .tint(Theme.accent)
        .sheet(isPresented: $isShowingClassicHome) {
            HomeView()
                .presentationDragIndicator(.visible)
        }
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.surfaceMuted)
                Text(initial)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.greetingName)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(streakLine)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .warmCard()
        .accessibilityElement(children: .combine)
    }

    private var shortcuts: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.tap()
                isShowingClassicHome = true
            } label: {
                row(
                    symbol: "square.grid.2x2.fill",
                    title: "Home 2",
                    detail: "Your locks, alarms and settings."
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .warmCard()
    }

    private func row(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Text(detail)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .contentShape(.rect)
    }

    private var initial: String {
        let name = store.greetingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(name.first ?? "G").uppercased()
    }
}

#Preview("Profile") {
    ProfileView()
        .environment(AppStore())
}
