import SwiftUI

/// The Community tab.
///
/// There is no community yet, and inventing one — fake members, fake streaks,
/// a fake feed — would be the single fastest way to lose the trust the rest of
/// the app is built on. So this screen says plainly what is coming and shows
/// the one true thing it has: the user's own record, which is what they would
/// be bringing to a group.
struct CommunityView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // Same header treatment as the other tabs: this screen pushes nothing,
        // so it does not carry a navigation stack just to obtain a title.
        FloatingTitleScreen(title: "Community") {
            VStack(spacing: 14) {
                headline
                whatIsComing
            }
            .padding(.horizontal, 20)
        }
        .tint(Theme.accent)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Text("Showing up is easier\nwith other people.")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Groups aren't open yet. When they are, you'll bring \(store.streak.weeks == 1 ? "1 kept week" : "\(store.streak.weeks) kept weeks") with you.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .warmCard()
    }

    private var whatIsComing: some View {
        VStack(spacing: 0) {
            row(
                symbol: "person.3.fill",
                title: "Small groups",
                detail: "Four or five people, same training days."
            )
            divider
            row(
                symbol: "checkmark.seal.fill",
                title: "Verified only",
                detail: "Sessions your phone confirmed — nothing you can type in."
            )
            divider
            row(
                symbol: "square.and.arrow.up",
                title: "Share a week",
                detail: "Post a kept week to the group, from the frames you already make."
            )
        }
        .padding(.vertical, 4)
        .warmCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 60)
    }

    private func row(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Community") {
    CommunityView()
        .environment(AppStore())
}
