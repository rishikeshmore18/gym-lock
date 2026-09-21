import SwiftUI

/// The Profile tab.
///
/// Reachable from the detached circle on the tab bar. It shows the things it
/// can state truthfully — who the user said they are, the alarm that will
/// actually ring, and the streak the ledger has ruled on — and is where the
/// original home now lives, as "Home 2".
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    /// The classic home, presented rather than pushed: it owns its own
    /// navigation stack and toolbar, and nesting one stack inside another
    /// would give it two back buttons and two titles.
    @State private var isShowingClassicHome = false
    @State private var isShowingAlarmSettings = false
    @State private var alarmAuth: AlarmAuthorization = .notDetermined

    /// The alarm screen grows out of this row and returns to it.
    @Namespace private var alarmTransition

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
        .fullScreenCover(isPresented: $isShowingAlarmSettings, onDismiss: {
            // The interesting state is exactly what may have changed while the
            // cover was up.
            Task { alarmAuth = await coordinator.alarmAuthorization() }
        }) {
            AlarmSettingsView()
                .navigationTransition(.zoom(sourceID: "alarm-settings", in: alarmTransition))
        }
        .task {
            alarmAuth = await coordinator.alarmAuthorization()
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
                isShowingAlarmSettings = true
            } label: {
                row(
                    symbol: "alarm.fill",
                    title: "Alarm",
                    detail: alarmDetail,
                    detailColor: alarmDetailColor
                )
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "alarm-settings", in: alarmTransition)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.horizontal, 18)

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

    /// Live, derived, and honest: what will actually ring, or what is broken.
    private var alarmDetail: String {
        if alarmAuth == .denied { return "alarm is off in Settings" }

        guard let slot = store.plan.enabledSlots.first ?? store.plan.slots.first else {
            return "no alarm set"
        }
        return "\(slot.alarmTime.displayString) · \(slot.daysSummary)"
    }

    /// Denied permission is the one case where the row earns the accent,
    /// because it is the one case where something is broken.
    private var alarmDetailColor: Color {
        alarmAuth == .denied ? Theme.accent : Theme.inkSecondary
    }

    private func row(
        symbol: String,
        title: String,
        detail: String,
        detailColor: Color = Theme.inkSecondary
    ) -> some View {
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
                    .foregroundStyle(detailColor)
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
