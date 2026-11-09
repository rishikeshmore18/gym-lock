#if DEBUG
import Foundation
import Testing
@testable import GymLock

/// Parity between the Day Flow Simulator and every `DebugStep`. If a new step
/// is added and not reachable, or the run rules drift from the original
/// panel, these fail.
@MainActor
struct DebugScenarioLibraryTests {
    // MARK: - Fixtures

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    /// Monday 7 September 2026, 10:00 Berlin.
    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10)) ?? Date()
    }

    private final class Recorder {
        var simulated: [SimStep] = []
        var stays: [Int] = []
        var screenTime: [Bool] = []
        var health: [Bool] = []
        var total: Int { simulated.count + stays.count }
    }

    private func runner(_ recorder: Recorder, onSimulate: (@MainActor () -> Void)? = nil) -> SimRunner {
        SimRunner(
            applyScreenTime: { recorder.screenTime.append($0) },
            applyHealth: { recorder.health.append($0) },
            simulate: { recorder.simulated.append($0); onSimulate?() },
            simulateStay: { recorder.stays.append($0) }
        )
    }

    /// Copied from the original panel, so a change to either is caught.
    private let originalStaysOpen: Set<SimStep> = [
        .familyControlsAuthorized, .familyControlsDenied,
        .badGPSAccuracy, .goodGPSAccuracy,
        .healthDenied, .noHealthWorkout, .driveBy,
        .foregroundAfterWindow, .foregroundAfterResolved,
        .windDownLockStart, .windDownLockEnd, .windDownWhileSessionLive,
        .tapArrivalAfterGym, .tapDepartureMidSession, .tapWindDownAtNight,
        .legacyUserTwoGymDays, .changePlanMidWeek,
        .sundayLateAlarmVisitAfterMidnight, .tryRemoveGymDayAtThree,
        .legacyEveningUser, .changeBedtimeTonight,
        .bedtimeAfterMidnightGymMonday, .oldPlanNightLockOff,
        .wakeAndGoGymDay, .goLaterGymDay, .plainWakeAlarmRings,
        .ignoreAlarmUntilDeadline, .runningLateNearBedtime,
        .runningLateTwice, .phoneWasOffOnGymDay,
        .arriveStay20, .arriveLeaveAt12, .stepOutThreeMinutes, .healthWorkout22,
        .handTypedWorkout, .unplannedVisit, .visitInSleepHours, .imHereCameraPhoto,
        .use3HomeWorkouts, .homeWorkoutNoHealthPhoto, .cancelAReschedule,
        .jumpTwoMonthsAfterJoining, .jumpToJuly1, .newYearFreezesExpire,
        .planFreezeThisWeek, .atRiskThursday, .atRiskSunday, .atRiskHomeWorkoutsUsedUp,
        .ringerStart, .ringerEscalated, .ringerStop, .ringerCeiling,
        .customSongMissing, .customSongProtected,
    ]

    // MARK: - Coverage

    @Test func everyStepAppearsExactlyOnceInTheLibrary() {
        let listed = SimStep.sections.flatMap { SimCatalog.steps(inSection: $0) }
        #expect(listed.count == SimStep.allCases.count)
        #expect(Set(listed) == Set(SimStep.allCases))
        #expect(SimStep.allCases.count == 89)
    }

    @Test func fifteenOriginalSectionsAllNonEmpty() {
        #expect(SimStep.sections.count == 15)
        #expect(Set(SimStep.sections).count == 15)
        #expect(Set(SimStep.allCases.map(\.section)) == Set(SimStep.sections))
        for section in SimStep.sections {
            #expect(!SimCatalog.steps(inSection: section).isEmpty, "empty section \(section)")
        }
    }

    @Test func everyStepIsReachableFromAStage() {
        let byStage = SimStage.allCases.flatMap { SimCatalog.steps(in: $0) }
        #expect(byStage.count == SimStep.allCases.count)
        #expect(Set(byStage) == Set(SimStep.allCases))
    }

    @Test func calendarEntryHoldsTheSevenCases() {
        let steps = SimCatalog.steps(inSection: SimCatalog.calendarSection)
        #expect(steps == SimCatalog.calendarSteps)
        #expect(steps.count == 7)
        #expect(SimCatalog.sectionTitle(SimCatalog.calendarSection) == "Calendar, Streaks & Freezes")
        #expect(Set(steps) == [
            .jumpTwoMonthsAfterJoining, .jumpToJuly1, .newYearFreezesExpire,
            .planFreezeThisWeek, .atRiskThursday, .atRiskSunday, .atRiskHomeWorkoutsUsedUp,
        ])
    }

    @Test func metadataIsCompleteAndKeepsOriginalLabels() {
        for step in SimStep.allCases {
            let info = SimCatalog.scenario(for: step)
            #expect(info.step == step)
            #expect(info.title == step.label)
            #expect(!info.summary.isEmpty, "\(step) has no summary")
            #expect(!info.expected.isEmpty, "\(step) has no expected")
            #expect(!info.summary.contains("\u{2014}") && !info.expected.contains("\u{2014}"), "\(step) uses an em-dash")
        }
    }

    @Test func presetsAreValid() {
        for stage in SimStage.allCases {
            let presets = stage.presets
            #expect((3...5).contains(presets.count), "\(stage) has \(presets.count) presets")
            #expect(Set(presets).count == presets.count)
            for step in presets {
                #expect(SimCatalog.scenario(for: step).stage == stage, "\(step) is not a \(stage) scenario")
            }
        }
    }

    @Test func staysOpenMatchesTheOriginalPanel() {
        #expect(SimCatalog.staysOpen == originalStaysOpen)
        #expect(SimCatalog.playsAfterClose == [.tapWorkoutDoneNotification])
        #expect(SimCatalog.staysOpen.isDisjoint(with: SimCatalog.playsAfterClose))
        #expect(!SimCatalog.staysOpen.contains(.runningLate30))
    }

    // MARK: - Selection and run

    @Test func selectingNeverRuns() {
        let model = DaySimulatorModel(now: monday, calendar: calendar)
        let recorder = Recorder()
        _ = runner(recorder)
        for step in SimStep.allCases { model.select(step) }
        #expect(recorder.total == 0)
        #expect(recorder.screenTime.isEmpty && recorder.health.isEmpty)
        #expect(model.selectedStep == SimStep.allCases.last)
    }

    @Test func runCallsSimulateExactlyOnceWithTheRightDisposition() {
        for step in SimStep.allCases {
            let model = DaySimulatorModel(now: monday, calendar: calendar)
            let recorder = Recorder()
            model.select(step)
            let disposition = model.run(using: runner(recorder))

            if SimCatalog.playsAfterClose.contains(step) {
                #expect(disposition == .closeThenRun)
                #expect(recorder.total == 0)
                model.flushPendingAfterClose(using: runner(recorder))
                model.flushPendingAfterClose(using: runner(recorder))
                #expect(recorder.simulated == [step])
            } else {
                #expect(recorder.simulated == [step], "\(step) ran \(recorder.simulated)")
                #expect(disposition == (originalStaysOpen.contains(step) ? .showResult : .dismiss))
            }
        }
    }

    @Test func aRunCannotStartWhileOneIsInFlight() {
        let model = DaySimulatorModel(now: monday, calendar: calendar)
        let recorder = Recorder()
        var nested: SimRunDisposition?? = .none
        model.select(.alarmFired)
        let inner = runner(recorder) {
            nested = .some(model.run(using: runner(recorder)))
        }
        model.run(using: inner)
        #expect(recorder.simulated == [.alarmFired])
        #expect(nested == .some(nil))
        #expect(!model.isRunning)
    }

    @Test func nothingRunsWithoutASelection() {
        let model = DaySimulatorModel(now: monday, calendar: calendar)
        let recorder = Recorder()
        #expect(model.run(using: runner(recorder)) == nil)
        #expect(recorder.total == 0)
    }

    // MARK: - Day rules

    @Test func fixedDayScenariosLockTheDayRow() {
        let model = DaySimulatorModel(now: monday, calendar: calendar)
        model.select(.exampleB)
        #expect(model.selectedDay == .tuesday)
        #expect(!model.isDayAdjustable)
        model.selectDay(.friday)
        #expect(model.selectedDay == .tuesday)

        model.select(.atRiskSunday)
        #expect(model.selectedDay == .sunday)
        model.select(.atRiskThursday)
        #expect(model.selectedDay == .thursday)
    }

    @Test func realClockScenariosOnlyRunOnToday() {
        let model = DaySimulatorModel(now: monday, calendar: calendar)
        let recorder = Recorder()
        model.select(.alarmFired)
        #expect(model.selectedDay == .monday)
        model.selectDay(.wednesday)
        #expect(model.runBlocker != nil)
        #expect(model.run(using: runner(recorder)) == nil)
        #expect(recorder.total == 0)
        model.useToday()
        #expect(model.runBlocker == nil)
        model.run(using: runner(recorder))
        #expect(recorder.simulated == [.alarmFired])
    }

    @Test func relativeDatesFollowTheHandlers() {
        let joined = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)) ?? monday
        let twoMonths = SimCatalog.resolvedDate(for: .joinedPlusTwoMonths, joinedAt: joined, now: monday, calendar: calendar)
        #expect(twoMonths == calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        let july = SimCatalog.resolvedDate(for: .julyFirst, joinedAt: joined, now: monday, calendar: calendar)
        #expect(july == calendar.date(from: DateComponents(year: 2027, month: 7, day: 1)))
        let lastSunday = SimCatalog.resolvedDate(for: .lastSunday, joinedAt: joined, now: monday, calendar: calendar)
        #expect(lastSunday == calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))
        let wednesday = SimCatalog.resolvedDate(for: .thisWeek(.wednesday), joinedAt: joined, now: monday, calendar: calendar)
        #expect(wednesday == calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
    }

    // MARK: - Time at gym

    @Test func stayDialOnlyMovesArriveStay20() {
        let model = DaySimulatorModel(now: monday, calendar: calendar)
        let recorder = Recorder()

        model.select(.arriveLeaveAt12)
        model.setStay(5)
        #expect(model.stayMinutes == SimGymDial.originalMinutes)

        model.select(.arriveStay20)
        model.run(using: runner(recorder))
        #expect(recorder.simulated == [.arriveStay20])
        #expect(recorder.stays.isEmpty)

        model.setStay(12)
        model.run(using: runner(recorder))
        #expect(recorder.stays == [12])
        #expect(recorder.simulated == [.arriveStay20])

        model.setStay(99)
        #expect(model.stayMinutes == SimGymDial.range.upperBound)
        model.setStay(-4)
        #expect(model.stayMinutes == 0)

        model.select(.healthWorkout22)
        model.select(.arriveStay20)
        #expect(model.stayMinutes == SimGymDial.originalMinutes)
    }

    @Test func gymDialMarkIsTheRealRule() {
        #expect(SimGymDial.mark == WorkoutRules.minimumMinutes)
        #expect(SimGymDial.steps.contains(SimGymDial.mark))
        #expect(SimGymDial.steps.contains(SimGymDial.originalMinutes))
        #expect(SimGymDial.steps.allSatisfy { SimGymDial.range.contains($0) })
        let adjustable = SimStep.allCases.filter { SimCatalog.scenario(for: $0).gymTime == .adjustable }
        #expect(adjustable == [.arriveStay20])
    }

    // MARK: - Conditions

    @Test func conditionsApplyOnlyOnRunAndOnlyWhereRelevant() {
        let model = DaySimulatorModel(now: monday, calendar: calendar)
        let recorder = Recorder()

        model.select(.alarmFired)
        model.run(using: runner(recorder))
        #expect(recorder.screenTime.isEmpty)

        model.screenTime = .denied
        #expect(recorder.screenTime.isEmpty)
        model.run(using: runner(recorder))
        #expect(recorder.screenTime == [false])

        // Not a screen time scenario: the draft is cleared and never applied.
        model.select(.ringerStart)
        #expect(model.screenTime == .asIs)
        model.screenTime = .granted
        model.run(using: runner(recorder))
        #expect(recorder.screenTime == [false])
        #expect(recorder.health.isEmpty)
    }
}
#endif
