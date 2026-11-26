import SwiftUI

/// The one skip screen (FLOW, Flow 4), the "can't today" page.
///
/// The same screen appears whether they tapped "can't today" or slept through the alarm. The heading
/// and the order of the doors follow one question: can they still reach this week's goal with the
/// planned days left? There is no skip budget and nothing is taken away.
///
/// This view owns the data and the doors' actions. A look draws everything else, and picks itself the
/// same way the "plans changed" pause does: Day 0 at the worst moment to skip (`PauseFacts.isCritical`),
/// otherwise Ridge or the Matrix printer following the hero card style. Approved prototype:
/// docs/prototypes/cant-today-variations.html (the three "b" versions).
struct CantTodayView: View {
    let session: GymSession
    let plan: SkipScreenPlan
    let choices: [ReschedulePlanner.Choice]
    let defaultTimeFor: (Date) -> TimeOfDay
    let isTimeAvailable: (Date, TimeOfDay) -> Bool
    let isComebackModeOn: Bool
    let onReschedule: (Date, TimeOfDay) -> Void
    let onHomeWorkout: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void
    /// Opened from the Home banner's "reschedule for today": the time reel is open straight away.
    var startsOnPicker = false
    var onPickerShown: () -> Void = {}

    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HeroCardStyle.storageKey) private var cardStyleRaw = HeroCardStyle.default.rawValue

    /// Read once when the screen opens, so nothing shifts under the user while they choose.
    @State private var model: CantTodayModel?
    @State private var haptics = PauseHaptics()

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom
            )
            ZStack {
                (model?.look.isDark ?? true ? Color(red: 0.043, green: 0.043, blue: 0.047) : Theme.canvas)

                if let model {
                    let input = CantTodayInput(
                        data: model.data,
                        facts: model.facts,
                        layout: CantTodayLayout(size: full, safeArea: insets),
                        reduceMotion: reduceMotion,
                        haptics: haptics,
                        actions: CantTodayActions(
                            reschedule: onReschedule,
                            homeWorkout: onHomeWorkout,
                            skip: onSkip,
                            close: onBack
                        ),
                        startsOnReschedule: startsOnPicker
                    )
                    look(model.look, input)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear(perform: start)
        .onDisappear { haptics.stop() }
        .blocksHeroHaptics("cantToday")
    }

    @ViewBuilder
    private func look(_ look: PauseLook, _ input: CantTodayInput) -> some View {
        switch look {
        case .ridge: RidgeCantTodayB(input: input)
        case .matrixPrinter: MatrixPrinterCantTodayB(input: input)
        case .day0: Day0CantTodayB(input: input)
        }
    }

    private func start() {
        guard model == nil else { return }
        let facts = PauseFactsProvider.facts(
            store: store,
            coordinator: coordinator,
            session: session,
            context: .windowOpen
        )
        let style = HeroCardStyle(rawValue: cardStyleRaw) ?? .default
        let look: PauseLook = facts.isCritical ? .day0 : (style == .matrix ? .matrixPrinter : .ridge)
        let data = CantTodayDataProvider.make(
            plan: plan,
            facts: facts,
            choices: choices,
            defaultTimeFor: defaultTimeFor,
            isTimeAvailable: isTimeAvailable,
            comebackMode: isComebackModeOn,
            sleepFor: { [store] day in
                let r = store.plan.rhythm(at: day)
                return (bed: r.bedtime, wake: r.wakeTime)
            }
        )
        model = CantTodayModel(data: data, facts: facts, look: look)
        haptics.prepare()
        if startsOnPicker { onPickerShown() }
    }
}

/// Read once when the screen opens.
private struct CantTodayModel {
    let data: CantTodayData
    let facts: PauseFacts
    let look: PauseLook
}
