import SwiftUI

/// Placeholder destination for the Profile tab.
///
/// Shows the one thing it can honestly show today — who the user told GymLock
/// they are. Settings still live on the existing home screen; duplicating them
/// here before they have been designed for this surface would mean two places
/// to change the same thing.
struct ProfilePlaceholderView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)

                    Text(store.greetingName)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    Text("coming next.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(Theme.pageMargin)
                .accessibilityElement(children: .combine)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.accent)
    }
}
