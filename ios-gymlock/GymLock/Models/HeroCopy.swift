import Foundation

/// The words on the Dynamic hero card, from the prototype's copy tables (copy12.ts STATE12 and
/// DONE12) rewritten so every line holds on any theme and with real values only.
///
/// - Eyebrow and title are keyed by **theme** (they name the visual).
/// - The sub line is keyed by the **real weekday** (Monday 0 ... Sunday 6), so weekday facts stay true.
/// - `{token}` is filled from `HeroCopyFacts`. A line whose token has no real value is rejected
///   and the moment's fallback is used instead, so nothing is ever invented (UI-RULES §11).
///   `{?token}` only requires the fact and prints nothing.
/// - Sentence case, straight apostrophes, no em dashes. Prototype facts the app has no data for
///   ("6 min out", "open until 22:00", the comeback bonus, minutes per session) are gone.
enum HeroCopy {
    struct Row {
        let eyebrow: [String]
        let title: [String]
        let sub: [String]
        let fallback: [String]
    }

    // MARK: Lookup

    /// The card copy for a moment that is not one of the live clocks.
    static func line(_ moment: MatrixMoment, theme: Int, weekday: Int, facts f: HeroCopyFacts) -> (eyebrow: String, title: String, sub: String) {
        let row = table(moment, facts: f)
        let t = clamp(theme), w = clamp(weekday)
        let eyebrow = fill(row.eyebrow[t], f) ?? fill(row.eyebrow[0], f) ?? moment.rawValue.uppercased()
        let title = fill(row.title[t], f) ?? row.title.lazy.compactMap { fill($0, f) }.first ?? ""
        let sub = fill(row.sub[w], f) ?? row.fallback.lazy.compactMap { fill($0, f) }.first ?? ""
        return (eyebrow.uppercased(), title, sub)
    }

    /// RW.typeFor: the kinetic style of the headline for a moment and theme.
    static func kinetic(_ moment: MatrixMoment, theme: Int) -> MatrixKineticStyle {
        MatrixKineticStyle(rawValue: RW.typeFor(moment.rawValue, Double(clamp(theme)))) ?? .rise
    }

    static func clamp(_ i: Int) -> Int { min(6, max(0, i)) }

    /// Replaces `{token}` and `{?token}`; nil when a token has no real value.
    static func fill(_ template: String, _ f: HeroCopyFacts) -> String? {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { return nil }
            var name = String(rest[rest.index(after: open)..<close])
            let silent = name.hasPrefix("?")
            if silent { name.removeFirst() }
            guard let value = f.value(name) else { return nil }
            if !silent { out += value }
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out
    }

    // MARK: Tables

    private static func table(_ m: MatrixMoment, facts f: HeroCopyFacts) -> Row {
        switch m {
        case .setup: return setup
        case .firstnight: return firstnight
        case .bedtime: return f.appsLocked ? bedtimeLocked : bedtimeOpen
        case .wake: return wake
        case .countdown: return countdown
        case .ready: return ready
        case .commute: return commute
        case .atgym: return atgym
        case .verified: return verifiedRow(f.weekPos)
        case .stilltime: return stilltime
        case .rest: return f.plannedToday ? restOffPlan : rest
        case .paused: return paused
        case .freshstart: return freshstart
        case .missed: return f.missedToday ? missedToday : missed
        case .weekkept: return weekkept
        case .comeback: return comeback
        case .drift: return drift
        case .halfway: return halfway
        case .automatic: return automatic
        }
    }

    static let setup = Row(
        eyebrow: ["FRESH START", "FINISH YOUR SYSTEM", "ALMOST SET", "PLANT IT", "BASE CAMP", "NO RUSH", "SET UP THE WEEK"],
        title: Array(repeating: "{setupDone} of 3 ready", count: 7),
        sub: Array(repeating: "", count: 7),
        fallback: [""]
    )

    static let firstnight = Row(
        eyebrow: ["DAY ONE TOMORROW", "DAY ONE TOMORROW", "THE NIGHT BEFORE", "DAY ONE TOMORROW", "DAY ONE TOMORROW", "DAY ONE TOMORROW", "DAY ONE TOMORROW"],
        title: ["Charge up.", "Lights low.", "Bag packed?", "Rest easy.", "Sleep first.", "Early night.", "Day one."],
        sub: [
            "Tomorrow, **{alarm}** at **{gym}.** Sleep is step one.",
            "Tomorrow, **{alarm}.** A plan with a time and place **gets kept.**",
            "Shoes by the door. **Tomorrow, {alarm}.**",
            "Tomorrow starts it. All you do is **show up.**",
            "A Saturday start: **quiet floor, free racks.**",
            "Sunday is the **quietest gym day** of the week. Yours to own.",
            "More people start on a Monday **than any other day.** Join them.",
        ],
        fallback: ["Tomorrow, **{alarm}.** Sleep is step one.", "Sleep is **step one.**"]
    )

    /// The night lock is holding the user's apps: "locked" wording is true.
    static let bedtimeLocked = Row(
        eyebrow: ["LOCKED FOR SLEEP", "LOCKED FOR SLEEP", "SLEEP MODE", "LOCKED FOR SLEEP", "LOCKED FOR SLEEP", "LOCKED FOR SLEEP", "LOCKED FOR SLEEP"],
        title: ["Recharging.", "Lights out.", "Power down.", "Off duty.", "Rest up.", "Wind down.", "Refuel."],
        sub: [
            "Apps **locked** until {wake}. Muscle **rebuilds** while you sleep.",
            "{?tomorrowPlanned}Tomorrow is planned. **Nothing to decide** in the morning.",
            "Halfway through the week. **Sleep carries you through the rest.**",
            "{?tomorrowPlanned}Tomorrow is the day most people skip. **Sleep well and you won't.**",
            "Tomorrow is Saturday. **Apps back at {wake}.**",
            "Your phone sleeps too. **Nothing to scroll till morning.**",
            "New week tomorrow. Good sleep is **part of the workout.**",
        ],
        fallback: ["Apps back at **{wake}.** Sleep well.", "Muscle **rebuilds** while you sleep."]
    )

    /// The night window is on but no apps are held: never say "locked".
    static let bedtimeOpen = Row(
        eyebrow: ["BEDTIME", "BEDTIME", "SLEEP MODE", "BEDTIME", "BEDTIME", "BEDTIME", "BEDTIME"],
        title: bedtimeLocked.title,
        sub: [
            "Alarm at **{alarm}.** Muscle **rebuilds** while you sleep.",
            "{?tomorrowPlanned}Tomorrow is planned. **Nothing to decide** in the morning.",
            "Halfway through the week. **Sleep carries you through the rest.**",
            "{?tomorrowPlanned}Tomorrow is the day most people skip. **Sleep well and you won't.**",
            "Tomorrow is Saturday. **Sleep in, or don't.**",
            "Phone down. **Morning comes faster asleep.**",
            "New week tomorrow. Good sleep is **part of the workout.**",
        ],
        fallback: ["Muscle **rebuilds** while you sleep."]
    )

    static let wake = Row(
        eyebrow: ["ALARM · {ring}", "ALARM · {ring}", "GOOD MORNING", "ALARM · {ring}", "ALARM · {ring}", "{ring}", "ALARM · {ring}"],
        title: ["Rise.", "Feet down.", "Up.", "New day.", "Last push.", "Morning.", "Quiet start."],
        sub: [
            "Monday is **the busiest gym day** of the week. Be part of it.",
            "{?appsLocked}Apps stay locked until you're **at the gym.**",
            "Midweek. **First win of the day:** out of bed.",
            "Thirty minutes from now you'll be **glad you went.**",
            "Friday is **the most skipped weekday.** Not by you.",
            "No commute, no meetings. **Just the gym.**",
            "The gym is at its **emptiest** on a Sunday. All yours.",
        ],
        fallback: ["First win of the day: **out of bed.**"]
    )

    static let countdown = Row(
        eyebrow: ["ALARM IN", "ALARM IN", "UNTIL {alarm}", "ALARM IN", "COUNTING DOWN", "ALARM IN", "ALARM IN"],
        title: Array(repeating: "", count: 7),
        sub: [
            "Bag ready? **This one counts.**",
            "Same time, same place. **That's how it sticks.**",
            "People who plan **when and where** follow through 91% of the time.",
            "Planned, so it **happens.** No decision to make.",
            "**{gym}** by {gymBy}. **Finish the week strong.**",
            "A Saturday session is **pure choice.** Make it.",
            "Train today and Monday starts **with momentum.**",
        ],
        fallback: ["Planned, so it **happens.** No decision to make."]
    )

    static let ready = Row(
        eyebrow: ["ALARM BEATEN", "ALARM BEATEN", "UP AND MOVING", "ALARM BEATEN", "GET READY", "GET READY", "UP EARLY"],
        title: ["Get ready.", "Shoes on.", "Out the door.", "You're up.", "Grab the bag.", "Easy pace.", "Out you go."],
        sub: [
            "Shoes on. **Gym by {gymBy}.**",
            "The hardest rep is **the front door.**",
            "Next stop: **{gym}.**",
            "That was the hard part. **Now just go.**",
            "Gym by **{gymBy}.** Then the weekend.",
            "No traffic on a Saturday. **Gym by {gymBy}.**",
            "An empty gym is the best gym. **Gym by {gymBy}.**",
        ],
        fallback: ["The hardest rep is **the front door.**"]
    )

    static let commute = Row(
        eyebrow: ["ON YOUR WAY", "ON YOUR WAY", "EN ROUTE", "ON YOUR WAY", "HEADING IN", "ON YOUR WAY", "EN ROUTE"],
        title: ["On the way.", "Almost there.", "Moving.", "Moving.", "Nearly there.", "Rolling in.", "Out the door."],
        sub: [
            "The hard part **is behind you.**",
            "You're out the door. **That was the win.**",
            "{?appsLocked}Apps unlock **when you walk in.**",
            "Showing up is **most of it.**",
            "**{gym}** by **{gymBy}.**",
            "Weekend roads. **Due by {gymBy}.**",
            "Most people are still asleep. **You're on your way.**",
        ],
        fallback: ["Showing up is **most of it.**"]
    )

    static let atgym = Row(
        eyebrow: ["AT THE GYM", "ON THE FLOOR", "CHECKED IN", "AT {gym}", "IN SESSION", "ON THE FLOOR", "CHECKED IN"],
        title: Array(repeating: "", count: 7),
        sub: Array(repeating: "", count: 7),
        fallback: [""]
    )

    /// mx/atgym.ts MX_LIVE: what the 20 minutes build, by theme.
    static let live = ["until the sun is up", "until today's block is laid", "until today's battery is full", "until the bar goes up", "until your +1", "until the ring closes", "until the week turns over"]
    static let liveDone = ["20:00. Sun up. Verified.", "20:00. Block laid. Verified.", "20:00. Charged. Verified.", "20:00. Lifted. Verified.", "20:00. Plus one. Verified.", "20:00. Ring closed. Verified.", "20:00. Week turned. Verified."]

    static func verifiedRow(_ pos: HeroWeekPos) -> Row {
        switch pos {
        case .first: return doneFirst
        case .middle: return doneMiddle
        case .last: return doneLast
        case .bonus: return doneBonus
        }
    }

    static let doneFirst = Row(
        eyebrow: Array(repeating: "FIRST OF THE WEEK", count: 7),
        title: ["Week started.", "One down.", "Off the mark.", "Started.", "Got one in.", "On the board.", "One down."],
        sub: [
            "Monday is the **busiest gym day** of the week. You were in it.",
            "{left} more and **the week is kept.**",
            "A midweek start is still **a start.** {left} to go.",
            "Late in the week and **still in it.** That's the habit.",
            "Friday is the most skipped weekday. **You started on it.**",
            "A weekend session **counts the same.**",
            "Sunday is the **quietest gym day.** You came anyway.",
        ],
        fallback: ["The first of the week is **the hardest to start.**"]
    )

    static let doneMiddle = Row(
        eyebrow: Array(repeating: "WORKOUT VERIFIED", count: 7),
        title: ["Done.", "Stacking up.", "Keep going.", "Still going.", "On pace.", "Building.", "Done."],
        sub: [
            "**{count} of {goal}.** Look how much is already behind you.",
            "**{count} sessions** this week. {left} more and it's kept.",
            "Only **{left} left.** The end is closer than the start.",
            "Thursday to Friday is where most people **drop off.** Not you.",
            "Friday done. **{left} from a kept week.**",
            "**{count} this week,** one on a Saturday. That's commitment.",
            "The quietest day, **the strongest habit.** {count} of {goal}.",
        ],
        fallback: ["**{count} of {goal}** this week."]
    )

    static let doneLast = Row(
        eyebrow: Array(repeating: "WEEK COMPLETE", count: 7),
        title: ["Week kept.", "That's the week.", "Full week.", "Week done.", "Finished strong.", "All of them.", "Week, complete."],
        sub: [
            "Kept on a Monday. **The rest of the week is a bonus.**",
            "{goal} needed, **{count} done.** Week streak: **{streak}.**",
            "Most people never finish one. **You just did.**",
            "Done **before the weekend.** It's all yours now.",
            "Friday is the most skipped weekday. **You closed the week on it.**",
            "The last one is what you'll remember. **You made it count.**",
            "Closed on a Sunday. **Monday starts with a full tank.**",
        ],
        fallback: ["Every session you needed this week. **All of them.**"]
    )

    /// FLOW's bonus line: "4 this week. that's a bonus day.", in sentence case.
    static let doneBonus = Row(
        eyebrow: Array(repeating: "BONUS DAY", count: 7),
        title: doneMiddle.title,
        sub: Array(repeating: "**{count} this week.** That's a bonus day.", count: 7),
        fallback: ["That's a **bonus day.**"]
    )

    static let stilltime = Row(
        eyebrow: ["STILL TIME TODAY", "STILL TIME TODAY", "BEFORE THE DAY ENDS", "STILL TIME TODAY", "STILL TIME TODAY", "TODAY'S STILL OPEN", "STILL TIME TODAY"],
        title: Array(repeating: "", count: 7),
        sub: [
            "**20 minutes** tonight and today counts.",
            "Today is a planned day. **Twenty minutes counts.**",
            "A short session **beats a skipped one.**",
            "Twenty minutes **keeps the week in reach.**",
            "Go tonight and **the weekend starts earned.**",
            "Saturday evenings are quiet. **Twenty minutes is enough.**",
            "Go now and **Monday starts on a win.**",
        ],
        fallback: ["Twenty minutes **counts.**"]
    )

    static let rest = Row(
        eyebrow: ["REST DAY", "REST DAY", "DAY OFF", "REST DAY", "RECOVERY", "REST DAY", "REST DAY"],
        title: ["Recover.", "Rest is training.", "Still water.", "Breathe.", "Off day.", "Easy day.", "Recharge."],
        sub: [
            "Muscle is built **between** sessions.",
            "Rest days are **part of the plan.**",
            "Walk, stretch, sleep. **Back {nextDay}.**",
            "Nothing to do today **but recover.**",
            "Rest is in the plan. **Next: {nextDay}, {alarm}.**",
            "Nothing to unlock today. **Enjoy it.**",
            "Rest now, **new week tomorrow.** Sleep early.",
        ],
        fallback: ["Muscle is built **between** sessions."]
    )

    /// A planned day that was skipped or moved: never call it planned rest.
    static let restOffPlan = Row(
        eyebrow: Array(repeating: "OFF TODAY", count: 7),
        title: rest.title,
        sub: Array(repeating: "Off the plan today. **Next: {nextDay}, {alarm}.**", count: 7),
        fallback: ["Off the plan today. **Next: {nextDay}.**", "Off the plan today."]
    )

    static let paused = Row(
        eyebrow: ["STREAK FROZEN", "STREAK FROZEN", "PAUSED", "STREAK FROZEN", "STREAK FROZEN", "AWAY", "STREAK FROZEN"],
        title: ["Off the clock.", "On hold.", "Take the break.", "Rest up.", "Hold position.", "Enjoy it.", "Paused."],
        sub: [
            "Sick or travelling? A frozen week **doesn't break the streak.**",
            "Your streak waits **right here.**",
            "Come back when you're ready. **Nothing is lost.**",
            "Get well first. **The plan waits.**",
            "Alarms are off this week. **Back {frozenEnd}.**",
            "A frozen week **doesn't break the chain.**",
            "The count stays at **{streak}.** Come back to it.",
        ],
        fallback: ["Your streak waits **right here.**"]
    )

    static let freshstart = Row(
        eyebrow: Array(repeating: "NEW WEEK", count: 7),
        title: ["New week.", "Clean slate.", "Zero of {goal}.", "Go again.", "Week {week}.", "Begin.", "Day one."],
        sub: [
            "Last week: **{lastWeek} sessions.** Gym visits jump **33%** at the start of a week.",
            "Last week is banked. **This one starts at zero.**",
            "One session and the week **is moving.**",
            "Last week, **{lastWeek} of {lastGoal}.** This week, start strong.",
            "A new week is **a fresh start.** People train more in them. Ride it.",
            "Nothing on the board yet. **One session puts one there.**",
            "Seven days, **{goal} sessions.** The first can be today.",
        ],
        fallback: ["One session and the week **is moving.**"]
    )

    static let missed = Row(
        eyebrow: ["MISSED YESTERDAY", "MISSED YESTERDAY", "YESTERDAY SLIPPED", "MISSED YESTERDAY", "ONE MISS", "MISSED YESTERDAY", "MISSED YESTERDAY"],
        title: ["Never twice.", "Back today.", "Today counts.", "Reset.", "Not two.", "Make it up.", "Still time."],
        sub: [
            "One miss doesn't undo a habit. **Today keeps it.**",
            "Missing once has **no real effect** on habit forming.",
            "One day is a blip. **Two is a pattern.**",
            "Twenty minutes today and **the week is back.**",
            "Go today and **yesterday won't matter.**",
            "The weekend is **the perfect catch-up.** Go today.",
            "The week isn't over **until tonight.**",
        ],
        fallback: ["One day is a blip. **Two is a pattern.**"]
    )

    /// Today's planned session was missed and the day can't be saved any more.
    static let missedToday = Row(
        eyebrow: Array(repeating: "TODAY SLIPPED", count: 7),
        title: ["Never twice.", "Not two.", "Reset.", "Never twice.", "Not two.", "Reset.", "Never twice."],
        sub: Array(repeating: "One miss is a blip. **{NextDay} keeps the habit.**", count: 7),
        fallback: ["One day is a blip. **Two is a pattern.**"]
    )

    static let weekkept = Row(
        eyebrow: Array(repeating: "WEEK KEPT", count: 7),
        title: ["{count} of {goal}.", "Full week.", "Kept.", "All done.", "Closed out.", "Banked.", "Every one."],
        sub: [
            "Every session you needed, **stacked.**",
            "{goal} needed, **{count} done.**",
            "Week streak: **{streak}.** Keep the run going.",
            "You kept **the promise** this week.",
            "Week kept. **Rest well this weekend.**",
            "{count} sessions, **zero excuses.** Enjoy the weekend.",
            "A full week, **start to finish.** Tomorrow, go again.",
        ],
        fallback: ["Every session you needed, **stacked.**"]
    )

    static let comeback = Row(
        eyebrow: ["WELCOME BACK", "WELCOME BACK", "BACK", "WELCOME BACK", "WELCOME BACK", "WELCOME BACK", "WELCOME BACK"],
        title: ["Start again.", "Good to see you.", "Day one, again.", "Pick it up.", "Fresh start.", "Back on it.", "Here again."],
        sub: [
            "A Monday comeback rides **the fresh-start wave.**",
            "Just 20 minutes **restarts the run.**",
            "Everyone restarts. **The ones who win do it fast.**",
            "A return after a break is **the habit working.**",
            "Twenty minutes **and you're back on the board.**",
            "No better day to restart than **a Saturday.**",
            "Start today and **next week starts strong.**",
        ],
        fallback: ["Just 20 minutes **restarts the run.**"]
    )

    static let drift = Row(
        eyebrow: ["WEEK {week}", "WEEK {week}", "THE MIDDLE", "WEEK {week}", "WEEK {week}", "WEEK {week}", "WEEK {week}"],
        title: ["Drift zone.", "Stay sharp.", "Keep going.", "Hold the line.", "Stay the course.", "Don't drift.", "Stay on it."],
        sub: [
            "Most slip to **once a week** by week 6. **Not you.**",
            "This is where **most people fade.**",
            "The middle is **the hardest part.** It passes.",
            "New members plan 3 a week. **By week 6, 1.** Not you.",
            "The fog lifts **if you keep walking.**",
            "The novelty is gone. **Routine is what's left.** Lean on it.",
            "Motivation fades by design. **The plan doesn't.**",
        ],
        fallback: ["This is where **most people fade.**"]
    )

    static let halfway = Row(
        eyebrow: ["HABIT FORMING", "HALFWAY", "DAY {day} OF 66", "HABIT FORMING", "DAY {day}", "HALFWAY", "DAY {day} OF 66"],
        title: ["Day {day}.", "Halfway.", "Half there.", "Day {day}.", "Midpoint.", "Day {day}.", "Halfway."],
        sub: [
            "Halfway up. **{sessions} sessions** in.",
            "Habits take **66 days** on average. You're at {day}.",
            "From here, **the end is closer** than the start.",
            "It's getting **easier** than it was.",
            "{day} days behind you. **{toGo} to automatic.**",
            "Halfway to automatic. **The hard half is done.**",
            "Half the shape is there. **{toGo} days to the rest.**",
        ],
        fallback: ["From here, **the end is closer** than the start."]
    )

    static let automatic = Row(
        eyebrow: ["DAY {day}", "DAY {day}", "DAY {day}", "HABIT BUILT", "DAY {day}", "DAY {day}", "DAY {day}"],
        title: ["Automatic.", "Habit made.", "Who you are.", "{day} days.", "Locked in.", "Second nature.", "Automatic."],
        sub: [
            "66 days is the median. **It's yours now.**",
            "It runs **on its own** now.",
            "You're someone who **trains.**",
            "The median time to automatic. **Done.**",
            "No more deciding. **You just go.**",
            "What took effort **now takes none.**",
            "Every piece in place. **This is who you are now.**",
        ],
        fallback: ["It runs **on its own** now."]
    )

    // MARK: Month overlays (copy12.ts cardCopy)

    static let firstFresh = [
        "New week **and** new month. A double fresh start.",
        "**{month}** starts clean. So does the week.",
        "A new month lifts gym visits **14%** on its own. Use it.",
        "First week of {month}. **Set the tone.**",
        "{month} is a blank page. **Write the first line today.**",
        "Nothing on the {month} calendar yet. **Start it today.**",
        "Start {month} the way you want to **finish it.**",
    ]

    /// Layers the month's first and last weeks over a card line.
    static func monthOverlay(_ moment: MatrixMoment, weekday: Int, base: (eyebrow: String, title: String, sub: String), facts f: HeroCopyFacts) -> (eyebrow: String, title: String, sub: String) {
        guard let month = f.month else { return base }
        let up = month.uppercased(), short = String(up.prefix(3))
        let n = f.monthSessions
        if f.monthPos == .first, moment == .freshstart {
            return ("NEW WEEK · NEW MONTH", base.title, fill(firstFresh[clamp(weekday)], f) ?? base.sub)
        }
        // Every other overlay quotes the month target: only one the user picked.
        guard let target = f.monthTarget else { return base }
        switch (f.monthPos, moment) {
        case (.first, .verified):
            if f.weekPos == .first, n == 1 {
                return ("FIRST OF \(up)", base.title, "\(month)'s first session. **\(n) of \(target)** for the month.")
            }
            return ("\(short) · \(n) OF \(target)", base.title, base.sub)
        case (.last, .freshstart):
            return ("LAST WEEK OF \(up)", base.title, "**\(max(0, target - n)) sessions** to your \(month) target. Finish the month strong.")
        case (.last, .weekkept):
            return ("\(short) · \(n) OF \(target)", base.title, "A full week to close out \(month). **Best way to end one.**")
        case (.last, .verified):
            return n >= target
                ? ("\(up) · TARGET HIT", base.title, "**\(n) sessions** in \(month). Target hit.")
                : ("\(short) · \(n) OF \(target)", base.title, "**\(target - n) more** and \(month) hits its target. **The finish is in sight.**")
        default:
            return base
        }
    }
}

/// The real values a copy line may print. Nil means "no data": the line falls back.
struct HeroCopyFacts: Equatable {
    var weekPos: HeroWeekPos = .middle
    var monthPos: MatrixMonthPos = .middle
    var appsLocked = false
    var plannedToday = false
    var missedToday = false
    var tomorrowPlanned = false
    var setupDone = 0
    var alarm: String?
    var ring: String?
    var wake: String?
    var gymBy: String?
    var gym: String?
    var nextDay: String?
    var frozenEnd: String?
    var count = 0
    var goal = 3
    var streak = 0
    var habitDay: Int?
    var sessions = 0
    var lastWeek = 0
    var lastGoal: Int?
    var week = 1
    var month: String?
    var monthSessions = 0
    var monthTarget: Int?

    func value(_ name: String) -> String? {
        switch name {
        case "appsLocked": return appsLocked ? "" : nil
        case "tomorrowPlanned": return tomorrowPlanned ? "" : nil
        case "setupDone": return String(setupDone)
        case "alarm": return alarm
        case "ring": return ring
        case "wake": return wake
        case "gymBy": return gymBy
        case "gym": return gym
        case "nextDay": return nextDay
        case "NextDay": return nextDay.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        case "frozenEnd": return frozenEnd
        case "count": return String(count)
        case "goal": return String(goal)
        case "left": return count < goal ? String(goal - count) : nil
        case "streak": return streak > 0 ? String(streak) : nil
        case "day": return habitDay.map(String.init)
        case "toGo": return habitDay.flatMap { $0 < 66 ? String(66 - $0) : nil }
        case "sessions": return sessions > 0 ? String(sessions) : nil
        case "lastWeek": return lastWeek > 0 ? String(lastWeek) : nil
        case "lastGoal": return lastGoal.map(String.init)
        case "week": return String(week)
        case "month": return month
        default: return nil
        }
    }
}
