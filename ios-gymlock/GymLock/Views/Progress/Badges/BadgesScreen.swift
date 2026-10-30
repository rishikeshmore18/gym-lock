import SwiftUI

/// The Badges screen, opened from the Progress tile.
///
/// Shows the kit's gallery over `BadgeStore`. Badges earned since the user
/// last looked start muted and are revealed once: the kit's rank-up for the
/// most prestigious of them (the others pop into place as it lands), or,
/// with Reduce Motion on, a success haptic and a short crossfade. Either way
/// they are marked seen the moment the reveal begins, so it never replays.
struct BadgesScreen: View {
    let badges: BadgeStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Earned but not yet revealed: drawn locked until their moment.
    @State private var pending: Set<String>
    @State private var pops: [String: Double] = [:]
    @State private var request: BadgeRankUpRequest?
    @State private var selected: BadgeDefinition?
    @State private var hasRevealed = false

    init(badges: BadgeStore) {
        self.badges = badges
        _pending = State(initialValue: Set(badges.unseenEarned))
    }

    private var unlocked: Set<String> {
        Set(BadgeCatalog.all.map(\.id).filter { badges.state(for: $0).isEarned && !pending.contains($0) })
    }

    var body: some View {
        NavigationStack {
            BadgeGalleryView(
                unlocked: unlocked,
                stateFor: { badges.state(for: $0) },
                pops: pops,
                focusBadgeId: request?.to.id,
                onTap: { selected = $0 }
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .tint(Theme.ink)
                    .accessibilityLabel(Text("close"))
                }
            }
            .toolbarBackground(BadgePalette.of(.light).bg, for: .navigationBar)
        }
        .badgeRankUp($request) { land($0) }
        .interactiveDismissDisabled(request != nil)
        .sheet(item: $selected) { badge in
            BadgeDetailSheet(badge: badge, state: shownState(for: badge.id))
        }
        .task { await reveal() }
    }

    private func shownState(for id: String) -> BadgeState {
        let state = badges.state(for: id)
        return pending.contains(id) ? .locked(nil) : state
    }

    // MARK: Reveal

    private func reveal() async {
        guard !hasRevealed, !pending.isEmpty else { return }
        hasRevealed = true
        let ids = BadgeCatalog.all.map(\.id).filter { pending.contains($0) }
        badges.markSeen(ids)

        // Lets the sheet finish rising first.
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 650))

        if reduceMotion {
            Haptics.commit()
            withAnimation(.easeInOut(duration: 0.3)) { pending = [] }
            return
        }
        guard let headline = badges.headlineReveal(among: ids) else {
            pending = []
            return
        }
        request = BadgeRankUpRequest(unlocking: BadgeCatalog.badge(headline))
    }

    private func land(_ request: BadgeRankUpRequest) {
        let others = BadgeCatalog.all.map(\.id).filter { pending.contains($0) && $0 != request.to.id }
        var next: [String: Double] = [request.to.id: 0]
        for (index, id) in others.enumerated() {
            next[id] = 0.12 + Double(index) * 0.07
        }
        pending = []
        pops = next
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            pops = [:]
        }
    }
}

// MARK: - Detail

/// One badge, larger: what it is, what earns it, and where the user stands.
struct BadgeDetailSheet: View {
    let badge: BadgeDefinition
    let state: BadgeState

    @ScaledMetric(relativeTo: .largeTitle) private var artWidth: CGFloat = 168
    @ScaledMetric(relativeTo: .title) private var nameSize: CGFloat = 26

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BadgeArtView(badge: badge, locked: !state.isEarned, width: min(artWidth, 230))
                    .opacity(state.isEarned ? 1 : 0.6)
                    .accessibilityHidden(true)
                    .padding(.bottom, 10)

                Text(badge.name)
                    .font(.system(size: nameSize, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                tierChip
                    .padding(.top, 10)

                Text(BadgeCopy.requirement(badge))
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                status
                    .padding(.top, 20)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }

    private var tierChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(badge.tier.accent)
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .frame(width: 8, height: 8)
            Text(BadgeCopy.tierName(badge.tier))
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.surfaceMuted, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(BadgeCopy.tierName(badge.tier)) tier"))
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case let .earned(date):
            Text(BadgeCopy.earnedLine(date))
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.ink)
        case let .locked(progress?):
            VStack(spacing: 8) {
                ProgressView(value: progress.fraction)
                    .tint(Theme.accent)
                    .accessibilityHidden(true)
                Text(BadgeCopy.progressLine(progress))
                    .font(.system(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(BadgeCopy.remainingLine(progress))
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .frame(maxWidth: 260)
        case .locked(nil):
            Text(BadgeCopy.firstTimeLine)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
    }
}

#if DEBUG
#Preview("Badges, partly earned") {
    let store = BadgeStore(defaults: UserDefaults(suiteName: "badges.preview") ?? .standard)
    var states: [String: BadgeState] = [:]
    for badge in BadgeCatalog.all {
        states[badge.id] = .locked(nil)
    }
    states["first-lock"] = .earned(on: .now)
    states["momentum"] = .earned(on: .now)
    states["locked-in"] = .locked(BadgeProgress(current: 2, target: 4, unit: .weeksInARow))
    states["showed-up"] = .earned(on: .now)
    states["ten-strong"] = .earned(on: .now)
    states["quarter-century"] = .locked(BadgeProgress(current: 17, target: 25, unit: .workoutDays))
    states["first-proof"] = .earned(on: .now)
    states["gym-regular"] = .locked(BadgeProgress(current: 12, target: 25, unit: .gymWorkouts))
    store.apply(states)
    return BadgesScreen(badges: store)
}
#endif
