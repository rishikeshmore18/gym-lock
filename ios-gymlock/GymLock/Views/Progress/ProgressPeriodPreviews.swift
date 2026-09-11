#if DEBUG
import SwiftUI

/// Fixtures for the period card.
///
/// Compiled only into debug builds: the shipping app derives every number from
/// the real ledger, and none of this is reachable at runtime. These exist so
/// the states that are hard to reach by hand — a finished month, a brand-new
/// user, a five-week month — can be looked at directly.
enum ProgressPreviewData {
    static let calendar = Calendar(identifier: .gregorian)

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// A plan training on the given weekdays.
    static func plan(_ days: Set<Weekday>) -> MorningPlan {
        var plan = MorningPlan.default
        plan.slots = days.isEmpty ? [] : [AlarmSlot(days: days, alarmTime: TimeOfDay(hour: 7, minute: 0))]
        return plan
    }

    static func log(_ entries: [(Date, SessionOutcomeKind)]) -> MomentumLog {
        MomentumLog(outcomes: entries.map { SessionOutcome(date: $0.0, kind: $0.1) })
    }

    /// Fills every planned day in `month` before `cutoff` with outcomes drawn
    /// from `pattern`, cycling through it.
    static func filledMonth(
        year: Int,
        month: Int,
        days: Set<Weekday>,
        cutoff: Date,
        pattern: [SessionOutcomeKind]
    ) -> MomentumLog {
        guard !pattern.isEmpty,
              let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: start)
        else { return .empty }

        var entries: [(Date, SessionOutcomeKind)] = []
        var step = 0

        for offset in range {
            guard let day = calendar.date(from: DateComponents(year: year, month: month, day: offset)),
                  day < cutoff,
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
                  days.contains(weekday)
            else { continue }

            entries.append((day, pattern[step % pattern.count]))
            step += 1
        }

        return log(entries)
    }

    static func model(
        now: Date,
        log: MomentumLog,
        plan: MorningPlan,
        schedule: GymSchedule = .default
    ) -> ProgressPeriodModel {
        let model = ProgressPeriodModel(now: now, calendar: calendar)
        model.refresh(log: log, plan: plan, schedule: schedule, now: now)
        return model
    }
}

/// Hosts a fixture chart on the app canvas.
///
/// `expandWeek` focuses a week so the week level of the chart can be inspected
/// directly, which is otherwise only reachable by tapping.
private struct ProgressPreviewStage: View {
    let model: ProgressPeriodModel
    var expandWeek: Int?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ProgressPeriodCard(
                model: model,
                appearanceDelay: 0,
                onSelectWeek: { model.selectWeek($0) },
                onCollapseWeek: { model.collapseWeek() },
                onStepMonth: { _ in },
                onStepWeek: { model.stepWeek(by: $0) }
            )
            .padding(.horizontal, 20)
        }
        .task {
            guard let expandWeek else { return }
            // Past the model's own bounce guard, which measures from init.
            model.selectWeek(expandWeek, now: Date().addingTimeInterval(1))
        }
    }
}

// MARK: - Month states

#Preview("1 · Current month, mid-flight") {
    let days: Set<Weekday> = [.monday, .wednesday, .friday]
    let now = ProgressPreviewData.date(2026, 9, 11)
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: now,
            log: ProgressPreviewData.filledMonth(
                year: 2026, month: 9, days: days, cutoff: now,
                pattern: [.showedUp, .showedUp, .homeWorkout, .showedUp]
            ),
            plan: ProgressPreviewData.plan(days)
        )
    )
}

#Preview("2 · Finished month · 75%") {
    let days: Set<Weekday> = [.monday, .wednesday, .friday]
    let now = ProgressPreviewData.date(2026, 9, 11)
    let august = ProgressPreviewData.date(2026, 9, 1)
    let model = ProgressPreviewData.model(
        now: now,
        log: ProgressPreviewData.filledMonth(
            year: 2026, month: 8, days: days, cutoff: august,
            pattern: [.showedUp, .showedUp, .homeWorkout, .missed]
        ),
        plan: ProgressPreviewData.plan(days)
    )
    model.step(
        by: -1,
        log: ProgressPreviewData.filledMonth(
            year: 2026, month: 8, days: days, cutoff: august,
            pattern: [.showedUp, .showedUp, .homeWorkout, .missed]
        ),
        plan: ProgressPreviewData.plan(days),
        schedule: .default,
        now: now
    )
    return ProgressPreviewStage(model: model)
}

#Preview("3 · All gym · 100%") {
    let days: Set<Weekday> = [.tuesday, .thursday]
    let now = ProgressPreviewData.date(2026, 9, 11)
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: now,
            log: ProgressPreviewData.filledMonth(
                year: 2026, month: 9, days: days, cutoff: now,
                pattern: [.showedUp]
            ),
            plan: ProgressPreviewData.plan(days)
        )
    )
}

#Preview("4 · Brand-new user · plans only") {
    let days: Set<Weekday> = [.monday, .wednesday, .friday]
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: ProgressPreviewData.date(2026, 9, 2),
            log: .empty,
            plan: ProgressPreviewData.plan(days)
        )
    )
}

#Preview("5 · No schedule at all") {
    ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: ProgressPreviewData.date(2026, 9, 11),
            log: .empty,
            plan: ProgressPreviewData.plan([]),
            schedule: GymSchedule(trainingDays: [], gymTime: .defaultGymTime, bedtime: .defaultBedtime)
        )
    )
}

#Preview("6 · Five week groups · Sep 2026") {
    // September 2026 starts on a Tuesday and ends on a Wednesday, so it spans
    // five Monday-first groups: Sep 1–6, 7–13, 14–20, 21–27, 28–30.
    let days: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    let now = ProgressPreviewData.date(2026, 9, 24)
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: now,
            log: ProgressPreviewData.filledMonth(
                year: 2026, month: 9, days: days, cutoff: now,
                pattern: [.showedUp, .homeWorkout, .showedUp, .missed, .showedUp]
            ),
            plan: ProgressPreviewData.plan(days)
        )
    )
}

// MARK: - Week states

#Preview("7 · Active week · 2 of 2 due") {
    let days: Set<Weekday> = [.monday, .tuesday, .thursday, .saturday]
    let now = ProgressPreviewData.date(2026, 9, 9)
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: now,
            log: ProgressPreviewData.log([
                (ProgressPreviewData.date(2026, 9, 7), .showedUp),
                (ProgressPreviewData.date(2026, 9, 8), .homeWorkout),
            ]),
            plan: ProgressPreviewData.plan(days)
        ),
        expandWeek: 1
    )
}

#Preview("8 · Finished week · 2 of 4") {
    let days: Set<Weekday> = [.monday, .tuesday, .thursday, .saturday]
    let now = ProgressPreviewData.date(2026, 9, 20)
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: now,
            log: ProgressPreviewData.log([
                (ProgressPreviewData.date(2026, 9, 7), .showedUp),
                (ProgressPreviewData.date(2026, 9, 8), .homeWorkout),
                (ProgressPreviewData.date(2026, 9, 10), .missed),
                (ProgressPreviewData.date(2026, 9, 12), .missed),
            ]),
            plan: ProgressPreviewData.plan(days)
        ),
        expandWeek: 1
    )
}

#Preview("9 · Mixed week · every state") {
    let days: Set<Weekday> = [.monday, .tuesday, .wednesday, .friday, .sunday]
    let now = ProgressPreviewData.date(2026, 9, 10)
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: now,
            log: ProgressPreviewData.log([
                (ProgressPreviewData.date(2026, 9, 7), .showedUp),
                (ProgressPreviewData.date(2026, 9, 8), .homeWorkout),
                (ProgressPreviewData.date(2026, 9, 9), .missed),
            ]),
            plan: ProgressPreviewData.plan(days)
        ),
        expandWeek: 1
    )
}

#Preview("10 · Week with nothing planned") {
    let days: Set<Weekday> = [.monday]
    let now = ProgressPreviewData.date(2026, 9, 24)
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: now,
            log: .empty,
            plan: ProgressPreviewData.plan(days)
        ),
        expandWeek: 4
    )
}

#Preview("11 · Month boundary week · Sep 28–30") {
    let days: Set<Weekday> = [.monday, .tuesday, .wednesday]
    let now = ProgressPreviewData.date(2026, 9, 30)
    return ProgressPreviewStage(
        model: ProgressPreviewData.model(
            now: now,
            log: ProgressPreviewData.log([
                (ProgressPreviewData.date(2026, 9, 28), .showedUp),
                (ProgressPreviewData.date(2026, 9, 29), .homeWorkout),
            ]),
            plan: ProgressPreviewData.plan(days)
        ),
        expandWeek: 4
    )
}
#endif
