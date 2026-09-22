import SwiftUI

/// The post-onboarding home. Shows the two locks the user committed to and
/// today's state, so the commitment made in onboarding stays visible.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    @State private var isShowingSchedule = false
    @State private var isShowingMorningPlan = false
    @State private var isRunningSetup = false
    @State private var isPickingGym = false
    @State private var isChoosingApps = false
    // TEMPORARY (dev only) — remove this and `devRestartCard` below.
    @State private var isConfirmingRestart = false
    #if DEBUG
    @State private var isShowingSimulator = false
    #endif

    private var isTrainingDayToday: Bool {
        let weekdayNumber = Calendar.current.component(.weekday, from: Date())
        guard let today = Weekday(rawValue: weekdayNumber) else { return false }
        return store.schedule.trainingDays.contains(today)
    }

    /// The alarm that will ring next, if the plan has one.
    private var nextAlarm: (slot: AlarmSlot, fireDate: Date)? {
        store.plan.nextOccurrence()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        greeting
                            .padding(.bottom, 4)

                        statusCard
                        thisMorningCard
                        morningCard
                        momentumCard
                        automationCard
                        locksCard
                        consistencyCard
                        principleCard

                        // TEMPORARY (dev only) — remove this line.
                        devRestartCard
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSimulator = true
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .accessibilityLabel("Morning simulator")
                }
                #endif

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSchedule = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Edit your locks")
                }
            }
            .sheet(isPresented: $isShowingSchedule) {
                ScheduleEditSheet()
            }
            .sheet(isPresented: $isShowingMorningPlan) {
                MorningAlarmPlanView(onSave: { isShowingMorningPlan = false })
                    .onDisappear {
                        Task { await coordinator.syncAlarms() }
                    }
            }
            .sheet(isPresented: $isPickingGym) {
                GymPickerView(onPicked: { gym in
                    store.primaryGym = gym
                    coordinator.armArrivalIfPossible()
                    coordinator.arrival.requestAlways()
                    isPickingGym = false
                })
            }
            .sheet(isPresented: $isChoosingApps) {
                BlockedAppsSetupView(onDone: { isChoosingApps = false })
            }
            #if DEBUG
            .sheet(isPresented: $isShowingSimulator) {
                DebugMorningPanel()
            }
            #endif
            .fullScreenCover(isPresented: $isRunningSetup) {
                MorningSetupFlowView {
                    isRunningSetup = false
                    Task {
                        await coordinator.requestAlarmAuthorization()
                        await coordinator.syncAlarms()
                    }
                }
            }
            .task {
                // The two morning screens run once, immediately after
                // activation, before the first alarm is finalised.
                store.seedPlanIfNeeded()
                guard !store.plan.hasBeenReviewed else { return }
                isRunningSetup = true
            }
        }
        .tint(Theme.accent)
    }

    /// The next morning at a glance, and the way into the plan.
    private var morningCard: some View {
        Button {
            Haptics.tap()
            isShowingMorningPlan = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    CelestialRhythmView(
                        phase: CelestialRhythmView.phaseNow(),
                        size: 46,
                        showsStars: false
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("your morning")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)

                        Text(nextAlarmSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }

                if let nextAlarm {
                    Divider().overlay(Theme.border)

                    HStack(spacing: 0) {
                        milestone(nextAlarm.slot.alarmTime, "wake")
                        milestoneArrow
                        milestone(
                            nextAlarm.slot.alarmTime.offset(byMinutes: store.plan.rhythm.getReadyMinutes),
                            "leave"
                        )
                        milestoneArrow
                        milestone(
                            nextAlarm.slot.gymByTime(window: store.plan.rhythm.gapToGymMinutes),
                            "gym",
                            isEmphasised: true
                        )
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
        .overlay(alignment: .bottom) { startEarlyButton }
    }

    /// For the morning you wake up before the alarm.
    ///
    /// Beating your own alarm should be rewarded, not wasted waiting for it to
    /// ring. The window is measured from the moment you commit, so starting
    /// early buys a calmer morning rather than a shorter one.
    @ViewBuilder
    private var startEarlyButton: some View {
        if coordinator.canStartEarly {
            Button {
                Haptics.medium()
                coordinator.startEarly()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("start early")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Theme.accent, in: .capsule)
                .shadow(color: Theme.accent.opacity(0.3), radius: 10, y: 3)
            }
            .offset(y: 16)
        }
    }

    private var nextAlarmSummary: String {
        guard let nextAlarm else { return "no alarm set yet" }
        let day = Calendar.current.isDateInTomorrow(nextAlarm.fireDate)
            ? "tomorrow"
            : nextAlarm.fireDate.formatted(.dateTime.weekday(.wide))
        return "\(nextAlarm.slot.alarmTime.displayString) · \(day)"
    }

    private func milestone(_ time: TimeOfDay, _ label: String, isEmphasised: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(time.displayString)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isEmphasised ? Theme.accent : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var milestoneArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.accent.opacity(0.45))
            .offset(y: -6)
    }

    /// What happened today, once the morning has resolved.
    ///
    /// Two facts, and the second one is never a failure. "No workout data"
    /// simply means nothing wrote a workout to Health — which is the normal
    /// case for anyone lifting without a watch. A red cross there would be
    /// telling people off for their choice of hardware.
    @ViewBuilder
    private var thisMorningCard: some View {
        if let outcome = store.log.outcome(), outcome.kind.preservesMomentum {
            VStack(alignment: .leading, spacing: 14) {
                Text("this morning")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkTertiary)

                todayRow(
                    icon: outcome.kind == .showedUp ? "figure.walk" : "house.fill",
                    title: outcome.kind == .showedUp ? "showed up" : "quick workout completed",
                    isConfirmed: true
                )

                todayRow(
                    icon: "heart.fill",
                    title: outcome.workoutDetected ? "workout detected" : "no workout data",
                    isConfirmed: outcome.workoutDetected
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .warmCard(radius: 20)
        }
    }

    private func todayRow(icon: String, title: String, isConfirmed: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isConfirmed ? Theme.accent : Theme.inkTertiary)
                .frame(width: 32, height: 32)
                .background(
                    (isConfirmed ? Theme.accent : Theme.inkTertiary).opacity(0.11),
                    in: .circle
                )

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isConfirmed ? Theme.ink : Theme.inkSecondary)

            Spacer(minLength: 8)

            Image(systemName: isConfirmed ? "checkmark" : "minus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isConfirmed ? Theme.accent : Theme.inkTertiary.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(isConfirmed ? "yes" : "not recorded")")
    }

    /// The automatic bits, and an honest line about what is switched on.
    ///
    /// Only shown when something needs attention or the build cannot really
    /// block. A fully configured user on an approved build sees nothing here,
    /// because a working system should be invisible.
    @ViewBuilder
    private var automationCard: some View {
        let needsGym = store.primaryGym == nil
        let needsApps = !coordinator.shield.hasSelection
        let isDemo = coordinator.shieldCapability == .demo

        if needsGym || needsApps || isDemo {
            VStack(alignment: .leading, spacing: 12) {
                Text("automatic unlock")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkTertiary)

                if needsGym {
                    setupRow(
                        icon: "mappin.and.ellipse",
                        title: "choose your gym",
                        detail: "so your apps unlock when you get there"
                    ) { isPickingGym = true }
                }

                if needsApps {
                    setupRow(
                        icon: "shield.lefthalf.filled",
                        title: "choose what to block",
                        detail: "one-time setup"
                    ) { isChoosingApps = true }
                }

                if isDemo {
                    Text("this build can't block other apps yet — real blocking needs Apple's Screen Time approval.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .warmCard(radius: 20)
        }
    }

    private func setupRow(
        icon: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The two numbers, side by side and clearly distinct.
    ///
    /// A home workout can hold the streak on the left. Only a confirmed trip to
    /// the gym moves the number on the right.
    private var momentumCard: some View {
        HStack(spacing: 12) {
            VStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)

                Text("\(store.streak.weeks)")
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)

                Text("week streak")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .warmCard(radius: 20)

            VStack(spacing: 5) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)

                Text("\(store.log.verifiedGymVisitsThisMonth)")
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)

                Text("gym visits this month")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .warmCard(radius: 20)
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("hi, \(store.greetingName).")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(
                isTrainingDayToday
                    ? "today is a training day."
                    : "no training scheduled today. rest properly."
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, 8)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: isTrainingDayToday ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        isTrainingDayToday ? Theme.accent : Theme.inkTertiary,
                        in: .circle
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(isTrainingDayToday ? "apps locked" : "apps unlocked")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(
                        isTrainingDayToday
                            ? "verify the gym to unlock"
                            : "nothing to verify today"
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                }

                Spacer()
            }

            if isTrainingDayToday {
                Divider().overlay(Theme.border)

                VStack(alignment: .leading, spacing: 12) {
                    verificationRow(
                        icon: "location.fill",
                        title: "location",
                        detail: "confirms you were at the gym"
                    )
                    verificationRow(
                        icon: "heart.fill",
                        title: "Apple Health",
                        detail: "confirms a workout was logged"
                    )
                }
            }
        }
        .padding(20)
        .warmCard()
    }

    private func verificationRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accent.opacity(0.11), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()

            Text("pending")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    private var locksCard: some View {
        VStack(spacing: 0) {
            lockRow(
                icon: "dumbbell.fill",
                title: "gym time",
                value: store.schedule.gymTime.displayString,
                subtitle: store.schedule.daysSummary
            )

            Divider().overlay(Theme.border).padding(.vertical, 16)

            lockRow(
                icon: "moon.fill",
                title: "bedtime",
                value: store.schedule.bedtime.displayString,
                subtitle: "apps lock again at night"
            )
        }
        .padding(20)
        .warmCard()
    }

    private func lockRow(icon: String, title: String, value: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.11), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()

            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
    }

    /// Consistency, framed as history rather than as a streak to protect.
    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            IllustrationView(illustration: .calendarMarking, cornerRadius: 18)
                .frame(maxHeight: 168)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text("your history")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("every verified session gets marked here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
        }
        .padding(20)
        .warmCard()
    }

    private var principleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("no guilt. no streak-shaming.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("miss a day and GymLock makes coming back easier, not heavier.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: Theme.cardRadius))
    }

    // MARK: - TEMPORARY dev affordance
    // Everything below this marker exists only to re-run onboarding while
    // building. Delete this whole section (and its two references above)
    // before shipping.

    private var devRestartCard: some View {
        VStack(spacing: 10) {
            Button {
                isConfirmingRestart = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("restart onboarding")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.ink.opacity(0.05), in: .rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(Theme.ink.opacity(0.18))
                )
            }

            Text("dev only — wipes your name and locks")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.top, 8)
        .confirmationDialog(
            "Start over as a first-time user?",
            isPresented: $isConfirmingRestart,
            titleVisibility: .visible
        ) {
            Button("Restart onboarding", role: .destructive) {
                Haptics.commit()
                store.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your name and both locks, then returns to the first screen.")
        }
    }
}

/// Lets the user revisit the two locks after onboarding.
private struct ScheduleEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var gymTime = Date()
    @State private var bedtime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("gym time") {
                    DatePicker("alarm", selection: $gymTime, displayedComponents: .hourAndMinute)
                    ForEach(Weekday.allCases) { day in
                        Toggle(
                            day.shortLabel,
                            isOn: Binding(
                                get: { store.schedule.trainingDays.contains(day) },
                                set: { _ in store.toggleTrainingDay(day) }
                            )
                        )
                    }
                }

                Section("bedtime") {
                    DatePicker("lock again until", selection: $bedtime, displayedComponents: .hourAndMinute)
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Your locks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                gymTime = store.schedule.gymTime.asDateToday
                bedtime = store.schedule.bedtime.asDateToday
            }
            .onChange(of: gymTime) { _, newValue in
                store.schedule.gymTime = TimeOfDay(from: newValue)
            }
            .onChange(of: bedtime) { _, newValue in
                store.schedule.bedtime = TimeOfDay(from: newValue)
            }
        }
    }
}
