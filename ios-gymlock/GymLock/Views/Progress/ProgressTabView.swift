import SwiftUI

/// The Progress tab.
///
/// It opens with two stat tiles — the streak and the badges — before anything
/// else, because progress on this screen is first a feeling ("am I actually
/// doing this") and only then a chart. Every number here comes from the record:
/// the streak is the ledger's, and badges stay at zero until a badge system
/// exists. Nothing is estimated to make the page look fuller.
struct ProgressTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ProgressStatCard(
                        title: "Day Streak",
                        count: store.log.momentumStreak,
                        appearanceDelay: 0
                    ) {
                        FlameEmblem()
                    }

                    ProgressStatCard(
                        title: "Badges Earned",
                        count: 0,
                        digitStyle: .dark,
                        appearanceDelay: 0.08
                    ) {
                        LogoEmblem()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .background(Theme.canvas)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(Theme.accent)
    }
}

#Preview {
    ProgressTabView()
        .environment(AppStore())
}
