//
//  CantTodayModel.swift
//  GymLock · the "can't today" screen (three looks)
//
//  The data and the contract every look reads. Nothing here draws. Everything is real app state:
//  the heading and the order of the doors come from SkipRules.screen (FLOW, Flow 4), the days and
//  times from ReschedulePlanner, the costs from the same numbers the pause reads (PauseFacts).
//  A value the app does not have is absent and the look hides that element.
//
//  Approved prototype: docs/prototypes/cant-today-variations.html (the three "b" versions).
//

import SwiftUI

/// One of the three doors, in the order the skip screen shows them.
enum CantTodayDoor: Hashable {
    case reschedule
    case home
    case skip
}

/// A place today's workout can move to: "later today", or a free day left this week.
struct CantTodayTarget: Identifiable, Hashable {
    /// "today", "thu", "sat" ...
    let id: String
    /// Start of the day the alarm would ring on.
    let day: Date
    /// Short label for chips: "today", "thu".
    let short: String
    /// Full label for sentences: "later today", "thursday".
    let name: String
    let isToday: Bool
    /// The time the reel opens on, minutes after midnight (5 minute steps).
    let defaultMinutes: Int
    /// Position in the week, Monday = 0.
    let weekIndex: Int
}

/// Whether a time can be chosen for a target, and if not, the 2 to 3 word note shown.
enum CantTodayAllowance: Equatable {
    case ok
    case blocked(String)

    var isOK: Bool { self == .ok }
}

/// One real cost of skipping. Empty list when skipping costs nothing.
struct CantTodayCost: Identifiable, Hashable {
    enum Kind: Hashable { case week, row, streak }
    let kind: Kind
    /// The big figure: "1/3", "2×", "6".
    let big: String
    /// Plain words: "3 this week out of reach".
    let text: String
    /// Only the streak cost is hot (the one coral signal).
    let hot: Bool

    var id: Kind { kind }
}

struct CantTodayData {
    /// Exact FLOW copy from SkipRules.screen.
    let heading: String
    /// The week can still reach its goal without today.
    let reachable: Bool
    let need: Int
    let weekDone: Int
    let weekGoal: Int
    let streakWeeks: Int
    /// This week, Monday first.
    let week: [PauseWeekDay]
    let todayIndex: Int?
    /// Empty when there is nowhere to move it to: the reschedule door is then absent from `order`.
    let targets: [CantTodayTarget]
    /// Usual gym alarm time, minutes after midnight.
    let usualMinutes: Int
    /// Now, minutes after midnight.
    let nowMinutes: Int
    let cost: [CantTodayCost]
    /// Nil when no home workout is left this month (the home door is then absent from `order`).
    let homeMinutes: Int?
    let homeLeft: Int
    let homeOf: Int
    /// The doors in FLOW order: week at risk puts reschedule first and skip last; week fine puts skip first.
    let order: [CantTodayDoor]
    /// Skipping costs the week: the skip door is last and needs a 1.5 second hold. Otherwise a plain tap.
    let skipNeedsHold: Bool
    /// Comeback mode is on: the next realistic session is already set (shown as one quiet line).
    let comebackMode: Bool
    /// The real rule, asked of the coordinator. Combined with sleep and "too soon" notes.
    let allowance: (CantTodayTarget, Int) -> CantTodayAllowance
    /// Real sunrise and sunset where the person trains. The Ridge sky and sun follow it.
    var daylight: CantTodayDaylight = .fallback

    func allowed(_ target: CantTodayTarget, minutes: Int) -> CantTodayAllowance {
        allowance(target, minutes)
    }
}

// MARK: - Time formatting (12 hour, lowercase, no leading zero: "6:30 am")

enum CantTodayClock {
    static func wrap(_ minutes: Int) -> Int { ((minutes % 1440) + 1440) % 1440 }

    /// 1...12
    static func hour12(_ minutes: Int) -> Int {
        let h = wrap(minutes) / 60
        return h % 12 == 0 ? 12 : h % 12
    }

    static func minute(_ minutes: Int) -> Int { wrap(minutes) % 60 }
    static func isPM(_ minutes: Int) -> Bool { wrap(minutes) / 60 >= 12 }

    /// "6:30 am"
    static func text(_ minutes: Int) -> String {
        let m = minute(minutes)
        let mm = m < 10 ? "0\(m)" : "\(m)"
        return "\(hour12(minutes)):\(mm) \(isPM(minutes) ? "pm" : "am")"
    }

    static func timeOfDay(_ minutes: Int) -> TimeOfDay {
        TimeOfDay(hour: wrap(minutes) / 60, minute: wrap(minutes) % 60)
    }

    static func minutes(_ time: TimeOfDay) -> Int { time.hour * 60 + time.minute }
}

// MARK: - Building the data from the real app

@MainActor
enum CantTodayDataProvider {
    /// The earliest "later today" time offered: at least `ReschedulePlanner.minimumLead` away, on a 5 minute step.
    static func earliestToday(nowMinutes: Int) -> Int {
        let lead = Int(ReschedulePlanner.minimumLead / 60)
        return Int((Double(nowMinutes + lead) / 5.0).rounded(.up)) * 5
    }

    /// The time "later today" opens on: the next quarter hour that is at least 30 minutes away.
    static func defaultToday(nowMinutes: Int) -> Int {
        Int((Double(nowMinutes + 30) / 15.0).rounded(.up)) * 15
    }

    static func make(
        plan: SkipScreenPlan,
        facts: PauseFacts,
        choices: [ReschedulePlanner.Choice],
        defaultTimeFor: (Date) -> TimeOfDay,
        isTimeAvailable: @escaping (Date, TimeOfDay) -> Bool,
        comebackMode: Bool,
        daylight: CantTodayDaylight = .fallback,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CantTodayData {
        let nowParts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (nowParts.hour ?? 0) * 60 + (nowParts.minute ?? 0)
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)

        let targets: [CantTodayTarget] = choices.map { choice in
            let isToday = choice.isLaterToday
            let weekday = calendar.component(.weekday, from: choice.day)
            // Monday = 0 ... Sunday = 6.
            let weekIndex = (weekday + 5) % 7
            let short = isToday ? "today" : choice.label.lowercased()
            let fallback = CantTodayClock.minutes(defaultTimeFor(choice.day))
            return CantTodayTarget(
                id: isToday ? "today" : short,
                day: choice.day,
                short: short,
                name: isToday ? "later today" : weekCalendar.weekdaySymbols[weekday - 1].lowercased(),
                isToday: isToday,
                defaultMinutes: isToday ? defaultToday(nowMinutes: nowMinutes) : fallback,
                weekIndex: weekIndex
            )
        }

        let earliest = earliestToday(nowMinutes: nowMinutes)
        let allowance: (CantTodayTarget, Int) -> CantTodayAllowance = { target, minutes in
            let m = CantTodayClock.wrap(minutes)
            if target.isToday && m < earliest { return .blocked("too soon") }
            if isTimeAvailable(target.day, CantTodayClock.timeOfDay(m)) { return .ok }
            return .blocked("sleep hours")
        }

        var cost: [CantTodayCost] = []
        let reachable = !facts.weekAtRisk
        if !reachable {
            cost.append(CantTodayCost(
                kind: .week,
                big: "\(facts.weekDone)/\(facts.weekGoal)",
                text: "\(facts.weekGoal) this week out of reach",
                hot: false
            ))
        }
        if facts.lastSkipped {
            cost.append(CantTodayCost(kind: .row, big: "2×", text: "second skip in a row", hot: false))
        }
        if !reachable && facts.streakWeeks > 0 {
            cost.append(CantTodayCost(
                kind: .streak,
                big: "\(facts.streakWeeks)",
                text: "\(facts.streakWeeks)-week streak at risk",
                hot: true
            ))
        }

        // The doors exactly as SkipRules.screen ordered them. Home drops out at the monthly cap.
        let order: [CantTodayDoor] = plan.options.compactMap { option in
            switch option {
            case .reschedule: return targets.isEmpty ? nil : .reschedule
            case .homeWorkout: return facts.homeLeft > 0 ? .home : nil
            case .skip: return .skip
            }
        }

        let todayIndex = facts.week.firstIndex { $0.state == .today }

        return CantTodayData(
            heading: plan.heading,
            reachable: reachable,
            need: plan.moreNeeded,
            weekDone: facts.weekDone,
            weekGoal: facts.weekGoal,
            streakWeeks: facts.streakWeeks,
            week: facts.week,
            todayIndex: todayIndex,
            targets: targets,
            usualMinutes: CantTodayClock.minutes(defaultTimeFor(calendar.startOfDay(for: now))),
            nowMinutes: nowMinutes,
            cost: cost,
            homeMinutes: facts.homeLeft > 0 ? facts.homeMinutes : nil,
            homeLeft: facts.homeLeft,
            homeOf: HomeWorkoutRules.monthlyLimit,
            order: order,
            skipNeedsHold: !reachable,
            comebackMode: comebackMode,
            allowance: allowance,
            daylight: daylight
        )
    }
}

// MARK: - What every look receives

/// What the look does when a door is taken. The host wires these to the coordinator.
struct CantTodayActions {
    /// Real alarm on `day` at `time`. Only called with a time `data.allowed` said ok.
    let reschedule: (Date, TimeOfDay) -> Void
    let homeWorkout: () -> Void
    let skip: () -> Void
    /// The close button: back to the countdown (same as the X on the pause, "still going").
    let close: () -> Void
}

/// The space a look draws in (full screen with the safe area carried alongside).
struct CantTodayLayout {
    let size: CGSize
    let safeArea: EdgeInsets

    var contentTop: CGFloat { safeArea.top + 6 + 44 + 8 }
    var contentBottom: CGFloat { size.height - safeArea.bottom - 12 }
    var contentHeight: CGFloat { max(0, contentBottom - contentTop) }
    var contentWidth: CGFloat { max(0, size.width - Theme.pageMargin * 2) }
    /// Short phones (iPhone SE: 667 tall) scale type and gaps down.
    var isCompact: Bool { size.height < 740 }
}

struct CantTodayInput {
    let data: CantTodayData
    let facts: PauseFacts
    let layout: CantTodayLayout
    let reduceMotion: Bool
    /// The same haptics helper the pause uses. Looks never create their own generators.
    let haptics: PauseHaptics
    let actions: CantTodayActions
    /// Opened from the Home banner's "reschedule for today": the look opens straight on the time reel
    /// with "today" picked, with no intro.
    let startsOnReschedule: Bool
}
