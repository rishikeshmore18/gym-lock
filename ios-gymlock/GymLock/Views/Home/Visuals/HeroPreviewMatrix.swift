import SwiftUI

// MARK: - Preview matrix
//
// Every hero state rendered side by side with the mini-card row, so the whole
// family can be inspected as one product rather than compiled in isolation.
// States that do not exist in the current build are driven by the stage enum
// directly — the previews are the specification, the deriver is the runtime.

private struct StageCanvas: View {
    let stage: HeroStage
    var protection: ProtectionCard
    var next: NextCard
    var path: PathCard

    init(
        stage: HeroStage,
        protection: ProtectionCard = ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        next: NextCard = NextCard(eyebrow: "NEXT", value: "6:40 AM", detail: "Tomorrow", showsArrow: true),
        path: PathCard = PathCard(completedSteps: 0, placeholder: nil)
    ) {
        self.stage = stage
        self.protection = protection
        self.next = next
        self.path = path
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 14) {
                HeroCardView(stage: stage)
                MiniCardsRow(protection: protection, next: next, path: path)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 24)
        }
        .background(Theme.canvas)
    }
}

private let sampleWeekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

#Preview("1 · First day") {
    StageCanvas(
        stage: .firstDay(alarm: TimeOfDay(hour: 6, minute: 40)),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        path: PathCard(completedSteps: 0, placeholder: nil)
    )
}

#Preview("2 · Setup incomplete") {
    StageCanvas(
        stage: .setupIncomplete(items: [
            ChecklistItem(id: "apps", label: "Apps locked", isDone: true),
            ChecklistItem(id: "alarm", label: "Alarm ready", isDone: true),
            ChecklistItem(id: "gym", label: "Gym selected", isDone: false),
        ]),
        protection: ProtectionCard(mood: .unset, appCount: 0, detail: "choose apps in setup"),
        next: NextCard(eyebrow: "NEXT", value: "Set alarm", detail: nil, showsArrow: true)
    )
}

#Preview("3 · Night") {
    StageCanvas(
        stage: .night(bedtime: TimeOfDay(hour: 23, minute: 10), nextAlarm: TimeOfDay(hour: 6, minute: 40)),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        path: PathCard(completedSteps: 0, placeholder: "Tomorrow is ready")
    )
}

#Preview("4 · Pre-session countdown") {
    StageCanvas(
        stage: .countdown(secondsRemaining: 2 * 3600 + 18 * 60 + 24, windowSeconds: 2 * 3600),
        protection: ProtectionCard(mood: .shielding, appCount: 3, detail: "until verification"),
        next: NextCard(eyebrow: "LEAVE", value: "6:58 AM", detail: nil, showsArrow: true),
        path: PathCard(completedSteps: 0, placeholder: nil)
    )
}

#Preview("5 · Committed") {
    StageCanvas(
        stage: .committed(step: 1, total: 4),
        protection: ProtectionCard(mood: .shielding, appCount: 3, detail: "until verification"),
        next: NextCard(eyebrow: "LEAVE", value: "6:58 AM", detail: nil, showsArrow: true),
        path: PathCard(completedSteps: 1, placeholder: nil)
    )
}

#Preview("6 · Departed") {
    StageCanvas(
        stage: .departed(step: 2, total: 4, nearGym: false),
        protection: ProtectionCard(mood: .shielding, appCount: 3, detail: "until verification"),
        next: NextCard(eyebrow: "NEXT", value: "Gym", detail: nil, showsArrow: true),
        path: PathCard(completedSteps: 2, placeholder: nil)
    )
}

#Preview("7 · Arrived") {
    StageCanvas(
        stage: .arrived(step: 3, total: 4),
        protection: ProtectionCard(mood: .released, appCount: 3, detail: "until next session"),
        next: NextCard(eyebrow: "NOW", value: "Train", detail: nil, showsArrow: false),
        path: PathCard(completedSteps: 3, placeholder: nil)
    )
}

#Preview("8 · Verified") {
    StageCanvas(
        stage: .verified(step: 4, total: 4, streak: 5),
        protection: ProtectionCard(mood: .released, appCount: 3, detail: "until next session"),
        next: NextCard(eyebrow: "NEXT", value: "Recover", detail: nil, showsArrow: false),
        path: PathCard(completedSteps: 4, placeholder: nil)
    )
}

#Preview("9 · Day complete") {
    StageCanvas(
        stage: .restDay(nextDay: "Tomorrow", nextTime: nil),
        protection: ProtectionCard(mood: .released, appCount: 3, detail: "until next session"),
        next: NextCard(eyebrow: "NEXT", value: "Recover", detail: nil, showsArrow: false),
        path: PathCard(completedSteps: 4, placeholder: nil)
    )
}

#Preview("10 · Week progress") {
    StageCanvas(
        stage: .weekProgress(done: 2, of: 4, useDots: true),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        path: PathCard(completedSteps: 0, placeholder: "Pattern building")
    )
}

#Preview("11 · Week consistency") {
    StageCanvas(
        stage: .weekProgress(done: 4, of: 5, useDots: false),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm")
    )
}

#Preview("12 · Pattern insight") {
    StageCanvas(
        stage: .pattern(
            weekdayLabels: sampleWeekdayLabels,
            values: [1, 3, 0, 3, 1, 0, 1],
            bestIndex: 1
        ),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm")
    )
}

#Preview("13 · Month complete") {
    StageCanvas(
        stage: .monthComplete(sessions: 12, consistency: 83),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        path: PathCard(completedSteps: 0, placeholder: "Pattern holding")
    )
}

#Preview("14 · Missed") {
    StageCanvas(
        stage: .missed,
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        next: NextCard(eyebrow: "NEXT", value: "6:40 AM", detail: "Tomorrow", showsArrow: true),
        path: PathCard(completedSteps: 0, placeholder: "Today reset — tomorrow is ready")
    )
}

#Preview("15 · Comeback") {
    StageCanvas(
        stage: .comeback,
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        next: NextCard(eyebrow: "NEXT", value: "6:40 AM", detail: "Today", showsArrow: true),
        path: PathCard(completedSteps: 0, placeholder: "One step wins today")
    )
}

#Preview("16 · Start of month") {
    StageCanvas(
        stage: .startMonth(totalSessions: 14, goal: 12),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        path: PathCard(completedSteps: 0, placeholder: "Pattern holding")
    )
}

#Preview("17 · Mid month") {
    StageCanvas(
        stage: .midMonth(done: 8, of: 12, percent: 67),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        path: PathCard(completedSteps: 0, placeholder: "Pattern holding")
    )
}

#Preview("18 · Late month pattern") {
    StageCanvas(
        stage: .latePattern(momentumDays: 18),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        path: PathCard(completedSteps: 0, placeholder: "Pattern holding")
    )
}

#Preview("Rest day") {
    StageCanvas(
        stage: .restDay(nextDay: "Tue", nextTime: "6:40 AM"),
        protection: ProtectionCard(mood: .ready, appCount: 3, detail: "armed for the alarm"),
        next: NextCard(eyebrow: "NEXT", value: "6:40 AM", detail: "Tue", showsArrow: true),
        path: PathCard(completedSteps: 0, placeholder: "Next session ready")
    )
}
