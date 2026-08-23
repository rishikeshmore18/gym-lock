#if DEBUG
import SwiftUI

/// Jumps the morning flow to any state without waiting for a real 6:30 AM.
///
/// The entire file is inside `#if DEBUG`, so none of it — not the view, not the
/// entry point, not the simulation methods it calls — exists in a release
/// binary. There is no runtime flag to get wrong.
struct DebugMorningPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var alarmAuthorization: AlarmAuthorization = .notDetermined

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        environmentCard
                        stepsSection
                        resetSection
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Morning simulator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
            .task {
                alarmAuthorization = await coordinator.alarmAuthorization()
            }
        }
    }

    // MARK: - Sections

    /// What the flow is actually running against on this device, which is the
    /// first thing worth knowing when something behaves unexpectedly.
    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("environment")
                .font(.system(size: 13, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkTertiary)

            row("alarm backend", coordinator.alarmCapability.headline)
            row("alarm permission", alarmAuthorization.rawValue)
            row("session state", coordinator.session?.state.rawValue ?? "idle")
            row("window", "\(store.plan.rhythm.windowMinutes) min")
            row("planned / 28d", "\(store.plan.plannedSessionsPer28Days)")
            row("skips", "\(coordinator.easySkipsUsed) of \(coordinator.easySkipAllowance)")
            row("momentum", "\(store.log.momentumStreak) days")
            row("gym visits (month)", "\(store.log.verifiedGymVisitsThisMonth)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("jump to")
                .font(.system(size: 13, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkTertiary)

            ForEach(GymSessionCoordinator.DebugStep.allCases) { step in
                Button {
                    coordinator.simulate(step)
                    dismiss()
                } label: {
                    HStack {
                        Text(step.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MorningCardStyle())
            }
        }
    }

    private var resetSection: some View {
        VStack(spacing: 10) {
            Button {
                coordinator.endSession()
                dismiss()
            } label: {
                Text("clear active session")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
            }

            Button {
                store.debugClearSkips()
            } label: {
                Text("clear recent skips")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
            }
        }
    }
}
#endif
