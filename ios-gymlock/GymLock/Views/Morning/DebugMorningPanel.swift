#if DEBUG
import SwiftUI

/// The Day Flow Simulator: pick a scenario, see what it sets, run it once.
///
/// The entire file is inside `#if DEBUG`, so none of it exists in a release
/// binary. Every test is still one `GymSessionCoordinator.DebugStep`, run
/// through the same `simulate(_:)` the old panel called; this view only
/// describes, selects and runs them.
struct DebugMorningPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model = DaySimulatorModel()
    @State private var path: [SimRoute] = []
    @State private var isConfirmingLiveRun = false
    @State private var isConfirmingEndSession = false

    private var calendar: Calendar { model.calendar }
    private var stateAnimation: Animation? { reduceMotion ? nil : Theme.stateChange }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    simulationNote
                    if coordinator.isSessionLive { liveSessionBanner }
                    dayCard
                    stageRow
                    presetsSection
                    dialsCard
                    if let scenario = model.scenario, !scenario.conditions.isEmpty || !scenario.fixedNotes.isEmpty {
                        conditionsCard(scenario)
                    }
                    linksSection
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Day Flow Simulator")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("DEBUG")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accentWash, in: .capsule)
                        .accessibilityLabel("Debug build only")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
            .safeAreaInset(edge: .bottom) { runBar }
            .navigationDestination(for: SimRoute.self, destination: destination)
            .confirmationDialog(
                "A session is live",
                isPresented: $isConfirmingLiveRun,
                titleVisibility: .visible
            ) {
                Button("End session, then run", role: .destructive) {
                    coordinator.endSession()
                    performRun()
                }
                Button("Run with the session live") { performRun() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This test may replace or change the live session (\(coordinator.session?.state.rawValue ?? "live")).")
            }
            .confirmationDialog(
                "End the live session?",
                isPresented: $isConfirmingEndSession,
                titleVisibility: .visible
            ) {
                Button("End session", role: .destructive) { coordinator.endSession() }
                Button("Cancel", role: .cancel) {}
            }
        }
        // Fires once the sheet is fully gone, whatever the dismissal took.
        .onDisappear {
            model.flushPendingAfterClose(using: runner)
        }
    }

    // MARK: - Routing

    @ViewBuilder
    private func destination(_ route: SimRoute) -> some View {
        switch route {
        case let .library(stage):
            DaySimulatorLibraryView(selected: model.selectedStep, stage: stage) { step in
                withAnimation(stateAnimation) { model.select(step) }
                if !path.isEmpty { path.removeLast() }
            }
        case let .result(step, ranAt, stay):
            DaySimulatorResultView(
                step: step,
                ranAt: ranAt,
                stayMinutes: stay,
                onRunAnother: { path.removeAll() },
                onDiagnostics: { path.append(.diagnostics) }
            )
        case .diagnostics:
            DaySimulatorDiagnosticsView(closeSimulator: { dismiss() })
        }
    }

    // MARK: - Run

    private var runner: SimRunner {
        let coordinator = coordinator
        return SimRunner(
            applyScreenTime: { coordinator.shield.debugSetAuthorization($0 ? .approved : .denied) },
            applyHealth: { coordinator.health.debugSetAvailability($0 ? .authorized : .denied) },
            simulate: { coordinator.simulate($0) },
            simulateStay: { coordinator.debugSimulateStay(minutes: $0) }
        )
    }

    private func runTapped() {
        guard model.runBlocker == nil else { return }
        if coordinator.isSessionLive {
            isConfirmingLiveRun = true
        } else {
            performRun()
        }
    }

    private func performRun() {
        guard let scenario = model.scenario else { return }
        // Cleared first, so the Observed line can only be this run's.
        scenario.resultChannel?.value = "none"
        let stay = scenario.gymTime == .adjustable ? model.stayMinutes : nil

        switch model.run(using: runner) {
        case .showResult:
            path.append(.result(scenario.step, Date(), stay))
        case .dismiss:
            dismiss()
        case .closeThenRun:
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { dismiss() }
        case nil:
            break
        }
    }

    private var runBar: some View {
        VStack(spacing: 10) {
            if let blocker = model.runBlocker {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(blocker)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.scenario?.day == .today, model.selectedDay != model.today {
                        Button("Use today") {
                            withAnimation(stateAnimation) { model.useToday() }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
            } else if let scenario = model.scenario {
                Text(runSummary(scenario))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: runTapped) {
                Label("Run this test", systemImage: "play.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        model.runBlocker == nil ? Theme.accent : Theme.inkTertiary.opacity(0.6),
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.runBlocker != nil)
            .sensoryFeedback(.impact(weight: .light), trigger: model.isRunning) { _, running in running }
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Theme.canvas
                .opacity(0.97)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func runSummary(_ scenario: SimScenario) -> String {
        var parts = ["Simulation", scenario.staysOpen ? "shows a result" : "closes to show the flow"]
        if scenario.playsAfterClose { parts[1] = "closes first, then runs" }
        if scenario.writesRealData { parts.append("writes to your real plan or log") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Header notes

    private var simulationNote: some View {
        Label("Simulation only. The clock, GPS, Health and system alarms are never faked; each test runs the app's real rules.", systemImage: "flask")
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
    }

    private var liveSessionBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Session live")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(coordinator.session?.state.rawValue ?? "live")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            Button("End it") { isConfirmingEndSession = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(14)
        .background(Theme.accentWash, in: .rect(cornerRadius: Theme.controlRadius))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Day

    private var dayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Day")

            HStack(spacing: 6) {
                ForEach(SimCatalog.weekOrder) { day in
                    dayButton(day)
                }
            }

            if let scenario = model.scenario {
                dayRuleLine(scenario)
            } else {
                Text("Picking a day is a draft. It never changes your saved schedule.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
            }

            if model.selectedDay != model.today, model.isDayAdjustable {
                dayScenarioChips
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: Theme.cardRadius)
    }

    private func dayButton(_ day: Weekday) -> some View {
        let date = SimCatalog.date(of: day, inWeekOf: model.now, calendar: calendar)
        let isSelected = day == model.selectedDay
        let isToday = day == model.today
        let enabled = model.isDayAdjustable || isSelected
        return Button {
            withAnimation(stateAnimation) { model.selectDay(day) }
        } label: {
            VStack(spacing: 2) {
                Text(day.shortLabel)
                    .font(.caption2.weight(.semibold))
                Text(date.formatted(.dateTime.day()))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isSelected ? .white : (isToday ? Theme.accent : Theme.ink))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                isSelected ? Theme.accent : Theme.surfaceMuted,
                in: .rect(cornerRadius: 12)
            )
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!model.isDayAdjustable)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).day().month()))\(isToday ? ", today" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dayRuleLine(_ scenario: SimScenario) -> some View {
        let resolved = SimCatalog.resolvedDate(for: scenario.day, joinedAt: store.joinedAt, now: model.now, calendar: calendar)
        let showsDate: Bool = {
            switch scenario.day {
            case .today, .dayless: false
            default: true
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Label(SimCatalog.dayRuleNote(scenario.day), systemImage: scenario.day.isDraftAdjustable ? "calendar" : "lock")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            if showsDate, let resolved {
                Text("Acts on \(resolved.formatted(.dateTime.weekday(.abbreviated).day().month().year()))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    private var dayScenarioChips: some View {
        let steps = model.scenariosForSelectedDay
        return VStack(alignment: .leading, spacing: 8) {
            Text(steps.isEmpty
                 ? "No scenario is set on \(model.selectedDay.shortLabel). Real-clock tests run on today."
                 : "Set on \(model.selectedDay.shortLabel):")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
            if !steps.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(steps) { step in
                            Button {
                                withAnimation(stateAnimation) { model.select(step) }
                            } label: {
                                Text(step.label)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.accentWash, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Stages

    private var stageRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SimStage.allCases) { stage in
                    let isSelected = stage == model.stage
                    Button {
                        withAnimation(stateAnimation) { model.stage = stage }
                    } label: {
                        Label(stage.title, systemImage: stage.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? .white : Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isSelected ? Theme.accent : Theme.surface, in: .capsule)
                            .overlay { Capsule().strokeBorder(isSelected ? .clear : Theme.border, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint("Filters the scenarios. Does not run anything.")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Theme.pageMargin)
        .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
    }

    // MARK: - Presets

    private var presetsSection: some View {
        let presets = model.stage.presets
        let stageCount = SimCatalog.steps(in: model.stage).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("\(model.stage.title) presets")
                Spacer()
                Button("See all · \(stageCount)") {
                    path.append(.library(model.stage))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }

            if let selected = model.selectedStep, !presets.contains(selected) {
                presetCard(selected, badge: "Selected")
            }
            ForEach(presets) { step in
                presetCard(step, badge: nil)
            }
        }
    }

    private func presetCard(_ step: SimStep, badge: String?) -> some View {
        let info = SimCatalog.scenario(for: step)
        let isSelected = step == model.selectedStep
        return Button {
            withAnimation(stateAnimation) {
                if isSelected { model.clearSelection() } else { model.select(step) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let badge {
                            Text(badge.uppercased())
                                .font(.caption2.weight(.heavy))
                                .tracking(0.6)
                                .foregroundStyle(Theme.accent)
                        }
                        Text(step.label)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(info.summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.accent : Theme.border)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Expected")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkTertiary)
                    Text(info.expected)
                        .font(.caption)
                        .foregroundStyle(Theme.ink)
                }

                Text(fixedLine(info))
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(MorningCardStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Selected. Tap again to clear." : "Selects this test. Does not run it.")
    }

    private func fixedLine(_ info: SimScenario) -> String {
        var parts = [info.stage.title, shortDay(info.day)]
        if info.writesRealData { parts.append("writes real data") }
        return parts.joined(separator: " · ")
    }

    private func shortDay(_ rule: SimDayRule) -> String {
        switch rule {
        case .today: "today"
        case let .thisWeek(day): "fixed to \(day.shortLabel)"
        case .lastSunday: "last Sun 23:30"
        case .nextMonday: "next Mon 01:00"
        case .joinedPlusTwoMonths: "join + 2 months"
        case .julyFirst: "July 1"
        case .newYearsEve: "Dec 31 to Jan 1"
        case .dayless: "any day"
        }
    }

    // MARK: - Dials

    private var dialsCard: some View {
        let scenario = model.scenario
        let time = timeValue(scenario?.time ?? .notUsed)
        let gym = gymValue(scenario)
        let isStacked = dynamicTypeSize.isAccessibilitySize

        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel("What this test sets")

            let layout = isStacked
                ? AnyLayout(VStackLayout(spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                SimTimeDial(time: time.0, caption: time.1)
                SimDistanceRing(reading: scenario?.journey)
                SimGymDialView(minutes: gym.0, caption: gym.1)
            }

            if model.isStayAdjustable {
                stayStepper
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: Theme.cardRadius)
    }

    private func timeValue(_ reading: SimTimeReading) -> (TimeOfDay?, String) {
        switch reading {
        case let .fixed(time, note):
            return (time, note)
        case .planLockAlarm:
            return (store.plan.rhythm.lockAlarmTime, "from your plan")
        case let .minutesAgo(minutes, note):
            return (TimeOfDay(from: Date().addingTimeInterval(-Double(minutes) * 60)), note)
        case let .afterWindow(extra, note):
            let minutes = store.plan.windowMinutes + extra
            return (TimeOfDay(from: Date().addingTimeInterval(-Double(minutes) * 60)), note)
        case let .now(note):
            return (TimeOfDay(from: Date()), note)
        case .notUsed:
            return (nil, model.scenario == nil ? "Pick a scenario" : "Not part of this test")
        }
    }

    private func gymValue(_ scenario: SimScenario?) -> (Int?, String) {
        switch scenario?.gymTime {
        case .adjustable:
            let counts = model.stayMinutes >= SimGymDial.mark
            return (model.stayMinutes, counts ? "At or past the 20 min mark" : "Under the 20 min mark")
        case let .fixed(minutes, note):
            return (minutes, note)
        case nil:
            return (nil, scenario == nil ? "Pick a scenario" : "Not part of this test")
        }
    }

    private var stayStepper: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time at gym")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(SimGymDial.steps, id: \.self) { minutes in
                        let isSelected = minutes == model.stayMinutes
                        Button {
                            withAnimation(stateAnimation) { model.setStay(minutes) }
                        } label: {
                            Text(minutes == SimGymDial.originalMinutes ? "\(minutes) orig." : "\(minutes)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? .white : (minutes == SimGymDial.mark ? Theme.accent : Theme.ink))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(isSelected ? Theme.accent : Theme.surfaceMuted, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(minutes) minutes\(minutes == SimGymDial.originalMinutes ? ", original" : "")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text("Only backdates the arrival. Whether it counts is decided by the real proof rules, never by this dial.")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    // MARK: - Conditions

    private func conditionsCard(_ scenario: SimScenario) -> some View {
        let isDemoShield = coordinator.shield is DemoShieldService
        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Conditions")

            if scenario.conditions.contains(.screenTime) {
                conditionRow(
                    title: "Screen Time permission",
                    current: coordinator.shield.authorization.rawValue,
                    selection: $model.screenTime,
                    disabledReason: isDemoShield
                        ? "Demo shield on this build: permission does not gate the lock, so it cannot change the outcome."
                        : nil,
                    note: "Applied when you press Run."
                )
            }
            if scenario.conditions.contains(.health) {
                conditionRow(
                    title: "Health access",
                    current: SimReadingSource(store: store, coordinator: coordinator).healthLabel,
                    selection: $model.health,
                    disabledReason: nil,
                    note: "Decides whether the app asks Health for real workouts. No Health result is ever invented."
                )
            }
            ForEach(scenario.fixedNotes, id: \.self) { note in
                Label(note, systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: Theme.cardRadius)
    }

    private func conditionRow(
        title: String,
        current: String,
        selection: Binding<SimPermissionChoice>,
        disabledReason: String?,
        note: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SimReadingRow(label: title, value: "now \(current)")
            Picker(title, selection: selection) {
                ForEach(SimPermissionChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .disabled(disabledReason != nil)
            Text(disabledReason ?? note)
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        VStack(spacing: 10) {
            linkRow("All Scenarios · \(SimStep.allCases.count)", systemImage: "list.bullet") {
                path.append(.library(nil))
            }
            linkRow("Diagnostics", systemImage: "gauge.with.dots.needle.33percent") {
                path.append(.diagnostics)
            }
        }
    }

    private func linkRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.heavy))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkTertiary)
    }
}

/// Pushed pages inside the simulator sheet.
enum SimRoute: Hashable {
    case library(SimStage?)
    case result(SimStep, Date, Int?)
    case diagnostics
}
#endif
