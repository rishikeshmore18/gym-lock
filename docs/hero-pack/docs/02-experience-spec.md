# GymLock: Hero Card and Done Flow Experience Spec

> Status: build spec for the native SwiftUI app (iOS 18+). Owner: Rishi.
> Inputs: `docs/FLOW.md` (behavior, wins on rules), `docs/UI-RULES.md` (look, motion, copy), the badge code (`Models/Badges/BadgeEngine.swift`, `Views/Progress/Badges/*`), and the web prototype (`web-reference/hero12`, `web-reference/hero13`).
> Scope: which theme a day uses, when rare moments appear, how celebrations are queued, done-flow timing, card motion, haptics, the card-style selector.

## 0. Conflicts with the rule files (decide before building)

| # | Rule file says | This spec says | Who decides |
|---|---|---|---|
| C1 | UI-RULES §5.7: "Nothing loops." | The hero card always has a calm idle loop (§5). It applies only to the hero card, the done flow and the style preview. | Rishi. Add the exemption to UI-RULES §5.7. |
| C2 | FLOW Flow 3: tapping the workout-done notification opens the Progress spotlight. | Tap opens Home, plays the done flow if it hasn't run, then goes to the spotlight (§4.1, row N). | Rishi. FLOW wins until it changes. Fallback: the notification opens the spotlight and the done flow waits for the next Home appear. |
| C3 | UI-RULES §9: no `selection()` haptic during a drag. | The prototype's per-dot ticks while dragging across the Matrix card are dropped. Only a soft touch-down tick plays (§6). | Settled. Follows UI-RULES. |
| C4 | UI-RULES §5.3: 300 ms ceiling in Operate screens. | Done flow and rank-up timings run past it. They fall under its existing "celebratory moments" exception. | Settled. |

The prototype's placeholder data must not ship: `autoPos()` derives the week position from the weekday, `monthCal()` invents a calendar, and copy hard-codes numbers ("Week 5 of 5", "Week streak 6", "07:00", "Iron Works"). Every number comes from a model field (UI-RULES §11). §1.5 defines the real `pos` and `monthPos`.

---

## 1. Theme rotation

### 1.1 The problem

The prototype ties the theme to the weekday: Mon radiant, Tue tiles, Wed signal, Thu levels, Fri vectors, Sat loops, Sun week. A Mon/Wed/Fri user only ever builds the sunrise, the battery and the +1. They never see 4 of the 7 done objects, and their Tue/Thu/Sat/Sun rest cards only ever show 4 of the 7 rest variants. Variety is what slows hedonic adaptation ([Sheldon & Lyubomirsky 2012](https://sonjalyubomirsky.com/wp-content/uploads/2024/07/Sheldon-Lyubomirsky-2012.pdf)), so the 7x19 variants we built only pay off if people see them.

### 1.2 Words

- **Theme index** `0...6`: radiant, tiles, signal, levels, vectors, loops, week. These are the 7 columns of `STATE12`, `mx/*.ts` `SCENES[]` and Ridge's `W[state][i]`. They are re-keyed from weekday to theme.
- **Display day**: the calendar day of `now − 4 h` in the current calendar. 00:00 to 03:59 still belongs to the previous day, so a bedtime card at 00:30 keeps that evening's theme. A session that counts on the alarm's day (FLOW item 20) uses that day's theme.
- **Training day**: a display day that is a planned gym day (`plan.effectiveTrainingDays`), a rescheduled day, or a day with a counted session.
- **Built**: a theme's done object counts as built in the current cycle when that session's done flow ends (sealed or closed) or its verified home card is displayed. One that expired unseen is not built.

### 1.3 Rules

1. **One theme per display day.** It is assigned the first time any card or flow needs it, persisted at once, and never changed for that day, even if a rest day turns into a training day.
2. **Training days pick from the themes not yet built this cycle.** A cycle ends when all 7 are built. Then `built` resets.
3. **No back-to-back repeats.** A training day never takes the previous training day's theme, or yesterday's theme, unless no other theme is left.
4. **Weekday alignment when free.** If the weekday's own theme is still unbuilt, the day takes it. A new user's first week therefore matches the prototype. Otherwise the day takes the next unbuilt theme in cyclic order after the last training theme.
5. **Other days** (rest, paused, setup, firstnight) take the theme shown least recently. They exclude yesterday's theme, the last training theme and the theme the next training day would get (peeked, not committed), so tomorrow's world stays fresh. Ties go to the weekday's own theme, then the next one in cyclic order from it.
6. **Offline and deterministic.** Only local state, the plan and the calendar are used. There is no randomness and no network.
7. **Copy splits into two layers.**
   - **Theme-keyed:** eyebrow and title (they name the visual), climax copy, live labels, TALLY, Ridge notes.
   - **Weekday-keyed:** the `sub` line, which carries weekday facts ("Friday is the most skipped weekday").
   - **Must be rewritten so they hold on any theme:** titles that name a weekday (`firstnight[6]` "Monday, day one.") and `DONE12` subs that assume a weekday plan ("Monday slipped, Tuesday didn't").

### 1.4 Pseudo-Swift

```swift
enum HeroTheme: Int, CaseIterable, Codable { case radiant, tiles, signal, levels, vectors, loops, week }

struct ThemeLedger: Codable, Equatable {
    var assigned: [String: Int] = [:]   // display-day key "yyyy-MM-dd" → theme; trimmed to 45 days
    var lastShown: [Int: String] = [:]  // theme → last display-day key it was assigned to
    var built: UInt8 = 0                // bit i = theme i built in this cycle
    var cycle = 0
    var lastTrainingTheme: Int?
    static let full: UInt8 = 0b111_1111
}

enum DayKind { case training, other }

enum ThemeRotation {
    static let rolloverHour = 4

    static func displayDay(_ date: Date, _ cal: Calendar) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .hour, value: -rolloverHour, to: date)!)
    }
    static func key(_ day: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    /// Monday = 0 … Sunday = 6 (Calendar.weekday: Sunday = 1).
    static func weekdayIndex(_ day: Date, _ cal: Calendar) -> Int { (cal.component(.weekday, from: day) + 5) % 7 }
    private static func forward(_ c: Int, after base: Int) -> Int { (c - base - 1 + 14) % 7 }

    /// Pure: what a training day would get. Used to commit and to peek.
    static func trainingPick(_ l: ThemeLedger, day: Date, yesterday: Int?, _ cal: Calendar) -> Int {
        let w = weekdayIndex(day, cal)
        var c = Set((0..<7).filter { l.built & (1 << $0) == 0 })
        if c.isEmpty { c = Set(0..<7) }                       // defensive; built resets when full
        if let t = l.lastTrainingTheme, c.count > 1 { c.remove(t) }
        if let y = yesterday, c.count > 1 { c.remove(y) }
        if c.contains(w) { return w }
        let base = l.lastTrainingTheme ?? (w + 6) % 7
        return c.min { forward($0, after: base) < forward($1, after: base) }!
    }

    static func otherPick(_ l: ThemeLedger, day: Date, yesterday: Int?, nextTrainingDay: Date?, _ cal: Calendar) -> Int {
        let w = weekdayIndex(day, cal)
        let peek = nextTrainingDay.map { trainingPick(l, day: $0, yesterday: nil, cal) }
        var c = (0..<7).filter { $0 != yesterday && $0 != peek && $0 != l.lastTrainingTheme }
        if c.isEmpty { c = (0..<7).filter { $0 != yesterday } }
        func age(_ t: Int) -> String { l.lastShown[t] ?? "0000-00-00" }   // never shown = oldest
        return c.min {
            (age($0), $0 == w ? 0 : 1, forward($0, after: (w + 6) % 7)) <
            (age($1), $1 == w ? 0 : 1, forward($1, after: (w + 6) % 7))
        }!
    }

    /// The only writer. Call on the main actor; persist the ledger right after.
    static func theme(for date: Date, kind: DayKind, nextTrainingDay: Date?, ledger l: inout ThemeLedger, _ cal: Calendar) -> HeroTheme {
        let day = displayDay(date, cal), k = key(day, cal)
        if let t = l.assigned[k] { return HeroTheme(rawValue: t)! }   // rule 1: stable
        let yKey = key(cal.date(byAdding: .day, value: -1, to: day)!, cal)
        let y = l.assigned[yKey]
        let t = kind == .training
            ? trainingPick(l, day: day, yesterday: y, cal)
            : otherPick(l, day: day, yesterday: y, nextTrainingDay: nextTrainingDay, cal)
        l.assigned[k] = t
        l.lastShown[t] = k
        if kind == .training { l.lastTrainingTheme = t }
        l.assigned = l.assigned.filter { $0.key >= key(cal.date(byAdding: .day, value: -45, to: day)!, cal) }
        return HeroTheme(rawValue: t)!
    }

    /// Call when a session's done flow ends (sealed or closed) or its verified card is displayed.
    static func markBuilt(_ t: HeroTheme, ledger l: inout ThemeLedger) {
        l.built |= 1 << t.rawValue
        l.lastTrainingTheme = t.rawValue          // also covers an unplanned day that was "other"
        if l.built == ThemeLedger.full { l.built = 0; l.cycle += 1 }
    }
}
```

**Persistence.**
- `ThemeLedger` lives in `UserDefaults` under `hero.themeLedger.v1`. Use the App Group suite if a widget ever reads it. It is under 2 KB. Write it synchronously right after each assignment.
- Once assigned, a theme survives relaunches, time-zone travel and a clock set backwards, because the key already exists.
- `nextTrainingDay` is the next display day after today that is a planned or rescheduled gym day.

### 1.5 Week position, month position, taps

```swift
enum WeekPos { case first, middle, last, bonus }
/// k = counted session days this week including today; goal = the week's saved goal (min 3).
func weekPos(k: Int, goal: Int) -> WeekPos {
    k > goal ? .bonus : k == goal ? .last : k == 1 ? .first : .middle
}
```

**Week position.**
- `.bonus` uses the `middle` visuals with FLOW's bonus line ("4 this week. that's a bonus day.").
- `.last` is the session that keeps the week. It uses `DONE12.last` ("WEEK COMPLETE").
- If a week is kept on its last day there is no separate week-kept screen: the done flow is the week-kept moment.

```swift
enum MonthPos { case first, middle, last }
func monthPos(earlierCountedThisMonth: Int, plannedDaysLeftAfterToday: Int, recapShownThisMonth: Bool) -> MonthPos {
    let isLast = plannedDaysLeftAfterToday == 0 && !recapShownThisMonth
    if isLast { return .last }                 // the recap is the truth of the month; it wins a tie
    return earlierCountedThisMonth == 0 ? .first : .middle
}
```

**Month position.**
- `.first` is the first counted session of the calendar month, whatever the date. It adds the month screen with the target pick, once a month.
- `.last` is a session after which no planned or rescheduled gym day is left in the month. It adds the recap, once a month.
- If a month ends without a `.last` session, there is no recap. The month stays visible in Progress, and nothing carries into next month's flow.

**Taps on the climax.** `N = (pos == .last || theme == .week) ? 7 : 5`. Seven taps close the week, and the week/hourglass object has one piece per weekday. VoiceOver gets a single "build" action that completes every tap.

### 1.6 Worked example: Mon/Wed/Fri user, 3 weeks

This output comes from running the algorithm. It starts Mon 2 Nov 2026 with an empty ledger, every session done, and the app opened every day. `built` is shown after each day.

| Date | Day | Kind | Theme | Built this cycle | Home card that day |
|---|---|---|---|---|---|
| 02 Nov | Mon | train | 0 radiant (own) | {0} | wake…verified, sunrise built |
| 03 Nov | Tue | other | 1 tiles | {0} | rest (peek next = 2) |
| 04 Nov | Wed | train | 2 signal (own) | {0,2} | battery built |
| 05 Nov | Thu | other | 3 levels | {0,2} | rest |
| 06 Nov | Fri | train | 4 vectors (own) | {0,2,4} | week kept: done flow `pos=.last`, N=7 |
| 07 Nov | Sat | other | 6 week | {0,2,4} | weekkept (§2) |
| 08 Nov | Sun | other | 0 radiant | {0,2,4} | weekkept |
| 09 Nov | Mon | train | 5 loops (next after 4) | {0,2,4,5} | ring built (freshstart only for go-later users, §2) |
| 10 Nov | Tue | other | 1 tiles | … | rest |
| 11 Nov | Wed | train | 6 week | {0,2,4,5,6} | hourglass built, N=7 |
| 12 Nov | Thu | other | 2 signal | … | rest |
| 13 Nov | Fri | train | 1 tiles | {0,1,2,4,5,6} | wall built, `pos=.last`, N=7 |
| 14 Nov | Sat | other | 4 vectors | … | weekkept |
| 15 Nov | Sun | other | 0 radiant | … | weekkept |
| 16 Nov | Mon | train | 3 levels | cycle 1 complete → {} | barbell built; the "far" set strip reads 7 of 7 |
| 17 Nov | Tue | other | 5 loops | {} | rest |
| 18 Nov | Wed | train | 2 signal (own) | {2} | |
| 19 Nov | Thu | other | 6 week | {2} | rest |
| 20 Nov | Fri | train | 4 vectors (own) | {2,4} | |

What the example shows:
- **Coverage:** all 7 done objects are built in 7 sessions (15 days).
- **Rest variety:** rest days show 6 themes in the first 2 weeks and all 7 by 17 Nov.
- **No back-to-back repeat:** no two consecutive days share a theme, and no training day repeats the previous training day.
- **Cycles differ:** cycle 2 runs 2, 4, 0, 1, 3, 5, 6. Cycle 1 ran 0, 2, 4, 5, 6, 1, 3.

**Other plans.**
- A 7-day user keeps weekday alignment forever: each day's own theme is always free.
- A Mon–Fri user covers all 7 themes by Tue of week 2.
- A missed training day leaves its theme unbuilt. It comes back on a later training day, never the very next one.

---

## 2. Moment exposure

### 2.1 Two kinds of home state

| Kind | States | Rule |
|---|---|---|
| **Functional**: driven by the session engine; never replaced | setup, firstnight, bedtime, wake, countdown, ready, commute, atgym, verified, stilltime, paused | Shown whenever their condition holds. |
| **Ambient**: fills the idle part of a display day | rest, freshstart, missed, weekkept, comeback, drift, halfway, automatic | **One ambient state per display day**, chosen once by the priority below and frozen for the day. A rest day therefore never flips between rest and drift mid-afternoon. |

Wake & Go users have no ambient slot on gym days: bedtime runs straight into wake. Go-later users have one between wake and the alarm.

### 2.2 Ambient priority and windows

| Priority | State | Eligible when | Window | Cap | If no slot in window |
|---|---|---|---|---|---|
| 1 | automatic | habit day ≥ 66 (calendar days since first counted session, +1) **and** the live week has a counted session or last week was kept | days 66–79 | once ever | Also offered by the done flow (§2.3). If the user is lapsed, wait until they next keep a week, then show it on the next slot. |
| 2 | halfway | habit day ≥ 33 | days 33–39 | once ever | Done flow (§2.3), else dropped silently |
| 3 | comeback | streak broke after ≥ 1 kept week, or ≥ 8 days without a counted session | until the next counted session, max 3 display days | per lapse | Its copy moves to the done flow's `today` screen |
| 4 | missed | yesterday was a planned day, not counted, not rescheduled | today | per miss | Dropped. The FLOW notification already covered it. |
| 5 | weekkept | the live week reached its goal before today | the rest of that week | per week | none: the done flow was the week-kept moment |
| 6 | drift | habit days 22–35 (week 4–5: half drop off by week 6, FLOW Overview) | days 22–35 | once ever | Dropped. Never shown inside the done flow: it would damp the peak. |
| 7 | freshstart | first display day of the week, or the first open in a new week | that day | per week | Monday trainers get the new week through `DONE12.first` |
| 8 | rest | any other non-training day | | | |

**Spacing:** at most one once-ever moment (automatic, halfway, drift) per 2 display days. A second one waits.

**Why gate them:** rare moments only feel rare if they stay rare. Duolingo plays its full-screen streak animation only on milestone days, and a normal day gets just a counter tick ([Deconstructor of Fun](https://duolingo.deconstructoroffun.com/mechanics/streaks), [Duolingo blog](https://blog.duolingo.com/streak-milestone-design-animation)). Forcing a moment outside its window turns a true statement ("day 33") into a stale one, which breaks UI-RULES' honesty rule.

### 2.3 Milestones inside the done flow

**Halfway and automatic.** When the session itself crosses day 33 or day 66 (or is the first session inside the window):
- The done flow's `far` screen uses its milestone variant ("Day **33** of about 66").
- After the flow, the home card lands on `halfway` or `automatic` instead of `verified` for the rest of the day.
- This guarantees the user meets the milestone at its peak without taking over a rest day.

**Comeback.** The first session after a lapse uses comeback copy on the `today` screen ("you came back. that's the hardest one.", from FLOW). Any Comeback or Second Wind badge appends as a rank-up step (§3).

### 2.4 Preview of the next theme: deliberately minimal

- **No preview of which object comes next.** Uncertainty about a reward raises effort while pursuing it ([Shen, Fishbach & Hsee 2015, via Chicago Booth Review](https://www.chicagobooth.edu/review/uncertainty-can-improve-motivation)). Spoiling the next build would also spend its novelty early.
- **One honest anticipation cue: the set strip.** The `far` screen shows a 7-slot strip of done-object silhouettes. Built ones are filled, unbuilt ones are outlines, and today's object flies into its slot. The label reads "3 of 7" (from `ThemeLedger.built`).
  - It is goal-gradient and endowed-progress ([Kivetz, Urminsky & Zheng 2006](https://business.columbia.edu/sites/default/files-efs/pubfiles/1200/goalgradient.pdf)).
  - It tells the user every object exists without saying which comes next.
- **On cycle completion** the strip fills and holds for 600 ms with a light haptic. It never adds an extra modal.

---

## 3. Celebration orchestration

### 3.1 What can celebrate

| Item | Source | Bound to a session? | Presentation |
|---|---|---|---|
| Done flow | session verified (FLOW Flow 3) | yes | full-screen sequence |
| Badge rank-up: streak ladder (the streak milestones), days ladder, achievement | `BadgeRules.states` diff, before vs after the session's ledger write | yes, except backlog or repair | step inside the done flow; standalone only for backlog |
| Week kept | goal reached | yes | `pos = .last` inside the done flow; `weekkept` ambient card afterwards |
| Halfway / automatic | habit day | sometimes | done-flow `far` variant, or ambient card |
| Freeze earned | FLOW Flow 5 | no | existing notification; in-app, a home banner line, never a modal |
| Set complete (7 of 7) | `ThemeLedger` | yes | inline on the `far` strip |

### 3.2 One queue

`CelebrationQueue` is an `@Observable @MainActor` store, persisted as JSON in `UserDefaults` (`celebrations.v1`). It is the **only** thing that presents full-screen celebrations.

```swift
struct PendingCelebration: Codable, Identifiable {
    enum Kind: Codable { case doneFlow(sessionID: UUID), rankUp(badgeID: String, sessionID: UUID?) }
    let id: UUID; let kind: Kind; let earnedAt: Date; let displayDay: String
}
```

**Rules:**
1. **One full-screen celebration sequence per foreground session.** A foreground session runs from `scenePhase == .active` until the app has been in the background for 10 min or more. A shorter trip out continues the same session.
   - Basis: HIG modality says "Let people dismiss a modal view before presenting another one" ([HIG Modality](https://developer.apple.com/design/human-interface-guidelines/modality)).
2. **Session-bound rank-ups merge into that session's done flow** as final steps after the count, before the collapse:
   - **At most 2 steps.** Rank by group (streak > days > achievement), then tier rank. Show the top two, lower first, so the larger lands last (peak-end: [Kahneman et al. 1993](https://www.psychologicalscience.org/journals/psychological-science/j.1467-9280.1993.tb00589.x/)).
   - **Only the highest rung per ladder.** `BadgeRankUpRequest(unlocking:)` already animates from the previous rung.
   - **Why inside the flow and not after the collapse:** two full-screen modals back to back read as stacking. Strava attaches PRs and trophies to the activity that earned them ([Strava](https://communityhub.strava.com/insider-journal-9/getting-started-with-strava-achievements-1534)). Duolingo's post-lesson chain is one tap-through sequence ([Deconstructor of Fun](https://duolingo.deconstructoroffun.com/mechanics/streaks)).
3. **The 3rd and later badges go quiet.**
   - They get a coral dot on the Progress tab and a "new" state on the badge card.
   - The slot pop (`BadgeHaptics.playLand`) plays the first time the Badges screen shows them.
   - Apple's own model works this way: awards land in a trophy case in the Fitness app ([Apple](https://www.apple.com/watch/close-your-rings/)). Routine good days get quiet inline marks, like Oura's crowns ([BGR](https://www.bgr.com/2250779/what-does-crown-symbol-mean-oura-ring/)).
4. **Standalone rank-ups** (backlog, ledger repair, a badge found without a pending done flow):
   - At most 1 per foreground session, and never in a session that already had a done flow.
   - The next standalone needs a foreground session that starts ≥ 30 min after the previous celebration ended.
   - It presents after the home card's beat settles: the card scene's last haptic time + 400 ms, clamped to 1.2–3.0 s after Home appears.
   - A standalone pending for more than 7 days goes quiet.
   - Spacing keeps each one strong: breaks restore enjoyment that steady exposure wears down ([Nelson & Meyvis 2008](https://interruptions.net/literature/Nelson-JConsumRes09.pdf)).
5. **Several sessions verified before the app opens.** Only the latest session that is still valid (§4.3) gets a done flow. Older ones are consumed silently, and their rank-ups join the latest flow under rule 2.
6. **No local celebration notification while the app is foreground.** The workout-done notification is suppressed when the app is active on Home; the flow plays instead.

### 3.3 Order inside one done flow

```text
verified → today → week → [month: first | last] → far (+set strip, +halfway/automatic variant)
→ climax (N taps) → seal → count → [rank-up ≤ 2] → collapse into the home card
```

### 3.4 Backgrounded mid-flow

The flow's state is persisted on every change: screen index, taps, `sealedAt`, `monthPick` and the remaining rank-ups.

| Away for | On return |
|---|---|
| < 10 min, process alive | Resume on the same screen, already settled. No entrance replay and no haptics replay. Taps are kept. |
| ≥ 10 min, or process killed, not sealed | Resume **at the climax**, with the taps already made. The informational screens are skipped. Resuming at a task boundary is far less annoying than mid-task ([Adamczyk & Bailey 2004](https://hci.rwth-aachen.de/materials/conferences/CHI2004/1p271.pdf)), and the build is the part that turns effort into attachment. |
| ≥ 10 min, sealed | Show the count, settled. Pending rank-ups follow. Otherwise collapse after 600 ms. |
| The display day ended while away | Discard the flow. The theme stays unbuilt. Rank-ups follow rule 4 (standalone). |

On `scenePhase == .background`, stop Core Haptics players and freeze the overlay clock. On return, the clock resumes; it never jumps forward.

### 3.5 The hero card while a celebration is up

- The card's `TimelineView` is paused and its scene clock frozen. Its haptics are muted (prototype: `if (overlay) return`).
- On collapse the card switches to `verified` (or `halfway` / `automatic`) at 70% of the collapse (385 ms in). It plays its visual entrance **without** scene haptics, because the flow already delivered them. Its idle loop starts after.
- The verified card's own scene haptics play only if no done flow ran for that session today.

---

## 4. Done flow timing

### 4.1 When it opens

| # | Situation | Opens | How |
|---|---|---|---|
| A | 20:00 proof hits while the atgym card is visible on Home | proof beat at T0 (success + heavy at +140 ms), overlay at **T0 + 1300 ms** | expands from the card frame, 450 ms, `Theme.settle` curve. It exits along the same path (UI-RULES §5.6). |
| B | An Apple Health workout verifies while on Home | the card plays the same proof beat, overlay at **+1300 ms** | as A |
| C | Verified while the user is on another tab, a sheet or the camera | **never interrupts.** A coral dot goes on the Home tab, and the flow presents on the next Home appear at **+700 ms**. Interruptions raise stress ([Mark, Gudith & Klocke 2008](https://www.interruptions.net/literature/Mark-CHI08.pdf)), and HIG reserves modality for a clear benefit. | as A |
| D | Verified in the background, then the app opens (cold or warm) on Home | **Home appear + 700 ms**: the card's 600 ms entrance finishes, then the flow takes over. This is the prototype's timing. | as A |
| E | The app opens to another screen by deep link | as C | |
| F | The user is touching or scrolling Home at the trigger time | waits for touches to end + 500 ms of no touch | |
| G | Home is scrolled down | scroll to top (300 ms), then present | |
| N | Workout-done notification tapped (needs C2) | Home + **300 ms** (explicit intent), flow, then the Progress spotlight after the collapse | |
| X | Already completed, closed or expired | never auto-presents. Tapping the verified card replays it until the display day ends (no rank-ups, month screen read-only, theme unchanged). | |

**Opens automatically, once.** The session is the product's main event. The user already did the work; the flow only pays it out.

### 4.2 Screens, dwell, advance

Screens **never auto-advance**. Keep the prototype's behavior. Duolingo advances its post-lesson screens on a Continue tap ([Deconstructor of Fun](https://duolingo.deconstructoroffun.com/mechanics/streaks)), and the user sets the pace.

**Tap rules:**
- Tap before a screen settles: it jumps to its settled state, with a light haptic.
- Tap after it settles: the next screen.
- Tap the left 22% of the screen: back one screen, settled, with a light haptic.
- The tap hint fades in at settle and never pulses.

| Screen | Matrix settle (s) | Ridge settle (s) | Notes |
|---|---|---|---|
| verified | 1.5 | 2.0 | |
| today | 2.3 | 1.8 | comeback copy when §2.3 applies |
| week | 2.4 | 1.8 | `pos` copy |
| month | 1.8 | 1.6 | `.first`: the target must be picked before it can advance; a first tap off the chips picks the default ("your pace", 18 in the prototype; it should be derived from the plan: weekly goal × weeks left in the month). `.last`: recap. |
| far | 1.9 | 2.0 | set strip; halfway/automatic variant |
| climax | 1.0 | 1.0 | then N taps |

**After the last climax tap**, measured from the seal at S:

| Event | Time |
|---|---|
| Seal haptic pattern | S |
| Count lands | S + 1.6 s |
| Collapse starts, Matrix | S + 3.6 s |
| Collapse starts, Ridge | S + 2.8 s |
| Collapse starts, month `.last` and `pos == .last` | S + 4.2 s |
| Collapse length | 0.55 s; the card swaps at 0.385 s |
| Overlay gone | collapse start + 0.55 s |

**With rank-up steps,** the collapse start becomes the rank-up start instead:
1. A 200 ms crossfade into `RankUpView`. Tapping is possible from frame 100 (3.33 s).
2. A tap moves to the next rank-up, or after the last one the badge flies to the **Progress tab icon** (the existing 0.72 s `BadgeFlightView` arc).
3. The done-flow collapse starts 200 ms after the flight starts. The ending is always the same: back into the home card.

### 4.3 Skip, close, expiry

- **Close control.**
  - A glass X in the top-right corner (44 pt, UI-RULES §8 chain), visible from the first frame.
  - A swipe down also closes: commit on 35% travel or 500 pt/s (UI-RULES §6.6).
  - Closing skips the remaining screens and rank-ups and collapses at once (0.55 s).
  - Skipped rank-ups go quiet (rule 3). The theme counts as built because the verified card shows the finished object.
- **Expiry.** A session's flow can present until its counting display day ends (04:00 the next morning). After that it is discarded.
- **Never twice.** A flow is consumed when it collapses (completed or closed) or expires. `consumedSessionIDs` keeps the last 60.
- **Fatigue guard.** Sessions run 3–7 times a week, and the same 6–7 screens wear thin even with themes rotating. After 21 completed flows, if the user closed early in 3 or more of the last 5, the default becomes **short**: verified → climax → count, plus any month screen and rank-ups. Profile gets a "done screens: full / short" setting, and the user's choice always wins.

### 4.4 Accessibility

- **VoiceOver.**
  - Each screen is one element: eyebrow, title and sub. A double tap advances.
  - The climax exposes a "build" action that seals it.
  - `UIAccessibility.post(.screenChanged)` fires on each screen.
- **Reduce Motion.**
  - Screen changes become a 200 ms crossfade.
  - No camera moves, shakes or flashes; dot flights become crossfades.
  - The taps and their haptics stay, so the outcome is the same (UI-RULES §5.8).

---

## 5. Card motion: always alive

Every hero card has three phases. Motion is a pure function of `T = now − stateEnteredAt` (scene clock) and never of frame count, so timing is identical at 120, 60 or 30 Hz.

| Phase | Window | Rules |
|---|---|---|
| **Entrance** | T 0–0.6 s | Matrix: dots fly from the previous scene, or from scattered on a cold start. Ridge: camera push, 600 ms. The copy follows UI-RULES §5.6 stagger (eyebrow 0 ms, title 60 ms, sub 120 ms). |
| **Beat** | one onset, T 0.3–2.5 s (the scene's `hap` times; wake rings are the exception) | `flash ≤ 0.3`, `shake ≤ 0.4`, both off under Reduce Motion. The haptic lands on the same frame. One beat per scene. Motion onset grabs attention; ongoing motion doesn't ([MATRIX-DESIGN.md](../web-reference/hero13/MATRIX-DESIGN.md), Abrams & Christ 2003). |
| **Idle** | after the scene settles (≤ 3 s), until the state changes | See the idle rules below. |

**Idle rules:**
- **Shape:** calm and local, one of breath (4 s), light sweep (6 s) or slow flow (8 s). Every idle function's period divides 24 s, so composites stay seamless.
- **Amplitude:** brightness varies by 15% or less on the moving element. Nothing full-card at around 0.2 Hz.
- **Never:** flicker, random twinkle, or haptics.
- **Functional tickers keep ticking:** countdown digits, the atgym timer, stilltime.

**Wake rings.**
- The visual rings follow `RINGS = [0.35, 0.85, 1.35, 1.85, 2.35]`, then 2.85, then every 2.5 s.
- If `AlarmRinger` is playing, the ring visuals take their beat times from the ringer's active pattern, and the card adds **no** haptics (§6.3).

**Re-entry.**
- Switching tabs or returning from background resumes the frozen T. It does not replay the entrance.
- The entrance replays only when the state, theme or style changes.

**Pause when:**
- less than 10% of the card is visible (scroll),
- `scenePhase != .active`,
- any overlay or full-screen celebration is up,
- a sheet covers 50% or more of Home.

Paused means `TimelineView(paused: true)`, the scene clock frozen and the Matrix spring solver stopped.

**Frame rate** (`TimelineView(.animation(minimumInterval:paused:))`):

| Condition | Entrance + beat | Idle |
|---|---|---|
| ProMotion (needs `CADisableMinimumFrameDurationOnPhone = YES` in Info.plist) | display rate, up to 120 Hz | 60 Hz (`minimumInterval: 1/60`) |
| 60 Hz device | 60 Hz | 30 Hz |
| Low Power Mode (`ProcessInfo.isLowPowerModeEnabled`, observe `NSProcessInfoPowerStateDidChange`) | 60 Hz | 30 Hz. No glow or bloom. Particle count unchanged. |
| `thermalState == .serious` | 60 Hz | 30 Hz, no bloom |
| `thermalState == .critical` | 30 Hz | settled frame plus the Reduce Motion pulse |

Apple advises lower frame rates for small animations to save power ([AppleInsider on Apple's ProMotion guidance](https://appleinsider.com/articles/21/09/25/apple-tells-developers-how-to-use-120hz-promotion-for-iphone-13-pro)). In Low Power Mode, apps should "take appropriate steps to reduce activity" ([Apple](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)).

**Timing invariance.**
- The Matrix spring board (`MDots`, stiffness 210, damping 21) integrates in **fixed 1/240 s substeps** from an accumulator, and the renderer interpolates. Particle positions at a given T are then the same at any display rate.
- Ridge camera and kinetic type are closed-form in T, like `springValue` in `RankUpView.swift`.

**Reduce Motion.**
- **Entrance:** a 200 ms opacity crossfade.
- **Beat:** the haptic stays and the visual becomes a 200 ms opacity step.
- **Idle:** one opacity pulse on the coral accent cell or element only (0.6 → 1.0 → 0.6, 4 s). That keeps the card alive without movement.

**Performance budget** (acceptance):
- The idle card costs at most 3 ms of main-thread time per frame at 60 Hz on an iPhone 13.
- No dropped frames during the entrance on an iPhone 12.
- The Matrix board keeps 400 or fewer lit targets (cap 720).

---

## 6. Haptics map

### 6.1 Kinds to APIs

| Kind (prototype) | Single event: UIKit | Inside a Core Haptics pattern (starting values, tune on device) |
|---|---|---|
| light | `UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)` | transient I 0.45, S 0.55 |
| medium | `.medium`, intensity 0.9 | transient I 0.70, S 0.50 |
| heavy | `.heavy`, intensity 1.0 | transient I 1.0, S 0.35, plus continuous 0.05 s I 0.5, S 0.15 |
| success | `UINotificationFeedbackGenerator().notificationOccurred(.success)` | transient I 0.70, S 0.55 at 0; transient I 1.0, S 0.75 at +0.09 s |
| tick | `.rigid`, intensity 0.6 | transient I 0.50, S 0.90 |
| soft | `.soft`, intensity 0.6 | transient I 0.40, S 0.20 |

**Compile rule.**
- A scripted list with 2 or more events (card scenes, done-flow screens, seal) becomes **one `CHHapticPattern`**. It starts on the same frame as the visual's T0 (§6.4), which makes it immune to main-thread jitter.
- One-off events from user input (climax taps, chips, back-tap) use prepared UIKit generators.

**`.success` follows Apple's documented meaning only** ("a task or action has completed", [HIG Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)). It plays at four moments: the 20:00 proof, the seal, week kept and automatic. It is never used on an entrance. When porting the scene arrays, any other `success` (for example comeback and the verified card) becomes heavy.

### 6.2 The table

| Moment | Event(s) | Times (s) | API |
|---|---|---|---|
| **Card entrance**, every scene | per scene `hap` (Matrix `mx/*.ts`; Ridge `W[s][theme].hap ?? HAP_DEF[s]`), ported verbatim, keyed by **theme** | e.g. atgym `ENTRY` light 0.45; bedtime Mon medium 1.33 | pattern at state entry |
| **Card beats** | as above: halfway light 0.3 + heavy 0.68 (theme 0); automatic light 0.2, heavy 0.95, success 1.0 (theme 0); weekkept five lights + heavy 1.3 + success 1.33 (theme 0) | per file | pattern |
| **Play policy** | card scene haptics play **only the first time a state is entered in a display day** (`hapticsPlayed: Set<"day|state">`). Never on relaunch, tab return or replayed idle. They are dropped (not deferred) if the user is scrolling. | | |
| **Alarm rings** (wake card) | `ringHap`: heavy, medium, heavy, medium, heavy at 0.35, 0.85, 1.35, 1.85, 2.35; medium 2.85; heavy every 2.5 s from 5.35, 24 times (to 62.85 s) | | pattern, **only if `AlarmRinger` is not vibrating and AlarmKit is not alerting** |
| **Countdown, last 10 s** | 10…4: tick (prototype used medium; rigid reads as a clock); 3…1: heavy; 0: heavy (then the ready state) | each whole-second boundary | `.rigid` 0.6 / `.heavy` 1.0 prepared generators |
| **atgym, last 10 s** before 20:00 | 1190…1196: tick; 1197…1199: heavy | whole seconds | as countdown |
| **20:00 proof** | success, then heavy | 0, +0.14 | pattern |
| **Done: verified** (Matrix) | medium 0.05, heavy 0.75, success 0.80 | lt | pattern at screen T0 |
| **Done: verified** (Ridge) | light 0.05, medium 0.5, heavy 0.9, success 0.95, light 1.3, 1.42, 1.54 | lt | pattern |
| **Done: today** (M) | medium 0.05; light 0.30 + 0.14k, k = 0…12; heavy 2.12 | | pattern |
| **Done: today** (R) | medium 0.05; light 0.25 + 0.12k, k = 0…7; medium 1.3 | | pattern |
| **Done: week** (M) | medium 0.05; light 0.20 + 0.18k, k = 0…7; medium 1.9, 2.15 | | pattern |
| **Done: week** (R) | medium 0.05; medium 0.5, 0.68, 0.86; light 1.3 | | pattern |
| **Done: month** (M) | medium 0.05; light 0.25 + 0.1k, k = 0…7; heavy 1.3 | | pattern |
| **Done: month** (R) | medium 0.05; light 0.25 + 0.1k, k = 0…5; heavy 1.1 | | pattern |
| **Month target chip** | first pick: heavy, then success at +0.12; re-pick: medium | | prepared generators |
| **Done: far** (M) | medium 0.05, heavy 0.7, success 0.75, light 1.5 (+ set strip land: light at strip land) | | pattern |
| **Done: far** (R) | medium 0.05; light 0.30 + 0.13k, k = 0…6; heavy 1.4 | | pattern |
| **Done: climax** appear | medium 0.05 | | pattern |
| **Climax tap n of N** (n < N) | n ≥ N − 1: heavy; n > N/2: medium; else light. N = 5 gives L, L, M, H; N = 7 gives L, L, L, M, M, H. Fires on **touch-down**. | | prepared `.light` / `.medium` / `.heavy`; call `prepare()` again after each tap |
| **Seal** (tap N) | heavy, heavy, success | 0, 0.07, 0.16 | pattern, started on the touch-down frame |
| **Count lands** | soft | S + 1.6 | single `.soft` 0.6 |
| **Collapse lands** (card swap) | soft 0.5 | collapse + 0.385 | single |
| **Screen advance / skip-to-settled / back** | medium / light / light | on tap | prepared generators |
| **Badge rank-up** | `BadgeHaptics.playRankUp(tier:)` as built: light f4; rumble f14–40; 4 spin ticks f38–60; impact f60 + decaying rumble; slam f76; chip f92 (30 fps units) | | existing Core Haptics pattern |
| **Badge lands** (tab icon or grid slot) | `BadgeHaptics.playLand()` | flight end (0.72 s) | existing |
| **Setup card** item toggle | on: medium; off: light; all three done: heavy + success at +0.12 | | prepared generators |
| **Matrix card touch** | touch-down only: soft 0.4. No per-cell ticks (C3). | | prepared `.soft` |
| **Style selector** | the native segmented `Picker` selection haptic only | | system |

### 6.3 Gates and rate limits

A single `HeroHaptics` gate sits in front of every call above except `BadgeHaptics`, which is already exclusive.

**Gate (a haptic plays only if all of these hold):**
1. The in-app **Haptics** toggle is on (Profile, default on). Apple says "Make haptics optional" ([HIG](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)).
   - The app cannot read the System Haptics switch.
   - UIKit generators follow it. Whether Core Haptics follows it must be checked on a device, so the in-app toggle gates both.
2. `scenePhase == .active`.
3. `AlarmRinger` is not vibrating, and no AlarmKit alert is up. The alarm's own vibration always wins; card rings go visual-only.
4. The camera and microphone are not in use (progress photo, Story editor). The HIG warns haptics can disrupt the camera and microphone.
5. No full-screen overlay is up, for card haptics.

**Rate limits:**
- At least 50 ms between discrete events from different sources; the weaker one is dropped.
- At most one heavy or success per 300 ms outside an authored pattern.
- A new pattern stops the previous player (`stop(atTime: CHHapticTimeImmediate)`), and it never stacks.
- Missed haptics are **never replayed** after a pause. This is the prototype's `lastF` logic.

### 6.4 Landing on the same frame

**Core Haptics.**
- One `CHHapticEngine` is created when Home appears, with `isAutoShutdownEnabled = true` and `playsHapticsOnly = true`.
- `stoppedHandler` and `resetHandler` restart the engine and rebuild the players (`.applicationSuspended`, `.audioSessionInterrupt`, `.idleTimeout`; [Apple](https://developer.apple.com/documentation/corehaptics/chhapticengine/stoppedreason)).
- **Build the pattern and player when the state, screen or theme is chosen,** before T0.
- **Start on the visual's first frame:** take that frame's target timestamp `ts` from the `TimelineView` context date or a `CADisplayLink.targetTimestamp`. Then call `player.start(atTime: engine.currentTime + max(0, ts − CACurrentMediaTime()))`.
- **Set the visual's T0 to that same `ts`.**

**UIKit generators.**
- Call `prepare()` 0.2–2 s ahead and again after every trigger. Apple: calling it right before triggering "does not improve latency", and the prepared state lasts "typically seconds" ([UIFeedbackGenerator.prepare()](https://developer.apple.com/documentation/uikit/uifeedbackgenerator/prepare())).
- When to prepare:

| Generators | Prepare at |
|---|---|
| Countdown and atgym tick generators | 11 s before the final 10 s, then after each tick |
| Climax generators | climax appear, then after each tap |
| Done-flow advance generator | each screen's settle |

---

## 7. Card style selector (Profile)

**Placement.** Profile → section "home card":
- a full-width live preview (page margin 28, `Theme.cardRadius` 24, 1000:488 aspect),
- below it a native segmented `Picker`: "ridge | matrix".
- Two side-by-side thumbnails were rejected: at about 160 pt wide, the card's copy can't be read.

**Preview.**
- It renders **today's real state and theme** with the same `HeroCardView`, at preview scale. It is never a screenshot.
- It plays the entrance and beat, then idles. Tapping the preview replays the entrance and beat, with haptics (user-initiated).
- It runs at 30 Hz idle, settled plus the opacity pulse under Reduce Motion, and the static settled frame in Low Power Mode.

**Default and persistence.**
- The default is **ridge**, as in the prototype (`useState<Concept>('ridge')`). Its warm painted look matches the off-white identity in UI-RULES §1. Matrix is the opt-in instrument look.
- Stored with `@AppStorage("hero.cardStyle")` as `"ridge" | "matrix"` (App Group suite if widgets need it). It is written on selection.
- Only Dynamic ships. There is no Classic option.

**The switch.**
- The segmented control's own haptic plays, and no extra one.
- The old style fades out over 150 ms while the new style plays its 600 ms entrance: Matrix dots fly in from scatter, or the Ridge camera pushes in.
- It is interruptible: switching again mid-entrance retargets from the current values.
- Home picks up the new style on its next appear. The card plays its entrance there **without** beat haptics, since they were felt in the preview.
- The done flow reads the style when it starts, so a switch never changes a flow already running.

**Accessibility.**
- The picker is labeled "card style".
- The preview's label is "preview of the ‹style› card: ‹eyebrow›, ‹title›", with a "replay" action.

---

## 8. Acceptance checklist

**Theme rotation**
- [ ] Theme is keyed by display day (04:00 rollover). Every card and flow on one day shares it, across relaunch, tab switches, time-zone change and a clock set backwards.
- [ ] A Mon/Wed/Fri test fixture reproduces the §1.6 table exactly (Swift Testing, pure `ThemeRotation` with injected `calendar`).
- [ ] All 7 done objects are built within 7 consecutive completed sessions for 3-, 4-, 5- and 7-day plans.
- [ ] No training day repeats the previous training day's theme. No two consecutive display days share a theme, unless it is the only one left.
- [ ] Scenes and theme-keyed copy are indexed by theme. `sub` lines are indexed by real weekday. No title names a weekday.
- [ ] `pos` comes from counted days versus the saved weekly goal, and `.bonus` exists. `monthPos` follows §1.5. N = 7 iff `pos == .last` or theme is week.

**Moments**
- [ ] One ambient state per display day, chosen by the §2.2 priority and frozen.
- [ ] Halfway and automatic appear exactly once, in their window, through the ambient slot or the done-flow `far` variant. Automatic is withheld while the user is lapsed.
- [ ] Drift never appears inside the done flow. No two once-ever moments fall within 2 display days of each other.
- [ ] The set strip on `far` shows built/unbuilt for this cycle and never reveals the next theme.

**Celebrations**
- [ ] Only `CelebrationQueue` presents full-screen celebrations. Never two at once, and at most one sequence per foreground session.
- [ ] Session-bound rank-ups appear as at most 2 steps after the count, lower tier first. The 3rd and later go quiet (Progress dot, slot pop on the Badges screen).
- [ ] Standalone rank-ups: at most 1 per foreground session, never after a done flow in the same session, ≥ 30 min apart, quiet after 7 days.
- [ ] Backgrounding at each screen resumes per §3.4. A killed process resumes at the climax with taps kept.
- [ ] The hero card is paused and silent under any overlay. After the collapse it enters without scene haptics.

**Done flow**
- [ ] Opens per §4.1 rows A–X, with measured delays of 1300 ms, 700 ms and 300 ms (±1 frame).
- [ ] Never interrupts another tab, sheet or camera. The Home tab shows the coral dot while a flow waits.
- [ ] No screen auto-advances. Tap-to-settle, tap-to-advance and left-edge back all work. The month target must be picked.
- [ ] Seal to count is 1.6 s. Collapse starts at 3.6 s (Matrix), 2.8 s (Ridge) or 4.2 s (month finale), and lasts 0.55 s with the card swap at 70%.
- [ ] Close (X and swipe down) collapses at once. A consumed or expired flow never auto-presents again. The verified card replays it until the day ends.
- [ ] The fatigue guard switches to the short flow per §4.3, and the Profile setting overrides it.
- [ ] VoiceOver can complete the whole flow, including a single "build" action. Under Reduce Motion the flow reaches the same states with crossfades.

**Motion**
- [ ] Every card has an entrance (≤ 0.6 s), one beat and a calm idle loop with a period dividing 24 s. No flicker, no idle haptics.
- [ ] Motion is identical at 120, 60 and 30 Hz (fixed-step springs; snapshot test at T = 0.3, 0.8, 1.6, 3.5 s across rates).
- [ ] The card pauses off-screen, in background, under overlays and under large sheets. It resumes without replaying the entrance.
- [ ] Low Power Mode, the thermal states and Reduce Motion behave per §5. The performance budget is met in Instruments.

**Haptics**
- [ ] Every row of §6.2 is implemented. Scripted lists play as single patterns aligned to the visual frame (verified with a 240 fps camera: ≤ 1 frame offset at 120 Hz).
- [ ] Scene haptics play once per state per display day. Nothing replays after a pause.
- [ ] Gates hold: Haptics toggle, active scene, no alarm vibration, no camera or mic, no overlay. Rate limits hold.
- [ ] `.success` only at the proof, the seal, week kept and automatic.

**Style selector**
- [ ] Live preview of today's real state. Ridge is the default. The choice persists and animates per §7. The flow style is fixed at flow start.

---

## Sources

**Apps**
- Duolingo, streak milestone design: https://blog.duolingo.com/streak-milestone-design-animation
- Duolingo, how the streak builds habit (the celebration animation's +1.7% 7-day retention; freezes): https://blog.duolingo.com/how-duolingo-streak-builds-habit
- Deconstructor of Fun, Duolingo streak mechanics and the post-lesson sequence: https://duolingo.deconstructoroffun.com/mechanics/streaks
- Apple, Close Your Rings (awards in a trophy case): https://www.apple.com/watch/close-your-rings/
- Strava, achievements tied to the uploaded activity: https://communityhub.strava.com/insider-journal-9/getting-started-with-strava-achievements-1534
- Nike Run Club, Activity tab (achievements live in a tab, not a modal): https://www.nike.com/help/a/nrc-activity
- Headspace, run streak shown on the Profile tab: https://help.headspace.com/hc/en-us/articles/215730567-How-does-the-run-streak-feature-work
- Oura crowns (quiet inline recognition): https://www.bgr.com/2250779/what-does-crown-symbol-mean-oura-ring/
- Opal home screen (Focus Score, gem milestones in the profile): https://opalapp.com/blog/introducing-the-new-opal-home-screen-track-your-screen-time-and-improve-your-focus

**Research**
- Kahneman, Fredrickson, Schreiber & Redelmeier 1993, peak-end ("adding a better end"): https://www.psychologicalscience.org/journals/psychological-science/j.1467-9280.1993.tb00589.x/
- Sheldon & Lyubomirsky 2012, the hedonic adaptation prevention model (variety): https://sonjalyubomirsky.com/wp-content/uploads/2024/07/Sheldon-Lyubomirsky-2012.pdf
- Nelson & Meyvis 2008, interruptions disrupt hedonic adaptation: https://interruptions.net/literature/Nelson-JConsumRes09.pdf
- Shen, Fishbach & Hsee 2015, the motivating-uncertainty effect: https://www.chicagobooth.edu/review/uncertainty-can-improve-motivation
- Kivetz, Urminsky & Zheng 2006, goal-gradient: https://business.columbia.edu/sites/default/files-efs/pubfiles/1200/goalgradient.pdf
- Adamczyk & Bailey 2004, interrupting at task boundaries: https://hci.rwth-aachen.de/materials/conferences/CHI2004/1p271.pdf
- Mark, Gudith & Klocke 2008, the cost of interrupted work: https://www.interruptions.net/literature/Mark-CHI08.pdf

**Apple platform**
- HIG, Playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- HIG, Modality: https://developer.apple.com/design/human-interface-guidelines/modality
- UIFeedbackGenerator.prepare(): https://developer.apple.com/documentation/uikit/uifeedbackgenerator/prepare()
- CHHapticEngine.StoppedReason: https://developer.apple.com/documentation/corehaptics/chhapticengine/stoppedreason
- ProcessInfo.isLowPowerModeEnabled: https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled
- Apple's ProMotion guidance (via AppleInsider): https://appleinsider.com/articles/21/09/25/apple-tells-developers-how-to-use-120hz-promotion-for-iphone-13-pro
