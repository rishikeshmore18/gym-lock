#if DEBUG
import Foundation
import Observation

/// What the simulator needs from the app to run a scenario. Real runs pass
/// the coordinator; tests pass recording closures.
struct SimRunner {
    var applyScreenTime: @MainActor (Bool) -> Void
    var applyHealth: @MainActor (Bool) -> Void
    var simulate: @MainActor (SimStep) -> Void
    var simulateStay: @MainActor (Int) -> Void
}

/// What the panel does after Run.
enum SimRunDisposition: Equatable {
    /// The scenario ran; show the Test Result view.
    case showResult
    /// The scenario ran; close the simulator so the flow is visible.
    case dismiss
    /// Close instantly; the scenario runs once the sheet is gone.
    case closeThenRun
}

/// The draft the simulator edits. Nothing here touches the saved plan:
/// the selected day and every control are throwaway until Run.
@MainActor
@Observable
final class DaySimulatorModel {
    let calendar: Calendar
    let now: Date

    private(set) var selectedDay: Weekday
    var stage: SimStage = .alarm
    private(set) var selectedStep: SimStep?
    private(set) var stayMinutes: Int = SimGymDial.originalMinutes
    var screenTime: SimPermissionChoice = .asIs
    var health: SimPermissionChoice = .asIs

    /// True between Run and the scenario returning, so a double tap can never
    /// start a second run.
    private(set) var isRunning = false
    /// A scenario waiting for the sheet to close.
    private(set) var pendingAfterClose: SimStep?

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        self.selectedDay = Weekday(rawValue: calendar.component(.weekday, from: now)) ?? .monday
    }

    var today: Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: now)) ?? .monday
    }

    var scenario: SimScenario? { selectedStep.map(SimCatalog.scenario(for:)) }

    // MARK: - Selection

    /// Selects a scenario. It never runs anything, and it clears every draft
    /// control so one scenario's settings cannot leak into another.
    func select(_ step: SimStep) {
        selectedStep = step
        let info = SimCatalog.scenario(for: step)
        stage = info.stage
        stayMinutes = SimGymDial.originalMinutes
        screenTime = .asIs
        health = .asIs
        if let locked = info.day.lockedWeekday {
            selectedDay = locked
        } else if info.day == .today {
            selectedDay = today
        }
    }

    func clearSelection() {
        selectedStep = nil
        stayMinutes = SimGymDial.originalMinutes
        screenTime = .asIs
        health = .asIs
    }

    // MARK: - Day

    /// Whether the day row accepts taps. Scenarios that set their own day
    /// lock it; with none selected the day is a free draft.
    var isDayAdjustable: Bool {
        guard let scenario else { return true }
        return scenario.day.isDraftAdjustable
    }

    func selectDay(_ day: Weekday) {
        guard isDayAdjustable else { return }
        selectedDay = day
    }

    func useToday() { selectedDay = today }

    /// Scenarios that act on the selected day, offered when it is not today.
    var scenariosForSelectedDay: [SimStep] {
        SimStep.allCases.filter { SimCatalog.scenario(for: $0).day.lockedWeekday == selectedDay }
    }

    // MARK: - Time at gym

    var isStayAdjustable: Bool { scenario?.gymTime == .adjustable }

    func setStay(_ minutes: Int) {
        guard isStayAdjustable else { return }
        stayMinutes = min(max(minutes, SimGymDial.range.lowerBound), SimGymDial.range.upperBound)
    }

    // MARK: - Run

    /// Why Run is disabled, or nil when it can run.
    var runBlocker: String? {
        guard let scenario else { return "Pick a scenario first." }
        if isRunning { return "A test is already running." }
        if scenario.day == .today, selectedDay != today {
            return "This test uses the real clock, so it can only run on today (\(today.shortLabel))."
        }
        return nil
    }

    /// Runs the selected scenario exactly once.
    @discardableResult
    func run(using runner: SimRunner) -> SimRunDisposition? {
        guard runBlocker == nil, let scenario else { return nil }
        isRunning = true
        defer { isRunning = false }

        applyConditions(for: scenario, using: runner)

        if scenario.playsAfterClose {
            pendingAfterClose = scenario.step
            return .closeThenRun
        }

        perform(scenario.step, using: runner)
        return scenario.staysOpen ? .showResult : .dismiss
    }

    /// Runs the step held back by `.closeThenRun`, once.
    func flushPendingAfterClose(using runner: SimRunner) {
        guard let step = pendingAfterClose else { return }
        pendingAfterClose = nil
        runner.simulate(step)
    }

    private func perform(_ step: SimStep, using runner: SimRunner) {
        if step == .arriveStay20, stayMinutes != SimGymDial.originalMinutes {
            runner.simulateStay(stayMinutes)
        } else {
            runner.simulate(step)
        }
    }

    private func applyConditions(for scenario: SimScenario, using runner: SimRunner) {
        if scenario.conditions.contains(.screenTime), screenTime != .asIs {
            runner.applyScreenTime(screenTime == .granted)
        }
        if scenario.conditions.contains(.health), health != .asIs {
            runner.applyHealth(health == .granted)
        }
    }
}
#endif
