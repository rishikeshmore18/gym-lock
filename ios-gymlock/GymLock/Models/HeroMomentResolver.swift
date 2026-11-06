import Foundation

// MARK: - Rules

enum HeroMomentRules {
    /// Moments a user meets once in their life (spec §2.2).
    static let onceEver: Set<MatrixMoment> = [.automatic, .halfway, .drift]
    /// The countdown runs in the last two hours before a ring.
    static let countdownLead: TimeInterval = 2 * 3600
    /// Comeback shows for at most three display days per lapse.
    static let comebackMaxDays = 3
    /// A lapse: this many days without a counted session.
    static let lapseDays = 8
    /// stilltime: the last start leaves 30 min of workout and 20 min of wind-down before bed.
    static let eveningBuffer = 50
    static let halfwayWindow = 33...39
    static let driftWindow = 22...35
    static let automaticFrom = 66
}

// MARK: - Output

/// What the Dynamic hero card shows right now.
struct HeroMomentState: Equatable {
    var moment: MatrixMoment
    var theme: HeroTheme
    var pos: HeroWeekPos
    var monthPos: MatrixMonthPos
    var dayData: MatrixDayData
    var clock: MatrixLiveClock
    var copy: MatrixCardCopy
    /// The display day "yyyy-MM-dd" (04:00 rollover).
    var dayKey: String
    var accessibilityLabel: String

    /// "dayKey|moment|style": the scene-haptics play-once entry (spec §6.2).
    func hapticsEntry(style: HeroCardStyle) -> String { "\(dayKey)|\(moment.rawValue)|\(style.rawValue)" }

    func input(hapticsEnabled: Bool) -> MatrixCardInput {
        MatrixCardInput(moment: moment, day: theme.rawValue, pos: pos.visual, dayData: dayData, clock: clock, copy: copy, entrance: .onAppear, hapticsEnabled: hapticsEnabled)
    }
}

// MARK: - Facts

/// Everything the decision reads, gathered once from the app. Plain values so `decide` is pure.
struct HeroDayFacts: Equatable {
    var now: Date
    var displayDay: Date
    var dayKey: String
    /// Monday = 0 ... Sunday = 6, of the display day.
    var weekday: Int
    var hour: Int

    // Session
    var sessionState: GymSessionState?
    var visitArrivedAt: Date?
    var visitTimeCounts = true
    var visitPendingExitAt: Date?

    // Today
    var todayCounts = false
    var todayKind: SessionOutcomeKind?
    var plannedToday = false
    var rescheduledToday = false
    var ringToday: Date?
    var nextRing: Date?
    var nextRingIsTomorrow = false
    var lastStartToday: Date?

    // Setup, lock and night
    var setupDone: [Bool] = [true, true, true]
    var isPreArmed = false
    var windDownActive = false
    var appsLocked = false
    var lockEnd: Date?

    // History
    var countedDays: [Date] = []          // display-calendar start of each counted day, ascending, unique
    var weekGoal = 3
    var weekCount = 0
    var isThisWeekKept = false
    var streakWeeks = 0
    var lastWeekCount = 0
    var lastWeekGoal = 3
    var hadKeptWeek = false
    var yesterdayPlanned = false
    var yesterdayKind: SessionOutcomeKind?
    var yesterdayCounts = false

    // Month
    var monthName: String?
    var monthKey = ""
    var dayOfMonth = 1
    var daysLeftInMonth = 0
    var earlierCountedThisMonth = 0
    var monthSessions = 0
    var plannedDaysLeftInMonth = 0
    var recapShownThisMonth = false
    var monthTarget: Int?

    // Words
    var gymName: String?
    var gymBy: String?
    var ringLabel: String?
    var nextDayLabel: String?
    var tomorrowPlanned = false
    var frozenEndLabel: String?

    var neverCounted: Bool { countedDays.isEmpty }
    var totalCounted: Int { countedDays.count }

    func habitDay(_ cal: Calendar) -> Int? {
        guard let first = countedDays.first else { return nil }
        return (cal.dateComponents([.day], from: first, to: displayDay).day ?? 0) + 1
    }

    /// Days since the last counted session before today (nil when never counted).
    func daysSinceLastCount(_ cal: Calendar) -> Int? {
        guard let last = countedDays.last(where: { $0 < displayDay }) else { return nil }
        return cal.dateComponents([.day], from: last, to: displayDay).day
    }
}

// MARK: - Resolver

@MainActor
enum HeroMomentResolver {
    static func displayCalendar() -> Calendar { ProgressAnalytics.displayCalendar(.current) }

    /// Resolves the card and commits what the day freezes (theme, ambient slot, once-ever spend).
    static func resolve(store: AppStore, coordinator: GymSessionCoordinator, now: Date = Date(), rotation: HeroRotationStore = .shared) -> HeroMomentState {
        let cal = displayCalendar()
        let f = gather(store: store, coordinator: coordinator, now: now, cal: cal, rotation: rotation)
        return state(for: f, cal: cal, rotation: rotation, commit: true)
    }

    /// Same answer without writing anything (the style preview, the lab).
    static func peek(store: AppStore, coordinator: GymSessionCoordinator, now: Date = Date(), rotation: HeroRotationStore = .shared) -> HeroMomentState {
        let cal = displayCalendar()
        let f = gather(store: store, coordinator: coordinator, now: now, cal: cal, rotation: rotation)
        return state(for: f, cal: cal, rotation: rotation, commit: false)
    }

    static func state(for f: HeroDayFacts, cal: Calendar, rotation: HeroRotationStore, commit: Bool) -> HeroMomentState {
        var moment = functional(f, cal: cal)
        var missedToday = false
        if moment == nil, f.plannedToday, !f.todayCounts, isOffPlan(f) == false, let ring = f.ringToday, ring <= f.now {
            moment = .missed
            missedToday = true
        }

        // Halfway and automatic replace verified for the rest of a crossing day (spec §2.3).
        if moment == .verified, let milestone = milestoneOnVerified(f, cal: cal, ledger: rotation.ambient) {
            moment = milestone
            if commit { rotation.spendOnceEver(milestone, dayKey: f.dayKey) }
        }

        let resolved: MatrixMoment
        if let moment {
            resolved = moment
        } else if let frozen = rotation.ambientMoment(dayKey: f.dayKey) {
            resolved = frozen
        } else {
            let pick = ambient(f, cal: cal, ledger: rotation.ambient)
            if commit {
                rotation.freezeAmbient(pick.moment, dayKey: f.dayKey, oldestKey: ThemeRotation.key(cal.date(byAdding: .day, value: -60, to: f.displayDay)!, cal))
                if pick.moment == .comeback, let lapse = pick.lapse { rotation.noteComeback(lapse: lapse, dayKey: f.dayKey) }
            }
            resolved = pick.moment
        }

        // A training day with nothing ambient to say counts down to its ring instead of calling it rest.
        let final: MatrixMoment = (resolved == .rest && f.plannedToday && !isOffPlan(f) && (f.ringToday.map { $0 > f.now } ?? false)) ? .countdown : resolved

        let theme = themeFor(f, cal: cal, rotation: rotation, commit: commit)
        return assemble(final, f: f, theme: theme, missedToday: missedToday, cal: cal)
    }

    // MARK: Functional (01-app-map §3.3 order)

    static func functional(_ f: HeroDayFacts, cal: Calendar) -> MatrixMoment? {
        if let s = f.sessionState {
            switch s {
            case .alarmFired, .awaitingDecision, .snoozed, .runningLate, .activationMission: return .wake
            case .preparing, .quickWorkoutOffered, .quickWorkoutActive: return .ready
            case .departed, .approachingGym, .arrivalTrouble: return .commute
            default: break
            }
        }
        if !f.todayCounts {
            if f.sessionState == .arrived || f.visitArrivedAt != nil || f.sessionState == .homeWorkoutAwaitingProof { return .atgym }
        }
        if f.todayCounts || f.sessionState == .homeWorkoutVerified { return .verified }
        if f.setupDone.contains(false) { return .setup }
        if f.isPreArmed { return .paused }
        let night = f.windDownActive || f.hour >= 21 || f.hour < 4
        if f.neverCounted, f.nextRingIsTomorrow, night { return .firstnight }
        if f.windDownActive { return .bedtime }
        if let ring = f.nextRing, ring > f.now, ring.timeIntervalSince(f.now) <= HeroMomentRules.countdownLead {
            return .countdown
        }
        if f.plannedToday, !isOffPlan(f), let ring = f.ringToday, ring <= f.now, let last = f.lastStartToday, last > f.now {
            return .stilltime
        }
        return nil
    }

    /// Skipped, moved or easy-skipped: the day left the plan on purpose.
    static func isOffPlan(_ f: HeroDayFacts) -> Bool {
        if f.sessionState == .cantToday || f.sessionState == .rescheduled { return true }
        switch f.todayKind {
        case .skipped?, .rescheduled?, .easySkip?, .dayOff?: return true
        default: return false
        }
    }

    // MARK: Ambient (spec §2.2)

    static func ambient(_ f: HeroDayFacts, cal: Calendar, ledger: HeroAmbientLedger) -> (moment: MatrixMoment, lapse: String?) {
        let day = f.habitDay(cal)
        let yesterdayKey = ThemeRotation.key(cal.date(byAdding: .day, value: -1, to: f.displayDay)!, cal)
        let spacingFree = !ledger.onceEver.values.contains(yesterdayKey) && !ledger.onceEver.values.contains(f.dayKey)
        func available(_ m: MatrixMoment) -> Bool { ledger.onceEver[m.rawValue] == nil && spacingFree }

        // 1 automatic: withheld while lapsed.
        if let d = day, d >= HeroMomentRules.automaticFrom, available(.automatic), f.weekCount > 0 || f.lastWeekCount >= f.lastWeekGoal {
            return (.automatic, nil)
        }
        // 2 halfway
        if let d = day, HeroMomentRules.halfwayWindow.contains(d), available(.halfway) { return (.halfway, nil) }
        // 3 comeback
        if let lapse = comebackLapse(f, cal: cal) {
            let shown = ledger.comebackLapse == lapse ? ledger.comebackDays.count : 0
            if shown < HeroMomentRules.comebackMaxDays { return (.comeback, lapse) }
        }
        // 4 missed: yesterday planned, not counted, not moved.
        if f.yesterdayPlanned, !f.yesterdayCounts {
            switch f.yesterdayKind {
            case .rescheduled?, .easySkip?, .dayOff?: break
            default: return (.missed, nil)
            }
        }
        // 5 weekkept
        if f.isThisWeekKept { return (.weekkept, nil) }
        // 6 drift
        if let d = day, HeroMomentRules.driftWindow.contains(d), available(.drift) { return (.drift, nil) }
        // 7 freshstart: the week's first ambient day, nothing counted yet.
        if f.weekCount == 0, isFirstAmbientOfWeek(f, cal: cal, ledger: ledger) { return (.freshstart, nil) }
        return (.rest, nil)
    }

    /// The lapse key (the last counted day before it), when today is a comeback.
    static func comebackLapse(_ f: HeroDayFacts, cal: Calendar) -> String? {
        guard let last = f.countedDays.last(where: { $0 < f.displayDay }), f.weekCount == 0 else { return nil }
        let gap = cal.dateComponents([.day], from: last, to: f.displayDay).day ?? 0
        let broke = f.streakWeeks == 0 && f.hadKeptWeek && f.lastWeekCount < f.lastWeekGoal
        guard gap >= HeroMomentRules.lapseDays || broke else { return nil }
        return ThemeRotation.key(last, cal)
    }

    static func isFirstAmbientOfWeek(_ f: HeroDayFacts, cal: Calendar, ledger: HeroAmbientLedger) -> Bool {
        if f.weekday == 0 { return true }
        guard let start = StreakEngine.weekStart(containing: f.displayDay, weekCalendar: cal) else { return false }
        let startKey = ThemeRotation.key(start, cal)
        return !ledger.byDay.keys.contains { $0 >= startKey && $0 < f.dayKey }
    }

    static func milestoneOnVerified(_ f: HeroDayFacts, cal: Calendar, ledger: HeroAmbientLedger) -> MatrixMoment? {
        guard let d = f.habitDay(cal) else { return nil }
        func open(_ m: MatrixMoment) -> Bool { ledger.onceEver[m.rawValue] == nil || ledger.onceEver[m.rawValue] == f.dayKey }
        if d >= HeroMomentRules.automaticFrom, d <= 79, open(.automatic) { return .automatic }
        if HeroMomentRules.halfwayWindow.contains(d), open(.halfway) { return .halfway }
        return nil
    }

    // MARK: Theme

    static func themeFor(_ f: HeroDayFacts, cal: Calendar, rotation: HeroRotationStore, commit: Bool) -> HeroTheme {
        let training = (f.plannedToday && !isOffPlan(f)) || f.rescheduledToday || f.todayCounts
        if !commit, let t = rotation.peekTheme(for: f.now, calendar: cal) { return t }
        if !commit {
            var l = rotation.ledger
            return ThemeRotation.theme(for: f.now, kind: training ? .training : .other, nextTrainingDay: nextTrainingDay(f, cal: cal), ledger: &l, cal)
        }
        return rotation.theme(for: f.now, kind: training ? .training : .other, nextTrainingDay: nextTrainingDay(f, cal: cal), calendar: cal)
    }

    static func nextTrainingDay(_ f: HeroDayFacts, cal: Calendar) -> Date? {
        guard let ring = f.nextRing else { return nil }
        let d = ThemeRotation.displayDay(ring, cal)
        return d > f.displayDay ? d : cal.date(byAdding: .day, value: 1, to: f.displayDay)
    }

    // MARK: Copy

    static func assemble(_ moment: MatrixMoment, f: HeroDayFacts, theme: HeroTheme, missedToday: Bool, cal: Calendar) -> HeroMomentState {
        let habit = f.habitDay(cal)
        let pos = HeroPositions.weekPos(k: max(1, f.weekCount), goal: f.weekGoal)
        let cardMonthPos: MatrixMonthPos = moment == .verified
            ? HeroPositions.monthPos(earlierCountedThisMonth: f.earlierCountedThisMonth, plannedDaysLeftAfterToday: f.plannedDaysLeftInMonth, recapShownThisMonth: f.recapShownThisMonth)
            : (f.dayOfMonth <= 7 && f.earlierCountedThisMonth == 0 ? .first : f.daysLeftInMonth < 7 ? .last : .middle)

        var facts = HeroCopyFacts()
        facts.weekPos = pos
        facts.monthPos = cardMonthPos
        facts.appsLocked = f.appsLocked
        facts.plannedToday = f.plannedToday && isOffPlan(f)
        facts.missedToday = missedToday
        facts.tomorrowPlanned = f.tomorrowPlanned
        facts.setupDone = f.setupDone.filter { $0 }.count
        facts.alarm = f.nextRing.map(Date.formattedClock)
        facts.ring = f.ringLabel
        facts.wake = f.lockEnd.map(Date.formattedClock)
        facts.gymBy = f.gymBy
        facts.gym = f.gymName
        facts.nextDay = f.nextDayLabel
        facts.frozenEnd = f.frozenEndLabel
        facts.count = f.weekCount
        facts.goal = f.weekGoal
        facts.streak = f.streakWeeks
        facts.habitDay = habit
        facts.sessions = f.totalCounted
        facts.lastWeek = f.lastWeekCount
        facts.lastGoal = f.lastWeekGoal
        facts.week = habit.map { ($0 - 1) / 7 + 1 } ?? 1
        facts.month = f.monthName
        facts.monthSessions = f.monthSessions
        facts.monthTarget = f.monthTarget

        var words = HeroCopy.line(moment, theme: theme.rawValue, weekday: f.weekday, facts: facts)
        words = HeroCopy.monthOverlay(moment, weekday: f.weekday, base: words, facts: facts)
        let kinetic = HeroCopy.kinetic(moment, theme: theme.rawValue)

        var clock = MatrixLiveClock(setupDone: f.setupDone)
        var copy: MatrixCardCopy
        switch moment {
        case .setup:
            let labels = ["Apps locked", "Alarm ready", "Gym selected"]
            copy = MatrixCardCopy(eyebrow: words.eyebrow, headline: .text(words.title, kinetic), support: "", checklist: zip(labels, f.setupDone).map { MatrixCardCopy.ChecklistRow(label: $0.0, isDone: $0.1) })
        case .countdown:
            clock.countdownEnd = f.nextRing
            copy = MatrixCardCopy(eyebrow: words.eyebrow, headline: .countdownClock, support: words.sub)
        case .atgym:
            if f.sessionState == .homeWorkoutAwaitingProof && f.visitArrivedAt == nil {
                copy = MatrixCardCopy(eyebrow: "WORKOUT DONE", headline: .text("Nearly counted.", kinetic), support: "Counts with **Apple Health** or a **progress photo.**")
            } else if !f.visitTimeCounts || f.visitArrivedAt == nil {
                copy = MatrixCardCopy(eyebrow: words.eyebrow, headline: .text("You're here.", kinetic), support: "Counts with **Apple Health** or a **progress photo.**", liveDot: true)
            } else {
                clock.gymStart = f.visitArrivedAt
                clock.gymFrozenAt = f.visitPendingExitAt
                copy = MatrixCardCopy(eyebrow: words.eyebrow, headline: .gymClock, support: "**{left}** " + HeroCopy.live[theme.rawValue] + ".", liveDot: true, showsProofBar: true, supportDone: HeroCopy.liveDone[theme.rawValue])
            }
        case .stilltime:
            clock.eveningEnd = f.lastStartToday
            copy = MatrixCardCopy(eyebrow: words.eyebrow, headline: .stillLeft, support: words.sub, liveDot: true)
        default:
            copy = MatrixCardCopy(eyebrow: words.eyebrow, headline: .text(words.title, kinetic), support: words.sub)
        }

        let label = [copy.eyebrow.capitalized, copy.spokenHeadline, copy.support.replacingOccurrences(of: "**{left}** ", with: "").replacingOccurrences(of: "**", with: "")]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")

        return HeroMomentState(
            moment: moment,
            theme: theme,
            pos: pos,
            monthPos: cardMonthPos,
            dayData: MatrixDayData(day: max(1, habit ?? 1), week: max(1, ((habit ?? 1) - 1) / 7 + 1), sessions: f.totalCounted),
            clock: clock,
            copy: copy,
            dayKey: f.dayKey,
            accessibilityLabel: label
        )
    }

    // MARK: Gather

    static func gather(store: AppStore, coordinator: GymSessionCoordinator, now: Date, cal: Calendar, rotation: HeroRotationStore) -> HeroDayFacts {
        let displayDay = ThemeRotation.displayDay(now, cal)
        let dayKey = ThemeRotation.key(displayDay, cal)
        var f = HeroDayFacts(now: now, displayDay: displayDay, dayKey: dayKey, weekday: ThemeRotation.weekdayIndex(displayDay, cal), hour: cal.component(.hour, from: now))

        let plan = store.plan
        let training = plan.effectiveTrainingDays(fallback: store.schedule)
        let frozenEnd = store.frozenWeekEnd
        func planned(_ day: Date) -> Bool {
            if let frozenEnd, day < frozenEnd, store.streak.isLiveWeekPreArmed, day >= store.streak.liveWeekStart { return false }
            guard let wd = Weekday(rawValue: cal.component(.weekday, from: day)) else { return false }
            return training.contains(wd)
        }
        func rescheduled(_ day: Date) -> Bool {
            coordinator.pendingReschedules.contains { cal.isDate($0.fireDate, inSameDayAs: day) }
        }

        // Session
        if let s = coordinator.session, cal.isDate(s.day, inSameDayAs: displayDay) || cal.isDate(s.day, inSameDayAs: now) {
            f.sessionState = s.state
            f.ringLabel = s.alarmTime.displayString
            f.gymBy = (s.deadline ?? s.arrivalTarget).map(Date.formattedClock)
        }
        if let v = coordinator.visits.openVisit(now: now, calendar: cal), !v.isCounted, !v.isHome {
            f.visitArrivedAt = v.arrivedAt
            f.visitTimeCounts = v.timeCounts
            f.visitPendingExitAt = v.pendingExitAt
        }

        // Today
        let todayOutcome = store.log.outcome(on: displayDay, calendar: cal)
        f.todayCounts = todayOutcome?.counts ?? false
        f.todayKind = todayOutcome?.kind
        f.plannedToday = planned(displayDay)
        f.rescheduledToday = rescheduled(displayDay)
        let next = plan.nextOccurrence(after: now, calendar: cal)
        f.nextRing = next?.fireDate
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: displayDay) {
            f.nextRingIsTomorrow = next.map { cal.isDate($0.fireDate, inSameDayAs: tomorrow) } ?? false
            f.tomorrowPlanned = planned(tomorrow) || rescheduled(tomorrow)
        }
        if let next, cal.isDate(next.fireDate, inSameDayAs: displayDay) {
            f.ringToday = next.fireDate
        } else if f.plannedToday {
            f.ringToday = plan.enabledSlots
                .filter { slot in Weekday(rawValue: cal.component(.weekday, from: displayDay)).map { slot.days.contains($0) } ?? false }
                .compactMap { cal.date(bySettingHour: $0.alarmTime.hour, minute: $0.alarmTime.minute, second: 0, of: displayDay) }
                .min()
        }
        let rhythm = plan.rhythm(at: now, calendar: cal)
        if f.gymBy == nil { f.gymBy = rhythm.gymByTime.displayString }
        if var bed = cal.date(bySettingHour: rhythm.bedtime.hour, minute: rhythm.bedtime.minute, second: 0, of: displayDay) {
            if rhythm.bedtime.hour < 12 { bed = cal.date(byAdding: .day, value: 1, to: bed) ?? bed }
            f.lastStartToday = bed.addingTimeInterval(-Double(HeroMomentRules.eveningBuffer + rhythm.currentTimeToGymMinutes) * 60)
        }

        // Setup, lock, night
        f.setupDone = [
            store.hasConfiguredBlockedApps && coordinator.shield.selectionCount > 0,
            plan.hasBeenReviewed && !plan.enabledSlots.isEmpty,
            store.isAutomaticArrivalReady,
        ]
        f.isPreArmed = store.streak.isLiveWeekPreArmed
        f.windDownActive = coordinator.windDown.isActive
        f.appsLocked = coordinator.shield.isShielded && coordinator.shield.selectionCount > 0
        f.lockEnd = plan.nightLockWindow(at: now, calendar: cal)?.end
            ?? cal.date(bySettingHour: rhythm.wakeTime.hour, minute: rhythm.wakeTime.minute, second: 0, of: cal.date(byAdding: .day, value: f.hour < 12 ? 0 : 1, to: cal.startOfDay(for: now)) ?? now)

        // History
        let counted = Set(store.log.outcomes.filter(\.counts).map { cal.startOfDay(for: $0.countingDay(calendar: cal)) })
        f.countedDays = counted.sorted()
        f.weekGoal = max(1, store.streak.weeklyGoal)
        f.weekCount = store.streak.thisWeekSessionDays
        f.isThisWeekKept = store.streak.isThisWeekKept
        f.streakWeeks = store.streak.weeks
        if let weekStart = StreakEngine.weekStart(containing: displayDay, weekCalendar: cal),
           let lastStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) {
            f.lastWeekCount = counted.filter { $0 >= lastStart && $0 < weekStart }.count
            f.lastWeekGoal = store.weeklyGoal(forWeekContaining: lastStart, calendar: .current)
            // Any earlier week that reached its goal.
            var byWeek: [Date: Int] = [:]
            for d in counted where d < weekStart {
                if let ws = StreakEngine.weekStart(containing: d, weekCalendar: cal) { byWeek[ws, default: 0] += 1 }
            }
            f.hadKeptWeek = byWeek.contains { $0.value >= store.weeklyGoal(forWeekContaining: $0.key, calendar: .current) }
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: displayDay), yesterday >= cal.startOfDay(for: store.joinedAt) {
            f.yesterdayPlanned = planned(yesterday)
            let y = store.log.outcome(on: yesterday, calendar: cal)
            f.yesterdayKind = y?.kind
            f.yesterdayCounts = y?.counts ?? false
        }

        // Month
        if let month = cal.dateInterval(of: .month, for: displayDay) {
            f.monthName = displayDay.formatted(.dateTime.month(.wide))
            f.monthKey = monthKey(displayDay, cal)
            f.dayOfMonth = cal.component(.day, from: displayDay)
            f.daysLeftInMonth = cal.dateComponents([.day], from: displayDay, to: month.end).day.map { $0 - 1 } ?? 0
            f.earlierCountedThisMonth = counted.filter { month.contains($0) && $0 < displayDay }.count
            f.monthSessions = counted.filter { month.contains($0) }.count
            var left = 0
            var d = cal.date(byAdding: .day, value: 1, to: displayDay)!
            while d < month.end {
                if planned(d) { left += 1 }
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            f.plannedDaysLeftInMonth = left
            f.recapShownThisMonth = rotation.ambient.recapMonths.contains(f.monthKey)
            f.monthTarget = rotation.monthTarget(monthKey: f.monthKey)
        }

        // Words
        f.gymName = store.primaryGym?.name
        if let next {
            let nd = ThemeRotation.displayDay(next.fireDate, cal)
            let tomorrow = cal.date(byAdding: .day, value: 1, to: displayDay)!
            f.nextDayLabel = cal.isDate(nd, inSameDayAs: displayDay) ? "today"
                : cal.isDate(nd, inSameDayAs: tomorrow) ? "tomorrow"
                : nd.formatted(.dateTime.weekday(.wide))
        }
        if let frozenEnd { f.frozenEndLabel = frozenEnd.formatted(.dateTime.weekday(.wide)) }
        return f
    }

    static func monthKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
