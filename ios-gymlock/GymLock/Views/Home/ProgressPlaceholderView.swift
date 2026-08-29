import SwiftUI

/// Placeholder destination for the Progress tab.
///
/// Empty on purpose. GymLock already records what happened every morning, and
/// this screen will be built from that record — inventing charts before then
/// would mean showing numbers the app has not earned.
struct ProgressPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(spacing: 10) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)

                    Text("progress")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    Text("coming next.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(Theme.pageMargin)
                .accessibilityElement(children: .combine)
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.accent)
    }
}
