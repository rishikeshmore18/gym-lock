#if DEBUG
import SwiftUI

// MARK: - Readings

/// Live readings shared by Diagnostics and the Test Result view. Everything
/// here is read, never written.
@MainActor
struct SimReadingSource {
    let store: AppStore
    let coordinator: GymSessionCoordinator

    func value(_ reading: SimReading) -> (label: String, value: String) {
        switch reading {
        case .sessionState: ("session state", coordinator.session?.state.rawValue ?? "idle")
        case .showedUp: ("showed up", coordinator.session?.gymArrivalVerified == true ? "yes" : "no")
        case .workoutDetected: ("workout detected", coordinator.session?.workoutDetected == true ? "yes" : "no")
        case .handoff: ("handoff pending", handoffSummary)
        case .shieldPermission: ("shield permission", coordinator.shield.authorization.rawValue)
        case .shieldActive: ("shield active", coordinator.shield.isShielded ? "yes" : "no")
        case .shieldOwner: ("shield owner", coordinator.shield.owner?.rawValue ?? "none")
        case .windDown: ("wind-down active", coordinator.windDown.isActive ? "yes" : "no")
        case .gps: ("gps accuracy", coordinator.arrival.lastAccuracy.map { "\(Int($0)) m" } ?? "none")
        case .location: ("location", locationLabel)
        case .health: ("health", healthLabel)
        case .ringer: ("ringer", ringerLabel)
        case .customSong: ("custom song", customSongLabel)
        case .route: ("last tap route", store.pendingNotificationRoute.map { String(describing: $0.route) } ?? "none")
        case .homeWorkouts: ("home workouts (month)", "\(coordinator.homeWorkoutsUsedThisMonth) of \(HomeWorkoutRules.monthlyLimit)")
        case .momentum: ("momentum", "\(store.streak.weeks) weeks · \(store.streak.thisWeekLabel)")
        }
    }

    /// Peeked, never taken: reporting on the note must not consume it.
    var handoffSummary: String {
        guard let pending = AlarmHandoff.peek() else { return "none" }
        let fired = pending.firedAt.formatted(date: .omitted, time: .standard)
        return pending.wantsSnooze ? "snooze · \(fired)" : "I'm up · \(fired)"
    }

    var resolvedSummary: String {
        let keys = coordinator.debugResolvedSlotKeys
        return keys.isEmpty ? "none" : "\(keys.count) slot(s)"
    }

    var ringerLabel: String {
        guard coordinator.ringer.isRinging else { return "idle" }
        let percent = Int((coordinator.ringer.intensity * 100).rounded())
        let track = coordinator.ringer.playingSound?.label ?? "unknown"
        let fallback = coordinator.ringer.isPlayingFallback ? " (fallback)" : ""
        return "ringing at \(percent)% · \(track)\(fallback)"
    }

    /// Distinguishes "never chosen" from "chosen but the file is gone".
    var customSongLabel: String {
        guard let name = store.profile.effectiveCustomSoundFile else { return "none" }
        return AlarmTrackResolver.customSongExists(named: name) ? name : "missing"
    }

    var nextAlarmLabel: String {
        guard let next = store.plan.nextOccurrence() else { return "none" }
        return next.fireDate.formatted(date: .abbreviated, time: .shortened)
    }

    var locationLabel: String {
        switch coordinator.arrival.availability {
        case .ready: "always"
        case .whenInUseOnly: "when in use"
        case .denied: "denied"
        case .unsupported: "unsupported"
        case .unknown: "not asked"
        }
    }

    var healthLabel: String {
        switch coordinator.health.availability {
        case .authorized: "authorized"
        case .denied: "denied"
        case .unavailable: "unavailable"
        case .notDetermined: "not asked"
        case .unknown: "unknown"
        }
    }
}

/// One label and value line, wrapping instead of truncating at large sizes.
struct SimReadingRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                labelText
                Spacer(minLength: 8)
                valueText.multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                labelText
                valueText
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.inkSecondary)
    }

    private var valueText: some View {
        Text(value)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
    }
}

// MARK: - Diagnostics

/// Every environment row from the original panel, the Hero card lab and the
/// four test tools. Each tool runs the same method it always did, after a
/// confirmation.
struct DaySimulatorDiagnosticsView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    /// Closes the whole simulator sheet, for "clear active session".
    let closeSimulator: () -> Void

    @State private var alarmAuthorization: AlarmAuthorization = .notDetermined
    @State private var results: [SimResultChannel: String] = [:]
    @State private var tapRouteSummary = "none"
    @State private var handoffSummary = "none"
    @State private var resolvedSummary = "none"
    @State private var pendingTool: SimTool?

    private var source: SimReadingSource { SimReadingSource(store: store, coordinator: coordinator) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroLabLink
                environmentCard
                toolsSection
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") { refreshDoorReadings() }
                    .foregroundStyle(Theme.accent)
            }
        }
        .task {
            alarmAuthorization = await coordinator.alarmAuthorization()
            refreshDoorReadings()
        }
        .confirmationDialog(
            pendingTool?.title ?? "",
            isPresented: Binding(get: { pendingTool != nil }, set: { if !$0 { pendingTool = nil } }),
            titleVisibility: .visible,
            presenting: pendingTool
        ) { tool in
            Button(tool.confirmLabel, role: .destructive) { perform(tool) }
            Button("Cancel", role: .cancel) {}
        } message: { tool in
            Text(tool.message)
        }
    }

    // MARK: Hero lab

    private var heroLabLink: some View {
        NavigationLink {
            HeroCardLabView()
        } label: {
            HStack {
                Text("Hero card lab")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }

    // MARK: Environment

    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("environment")
                .font(.footnote.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkTertiary)

            row("alarm sound", store.profile.alarmSoundLabel)
            row("alarm backend", coordinator.alarmCapability.headline)
            row("alarm permission", alarmAuthorization.rawValue)
            row("next alarm", source.nextAlarmLabel)
            row("handoff pending", handoffSummary)
            row("resolved today", resolvedSummary)
            row("open gym visit", coordinator.visits.openVisit(now: Date(), calendar: .current).map { "\($0.minutesAtGym(now: Date())) min" } ?? "none")
            row("last done line", coordinator.visits.lastLine ?? "none")
            row("at the gym result", results[.gym] ?? "none")
            row("flow", store.plan.rhythm.flowMode.label)
            row("lock alarm", store.plan.rhythm.lockAlarmTime.clockString)
            row("sleep days (wake)", Weekday.allCases.filter { store.plan.effectiveSleepDays().contains($0) }.map(\.shortLabel).joined(separator: " "))
            row("one-off alarms", "\(store.plan.oneOffAlarms.count)")
            row("alarm rules result", results[.alarmRules] ?? "none")
            row("sleep", "\(store.plan.rhythm.bedtime.clockString) to \(store.plan.rhythm.wakeTime.clockString)")
            row("pending bedtime", store.plan.pendingBedtime?.bedtime.clockString ?? "none")
            row("ask wake time", store.plan.needsWakeTimeAnswer ? "yes" : "no")
            row("sleep result", results[.sleep] ?? "none")
            row("gym days", "\(store.plan.gymDays.count)")
            row("this week's goal", "\(store.streak.weeklyGoal) (plan \(store.plan.effectiveTrainingDays(fallback: store.schedule).count) days)")
            row("goal rule", "v\(store.streakVault.goalRule ?? 0) · minimum 3 from \(store.streakVault.threeDayRuleStart?.formatted(date: .abbreviated, time: .omitted) ?? "not set")")
            row("week rules result", results[.weekRules] ?? "none")
            row("last tap route", tapRouteSummary)
            row("tap result", results[.notificationTaps] ?? "none")
            row("shield backend", coordinator.shieldCapability.headline)
            row("shield permission", coordinator.shield.authorization.rawValue)
            row("shield active", coordinator.shield.isShielded ? "yes" : "no")
            row("shield owner", coordinator.shield.owner?.rawValue ?? "none")
            row("wind-down active", coordinator.windDown.isActive ? "yes" : "no")
            row("ringer", source.ringerLabel)
            row("custom song", source.customSongLabel)
            row("blocked items", "\(coordinator.shield.selectionCount)")
            row("gym", store.primaryGym?.name ?? "not set")
            row("location", source.locationLabel)
            row("gps accuracy", coordinator.arrival.lastAccuracy.map { "\(Int($0)) m" } ?? "none")
            row("health", source.healthLabel)
            row("session state", coordinator.session?.state.rawValue ?? "idle")
            row("showed up", coordinator.session?.gymArrivalVerified == true ? "yes" : "no")
            row("workout detected", coordinator.session?.workoutDetected == true ? "yes" : "no")
            row("window", "\(store.plan.rhythm.windowMinutes) min")
            row("home workouts (month)", "\(coordinator.homeWorkoutsUsedThisMonth) of \(HomeWorkoutRules.monthlyLimit)")
            row("pending reschedules", "\(coordinator.pendingReschedules.count)")
            row("skips result", results[.skips] ?? "none")
            row("momentum", "\(store.streak.weeks) weeks · \(store.streak.thisWeekLabel)")
            row("freezes", "\(store.streak.freezesAvailable)")
            row("joined", store.joinedAt.formatted(date: .abbreviated, time: .omitted))
            row("gym alarms paused until", store.frozenWeekEnd?.formatted(date: .abbreviated, time: .omitted) ?? "not paused")
            row("at-risk banner", coordinator.streakRiskBanner?.line ?? "quiet")
            row("freezes and at risk result", results[.freezes] ?? "none")
            row("gym visits (month)", "\(store.log.verifiedGymVisitsThisMonth)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    private func row(_ label: String, _ value: String) -> some View {
        SimReadingRow(label: label, value: value)
    }

    /// Re-read on appear and on Refresh, because these are plain values the
    /// view cannot observe.
    private func refreshDoorReadings() {
        handoffSummary = source.handoffSummary
        resolvedSummary = source.resolvedSummary
        tapRouteSummary = store.pendingNotificationRoute.map { String(describing: $0.route) } ?? "none"
        var next: [SimResultChannel: String] = [:]
        for channel in SimResultChannel.allCases { next[channel] = channel.value }
        results = next
    }

    // MARK: Test tools

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("test tools")
                .font(.footnote.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkTertiary)

            Text("Each tool does one thing and asks first. There is no reset-everything button.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)

            ForEach(SimTool.allCases) { tool in
                Button {
                    pendingTool = tool
                } label: {
                    Text(tool.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tool == .forceReleaseShield ? Theme.accent : Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .padding(.horizontal, 12)
                        .background(
                            tool == .forceReleaseShield ? Theme.accent.opacity(0.1) : Theme.surfaceMuted,
                            in: .rect(cornerRadius: Theme.controlRadius)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func perform(_ tool: SimTool) {
        switch tool {
        case .clearSession:
            coordinator.endSession()
            closeSimulator()
        case .clearHomeWorkouts:
            store.debugClearHomeWorkouts()
        case .clearHandoff:
            AlarmHandoff.clear()
            coordinator.debugClearResolvedSlots()
            refreshDoorReadings()
        case .forceReleaseShield:
            coordinator.shield.release()
        }
    }
}

/// The four original reset buttons.
enum SimTool: String, CaseIterable, Identifiable {
    case clearSession, clearHomeWorkouts, clearHandoff, forceReleaseShield
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clearSession: "clear active session"
        case .clearHomeWorkouts: "clear home workouts this month"
        case .clearHandoff: "clear handoff and resolved slots"
        case .forceReleaseShield: "force-release shield"
        }
    }

    var confirmLabel: String {
        switch self {
        case .clearSession: "End session and close"
        case .clearHomeWorkouts: "Clear home workouts"
        case .clearHandoff: "Clear handoff and slots"
        case .forceReleaseShield: "Release shield"
        }
    }

    var message: String {
        switch self {
        case .clearSession: "Ends the live session and closes the simulator."
        case .clearHomeWorkouts: "Removes this month's home workouts from your real log."
        case .clearHandoff: "Clears the pending alarm handoff and today's resolved slots."
        case .forceReleaseShield: "Lifts the shield right now, whoever owns it."
        }
    }
}
#endif
