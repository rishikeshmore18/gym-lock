import Foundation

/// Builds the done flow from the user's own record (02-experience-spec §4). Every figure on every
/// screen is real: nothing from the prototype's sample session (heart rate, energy, "+6:10") is
/// shown, and a figure GymLock did not measure is simply left out.
@MainActor
enum DoneFlowBuilder {
    struct Resume: Equatable {
        /// back within 10 minutes: this screen, settled
        var index: Int?
        /// back after 10 minutes or more (or after a relaunch), not sealed: open on the climax
        var atClimax = false
        var taps = 0
    }

    struct Built {
        let model: MatrixStoryModel
        /// the once-ever moment (halfway / automatic) the far screen spoke for, if any
        let onceEver: MatrixMoment?
        let dayKey: String
        let monthKey: String
    }

    static func make(
        outcome: SessionOutcome,
        store: AppStore,
        coordinator: GymSessionCoordinator,
        style: HeroCardStyle,
        short: Bool,
        replay: Bool,
        resume: Resume? = nil,
        now: Date = Date(),
        rotation: HeroRotationStore = .shared
    ) -> Built {
        let cal = HeroMomentResolver.displayCalendar()
        let f = HeroMomentResolver.gather(store: store, coordinator: coordinator, now: now, cal: cal, rotation: rotation)
        let st = HeroMomentResolver.state(for: f, cal: cal, rotation: rotation, commit: false)
        let verified = HeroMomentResolver.assemble(.verified, f: f, theme: st.theme, missedToday: false, cal: cal)

        let day = st.theme.rawValue
        let goal = max(1, f.weekGoal)
        let k = max(1, f.weekCount)
        let heroPos = HeroPositions.weekPos(k: k, goal: goal)
        let pos = heroPos.visual
        let monthPos = HeroPositions.monthPos(
            earlierCountedThisMonth: f.earlierCountedThisMonth,
            plannedDaysLeftAfterToday: f.plannedDaysLeftInMonth,
            recapShownThisMonth: f.recapShownThisMonth && !replay
        )
        let weekDone = max(1, min(k, day + 1))

        let record = Record(store: store, coordinator: coordinator, cal: cal)
        let minutesToday = record.minutes(of: outcome)

        // MARK: Headers and captions

        var headers: [MatrixStoryScreen: MatrixStoryCopy.Header] = [:]
        var captions: [MatrixStoryScreen: String] = [:]
        var research: [MatrixStoryScreen: String] = [:]

        headers[.verified] = .init(eyebrow: verified.copy.eyebrow, title: verified.copy.spokenHeadline)
        if !verified.copy.support.isEmpty { captions[.verified] = verified.copy.support }

        // Today
        let visit = record.visit(for: outcome)
        let todayCopy = todaySession(outcome: outcome, visit: visit, minutes: minutesToday, sessions: f.totalCounted)
        headers[.today] = .init(eyebrow: outcome.kind == .homeWorkout ? "TODAY'S WORKOUT" : "TODAY'S SESSION",
                                title: minutesToday.map { "\($0) min." } ?? "Counted.")

        // Week
        let left = max(0, goal - k)
        headers[.week] = .init(eyebrow: "THIS WEEK", title: "\(k) of \(goal).")
        switch heroPos {
        case .first:
            captions[.week] = "Session one is down. **The week has started.**"
            research[.week] = "Gym visits jump **33%** at the start of a week. You rode the wave instead of waiting for it."
        case .middle:
            captions[.week] = k * 2 > goal
                ? "More than half done. **Only \(left) left.**"
                : "Session \(k) is down. **\(left) to go.**"
            research[.week] = "Motivation dips halfway to a goal. The fix is to look ahead: **\(left == 1 ? "1 session" : "\(left) sessions")** and the week stands."
        case .last:
            captions[.week] = "Every session done. **The week is full.**"
            research[.week] = "People remember a stretch of time by its high point and its end. **This is both.**"
        case .bonus:
            captions[.week] = "The week was already kept. **This one is extra.**"
            research[.week] = "Going past the goal is how a habit stops needing one."
        }
        let week = record.week(containing: f.displayDay, today: f.displayDay)
        var weekStats: [MatrixStoryCopy.Stat] = [.count(k, label: k == 1 ? "SESSION" : "SESSIONS")]
        if week.minutes > 0 { weekStats.append(duration(week.minutes, label: "THIS WEEK")) }
        if f.streakWeeks > 0 { weekStats.append(.count(f.streakWeeks, label: "WEEK STREAK", coral: pos == .last)) }

        // Month (first and last weeks only)
        let month = record.month(of: f.displayDay, today: f.displayDay, goal: goal)
        let defaultTarget = defaultMonthTarget(goal: goal, daysRemaining: f.daysLeftInMonth + 1)
        let target = max(1, f.monthTarget ?? defaultTarget)
        let monthPick = monthPos == .first && f.monthTarget == nil && !replay
        let name = f.monthName ?? ""
        let upper = name.uppercased()
        var monthTargets: [MatrixStoryCopy.MonthTarget] = []
        var monthStats: [MatrixStoryCopy.Stat] = []
        switch monthPos {
        case .first where monthPick:
            headers[.month] = .init(eyebrow: "NEW MONTH", title: "\(name).")
            captions[.month] = "A fresh month. **Pick your target** for it."
            research[.month] = "Gym visits rise **14%** at the start of a month. A new chapter makes last month's misses feel like someone else's, so goals set now **stick better.**"
            monthTargets = targetChoices(default: defaultTarget, goal: goal, cap: max(1, f.daysLeftInMonth + 1))
        case .first:
            headers[.month] = .init(eyebrow: "\(upper) SO FAR", title: "\(f.monthSessions) of \(target).")
            captions[.month] = "The first week sets **the pace for the month.**"
            research[.month] = "The start of a month is a fresh start: people train more in it than in any other week. **Bank as much of it as you can.**"
            monthStats = [.count(f.monthSessions, label: "SESSIONS"), .count(target, label: "TARGET")]
        case .last:
            let hit = f.monthSessions >= target
            headers[.month] = .init(eyebrow: hit ? "\(upper), DONE" : "\(upper), SO FAR",
                                    title: f.monthSessions == 1 ? "1 session." : "\(f.monthSessions) sessions.")
            var parts: [String] = []
            if month.minutes > 0 { parts.append("**\(clock(month.minutes))** on the floor.") }
            if let best = month.bestWeek { parts.append("Best week: **week \(best.index), \(best.count) of \(best.goal).**") }
            captions[.month] = parts.isEmpty ? "The month, in sessions." : parts.joined(separator: " ")
            research[.month] = hit
                ? "Target hit. People remember a month by its high point and its end. **This is both.**"
                : "**\(target - f.monthSessions) to go.** The closer the finish line, the faster people move toward it."
            monthStats = [.count(f.monthSessions, label: "SESSIONS", coral: hit), .count(target, label: "TARGET")]
            if month.minutes > 0 { monthStats.append(duration(month.minutes, label: "TIME")) }
        case .middle:
            break
        }
        let storyCal = MatrixStoryCal(lead: month.lead, cells: month.cells, target: monthPick ? defaultTarget : target, sessions: f.monthSessions)

        // Far
        let habit = st.dayData.day
        var onceEver: MatrixMoment?
        if st.moment == .halfway || st.moment == .automatic {
            onceEver = st.moment
            headers[.far] = .init(eyebrow: st.copy.eyebrow, title: st.copy.spokenHeadline)
            captions[.far] = st.copy.support.isEmpty ? "Day **\(habit)** of the habit." : st.copy.support
        } else {
            headers[.far] = .init(eyebrow: "HOW FAR YOU'VE COME", title: "Week \(st.dayData.week).")
            captions[.far] = "Day **\(habit)** of the habit. **\(f.totalCounted == 1 ? "1 session" : "\(f.totalCounted) sessions")** in."
        }
        let far = record.recentWeeks(endingWith: f.displayDay, count: 8)
        if record.totalMinutes > 0 { research[.far] = "**\(clock(record.totalMinutes))** of training since day one." }
        var farStats: [MatrixStoryCopy.Stat] = [.count(f.totalCounted, label: "SESSIONS")]
        if f.streakWeeks > 0 { farStats.append(.count(f.streakWeeks, label: "WEEK STREAK")) }
        farStats.append(.count(habit, label: "DAYS IN"))

        // End
        let nextTime = f.nextRing.map(Date.formattedClock)
        let end = MatrixClimaxCopy.end(pos: pos, facts: .init(
            weekDone: k, weekGoal: goal, weekStreak: f.streakWeeks,
            nextDay: f.nextDayLabel.map(capitalizedDay), nextTime: nextTime
        ))

        var copy = MatrixStoryCopy(
            headers: headers,
            captions: captions,
            research: research,
            today: todayCopy,
            appsUnlocked: appsUnlocked(outcome: outcome, store: store, coordinator: coordinator, facts: f),
            monthStats: monthStats,
            monthTargets: monthTargets,
            monthName: name.isEmpty ? nil : name,
            endSub: end.sub,
            endButton: end.button
        )
        copy.weekDays = week.days
        copy.weekStats = weekStats
        copy.farWeeks = far.contains { $0 > 0 } && far.count >= 2 ? far : []
        copy.farStats = farStats
        copy.sessions = f.totalCounted

        let model = MatrixStoryModel(
            day: day,
            pos: pos,
            monthPos: monthPos,
            dayData: st.dayData,
            weekDone: weekDone,
            weekToday: weekDone - 1,
            monthPick: monthPick,
            cal: monthPos == .middle ? nil : storyCal,
            copy: copy,
            dynamic: true,
            style: style,
            short: short,
            resumeAtClimax: resume?.atClimax ?? false,
            resumeIndex: resume?.index,
            restoredTaps: resume?.taps ?? 0,
            now: now
        )
        return Built(model: model, onceEver: onceEver, dayKey: f.dayKey, monthKey: f.monthKey)
    }

    // MARK: Pieces

    /// "tomorrow" stays lower-case in "See you tomorrow"; weekday names are already capitalised.
    private static func capitalizedDay(_ s: String) -> String { s }

    private static func todaySession(outcome: SessionOutcome, visit: GymVisit?, minutes: Int?, sessions: Int) -> MatrixStoryCopy.Today {
        let start: Date
        var end: Date?
        if let visit, !visit.isHome {
            start = visit.manualAt ?? visit.arrivedAt
            end = visit.leftAt ?? visit.countedAt
        } else if let m = outcome.minutes, m > 0 {
            end = outcome.date
            start = outcome.date.addingTimeInterval(-Double(m) * 60)
        } else {
            start = outcome.date
        }
        if let e = end, e.timeIntervalSince(start) < 60 { end = nil }

        let caption: String? = {
            switch visit?.proof ?? outcome.proof {
            case .health: return "Confirmed by **Apple Health.**"
            case .timeAtGym: return "**20 minutes** at the gym. **Counted.**"
            case .photo: return "Counted with a **progress photo.**"
            default: return nil
            }
        }()

        var stats: [MatrixStoryCopy.Stat] = []
        if let minutes, minutes > 0 { stats.append(.count(minutes, unit: "min", label: "TODAY")) }
        stats.append(.init(value: Date.formattedClock(start), label: outcome.kind == .homeWorkout ? "STARTED" : "IN AT"))
        stats.append(.count(sessions, label: sessions == 1 ? "SESSION" : "SESSIONS", coral: true))
        return .init(
            start: Date.formattedClock(start),
            end: end.map(Date.formattedClock),
            caption: caption,
            stats: stats,
            minutes: minutes
        )
    }

    private static func appsUnlocked(outcome: SessionOutcome, store: AppStore, coordinator: GymSessionCoordinator, facts f: HeroDayFacts) -> Int? {
        guard outcome.kind == .showedUp, store.hasConfiguredBlockedApps, !f.appsLocked else { return nil }
        let n = coordinator.shield.selectionCount
        return n > 0 ? n : nil
    }

    /// The month's pace if the weekly goal holds for every remaining day (spec: "Your pace").
    static func defaultMonthTarget(goal: Int, daysRemaining: Int) -> Int {
        max(1, Int((Double(goal * max(1, daysRemaining)) / 7).rounded()))
    }

    static func targetChoices(default d: Int, goal: Int, cap: Int) -> [MatrixStoryCopy.MonthTarget] {
        let raw: [(Int, String)] = [(d - goal, "Steady"), (d, "Your pace"), (d + goal, "Push")]
        var seen = Set<Int>()
        var out: [MatrixStoryCopy.MonthTarget] = []
        for (n, label) in raw {
            let v = min(max(1, n), max(1, cap))
            if seen.insert(v).inserted { out.append(.init(n: v, label: label)) }
        }
        return out
    }

    private static func duration(_ minutes: Int, label: String) -> MatrixStoryCopy.Stat {
        minutes < 60 ? .count(minutes, unit: "min", label: label) : .init(value: clock(minutes), label: label)
    }

    private static func clock(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    // MARK: The record

    /// Counted sessions and their minutes, read once per build.
    private struct Record {
        let cal: Calendar
        let counted: [SessionOutcome]
        let visitsByOutcome: [UUID: GymVisit]
        let plannedWeekdays: Set<Weekday>
        let countedDays: [Date: Int]

        init(store: AppStore, coordinator: GymSessionCoordinator, cal: Calendar) {
            self.cal = cal
            counted = store.log.outcomes.filter(\.counts)
            visitsByOutcome = Dictionary(coordinator.visits.visits.map { ($0.outcomeID, $0) }, uniquingKeysWith: { a, b in a.countedAt != nil ? a : b })
            plannedWeekdays = store.plan.effectiveTrainingDays(fallback: store.schedule)
            countedDays = Self.minutesByDay(counted, visits: visitsByOutcome, cal: cal)
        }

        func visit(for o: SessionOutcome) -> GymVisit? { visitsByOutcome[o.id] }

        func minutes(of o: SessionOutcome) -> Int? {
            Self.minutes(of: o, visit: visitsByOutcome[o.id])
        }

        static func minutes(of o: SessionOutcome, visit: GymVisit?) -> Int? {
            if let v = visit, !v.isHome, let end = v.leftAt ?? v.countedAt {
                let m = Int(end.timeIntervalSince(v.manualAt ?? v.arrivedAt) / 60)
                if m > 0 { return min(m, 300) }
            }
            if let m = o.minutes, m > 0 { return min(m, 300) }
            return nil
        }

        static func minutesByDay(_ outcomes: [SessionOutcome], visits: [UUID: GymVisit], cal: Calendar) -> [Date: Int] {
            var out: [Date: Int] = [:]
            for o in outcomes {
                let d = cal.startOfDay(for: o.countingDay(calendar: cal))
                out[d] = max(out[d] ?? 0, minutes(of: o, visit: visits[o.id]) ?? 0)
            }
            return out
        }

        var totalMinutes: Int { countedDays.values.reduce(0, +) }

        func isPlanned(_ day: Date) -> Bool {
            Weekday(rawValue: cal.component(.weekday, from: day)).map(plannedWeekdays.contains) ?? false
        }

        func weekStart(_ day: Date) -> Date {
            StreakEngine.weekStart(containing: day, weekCalendar: cal) ?? cal.startOfDay(for: day)
        }

        func week(containing day: Date, today: Date) -> (days: [MatrixStoryCopy.WeekDay], minutes: Int) {
            let start = weekStart(day)
            let labels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
            var total = 0
            let days: [MatrixStoryCopy.WeekDay] = (0..<7).map { i in
                let d = cal.date(byAdding: .day, value: i, to: start)!
                let m = countedDays[d]
                total += m ?? 0
                return .init(label: labels[i], minutes: (m ?? 0) > 0 ? m : nil, done: m != nil, isToday: cal.isDate(d, inSameDayAs: today))
            }
            return (days, total)
        }

        func recentWeeks(endingWith day: Date, count: Int) -> [Int] {
            let thisWeek = weekStart(day)
            let first = countedDays.keys.min().map(weekStart)
            var out: [Int] = []
            for back in stride(from: count - 1, through: 0, by: -1) {
                guard let ws = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { continue }
                if let first, ws < first { continue }
                let we = cal.date(byAdding: .day, value: 7, to: ws)!
                out.append(countedDays.filter { $0.key >= ws && $0.key < we }.values.reduce(0, +))
            }
            return out
        }

        struct Month {
            var lead: Int
            var cells: [String]
            var minutes: Int
            var bestWeek: (index: Int, count: Int, goal: Int)?
        }

        func month(of day: Date, today: Date, goal: Int) -> Month {
            guard let interval = cal.dateInterval(of: .month, for: day) else { return Month(lead: 0, cells: [], minutes: 0) }
            let first = interval.start
            // Monday-first: Monday 0 … Sunday 6
            let lead = (cal.component(.weekday, from: first) + 5) % 7
            var cells: [String] = []
            var minutes = 0
            var byWeek: [Int: Int] = [:]
            var d = first
            var i = 0
            while d < interval.end {
                let done = countedDays[d] != nil
                if done { minutes += countedDays[d] ?? 0; byWeek[(i + lead) / 7, default: 0] += 1 }
                if cal.isDate(d, inSameDayAs: today) {
                    cells.append("today")
                } else if d > today {
                    cells.append("future")
                } else if done {
                    cells.append("done")
                } else {
                    cells.append(isPlanned(d) ? "miss" : "rest")
                }
                d = cal.date(byAdding: .day, value: 1, to: d)!
                i += 1
            }
            let best = byWeek.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }
            return Month(lead: lead, cells: cells, minutes: minutes, bestWeek: best.map { ($0.key + 1, $0.value, goal) })
        }
    }
}
