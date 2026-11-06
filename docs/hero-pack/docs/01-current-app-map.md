# 01 · Current app map for the hero card + done flow port

Read-only survey of `/home/claude/rishikeshmore18/gym-lock` (native SwiftUI, iOS 18). All paths below are under
`ios-gymlock/GymLock/` unless written in full. Rule files: `CLAUDE.md` = `AGENTS.md` (identical, 15 lines),
`docs/FLOW.md` (behaviour, wins on what happens and on quoted wording), `docs/UI-RULES.md` (look, motion, haptics, copy style).

> Ground rule from `CLAUDE.md`: anything touching alarms, sessions, arrival, Health, skips, streaks, freezes or their
> notifications must follow `docs/FLOW.md` exactly; "If a request conflicts with it, stop and say so before writing code."
> The conflicts found are listed in §4.4 and §10.

---

## 1. Architecture summary

### 1.1 Object graph (who owns what)

| Object | File | Kind | Injected / owned by |
|---|---|---|---|
| `AppStore` | `ViewModels/AppStore.swift` | `@Observable` `@MainActor final class` | `GymLockApp` `@State`, `.environment(store)` |
| `GymSessionCoordinator` | `Services/GymSessionCoordinator.swift` (2281 lines) + `+Debug.swift` | `@Observable` | `GymLockApp` `@State`, `.environment(coordinator)`; `attach(to:)` / `attach(photos:)` in `.task` |
| `GymVisitTracker` | `Services/GymVisitTracker.swift` | **plain `@MainActor final class`, not observable** | `coordinator.visits` |
| `HealthWorkoutObserver` | `Services/HealthWorkoutObserver.swift` | | `coordinator.health` |
| `GymArrivalMonitor` | `Services/GymArrivalMonitor.swift` | geofence | `coordinator.arrival` |
| `WindDownController` | `Services/WindDownController.swift` | `@Observable`, `isActive` | `coordinator.windDown` |
| `ProgressPhotoStore` | `Services/ProgressPhotoStore.swift` | `@Observable` | `GymLockApp`, `.environment(photos)` |
| `StreakIntroController` | `Views/Home/StreakIntroController.swift` | `@Observable` | `RootTabView` `@State intro` |
| `ProgressSpotlightModel` | `ViewModels/ProgressSpotlightModel.swift` | | `RootTabView` `@State spotlight` |
| `BadgeStore` | `ViewModels/BadgeStore.swift` | `@Observable` | `ProgressTabView` `@State badges` (not app-wide) |
| `LaunchCover.shared` | `ViewModels/LaunchCover.swift` | singleton | read directly |

### 1.2 Screen tree

```
GymLockApp
└─ ContentView                      (Views ContentView.swift)
   ├─ .fullScreenCover(isPresented: coordinator.isSessionLive) → MorningFlowView   ← every live session state
   ├─ GymLockLaunchIntroView (launch cover, zIndex 1)
   └─ switch store.stage: .onboarding | .scheduleSetup | .home → RootTabView
      RootTabView                   (Views/Home/RootTabView.swift)
      ├─ destination(.home)      TodayHomeView(intro:coordinator:isVisible:)   ← permanently mounted, opacity-hidden
      ├─ destination(.progress)  ProgressTabView(spotlight:)
      ├─ destination(.community) CommunityView
      ├─ destination(.profile)   ProfileView(tabRequestCount:)
      ├─ .safeAreaInset(.bottom) RootTabBar
      ├─ .sheet AddGymDaySheet, .sheet WakeTimeSheet
      └─ .fullScreenCover MorningSetupFlowView (first run)
```

`TodayHomeView.body` (Views/Home/TodayHomeView.swift):
`header` (logo, "GymLock", `StreakChip`) → `ScrollView { CalendarStripView · StreakRiskBannerView? · HeroCardView(stage: cards.hero) · MiniCardsRow(protection:next:path:) · MomentumSection(field:) }` + `.overlay { streakOverlay }` (the chip-to-card morph, `StreakCardContent`).

`cards` is a computed property: `HomeCardDeriver.derive(store: store, coordinator: coordinator)` evaluated **inside body on every pass** (UI-RULES §10 says cache in `@State`; existing deviation, comment says it is cheap). There is **no clock trigger**: time-based switches (21:00 night, countdown window entry) only appear when something observed changes. Only `CountdownHero` ticks, via its own `TimelineView(.periodic(by: 1))`.

### 1.3 Files the port will touch

| Action | File | Exact symbols |
|---|---|---|
| **Replace** | `Views/Home/Visuals/HeroCard.swift` | `HeroCardView(stage:onCTA:)`, private `ImageHero`, `RingHero`, `CountdownHero` (static `anchoredTarget`), `SetupHero`, `PatternHero`, `ComebackHero`. **Keep** `HeroMetrics` (aspect `2.05`, `maxWidth 480`, `cornerRadius 24`, `padding max(15, w*0.052)`, `eyebrowSize`, `headlineSize w*0.088`, `supportSize w*0.040`) |
| **Replace** | `Views/Home/Visuals/HeroPreviewMatrix.swift` | private `StageCanvas`, 19 `#Preview`s keyed to `HeroStage` |
| **Rewrite resolver** | `Models/HomeStage.swift` | `HomeCardModel`, `enum HeroStage` (17 cases), `HomeCardDeriver.derive / cardSection / model(for:) / resolvedModel / setupChecklist / isComebackDay / countdownStage / deduplicated / heroClaim / nextDeadline / aggregateStage / weekStage / patternStage / monthStage / restDayModel / nextTrainingDayLabel`. **Keep** `ProtectionCard`, `NextCard`, `PathCard`, `protection(...)`, `nextIdle`, `nextDuringSession`, `ChecklistItem` |
| Edit (slot only) | `Views/Home/TodayHomeView.swift` | line 106 `HeroCardView(stage: cards.hero)`; add done-flow trigger + style read |
| Keep, maybe trim | `Views/Home/Visuals/GymLockVisuals.swift` | `GymLockProgressRing`, `GymLockChecklist`, `GymLockStepDots`, `GymLockLinearProgress`, `GymLockMiniBarChart`, `GymLockMetricPair`, `GymLockHeroImageBlend` (hero-only), `GymLockCircularCTA` (unused: `onCTA` never passed), `GymLockNumberedSteps` (Comeback only) |
| Keep | `Views/Home/Visuals/MiniCardsRow.swift` | `MiniCardsRow`, `ProtectionMini`, `NextMini`, `PathMini` |
| Keep | `Views/Home/Visuals/MomentumSection.swift`, `MomentumFlameProgress.swift`, `Models/MomentumField.swift` | `MomentumField.build(log:plan:schedule:weeklyGoal:now:calendar:)` (Monday-first, `countedCount`, `targetCount`, `days[].mark`) |
| Add setting | `Views/Home/PreferencesView.swift`, `ViewModels/AppStore.swift` | `PreferencesHome`, `AppStore.Key` |
| Present done flow | `Views/Home/RootTabView.swift` (recommended), `Services/GymSessionCoordinator.swift` | see §4 |
| Coordinate celebrations | `Views/Home/StreakIntroController.swift` | `isSuspended`, `lastCelebratedWeekStart` |
| Assets removable after port | `Assets.xcassets/HeroDiscipline, HeroMountain, HeroRest, HeroRoad, HeroSummit` | referenced only by `HeroCard.swift` |
| Tests to add | `ios-gymlock/GymLockTests/` | no `HomeCardDeriver` test exists today; pattern: Swift Testing, pure `now:`/`calendar:` |

---

## 2. Source-of-truth data the moments read

| Need | Exact source | Notes |
|---|---|---|
| Live morning | `coordinator.session: GymSession?`, `.state: GymSessionState`, `coordinator.route: MorningRoute?`, `coordinator.isSessionLive` | `GymSessionState.isLive` true for everything except `idle, alarmScheduled, completed, missed, rescheduled` |
| Session timing | `GymSession.alarmFiredAt`, `committedAt`, `deadline`, `arrivalTarget` (ring + Time to Gym), `departedAt`, `arrivedAt`, `remaining(at:)`, `elapsedFraction(at:)`, `timeToGymMinutes`, `flowMode` | absolute dates, relaunch-safe |
| Gym visit (post-arrival, survives session end) | `coordinator.visits.openVisit(now:calendar:) -> GymVisit?`; `GymVisit.arrivedAt`, `timeCounts`, `manualAt`, `pendingExitAt`, `leftAt`, `presenceEnd(now:)`, `minutesAtGym(now:)`, `presenceQualifies(now:)`, `isCounted`, `countedAt`, `proof`, `sleepBedtime`, `isHome` | persisted `gymlock.gymVisits`; dropped 24 h after `closesAt` |
| Proof rules | `WorkoutRules.minimumMinutes = 20`, `healthEarliestBeforeArrival 15 min`, `healthWindowAfterArrival 5 h`, `shortTripGrace 5 min`, `doneNoticeAfterArrival 30 min`, `WorkoutRules.proof(for:now:workouts:photos:calendar:) -> WorkoutProof?` | `WorkoutProof: unproven, legacy, health, timeAtGym, photo` (`Models/GymVisit.swift`) |
| Ledger | `store.log: MomentumLog` → `outcomes: [SessionOutcome]`; `outcome(on:calendar:)`, `SessionOutcome.counts`, `.isVerifiedWorkout`, `.isGymVisitOnly`, `.countingDay(calendar:)`, `.kind: SessionOutcomeKind`, `.minutes: Int?` (home only today) | kinds: `showedUp, homeWorkout, easySkip, dayOff, skipped, rescheduled, missed, technicalFailure`; capped at 400 |
| Streak | `store.streak: StreakSnapshot` → `weeks`, `weeklyGoal`, `thisWeekSessionDays`, `isThisWeekKept`, `freezesAvailable`, `lastCompletedWeekWasFrozen`, `isLiveWeekPreArmed`, `liveWeekStart` | built by `StreakEngine.evaluate(...)`; refreshed by `store.refreshStreak()` |
| Week maths | `ProgressAnalytics.displayCalendar(_:)` (Monday-first), `StreakEngine.weekStart(containing:weekCalendar:)`, `StreakEngine.sessionDays(in:weekStarting:calendar:)`, `store.weeklyGoal(forWeekContaining:)` | UI-RULES §10: never `Calendar.current` week maths |
| Plan | `store.plan: MorningPlan` → `rhythm` (`bedtime`, `wakeTime`, `gymByTime`, `lockAlarmTime`, `flowMode`, `gapToGymMinutes`, `currentTimeToGymMinutes`), `rhythm(at:calendar:)`, `enabledSlots`, `nextOccurrence(after:calendar:) -> (slot, fireDate)?`, `oneOffAlarms` (reschedules), `effectiveTrainingDays(fallback: store.schedule)` (in `Models/ProgressPeriod.swift:304`), `nightLockWindow(at:calendar:)` (`Models/SleepSchedule.swift:345`), `hasBeenReviewed` | training days come only from `effectiveTrainingDays` |
| Night lock | `coordinator.windDown.isActive` | window's own truth |
| Freeze ahead | `store.streak.isLiveWeekPreArmed`, `store.frozenWeekEnd` | gym alarms paused that week |
| Setup | `HomeCardDeriver.setupChecklist` → 3 items: `apps` (`store.hasConfiguredBlockedApps && coordinator.shield.selectionCount > 0`), `alarm` (`plan.hasBeenReviewed && !plan.enabledSlots.isEmpty`), `gym` (`store.isAutomaticArrivalReady` = `primaryGym != nil`) | |
| Gym name | `store.primaryGym?.name` | |
| Install day / day N | `store.joinedAt` = `AppInstallDate.resolve(defaults)` (key `gymlock.installedAt`); `JourneySnapshot.dayNumber` = calendar days install→day **+1** (`Models/Share/ShareContextBuilder.swift` `journey(...)`) | reuse this definition for "day X of 66" |
| Risk banner | `coordinator.streakRiskBanner: StreakRiskBanner?` (`StreakRisk.banner`) | sits above the hero |
| Skip screen plan | `coordinator.skipScreen: SkipScreenPlan`, `SkipRules.chancesRemaining`, `coordinator.pendingReschedules` | |

---

## 3. The 19 moments: triggers, data, resolver

### 3.1 Current `HeroStage` → new moment

| `HeroStage` (today) | Today's trigger (`cardSection`) | New moment | Change |
|---|---|---|---|
| `.setupIncomplete(items:)` | step 4, `!setup.allSatisfied` | `setup` | same data; raise priority (see 3.3) |
| `.firstDay(alarm:)` | step 7, `log.outcomes.isEmpty` at any hour | `firstnight` | restrict to the night before the first planned day |
| `.night(bedtime:nextAlarm:)` | step 5, `hour >= 21 \|\| hour < 4` (clock guess) | `bedtime` | use `windDown.isActive` / `plan.nightLockWindow` |
| `.countdown(secondsRemaining:windowSeconds:)` | step 6, next alarm ≤ 2 h away | `countdown` | same source; window may extend (3.4) |
| `.committed(step:total:)` | session `alarmFired, awaitingDecision, snoozed, activationMission, preparing, quickWorkout*` | split: `wake` (pre-commit) / `ready` (committed) | |
| `.departed(step:total:nearGym:)` | `departed` / `approachingGym` | `commute` | |
| `.arrived(step:total:)` | session `.arrived` | `atgym` | must also come from `visits.openVisit` (session ends at Done) |
| `.verified(step:total:streak:)` | session `homeWorkoutVerified`/`completed`, or today's outcome `counts` | `verified` | |
| `.missed` | today's outcome `.missed`, or session `windowExpired`/`missed` | `stilltime` or `missed` (3.4) | |
| `.comeback` | yesterday's outcome `.missed`/`.technicalFailure` (`isComebackDay`) | `missed` ("MISSED YESTERDAY") | name collision: prototype `comeback` means a return after a break |
| `.restDay(nextDay:nextTime:)` | fallback, and session `cantToday`/`rescheduled` | `rest` | skipped day must not say "planned rest" |
| `.weekProgress`, `.pattern`, `.monthComplete`, `.startMonth`, `.midMonth`, `.latePattern` | step 8 aggregates | none | dropped from the hero; `monthStage` maths reusable for the done-flow month screen |
| none | | `paused`, `freshstart`, `weekkept`, `comeback`, `drift`, `halfway`, `automatic` | new detection, all derivable except where flagged |

Existing bug to not carry over: `weekStage` and `patternStage` use `calendar.dateInterval(of: .weekOfYear, for:)` with `Calendar.current` (Sunday-first in US locales), and `weekStage` takes the goal from `enabledSlots` days instead of `store.streak.weeklyGoal`.

### 3.2 Per-moment detection and scene data

`today` = `calendar.startOfDay(now)`. `planned(day)` = `store.plan.effectiveTrainingDays(fallback: store.schedule)` contains the weekday. `countedToday` = `store.log.outcome(on: now)?.counts == true`. `dayN` = install-based day number (§2). Weekday copy index `d` = Monday 0 … Sunday 6 via `displayCalendar`.

| # | Moment | Detect (real state) | Scene data and where it comes from | Gap / proposal |
|---|---|---|---|---|
| 1 | `setup` | `!HomeCardDeriver.setupChecklist(...).allSatisfied` | items done = `items.filter(\.isDone).count` of 3, labels from `ChecklistItem` | none |
| 2 | `firstnight` | `!store.log.outcomes.contains(where: \.counts)` **and** next `plan.nextOccurrence(after: now)` fires tomorrow **and** night (`windDown.isActive` or within `nightLockWindow` or after `rhythm.bedtime - X`) | alarm time `nextOccurrence.slot.alarmTime`, gym-by `slot.gymByTime(window: rhythm.gapToGymMinutes)`, gym `store.primaryGym?.name`, weekday of `fireDate` | none. Today's `firstDay` shows all day; restrict to the evening |
| 3 | `bedtime` | `coordinator.windDown.isActive` (night lock running) | wake / "apps back at" = `rhythm(at:).wakeTime`; next gym `nextOccurrence`; tomorrow planned? | **lock honesty**: FLOW Risk 1, the background DeviceActivity extension does not exist, the lock only applies when the app opens. Copy "apps locked until 06:30" must stay true (`isActive` is window truth, not shield truth; use `coordinator.shield.isShielded` / `selectionCount` for "locked" wording) |
| 4 | `wake` | session state ∈ `alarmFired, awaitingDecision, snoozed, runningLate` (and `activationMission`) | ring time `session.alarmTime` / `alarmFiredAt`; `flowMode` (`.wakeAndGo` vs go-later "time to go") | **hidden**: `isSessionLive` puts `MorningFlowView` over everything, so the hero never shows here. Only useful as preview/fallback; see Risk R1 |
| 5 | `countdown` | not live; `nextOccurrence(after: now)` fires today, `0 < s ≤ 2 h` (today's `countdownStage`) | seconds `fireDate - now`; window `7200`; gym-by time; gym name | **gap**: go-later gym day between wake and T-2 h matches nothing. Proposal: on a planned day, countdown from `rhythm.wakeTime` (or now) to `fireDate`, window = that span. Display only, no FLOW change |
| 6 | `ready` | session `preparing` (committed, not departed) | "out by" = no separate travel time exists. Use `session.deadline` / `arrivalTarget` ("gym by"), `remaining(at:)`, `elapsedFraction` | hidden behind the morning cover (R1). Prototype "Out by 06:45" needs travel split: not in data, drop or use gym-by |
| 7 | `commute` | session `departed` / `approachingGym` | `departedAt`, `arrivalTarget - now` | **no ETA / distance to gym** ("6 min out"). `SessionLocationMonitor` only has `distanceFromAnchor` (from start point). Minimal: "due by HH:MM" from `arrivalTarget`. Hidden behind cover anyway |
| 8 | `atgym` | `coordinator.visits.openVisit(now:calendar:)` non-nil, `!isCounted`, `!isHome` (also session `.arrived`) | seconds at gym = `presenceEnd(now:).timeIntervalSince(arrivedAt)`; to go = `1200 - that`; `timeCounts == false` (manual "I'm here", or home inside gym area) → no timer: "counts with Apple Health or a progress photo" (FLOW Flow 3) ; `pendingExitAt != nil` → paused clock | `GymVisitTracker` is not `@Observable`: Home redraws only because `store.log` changes. Needs a `TimelineView` and a trigger to call `coordinator.evaluateVisits()` at the 20-min mark (§4.1) |
| 9 | `verified` | `countedToday` (any proof) or session `homeWorkoutVerified` | proof `outcome.proof`, `workoutDetected`; this week `streak.thisWeekSessionDays` / `weeklyGoal`; position in week (below); streak `streak.weeks` | prototype hero copy is only "WORKOUT VERIFIED / Done."; detail lives in the done flow |
| 10 | `stilltime` | planned today, `!countedToday`, no open visit, not live, today's ring already passed or resolved (`outcome(on:).kind ∈ missed, skipped, rescheduled` or session window expired), **and** time left > 0 | evening time left: **no field exists**. Proposal: `lastStart = bedtimeToday - 30 min (travel home, FLOW night-lock rule) - 20 min (WorkoutRules.minimumMinutes) - rhythm.currentTimeToGymMinutes`; `secondsLeft = lastStart - now`. Or a pending reschedule later today (`coordinator.pendingReschedules`) → show `countdown` to it | prototype "#LEFT" needs this one derived number; "gym open until 22:00" has no data, drop |
| 11 | `rest` | `!planned(today)`, no counted outcome today, nothing live | next session `nextTrainingDayLabel`, `nextOccurrence`; streak safe = `!streak` at risk (`streakRiskBanner == nil`) | a **skipped** planned day currently falls here (`cantToday`→`.restDay`); "Planned rest protects the streak" would be false. Needs its own handling (Q3) |
| 12 | `paused` | `store.streak.isLiveWeekPreArmed` (planned freeze, alarms paused until `store.frozenWeekEnd`) | `frozenWeekEnd`, `streak.weeks`, `freezesAvailable` | auto-used freezes are only known after Sunday (`lastCompletedWeekWasFrozen`); that is a Monday state, use `freshstart` copy that does not say "lost" |
| 13 | `freshstart` | first day of the live week (or first open of it), `streak.thisWeekSessionDays == 0`; FLOW Flow 5: Monday after a reset says "new week," not "you lost" | last week's counted days `StreakEngine.sessionDays(in:weekStarting: liveWeekStart - 7d)`; this week goal `weeklyGoal`; "Week N" = weeks since `joinedAt` | "**4 sessions, 3h 12m**" needs minutes per session: **not stored** for gym visits (visits deleted after ~1 day; `SessionOutcome.minutes` is home-only). Proposal in §3.5 |
| 14 | `missed` | yesterday's outcome is a miss (today's `isComebackDay`: `.missed`/`.technicalFailure`; consider `.skipped`) and `!countedToday` | yesterday weekday, `SkipRules.chancesRemaining` (can the week still be made?) | also today-missed (`outcome(on: today).kind == .missed`, after the lock lifted): copy says "MISSED YESTERDAY"; use `stilltime` while time is left, else this |
| 15 | `weekkept` | `store.streak.isThisWeekKept` and `!countedToday` (the day it is kept, `verified` + done flow own it) | `thisWeekSessionDays`, `weeklyGoal`, `streak.weeks` | copy hard-codes "5 of 5": goal is 3 to 7 |
| 16 | `comeback` | return after a break: `streak.weeks == 0` with history, or last counted day ≥ 14 days ago (same gap as badge `second-wind`, `BadgeFacts.firstReturnAfterGap`), `!countedToday` | days away = today − last counted day; prior best `BadgeFacts.bestStreak` | "Bonus waiting / earns a bonus" (copy11/12): **no bonus mechanic exists**, drop |
| 17 | `drift` | weeks since install ∈ 4…6 (`(dayN-1)/7 + 1`), not counted today, week not kept, not a more specific moment | week number; this week count/goal | deterministic, no storage needed. FLOW Overview: "Half of new gym members drop off by week 6." |
| 18 | `halfway` | `dayN` reaches 33 (first app open on or after day 33, once) | `dayN`, counted days since install (`log.outcomes` counted, distinct days) | **new data**: "shown once" flag. Honesty gate: only if the user is active (`streak.weeks ≥ 1` or a counted day in the last 14 days), else skip. Q5 |
| 19 | `automatic` | `dayN ≥ 66`, once | same | same gate; 66-day claim is calendar days since install, not workouts |

**Scene numbers the prototype asks for, and their real source**

| Number | Source |
|---|---|
| countdown seconds | pre-alarm: `nextOccurrence.fireDate - now`; in session: `session.remaining(at:)` |
| seconds at gym | `openVisit.presenceEnd(now:) - arrivedAt` (only when `timeCounts`) |
| evening time left | derived (row 10), no stored field |
| setup items done | `setupChecklist` (0…3) |
| day of 66 | `calendar.dateComponents([.day], from: startOfDay(joinedAt), to: today).day + 1`, clamp 66 |
| sessions this week | `store.streak.thisWeekSessionDays` (= `MomentumField.countedCount`) |
| weekly target | `store.streak.weeklyGoal` (live week follows plan; past weeks `store.weeklyGoal(forWeekContaining:)`) |
| position in week | **data-driven** (prototype uses weekday): `first` if `thisWeekSessionDays == 1`; `last` if the counting day made `isThisWeekKept` true (`thisWeekSessionDays == weeklyGoal`); bonus (`> weeklyGoal`) → `last` copy variant "bonus day" per FLOW line; else `middle`. Same branches as `WorkoutDoneLine.countLine` |
| week of month | `first` if `day ≤ 7`, `last` if `day > daysInMonth - 7` (prototype `autoMonthPos`), else `middle`; use `displayCalendar` |
| week streak | `store.streak.weeks` |
| month sessions / target | counted days in month (`log` filtered by `countingDay`); target: **none exists** (today `monthStage` uses `perWeek * 4`). Proposal: sum of the saved weekly goals (`streakVault.weekGoals`, live goal for the rest) over weeks starting in the month |

### 3.3 Resolver (proposed, first match wins)

Pure function `HeroMomentResolver.resolve(store:coordinator:now:calendar:) -> HeroMoment` (testable, mirrors `HomeCardDeriver` signature). Rows marked (hidden) only ever render behind the morning cover.

| P | Moment | Condition | Why here |
|---|---|---|---|
| 1 | `wake` (hidden) | live session, state ∈ alarmFired/awaitingDecision/snoozed/runningLate/activationMission | today's step 1 |
| 2 | `ready` (hidden) | live, `preparing` / `quickWorkoutOffered` / `quickWorkoutActive` | |
| 3 | `commute` (hidden) | live, `departed` / `approachingGym` / `arrivalTrouble` | |
| 4 | `atgym` | session `.arrived`, or `visits.openVisit` not counted, not home | survives session end |
| 5 | `verified` | `countedToday` or session `homeWorkoutVerified` | outcome beats everything after it; two workouts count once (FLOW Flow 3) |
| 6 | `setup` | checklist incomplete | an unenforceable plan outranks clock states (existing comment) |
| 7 | `paused` | `streak.isLiveWeekPreArmed` | no alarms this week, nothing else is true |
| 8 | `firstnight` | no counted day ever, evening before first planned ring | |
| 9 | `bedtime` | `windDown.isActive` | night lock is the fact of the hour |
| 10 | `countdown` | planned ring later today within window (or a reschedule later today) | |
| 11 | `stilltime` | planned today, ring passed/resolved without a count, `secondsLeft > 0` | the day can still be saved |
| 12 | `automatic` | `dayN ≥ 66`, not yet shown, active gate | rare, once |
| 13 | `halfway` | `dayN ≥ 33`, not yet shown, active gate | rare, once |
| 14 | `comeback` | break ≥ 14 days or streak reset with history | |
| 15 | `missed` | yesterday (or today, after cutoff) a miss | "never twice" |
| 16 | `weekkept` | `isThisWeekKept` | |
| 17 | `freshstart` | first day(s) of week, 0 counted | |
| 18 | `drift` | weeks 4–6 since install, week not kept | |
| 19 | `rest` | not a planned day (or fallback) | |

Notes: `halfway`/`automatic` sit below every action moment so a milestone never hides a countdown or a running visit. `weekkept` sits above `freshstart` only for clarity; they cannot both be true (fresh week has 0 days).

### 3.4 What the resolver needs that the app does not have

| Missing | Minimal addition, consistent with FLOW |
|---|---|
| Clock-driven refresh of Home | wrap derivation in `TimelineView(.everyMinute)` for the hero only, or a `refreshKey` bumped by a minute timer (UI-RULES §10 `refreshKey` pattern); 1 s ticking only inside `countdown`/`atgym`/`stilltime` scenes |
| Evening time left | derived (row 10); no storage |
| Commute ETA | none; use `arrivalTarget` ("gym by") |
| "Shown once" for milestones and done flow | `UserDefaults` keys, e.g. `gymlock.home.milestone.halfway`, `gymlock.home.milestone.automatic`, `gymlock.done.lastShownDay` (pattern §6) |
| Per-session minutes (today, last session, week total, "from 38 min in week 1") | write gym minutes to the existing `SessionOutcome.minutes` when a visit settles (`GymVisit.leftAt` known, or `closesAt` reached: `presenceEnd - arrivedAt`), or Health duration when `proof == .health`. Additive field already decoded; no rule change. Until then those numbers are absent, never invented (UI-RULES §11) |
| Month target | none in FLOW. Derive from weekly goals (above). A user "pick your target" screen (prototype month screen, first week) is a **new rule**: needs Rishi (FLOW rule 5) |
| Bonus for comeback | none; drop the copy |

---

## 4. The done / verification moment

### 4.1 How the app learns a workout counts

Single place: `GymVisitTracker.evaluate(now:store:photos:calendar:) -> [GymVisit]` (returns newly counted). It calls `WorkoutRules.proof(...)` and `markCounted(...)` → `store.log` updated (`MomentumLog.markCounted(outcomeID:proof:)` or a new `SessionOutcome` for alarm-less visits) and `store.record(.workoutCounted, ...)`. Wrapped by `coordinator.evaluateVisits(now:extraPhotos:)`.

Callers of `evaluateVisits()`:

| Trigger | Where | Foreground? |
|---|---|---|
| 1 s ticker | `tick()` via `startTicking()` | **only while `session != nil`**; `tick` cancels the ticker when the session is gone |
| Region exit/entry | `noteGymExit` / `noteGymEntry` (wired in `wireGymEvents`) | background-capable |
| Health workout | `attach(_ workout:)` from `health.startObserving` | background delivery possible |
| Foreground | `applicationDidBecomeActive()` | yes |
| Launch | `attach(to:)` | yes |
| Visit start | `beginVisit(...)` and `fetchWorkouts` | |
| Photo | `evaluateVisits(extraPhotos:)` | |

Timeline of a normal gym morning:
1. Arrival dwell → `confirmArrival(manual:at:)`: `session.state = .arrived`, outcome `.showedUp` with `proof: .unproven`, shield released, `Haptics.commit()`, `beginVisit` (sends "you're in. 20 minutes and today counts.").
2. `MorningFlowView` shows `.gymSuccess` → `GymArrivedView` ("you made it."). Done → `acknowledgeResult()` → `endSession()`. **Ticker stops.**
3. Minute 20: nothing evaluates in the foreground unless a region/Health event or a foreground happens. The `verified` state can appear late.
4. Background: `syncNotices` pre-schedules the workout-done line at `GymVisit.doneNoticeDate()` (30 min or on leaving, `id: gymlock.done.<day>.<visit>`), text from `WorkoutDoneLine.pick(...)`. Tap → `NotificationRoute.workoutDone(day:)` → `coordinator.openPendingSkipScreenIfNeeded()` → `openProgressSpotlight(for:)` → `requestedTab = .progress` + `pendingSpotlightDay` → `RootTabView` arms `ProgressSpotlightModel`.
5. Home workout: `finishQuickWorkout` → `.homeWorkoutAwaitingProof` (`HomeWorkoutProofView`) → when it counts, `settleHomeWorkoutState` sets `.homeWorkoutVerified` + `Haptics.commit()` → route `.momentumSaved` → `MomentumSavedView`.

Minimal fix for foreground detection: keep the ticker (or a 15–30 s timer) alive while `visits.openVisit(now:calendar:) != nil`; or have the `atgym` scene's `TimelineView` call `coordinator.evaluateVisits()` once when `presenceEnd - arrivedAt` crosses 1200 s.

Detecting "just verified" for the done flow: observe `store.log` and compare today's `outcome(on:).counts` false → true (or `evaluateVisits` returning a non-empty array). Gate once per counting day.

### 4.2 Existing done/success screens (Views/Morning)

| Screen | Route | When | Haptics |
|---|---|---|---|
| `ConfirmingArrivalView` | `.confirmingArrival` | in gym region, dwell running | `Haptics.tap()` |
| `ArrivalTroubleView` | `.arrivalTrouble` | GPS failed | |
| `GymArrivedView` (`ArrivalViews.swift:194`) | `.gymSuccess` | **arrival**, not verification | `confirmArrival` fires `Haptics.commit()`; share `Haptics.tap()` |
| `MomentumSavedView` | `.momentumSaved` | home workout verified | `Haptics.commit()` in `settleHomeWorkoutState` |
| `HomeWorkoutProofView` | `.homeWorkoutProof` | timer done, awaiting Health/photo | |
| `DepartedView`, `GymWindowView`, `AlarmFiredView`, `ActivationMissionView`, `StillGettingReadyView` (sheet), `PlansChangedView`, `QuickWorkoutView`, `CantTodayView` | | | |

There is **no in-app screen at gym verification**. The only signal is the notification + Progress spotlight.

### 4.3 Where to present the done flow

Recommended: `RootTabView` as a `.fullScreenCover(item:)` driven by a single observable value (e.g. `coordinator.pendingDoneFlow: DoneFlowRequest?`, or a small `@Observable DoneFlowController` owned beside `intro`). Reasons:
- `ContentView` already hosts the morning `.fullScreenCover`; a second cover on the same view cannot show while the first is up.
- `RootTabView` already arbitrates the other overlays (spotlight, setup cover, sheets, celebration).

Gate before presenting: `!coordinator.isSessionLive`, `!launchCover.isHoldingApp`, `scenePhase == .active`, `!isRunningSetup`, no sheet up (`isAskingToAddGymDay`, `isAskingForWakeTime`), `!spotlight.isActive`. UI-RULES §6.9: presenting in the same runloop as a dismissal is dropped, defer ~120 ms.

Home workouts: the done flow would duplicate `MomentumSavedView` (inside `MorningFlowView`). Either replace that route's screen with the done flow (UI change only) or start the flow after its Done. Home workouts are not gym visits; scenes must not show gym name or time at the gym (`MomentumLog` doc comment: the app "is not allowed to blur that").

### 4.4 Conflicts with FLOW.md (stop-and-ask items)

| # | Conflict | FLOW text |
|---|---|---|
| F1 | Done flow on notification tap replaces/precedes the Progress spotlight | Flow 3: "tap ──► PROGRESS SPOTLIGHT"; spotlight "shown once per workout day, only from that notification". Needs a decision: done flow only on in-app detection, or done flow then spotlight |
| F2 | Month "pick your target" (first week of month) | FLOW has only the weekly goal ("the alarm screen's gym days are the one setting", item 19a). A month target is a new rule |
| F3 | Late-night visit inside sleep hours | night lock stays on, line is "workout counted. it cost you sleep though..." A full celebratory flow at 23:30 contradicts the intent; suggest a reduced flow or none |
| F4 | "WORKOUT VERIFIED" for manual "I'm here" + photo, and home workouts | Flow 3/4 allow it (sticker included); fine, but proof wording must match `WorkoutProof` |
| F5 | Item 11 (workout-done notification + spotlight) is still marked **Change** (not built) in "Everything to Change", though the code sends it (`syncNotices`) and routes it. Status marker is stale or partial; confirm before building on it |

---

## 5. Badge system and collisions

### 5.1 How it works today

- Facts: `BadgeEngine.facts(log:plan:schedule:vault:now:calendar:) -> BadgeFacts` (`Models/Badges/BadgeEngine.swift`); rules `BadgeRules.states(for:)` → `[String: BadgeState]`.
- Store: `BadgeStore.refresh(store:)` merges into `records` (`gymlock.badges.records`, `Record(unlockedOn:seen:)`). `unseenEarned`, `headlineReveal(among:)` (highest tier wins), `markSeen(_:)`.
- Catalog (`Views/Progress/Badges/BadgeCatalog.swift`): streak ladder 1/2/4/8/12/26/52/78/104/156 weeks; workout days 3/10/25/50/100; achievements `first-proof, home-hero, health-synced, comeback, second-wind, overachiever, recovery, sunrise, night-owl, gym-regular, home-saver, clean-run`. **No 66-day badge.**
- Refresh timing: only `ProgressTabView` `.task(id: badgeKey) { badges.refresh(store: store) }`. `BadgeStore` is local to Progress.
- Presentation: only when the user opens `BadgesScreen` (sheet from the Progress tile). `reveal()` waits 650 ms (300 ms Reduce Motion), `markSeen` first, then `request = BadgeRankUpRequest(unlocking:)` → `.badgeRankUp($request) { land($0) }` (`BadgeRankUpPresenter`) → `RankUpView` (Canvas + `TimelineView(.animation)`, 30 fps frame units, tap allowed after `RankUpTiming.tapReady`) → `BadgeFlightView` 0.72 s flight into the slot → `BadgeHaptics.shared.playLand()` → pops staggered 0.12 + 0.07 s. Reduce Motion: `Haptics.commit()` + 0.3 s crossfade, no rank-up.
- Haptics: `BadgeHaptics.shared.playRankUp(tier:rate:)` (CHHapticEngine, light tap f4, charge rumble f14–40, 4 spin ticks, impact f60 + rumble, slam f76, chip f92), fallback heavy impact. `playLand()` soft double tap.
- `RankUpView` uses `GymLockFonts` (bundled fonts, `.custom(GymLockFonts.semiBold...)`): an existing exception to UI-RULES §3 "No bundled fonts anywhere". Do not copy it into the port.

### 5.2 Collision points with a done flow / hero celebration

| # | Collision | Detail | Mitigation |
|---|---|---|---|
| C1 | Weekly kept celebration on Home | `StreakIntroController.presentEarnedCelebrationIfNeeded` auto-expands the streak card once per kept week (`gymlock.streak.lastCelebratedWeekStart`), `Haptics.commit()` at expand, ~2.8 s. Triggered by `store.streak` change, tab switch to Home, scene active, launch cover lifting. Its only cover-guard is `isSuspended` (set for setup only; **not** for `MorningFlowView`) | set `intro.isSuspended = true` while the done flow is up; when the flow's `last` (week complete) plays, write `lastCelebratedWeekStart` so the card does not replay, or deliberately hand over to it after dismissal. Pick one |
| C2 | Home haptics firing under the cover | Home is mounted permanently. `TodayHomeView.onChange(of: cards.pathStep)` plays `Haptics.commit()`/`tap()`; `MomentumFlameProgress` `.onChange(of: Snapshot)` plays `commit()` when the week completes, `tap()` otherwise. Both fire the moment `store.log` changes, i.e. exactly when the done flow opens | gate those on "no done flow / cover up", or replay them after (UI-RULES §9: one commit per event) |
| C3 | Progress spotlight | notification tap → Progress + dim spotlight (F1) | order explicitly |
| C4 | Badge earned by the same workout | e.g. `first-proof`, `showed-up` (3 days), `locked-in` (4 weeks), `overachiever`, `home-saver`. Reveal waits for the user to open Badges; the done flow can't know without `BadgeStore.refresh` (store lives in Progress) | if the flow mentions it, lift `BadgeStore` to app level or compute `BadgeEngine.facts` in the flow; never auto-chain the rank-up (frequency gate) |
| C5 | Haptic engines | `BadgeHaptics`, `IntroHaptics`, `Haptics.glassBreak` engine and a new done-flow engine are separate `CHHapticEngine`s; nothing stops one when another starts | one shared engine or stop others on start |
| C6 | `GymArrivedView` commit at arrival + done flow commit 20 min later | two success moments per visit | allowed (two events) but keep the done flow's peak distinct |
| C7 | Risk banner | `StreakRiskBannerView` above the hero; stops when the week is safe (FLOW Flow 6) | no clash; hero must not repeat "1 workout keeps your N-week streak" |

---

## 6. Settings: "Card style: Ridge / Matrix"

**Where**: Profile → `Preferences` row (`ProfileView.shortcuts`, `matchedTransitionSource(id: "preferences")`) → `PreferencesView` (`.fullScreenCover` + `.navigationTransition(.zoom(sourceID: "preferences"...))`) → `PreferencesHome`. Today it has one section: `PreferencesEyebrow(text: "GYM ROUTINE")` + `NavigationLink { TimeToGymEditor() }` row styled `AlarmGlassCardButtonStyle(verticalPadding: 6)` + `PreferencesFootnote`. Add a second section (e.g. `PreferencesEyebrow(text: "HOME")`) with a "Card style" row pushing a picker subpage (`AlarmSubpage(title:)`, `AlarmGroupCard`, `AlarmSectionHeader`).

**Precedent to copy**: `Models/AlarmScreenStyle.swift` (`enum AlarmScreenStyle: String, Codable, CaseIterable, Identifiable` with lowercase `label`, `mood`, `accessibilityDescription`; `AlarmScreenDraft` working copy committed on Done) and `Views/Morning/AlarmScreenPickerView.swift` (`AlarmScreenPreviewCard`, `Haptics.prepareSelection()` on appear, `Haptics.selection()` per change, `Haptics.commit()` on save). A `HeroCardStyle { ridge, matrix }` should mirror it; preview cards can render the real `HeroCardView` at small scale.

**Storage pattern**: no `@AppStorage` anywhere; no SwiftData. All persistence is `UserDefaults` with `"gymlock.<area>.<name>"` keys:
- `AppStore.Key` enum (`gymlock.userName`, `.stage`, `.schedule`, `.profile`, `.morningPlan`, `.momentumLog`, `.primaryGym`, `.sessionEvents`, `.blockedAppsConfigured`, `.streakVault`), JSON via `persist(_:forKey:)`, properties with `didSet`.
- Per-type keys elsewhere: `GymSessionCoordinator.Key` (`gymlock.activeSession`, `gymlock.progress.pendingSpotlightDay`, `gymlock.streak.sawMakeUpDay`, `gymlock.streak.atRiskFireDate`, ...), `GymVisitTracker.Key` (`gymlock.gymVisits`, `gymlock.recentWorkouts`, `gymlock.lastWorkoutDoneLine`), `BadgeStore.recordsKey`, `StreakIntroController.lastCelebratedWeekStartKey`.
- Alarm screen style is stored inside `MorningPlan` (`alarmScreenStyle`, Codable with `decodeIfPresent` default). A hero style is not plan data: recommend `AppStore` property `heroCardStyle` with `Key.heroCardStyle = "gymlock.home.cardStyle"` (raw string), default `.ridge` (or as decided). Avoid `gymlock.home.lastSeenStreak` (retired key, removed on sight by `StreakIntroController.init`).

**UI-RULES constraints for the row/picker**: row title style "Time to Gym" (SF 17 semibold), values lowercase ("ridge", "matrix", as the Alarm screen does); 44 pt targets; `accessibilityLabel/Value/Hint`; `.isSelected` trait on the chosen preview; glass only on floating chrome (§8), cards are content (no glass on previews); `Haptics.selection()` only when the choice changes, never during a drag (§9); one coral accent (§1); `UserDefaults` for small metadata (§10). Reduce Motion: preview crossfade 180–220 ms.

---

## 7. Haptics: utilities and conventions

`Utilities/Haptics.swift` (`enum Haptics`):

| Call | Generator | UI-RULES §9 use |
|---|---|---|
| `tap(intensity: = 1)` | light impact | small deliberate action |
| `selection()` / `prepareSelection()` | kept-alive `UISelectionFeedbackGenerator` | selection actually changed, once, never during drag |
| `press(intensity: = 0.5)` / `preparePress()` | kept-alive soft impact | finger-down give |
| `soft()` | soft impact | press-down, explanatory tap |
| `medium()` | medium impact | starting something |
| `boundary()` | rigid 0.85 | hitting a limit once |
| `commit()` | `UINotificationFeedbackGenerator .success` | **the** success moment, never twice per event |
| `preview(_ AlarmHaptic)` / `stopPreview()` | Core Haptics | alarm vibration preview |
| `prepareGlassBreak()` / `glassBreak()` | shared `CHHapticEngine` (`runningEngine()`), fallback on impact generators | unlock moment only |

Choreographed Core Haptics precedents (closest to the done flow's per-screen timelines and the "tap N times" climax):
- `BadgeHaptics.shared` (`Views/Progress/Badges/BadgeHaptics.swift`): timeline in 30 fps frames, intensity scaled by tier, engine with `resetHandler`, fallback.
- `IntroHaptics.shared` (`Views/Onboarding/Intro/IntroHaptics.swift`): `tap(level:)` escalating per tap, `chainBreak()` on the final tap, `land()`, `slam()`. Direct model for the climax.

Prototype haptic schedules (`hero12/screens12.ts` `CFG_R` / `CFG_M`) fire up to 13 `light` impacts per screen plus `heavy` + `success` together. Under §9 (`commit()` "never twice for one event") the success notification may appear once in the whole flow (verified screen or the climax seal, not both); counting ticks should be a Core Haptics pattern, not repeated `tap()` calls.

---

## 8. HeroCard / HeroPreviewMatrix today, and the copy

### 8.1 What `HeroCardView` does now

- Fixed geometry: `GeometryReader` → `HeroMetrics(width: min(w, 480))`, `.aspectRatio(2.05, .fit)`, white `Theme.surface`, 24 radius, 1 pt `Theme.border`, shadow `0.05 / 14 / y6` (the `warmCard` recipe, hand-rolled).
- Five layouts: `ImageHero` (copy column `leftFraction 0.58` over `GymLockHeroImageBlend` photo, optional bottom view, optional `GymLockCircularCTA`), `RingHero` (`copyFraction 0.46` + `GymLockProgressRing`), `CountdownHero` (`TimelineView` 1 s, `HH:MM:SS`, static `anchoredTarget` so re-renders do not reset), `SetupHero` (`GymLockChecklist`), `PatternHero` (`GymLockMiniBarChart`), `ComebackHero` (`GymLockNumberedSteps`).
- Transition: `.animation(.easeInOut(duration: 0.3), value: stage)` on the whole content; headlines `.contentTransition(.numericText())`.
- Copy is **hard-coded string literals per `HeroStage` case** inside `HeroCardView.content(_:)`: `eyebrow` (uppercase, `tracking eyebrowSize * 0.14`, `inkSecondary`), `headline: [String]` (one `Text` per line, SF Rounded bold, `lineLimit(1)`, `minimumScaleFactor 0.6`), `support` (SF medium, 2 lines, 0.75). Values come from the stage's associated values (times via `TimeOfDay.displayString`). No localisation table, no variants, no weekday rotation.
- `onCTA` is never passed by `TodayHomeView`, so no CTA ever renders.
- Existing UI-RULES slips in this file: em-dashes in UI strings (`"Apps unlocked — nice work"`, `PatternHero` fallback `"—"`, and `"Today reset — tomorrow is ready"` in `HomeStage.swift`); Title Case headlines ("Train now", "Get ready") vs §1/§11 lowercase chrome; a hard-coded `"4 steps to a stronger you"`.

### 8.2 `HeroPreviewMatrix.swift`

`#Preview`-only file. `StageCanvas(stage:protection:next:path:)` renders `HeroCardView` + `MiniCardsRow` on `Theme.canvas`; 19 previews (`"1 · First day"` … `"18 · Late month pattern"`, `"Rest day"`) with sample data (`6:40 AM`, 3 apps). Replace with a 19 moments × 7 weekdays × 2 styles matrix (plus Reduce Motion and a long-locale variant), fixtures behind `#if DEBUG` (§10).

### 8.3 Replace vs keep

| Replace | Keep |
|---|---|
| `HeroStage` enum and `cardSection` precedence | `HomeCardModel` shape (hero + three mini cards + momentum) |
| All private hero layouts and the photo blend | `HeroMetrics` proportions (card size must not change: prototype `CARD_H` "unchanged: the app's hero card") |
| Inline copy | `MiniCardsRow` and its derivation; prototype `app12.tsx` drives `PathMini` per moment (`'1 / 4' awake`, `'3 / 4' stay 20 min`, `'Rest' no steps today`, `'Paused' resume anytime`), a small mapping update |
| Aggregate stages (week/pattern/month) | `deduplicated` / `heroClaim` (update cases so Next never repeats the hero's time) |
| Hero image assets | `GymLockChecklist` (setup), ring if Matrix needs none |

### 8.4 Prototype copy: `copy12.ts` vs `copy11.ts`

| | `hero11/copy11.ts` | `hero12/copy12.ts` |
|---|---|---|
| Type | `C11 = {eyebrow, title, sub, note?}`, `Pos = first/middle/last` | imports `C11`, `Pos` from copy11 |
| Card copy | `STATE_COPY: Record<S4, C11[5]>`, rotated by `dayVariant()` = day-of-year % 5 | `STATE12: Record<S4, W7>`, **7 variants indexed by weekday** (Mon 0), each weekday a "world" |
| Done copy | `DONE_COPY: Record<Pos, C11[5]>` | `DONE12: Record<Pos, W7>` (pos × weekday) |
| Month layer | none | `cardCopy(s, day, pos, monthPos, cal)` overrides `freshstart`, `verified`, `weekkept` in the first/last week of a month; `monthScreen(mp, pos, cal)` for the done-flow month screen |
| Still used from 11 | | `POS_WEEK` (week screen title/sub/research, end-screen sub/button), `DONE_DATA`, `DAYS`, `MINS`, `tapsFor` via `days12.ts` / `story12.tsx`; `tapsFor12(day,pos)` = 7 if Sunday or `last`, else 5 |
| `note` | Ridge brush note | Ridge brush note, names the day's world |

Conclusion: copy12 is canonical; port copy11's `POS_WEEK` strings too (they are the week/end screens). Data placeholders (`DONE_DATA`, `MINS`, `monthCal` fake calendar) are fixtures only.

**How it maps onto the current card**: `eyebrow` → eyebrow; `title` → headline (single string; current card takes `[String]` lines); `sub` → support, with `**bold**` spans rendered as a heavier weight of the same face (allowed, §3) via `AttributedString` / concatenated `Text`; `note` → Ridge-only annotation. Title tokens map to computed values: `#SETUP` → "N of 3 ready" (`SetupHero`), `#CLOCK` → countdown clock, `#LIVE` → mm:ss at gym, `#LEFT` → evening h mm. Keep copy in one Swift table keyed `(HeroMoment, weekdayIndex)` with a formatter that injects real values; never ship literal sample values.

**Copy that cannot ship as written** (UI-RULES §1, §11, FLOW honesty):

| Issue | Examples |
|---|---|
| Hard-coded data | "Iron Works", "07:00", "06:30", "Out by 06:45", "6 min out", "5 of 5", "Five for five", "Week 8", "Day 33", "13 sessions", "+6:10", "38 min in week 1", "Week streak: 6", "3h 12m" |
| No data behind it | "The gym is open until 22:00", "Bonus waiting when you check in" / "earns a bonus", commute ETA |
| Precise research figures | "91%", "33%", "14%", Friday "58% of Monday" (§11 bans invented precise figures; these are cited in `days12.ts`/FLOW Sources but the rule needs a call, Q6) |
| Case | Title Case titles ("Done.", "Rise.") vs §1 "Copy is lowercase and terse" in chrome; eyebrows uppercase are fine (§3 eyebrow role) |
| Fonts | Ridge note uses `MARKER` = Permanent Marker (`hero11/fonts/permanent-marker-latin-400-normal.woff2`), titles use a `DISPLAY` web font: §3 "No bundled fonts anywhere", §12 "No brush/script/handwriting fonts". Use New York italic (editorial annotation role) and SF Pro Display black condensed / SF Rounded |
| Goal assumptions | "Five planned", "Two more", "4 for 5": goal is 3–7 (FLOW item 19a) |
| Banned words / em-dash | none found in copy11/copy12 (checked) |

FLOW-quoted lines the port must keep verbatim where they appear (notifications, not the card): "you're in. 20 minutes and today counts.", the `WorkoutDoneLine.countLine` lines, "you came back. that's the hardest one.", "you left after N min. 20 minutes makes it count.", "workout counted. it cost you sleep though. aim to be home by HH:MM."

---

## 9. UI-RULES the port must obey (brief quotes)

| Area | Rule (quoted) | Hits in this port |
|---|---|---|
| Mode | Home and the morning flow are "**Operate**"; "Do not design an Operate screen like a landing page." | hero card is Operate; done flow is the rare celebratory tier |
| Accent | "One accent per screen, and it is coral." | Ridge/Matrix palettes must not add a second accent; Matrix lit dots coral at most |
| Colour | "Never invent a colour." "Never pure `#000000` or `#FFFFFF` as a content colour." Dark surfaces: `#0B0B0C` canvases, text white 100/80/55% | painterly Ridge palettes and the done flow's night/dark scenes need token sign-off |
| Gradients | Anti-slop: "No gradients except a flat dark canvas; no glows, textures, metal, grunge" ; §4 "No glow, no neon" | **direct conflict** with Ridge (painterly washes) and glowing dots; needs an explicit brief override (§13 "The brief wins... but say so out loud") |
| Radius | "Cards 24, controls 16, stat tiles 20, mini cards 18. Do not introduce a fourth value" | hero stays 24 |
| Type | System faces only, "**No bundled fonts anywhere.**" Numbers that tick: SF Rounded, `.monospacedDigit()`. Headlines max 2 lines. Data text gets `lineLimit` + `minimumScaleFactor (0.6–0.85)`. Test `7`, `127`, `0`, "Donnerstag" | countdown, at-gym timer, 66-day count |
| Eyebrows | "at most one eyebrow label per three sections on a screen" | hero eyebrow already counts; done-flow screens must ration |
| Frequency gate | "100+ times a day: None. Ever." "Tens of times a day: Near-imperceptible only." "Rare / first-time (... arrival success, milestone): Delight budget available" | hero is seen many times a day: entrance once, no idle motion; done flow is rare |
| Duration | "Hard ceiling: 300 ms for anything in the Operate layer." "The morning flow's celebratory moments are the exception." | hero transitions ≤ 300 ms; prototype 1.5–2.4 s per done screen is fine only in the done flow |
| Looping | "Elements may animate in once. **Nothing loops.** No pulsing buttons, no breathing glows, no perpetual shimmer." | ambient fireflies/tide/clouds/twinkling dots on the hero are banned; a ticking countdown/at-gym clock is state indication, allowed. Existing `NextTaskBreathe` in `MomentumFlameProgress` is already a loop |
| Curves | tokens `Theme.settle` (0.55 s), `Theme.stateChange` (0.18 s, "never scale"), `Theme.pageTurn`, `Theme.celestial` (0.95 s); "Never use `easeIn` on UI." "Never from `scale(0)`" (start 0.94–0.97) | |
| Bounce | "Bounce must be earned." Never on a state change the user did not push | climax taps may bounce (user supplied the energy); screen entrances may not |
| Stagger | "30–80 ms between siblings ... never stagger more than ~6 items" | done-flow stat rows, week dots (7) |
| Reduce Motion | "Honour `@Environment(\.accessibilityReduceMotion)` everywhere. Reduce Motion means gentler, not absent. Swap springs and offsets for a 180–220 ms opacity crossfade. The outcome must be identical" | climax "tap N times" must still be completable; prototype checks `prefers-reduced-motion`, port must use the environment value |
| Interruptibility | "Never lock input during a transition." | done-flow "tap to continue" must work mid-animation (prototype gates on `settle`) |
| Taps | "Highlight on touch-down, commit on touch-up", 44 pt targets | climax tap target is the whole scene |
| Haptics | table in §7; `commit()` "**The** success moment ... Never twice for one event." `selection()` "Never during a drag." | |
| Rendered images | "Anything rendered to an image (share frames) must render its settled end state — pass an `isAnimated: false` flag" ; "Glass and materials never appear inside anything rendered by `ImageRenderer`" | if the done flow offers share |
| Conventions | `@Observable @MainActor final class`; derived models pure with `now:`/`calendar:`; "Never compute a derived model inside `body`"; Monday-first weeks via `ProgressAnalytics.displayCalendar()`; training days only from `plan.effectiveTrainingDays(fallback:)`; small metadata in `UserDefaults`; Swift Testing for pure logic; fixtures behind `#if DEBUG` | resolver, copy formatter, position-in-week, week-of-month, day-of-66 all need tests |
| Copy | lowercase, terse; banned words list; "No em-dashes (`—`) in UI strings"; "No emoji in chrome"; "Never fabricate ... If the data is missing, the element is absent."; "Forward-looking, never a verdict." | §8.4 table |
| States | Loading / Empty / Error / Pressed all defined; "Zeros are not an empty state." | first week (0 sessions), Health denied, no gym selected |
| Scope | "Do not widen scope." | |

---

## 10. Risks and open questions

**Risks**

- R1. `wake`, `ready`, `commute` (and in-session `countdown`, `atgym` before Done) are never visible on Home: any live session presents `MorningFlowView` full screen (`ContentView` `isMorningLive`). Building 3 × 7 × 2 scenes for them only pays off if they are reused inside the morning flow screens.
- R2. Foreground verification lag: the ticker dies with the session, so the 20-minute count (and the done flow) waits for a region/Health event or a foreground (§4.1).
- R3. `GymVisitTracker` is not observable; the `atgym` scene must poll by `TimelineView` and the resolver must read `visits` at derivation time.
- R4. Ridge's painterly gradients/glow and the marker font conflict with UI-RULES §3, §4, §12. Needs an explicit, recorded exception or a restyle.
- R5. Celebration pile-up on the day a week is kept: done flow + `StreakIntroController` auto-card + `MomentumFlameProgress` commit + path commit, all off one `store.log` write (C1, C2).
- R6. Minutes-based numbers (today's time, week total, "from 38 min in week 1", freshstart "3h 12m") have no persisted source; until `SessionOutcome.minutes` is written for gym visits they must be omitted.
- R7. Day-66 claims based on install date can be untrue for a lapsed user; needs an activity gate.
- R8. Existing Calendar.current week maths in `HomeCardDeriver.weekStage/patternStage` must not be copied into the new resolver.
- R9. Performance: Home is permanently mounted; a continuously animating Canvas scene behind other tabs must pause when `isVisible == false` or Reduce Motion is on.

**Open questions (for Rishi)**

- Q1 (F1). On the workout-done notification tap: done flow, then Progress spotlight? Or done flow only for in-app detection and the spotlight stays the notification's destination?
- Q2 (F2). Month target: derive from weekly goals (no picker), or add the "pick your target" screen as a new FLOW rule?
- Q3. Which moment for a planned day the user **skipped** or rescheduled (today it becomes `.restDay`)? Proposal: `stilltime` while time remains, else a skip-aware `rest` variant that does not say "planned rest".
- Q4 (F3). Done flow for a visit inside sleep hours: full, reduced, or none?
- Q5. Day count for 33/66: calendar days since install (matches `JourneySnapshot.dayNumber`), or counted workout days? And the activity gate.
- Q6. Are cited research percentages (33%, 14%, 91%) allowed in chrome under §11 "no invented precise figures"?
- Q7. Default card style (Ridge or Matrix), and should the picker live in Preferences (recommended) or on the hero card itself?
- Q8. Should a home workout get the full done flow (replacing `MomentumSavedView`) or a variant without gym-specific screens?
- Q9. Does the done flow surface a badge earned by the same workout, given `BadgeStore` lives only in Progress?
