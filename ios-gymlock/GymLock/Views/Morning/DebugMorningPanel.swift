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
    /// Re-read whenever the panel appears, because the interesting cases are
    /// exactly the ones where something changed while it was closed.
    @State private var handoffSummary = "none"
    @State private var resolvedSummary = "none"

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
                refreshDoorReadings()
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
            row("next alarm", nextAlarmLabel)
            row("handoff pending", handoffSummary)
            row("resolved today", resolvedSummary)
            row("shield backend", coordinator.shieldCapability.headline)
            row("shield permission", coordinator.shield.authorization.rawValue)
            row("shield active", coordinator.shield.isShielded ? "yes" : "no")
            row("shield owner", coordinator.shield.owner?.rawValue ?? "none")
            row("wind-down active", coordinator.windDown.isActive ? "yes" : "no")
            row("blocked items", "\(coordinator.shield.selectionCount)")
            row("gym", store.primaryGym?.name ?? "not set")
            row("location", locationLabel)
            row("gps accuracy", coordinator.arrival.lastAccuracy.map { "\(Int($0)) m" } ?? "none")
            row("health", healthLabel)
            row("session state", coordinator.session?.state.rawValue ?? "idle")
            row("showed up", coordinator.session?.gymArrivalVerified == true ? "yes" : "no")
            row("workout detected", coordinator.session?.workoutDetected == true ? "yes" : "no")
            row("window", "\(store.plan.rhythm.windowMinutes) min")
            row("planned / 28d", "\(store.plan.plannedSessionsPer28Days)")
            row("skips", "\(coordinator.easySkipsUsed) of \(coordinator.easySkipAllowance)")
            row("momentum", "\(store.streak.weeks) weeks · \(store.streak.thisWeekLabel)")
            row("freezes", "\(store.streak.freezesAvailable)")
            row("gym visits (month)", "\(store.log.verifiedGymVisitsThisMonth)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    /// Peeked, never taken: reporting on the note must not consume it.
    private func refreshDoorReadings() {
        if let pending = AlarmHandoff.peek() {
            let fired = pending.firedAt.formatted(date: .omitted, time: .standard)
            handoffSummary = pending.wantsSnooze ? "snooze · \(fired)" : "I'm up · \(fired)"
        } else {
            handoffSummary = "none"
        }

        let keys = coordinator.debugResolvedSlotKeys
        resolvedSummary = keys.isEmpty ? "none" : "\(keys.count) slot(s)"
    }

    private var nextAlarmLabel: String {
        guard let next = store.plan.nextOccurrence() else { return "none" }
        return next.fireDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var locationLabel: String {
        switch coordinator.arrival.availability {
        case .ready: "always"
        case .whenInUseOnly: "when in use"
        case .denied: "denied"
        case .unsupported: "unsupported"
        case .unknown: "not asked"
        }
    }

    private var healthLabel: String {
        switch coordinator.health.availability {
        case .authorized: "authorized"
        case .denied: "denied"
        case .unavailable: "unavailable"
        case .notDetermined: "not asked"
        case .unknown: "unknown"
        }
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

    /// Grouped by subsystem, because the list is now long enough that a flat
    /// run of twenty-odd buttons would be slower to scan than useful.
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(GymSessionCoordinator.DebugStep.sections, id: \.self) { section in
                let steps = GymSessionCoordinator.DebugStep.allCases
                    .filter { $0.section == section }

                VStack(alignment: .leading, spacing: 10) {
                    Text(section)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkTertiary)

                    ForEach(steps) { step in
                        stepButton(step)
                    }
                }
            }
        }
    }

    /// Steps that only change a reading stay on screen; steps that move the
    /// flow dismiss, so the result is actually visible.
    private func stepButton(_ step: GymSessionCoordinator.DebugStep) -> some View {
        // The two "must produce nothing" doors stay open on purpose: the whole
        // point is to watch the readings *not* change.
        let staysOpen: Set<GymSessionCoordinator.DebugStep> = [
            .familyControlsAuthorized, .familyControlsDenied,
            .badGPSAccuracy, .goodGPSAccuracy,
            .healthDenied, .noHealthWorkout, .driveBy,
            .foregroundAfterWindow, .foregroundAfterResolved,
            .windDownLockStart, .windDownLockEnd, .windDownWhileSessionLive,
        ]
        let isReadingOnly = staysOpen.contains(step)

        return Button {
            coordinator.simulate(step)
            refreshDoorReadings()
            if !isReadingOnly { dismiss() }
        } label: {
            HStack {
                Text(step.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: isReadingOnly ? "bolt.fill" : "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
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

            Button {
                AlarmHandoff.clear()
                coordinator.debugClearResolvedSlots()
                refreshDoorReadings()
            } label: {
                Text("clear handoff and resolved slots")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
            }

            Button {
                coordinator.shield.release()
            } label: {
                Text("force-release shield")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: 14))
            }
        }
    }
}
#endif
